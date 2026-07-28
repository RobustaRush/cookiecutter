# 06 — django-silk + Django Tasks (DB backend) + GoatCounter + db-safety

Covers django-silk profiling, the Database backend for Django Tasks (no Redis), GoatCounter analytics, and the three db-safety tools: django-zeal (N+1 detection), django-migration-linter (CI audit), django-test-migrations (rollback tests).

## Prompt

```
/django-seedkit

Project name: 06-silk-lab
Purpose: profile a few request paths with django-silk and run a simple background email task on the DB backend.

Settings layout: split.
Database: PostgreSQL.
Postgres location: on the host (use `createdb silk_db`).
Lint with Ruff: yes.
Test runner: pytest (required for django-test-migrations).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: no.
Task runner: none.
Add-ons:
  - debug: django-silk (profiling + `@silk_profile`)
  - tasks: Django Tasks with the Database backend (`django-tasks-db`). Also `uv run manage.py startapp jobs`, register `jobs` in `INSTALLED_APPS`, wire `jobs/apps.py` `ready()` to import `tasks`, and add a sample `@task` to `jobs/tasks.py`.
  - analytics: GoatCounter (self-hosted snippet, env-driven site code)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - HTML email base template: no.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Devcontainer: no.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: yes.
  - Database safety tools: all three —
      - django-zeal: yes
      - django-migration-linter: yes
      - django-test-migrations: yes

Production setup: skip.

Run the foundation, the boot check, start `manage.py db_worker` in a second terminal, enqueue one example task and confirm it runs. Hit a profiled view and confirm the request appears under `/silk/`. Run `uv run manage.py lintmigrations`. Run `uv run pytest` to confirm the test runner is wired (no project-specific tests required — `django-test-migrations` is installed for the user to write migration tests later).
```

## Boot check

```sh
createdb silk_db || true
cd 06-silk-lab
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
uv run manage.py db_worker &
WORKER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID" "$WORKER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/silk/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
uv run manage.py show_urls > /dev/null
uv run manage.py lintmigrations
uv run ruff check .
uv run pytest; rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ]   # exit 5 = no tests collected (empty scaffold)
kill "$RUNSERVER_PID" "$WORKER_PID"
dropdb silk_db
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `pytest.ini` or `[tool.pytest.ini_options]` in `pyproject.toml`, `setup.cfg`, `.env`, `.gitignore`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tasks-db`. Dev deps include `django-silk`, `django-extensions`, `django-zeal`, `django-migration-linter`, `django-test-migrations`, `pytest`, `pytest-django`, `ruff`. NONE of those dev-only packages appear in runtime deps.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `INSTALLED_APPS` in `base.py` does NOT contain `silk`, `django_extensions`, `zeal`, or `django_migration_linter`. Each appears only in `local.py` (or DEBUG-gated single-file).
- `config/settings/local.py` adds `silk`, `django_extensions`, `zeal`, `django_migration_linter` to `INSTALLED_APPS`. Adds `silk.middleware.SilkyMiddleware` and `zeal.middleware.zeal_middleware` to `MIDDLEWARE`. Sets `ZEAL_RAISE_ON_VIOLATION = True`.
- `setup.cfg` has a `[django_migration_linter]` section with `exclude_apps` covering third-party migrations.

**URLs + analytics + tasks + tests**
- `config/urls.py` mounts `silk.urls` only when `silk` is in `INSTALLED_APPS` (or `settings.DEBUG`).
- `templates/base.html` (or analytics partial) renders the GoatCounter snippet, gated on `ANALYTICS_ID` and `ANALYTICS_HOST` from a context processor.
- A registered Django app has `apps.py` with `ready()` importing `tasks`, and a `tasks.py` defining at least one `@task`.
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
