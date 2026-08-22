# 07 — Production: VPS deploy, SQLite mini-prod, single-stage Dockerfile, Sentry

Covers the SQLite mini-prod path on a single VPS: WAL-tuned `production.py`, separate `cache.sqlite3` for the cache backend, Litestream replication to S3, Caddy + single-stage Dockerfile, security settings, Sentry SaaS error reporting, GitHub Actions test CI.

## Prompt

```
/django-seedkit

Project name: 07-vps-sqlite-saas
Purpose: production-ready SaaS skeleton deployed to a single VPS via docker-compose + Caddy, using the SQLite mini-prod stack (no separate DB / cache / queue server).

Settings layout: split.
Database: SQLite.
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: yes.
Internationalisation (i18n): no.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login + mandatory verification).
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: mise.
Add-ons:
  - cache backend: sqlite (separate `cache.sqlite3` + `CacheRouter` + `DatabaseCache`)
  - tasks: none.
  - storage: WhiteNoise (static), media volume on the VPS host
  - email: SMTP in production, console mailer in local. Use placeholder Postmark variables (`DJANGO_MAIL_HOST=smtp.postmarkapp.com`, `DJANGO_MAIL_PORT=587`, `DJANGO_MAIL_USE_TLS=True`, and token username/password); also wire `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL`, `DJANGO_ADMINS`.
  - HTML email base template: no.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: `django-axes` (yes), 2FA (yes).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings (HSTS, secure cookies, X-Frame, SSL redirect)
  - CSP using Django's built-in CSP support: yes
  - error reporting: Sentry SaaS (sentry-sdk)
  - CI: GitHub Actions test workflow
  - deploy target: VPS (Docker + Caddy)
  - database backups: Litestream replication to S3-compatible storage; do not use `django-dbbackup`
  - production Dockerfile: multi-stage with the Litestream `.deb` installed in the prod stage; ship `litestream.yml` + `entrypoint.sh` that restores the DB on boot, runs migrations, then execs `litestream replicate -exec "gunicorn ..."`
Skip GDPR for this case.

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `Caddyfile`, `litestream.yml`, `entrypoint.sh`, `.github/workflows/test.yml`. Do not actually push to a remote VPS — just verify all artifacts are present and `docker build .` succeeds.
```

## Boot check

