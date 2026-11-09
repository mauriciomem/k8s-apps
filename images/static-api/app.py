"""Static JSON API: returns hard-coded data, no database.

Endpoints:
  GET /health         -> {"status": "ok"}
  GET /quotes         -> all quotes
  GET /quotes/random  -> one random quote
  GET /info           -> pod hostname
"""
import json
import random
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

QUOTES = [
    {"id": 1, "text": "Least privilege is a habit, not a setting."},
    {"id": 2, "text": "If it runs as root, ask why."},
    {"id": 3, "text": "Default deny, then allow what you need."},
    {"id": 4, "text": "Scan the image before you ship it."},
]


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        elif self.path == "/quotes":
            self._send(200, {"quotes": QUOTES})
        elif self.path == "/quotes/random":
            self._send(200, random.choice(QUOTES))
        elif self.path == "/info":
            self._send(200, {"hostname": socket.gethostname()})
        else:
            self._send(404, {"error": "not found"})


if __name__ == "__main__":
    print("static-api listening on :8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
