# 02 — Split settings, Postgres on host, WhiteNoise + SMTP, Tailwind CSS + Stripe billing

Covers split settings layout, host Postgres, Ruff, WhiteNoise statics, SMTP email, `django-tailwind-cli` frontend integration, and Stripe billing (raw SDK — Checkout session, Customer Portal, webhook handler).

## Prompt

```
/seedkit

Project name: 02-shop
Purpose: small e-commerce site with admin and SMTP transactional email.

Settings layout: split (`config/settings/base.py`, `local.py`, `production.py`).
Database: PostgreSQL.
Postgres location: on the host (use `createdb` for the project DB).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login, mandatory email verification, no social providers).
Structured logging: no.
Task runner: mise.
Add-ons:
  - storage: WhiteNoise for static files (no media volume yet)
  - email: SMTP (console backend in local, SMTP in production)
  - HTML email base template: no.
  - CORS: no.
  - REST API: none.
  - Frontend: `tailwind-cli` (custom 404/403/500 templates: yes; DaisyUI: yes; favicon: yes — agent-drawn SVG). Also add a `pages` app with an `IndexView(TemplateView)` wired at `/`. Its `index.html` must include `text-blue-600` and `text-4xl` (utility check) and a `<button class="btn btn-primary">` (DaisyUI check) — concrete grep targets for the integration tests below.
  - SEO (meta/OG tags + sitemap): yes. The sitemap lists the `pages` index URL.
  - Auth hardening: `django-axes` (yes), 2FA (no).
  - Billing: `stripe` raw SDK.
  - Health check endpoints: yes.
  - `robots.txt`: yes.
  - `django-extensions`: no.
  - Browser auto-reload: yes (`django-browser-reload`).

Production setup: VPS (Docker + Caddy). Use a multi-stage `Dockerfile` (uv builder → `python:3.12-slim-bookworm` runtime).

Assume Postgres is already running locally on port 5432 with user `postgres` / password `postgres`. Create database `shop_db` if missing (Postgres identifiers can't start with a digit, so use a clean name). Run the foundation + boot check, then run `python manage.py tailwind build` once so the CSS asset exists, and verify the index page returns the Tailwind-styled HTML.
```

## Boot check

```sh
createdb shop_db || true
cd 02-shop
uv run manage.py tailwind build
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/ | grep -q 'text-blue-600'
CSS_URL=$(curl -sf http://127.0.0.1:8000/ | grep -oE 'href="[^"]*tailwind[^"]*\.css[^"]*"' | head -1 | sed 's/href="//;s/"//')
test -n "$CSS_URL"
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.text-blue-600'
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.btn'
curl -sf http://127.0.0.1:8000/ | grep -q 'data-theme='
# django-browser-reload middleware injects its script into DEBUG HTML responses.
curl -sf http://127.0.0.1:8000/ | grep -q '__reload__'
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
curl -sf http://127.0.0.1:8000/robots.txt | grep -q 'User-agent: \*'
curl -sf http://127.0.0.1:8000/ | grep -q 'favicon.svg'
curl -sf http://127.0.0.1:8000/static/favicon.svg | grep -q '<svg'
curl -sf http://127.0.0.1:8000/ | grep -q 'property="og:title"'
curl -sf http://127.0.0.1:8000/sitemap.xml | grep -q '<urlset'
uv run ruff check .
uv run pyright
# Task runner sanity — mise.toml present.
test -f mise.toml
kill "$RUNSERVER_PID"
dropdb shop_db
```

## Deploy check

Exercises the prod Dockerfile + `config/settings/production.py` + gunicorn end-to-end. Bypasses Caddy (port 80/443 may be busy on dev machines) by running `web` directly with a published port. Uses an isolated docker network + throwaway Postgres so it doesn't touch the host DB.

