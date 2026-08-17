# 09 — Production: GitHub Actions SSH deploy, Bugsink, Umami

Covers the GitHub-Actions-over-SSH deploy path, self-hosted Bugsink for error reporting, Umami analytics, GDPR scaffolding, and CI.

## Prompt

```
/django-seedkit

Project name: 09-ssh-deploy
Purpose: production app deployed to a remote host over SSH from GitHub Actions, using self-hosted services.

Settings layout: split.
Database: PostgreSQL.
Postgres location: Postgres-in-Docker (`db` + `redis` services in `docker-compose.yml`, port `127.0.0.1:5432` published).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Task runner: mise.
Add-ons:
  - redis
  - tasks: none.
  - analytics: Umami (self-hosted, env-driven website ID and host)
  - email: none (this project does not send transactional mail and the test verifies the skip path).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings
  - CSP via `django-csp`: yes
  - error reporting: Bugsink (self-hosted, sentry-sdk DSN)
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete
  - CI: GitHub Actions test workflow
  - deploy: GitHub Actions deploy via SSH (rsync + remote `docker compose pull && up -d`)
  - database backups via `django-dbbackup`: yes (self-managed host — no native backup service)
  - production Dockerfile: multi-stage — uv builder → `python:3.12-slim-bookworm` runtime

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `.github/workflows/test.yml`, `.github/workflows/deploy.yml`. Do not actually deploy — verify all artifacts are present, `docker build .` succeeds, and the deploy workflow references `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`.
```

## Boot check

```sh
cd 09-ssh-deploy
docker compose up -d                    # db + redis only
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
docker build --target prod -t 09-ssh-deploy:test .
kill "$RUNSERVER_PID"
docker compose down -v
docker rmi 09-ssh-deploy:test
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings/{base,local,production,test}.py`, `Dockerfile` (multi-stage), `docker-compose.yml` (local services only — `db`, `redis`; no `web` / `worker`), `deploy/docker-compose.prod.yml`, `deploy/.env.prod.example`, `mise.toml`, `.github/workflows/{test.yml,deploy.yml}`, `.env`, `.env.example`, `.dockerignore`, `.gitignore`. No `Dockerfile.dev`, no `docker-compose.override.yml`.
- `mise.toml` has `[tasks.deploy-migrate]` and `[tasks.deploy]` (with `depends = ["deploy-migrate"]`) targeting `deploy/docker-compose.prod.yml`, both passing `--env-file deploy/.env.prod`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-csp`, `django-dbbackup`, `django-storages[s3]` (or `boto3`), `sentry-sdk`, `structlog`, `django-structlog`, `gunicorn`. Dev deps include `pytest`, `pytest-django`, `ruff`.
- `pyproject.toml` does NOT list `django-axes`, `django-allauth`, `django-mail-auth`, or anymail/email packages — auth = none, email = none.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- Security settings (`SECURE_SSL_REDIRECT`, HSTS, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `CSRF_TRUSTED_ORIGINS`, `SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]`) live in `production.py` only.
- `csp.middleware.CSPMiddleware` and `CONTENT_SECURITY_POLICY` in `production.py` only. `script-src` includes the Umami host (resolved from env at runtime). No `'unsafe-inline'` in `script-src`.
- `INSTALLED_APPS` in `base.py` does NOT contain `axes`, `allauth`. `dbbackup` is added only inside the `if not DEBUG:` block in `production.py`.
- `production.py` `if not DEBUG:` block adds `dbbackup` to `INSTALLED_APPS`, sets `DBBACKUP_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"` and `DBBACKUP_STORAGE_OPTIONS` reading bucket/key/secret from env. `DBBACKUP_BUCKET` listed in `.env.example`.

**Logging + Sentry/Bugsink**
- `structlog` configured in `base.py`. `LOGGING` at module scope. `django_structlog.middlewares.RequestMiddleware` in `MIDDLEWARE` directly after `AuthenticationMiddleware`. `django_structlog` in `INSTALLED_APPS`.
- `sentry_sdk.init(...)` called from `production.py` only with `before_send` PII scrubber, `send_default_pii=False`. DSN read from env.

**Analytics + GDPR**
- Umami snippet in `templates/_analytics.html` (or equivalent), gated on `ANALYTICS_ID` and `ANALYTICS_HOST` from a context processor. Included from `templates/base.html`.
- GDPR scaffolding: `data_export` / `data_delete` views or management commands present.

**Deploy artefacts**
- `deploy/.env.prod.example` ships every var the prod compose references, including `DJANGO_SETTINGS_MODULE=config.settings.production`, `DJANGO_ALLOWED_HOSTS=example.com,localhost,127.0.0.1` (localhost+127.0.0.1 for the in-container healthcheck), `DJANGO_BEHIND_PROXY=True`, `POSTGRES_PASSWORD`, `GITHUB_REPOSITORY`.
- `.github/workflows/deploy.yml` uses `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`, `secrets.GHCR_TOKEN`. A `test` job runs `./.github/workflows/test.yml` (`uses:`) and the `deploy` job has `needs: test`. `docker/build-push-action` tags both `:latest` and `:${{ github.sha }}`. The SSH script exports `GITHUB_REPOSITORY="${{ github.repository }}"` and `IMAGE_TAG="${{ github.sha }}"` before `compose pull`, and runs `docker image prune -f` only after the health-wait passes. Every `docker compose` invocation passes `--env-file deploy/.env.prod`. `concurrency: group: deploy` set.
- Inherited `deploy/docker-compose.prod.yml` `web` image is `ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest}`.
- `docker/build-push-action` step has `target: prod` (matching the `prod` stage in `references/docker.md`).
- The container healthcheck in `deploy/docker-compose.prod.yml` uses python urllib (no curl dependency).
- `.github/workflows/test.yml` has a `workflow_call:` trigger (the deploy gate calls it) and runs `check --deploy`, `makemigrations --check --dry-run`, and pytest — no standalone `migrate` step. Env block ships `REDIS_URL=redis://localhost:6379`, `DJANGO_SECRET_KEY` placeholder, `DJANGO_DEBUG=False`, and dbbackup placeholders (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DBBACKUP_BUCKET`) so `check --deploy` against `production` settings loads.

**Health**
- `pages/views.py` (or equivalent — `config/views.py` is fine) defines `liveness` / `readiness`; `path('healthz', ...)` and `path('readyz', ...)` in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
