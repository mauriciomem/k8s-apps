"""Tiny JSON API backed by PostgreSQL.

Endpoints:
  GET  /api/health  -> liveness, does not touch the DB
  GET  /api/info    -> app name and pod hostname
  GET  /api/items   -> list items from the DB
  POST /api/items   -> add an item, body: {"name": "..."}

Configuration (environment variables):
  APP_NAME, DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

APP_NAME = os.getenv("APP_NAME", "cks-lab-app")
DSN = (
    f"host={os.getenv('DB_HOST', 'database')} "
    f"port={os.getenv('DB_PORT', '5432')} "
    f"dbname={os.getenv('DB_NAME', 'app')} "
    f"user={os.getenv('DB_USER', 'app')} "
    f"password={os.getenv('DB_PASSWORD', '')} "
    "connect_timeout=3"
)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/health":
            self._send(200, {"status": "ok"})
        elif self.path == "/api/info":
            self._send(200, {"app": APP_NAME, "hostname": socket.gethostname()})
        elif self.path == "/api/items":
            try:
                with psycopg.connect(DSN) as conn:
                    rows = conn.execute(
                        "SELECT id, name FROM items ORDER BY id"
                    ).fetchall()
                self._send(200, {"items": [{"id": r[0], "name": r[1]} for r in rows]})
            except Exception as exc:  # DB down, blocked by a NetworkPolicy, etc.
                self._send(503, {"error": f"database unavailable: {exc}"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/items":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            name = json.loads(self.rfile.read(length) or b"{}").get("name", "").strip()
        except (ValueError, AttributeError):
            self._send(400, {"error": "invalid JSON"})
            return
        if not name:
            self._send(400, {"error": "field 'name' is required"})
            return
        try:
            with psycopg.connect(DSN) as conn:
                row = conn.execute(
                    "INSERT INTO items (name) VALUES (%s) RETURNING id", (name,)
                ).fetchone()
            self._send(201, {"id": row[0], "name": name})
        except Exception as exc:
            self._send(503, {"error": f"database unavailable: {exc}"})


if __name__ == "__main__":
    print(f"{APP_NAME} listening on :8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
