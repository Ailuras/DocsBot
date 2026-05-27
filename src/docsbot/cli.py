"""DocsBot CLI entry point."""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import typer
from rich.console import Console

from docsbot.config import default_data_dir, list_projects, projects_dir, _slugify
from docsbot.server import run_server, stop_server

app = typer.Typer(help="DocsBot — interactive notebook manager for project docs")
console = Console()


def _start_daemon(host: str, port: int) -> None:
    log_dir = default_data_dir() / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "server.log"
    with open(log_path, "a") as log_file:
        proc = subprocess.Popen(
            [sys.executable, "-m", "docsbot.cli", "serve",
             "--host", host, "--port", str(port)],
            stdout=log_file, stderr=log_file,
            stdin=subprocess.DEVNULL, start_new_session=True,
        )
    console.print(f"[green]DocsBot started → http://{host}:{port}[/green]")
    console.print(f"[dim]pid {proc.pid} · log: {log_path}[/dim]")


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(8766, help="Port"),
    daemon: bool = typer.Option(False, "-d", "--daemon", help="Run in background"),
    stop: bool = typer.Option(False, "--stop", help="Stop the background server"),
    restart: bool = typer.Option(False, "--restart", help="Restart the background server"),
) -> None:
    """Start, stop, or restart the DocsBot web server.

    \b
    Examples:
      uv run docsbot serve            # foreground — Ctrl-C to quit
      uv run docsbot serve -d         # start in background
      uv run docsbot serve --stop     # stop background server
      uv run docsbot serve --restart  # restart background server
    """
    if stop and restart:
        console.print("[red]--stop and --restart are mutually exclusive.[/red]")
        raise typer.Exit(1)
    if stop:
        stopped = stop_server(port=port)
        console.print("[yellow]DocsBot stopped.[/yellow]" if stopped
                      else "[yellow]DocsBot is not running.[/yellow]")
        raise typer.Exit(0)
    if restart:
        if stop_server(port=port):
            console.print("[yellow]DocsBot stopped.[/yellow]")
            time.sleep(0.8)
        _start_daemon(host, port)
        raise typer.Exit(0)
    if daemon:
        _start_daemon(host, port)
        raise typer.Exit(0)
    run_server(host=host, port=port)


@app.command()
def status() -> None:
    """Show DocsBot status and registered projects."""
    pid_path = default_data_dir() / "server.pid"
    running = False
    if pid_path.exists():
        try:
            pid = int(pid_path.read_text().strip())
            os.kill(pid, 0)
            running = True
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    console.print("[green]DocsBot: RUNNING[/green]" if running
                  else "[yellow]DocsBot: STOPPED[/yellow]")
    projects = list_projects()
    if projects:
        console.print(f"\n[bold]Projects ({len(projects)}):[/bold]")
        for p in projects:
            console.print(f"  • {p['name']} — {p['tagline'] or '(no tagline)'}")
    else:
        console.print("\n[yellow]No projects found.[/yellow]")
        console.print(f"[dim]Projects dir: {projects_dir()}[/dim]")


@app.command()
def init(
    name: str = typer.Argument(..., help="Project name (directory name)"),
    demo: bool = typer.Option(False, "--demo", help="Seed with demo data"),
) -> None:
    """Create a new project notebook."""
    from docsbot.db import ProjectDB, seed_demo

    project_path = projects_dir() / name
    if (project_path / "db.sqlite").exists():
        console.print(f"[red]Project '{name}' already exists.[/red]")
        raise typer.Exit(1)

    project_path.mkdir(parents=True, exist_ok=True)
    db = ProjectDB.create(
        project_path / "db.sqlite",
        meta={
            "project": name,
            "short": name,
            "tagline": "Project notebook",
            "description": "",
            "last_updated": "",
            "doc_number": "NB-001",
            "repo_url": "",
            "stale_days": "14",
        },
    )

    if demo:
        seed_demo(db)
        console.print(f"[green]Project '{name}' created with demo data.[/green]")
    else:
        console.print(f"[green]Project '{name}' created.[/green]")

    console.print(f"[dim]Path: {project_path}[/dim]")