```sh
cd 02-shop

# 1. Build the prod image from the generated Dockerfile.
docker build -t shop-prod -f Dockerfile .

# 2. Throwaway network + Postgres for the smoke (separate from host DB).
docker network create shop-smoke
docker run -d --name shop-smoke-db --network shop-smoke \
    -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=shop_db \
    --health-cmd='pg_isready -U postgres' --health-interval=2s --health-retries=10 \
    postgres:17
# Wait for db healthy — no hand-rolled polling.
until [ "$(docker inspect -f '{{.State.Health.Status}}' shop-smoke-db)" = "healthy" ]; do sleep 1; done

# 3. migrate --check against the prod image must fail (no tables yet), then migrate.
docker run --rm --network shop-smoke \
    -e DJANGO_SETTINGS_MODULE=config.settings.production \
    -e DJANGO_SECRET_KEY=smoke-secret-not-for-prod-padding-to-fifty-chars-min \
    -e DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost \
    -e DATABASE_URL=postgres://postgres:postgres@shop-smoke-db:5432/shop_db \
    -e EMAIL_URL=consolemail:// \
    -e DEFAULT_FROM_EMAIL=webmaster@localhost \
    shop-prod python manage.py migrate --noinput

# 4. `manage.py check --deploy` against prod settings — no WARNING-level issues.
docker run --rm --network shop-smoke \
    -e DJANGO_SETTINGS_MODULE=config.settings.production \
    -e DJANGO_SECRET_KEY=smoke-secret-not-for-prod-padding-to-fifty-chars-min \
    -e DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost \
    -e DATABASE_URL=postgres://postgres:postgres@shop-smoke-db:5432/shop_db \
    -e EMAIL_URL=consolemail:// \
    -e DEFAULT_FROM_EMAIL=webmaster@localhost \
    shop-prod python manage.py check --deploy --fail-level WARNING

# 5. Boot gunicorn from the image. Port 8000 published to host.
docker run -d --name shop-smoke-web --network shop-smoke -p 8000:8000 \
    -e DJANGO_SETTINGS_MODULE=config.settings.production \
    -e DJANGO_SECRET_KEY=smoke-secret-not-for-prod-padding-to-fifty-chars-min \
    -e DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost \
    -e DATABASE_URL=postgres://postgres:postgres@shop-smoke-db:5432/shop_db \
    -e EMAIL_URL=consolemail:// \
    -e DEFAULT_FROM_EMAIL=webmaster@localhost \
    -e DJANGO_SECURE_SSL_REDIRECT=False \
    shop-prod
# Wait for healthz to return 200.
for i in $(seq 1 30); do curl -sf http://127.0.0.1:8000/healthz >/dev/null && prod_up=1 && break; sleep 1; done
[ -n "$prod_up" ] || { echo "DEPLOY CHECK FAILED: gunicorn never became healthy"; docker logs shop-smoke-web; docker rm -f shop-smoke-web shop-smoke-db; exit 1; }

# 6. Prod smoke assertions — gunicorn, not runserver.
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
curl -sfI http://127.0.0.1:8000/admin/login/ | grep -qi '^x-frame-options: DENY'
# DEBUG=False proof: a 404 must NOT contain the yellow debug-page boilerplate.
curl -s http://127.0.0.1:8000/__definitely_missing__ | grep -qv "You're seeing this error because you have"
# collectstatic ran during image build + WhiteNoise serves the file.
ADMIN_CSS=$(curl -sf http://127.0.0.1:8000/admin/login/ | grep -oE '/static/[^"]*\.css' | head -1)
test -n "$ADMIN_CSS"
curl -sfI "http://127.0.0.1:8000${ADMIN_CSS}" | head -1 | grep -q '200'

# 7. Teardown — always, even on failure.
docker rm -f shop-smoke-web shop-smoke-db
docker network rm shop-smoke
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `uv.lock`, `manage.py`, `config/settings/{base,local,production}.py`, `.env`, `.gitignore`.
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`; `wsgi.py` to `config.settings.production`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tailwind-cli`, `django-allauth`, `django-axes`, `stripe`, `whitenoise`. Dev deps include `ruff`, `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`, `django-browser-reload`.
- `pyproject.toml` has a `[tool.ruff]` block and a `[tool.pyright]` block.
- `mise.toml` present at project root with `[tools]` and at least one `[tasks.*]` block.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `whitenoise.middleware.WhiteNoiseMiddleware` is present in `config/settings/production.py`'s `MIDDLEWARE` and absent from `base.py`.
- `base.py` calls `globals().update(env.email_url("EMAIL_URL", default="consolemail://" if DEBUG else env.NOTSET))` so local resolves to the console backend and prod reads SMTP from env.
- `_stripe.api_key = STRIPE_SECRET_KEY` is set at module scope in `base.py`.
- `django_browser_reload` app + `django_browser_reload.middleware.BrowserReloadMiddleware` live in `config/settings/local.py` (appended last), absent from `base.py` and `production.py`. `config/urls.py` includes `django_browser_reload.urls` at `__reload__/` gated on `settings.DEBUG`.

**Custom user + auth**
- `users/models.py` defines a `User` extending `AbstractUser`. `AUTH_USER_MODEL = "users.User"` in `base.py`.
- `users/migrations/0001_initial.py` exists and creates the `users.User` table.
- `users.User` has a `stripe_customer_id` field (in the model OR a follow-up migration in `users/migrations/`).
- `INSTALLED_APPS` contains `allauth`, `allauth.account`, `django.contrib.sites`, `axes`. `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`.
- `accounts/` URL include in `config/urls.py`. `ACCOUNT_EMAIL_VERIFICATION = "mandatory"` in `production.py`.

**Tailwind + DaisyUI**
- `INSTALLED_APPS` contains `django_tailwind_cli`. `STATICFILES_DIRS = [BASE_DIR / "assets"]`. `TAILWIND_CLI_VERSION` pinned. `TAILWIND_CLI_SRC_CSS = "tailwind-src/css/source.css"` in `base.py`. `TAILWIND_CLI_USE_DAISY_UI` is **not** set.
- Files present: `tailwind-src/css/daisyui.mjs`, `tailwind-src/css/daisyui-theme.mjs`, `tailwind-src/css/source.css` — sources live outside `STATICFILES_DIRS` (see `tailwind.md`).
- `tailwind-src/css/source.css` contains `@import "tailwindcss";`, `@source not "./tailwindcss";`, `@source not "./daisyui{,*}.mjs";`, `@plugin "./daisyui.mjs";`.
- `templates/base.html` loads `{% load tailwind_cli %}`, calls `{% tailwind_css %}` inside `<head>`, and contains `<html data-theme=`.
- `templates/index.html` extends `base.html` and contains the literals `text-blue-600`, `text-4xl`, and `btn-primary`.
- `templates/404.html`, `templates/403.html`, `templates/500.html` present. `500.html` does NOT extend `base.html`.

**Favicon + SEO**
- `assets/favicon.svg` present, contains `<svg`. `templates/base.html` links it via `{% static 'favicon.svg' %}` and loads `{% load static %}`.
- `templates/base.html` `<head>` contains `property="og:title"`, `property="og:description"`, `rel="canonical"`, and `name="description"`.
- `INSTALLED_APPS` contains `django.contrib.sitemaps`. `config/sitemaps.py` (or an app equivalent) defines a `Sitemap` subclass; `config/urls.py` wires `path("sitemap.xml", ...)`. `SITEMAP_URL` read via `env(...)` and listed in `.env.example`.

**Production artifacts**
- Files present at project root: `Dockerfile` (multi-stage `builder` + `prod` targets), `.dockerignore`. Under `deploy/`: `docker-compose.prod.yml`, `Caddyfile`. No root `docker-compose.yml` (Postgres is on the host; no local services to compose).
- `Dockerfile` uses `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`, runs `uv sync --frozen --no-dev`, contains a `collectstatic --noinput` step under `DJANGO_SETTINGS_MODULE=config.settings.production`, switches to a non-root `django` user, and ends with a `CMD` invoking `gunicorn config.wsgi` with `--bind 0.0.0.0:8000`, `--max-requests`, `--max-requests-jitter`, and `--access-logfile -` (worker count comes from `WEB_CONCURRENCY`, not a `--workers` flag).
- `pyproject.toml` runtime deps include `gunicorn`.
- `.dockerignore` lists `.venv`.
- `deploy/docker-compose.prod.yml` defines a `web` healthcheck using `python -c 'import urllib.request...'` (not curl), a `db` healthcheck using `pg_isready`, and an `x-logging` anchor with `max-size` applied as `logging:` on every service.
- `deploy/Caddyfile` contains `encode zstd gzip` and a `request_body` block with `max_size`.

**Pages + billing**
- `pages/` app with `IndexView(TemplateView)` wired at `/`. `liveness`, `readiness`, `robots_txt` views live in `config/views.py` (per `healthcheck.md` / `robots.md`); `config/urls.py` wires `path('healthz', ...)`, `path('readyz', ...)` (no trailing slash), and `path('robots.txt', ...)`.
- `billing/` app with `create_checkout_session`, `customer_portal`, `stripe_webhook` views. Webhook decorated with `@csrf_exempt` AND `@require_POST`. Webhook calls `stripe.Webhook.construct_event(request.body, sig_header, settings.STRIPE_WEBHOOK_SECRET)`.
- `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` listed in `.env.example`. `billing/` URLs included in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks (docstrings, style, hypothetical scaling, "consider adding X"). Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
