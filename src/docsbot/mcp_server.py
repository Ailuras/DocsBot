"""DocsBot MCP server — exposes DocsBot read/write tools to Claude Code sessions."""

from __future__ import annotations

import datetime
import json
import re
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP

from docsbot.config import _load_meta, list_projects as _list_projects, project_base

mcp = FastMCP("docsbot")


# ── JS data helpers ───────────────────────────────────────────────────────────

def _find_js_assignment(text: str, var_name: str) -> tuple[str, int, int] | None:
    """Locate `window.VAR_NAME = <value>;` in *text*.

    Returns (value_text, assign_start, assign_end) where the slice
    text[assign_start:assign_end] covers the full assignment statement.
    Returns None if the variable is not found.
    """
    m = re.search(rf'\bwindow\.{re.escape(var_name)}\s*=\s*', text)
    if not m:
        return None
    assign_start = m.start()
    pos = m.end()
    depth = 0
    in_str: str | None = None
    escape_next = False

    while pos < len(text):
        c = text[pos]
        if escape_next:
            escape_next = False
            pos += 1
            continue
        if c == "\\" and in_str:
            escape_next = True
            pos += 1
            continue
        if in_str:
            if c == in_str:
                in_str = None
        else:
            if c in ('"', "'"):
                in_str = c
            elif c in ("{", "["):
                depth += 1
            elif c in ("}", "]"):
                depth -= 1
                if depth == 0:
                    pos += 1
                    break
        pos += 1

    assign_end = pos
    # Consume optional semicolon
    while assign_end < len(text) and text[assign_end] in (" ", "\t"):
        assign_end += 1
    if assign_end < len(text) and text[assign_end] == ";":
        assign_end += 1

    return text[m.end() : pos], assign_start, assign_end


def _load_js_var(path: Path, var_name: str) -> Any:
    """Parse a single JS variable value from a data file. Returns None on any failure."""
    try:
        import json5  # lazy import — only needed for read path

        text = path.read_text(encoding="utf-8")
        result = _find_js_assignment(text, var_name)
        if result is None:
            return None
        value_text, _, _ = result
        return json5.loads(value_text)
    except Exception:
        return None


