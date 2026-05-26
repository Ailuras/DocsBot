"""Configuration for DocsBot."""

from __future__ import annotations

import json
import os
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


def list_projects() -> list[dict]:
    """List all projects with their metadata.

    Scans the ``projects/`` directory first; if it is empty or does not exist,
    falls back to ``examples/`` so that a freshly-cloned repo still shows a
    demo project.
    """
    roots = [projects_dir(), default_data_dir() / "examples"]
    for root in roots:
        if not root.exists():
            continue
        projects = []
        for entry in sorted(root.iterdir()):
            if not entry.is_dir():
                continue
            meta_path = entry / "data" / "meta.js"
            meta = _load_meta(meta_path) if meta_path.exists() else {}
            projects.append({
                "id": entry.name,
                "name": meta.get("project", entry.name),
                "tagline": meta.get("tagline", ""),
                "path": str(entry),
            })
        if projects:
            return projects
    return []


def _load_meta(path: Path) -> dict:
    """Parse the window.AUGUR_META object from a meta.js file."""
    try:
        text = path.read_text(encoding="utf-8")
        # Find the JSON-like object after window.AUGUR_META =
        start = text.find("window.AUGUR_META = {")
        if start == -1:
            return {}
        # Extract the object by bracket matching
        brace_start = text.find("{", start)
        brace_count = 0
        end = brace_start
        for i, ch in enumerate(text[brace_start:], start=brace_start):
            if ch == "{":
                brace_count += 1
            elif ch == "}":
                brace_count -= 1
                if brace_count == 0:
                    end = i
                    break
        obj_text = text[brace_start:end + 1]
        return json.loads(obj_text)
    except Exception:
        return {}
