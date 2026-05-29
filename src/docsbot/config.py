"""DocsBot project registry."""

from __future__ import annotations

import os
import re
from pathlib import Path


def default_data_dir() -> Path:
    env = os.getenv("DOCSBOT_DATA_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".docsbot"


def projects_dir() -> Path:
    return default_data_dir() / "projects"


def project_base(project_id: str) -> Path | None:
    """Return the directory containing db.sqlite for *project_id*, or None."""
    candidate = projects_dir() / project_id
    if (candidate / "db.sqlite").exists():
        return candidate
    return None


def _slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9_-]", "", name.lower().replace(" ", "-"))


def create_project(name: str, tagline: str = "", repo_path: str = "") -> dict:
    """Create a new project in ~/.docsbot/projects/{id}/db.sqlite.

    Raises ValueError if the name is invalid or the project already exists.
    """
    from docsbot.db import ProjectDB

    project_id = _slugify(name)
    if not project_id:
        raise ValueError("Invalid project name — use letters, numbers, dashes.")

    project_path = projects_dir() / project_id
    if (project_path / "db.sqlite").exists():
        raise ValueError(f"Project '{project_id}' already exists.")

    project_path.mkdir(parents=True, exist_ok=True)
    meta: dict[str, str] = {"project": name, "tagline": tagline}
    if repo_path:
        meta["repo_path"] = repo_path

    ProjectDB.create(project_path / "db.sqlite", meta=meta)
    return {"id": project_id, "name": name, "tagline": tagline, "path": str(project_path)}


def list_projects() -> list[dict]:
    """Return all projects from ~/.docsbot/projects/."""
    from docsbot.db import ProjectDB

    result: list[dict] = []
    if not projects_dir().exists():
        return result
    for entry in sorted(projects_dir().iterdir()):
        if not entry.is_dir():
            continue
        db_path = entry / "db.sqlite"
        if not db_path.exists():
            continue
        db = ProjectDB.open(db_path)
        if not db:
            continue
        with db:
            meta = db.get_meta()
        result.append({
            "id": entry.name,
            "name": meta.get("project", entry.name),
            "tagline": meta.get("tagline", ""),
            "path": str(entry),
        })
    return result
