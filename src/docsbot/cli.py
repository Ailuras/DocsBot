"""DocsBot CLI entry point."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import typer
from rich.console import Console

from docsbot.config import default_data_dir, list_projects, projects_dir
from docsbot.server import run_server, stop_server

app = typer.Typer(help="DocsBot — interactive notebook manager for project docs")
console = Console()


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address"),
    port: int = typer.Option(18765, help="Port"),
    daemon: bool = typer.Option(False, help="Run in background"),
    stop: bool = typer.Option(False, help="Stop the running server"),
) -> None:
    """Start or stop the DocsBot web server."""
    if stop:
        stopped = stop_server()
        if stopped:
            console.print("[green]DocsBot stopped.[/green]")
        else:
            console.print("[yellow]DocsBot is not running.[/yellow]")
        raise typer.Exit(0)

    if daemon:
        pid = os.fork()
        if pid > 0:
            console.print(f"[green]DocsBot running in background (pid {pid}).[/green]")
            raise typer.Exit(0)
        os.setsid()
        pid = os.fork()
        if pid > 0:
            sys.exit(0)

        log_dir = default_data_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / "server.log"
        sys.stdout.flush()
        sys.stderr.flush()
        with open(log_path, "a+") as f:
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())

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

    if running:
        console.print("[green]DocsBot: RUNNING[/green]")
    else:
        console.print("[yellow]DocsBot: STOPPED[/yellow]")

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
    source: str = typer.Option("", help="Path to existing docs/ directory to import"),
) -> None:
    """Create a new project notebook."""
    project_path = projects_dir() / name
    if project_path.exists():
        console.print(f"[red]Project '{name}' already exists.[/red]")
        raise typer.Exit(1)

    project_path.mkdir(parents=True)
    (project_path / "data").mkdir()
    (project_path / "notes").mkdir()
    (project_path / "assets").mkdir()

    # Create default meta.js
    meta_path = project_path / "data" / "meta.js"
    meta_path.write_text(
        f'window.AUGUR_META = {{\n'
        f'  project: "{name}",\n'
        f'  short: "{name}",\n'
        f'  tagline: "Project notebook",\n'
        f'  description: "",\n'
        f'  last_updated: "",\n'
        f'  doc_number: "NB-001",\n'
        f'  repo_url: "",\n'
        f'  stale_days: 14,\n'
        f'  pages: [\n'
        f'    {{ id: "index", label: "Overview", path: "index.html" }},\n'
        f'    {{ id: "research", label: "Research", path: "research.html" }},\n'
        f'    {{ id: "backlog", label: "Backlog", path: "backlog.html" }},\n'
        f'    {{ id: "notes", label: "Notes", path: "notes.html" }},\n'
        f'  ],\n'
        f'  stages: [],\n'
        f'  external_links: [],\n'
        f'}};\n',
        encoding="utf-8"
    )

    # Create empty data files
    for fname in ["research.js", "backlog.js", "roadmap.js", "changelog.js", "notes.js"]:
        (project_path / "data" / fname).write_text(f"// {fname}\n", encoding="utf-8")

    if source:
        src = Path(source).expanduser()
        if src.exists():
            import shutil
            for item in src.iterdir():
                dst = project_path / item.name
                if item.is_dir():
                    if dst.exists():
                        shutil.rmtree(dst)
                    shutil.copytree(item, dst)
                else:
                    shutil.copy2(item, dst)
            console.print(f"[green]Project '{name}' created with imported data from {src}.[/green]")
        else:
            console.print(f"[yellow]Source path not found: {src}. Created empty project.[/yellow]")
    else:
        console.print(f"[green]Project '{name}' created.[/green]")

    console.print(f"[dim]Path: {project_path}[/dim]")


@app.command()
def lint(
    project: str = typer.Option("", help="Project name to lint (default: all)"),
) -> None:
    """Run cross-reference lint on project data."""
    from docsbot.config import _load_meta

    targets = []
    if project:
        p = projects_dir() / project
        if p.exists():
            targets.append(p)
        else:
            console.print(f"[red]Project '{project}' not found.[/red]")
            raise typer.Exit(1)
    else:
        targets = [p for p in projects_dir().iterdir() if p.is_dir()]

    import subprocess
    for p in targets:
        data_dir = p / "data"
        if not data_dir.exists():
            continue
        meta = _load_meta(data_dir / "meta.js")
        name = meta.get("project", p.name)
        console.print(f"\n[bold]{name}[/bold]")
        # Run node --check on data files
        for f in data_dir.glob("*.js"):
            result = subprocess.run(
                ["node", "--check", str(f)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                console.print(f"  [red]✗ {f.name} — syntax error[/red]")
            else:
                console.print(f"  [green]✓ {f.name}[/green]")


if __name__ == "__main__":
    app()
