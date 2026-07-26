# 08 — Production: Fly.io managed deploy, multi-stage Dockerfile, GlitchTip, GDPR, GA4

Covers managed-platform deployment with a slim multi-stage image, S3 storage, GA4 analytics, GlitchTip error reporting, GDPR scaffolding, and CI.

## Prompt

```
/seedkit

Project name: 08-fly-app
Purpose: production app deployed to Fly.io with a slim multi-stage runtime image and S3-compatible object storage.

Settings layout: split.
Database: PostgreSQL.
Postgres location: Postgres-in-Docker (`db` service alongside `redis` and `minio` in `docker-compose.yml`, port `127.0.0.1:5432` published).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Task runner: mise.
Add-ons:
  - redis
  - tasks: Celery
  - storage: S3-compatible (MinIO locally, real S3 in prod)
  - analytics: Google Analytics 4 (GA4)
  - email: anymail (Postmark provider). Install `django-anymail[postmark]`; set `EMAIL_BACKEND = "anymail.backends.postmark.EmailBackend"` only when not DEBUG; gate `POSTMARK_SERVER_TOKEN` from env. Wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`. Console backend stays as the `EMAIL_URL` fallback in dev. (django-mail-auth needs working email to send magic links.) Also include the Anymail webhook URL (`path("anymail/", include("anymail.urls"))`) and `ANYMAIL["WEBHOOK_SECRET"]`.
  - HTML email base template: no.
  - CORS: no.
  - REST API: `django-bolt` **with fast-path settings opt-in** (`uv add django-bolt`). Add `django_bolt` to `INSTALLED_APPS` in `base.py`. Create `config/settings/bolt.py` that imports from `base` and strips `SessionMiddleware`, `MessageMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `WhiteNoiseMiddleware` from `MIDDLEWARE` and `django.contrib.admin`, `django.contrib.sessions`, `django.contrib.messages`, `django.contrib.staticfiles` from `INSTALLED_APPS`; sets `TEMPLATES = []` and `ROOT_URLCONF = 'config.urls_bolt'`. Create `config/urls_bolt.py` (API-only; no admin / accounts). Create an `api` app (`uv run manage.py startapp api`) with `api/api.py` exposing `BoltAPI()`, a single `GET /users/{user_id}` async handler returning a `msgspec.Struct` (`id`, `username`) populated via `await User.objects.aget(id=user_id)`. `runserver`/`gunicorn` keep using `config.settings.local` / `production`; `runbolt` runs against `config.settings.bolt`.
  - Frontend: none.
  - Auth hardening: `django-axes` (yes), 2FA (no).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings
  - CSP via `django-csp`: yes
  - error reporting: GlitchTip via sentry-sdk
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete views
  - CI: GitHub Actions test workflow
  - deploy target: Fly.io managed (use `[processes]` for web + worker + bolt; the `bolt` process runs `manage.py runbolt` with `DJANGO_SETTINGS_MODULE=config.settings.bolt`)
  - production Dockerfile: multi-stage (builder + slim runtime)

Run the foundation + boot check locally. Generate `Dockerfile`, `fly.toml`, `.github/workflows/test.yml`. Verify `docker build .` succeeds and the runtime stage uses `python:3.12-slim-bookworm`.
```

## Boot check

