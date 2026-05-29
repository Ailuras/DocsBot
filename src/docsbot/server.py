"""DocsBot backend — REST API + static file server."""

from __future__ import annotations

import json
import mimetypes
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from docsbot.config import (
    create_project, default_data_dir, list_projects, project_base,
)
from docsbot.db import ProjectDB

DOCSBOT_DIR = Path(__file__).resolve().parents[2]


def _get_db(project_id: str) -> ProjectDB | None:
    base = project_base(project_id)
    return ProjectDB.open(base / "db.sqlite") if base else None


def _json(h: BaseHTTPRequestHandler, data: Any, status: int = 200) -> None:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    h.send_response(status)
    h.send_header("Content-Type", "application/json; charset=utf-8")
    h.send_header("Access-Control-Allow-Origin", "*")
    h.send_header("Content-Length", str(len(body)))
    h.send_header("Connection", "close")
    h.end_headers()
    h.wfile.write(body)


def _file(h: BaseHTTPRequestHandler, content: bytes, ctype: str, status: int = 200) -> None:
    h.send_response(status)
    h.send_header("Content-Type", ctype)
    h.send_header("Content-Length", str(len(content)))
    h.end_headers()
    h.wfile.write(content)


def _body(h: BaseHTTPRequestHandler) -> dict:
    n = int(h.headers.get("Content-Length", 0))
    return json.loads(h.rfile.read(n).decode("utf-8")) if n else {}


def _static(h: BaseHTTPRequestHandler, path: str) -> bool:
    safe = path.lstrip("/")
    if ".." in safe:
        return False
    tp = DOCSBOT_DIR / "templates" / safe
    if tp.exists() and tp.is_file():
        ctype = mimetypes.guess_type(str(tp))[0] or "application/octet-stream"
        _file(h, tp.read_bytes(), ctype)
        return True
    return False


def _parse_project_path(path: str) -> tuple[str, list[str]]:
    """Split /api/projects/{id}/... → (id, rest_parts)."""
    tail = path[len("/api/projects/"):]
    parts = tail.split("/")
    pid = urllib.parse.unquote(parts[0])
    rest = [urllib.parse.unquote(p) for p in parts[1:]]
    return pid, rest


