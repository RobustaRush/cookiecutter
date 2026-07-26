# 03 — Postgres-in-Docker, Django on host, Celery + Beat

Covers the "Postgres in Docker, Django on host" hybrid mode, plus Redis-backed Celery with periodic tasks.

## Prompt

```
/seedkit

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Postgres location: Postgres in Docker (`docker-compose.yml`, port `127.0.0.1:5432` published to the host).
Lint with Ruff: no.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): yes.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Structured logging: no.
Task runner: just.
Add-ons:
  - redis (for Celery)
  - tasks: Celery, with periodic tasks (Celery Beat). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, and add a sample `@shared_task` to `jobs/tasks.py` referenced from `CELERY_BEAT_SCHEDULE`.
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - HTML email base template: no.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.

Production setup: skip.

Ship a `docker-compose.yml` with `db` and `redis` services only. Run the foundation, start the containers, run migrate + createsuperuser, and define one trivial Celery task plus one Beat-scheduled task to prove autodiscovery works.
```

## Boot check

```sh
cd 03-jobs-board
docker compose up -d
docker compose ps
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Confirm Celery autodiscovers without holding a worker open. `import_default_modules`
# forces eager loading — plain `celery_app.tasks` only lists built-in `celery.*` entries.
# Task runner sanity — justfile present.
test -f justfile
uv run python -c "from config import celery_app; celery_app.loader.import_default_modules(); print(sorted(t for t in celery_app.tasks if not t.startswith('celery.')))"
# docker logs must not contain fatal errors:
! docker compose logs db redis 2>&1 | grep -iE 'fatal|panic|traceback'
kill "$RUNSERVER_PID"
docker compose down -v --rmi local
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings.py` (single-file), `config/celery.py`, `config/__init__.py`, `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `django-mail-auth`, `django-redis`. No `ruff`, no `pyright`.
- `.env` sets `DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres` and `REDIS_URL=redis://localhost:6379` (no `/0` — settings append the db number per subsystem).
- `docker-compose.yml` defines services `db` (postgres) and `redis` only — no `web`, no `worker`. Both ports bound to `127.0.0.1` (e.g. `"127.0.0.1:5432:5432"`), not `0.0.0.0`.

**Settings**
- `config/settings.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True` set.
- `CELERY_BROKER_URL` and `CELERY_RESULT_BACKEND` derived from `REDIS_URL` (broker on `/1`, results on `/2`).
- `CELERY_TASK_TIME_LIMIT` and `CELERY_TASK_SOFT_TIME_LIMIT` set (soft < hard).
- `LANGUAGES`, `LOCALE_PATHS`, `LocaleMiddleware` configured (i18n=yes).

**Celery**
- `config/celery.py` defaults `DJANGO_SETTINGS_MODULE` to the production module (mirrors wsgi/asgi). For the single-file layout this is `config.settings`.
- `config/__init__.py` exposes `celery_app`.
- A registered Django app (e.g. `jobs/`) ships `tasks.py` with at least one `@shared_task` (or `@task`) function. `CELERY_BEAT_SCHEDULE` references one of those tasks.

**Auth (mail-auth)**
- `INSTALLED_APPS` lists `mailauth.contrib.admin` BEFORE `django.contrib.admin`, plus `mailauth`. `AUTHENTICATION_BACKENDS` includes `mailauth.backends.MailAuthBackend`.
- `config/urls.py` includes `mailauth.urls` under `accounts/` with the `mailauth` namespace. `/accounts/login/` route resolves.
- Templates under `templates/registration/` exist for the magic-link UI.

**Task runner**
- `justfile` present at project root with at least one target defined.

**Health checks**
- `pages/views.py` (or equivalent) defines `liveness` and `readiness`. `urlpatterns` wires `path('healthz', ...)` and `path('readyz', ...)` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
