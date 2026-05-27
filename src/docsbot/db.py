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
    status      TEXT NOT NULL DEFAULT 'open',
    date_added  TEXT NOT NULL,
    updated_at  TEXT
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
"""

_DEFAULT_BUCKETS = [
    ("P0", "CORRECTNESS", "Items affecting result soundness."),
    ("P1", "VALIDATION",  "Testing, fixtures, and verification scripts."),
    ("P2", "EVIDENCE",    "Logging, metrics, and reproducibility."),
    ("P3", "PIPELINE",    "CLI, wrappers, batch, and scheduling."),
    ("P4", "FEATURES",    "Research prototypes and recognizers."),
    ("P5", "NOTES",       "Documentation and maintenance."),
]


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

    def next_task_id(self, bucket: str) -> str:
        rows = self._conn.execute(
            "SELECT id FROM tasks WHERE bucket = ?", (bucket,)
        ).fetchall()
        prefix = bucket + "-"
        nums = [int(r["id"][len(prefix):]) for r in rows
                if r["id"].startswith(prefix) and r["id"][len(prefix):].isdigit()]
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
        sql += " ORDER BY bucket, id"
        return [_deserialize(r) for r in self._conn.execute(sql, params).fetchall()]

    def get_task(self, task_id: str) -> dict | None:
        r = self._conn.execute(
            "SELECT * FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()
        return _deserialize(r) if r else None

    def create_task(
        self,
        title: str,
        bucket: str = "P0",
        module: str = "",
        size: str = "M",
        effort: str = "",
        description: str = "",
        output: str = "",
        acceptance: str = "",
        note: str = "",
        serves: list | None = None,
        status: str = "open",
        date_added: str = "",
        task_id: str | None = None,
        **_: Any,
    ) -> dict:
        tid = task_id or self.next_task_id(bucket)
        today = date_added or _today()
        self._conn.execute(
            """INSERT INTO tasks
               (id,bucket,module,title,size,effort,
                description,output,acceptance,note,
                serves,status,date_added)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (tid, bucket, module, title, size, effort,
             description, output, acceptance, note,
             json.dumps(serves or []), status, today),
        )
        self._conn.commit()
        return self.get_task(tid)  # type: ignore[return-value]

    def update_task(self, task_id: str, **kwargs: Any) -> dict | None:
        if not self.get_task(task_id):
            return None
        _json_fields = {"serves"}
        sets, params = [], []
        for k, v in kwargs.items():
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
        # Accept either body_html (raw HTML) or body (plain text → converted)
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
        # Convert body → body_html if provided
        if "body" in kwargs and "body_html" not in kwargs:
            kwargs["body_html"] = _text_to_html(kwargs.pop("body"))
        elif "body" in kwargs:
            kwargs.pop("body")
        _json_fields = {"tags"}
        sets, params = [], []
        for k, v in kwargs.items():
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

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    @classmethod
    def create(cls, path: Path, meta: dict | None = None) -> "ProjectDB":
        """Create a new database, initialize schema, seed default buckets."""
        path.parent.mkdir(parents=True, exist_ok=True)
        db = cls(path)
        db._conn.executescript(_SCHEMA)
        db.ensure_default_buckets()
        if meta:
            db.update_meta({k: str(v) for k, v in meta.items()})
        return db

    @classmethod
    def open(cls, path: Path) -> "ProjectDB | None":
        """Open an existing database. Returns None if not found."""
        if not path.exists():
            return None
        return cls(path)

    @classmethod
    def open_or_create(cls, path: Path, meta: dict | None = None) -> "ProjectDB":
        """Open if it exists, otherwise create."""
        if path.exists():
            return cls(path)
        return cls.create(path, meta)


def _text_to_html(text: str) -> str:
    """Convert plain text (markdown-lite) to HTML paragraphs."""
    if re.search(r"<[a-zA-Z]", text):
        return text  # already HTML
    paragraphs = [p.strip() for p in re.split(r"\n{2,}", text) if p.strip()]
    parts = []
    for p in paragraphs:
        p = p.replace("\n", "<br>")
        p = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", p)
        p = re.sub(r"`([^`]+)`", r"<code>\1</code>", p)
        parts.append(f"<p>{p}</p>")
    return "\n".join(parts)


