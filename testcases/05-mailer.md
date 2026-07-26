# 05 — django-orbit debug dashboard + Mailpit

Covers the django-orbit observability dashboard (with MCP) and the Mailpit dev mail catcher.

## Prompt

```
/seedkit

Project name: 05-orbit-demo
Purpose: scratch project to exercise django-orbit and verify outbound mail flows are captured.

Settings layout: single file.
Database: SQLite.
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: no.
Task runner: none.
Add-ons:
  - debug: django-orbit (observability dashboard + MCP)
  - email: console backend in local, plus Mailpit running in Docker for richer inspection
  - HTML email base template + `send_test_email` command: yes. Also `uv run manage.py startapp mailer`, register `mailer` in `INSTALLED_APPS`, and put the command under `mailer/management/commands/`.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.
Run the foundation + boot check. Spin up Mailpit via a one-service `docker-compose.yml`, point Django at SMTP `localhost:1025`, send the test mail with `manage.py send_test_email`, and confirm it appears in Mailpit's UI on `:8025`.
```

## Boot check

```sh
cd 05-orbit-demo
docker compose up -d mailpit
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/orbit/ > /dev/null
curl -sf http://127.0.0.1:8025/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Send the test mail (text + HTML alternative) and verify Mailpit captured it.
uv run manage.py send_test_email to@example.com
sleep 1
TOTAL=$(curl -sf http://127.0.0.1:8025/api/v1/messages | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"])')
test "$TOTAL" -ge 1
uv run ruff check .
! docker compose logs mailpit 2>&1 | grep -iE 'fatal|panic'
kill "$RUNSERVER_PID"
docker compose down -v --rmi local
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings.py`, `config/urls.py`, `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`.
- `pyproject.toml` runtime deps include `django-environ`. Dev deps include `django-orbit[mcp]`, `ruff`. `[tool.ruff]` block present.
- `docker-compose.yml` defines a single `mailpit` service exposing 1025 (SMTP) and 8025 (UI) on localhost.
- `.env` has `EMAIL_URL=smtp://localhost:1025` (uv-on-host hits the published port, not the docker hostname).

**Settings**
- `config/settings.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `EMAIL_URL`, `DEFAULT_FROM_EMAIL`, `SERVER_EMAIL` set via `env.email_url(...)` / `env(...)` with the gated-default idiom.
- `LOGGING` is at module scope (NOT inside `if DEBUG:`); `if DEBUG:` block only appends the orbit handler.
- `if DEBUG:` block adds `"orbit"` to `INSTALLED_APPS` and inserts `"orbit.middleware.OrbitMiddleware"` at MIDDLEWARE index 1 (after `SecurityMiddleware`, not before).

**HTML email**
- Files present: `templates/email/base.html` (table layout, inline `style=` attributes, `{% block content %}`), `templates/email/test.html` (extends `email/base.html`), `mailer/management/commands/send_test_email.py`.
- The command builds `EmailMultiAlternatives` and calls `attach_alternative(..., "text/html")` — not `send_mail`.
- `templates/email/base.html` contains no Tailwind utility classes and no `<style>` block.

**URLs + health**
- `config/urls.py` mounts `orbit.urls` only when `settings.DEBUG`.
- `pages/views.py` (or equivalent) defines `liveness` / `readiness`. `path('healthz', ...)` and `path('readyz', ...)` in `urlpatterns` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