```sh
cd 08-fly-app
docker compose up -d                    # db + redis + minio
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
uv run celery -A config worker -l info &
WORKER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID" "$WORKER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
DJANGO_SETTINGS_MODULE=config.settings.bolt uv run python -c "
from django.conf import settings
assert 'django.contrib.admin' not in settings.INSTALLED_APPS
assert settings.ROOT_URLCONF == 'config.urls_bolt'
assert settings.TEMPLATES == []
"
DJANGO_SETTINGS_MODULE=config.settings.bolt uv run manage.py runbolt --dev --port 8001 &
BOLT_PID=$!
sleep 2
curl -sf http://127.0.0.1:8001/users/1 || true
uv run pyright
docker build --target prod -t 08-fly-app:test .
docker run --rm 08-fly-app:test python --version | grep -q '3\.12'
docker run --rm 08-fly-app:test which uv && echo "uv leaked into runtime image" && exit 1 || true
kill "$RUNSERVER_PID" "$WORKER_PID" "$BOLT_PID"
docker compose down -v
docker rmi 08-fly-app:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,bolt,test}.py`, `config/urls.py`, `config/urls_bolt.py`, `Dockerfile` (multi-stage), `docker-compose.yml` (local services only — `db`, `redis`, `minio`; no `web` / `worker`), `fly.toml`, `mise.toml`, `.github/workflows/test.yml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`. No `Dockerfile.dev`, no `docker-compose.override.yml`.
- `mise.toml` has `[tasks.deploy]` running `fly deploy`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `django-storages[s3]`, `django-mail-auth`, `django-axes`, `django-csp`, `django-bolt`, `msgspec`, `django-anymail[postmark]`, `sentry-sdk`, `gunicorn`. Dev deps include `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `ruff`.

**Settings (split + bolt)**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`. `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `base.py` inside an `except ImportError: pass` guard.
- `config/settings/bolt.py` imports from `base` and strips `SessionMiddleware`, `MessageMiddleware`, `CsrfViewMiddleware`, `AuthenticationMiddleware`, `WhiteNoiseMiddleware` from `MIDDLEWARE`, and `django.contrib.admin`, `django.contrib.sessions`, `django.contrib.messages`, `django.contrib.staticfiles` from `INSTALLED_APPS`. Sets `TEMPLATES = []` and `ROOT_URLCONF = "config.urls_bolt"`.
- `config/urls_bolt.py` contains `urlpatterns: list = []` (BoltAPI auto-discovers; no `.urls` to mount). Does NOT import `django.contrib.admin` or `accounts`.
- Security settings in `production.py` only, including `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`.
- `csp.middleware.CSPMiddleware` in `production.py`'s `MIDDLEWARE` only. `CONTENT_SECURITY_POLICY['DIRECTIVES']['script-src']` includes `https://www.googletagmanager.com` and `https://www.google-analytics.com`. `connect-src` and `img-src` include `https://www.google-analytics.com`. No `'unsafe-inline'` in `script-src`.

**Bolt API**
- `api/api.py` defines `api = BoltAPI()` and a `@api.get("/users/{user_id}")` async handler returning a `msgspec.Struct` populated via `await User.objects.aget(id=user_id)`.
- `INSTALLED_APPS` in `base.py` includes `django_bolt`.

**Auth + analytics + GDPR + Sentry**
- `INSTALLED_APPS` lists `mailauth.contrib.admin` BEFORE `django.contrib.admin`. `MailAuthBackend` in `AUTHENTICATION_BACKENDS`. `accounts/` URL include with `mailauth` namespace.
- `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`. `AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'` set in `production.py`.
- GA4 snippet in `templates/_analytics.html` (or equivalent) using `{{ ANALYTICS_ID }}` from a context processor; included from `templates/base.html`.
- `sentry_sdk.init(...)` called from `production.py` only with `before_send` PII scrubber, `send_default_pii=False`.
- GDPR scaffolding present: `data_export` / `data_delete` views or management commands.

**Deploy artefacts**
- `Dockerfile` is multi-stage and pins `--platform=linux/amd64` on both stages so uv installs django-bolt's published `manylinux2014_x86_64` wheel (no `build-essential`, no source compile — there is no aarch64-linux wheel). `builder` runs `uv sync` on a `ghcr.io/astral-sh/uv:python3.12-*` image; final `prod` stage uses `python:3.12-slim-bookworm` with `/opt/venv/bin` on PATH and no uv binary.
- `fly.toml` has `[processes]` with `web`, `worker`, `bolt`. The `bolt` process sets `DJANGO_SETTINGS_MODULE=config.settings.bolt`. `[env]` sets `PORT` and `DJANGO_BEHIND_PROXY=True`. `DJANGO_ALLOWED_HOSTS` / `DJANGO_SECRET_KEY` / `DATABASE_URL` go via `fly secrets set` per `deploy-managed.md` — do not hardcode in `[env]`. `[deploy] release_command = "python manage.py migrate"` (not `uv run` — the slim runtime has no uv). `[[checks]]` (or service health) hits `/readyz`.
- `[checks]` / `[services.checks]` block in `fly.toml` references `/readyz`.

**Health**
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.
- Anymail webhook URL `path("anymail/", include("anymail.urls"))` wired; `ANYMAIL["WEBHOOK_SECRET"]` set.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
