"""DocsBot MCP server — exposes DocsBot read/write tools to Claude Code sessions."""

from __future__ import annotations

import datetime
import re
from typing import Any

from mcp.server.fastmcp import FastMCP

from docsbot.config import list_projects as _list_projects, project_base
from docsbot.db import ProjectDB, _text_to_html

mcp = FastMCP("docsbot")


def _db(project_id: str) -> ProjectDB | None:
    base = project_base(project_id)
    return ProjectDB.open(base / "db.sqlite") if base else None


def _today() -> str:
    return datetime.date.today().isoformat()


@mcp.tool()
def list_projects() -> str:
    """List all registered DocsBot projects with their IDs, names, and taglines.
    Always call this first to discover valid project_id values.
    """
    projects = _list_projects()
    if not projects:
        return "No projects registered. Open a project folder via the DocsBot dashboard."
    lines = ["Registered DocsBot projects:", ""]
    for p in projects:
        lines += [f"  id      : {p['id']}", f"  name    : {p['name']}",
                  f"  tagline : {p.get('tagline','')}", ""]
    return "\n".join(lines)


@mcp.tool()
def get_project_summary(project_id: str) -> str:
    """Return a concise summary: metadata, task status counts, research counts.

    Args:
        project_id: Project identifier from list_projects.
    """
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found. Run list_projects first."
    meta = db.get_meta()
    tasks = db.list_tasks()
    research = db.list_research()
    notes = db.list_notes()
    status_counts: dict[str, int] = {}
    for t in tasks:
        s = t.get("status", "?")
        status_counts[s] = status_counts.get(s, 0) + 1
    lines = [
        f"Project  : {meta.get('project', project_id)}",
        f"Tagline  : {meta.get('tagline', '(none)')}",
        f"Updated  : {meta.get('last_updated', '?')}",
        "", f"Tasks ({len(tasks)}):",
    ] + [f"  {s:<16} {c}" for s, c in sorted(status_counts.items())] + [
        "", f"Research ({len(research)}):",
    ] + [f"  {r['id']} [{r['status']}] {r['title']}" for r in research] + [
        "", f"Notes    : {len(notes)}",
    ]
    return "\n".join(lines)


@mcp.tool()
def read_file(project_id: str, resource: str = "tasks") -> str:
    """Read project data as formatted text.

    Args:
        project_id: Project identifier from list_projects.
        resource: One of 'tasks', 'research', 'notes', 'meta', 'buckets'.
    """
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found."
    import json
    if resource == "tasks":
        return json.dumps(db.list_tasks(), ensure_ascii=False, indent=2)
    if resource == "research":
        return json.dumps(db.list_research(), ensure_ascii=False, indent=2)
    if resource == "notes":
        return json.dumps(db.list_notes(), ensure_ascii=False, indent=2)
    if resource == "meta":
        return json.dumps(db.get_meta(), ensure_ascii=False, indent=2)
    if resource == "buckets":
        return json.dumps(db.list_buckets(), ensure_ascii=False, indent=2)
    return f"Error: unknown resource '{resource}'. Choose from: tasks, research, notes, meta, buckets."


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
    """Add a new task to the project backlog. ID is auto-generated within the bucket.

    Args:
        project_id: Project identifier from list_projects.
        title: Short, imperative task title.
        description: What needs to be done.
        bucket: P0=CORRECTNESS, P1=VALIDATION, P2=EVIDENCE, P3=PIPELINE, P4=FEATURES, P5=NOTES.
        module: Code module (e.g. 'core', 'infra').
        size: XS, S, M, L, XL.
        effort: Time estimate (e.g. '1 d', '2-3 d').
        note: Additional context.
    """
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found."
    task = db.create_task(title=title, bucket=bucket, module=module, size=size,
                          effort=effort, description=description, note=note)
    return f"Added task {task['id']}: {title}"


@mcp.tool()
def update_todo_status(project_id: str, task_id: str, status: str) -> str:
    """Update the status of a backlog task.

    Args:
        project_id: Project identifier from list_projects.
        task_id: Task ID (e.g. 'P0-01').
        status: 'open', 'in-progress', 'blocked', or 'done'.
    """
    valid = {"open", "in-progress", "blocked", "done"}
    if status not in valid:
        return f"Error: status must be one of {sorted(valid)}."
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found."
    task = db.update_task(task_id, status=status)
    if not task:
        return f"Error: task '{task_id}' not found."
    return f"Updated {task_id} → {status}"


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
    """Add a new research direction. ID is auto-generated (R6, R7, …).

    Args:
        project_id: Project identifier from list_projects.
        title: Research direction title.
        hypothesis: One-sentence hypothesis (without 'Hypothesis:' prefix).
        body: Body text — use double newlines to separate paragraphs.
        kind: ANALYSIS, SAFETY, STATIC, NORMALIZATION, MEASUREMENT, INFRA, FEATURE.
        module: Code module.
        codename: Short uppercase codename (auto-derived if empty).
    """
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found."
    if not codename:
        codename = re.sub(r"[^A-Z0-9]", "", title.upper())[:8]
    paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]
    item = db.create_research(
        title=title, codename=codename, kind=kind, module=module,
        hypothesis=f"Hypothesis: {hypothesis}", body=paragraphs,
    )
    return f"Added research item {item['id']}: {title}"


@mcp.tool()
def add_note(
    project_id: str,
    title: str,
    body: str,
    tags: str = "",
    excerpt: str = "",
) -> str:
    """Create a new note. Plain text paragraphs are converted to HTML automatically.

    Args:
        project_id: Project identifier from list_projects.
        title: Note title.
        body: Note content. Plain text (double newlines = paragraphs) or raw HTML accepted.
        tags: Comma-separated tags (e.g. 'architecture,session-summary').
        excerpt: Short summary (auto-generated if empty).
    """
    db = _db(project_id)
    if not db:
        return f"Error: project '{project_id}' not found."
    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []
    note = db.create_note(
        title=title,
        body=body,  # db.create_note handles text → HTML conversion
        tags=tag_list,
        excerpt=excerpt,
    )
    return f"Created note '{title}' (slug: {note['slug']})"


def run_mcp() -> None:
    """Start the DocsBot MCP server on stdio."""
    mcp.run()
