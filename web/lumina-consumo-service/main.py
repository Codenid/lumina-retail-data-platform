import os
from pathlib import Path
from urllib.parse import urlparse

import google.auth.transport.requests
import google.oauth2.id_token
import requests
from flask import Flask, Response, request, send_from_directory

ROOT = Path(__file__).parent / "static"
UPSTREAM = os.environ["UPSTREAM_API"].rstrip("/")
app = Flask(__name__, static_folder=None)


def upstream_token() -> str:
    req = google.auth.transport.requests.Request()
    return google.oauth2.id_token.fetch_id_token(req, UPSTREAM)


@app.route("/api/<path:path>", methods=["GET", "OPTIONS"])
def proxy(path):
    if request.method == "OPTIONS":
        return Response(status=204, headers={"Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Allow-Headers": "Content-Type"})
    target = f"{UPSTREAM}/api/{path}"
    response = requests.get(target, params=request.args, headers={"Authorization": f"Bearer {upstream_token()}"}, timeout=30)
    headers = {"Content-Type": response.headers.get("Content-Type", "application/json"), "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"}
    return Response(response.content, status=response.status_code, headers=headers)


@app.route("/healthz")
def healthz():
    return {"status": "ok", "proxy": "private-api"}


@app.route("/", defaults={"path": "index.html"})
@app.route("/<path:path>")
def static_files(path):
    candidate = ROOT / path
    if not candidate.exists() or candidate.is_dir():
        path = "index.html"
    return send_from_directory(ROOT, path)