def make_handler():
    class H(BaseHTTPRequestHandler):
        def log_message(self, *_: Any) -> None:
            pass

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods",
                             "GET, POST, PUT, PATCH, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            p = parsed.path
            qs = urllib.parse.parse_qs(parsed.query)
            db: ProjectDB | None = None
            try:
                if p == "/api/projects":
                    _json(self, {"projects": list_projects()})
                    return

                if p.startswith("/api/projects/"):
                    pid, rest = _parse_project_path(p)
                    db = _get_db(pid)
                    if db is None:
                        _json(self, {"error": "Project not found"}, 404); return

                    if rest == ["meta"]:
                        _json(self, db.get_meta()); return
                    if rest == ["buckets"]:
                        _json(self, db.list_buckets()); return
                    if rest == ["tasks"]:
                        bucket = qs.get("bucket", [None])[0]
                        status = qs.get("status", [None])[0]
                        _json(self, db.list_tasks(bucket=bucket, status=status)); return
                    if len(rest) == 2 and rest[0] == "tasks":
                        t = db.get_task(rest[1])
                        _json(self, t) if t else _json(self, {"error": "Not found"}, 404); return
                    if rest == ["research"]:
                        _json(self, db.list_research(status=qs.get("status",[None])[0])); return
                    if len(rest) == 2 and rest[0] == "research":
                        r = db.get_research(rest[1])
                        _json(self, r) if r else _json(self, {"error": "Not found"}, 404); return
                    if rest == ["notes"]:
                        _json(self, db.list_notes()); return
                    if len(rest) == 2 and rest[0] == "notes":
                        n = db.get_note(rest[1])
                        _json(self, n) if n else _json(self, {"error": "Not found"}, 404); return
                    if rest == ["weeks"]:
                        _json(self, db.list_weeks()); return
                    if len(rest) == 2 and rest[0] == "weeks":
                        _json(self, db.get_week(rest[1])); return
                    if rest == ["features"]:
                        wid = qs.get("week_id", [None])[0]
                        _json(self, db.list_features(week_id=wid)); return

                if _static(self, p):
                    return

                if not p.startswith("/api/"):
                    ip = DOCSBOT_DIR / "templates" / "index.html"
                    _file(self, ip.read_bytes(), "text/html; charset=utf-8") if ip.exists() \
                        else _json(self, {"error": "Frontend not found"}, 500)
                    return

                self.send_error(404, "Not Found")
            except Exception as e:
                _json(self, {"error": str(e)}, 500)
            finally:
                if db is not None:
                    db.close()

        def do_POST(self) -> None:
            p = urllib.parse.urlparse(self.path).path
            db: ProjectDB | None = None
            try:
                if p == "/api/projects":
                    body = _body(self)
                    name = body.get("name", "").strip()
                    if not name:
                        _json(self, {"error": "name is required"}, 400); return
                    try:
                        project = create_project(
                            name=name,
                            tagline=body.get("tagline", ""),
                            repo_path=body.get("repo_path", ""),
                        )
                        _json(self, {"project": project}, 201)
                    except ValueError as exc:
                        _json(self, {"error": str(exc)}, 400)
                    return

                if p.startswith("/api/projects/"):
                    pid, rest = _parse_project_path(p)
                    db = _get_db(pid)
                    if db is None:
                        _json(self, {"error": "Project not found"}, 404); return
                    body = _body(self)
                    if rest == ["tasks"]:
                        _json(self, db.create_task(**body), 201); return
                    if rest == ["research"]:
                        _json(self, db.create_research(**body), 201); return
                    if rest == ["notes"]:
                        _json(self, db.create_note(**body), 201); return
                    if rest == ["features"]:
                        _json(self, db.create_feature(**body), 201); return
                    if rest == ["meta"]:
                        db.update_meta(body); _json(self, db.get_meta()); return

                self.send_error(404, "Not Found")
            except Exception as e:
                _json(self, {"error": str(e)}, 500)
            finally:
                if db is not None:
                    db.close()

        def do_PUT(self) -> None:
            p = urllib.parse.urlparse(self.path).path
            db: ProjectDB | None = None
            try:
                if p.startswith("/api/projects/"):
                    pid, rest = _parse_project_path(p)
                    db = _get_db(pid)
                    if db is None:
                        _json(self, {"error": "Project not found"}, 404); return
                    body = _body(self)
                    if len(rest) == 2 and rest[0] == "tasks":
                        t = db.update_task(rest[1], **body)
                        _json(self, t) if t else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "research":
                        r = db.update_research(rest[1], **body)
                        _json(self, r) if r else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "notes":
                        n = db.update_note(rest[1], **body)
                        _json(self, n) if n else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "weeks":
                        _json(self, db.upsert_week(rest[1], **body)); return
                    if len(rest) == 2 and rest[0] == "features":
                        f = db.update_feature(rest[1], **body)
                        _json(self, f) if f else _json(self, {"error": "Not found"}, 404); return
                self.send_error(404, "Not Found")
            except Exception as e:
                _json(self, {"error": str(e)}, 500)
            finally:
                if db is not None:
                    db.close()

        def do_DELETE(self) -> None:
            p = urllib.parse.urlparse(self.path).path
            db: ProjectDB | None = None
            try:
                if p.startswith("/api/projects/"):
                    pid, rest = _parse_project_path(p)
                    db = _get_db(pid)
                    if db is None:
                        _json(self, {"error": "Project not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "tasks":
                        ok = db.delete_task(rest[1])
                        _json(self, {"ok": ok}) if ok else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "research":
                        ok = db.delete_research(rest[1])
                        _json(self, {"ok": ok}) if ok else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "notes":
                        ok = db.delete_note(rest[1])
                        _json(self, {"ok": ok}) if ok else _json(self, {"error": "Not found"}, 404); return
                    if len(rest) == 2 and rest[0] == "features":
                        ok = db.delete_feature(rest[1])
                        _json(self, {"ok": ok}) if ok else _json(self, {"error": "Not found"}, 404); return
                self.send_error(404, "Not Found")
            except Exception as e:
                _json(self, {"error": str(e)}, 500)
            finally:
                if db is not None:
                    db.close()

    return H


def _pid_file() -> Path:
    return default_data_dir() / "server.pid"


def _server_info_file() -> Path:
    return default_data_dir() / "server.info"


def run_server(host: str = "127.0.0.1", port: int = 8766) -> None:
    import signal, sys
    handler = make_handler()
    server = ThreadingHTTPServer((host, port), handler)
    pid_path = _pid_file()
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(str(os.getpid()))
    info_path = _server_info_file()
    info_path.write_text(json.dumps({"pid": os.getpid(), "host": host, "port": port}))

    def _stop(signum, frame):
        pid_path.unlink(missing_ok=True)
        _server_info_file().unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"DocsBot running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        pid_path.unlink(missing_ok=True)
        _server_info_file().unlink(missing_ok=True)


def _kill_by_port(port: int) -> bool:
    import subprocess
    try:
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"], capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0 and result.stdout.strip():
            killed = False
            for pid_str in result.stdout.strip().split():
                try:
                    os.kill(int(pid_str.strip()), 15)
                    killed = True
                except (ValueError, ProcessLookupError, PermissionError):
                    continue
            return killed
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return False


def stop_server(port: int = 8766) -> bool:
    pid_path = _pid_file()
    stopped = False
    if pid_path.exists():
        try:
            pid = int(pid_path.read_text().strip())
            os.kill(pid, 15)
            stopped = True
        except (ValueError, ProcessLookupError, PermissionError):
            pass
        pid_path.unlink(missing_ok=True)
    _server_info_file().unlink(missing_ok=True)
    if stopped:
        return True
    return _kill_by_port(port)
