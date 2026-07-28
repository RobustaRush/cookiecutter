---
name: django-seedkit
version: 26.31.2
description: Bootstrap a new Django project, or add components — auth (allauth, magic-link, axes, 2FA), payments (Stripe, dj-stripe), REST (django-modern-rest, django-bolt), Celery / django-tasks, async views & WebSockets (ASGI, uvicorn worker, django-channels, channels-redis), Tailwind+DaisyUI, favicon, SEO meta tags + sitemap, HTML email templates, S3 storage, structlog, healthchecks, Docker, CI, deploy (VPS / Fly / GitHub-SSH), dbbackup, Sentry/Bugsink — to an existing Django codebase. Use whenever the user wants to scaffold Django, integrate a Django package, set up async / WebSockets, set up production deploys, wire CI/CD, or extend an existing Django project.
---

## How this skill works

Two paths:

- **New project** (empty dir, only `.git/` or stub README): run §2 → §8 in order.
- **Existing project** (has `pyproject.toml` and Django code): skip §2–§4. Read `references/existing-project.md` for the inventory workflow, then jump to §5/§6 and ask only about missing components.

Before either path, run `uv --version` to confirm uv is installed (`references/uv.md`).

Every question below names the reference that answers it — read that one file before applying the step, and no others.

For every question that involves a third-party package: 1–2 sentences from the reference's intro on what it adds beyond stock Django, then ask. `none` (or `no`) is always a valid answer.

**Use answers already given.** Before asking any question, scan the user's initial request (and anything they've said since) for the answer. If it's there — explicit ("use PostgreSQL", "with Celery", "no auth") or unambiguous from context — take it as given, note the decision in one line, and move on. Don't re-ask to confirm. Only ask when the answer is genuinely missing or ambiguous.

**Preflight — read these before the first tool call of a new-project run:** `references/new-project.md`, `references/database.md`, and `references/conventions.md` (the cross-file contract: env var names, Redis DB map, prod compose service shape, SameSite rule, Python pins).

## Instructions

### 1. Open the conversation

Name the groups you'll walk through — Project Foundation (§2), then Developer Experience, Auth & Accounts, Data & Storage, Background & Email, Frontend & Site Basics, SaaS / Product, Real-time (§5.1–5.7), then Production & Deploy (§6) — one sentence each. For existing projects: first follow `references/existing-project.md` and note what's already detected per group. Invite the user to begin.

### 2. Project Foundation — new projects only, one question at a time, in order

1. Project name + one-line purpose (the explicit two-answer pair).
2. Settings layout: single `settings.py` or split `base/local/production`. → `references/new-project.md`
3. Database: SQLite or PostgreSQL. → `references/database.md`
4. Request handling: `wsgi` / `asgi` / `asgi+channels`. **Default `wsgi`.** Decide now — Dockerfile `CMD`, server choice, and the `manage.py`/`wsgi.py`/`asgi.py` settings defaults all hinge on this; switching later means rewriting deploy artefacts. See `references/async.md` (and `references/realtime.md` for the channels mode).
5. If Postgres: host Postgres or Postgres-in-Docker (single-service `docker-compose.yml` for the local DB only). SQLite users skip. → `references/docker.md`
6. Custom user model: yes / no — decide now (see `references/custom-user.md`).

Never bundle questions beyond the explicit pair in step 1.

### 3. Apply the foundation (new projects only)

Generate files from the matching references. `.env` `DATABASE_URL` must match DB + dev mode. If custom user = yes, apply `references/custom-user.md` **before** the boot check. If DB=SQLite, also apply the `production.py` block from `references/database.md` (WAL + IMMEDIATE PRAGMAs) — settings tuning, not a user-facing question.

### 4. Foundation smoke — agent-driven, new projects only

Run these yourself; do not ask the user. The goal is to catch foundation bugs before piling on add-ons, without making the user type `uv run …` commands that §5.1 may replace minutes later.

- `uv run manage.py migrate` (start the local Postgres service first with `docker compose up -d db` when DB=Postgres-in-Docker).
- Start `uv run manage.py runserver --noreload` in the background. `--noreload` drops the StatReloader so the listener is ready sooner; a `sleep 2` then `curl` can still race on slow CI, so poll — and test the flag after the loop, because a bare `for … curl … done` exits 0 even when the server never came up:

  ```sh
  for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
  [ -n "$up" ] || echo "BOOT CHECK FAILED"
  ```

