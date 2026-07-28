# 04 — ASGI + channels, S3 storage, Django-Tasks (RQ), devcontainer

Covers ASGI + django-channels (WebSockets with channels-redis layer), S3-compatible object storage, the Django Tasks API with the Redis Queue backend, and a uv-on-host devcontainer.

## Prompt

```
/django-seedkit

Project name: 04-media-vault
Purpose: media-heavy app where uploads land in S3, processing runs as Redis-queued background tasks, and clients subscribe over WebSockets for status updates.

Settings layout: split.
Database: PostgreSQL.
Request handling: asgi+channels.
Postgres location: Postgres-in-Docker (`db` service in `docker-compose.yml`, port `127.0.0.1:5432` published).
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: none.
Add-ons:
  - redis
  - storage: S3-compatible (use MinIO in local Compose; configure via env)
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, wire `jobs/apps.py` `ready()` to import `tasks`, and add a sample `@task` to `jobs/tasks.py`.
  - real-time channel layer: `channels-redis` (reuse the same Redis service). Add an `EchoConsumer` (`AsyncJsonWebsocketConsumer`) that echoes received JSON back to the sender, routed at `/ws/echo/` in `config/routing.py`. Wire `config/asgi.py` with `ProtocolTypeRouter` + `AllowedHostsOriginValidator` + `AuthMiddlewareStack`.
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - HTML email base template: no.
  - CORS: yes.
  - REST API: `django-modern-rest` with the `msgspec` + `openapi` extras (`uv add 'django-modern-rest[msgspec,openapi]'`). Create an `api` app (`uv run manage.py startapp api`) with a single `MediaController` exposing `POST /api/media/` that accepts `{ "filename": str, "size": int }` (msgspec.Struct) and returns `{ "uid": uuid, "filename": str }`. Wire the `Router` from `api/urls.py` into `config/urls.py` under the `api` namespace. Do NOT add `dmr` to `INSTALLED_APPS`.
  - Frontend: none.
  - Devcontainer: yes.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.

Production setup: skip.

Generate `docker-compose.yml` with services `db`, `redis`, `minio` (local services only — Django, the rqworker, and uvicorn run on the host). Run the foundation, `docker compose up -d`, `uv run uvicorn config.asgi:application --reload --host 0.0.0.0` (HTTP + WS share one process in dev — `manage.py runserver` doesn't upgrade WebSockets), `uv run manage.py rqworker default` in a separate terminal, migrate, createsuperuser, and confirm a sample task enqueues and a WebSocket round-trip works.
```

## Boot check

```sh
cd 04-media-vault
docker compose up -d                    # db + redis + minio only
uv run manage.py migrate
uv run manage.py createsuperuser --noinput || true
# Start uvicorn on the host in the background — runserver doesn't upgrade WS.
uv run uvicorn config.asgi:application --host 0.0.0.0 --port 8000 &
UVICORN_PID=$!
uv run manage.py rqworker default &
WORKER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: uvicorn never came up"; kill "$UVICORN_PID" "$WORKER_PID"; exit 1; }
curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png","size":42}' > /dev/null
! curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png"}' > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# WebSocket round-trip — uses the `websockets` lib (already a transitive
# dep of uvicorn[standard]). Connects, sends one message, expects it
# back. Times out at 5s.
uv run python -c "
import asyncio, json, websockets

async def main():
    # AllowedHostsOriginValidator requires an Origin header; the Python
    # websockets client doesn't send one by default.
    async with websockets.connect('ws://127.0.0.1:8000/ws/echo/', origin='http://localhost') as ws:
        await ws.send(json.dumps({'text': 'ping'}))
        reply = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert reply == {'text': 'ping'}, reply

asyncio.run(main())
"
uv run ruff check .
uv run pyright
kill "$UVICORN_PID" "$WORKER_PID"
docker compose down -v
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production}.py`, `config/asgi.py`, `config/routing.py`, `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`. No `Dockerfile.dev` (dev runs on the host).
- `docker-compose.yml` defines local services only — `db`, `redis`, `minio`. No `web` and no `worker` service: Django + rqworker + uvicorn run on the host via `uv run …`. Named volumes for `pgdata` and `miniodata`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tasks`, `django-tasks-rq`, `django-storages[s3]` (or `boto3`), `django-cors-headers`, `django-modern-rest[msgspec,openapi]`, `channels`, `channels-redis`, `daphne`, `uvicorn`, `gunicorn`, `pyjwt`, `structlog`, `django-structlog`. Dev deps include `ruff`, `pyright`, `django-stubs`, `django-stubs-ext`.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `config/settings/base.py` inside an `except ImportError: pass` guard.
- `STORAGES["default"]` resolves to `S3Boto3Storage` when `AWS_STORAGE_BUCKET_NAME` is set; falls back to `FileSystemStorage` when empty.
- `LOGGING` is at module scope (not inside `if DEBUG:`), with `json` and `console` formatters, `console` chosen when `DEBUG`.
- `INSTALLED_APPS` includes `daphne` and `channels`. `ASGI_APPLICATION = "config.asgi.application"`. `CHANNEL_LAYERS["default"]["BACKEND"]` = `"channels_redis.core.RedisChannelLayer"` with `CONFIG` `hosts` built from `REDIS_URL` + the `/4` database (the channel layer's slot — cache is `/0`, RQ is `/3`).
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`. `config/asgi.py` defaults to `config.settings.production`. `config/wsgi.py` remains at the `startproject` default (unchanged) — the deploy loads `asgi.py`, not `wsgi.py`.

**ASGI + channels**
- `config/asgi.py` constructs `ProtocolTypeRouter({"http": django_asgi_app, "websocket": AllowedHostsOriginValidator(AuthMiddlewareStack(URLRouter(websocket_urlpatterns)))})` per `references/realtime.md`. `django.setup()` is called before importing `config.routing`.
- `config/routing.py` defines `websocket_urlpatterns` containing one `path("ws/echo/", EchoConsumer.as_asgi())` entry.
- A consumer module (e.g. `jobs/consumers.py` or `realtime/consumers.py`) defines `EchoConsumer(AsyncJsonWebsocketConsumer)` with at least `connect` (awaits `self.accept()`) and `receive_json` (echoes the same JSON back via `self.send_json`).

**REST API**
- `INSTALLED_APPS` does NOT contain `dmr`.
- `api/` app with `controllers.py`, `schemas.py`, `urls.py`. `MediaController` typed with `Body[MediaCreate]` and a return type. Router mounted at `/api/` in `config/urls.py`.

**Logging**
- `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`. `pyproject.toml` runtime deps include `django-structlog`.

**Tasks**
- `INSTALLED_APPS` includes `django_rq` and `django_tasks` (`django_tasks_rq` is a backend module, not an app). `RQ_QUEUES` defined; `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}` at module scope (not inside `RQ_QUEUES`).
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task`.

**CORS + Devcontainer + Health**
- `corsheaders` in `INSTALLED_APPS`; `corsheaders.middleware.CorsMiddleware` BEFORE `CommonMiddleware`.
- `.devcontainer/devcontainer.json` parseable JSON: `"image"` points at a Python devcontainer image (e.g. `mcr.microsoft.com/devcontainers/python:3.12-bookworm`), `"features"` includes the uv feature, `"postCreateCommand"` runs `uv sync --frozen`, `forwardPorts` includes `8000`, `python.defaultInterpreterPath` points at `${containerWorkspaceFolder}/.venv/bin/python`. No secrets / DB passwords inline.
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` and `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