def _save_js_var(path: Path, var_name: str, data: Any) -> None:
    """Write *data* back as the assignment of *var_name* in *path*.

    If the variable already exists its assignment is replaced in-place,
    preserving all other content in the file (comments, other variables).
    If it does not exist yet the assignment is appended.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        text = ""

    new_assignment = (
        f"window.{var_name} = "
        + json.dumps(data, ensure_ascii=False, indent=2, default=str)
        + ";"
    )
    result = _find_js_assignment(text, var_name)
    if result:
        _, start, end = result
        new_text = text[:start] + new_assignment + text[end:]
    else:
        sep = "\n" if text and not text.endswith("\n") else ""
        new_text = text + sep + new_assignment + "\n"

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_text, encoding="utf-8")


def _is_example(base: Path) -> bool:
    from docsbot.config import default_data_dir

    return str(base).startswith(str(default_data_dir() / "examples"))


# ── Tools ─────────────────────────────────────────────────────────────────────

@mcp.tool()
def list_projects() -> str:
    """List all registered DocsBot projects with their IDs, names, and taglines.

    Always call this first to discover valid project_id values before using
    any other tool.
    """
    projects = _list_projects()
    if not projects:
        return "No projects registered. Open a project folder first via the DocsBot dashboard."
    lines = ["Registered DocsBot projects:", ""]
    for p in projects:
        lines.append(f"  id       : {p['id']}")
        lines.append(f"  name     : {p['name']}")
        lines.append(f"  tagline  : {p.get('tagline', '')}")
        lines.append(f"  path     : {p.get('path', '')}")
        lines.append("")
    return "\n".join(lines)


@mcp.tool()
def get_project_summary(project_id: str) -> str:
    """Return a concise summary of a project: metadata, task status counts, research counts.

    Args:
        project_id: Project identifier (from list_projects).
    """
    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found. Run list_projects to see valid IDs."

    meta = _load_meta(base / "data" / "meta.js")
    backlog = _load_js_var(base / "data" / "backlog.js", "AUGUR_BACKLOG") or []
    research = _load_js_var(base / "data" / "research.js", "AUGUR_RESEARCH") or []
    notes_index = _load_js_var(base / "data" / "notes.js", "AUGUR_NOTES") or []

    status_counts: dict[str, int] = {}
    for task in backlog:
        s = task.get("status", "unknown")
        status_counts[s] = status_counts.get(s, 0) + 1

    research_by_status: dict[str, int] = {}
    for r in research:
        s = r.get("status", "unknown")
        research_by_status[s] = research_by_status.get(s, 0) + 1

    lines = [
        f"Project  : {meta.get('project', project_id)}",
        f"Tagline  : {meta.get('tagline', '(none)')}",
        f"Updated  : {meta.get('last_updated', '(unknown)')}",
        "",
        f"Backlog ({len(backlog)} tasks):",
    ]
    for status, count in sorted(status_counts.items()):
        lines.append(f"  {status:<14} {count}")
    lines.append("")
    lines.append(f"Research ({len(research)} directions):")
    for status, count in sorted(research_by_status.items()):
        lines.append(f"  {status:<14} {count}")
    lines.append("")
    lines.append(f"Notes    : {len(notes_index)}")

    return "\n".join(lines)


@mcp.tool()
def read_file(project_id: str, filename: str) -> str:
    """Read the raw contents of a project data file.

    Use this to inspect existing tasks, research directions, or notes before
    making changes.  filename is relative to the project root (e.g.
    'data/backlog.js', 'data/research.js', 'data/notes.js').

    Args:
        project_id: Project identifier (from list_projects).
        filename: Path relative to the project root directory.
    """
    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found."
    if ".." in filename or filename.startswith("/"):
        return "Error: invalid filename (directory traversal not allowed)."

    for candidate in (base / filename, base / "data" / filename):
        if candidate.exists() and candidate.is_file():
            return candidate.read_text(encoding="utf-8")

    return f"Error: file '{filename}' not found in project '{project_id}'."


@mcp.tool()
def add_todo(
    project_id: str,
    title: str,
    description: str = "",
    bucket: str = "P0",
    module: str = "core",
    size: str = "M",
    effort: str = "",
    note: str = "",
) -> str:
    """Add a new task to the project backlog.

    A unique task ID is generated automatically within the chosen bucket
    (e.g. P0-05, P2-03).

    Args:
        project_id: Project identifier (from list_projects).
        title: Short, imperative task title.
        description: What needs to be done (stored in fields.input).
        bucket: Priority bucket — P0=CORRECTNESS, P1=VALIDATION, P2=EVIDENCE,
                P3=PIPELINE, P4=FEATURES, P5=NOTES.
        module: Code module or subsystem (e.g. 'core', 'infra', 'loop').
        size: T-shirt size — XS, S, M, L, XL.
        effort: Time estimate (e.g. '1 d', '2-3 d', '1 wk').
        note: Additional context (stored in fields.note).
    """
    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found."
    if _is_example(base):
        return "Error: cannot write to example projects."

    backlog_path = base / "data" / "backlog.js"
    backlog: list[dict] = _load_js_var(backlog_path, "AUGUR_BACKLOG") or []

    prefix = bucket + "-"
    nums = []
    for t in backlog:
        tid = t.get("id", "")
        if isinstance(tid, str) and tid.startswith(prefix):
            suffix = tid[len(prefix):]
            if suffix.isdigit():
                nums.append(int(suffix))
    new_num = (max(nums) + 1) if nums else 1
    new_id = f"{bucket}-{new_num:02d}"

    today = datetime.date.today().isoformat()
    backlog.append(
        {
            "id": new_id,
            "bucket": bucket,
            "module": module,
            "title": title,
            "size": size,
            "effort": effort,
            "serves": [],
            "fields": {
                "input": description,
                "output": "",
                "accept": "",
                "note": note,
            },
            "status": "open",
            "date_added": today,
        }
    )
    _save_js_var(backlog_path, "AUGUR_BACKLOG", backlog)
    return f"Added task {new_id}: {title}"


@mcp.tool()
def update_todo_status(project_id: str, task_id: str, status: str) -> str:
    """Update the status of an existing backlog task.

    Args:
        project_id: Project identifier (from list_projects).
        task_id: Task ID to update (e.g. 'P0-01').
        status: New status — 'open', 'in-progress', 'blocked', 'done'.
    """
    valid = {"open", "in-progress", "blocked", "done"}
    if status not in valid:
        return f"Error: status must be one of {sorted(valid)}."

    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found."
    if _is_example(base):
        return "Error: cannot write to example projects."

    backlog_path = base / "data" / "backlog.js"
    backlog: list[dict] = _load_js_var(backlog_path, "AUGUR_BACKLOG") or []

    for task in backlog:
        if task.get("id") == task_id:
            task["status"] = status
            task["updated_at"] = datetime.date.today().isoformat()
            _save_js_var(backlog_path, "AUGUR_BACKLOG", backlog)
            return f"Updated {task_id} → {status}"

    return f"Error: task '{task_id}' not found in project '{project_id}'."


@mcp.tool()
def add_research_item(
    project_id: str,
    title: str,
    hypothesis: str,
    body: str,
    kind: str = "ANALYSIS",
    module: str = "core",
    codename: str = "",
) -> str:
    """Add a new research direction to the project.

    A unique ID is generated automatically (R6, R7, …).

    Args:
        project_id: Project identifier (from list_projects).
        title: Research direction title.
        hypothesis: One-sentence hypothesis (without the 'Hypothesis:' prefix).
        body: Body text — use double newlines to separate paragraphs.
        kind: Category — ANALYSIS, SAFETY, STATIC, NORMALIZATION, MEASUREMENT,
              INFRA, FEATURE.
        module: Code module or subsystem.
        codename: Short uppercase codename (auto-derived from title if empty).
    """
    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found."
    if _is_example(base):
        return "Error: cannot write to example projects."

    research_path = base / "data" / "research.js"
    research: list[dict] = _load_js_var(research_path, "AUGUR_RESEARCH") or []

    nums = []
    for r in research:
        rid = r.get("id", "")
        if isinstance(rid, str) and rid.startswith("R"):
            try:
                nums.append(int(rid[1:]))
            except ValueError:
                pass
    new_num = (max(nums) + 1) if nums else 1
    new_id = f"R{new_num}"

    if not codename:
        codename = re.sub(r"[^A-Z0-9]", "", title.upper())[:8]

    paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]

    today = datetime.date.today().isoformat()
    research.append(
        {
            "id": new_id,
            "codename": codename,
            "title": title,
            "kind": kind,
            "module": module,
            "hypothesis": f"Hypothesis: {hypothesis}",
            "body": paragraphs,
            "depends_on": [],
            "status": "open",
            "date_added": today,
        }
    )
    _save_js_var(research_path, "AUGUR_RESEARCH", research)
    return f"Added research item {new_id}: {title}"


@mcp.tool()
def add_note(
    project_id: str,
    title: str,
    body: str,
    tags: str = "",
    excerpt: str = "",
) -> str:
    """Create a new note in the project and add it to the notes index.

    The note is written to notes/<date>-<slug>.html and the notes.js index
    is updated so it appears in the DocsBot dashboard immediately.

    Args:
        project_id: Project identifier (from list_projects).
        title: Note title.
        body: Note content.  Plain text paragraphs (separated by blank lines)
              are wrapped in <p> tags automatically.  Raw HTML is also accepted.
        tags: Comma-separated tags, e.g. 'architecture,decisions,session-summary'.
        excerpt: Short summary for the index card (auto-generated if empty).
    """
    base = project_base(project_id)
    if not base:
        return f"Error: project '{project_id}' not found."
    if _is_example(base):
        return "Error: cannot write to example projects."

    today = datetime.date.today().isoformat()

    slug_base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    slug = f"{today}-{slug_base}"

    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []

    is_html = bool(re.search(r"<[a-zA-Z]", body))
    if is_html:
        html_body = body
    else:
        paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]
        html_body = "\n".join(
            f"<p>{p.replace(chr(10), '<br>')}</p>" for p in paragraphs
        )

    if not excerpt:
        clean = re.sub(r"<[^>]+>", "", html_body)
        excerpt = clean[:150].strip()
        if len(clean) > 150:
            excerpt += "…"

    tag_display = " · ".join(tag_list)
    note_html = (
        "<!DOCTYPE html>\n"
        "<html>\n"
        "<head><meta charset=\"UTF-8\">"
        f"<title>{title}</title></head>\n"
        "<body>\n"
        f"<h1>{title}</h1>\n"
        f"<p class=\"note-meta\"><time>{today}</time>"
        + (f" · {tag_display}" if tag_display else "")
        + "</p>\n"
        + html_body
        + "\n</body>\n</html>\n"
    )

    notes_dir = base / "notes"
    notes_dir.mkdir(exist_ok=True)
    note_path = notes_dir / f"{slug}.html"
    note_path.write_text(note_html, encoding="utf-8")

    notes_js_path = base / "data" / "notes.js"
    notes_index: list[dict] = _load_js_var(notes_js_path, "AUGUR_NOTES") or []
    notes_index.insert(
        0,
        {
            "slug": slug,
            "title": title,
            "date": today,
            "path": f"notes/{slug}.html",
            "tags": tag_list,
            "excerpt": excerpt,
        },
    )
    _save_js_var(notes_js_path, "AUGUR_NOTES", notes_index)

    return f"Created note '{title}' → notes/{slug}.html (index updated)"


def run_mcp() -> None:
    """Start the DocsBot MCP server on stdio (called by `docsbot mcp`)."""
    mcp.run()