def seed_demo(db: "ProjectDB") -> None:
    """Seed *db* with representative demo data."""
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
        ("P0", "infra",  "Set up minimal regression test suite",     "M", "2-3 d",  "open",        "Project has no automated test directory.", "CMake test target + fixture files.", "`ctest` runs cleanly.", "Prevents future soundness regressions.", [], "2026-01-10"),
        ("P0", "loop",   "Wire validation gate into main solver loop","M", "2-3 d",  "in-progress", "Validation module exists but is not called.", "Candidates pass through entailment check.", "Unsound candidate does not corrupt result.", "Largest semantic gap.", ["R1", "R5"], "2026-01-15"),
        ("P1", "core",   "Add parser round-trip property tests",      "S", "1 d",    "open",        "No round-trip guarantee is tested.", "Property-based tests.", "100+ inputs pass.", "", [], "2026-01-20"),
        ("P1", "infra",  "Sanitize shell command construction",       "S", "1 d",    "open",        "Paths concatenated into shell strings.", "Uniform command builder with escaping.", "Paths with spaces work.", "", ["R1"], "2026-01-25"),
        ("P2", "infra",  "Design run manifest schema",               "S", "1-2 d",  "open",        "Ad-hoc logs exist but no structured manifest.", "Documented JSONL schema.", "One run produces a summary.", "", ["R4"], "2026-02-01"),
        ("P3", "infra",  "Batch runner CLI skeleton",                "L", "3-5 d",  "blocked",     "No automated batch execution.", "CLI accepting config + collecting outputs.", "10 cases run without intervention.", "", ["R5"], "2026-02-15"),
        ("P4", "core",   "Implement alphabet analyzer prototype",    "L", "1-2 wk", "open",        "String expressions with replace_all chains.", "Static classification: idempotent/commutative.", "12 samples classified correctly.", "", ["R2"], "2026-03-01"),
        ("P5", "infra",  "Write architecture overview note",         "S", "1 d",    "done",        "No single document describes architecture.", "Living architecture note with component map.", "New contributor orients in 30 min.", "", [], "2026-01-05"),
    ]
    for bucket, module, title, size, effort, status, desc, out, accept, note, serves, date in tasks_data:
        db.create_task(title=title, bucket=bucket, module=module, size=size,
                       effort=effort, description=desc, output=out,
                       acceptance=accept, note=note, serves=serves,
                       status=status, date_added=date)

    research_data = [
        ("SOUND",   "Integrate candidate validation into the main loop", "SAFETY",      "loop",
         "Hypothesis: Candidate lemmas should be validated for entailment before influencing the main solver conclusion.",
         ["The current pipeline generates candidate lemmas but does not gate them through a soundness check.",
          "The goal is to insert a validation step: generate, check entailment, then only pass sound candidates.",
          "**Milestone:** Construct a deliberately unsound candidate and confirm it does not corrupt the result."],
         ["P0-01", "P1-01"], "in-progress", "2026-01-10"),
        ("STATIC",  "Static analysis for input-output alphabet properties", "STATIC", "core",
         "Hypothesis: Many rewrite patterns can be resolved by static analysis of input/output alphabets before invoking the solver.",
         ["Manual analysis shows idempotence and commutativity often depend only on the input/output alphabet relationship.",
          "If we can classify these statically, we can short-circuit solver calls for easy cases."],
         ["P4-01"], "open", "2026-01-15"),
        ("MEASURE", "Structured run manifests for experiment reproducibility", "MEASUREMENT", "infra",
         "Hypothesis: Without structured run manifests, experimental results cannot be compared across iterations.",
         ["Current logging captures raw traces but lacks structured fields: candidate count, pass/fail reasons, tokens.",
          "**Milestone:** Run one experiment and produce a manifest.json summarizable in one command."],
         ["P2-01"], "in-progress", "2026-02-10"),
        ("BATCH",   "Batch orchestration and regression testing", "INFRA", "infra",
         "Hypothesis: A stable batch runner is required before scaling to larger benchmark suites.",
         ["Running experiments by hand does not scale. A batch runner should accept config, run all cases, collect manifests."],
         ["P3-01"], "blocked", "2026-03-01"),
    ]
    for codename, title, kind, module, hyp, body, deps, status, date in research_data:
        db.create_research(title=title, codename=codename, kind=kind,
                           module=module, hypothesis=hyp, body=body,
                           depends_on=deps, status=status, date_added=date)

    db.create_note(
        title="Getting Started with DocsBot",
        body_html=(
            "<h2>Welcome</h2>"
            "<p>This is a demo project. Open a real project folder via the <strong>+</strong> button in the header.</p>"
            "<h2>Data model</h2>"
            "<p>Each project has <strong>Tasks</strong> (grouped by priority bucket), "
            "<strong>Research directions</strong>, and <strong>Notes</strong>. "
            "All data is stored in a local SQLite database.</p>"
            "<h2>MCP integration</h2>"
            "<p>Run <code>docsbot mcp</code> to expose your projects as tools that Claude Code sessions "
            "can read and write automatically.</p>"
        ),
        tags=["docs", "intro"],
        date="2026-01-15",
    )
