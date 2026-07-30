# 03 — Postgres-in-Docker, Django in a container, Celery + Beat

Covers the container dev loop: `manage.py`, the Celery worker and Beat all run as compose services, `db` and `redis` publish no host port, and the task runner drives the stack instead of `uv run`. Also the only case where i18n meets the dev image — `compilemessages` needs GNU gettext, which the slim base does not carry.

## Prompt

```
/django-seedkit

Project name: 03-jobs-board
Purpose: job board with background email notifications and a daily digest.

Settings layout: single file.
Database: PostgreSQL.
Postgres location: Postgres in Docker (`docker-compose.yml`).
Dev loop: `manage.py` in a `web` container via `docker compose`, not on the host.
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
  - Cache backend: redis (`django-redis`, cache on `/0`).
  - tasks: Celery, with periodic tasks (Celery Beat). Also add a `jobs` app (`manage.py startapp jobs`), register `jobs` in `INSTALLED_APPS`, and add a sample `@shared_task` to `jobs/tasks.py` referenced from `CELERY_BEAT_SCHEDULE`.
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

Ship a `docker-compose.yml` with `web`, `worker`, `beat`, `db` and `redis` services, where only `web` publishes a host port. Run the foundation, build and start the stack, run migrate + createsuperuser through `web`, and define one trivial Celery task plus one Beat-scheduled task to prove autodiscovery works.
```

## Boot check

```sh
cd 03-jobs-board
docker compose up -d --build --wait     # web + worker + beat + db + redis
docker compose ps
docker compose exec -T web python manage.py migrate
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: web never came up"; docker compose logs web; docker compose down -v --rmi local; exit 1; }
curl -sf http://127.0.0.1:8000/accounts/login/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Neither backing service may publish a host port — web reaches them by service name.
! docker compose config | grep -q 'published: "5432"'
! docker compose config | grep -q 'published: "6379"'
# The host venv must be masked inside the container. Unmasked, a tree-walking
# management command descends into it — compilemessages finds >1000 stray .po files.
docker compose exec -T web sh -c 'test -d /app/.venv && test -z "$(ls -A /app/.venv)"'
# Task runner sanity — justfile present, and its bodies drive the container.
test -f justfile
grep -q 'docker compose' justfile
# i18n=yes: the dev stage must install GNU gettext. Django checks for msgfmt before it
# looks for .po files, so this fails on a gettext-less image even with no translations yet.
docker compose exec -T web python manage.py compilemessages
# Confirm Celery autodiscovers. `import_default_modules` forces eager loading —
# plain `celery_app.tasks` only lists built-in `celery.*` entries.
docker compose exec -T web python -c "from config import celery_app; celery_app.loader.import_default_modules(); print(sorted(t for t in celery_app.tasks if not t.startswith('celery.')))"
# worker and beat must still be up, not crash-looped behind a passing web service.
docker compose ps --services --filter status=running | grep -qx worker
docker compose ps --services --filter status=running | grep -qx beat
# docker logs must not contain fatal errors:
! docker compose logs db redis web worker beat 2>&1 | grep -iE 'fatal|panic|traceback'
docker compose down -v --rmi local
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings.py` (single-file), `config/celery.py`, `config/__init__.py`, `docker-compose.yml`, `Dockerfile`, `.dockerignore`, `.env`, `.env.example`, `.gitignore`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `celery[redis]` (or `celery` + `redis`), `django-mail-auth`, `django-redis`. No `ruff`, no `pyright`.
- `.env` addresses both services by name: `DATABASE_URL=postgres://postgres:postgres@db:5432/postgres` and `REDIS_URL=redis://redis:6379` (no `/0` — settings append the db number per subsystem). No `localhost` in either.
- `docker-compose.yml` defines `web`, `worker`, `beat`, `db` and `redis`. Only `web` has a `ports:` block, bound to `127.0.0.1` (e.g. `"127.0.0.1:8000:8000"`), not `0.0.0.0`. `worker` and `beat` build the same `target: dev` and carry `celery -A config worker` / `celery -A config beat` as their `command:`.
- Every service that bind-mounts `.:/app` also carries the `- /app/.venv` anonymous volume. Without it a tree-walking management command descends into the host venv.
- `CACHES` uses `django_redis.cache.RedisCache` on `f"{REDIS_URL}/0"`, and `django-redis` is a runtime dep.

**Dev image** (`Production setup: skip`, so the dev stage is the whole file)
- `Dockerfile` has a `dev` target, sets `UV_PROJECT_ENVIRONMENT=/opt/venv` and puts `/opt/venv/bin` on `PATH`, and installs `gettext` (i18n=yes). No `prod` stage, no `gunicorn` dep.
- `.dockerignore` lists `.venv/`.

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
- `justfile` present at project root with at least one target defined. Its `manage.py` bodies go through `docker compose exec … web`, not `uv run` — the host has no venv to run them in.

**Health checks**
- `pages/views.py` (or equivalent) defines `liveness` and `readiness`. `urlpatterns` wires `path('healthz', ...)` and `path('readyz', ...)` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