- Stop the server. Use the recorded PID from the background-launch step (`kill "$PID"`); don't use `kill %1` (no job control in non-interactive bash) or `pkill -f manage.py` (matches the parent harness process).

If `migrate` or the curl fails, fix the foundation before proceeding to §5. `createsuperuser` and the browser login move to §7 — they need a stable task runner name and a real browser, neither of which exists yet.

### 5. Add-ons — one group at a time, one question at a time

For new projects: ask every question. For existing projects: only ask about components not already detected in §1; confirm and skip the rest.

#### 5.1 Developer Experience

1. Ruff lint: yes / no. **Default no.** → `references/lint.md`
2. Test runner: pytest or stock `manage.py test`. **Default no** (stock). → `references/pytest.md`
3. Type checking with pyright + django-stubs: yes / no. **Default no.** → `references/typecheck.md`
4. Pre-commit hooks: yes / no. **Default no** — recommend yes if lint=yes; wires whichever of lint / format / typecheck were chosen. → `references/pre-commit.md`
5. Devcontainer: yes / no. **Default no.** Wraps a Python image with uv pre-installed so VS Code / Codespaces / JetBrains Gateway open the project ready to run. → `references/devcontainer.md`
6. Debug toolbar: `django-orbit` / `django-silk` / `none`. **Default none.** → `references/dev-tools.md`
7. Browser auto-reload via `django-browser-reload`: yes / no. **Default no.** → `references/dev-tools.md`
8. DB safety: any of `django-zeal` / `django-migration-linter` / `django-test-migrations`. **Default none.** Skip `django-test-migrations` if pytest = no. → `references/dev-tools.md`
9. `django-extensions`: yes / no. **Default no.** → `references/dev-tools.md`
10. Structured logging via `structlog`: yes / no. **Default no.** → `references/logging.md`
11. Task runner: `mise` / `just` / `make` / `poe` / `none`. **Default mise** (recommended). Detect what's installed with `command -v` and offer the first hit; mention the others. See `references/dev-tasks.md`.

#### 5.2 Auth & Accounts

1. Auth: `django-allauth` / `django-mail-auth` / `none`. **Default none.** → `references/auth.md`
2. `django-axes` brute-force lockout: yes / no. **Default yes.** Skip if auth = none. → `references/auth-hardening.md`
3. 2FA: yes / no. **Default no.** Skip if auth = none. When yes: built-in `allauth.mfa` if auth = allauth (via `django-allauth[mfa]` extra — never `allauth-2fa`, which is unmaintained), else `django-otp`. → `references/auth-hardening.md`

#### 5.3 Data & Storage

1. Cache backend: `sqlite` / `redis` / `locmem` / `none`. **Default `sqlite` when DB=SQLite, else `locmem`.** `sqlite` wires a separate `cache.sqlite3` + `CacheRouter` + `DatabaseCache` (see `references/database.md`); `redis` adds `django-redis` (`references/redis.md`); `locmem` is the per-process in-memory backend.
2. Static + media storage: `whitenoise` / `s3` / `none`. **Default none** — required before production but not for first boot. → `references/storage-whitenoise.md` / `references/storage-s3.md`

#### 5.4 Background & Email

1. Background tasks: `celery` / `django-tasks-db` / `django-tasks-rq` / `none`. **Default `django-tasks-db` when DB=SQLite, else `none`.** → `references/tasks-celery.md` / `references/tasks-django.md` (dispatches to `-db.md` / `-rq.md`)
   - If `django-tasks-db` or `django-tasks-rq`: periodic tasks via `django-crontask`? **Default no.** `django.tasks` ships no Beat equivalent — see `references/tasks-django-cron.md`.
2. Email backend: `console` / `smtp` / `mailpit` / `anymail` / `none`. **Always ask** — every project sends mail eventually (password resets, error reports, allauth verification). → `references/email.md`
   - If backend ≠ none: HTML email base template + `send_test_email` command? **Default no.**

#### 5.5 Frontend & Site Basics