@app.command()
def migrate(
    folder: str = typer.Argument(..., help="Path to project folder (or its docs/ dir)"),
    project_name: str = typer.Option("", "--name", help="Override project name"),
) -> None:
    """Migrate a JS-based project to SQLite.

    Reads existing data/*.js files and creates db.sqlite alongside them.

    \b
    Examples:
      uv run docsbot migrate /Users/you/MyProject
      uv run docsbot migrate /Users/you/MyProject/docs --name myproject
    """
    import json5  # type: ignore[import]
    import re as re_
    from docsbot.db import ProjectDB

    folder_path = Path(folder).expanduser().resolve()

    # Find docs root
    docs_root: Path | None = None
    for candidate in (folder_path / "docs", folder_path):
        if (candidate / "data" / "meta.js").exists():
            docs_root = candidate
            break
    if docs_root is None:
        console.print(f"[red]No data/meta.js found in '{folder_path}' or its docs/ subfolder.[/red]")
        raise typer.Exit(1)

    def read_js_var(path: Path, var_name: str):
        if not path.exists():
            return None
        text = path.read_text(encoding="utf-8")
        m = re_.search(rf'\bwindow\.{re_.escape(var_name)}\s*=\s*', text)
        if not m:
            return None
        start = m.end()
        depth = 0
        pos = start
        in_str = None
        escape_next = False
        while pos < len(text):
            c = text[pos]
            if escape_next:
                escape_next = False; pos += 1; continue
            if c == '\\' and in_str:
                escape_next = True; pos += 1; continue
            if in_str:
                if c == in_str: in_str = None
            else:
                if c in ('"', "'"): in_str = c
                elif c in ('{', '['): depth += 1
                elif c in ('}', ']'):
                    depth -= 1
                    if depth == 0: pos += 1; break
            pos += 1
        try:
            return json5.loads(text[start:pos])
        except Exception:
            return None

    data_dir = docs_root / "data"
    meta_raw = read_js_var(data_dir / "meta.js", "AUGUR_META") or {}
    backlog = read_js_var(data_dir / "backlog.js", "AUGUR_BACKLOG") or []
    buckets = read_js_var(data_dir / "backlog.js", "AUGUR_BACKLOG_BUCKETS") or []
    research = read_js_var(data_dir / "research.js", "AUGUR_RESEARCH") or []
    notes_index = read_js_var(data_dir / "notes.js", "AUGUR_NOTES") or []

    # Determine project name and target db path in ~/.docsbot/projects/
    name = project_name or meta_raw.get("project", folder_path.name)
    project_id = _slugify(name)
    project_path = projects_dir() / project_id
    db_path = project_path / "db.sqlite"
    if db_path.exists():
        console.print(f"[yellow]db.sqlite already exists at {db_path}. Delete it first to re-migrate.[/yellow]")
        raise typer.Exit(1)
    project_path.mkdir(parents=True, exist_ok=True)

    console.print(f"Migrating [bold]{name}[/bold] from {docs_root} ...")

    db = ProjectDB.create(db_path, meta={
        "project": name,
        "short": meta_raw.get("short", name),
        "tagline": meta_raw.get("tagline", ""),
        "description": meta_raw.get("description", ""),
        "last_updated": meta_raw.get("last_updated", ""),
        "doc_number": meta_raw.get("doc_number", ""),
        "repo_url": meta_raw.get("repo_url", ""),
        "stale_days": str(meta_raw.get("stale_days", 14)),
        "repo_path": str(folder_path),
    })

    # Migrate custom buckets
    if buckets:
        db._conn.executemany(
            "INSERT OR REPLACE INTO buckets (p, label, descr) VALUES (?, ?, ?)",
            [(b.get("p",""), b.get("label",""), b.get("desc", b.get("descr",""))) for b in buckets],
        )
        db._conn.commit()

    # Migrate tasks
    task_count = 0
    for t in backlog:
        fields = t.get("fields") or {}
        db.create_task(
            task_id=t.get("id"),
            title=t.get("title", "(no title)"),
            bucket=t.get("bucket", "P0"),
            module=t.get("module", ""),
            size=t.get("size", "M"),
            effort=t.get("effort", ""),
            description=fields.get("input", t.get("description", "")),
            output=fields.get("output", ""),
            acceptance=fields.get("accept", ""),
            note=fields.get("note", ""),
            serves=t.get("serves", []),
            status=t.get("status", "open"),
            date_added=t.get("date_added", ""),
        )
        task_count += 1

    # Migrate research
    research_count = 0
    for r in research:
        db.create_research(
            research_id=r.get("id"),
            title=r.get("title", "(no title)"),
            codename=r.get("codename", ""),
            kind=r.get("kind", "ANALYSIS"),
            module=r.get("module", ""),
            hypothesis=r.get("hypothesis", ""),
            body=r.get("body", []),
            depends_on=r.get("depends_on", []),
            status=r.get("status", "open"),
            date_added=r.get("date_added", ""),
        )
        research_count += 1

    # Migrate notes (read HTML files if they exist)
    note_count = 0
    notes_dir = docs_root / "notes"
    for n in notes_index:
        slug = n.get("slug", "")
        title = n.get("title", "(no title)")
        date = n.get("date", "")
        path_rel = n.get("path", "")
        tags = n.get("tags", [])
        excerpt = n.get("excerpt", "")

        body_html = ""
        if path_rel:
            note_file = docs_root / path_rel
            if not note_file.exists():
                note_file = notes_dir / Path(path_rel).name
            if note_file.exists():
                raw = note_file.read_text(encoding="utf-8")
                m = re_.search(r'<body[^>]*>([\s\S]*)</body>', raw, re_.IGNORECASE)
                body_html = m.group(1).strip() if m else raw

        db.create_note(
            slug=slug or None,
            title=title,
            body_html=body_html,
            tags=tags,
            excerpt=excerpt,
            date=date,
        )
        note_count += 1

    console.print(f"  [green]✓[/green] {task_count} tasks")
    console.print(f"  [green]✓[/green] {research_count} research items")
    console.print(f"  [green]✓[/green] {note_count} notes")
    console.print(f"[bold green]Migration complete → {db_path}[/bold green]")
    console.print(f"\n[dim]Project '{project_id}' is now available in DocsBot.[/dim]")


@app.command()
def mcp() -> None:
    """Run DocsBot as an MCP server (stdio transport).

    \b
    Mount in Claude Code by adding to ~/.claude/.mcp.json:
      {
        "mcpServers": {
          "docsbot": {
            "command": "uv",
            "args": ["run", "--project", "/path/to/DocsBot", "docsbot", "mcp"]
          }
        }
      }
    """
    from docsbot.mcp_server import run_mcp
    run_mcp()


if __name__ == "__main__":
    app()
