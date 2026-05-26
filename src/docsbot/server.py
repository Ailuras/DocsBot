"""DocsBot backend — REST API + static file server."""

from __future__ import annotations

import json
import mimetypes
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from docsbot.config import default_data_dir, list_projects, projects_dir

DOCSBOT_DIR = Path(__file__).resolve().parents[2]


def _project_base(project_id: str) -> Path | None:
    """Find a project directory in projects/ or examples/. Return None if not found."""
    for root in (projects_dir(), default_data_dir() / "examples"):
        candidate = root / project_id
        if candidate.exists() and candidate.is_dir():
            return candidate
    return None


def _json_response(handler: BaseHTTPRequestHandler, data: Any, status: int = 200) -> None:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Connection", "close")
    handler.end_headers()
    handler.wfile.write(body)


def _file_response(handler: BaseHTTPRequestHandler, content: bytes, content_type: str, status: int = 200) -> None:
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(content)))
    handler.end_headers()
    handler.wfile.write(content)


def _read_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length == 0:
        return {}
    body = handler.rfile.read(content_length).decode("utf-8")
    return json.loads(body)


def _serve_static(handler: BaseHTTPRequestHandler, path: str, project_id: str | None = None) -> bool:
    """Serve a static file from the templates or project directory. Return True if served."""
    # Security: prevent directory traversal
    safe_path = path.lstrip("/")
    if ".." in safe_path:
        return False

    # Try project directory first if project_id given
    if project_id:
        base = _project_base(project_id)
        if base:
            project_path = base / safe_path
            if project_path.exists() and project_path.is_file():
                content = project_path.read_bytes()
                ctype = mimetypes.guess_type(str(project_path))[0] or "application/octet-stream"
                _file_response(handler, content, ctype)
                return True

    # Try templates (SPA assets)
    template_path = DOCSBOT_DIR / "templates" / safe_path
    if template_path.exists() and template_path.is_file():
        content = template_path.read_bytes()
        ctype = mimetypes.guess_type(str(template_path))[0] or "application/octet-stream"
        _file_response(handler, content, ctype)
        return True

    return False


def make_handler():
    class DocsBotHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            pass

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            try:
                # API: list projects
                if path == "/api/projects":
                    _json_response(self, {"projects": list_projects()})
                    return

                # API: read project data file (or any project file)
                if path.startswith("/api/projects/"):
                    parts = path[len("/api/projects/"):].split("/")
                    if len(parts) >= 3 and parts[1] == "data":
                        project_id = urllib.parse.unquote(parts[0])
                        filename = urllib.parse.unquote("/".join(parts[2:]))
                        base = _project_base(project_id)
                        if not base:
                            _json_response(self, {"error": "Project not found"}, 404)
                            return
                        # Try data/ dir first, then project root (for notes/ etc.)
                        candidates = [
                            base / "data" / filename,
                            base / filename,
                        ]
                        for project_path in candidates:
                            if project_path.exists() and project_path.is_file():
                                text = project_path.read_text(encoding="utf-8")
                                _json_response(self, {"content": text})
                                return
                        _json_response(self, {"error": "File not found"}, 404)
                        return

                # Root: serve SPA
                if path == "/" or path == "/index.html":
                    index_path = DOCSBOT_DIR / "templates" / "index.html"
                    if index_path.exists():
                        html = index_path.read_text(encoding="utf-8")
                        _file_response(self, html.encode("utf-8"), "text/html; charset=utf-8")
                    else:
                        _json_response(self, {"error": "Frontend not built"}, 500)
                    return

                # Static assets (check project first, then templates)
                projects = list_projects()
                if projects and _serve_static(self, path, projects[0]["id"]):
                    return
                if _serve_static(self, path):
                    return

                self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

        def do_POST(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            try:
                # API: save project data file
                if path.startswith("/api/projects/"):
                    parts = path[len("/api/projects/"):].split("/")
                    if len(parts) >= 3 and parts[1] == "data":
                        project_id = urllib.parse.unquote(parts[0])
                        filename = urllib.parse.unquote("/".join(parts[2:]))
                        # Save only to projects/ (never to examples/)
                        project_path = projects_dir() / project_id / "data" / filename
                        body = _read_body(self)
                        content = body.get("content", "")
                        project_path.parent.mkdir(parents=True, exist_ok=True)
                        project_path.write_text(content, encoding="utf-8")
                        _json_response(self, {"success": True, "file": filename})
                        return

                self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

    return DocsBotHandler


def _pid_file() -> Path:
    return default_data_dir() / "server.pid"


def run_server(host: str = "127.0.0.1", port: int = 18765) -> None:
    """Start the DocsBot HTTP server."""
    handler = make_handler()
    server = ThreadingHTTPServer((host, port), handler)

    pid_path = _pid_file()
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(str(os.getpid()))

    print(f"DocsBot running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        server.shutdown()
        pid_path.unlink(missing_ok=True)


def stop_server() -> bool:
    """Stop the running DocsBot server."""
    pid_path = _pid_file()
    if not pid_path.exists():
        return False
    try:
        pid = int(pid_path.read_text().strip())
        os.kill(pid, 15)  # SIGTERM
        pid_path.unlink(missing_ok=True)
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        pid_path.unlink(missing_ok=True)
        return False