1. Frontend: `tailwind` / `none`. **Default none.** → `references/tailwind.md`
   - If tailwind: custom 404/403/500 templates? **Default no.**
   - If tailwind: DaisyUI components? **No default — always ask explicitly.**
   - If tailwind: favicon (agent-drawn SVG matching the project)? **Default yes.** → `references/favicon.md`
2. SEO basics (meta/OG tags + sitemap): yes / no. **Default no** — only for public-facing sites. Skip if Frontend = none (the meta block needs `base.html`). → `references/seo.md`
3. i18n (gettext, LocaleMiddleware, makemessages): yes / no. **Default no** — cost of adding later is real. → `references/i18n.md`
4. CORS: yes / no. **Default no** — only when there's a separate frontend on a different domain. → `references/cors.md`
5. `robots.txt`: yes / no. **Default no** — only for public-facing sites. → `references/robots.md`

#### 5.6 SaaS / Product

1. REST API: `django-modern-rest` / `django-bolt` / `none`. **Default none.** → `references/rest.md` for the comparison; when the user already named a library, skip it and read `references/rest-modern-rest.md` or `references/rest-bolt.md` directly.
2. Billing: `stripe` (raw SDK) / `dj-stripe` / `none`. **Default none.** → `references/billing.md`
3. Analytics: `goatcounter` / `umami` / `shynet` / `ga4` / `none`. **Default none.** → `references/analytics.md`

#### 5.7 Real-time

Only ask when request handling is `asgi+channels` — Foundation §2.4 for new projects, the value `references/existing-project.md` §2 detected for existing ones. Otherwise skip the whole group.

1. Channel layer: `channels-redis` / `InMemoryChannelLayer`. **Default `channels-redis`.** In-memory is dev-only — it doesn't span processes, so any horizontal scale or separate ASGI worker process breaks broadcast. → `references/realtime.md`

### 6. Production & Deploy — one question at a time

1. Security settings: yes / no. **Default no.** → `references/security.md`
   - If yes: Content Security Policy via `django-csp`? **Default yes.** → `references/csp.md`
2. Health check endpoints (`/healthz`, `/readyz`): yes / no. **Default yes.** Apply before the deploy target so the deploy reference can wire the matching probe block in compose / `fly.toml` / nginx. → `references/healthcheck.md`
3. Error reporting: `bugsink` / `sentry` / `glitchtip` / `none`. **Default none.** → `references/error-reporting.md`
4. GDPR helpers: yes / no. **Default no.** → `references/gdpr.md`
5. CI on GitHub Actions: yes / no. **Default no.** → `references/ci.md`
6. Deploy target: `vps` / `managed` / `github-ssh` / `none`. **Default none.** → `references/deploy-vps.md` / `references/deploy-managed.md` / `references/deploy-github-ssh.md` Any target other than `none` applies `references/docker.md` first — all three deploy references build on its multi-stage production image. With `none`, skip the production Dockerfile; the local services compose from §2.5 / §5.3 stands on its own.
   - If `vps` or `github-ssh`: database backups via `django-dbbackup`? **Default yes.** → `references/dbbackup.md` Both deploy to self-managed hosts. Skip for `managed` — those platforms ship native backups. Also skip when DB=SQLite + deploy=`vps` if Litestream is already wired (see `references/database.md`) — Litestream replicates every WAL frame, so dbbackup snapshots are redundant.

### 7. Final smoke — user-driven, new projects only

After §6, ask the user to run, using the task-runner names from §5.1 if one was applied (else `uv run manage.py …`):

- `createsuperuser` (interactive — the user runs it themselves).
- `collectstatic --noinput` only if a static-files add-on was applied.
- Open `/admin/` in a browser and sign in with the new superuser.

Wait for the user to confirm the browser login works before §8.

### 8. README + agent context

After applying any reference, append the decision and any new commands to `README.md`. Finalize at the end of the run with stack summary and key commands (install, test, migrate, run, deploy). Don't hardcode dependency versions — read them from `pyproject.toml`. If a task runner was applied (§5.1), show task-runner names (`mise run dev`, `just test`) in the README's main command list — not the raw `uv run …` invocations.

If a deploy target was applied (§6.6), copy the deploy command block from the matching `references/deploy-*.md` verbatim into a `## Deploy` section in `README.md`. The block includes the one-shot `manage.py migrate` step that runs before `docker compose up -d` — without it, the first `up -d --build` hits an empty database and every page 500s.

