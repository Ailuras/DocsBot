"""DocsBot project registry."""

from __future__ import annotations

import json
import os
from pathlib import Path


def default_data_dir() -> Path:
    env = os.getenv("DOCSBOT_DATA_DIR")
    if env:
        return Path(env).expanduser()
    return Path(__file__).resolve().parents[2]


def projects_dir() -> Path:
    return default_data_dir() / "projects"


def external_projects_file() -> Path:
    return default_data_dir() / "external_projects.json"


def load_external_projects() -> list[dict]:
    fp = external_projects_file()
    if not fp.exists():
        return []
    try:
        return json.loads(fp.read_text(encoding="utf-8"))
    except Exception:
        return []


def project_base(project_id: str) -> Path | None:
    """Return the directory containing db.sqlite for *project_id*, or None."""
    candidate = projects_dir() / project_id
    if (candidate / "db.sqlite").exists():
        return candidate
    for entry in load_external_projects():
        if entry.get("id") == project_id:
            p = Path(entry["path"])
            if (p / "db.sqlite").exists():
                return p
    return None


def register_external_path(folder: Path) -> dict:
    """Register an external folder as a DocsBot project.

    Detects ``folder/docs`` as the docs root, falling back to ``folder``.
    Requires ``db.sqlite`` to exist inside the resolved root.
    Raises ``ValueError`` on validation failure.
    """
    from docsbot.db import ProjectDB

    docs_root: Path | None = None
    for candidate in (folder / "docs", folder):
        if (candidate / "db.sqlite").exists():
            docs_root = candidate
            break
    if docs_root is None:
        raise ValueError(
            f"No db.sqlite found in '{folder}' or '{folder / 'docs'}'. "
            "Run `docsbot migrate` on this folder first."
        )

    project_id = folder.name.lower().replace(" ", "-")
    db = ProjectDB.open(docs_root / "db.sqlite")
    meta = db.get_meta() if db else {}

    existing = load_external_projects()
    updated = [e for e in existing if e.get("id") != project_id]
    updated.append({"id": project_id, "path": str(docs_root)})
    fp = external_projects_file()
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "id": project_id,
        "name": meta.get("project", folder.name),
        "tagline": meta.get("tagline", ""),
        "path": str(docs_root),
    }


def list_projects() -> list[dict]:
    """Return all projects (local first, then external)."""
    from docsbot.db import ProjectDB

    result: list[dict] = []
    seen_ids: set[str] = set()

    # Local projects
    if projects_dir().exists():
        for entry in sorted(projects_dir().iterdir()):
            if not entry.is_dir():
                continue
            db_path = entry / "db.sqlite"
            if not db_path.exists():
                continue
            db = ProjectDB.open(db_path)
            if not db:
                continue
            meta = db.get_meta()
            seen_ids.add(entry.name)
            result.append({
                "id": entry.name,
                "name": meta.get("project", entry.name),
                "tagline": meta.get("tagline", ""),
                "path": str(entry),
            })

    # External projects
    for entry in load_external_projects():
        pid = entry.get("id", "")
        if not pid or pid in seen_ids:
            continue
        p = Path(entry["path"])
        db = ProjectDB.open(p / "db.sqlite")
        if not db:
            continue
        meta = db.get_meta()
        result.append({
            "id": pid,
            "name": meta.get("project", pid),
            "tagline": meta.get("tagline", ""),
            "path": str(p),
        })

    return result
