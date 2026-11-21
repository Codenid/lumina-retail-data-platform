import os
import secrets
from pathlib import Path
from urllib.parse import urlparse

import google.auth
import google.auth.transport.requests
import google.oauth2.id_token
import requests
from flask import Flask, Response, jsonify, request, send_from_directory, session

ROOT = Path(__file__).parent / "static"
UPSTREAM = os.environ["UPSTREAM_API"].rstrip("/")
app = Flask(__name__, static_folder=None)
app.secret_key = os.environ.get("LUMINA_SESSION_SECRET", secrets.token_hex(32))
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SECURE=True, SESSION_COOKIE_SAMESITE="Lax")


def configured_users() -> dict[str, str]:
    return {
        os.environ.get("LUMINA_USER_1", ""): os.environ.get("LUMINA_PASSWORD_1", ""),
        os.environ.get("LUMINA_USER_2", ""): os.environ.get("LUMINA_PASSWORD_2", ""),
    }


def is_authenticated() -> bool:
    return bool(session.get("lumina_user"))


@app.post("/auth/login")
def login():
    body = request.get_json(silent=True) or {}
    username = str(body.get("username", "")).strip()
    password = str(body.get("password", ""))
    expected = configured_users().get(username)
    if not expected or not secrets.compare_digest(password, expected):
        return jsonify({"error": "Usuario o clave incorrectos."}), 401
    session.clear()
    session["lumina_user"] = username
    session.permanent = True
    return jsonify({"authenticated": True, "user": username})


@app.post("/auth/logout")
def logout():
    session.clear()
    return jsonify({"authenticated": False})


@app.get("/auth/me")
def me():
    return jsonify({"authenticated": is_authenticated(), "user": session.get("lumina_user")})


def upstream_token() -> str:
    req = google.auth.transport.requests.Request()
    return google.oauth2.id_token.fetch_id_token(req, UPSTREAM)


@app.route("/api/<path:path>", methods=["GET", "OPTIONS"])
def proxy(path):
    if not is_authenticated():
        return jsonify({"error": "Autenticación requerida."}), 401
    if request.method == "OPTIONS":
        return Response(status=204, headers={"Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, OPTIONS", "Access-Control-Allow-Headers": "Content-Type"})
    target = f"{UPSTREAM}/api/{path}"
    response = requests.get(target, params=request.args, headers={"Authorization": f"Bearer {upstream_token()}"}, timeout=30)
    headers = {"Content-Type": response.headers.get("Content-Type", "application/json"), "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*"}
    return Response(response.content, status=response.status_code, headers=headers)


@app.post("/api/chat")
def chat():
    if not is_authenticated():
        return jsonify({"error": "Autenticación requerida."}), 401
    body = request.get_json(silent=True) or {}
    question = str(body.get("message", "")).strip()
    if not question:
        return jsonify({"error": "Escribe una pregunta."}), 400
    project = os.environ.get("VERTEX_PROJECT", "")
    location = os.environ.get("VERTEX_LOCATION", "us-central1")
    model = os.environ.get("VERTEX_MODEL", "gemini-2.0-flash-001")
    if not project:
        return jsonify({"error": "Vertex AI no está configurado."}), 503
    try:
        token = upstream_token()
        context = []
        for endpoint in ("summary", "stock-risk", "forecast", "operations", "maintenance-risks"):
            try:
                result = requests.get(f"{UPSTREAM}/api/v1/{endpoint}", params={"limit": 100}, headers={"Authorization": f"Bearer {token}"}, timeout=8)
                if result.ok:
                    context.append(f"{endpoint}: {result.text[:12000]}")
            except requests.RequestException:
                app.logger.warning("Fuente %s no disponible para el asistente", endpoint)
        context_text = "\n".join(context)
        prompt = ("Eres el asistente de operaciones de Lumina Retail. Responde en español, de forma breve y accionable. "
                  "Usa únicamente la información de los cuatro casos de uso y señala cuando un dato no esté disponible.\n\n"
                  f"Contexto actual:\n{context_text}\n\nPregunta: {question}")
        credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
        credentials.refresh(google.auth.transport.requests.Request())
        vertex_host = "aiplatform.googleapis.com" if location == "global" else f"{location}-aiplatform.googleapis.com"
        url = f"https://{vertex_host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
        response = requests.post(url, headers={"Authorization": f"Bearer {credentials.token}"}, json={"contents": [{"role": "user", "parts": [{"text": prompt}]}]}, timeout=60)
        if not response.ok:
            return jsonify({"error": "Vertex AI no pudo responder."}), 502
        payload = response.json()
        answer = payload["candidates"][0]["content"]["parts"][0]["text"]
        return jsonify({"answer": answer})
    except Exception:
        app.logger.exception("Error en asistente Vertex")
        return jsonify({"error": "No fue posible consultar Vertex AI."}), 502


@app.route("/healthz")
def healthz():
    return {"status": "ok", "proxy": "private-api"}


@app.route("/", defaults={"path": "index.html"})
@app.route("/<path:path>")
def static_files(path):
    if path not in {"index.html", "styles.css", "app.js", "config.js"} and not is_authenticated():
        return jsonify({"error": "Autenticación requerida."}), 401
    candidate = ROOT / path
    if not candidate.exists() or candidate.is_dir():
        path = "index.html"
    return send_from_directory(ROOT, path)