```sh
cd 07-vps-sqlite-saas
uv run manage.py migrate
uv run manage.py createcachetable --database cache
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
kill "$RUNSERVER_PID"
! rg -q 'django-csp' pyproject.toml
rg -q 'django.middleware.csp.ContentSecurityPolicyMiddleware' config/settings/production.py
rg -q 'SECURE_CSP' config/settings/production.py
uv run pyright
# Pre-commit hooks on the no-template path: uv-lock + django-upgrade + ruff.
# --files, not --all-files: no per-project .git, so --all-files reaches sibling projects.
PC_FILES="pyproject.toml config/settings/base.py config/urls.py users/models.py"
uv run pre-commit run --files $PC_FILES || true
uv run pre-commit run --files $PC_FILES
docker build --target prod -t 07-vps-sqlite-saas:test .
docker run --rm 07-vps-sqlite-saas:test which gunicorn
docker run --rm 07-vps-sqlite-saas:test which litestream
docker run --rm 07-vps-sqlite-saas:test id -un | grep -q '^django$'
docker rmi 07-vps-sqlite-saas:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `config/routers.py`, `Dockerfile` (multi-stage), `deploy/docker-compose.prod.yml`, `deploy/Caddyfile`, `litestream.yml`, `entrypoint.sh`, `mise.toml`, `.github/workflows/test.yml`, `.pre-commit-config.yaml`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`. No `Dockerfile.dev`, no root `docker-compose.yml` (dev runs on the host; SQLite needs no local services).
- `.pre-commit-config.yaml` declares hook ids `ruff-check`, `ruff-format`, `uv-lock`, `django-upgrade`, `djade`, and `djhtml`. No `rustywind` hook — this project has no Tailwind.
- `mise.toml` has `[tasks.deploy]` running `docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d` and **no** `deploy-migrate` task — the SQLite + Litestream `entrypoint.sh` runs `migrate --noinput` on every boot (`dev-tasks.md` exception).
- `pyproject.toml` runtime deps include `django-environ`, `whitenoise`, `django-allauth[mfa]`, `django-axes`, `sentry-sdk`, `structlog`, `django-structlog`, `gunicorn`. **No** `django-csp`, `psycopg`, `celery`, `redis`, `django-dbbackup`, or a standalone Django Tasks package. Dev deps include `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `ruff`, `pre-commit`.

**Settings split + SQLite mini-prod**
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`; `wsgi.py`/`asgi.py` to `config.settings.production`.
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`. `[tool.pyright]` block in `pyproject.toml`. `django_stubs_ext.monkeypatch()` called from `base.py` inside an `except ImportError: pass` guard.
- `production.py` sets `DATABASES["default"]["OPTIONS"]` with the SQLite mini-prod block: `transaction_mode = "IMMEDIATE"`, `timeout = 5`, and an `init_command` containing `PRAGMA journal_mode=WAL;`, `PRAGMA synchronous=NORMAL;`, `PRAGMA mmap_size=...`, `PRAGMA cache_size=...`.
- `base.py` defines `DATABASES["cache"]` (env-driven path, defaulting under `BASE_DIR`), `CACHES["default"]` using `django.core.cache.backends.db.DatabaseCache` with `LOCATION = "cache_table"`, and `DATABASE_ROUTERS = ["config.routers.CacheRouter"]`. `production.py` adds `DATABASES["cache"]["OPTIONS"] = DATABASES["default"]["OPTIONS"]`. Prod `.env` sets `CACHE_DB_PATH=/data/cache.sqlite3`.
- `config/routers.py` defines `CacheRouter` routing reads/writes/migrations for `app_label == "django_cache"` to the `cache` database.
- Security settings (`SECURE_SSL_REDIRECT`, HSTS, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `CSRF_TRUSTED_ORIGINS`, `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`) live in `production.py` only. `django.middleware.csp.ContentSecurityPolicyMiddleware` and `SECURE_CSP` in `production.py` only — not in `base.py`/`local.py`.
- `WhiteNoiseMiddleware` inserted directly after `SecurityMiddleware` in `MIDDLEWARE`.

**Custom user + auth + MFA**
- `users/models.py` defines `User` extending `AbstractUser`. `AUTH_USER_MODEL = "users.User"`. `users/migrations/0001_initial.py` exists.
- `INSTALLED_APPS` includes `allauth`, `allauth.account`, `allauth.mfa`, `django.contrib.sites`, `axes`. NOT `allauth_2fa` (deprecated).
- `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`.
- `accounts/` URL include in `config/urls.py` mounts both `allauth.urls` and `allauth.mfa.urls`. `MFA_SUPPORTED_TYPES` and `MFA_TOTP_ISSUER` defined. `ACCOUNT_REAUTHENTICATION_REQUIRED = True` in `production.py` only.

**Logging + Sentry**
- `structlog` configured in `base.py`. `LOGGING` at module scope. `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`.
- `sentry_sdk.init(...)` called from `production.py` only; DSN read from env via the gated default.

**Deploy artefacts**
- `Dockerfile` is multi-stage: `builder` on `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` (with `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, `UV_PROJECT_ENVIRONMENT=/opt/venv`, two-step `uv sync`) and `prod` on `python:3.12-slim-bookworm` (`/opt/venv/bin` on PATH, runs as `django` user, installs the Litestream `.deb` via `wget` + `dpkg -i litestream-v0.3.13-linux-${ARCH}.deb`).
- `entrypoint.sh` runs `litestream restore -if-db-not-exists -if-replica-exists /data/site.sqlite3`, then `python manage.py migrate --noinput`, then `createcachetable --database cache`, then `exec litestream replicate -exec "gunicorn config.wsgi --bind 0.0.0.0:8000 --max-requests 1000 --max-requests-jitter 100 --access-logfile -"`. `Dockerfile` `CMD` invokes `entrypoint.sh`.
- `litestream.yml` declares `dbs: [{path: /data/site.sqlite3, replicas: [{type: s3, ...}]}]` reading bucket/endpoint/keys from env.
- `Caddyfile` upstream block uses `health_uri /healthz` (liveness, not `/readyz`), and contains `encode zstd gzip` plus a `request_body` block with `max_size`.
- `deploy/docker-compose.prod.yml` defines an `x-logging` anchor (`max-size`) applied as `logging:` on every service.
- `deploy/docker-compose.prod.yml` defines a single `web` service with `restart: unless-stopped`, mounts a named `sqlite_data:/data` volume, and a container-level healthcheck (python urllib, no curl). **No** `db`, `redis`, or `celery` services. Top-level `volumes:` declares `sqlite_data`.
- `deploy/.env.prod.example` sets `DATABASE_URL=sqlite:////data/site.sqlite3` and lists the Litestream S3 env vars (`S3_BUCKET`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`). Dev `.env` keeps the SQLite default (`BASE_DIR/db.sqlite3`).
- `.github/workflows/test.yml` runs `uv run pytest` against SQLite (no `manage.py migrate` step — `pytest-django` builds the test DB from migrations; no Postgres/Redis services in the workflow). Env block ships `DJANGO_MAIL_HOST=localhost`, a `DATABASE_URL` pointing at a SQLite file, `DJANGO_SECRET_KEY` placeholder, `DJANGO_DEBUG=False`.

**Health**
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
