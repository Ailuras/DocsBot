"""DocsBot SQLite data layer — one db.sqlite per project."""

from __future__ import annotations

import datetime
import json
import re
import sqlite3
from pathlib import Path
from typing import Any

DB_FILENAME = "db.sqlite"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS buckets (
    p     TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    descr TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS tasks (
    id          TEXT PRIMARY KEY,
    bucket      TEXT NOT NULL DEFAULT 'P0',
    module      TEXT NOT NULL DEFAULT '',
    title       TEXT NOT NULL,
    size        TEXT NOT NULL DEFAULT 'M',
    effort      TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    output      TEXT NOT NULL DEFAULT '',
    acceptance  TEXT NOT NULL DEFAULT '',
    note        TEXT NOT NULL DEFAULT '',
    serves      TEXT NOT NULL DEFAULT '[]',
    status      TEXT NOT NULL DEFAULT 'todo',
    date_added  TEXT NOT NULL,
    updated_at  TEXT,
    tags        TEXT NOT NULL DEFAULT '[]',
    priority    TEXT NOT NULL DEFAULT 'medium'
);
CREATE TABLE IF NOT EXISTS research (
    id         TEXT PRIMARY KEY,
    codename   TEXT NOT NULL DEFAULT '',
    title      TEXT NOT NULL,
    kind       TEXT NOT NULL DEFAULT 'ANALYSIS',
    module     TEXT NOT NULL DEFAULT '',
    hypothesis TEXT NOT NULL DEFAULT '',
    body       TEXT NOT NULL DEFAULT '[]',
    depends_on TEXT NOT NULL DEFAULT '[]',
    status     TEXT NOT NULL DEFAULT 'open',
    date_added TEXT NOT NULL,
    updated_at TEXT
);
CREATE TABLE IF NOT EXISTS notes (
    slug      TEXT PRIMARY KEY,
    title     TEXT NOT NULL,
    date      TEXT NOT NULL,
    body_html TEXT NOT NULL DEFAULT '',
    tags      TEXT NOT NULL DEFAULT '[]',
    excerpt   TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS weeks (
    week_id    TEXT PRIMARY KEY,
    date_start TEXT NOT NULL DEFAULT '',
    goal_title TEXT NOT NULL DEFAULT '',
    goal_body  TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS features (
    id          TEXT PRIMARY KEY,
    week_id     TEXT NOT NULL DEFAULT '',
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'todo',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    date_added  TEXT NOT NULL DEFAULT ''
);
"""

_DEFAULT_BUCKETS = [
    ("P0", "CORRECTNESS", "Items affecting result soundness."),
    ("P1", "VALIDATION",  "Testing, fixtures, and verification scripts."),
    ("P2", "EVIDENCE",    "Logging, metrics, and reproducibility."),
    ("P3", "PIPELINE",    "CLI, wrappers, batch, and scheduling."),
    ("P4", "FEATURES",    "Research prototypes and recognizers."),
    ("P5", "NOTES",       "Documentation and maintenance."),
]

# Columns a client may update, per table. Field names in UPDATE statements are
# interpolated into SQL, so they must be validated against these whitelists to
# prevent SQL injection via attacker-controlled JSON keys.
_TASK_COLUMNS = {
    "bucket", "module", "title", "size", "effort", "description", "output",
    "acceptance", "note", "serves", "status", "date_added", "tags", "priority",
}
_RESEARCH_COLUMNS = {
    "codename", "title", "kind", "module", "hypothesis", "body", "depends_on",
    "status", "date_added",
}
_NOTE_COLUMNS = {"title", "date", "body_html", "tags", "excerpt"}
_WEEK_COLUMNS = {"date_start", "goal_title", "goal_body"}
_FEATURE_COLUMNS = {"week_id", "title", "description", "status", "sort_order", "date_added"}


def _migrate(conn: sqlite3.Connection) -> None:
    """Apply incremental schema changes to existing databases.

    Safe to run before the base schema exists (e.g. on a brand-new DB):
    column migrations are skipped when the target table is not present yet,
    and create() applies the full schema afterwards.
    """
    table_info = conn.execute("PRAGMA table_info(tasks)").fetchall()
    if table_info:
        existing_cols = {row[1] for row in table_info}
        for col, typedef in [("tags", "TEXT NOT NULL DEFAULT '[]'"),
                             ("priority", "TEXT NOT NULL DEFAULT 'medium'")]:
            if col not in existing_cols:
                conn.execute(f"ALTER TABLE tasks ADD COLUMN {col} {typedef}")
        conn.commit()
    # Add tables introduced after the initial release. Idempotent, and needed
    # when opening an older DB (open() does not re-run the full base schema).
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS weeks (
        week_id    TEXT PRIMARY KEY,
        date_start TEXT NOT NULL DEFAULT '',
        goal_title TEXT NOT NULL DEFAULT '',
        goal_body  TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS features (
        id          TEXT PRIMARY KEY,
        week_id     TEXT NOT NULL DEFAULT '',
        title       TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        status      TEXT NOT NULL DEFAULT 'todo',
        sort_order  INTEGER NOT NULL DEFAULT 0,
        date_added  TEXT NOT NULL DEFAULT ''
    );
    """)


def _deserialize(row: sqlite3.Row) -> dict:
    d = dict(row)
    for key in ("serves", "body", "depends_on", "tags"):
        if key in d and isinstance(d[key], str):
            try:
                d[key] = json.loads(d[key])
            except (json.JSONDecodeError, TypeError):
                d[key] = []
    return d


def _today() -> str:
    return datetime.date.today().isoformat()


class ProjectDB:
    """Thin wrapper around a project's SQLite database."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        _migrate(self._conn)

    def close(self) -> None:
        self._conn.close()

    # ── Meta ──────────────────────────────────────────────────────────────────

    def get_meta(self) -> dict[str, str]:
        rows = self._conn.execute("SELECT key, value FROM meta").fetchall()
        return {r["key"]: r["value"] for r in rows}

    def set_meta(self, key: str, value: str) -> None:
        self._conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", (key, value)
        )
        self._conn.commit()

    def update_meta(self, data: dict[str, str]) -> None:
        self._conn.executemany(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
            [(k, str(v)) for k, v in data.items()],
        )
        self._conn.commit()

    # ── Buckets ───────────────────────────────────────────────────────────────

    def list_buckets(self) -> list[dict]:
        rows = self._conn.execute(
            "SELECT p, label, descr FROM buckets ORDER BY p"
        ).fetchall()
        return [dict(r) for r in rows]

    def ensure_default_buckets(self) -> None:
        self._conn.executemany(
            "INSERT OR IGNORE INTO buckets (p, label, descr) VALUES (?, ?, ?)",
            _DEFAULT_BUCKETS,
        )
        self._conn.commit()

    # ── Tasks ─────────────────────────────────────────────────────────────────

    def next_task_id(self, bucket: str = "T") -> str:
        rows = self._conn.execute("SELECT id FROM tasks").fetchall()
        prefix = bucket + "-"
        nums = [
            int(r["id"][len(prefix):]) for r in rows
            if r["id"].startswith(prefix) and r["id"][len(prefix):].isdigit()
        ]
        return f"{bucket}-{(max(nums) + 1) if nums else 1:02d}"

    def list_tasks(
        self, bucket: str | None = None, status: str | None = None
    ) -> list[dict]:
        sql = "SELECT * FROM tasks"
        params: list[Any] = []
        conds: list[str] = []
        if bucket:
            conds.append("bucket = ?")
            params.append(bucket)
        if status:
            conds.append("status = ?")
            params.append(status)
        if conds:
            sql += " WHERE " + " AND ".join(conds)
        sql += " ORDER BY date_added DESC, id"
        return [_deserialize(r) for r in self._conn.execute(sql, params).fetchall()]

    def get_task(self, task_id: str) -> dict | None:
        r = self._conn.execute(
            "SELECT * FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()
        return _deserialize(r) if r else None

    def create_task(
        self,
        title: str,
        bucket: str = "T",
        module: str = "",
        size: str = "M",
        effort: str = "",
        description: str = "",
        output: str = "",
        acceptance: str = "",
        note: str = "",
        serves: list | None = None,
        status: str = "todo",
        date_added: str = "",
        task_id: str | None = None,
        tags: list | None = None,
        priority: str = "medium",
        **_: Any,
    ) -> dict:
        tid = task_id or self.next_task_id(bucket)
        today = date_added or _today()
        self._conn.execute(
            """INSERT INTO tasks
               (id,bucket,module,title,size,effort,
                description,output,acceptance,note,
                serves,status,date_added,tags,priority)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (tid, bucket, module, title, size, effort,
             description, output, acceptance, note,
             json.dumps(serves or []), status, today,
             json.dumps(tags or []), priority),
        )
        self._conn.commit()
        return self.get_task(tid)  # type: ignore[return-value]

    def update_task(self, task_id: str, **kwargs: Any) -> dict | None:
        if not self.get_task(task_id):
            return None
        _json_fields = {"serves", "tags"}
        sets, params = [], []
        for k, v in kwargs.items():
            if k not in _TASK_COLUMNS:
                continue
            if k in _json_fields and not isinstance(v, str):
                v = json.dumps(v)
            sets.append(f"{k} = ?")
            params.append(v)
        if not sets:
            return self.get_task(task_id)
        sets.append("updated_at = ?")
        params.extend([_today(), task_id])
        self._conn.execute(
            f"UPDATE tasks SET {', '.join(sets)} WHERE id = ?", params
        )
        self._conn.commit()
        return self.get_task(task_id)

    def delete_task(self, task_id: str) -> bool:
        cur = self._conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Research ──────────────────────────────────────────────────────────────

    def next_research_id(self) -> str:
        rows = self._conn.execute("SELECT id FROM research").fetchall()
        nums = [int(r["id"][1:]) for r in rows
                if r["id"].startswith("R") and r["id"][1:].isdigit()]
        return f"R{(max(nums) + 1) if nums else 1}"

    def list_research(self, status: str | None = None) -> list[dict]:
        sql = "SELECT * FROM research"
        params: list[Any] = []
        if status:
            sql += " WHERE status = ?"
            params.append(status)
        sql += " ORDER BY id"
        return [_deserialize(r) for r in self._conn.execute(sql, params).fetchall()]

    def get_research(self, rid: str) -> dict | None:
        r = self._conn.execute(
            "SELECT * FROM research WHERE id = ?", (rid,)
        ).fetchone()
        return _deserialize(r) if r else None

    def create_research(
        self,
        title: str,
        hypothesis: str = "",
        body: list | None = None,
        kind: str = "ANALYSIS",
        module: str = "",
        codename: str = "",
        depends_on: list | None = None,
        status: str = "open",
        date_added: str = "",
        research_id: str | None = None,
        **_: Any,
    ) -> dict:
        rid = research_id or self.next_research_id()
        today = date_added or _today()
        self._conn.execute(
            """INSERT INTO research
               (id,codename,title,kind,module,hypothesis,
                body,depends_on,status,date_added)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (rid, codename, title, kind, module, hypothesis,
             json.dumps(body or []), json.dumps(depends_on or []),
             status, today),
        )
        self._conn.commit()
        return self.get_research(rid)  # type: ignore[return-value]

    def update_research(self, rid: str, **kwargs: Any) -> dict | None:
        if not self.get_research(rid):
            return None
        _json_fields = {"body", "depends_on"}
        sets, params = [], []
        for k, v in kwargs.items():
            if k not in _RESEARCH_COLUMNS:
                continue
            if k in _json_fields and not isinstance(v, str):
                v = json.dumps(v)
            sets.append(f"{k} = ?")
            params.append(v)
        if not sets:
            return self.get_research(rid)
        sets.append("updated_at = ?")
        params.extend([_today(), rid])
        self._conn.execute(
            f"UPDATE research SET {', '.join(sets)} WHERE id = ?", params
        )
        self._conn.commit()
        return self.get_research(rid)

    def delete_research(self, rid: str) -> bool:
        cur = self._conn.execute("DELETE FROM research WHERE id = ?", (rid,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Notes ─────────────────────────────────────────────────────────────────

    def list_notes(self) -> list[dict]:
        rows = self._conn.execute(
            "SELECT slug,title,date,tags,excerpt FROM notes ORDER BY date DESC, slug DESC"
        ).fetchall()
        return [_deserialize(r) for r in rows]

    def get_note(self, slug: str) -> dict | None:
        r = self._conn.execute(
            "SELECT * FROM notes WHERE slug = ?", (slug,)
        ).fetchone()
        return _deserialize(r) if r else None

    def create_note(
        self,
        title: str,
        body_html: str = "",
        body: str = "",
        tags: list | None = None,
        excerpt: str = "",
        date: str = "",
        slug: str | None = None,
        **_: Any,
    ) -> dict:
        if not body_html and body:
            body_html = _text_to_html(body)
        today = date or _today()
        if not slug:
            slug_base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
            slug = f"{today}-{slug_base}"
        if not excerpt:
            clean = re.sub(r"<[^>]+>", "", body_html)
            excerpt = (clean[:150] + "…") if len(clean) > 150 else clean[:150]
        self._conn.execute(
            "INSERT INTO notes (slug,title,date,body_html,tags,excerpt) VALUES (?,?,?,?,?,?)",
            (slug, title, today, body_html, json.dumps(tags or []), excerpt),
        )
        self._conn.commit()
        return self.get_note(slug)  # type: ignore[return-value]

    def update_note(self, slug: str, **kwargs: Any) -> dict | None:
        if not self.get_note(slug):
            return None
        if "body" in kwargs and "body_html" not in kwargs:
            kwargs["body_html"] = _text_to_html(kwargs.pop("body"))
        elif "body" in kwargs:
            kwargs.pop("body")
        _json_fields = {"tags"}
        sets, params = [], []
        for k, v in kwargs.items():
            if k not in _NOTE_COLUMNS:
                continue
            if k in _json_fields and not isinstance(v, str):
                v = json.dumps(v)
            sets.append(f"{k} = ?")
            params.append(v)
        if not sets:
            return self.get_note(slug)
        params.append(slug)
        self._conn.execute(
            f"UPDATE notes SET {', '.join(sets)} WHERE slug = ?", params
        )
        self._conn.commit()
        return self.get_note(slug)

    def delete_note(self, slug: str) -> bool:
        cur = self._conn.execute("DELETE FROM notes WHERE slug = ?", (slug,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Weeks ─────────────────────────────────────────────────────────────────

    def get_week(self, week_id: str) -> dict:
        r = self._conn.execute(
            "SELECT * FROM weeks WHERE week_id = ?", (week_id,)
        ).fetchone()
        return dict(r) if r else {
            "week_id": week_id, "date_start": "",
            "goal_title": "", "goal_body": "",
        }

    def upsert_week(self, week_id: str, **kwargs: Any) -> dict:
        kwargs = {k: v for k, v in kwargs.items() if k in _WEEK_COLUMNS}
        existing = self._conn.execute(
            "SELECT week_id FROM weeks WHERE week_id = ?", (week_id,)
        ).fetchone()
        if existing:
            sets, params = [], []
            for k, v in kwargs.items():
                sets.append(f"{k} = ?")
                params.append(v)
            if sets:
                params.append(week_id)
                self._conn.execute(
                    f"UPDATE weeks SET {', '.join(sets)} WHERE week_id = ?", params
                )
        else:
            cols = ["week_id"] + list(kwargs.keys())
            vals = [week_id] + list(kwargs.values())
            ph = ", ".join("?" * len(vals))
            self._conn.execute(
                f"INSERT INTO weeks ({', '.join(cols)}) VALUES ({ph})", vals
            )
        self._conn.commit()
        return self.get_week(week_id)

    def list_weeks(self) -> list[dict]:
        rows = self._conn.execute(
            "SELECT * FROM weeks ORDER BY week_id DESC"
        ).fetchall()
        return [dict(r) for r in rows]

    # ── Features ──────────────────────────────────────────────────────────────

    def next_feature_id(self) -> str:
        rows = self._conn.execute("SELECT id FROM features").fetchall()
        nums = [int(r["id"][1:]) for r in rows
                if r["id"].startswith("F") and r["id"][1:].isdigit()]
        return f"F{(max(nums) + 1) if nums else 1:02d}"

    def list_features(self, week_id: str | None = None) -> list[dict]:
        sql = "SELECT * FROM features"
        params: list[Any] = []
        if week_id:
            sql += " WHERE week_id = ?"
            params.append(week_id)
        sql += " ORDER BY sort_order, id"
        return [dict(r) for r in self._conn.execute(sql, params).fetchall()]

    def get_feature(self, fid: str) -> dict | None:
        r = self._conn.execute(
            "SELECT * FROM features WHERE id = ?", (fid,)
        ).fetchone()
        return dict(r) if r else None

    def create_feature(
        self,
        title: str,
        week_id: str = "",
        description: str = "",
        status: str = "todo",
        sort_order: int = 0,
        feature_id: str | None = None,
        **_: Any,
    ) -> dict:
        fid = feature_id or self.next_feature_id()
        self._conn.execute(
            """INSERT INTO features (id,week_id,title,description,status,sort_order,date_added)
               VALUES (?,?,?,?,?,?,?)""",
            (fid, week_id, title, description, status, sort_order, _today()),
        )
        self._conn.commit()
        return self.get_feature(fid)  # type: ignore[return-value]

    def update_feature(self, fid: str, **kwargs: Any) -> dict | None:
        if not self.get_feature(fid):
            return None
        sets, params = [], []
        for k, v in kwargs.items():
            if k not in _FEATURE_COLUMNS:
                continue
            sets.append(f"{k} = ?")
            params.append(v)
        if not sets:
            return self.get_feature(fid)
        params.append(fid)
        self._conn.execute(
            f"UPDATE features SET {', '.join(sets)} WHERE id = ?", params
        )
        self._conn.commit()
        return self.get_feature(fid)

    def delete_feature(self, fid: str) -> bool:
        cur = self._conn.execute("DELETE FROM features WHERE id = ?", (fid,))
        self._conn.commit()
        return cur.rowcount > 0

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    @classmethod
    def create(cls, path: Path, meta: dict | None = None) -> "ProjectDB":
        path.parent.mkdir(parents=True, exist_ok=True)
        db = cls(path)
        db._conn.executescript(_SCHEMA)
        db.ensure_default_buckets()
        if meta:
            db.update_meta({k: str(v) for k, v in meta.items()})
        return db

    @classmethod
    def open(cls, path: Path) -> "ProjectDB | None":
        if not path.exists():
            return None
        return cls(path)

    @classmethod
    def open_or_create(cls, path: Path, meta: dict | None = None) -> "ProjectDB":
        if path.exists():
            return cls(path)
        return cls.create(path, meta)


def _text_to_html(text: str) -> str:
    if re.search(r"<[a-zA-Z]", text):
        return text
    paragraphs = [p.strip() for p in re.split(r"\n{2,}", text) if p.strip()]
    parts = []
    for p in paragraphs:
        p = p.replace("\n", "<br>")
        p = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", p)
        p = re.sub(r"`([^`]+)`", r"<code>\1</code>", p)
        parts.append(f"<p>{p}</p>")
    return "\n".join(parts)


def seed_demo(db: "ProjectDB") -> None:
    db.update_meta({
        "project": "Demo",
        "short": "Demo",
        "tagline": "Example project for DocsBot dashboard",
        "description": "A sample project to demonstrate DocsBot.",
        "last_updated": _today(),
        "doc_number": "NB-001",
        "repo_url": "",
        "stale_days": "14",
    })

    tasks_data = [
        ("T", "", "Set up minimal regression test suite",       "M", "",  "todo",    "Project has no automated test directory.",  "", "", "high",     ["testing"],           "2026-01-10"),
        ("T", "", "Wire validation gate into main solver loop", "M", "",  "todo",    "Validation module exists but is not called.","","", "critical", ["core", "soundness"], "2026-01-15"),
        ("T", "", "Add parser round-trip property tests",       "S", "",  "todo",    "No round-trip guarantee tested.",           "", "", "medium",   ["testing", "parser"], "2026-01-20"),
        ("T", "", "Sanitize shell command construction",        "S", "",  "todo",    "Paths concatenated into shell strings.",    "", "", "high",     ["security", "infra"], "2026-01-25"),
        ("T", "", "Design run manifest schema",                 "S", "",  "todo",    "Ad-hoc logs, no structured manifest.",      "", "", "medium",   ["infra"],             "2026-02-01"),
        ("T", "", "Batch runner CLI skeleton",                  "L", "",  "todo",    "No automated batch execution.",             "", "", "medium",   ["infra", "cli"],      "2026-02-15"),
        ("T", "", "Implement alphabet analyzer prototype",      "L", "",  "todo",    "Static classification for string exprs.",   "", "", "low",      ["research"],          "2026-03-01"),
        ("T", "", "Write architecture overview note",           "S", "",  "done",    "No single document describes architecture.","","", "low",      ["docs"],              "2026-01-05"),
    ]
    for bucket, module, title, size, effort, status, desc, out, accept, priority, tags, date in tasks_data:
        db.create_task(title=title, bucket=bucket, module=module, size=size,
                       effort=effort, description=desc, output=out,
                       acceptance=accept, status=status, priority=priority,
                       tags=tags, date_added=date)

    research_data = [
        ("SOUND",   "Integrate candidate validation into the main loop", "SAFETY",      "loop",
         "Candidate lemmas should be validated for entailment before influencing the main solver.",
         ["The current pipeline generates candidate lemmas but does not gate them through soundness.",
          "Insert a validation step: generate, check entailment, then only pass sound candidates."],
         [], "in-progress", "2026-01-10"),
        ("STATIC",  "Static analysis for input-output alphabet properties", "STATIC", "core",
         "Many rewrite patterns can be resolved by static analysis of input/output alphabets.",
         ["Manual analysis shows idempotence and commutativity often depend only on alphabet.",
          "If we can classify statically, we short-circuit solver calls for easy cases."],
         [], "open", "2026-01-15"),
        ("MEASURE", "Structured run manifests for experiment reproducibility", "MEASUREMENT", "infra",
         "Without structured run manifests, results cannot be compared across iterations.",
         ["Current logging captures raw traces but lacks structured fields.",
          "Run one experiment and produce a manifest.json summarizable in one command."],
         [], "in-progress", "2026-02-10"),
        ("BATCH",   "Batch orchestration and regression testing", "INFRA", "infra",
         "A stable batch runner is required before scaling to larger benchmark suites.",
         ["Running experiments by hand does not scale."],
         [], "open", "2026-03-01"),
    ]
    for codename, title, kind, module, hyp, body, deps, status, date in research_data:
        db.create_research(title=title, codename=codename, kind=kind,
                           module=module, hypothesis=hyp, body=body,
                           depends_on=deps, status=status, date_added=date)

    db.create_note(
        title="Getting Started with DocsBot",
        body_html=(
            "<h2>Welcome</h2>"
            "<p>This is a demo project. Create a real project via the <strong>+</strong> button.</p>"
            "<h2>Data model</h2>"
            "<p>Each project has <strong>Tasks</strong>, <strong>Research directions</strong>, "
            "and <strong>Notes</strong>. All stored in a local SQLite database under "
            "<code>~/.docsbot/projects/</code>.</p>"
            "<h2>Weekly Workbench</h2>"
            "<p>Use the weekly section to plan each week: set a goal and list the focus areas "
            "you want to tackle.</p>"
            "<h2>MCP integration</h2>"
            "<p>Run <code>docsbot mcp</code> to expose your projects as tools that Claude Code "
            "can read and write automatically.</p>"
        ),
        tags=["docs", "intro"],
        date="2026-01-15",
    )