For new projects only (no question — always):

- Write `AGENTS.md`: one line per stack decision (layout, DB, request handling, each applied add-on), the project layout tree, and the same key-commands block the README gets. Coding agents load it as project context, so keep it factual and short — no marketing prose.
- Write `CLAUDE.md` containing exactly one line: `@AGENTS.md`.
- Append a final line to `README.md`: `Built with [Seedkit](https://github.com/viewflow/seedkit).`

Skip all three on existing-project runs.

## Common pitfalls

Each rule has a *why* so you can judge edge cases.

**Snippet integrity**

- Use snippets verbatim. Don't drop lines that look obvious or redundant — `DEFAULT_AUTO_FIELD`, gated env defaults, top-level `RQ = {"JOB_CLASS": ...}`. They look optional and are not.
- The fail-fast idiom for env vars is `default=<dev-value> if DEBUG else env.NOTSET`. `env.NOTSET` raises `ImproperlyConfigured` naming the variable when the env var is missing in prod.
- Don't reimplement `django-environ` (no manual `.split(",")`, no leftover `import os`).

**Cross-file consistency**

- Shared names and shapes (env vars, Redis DBs, compose service fragments) follow `references/conventions.md`. If two references seem to disagree, conventions.md wins.

**Env vars and `.env.example`**

- Always `DJANGO_DEBUG` / `DJANGO_SECRET_KEY` / `DJANGO_ALLOWED_HOSTS` — these names are referenced across many references.
- When adding an add-on, append every env var its reference reads to `.env.example` so the file stays the canonical list.
- `.env.example` comments belong on their own lines, never trailing the value. `django-environ` reads everything after `=` verbatim, so `EMAIL_URL=consolemail://    # dev` becomes the literal URL `consolemail://    # dev` and breaks any deploy that copies the file.

**App layout**

- Don't create an app dir named after the project unless asked.
- `tasks.py` must live inside a registered Django app, not at project root or under `config/`. Both Celery autodiscovery and `django-tasks` only scan `INSTALLED_APPS`. When a fresh project has no app yet, **don't auto-create one** — wire the task settings / services / Dockerfile so the worker boots and idles, then tell the user where to drop `@task` functions once they create a domain app. Auto-creating `jobs/` dictates app layout the user may not want.

**After `startproject` / `uv init` / `startapp`**

- Set `requires-python = ">=3.12"` in `pyproject.toml` immediately after `uv init`, before the first `uv add`. The host-derived pin (`>=3.14` on recent machines) refuses Django 6.
- After inserting the env-driven `DATABASES = {...}` line in `references/new-project.md` (Option A in `settings.py`, Option B in `base.py`), **delete** the original hardcoded `DATABASES` block + `# Database` comment that `startproject` emitted. Bottom wins; leaving both makes `DATABASE_URL` dead code.
- After `startapp <name>`, if Ruff is enabled, run `uv run ruff check --fix .` — `startapp` ships `admin.py` / `views.py` / `tests.py` with stub imports that fail `F401`.
- Run `startapp <name>` **before** adding `<name>` to `INSTALLED_APPS`. `manage.py startapp` imports settings; if the app is already listed but the directory doesn't exist, the import fails with `ModuleNotFoundError`. Same for any package a settings block references (e.g. `orbit.handlers.OrbitLogHandler` in `LOGGING`) — `uv add` it before the next `startapp` runs, or that import fails too.
- If i18n = no, remove the `USE_I18N = True` line and the `# Internationalization` comment block that `startproject` emits. Harmless to leave, but the reference's settings are single-language by default and the orphan block invites confusion.

**`uv run` vs `python` invocation**

- On the **host** (dev, local commands, smoke checks): `uv run manage.py …`. uv resolves the project venv.
- **Inside any Docker container** (dev compose `exec`, prod `compose run`, Fly `release_command`, devcontainer `postAttach`): `python manage.py …`. `/opt/venv/bin` is on `PATH`; the multi-stage runtime image (`python:3.X-slim-trixie`) has no `uv` binary, so `uv run` breaks there.

**Add-on scope**

- Don't add packages the user didn't ask for. `django-extensions` is an explicit add-on question — apply only if the user said yes.
