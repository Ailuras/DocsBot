"""Configuration for DocsBot."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


def default_data_dir() -> Path:
    """Return the default data directory for DocsBot.

    Defaults to the directory containing the installed package
    (~/apps/DocsBot), overridable via DOCSBOT_DATA_DIR env var.
    """
    env = os.getenv("DOCSBOT_DATA_DIR")
    if env:
        return Path(env).expanduser()
    # Package lives at .../DocsBot/src/docsbot/config.py
    return Path(__file__).resolve().parents[2]


def projects_dir() -> Path:
    """Return the projects directory."""
    return default_data_dir() / "projects"


def external_projects_file() -> Path:
    """Return the path to the external projects registry JSON file."""
    return default_data_dir() / "external_projects.json"


def load_external_projects() -> list[dict]:
    """Load the list of externally registered projects.

    Each entry has ``{"id": str, "path": str}`` where ``path`` is the
    absolute path to the docs root folder (containing a ``data/`` subdir).
    Returns an empty list if the file does not exist or cannot be parsed.
    """
    fp = external_projects_file()
    if not fp.exists():
        return []
    try:
        return json.loads(fp.read_text(encoding="utf-8"))
    except Exception:
        return []


def register_external_path(folder: Path) -> dict:
    """Register a folder as an external project.

    Auto-detects ``folder/docs`` as the docs root, falling back to
    ``folder`` itself.  Requires that a ``data/meta.js`` file exists
    inside the resolved docs root.

    Returns a dict with keys ``id``, ``name``, ``tagline``, ``path``.
    Raises ``ValueError`` on any validation failure.
    """
    # 1. Resolve docs root
    docs_root: Path | None = None
    for candidate in (folder / "docs", folder):
        if (candidate / "data" / "meta.js").exists():
            docs_root = candidate
            break

    if docs_root is None:
        raise ValueError(
            f"No data/meta.js found inside '{folder}' or '{folder / 'docs'}'"
        )

    # 2. Derive project id
    project_id = folder.name.lower().replace(" ", "-")

    # 3. Load metadata
    meta = _load_meta(docs_root / "data" / "meta.js")
    name = meta.get("project", folder.name)
    tagline = meta.get("tagline", "")

    # 4. Persist to external_projects.json
    existing = load_external_projects()
    # Replace existing entry with same id, or append
    updated = [e for e in existing if e.get("id") != project_id]
    updated.append({"id": project_id, "path": str(docs_root)})
    fp = external_projects_file()
    fp.parent.mkdir(parents=True, exist_ok=True)
    fp.write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")

    return {"id": project_id, "name": name, "tagline": tagline, "path": str(docs_root)}


def project_base(project_id: str) -> Path | None:
    """Find the docs-root directory for a project by ID.

    Checks local ``projects/``, ``examples/``, and the external registry.
    Returns ``None`` if the project is not found.
    """
    for root in (projects_dir(), default_data_dir() / "examples"):
        candidate = root / project_id
        if candidate.exists() and candidate.is_dir():
            return candidate
    for entry in load_external_projects():
        if entry.get("id") == project_id:
            p = Path(entry["path"])
            if p.exists() and p.is_dir():
                return p
    return None


def list_projects() -> list[dict]:
    """List all projects with their metadata.

    Scans the ``projects/`` directory first; if it is empty or does not exist,
    falls back to ``examples/`` so that a freshly-cloned repo still shows a
    demo project.  External projects (from ``external_projects.json``) are
    appended after the local ones.
    """
    roots = [projects_dir(), default_data_dir() / "examples"]
    local_projects: list[dict] = []
    for root in roots:
        if not root.exists():
            continue
        for entry in sorted(root.iterdir()):
            if not entry.is_dir():
                continue
            meta_path = entry / "data" / "meta.js"
            meta = _load_meta(meta_path) if meta_path.exists() else {}
            local_projects.append({
                "id": entry.name,
                "name": meta.get("project", entry.name),
                "tagline": meta.get("tagline", ""),
                "path": str(entry),
            })
        if local_projects:
            break

    # Append external projects, skipping any whose id already appears locally
    local_ids = {p["id"] for p in local_projects}
    external: list[dict] = []
    for entry in load_external_projects():
        pid = entry.get("id", "")
        if not pid or pid in local_ids:
            continue
        docs_root = Path(entry["path"])
        meta_path = docs_root / "data" / "meta.js"
        meta = _load_meta(meta_path) if meta_path.exists() else {}
        external.append({
            "id": pid,
            "name": meta.get("project", pid),
            "tagline": meta.get("tagline", ""),
            "path": str(docs_root),
        })

    return local_projects + external


def _load_meta(path: Path) -> dict:
    """Extract scalar fields from a meta.js file using regex.

    Works with both JSON-style (quoted keys) and JS-style (unquoted keys)
    object literals, avoiding the fragility of json.loads on JS source.
    """
    try:
        text = path.read_text(encoding="utf-8")
        result: dict = {}
        for field in ("project", "short", "tagline", "description",
                       "last_updated", "doc_number", "repo_url"):
            m = re.search(
                field + r"""\s*:\s*["']([^"'\n]+)["']""",
                text,
            )
            if m:
                result[field] = m.group(1)
        return result
    except Exception:
        return {}
