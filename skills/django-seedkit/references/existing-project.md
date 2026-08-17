# Extending an existing Django project

Use this workflow when the working directory already contains a Django project and the user wants to add or update components — not bootstrap from scratch. Skip §2–§4 of `SKILL.md`; this file replaces them.

## 1. Inventory pass

Before asking any §5/§6 question, build a map of what's already wired. Read each source and note what you find — don't ask the user about anything you can read directly.

**Stack basics**

- `pyproject.toml` — Python version pin, declared deps and `--dev` deps. Notable signals: `ruff`, `pytest`, `pytest-django`, `pyright`, `django-stubs`, `pre-commit`, `django-extensions`, `structlog`, `django-allauth`, `django-axes`, `dj-stripe`, `stripe`, `django-modern-rest`, `django-bolt`, `celery`, `django-redis`, `whitenoise`, `django-storages`, `django-cors-headers`, `django-csp`, `sentry-sdk`, `django-dbbackup`.
- `manage.py` — confirms Django, surfaces the settings module path.
- Settings — locate the active module (single `settings.py`, split `base/local/production`, or custom). Read `INSTALLED_APPS`, `MIDDLEWARE`, `AUTH_USER_MODEL`, `DATABASES`, `CACHES`, `STORAGES`, email backend, `LANGUAGES`, security flags, `CSP_*` keys.
- `.env.example` and `.env` — which env vars are wired.
- `Dockerfile`, `docker-compose.yml`, `deploy/docker-compose.prod.yml`, `.devcontainer/` — which deploy artefacts already exist.
- `.pre-commit-config.yaml` — existing hook set.
- `.github/workflows/` — CI presence and shape.
- Deploy artefacts — `fly.toml`, `Caddyfile`, deploy scripts, GitHub-SSH workflow, `dbbackup` settings.

**Map findings to the eight groups**

For each group in the Reference files section of `SKILL.md`, mark each component as:

- **detected** — already installed and wired. Confirm with the user, then skip the question.
- **partial** — package present in deps but not fully wired (e.g. `django-axes` in `pyproject.toml` but missing from `INSTALLED_APPS`/`MIDDLEWARE`, or `LANGUAGES` set but no `LocaleMiddleware`). Surface the gap and ask if the user wants the wiring completed.
- **missing** — not present. Ask the §5/§6 question normally.

## 2. Derive foundation answers — don't replay §2

Don't ask Foundation questions. Read them off the repo:

- **Database engine** → `DATABASES['default']['ENGINE']`.
- **Local Postgres** → `db` service in `docker-compose.yml` → Postgres-in-Docker; otherwise host Postgres (or SQLite per the engine above).
- **Settings layout** → single `settings.py` vs `settings/` package with `base.py` / `local.py` / `production.py`. When it's split, settings added by any add-on follow the delta rule in `references/new-project.md`.
- **Custom user** → `AUTH_USER_MODEL` set to anything other than `auth.User`.
- **Request handling** → `channels` in `INSTALLED_APPS` (or an `asgi.py` wrapping `ProtocolTypeRouter`) → `asgi+channels`; a `uvicorn` / `UvicornWorker` command in the Dockerfile or deploy artefacts → `asgi`; otherwise `wsgi`. SKILL.md §5.7 and `references/async.md` both branch on this value, so record it even when no question follows.

If a downstream reference needs a foundation answer, use the detected value. Don't surprise the user with a layout change (e.g. don't split a single `settings.py` into a package unless they asked).

## 3. Report back to the user

Send one message structured as a bulleted list per group:

```
**Developer Experience**
- detected: ruff, pytest, pre-commit
- partial: django-extensions in deps but not in INSTALLED_APPS
- missing: typecheck, devcontainer, debug, db-safety, structlog

**Auth & Accounts**
- detected: django-allauth + axes
- missing: 2FA
…
```

Then ask which gaps they want to fill. Treat `none` as a valid answer for any group.

## 4. Boot check — replace §4

Skip the new-project boot check (no `createsuperuser`, the user already has accounts). Instead, after applying any reference that touches migrations, settings, or Docker, ask the user to confirm the existing project still boots cleanly:

- `uv run manage.py migrate` — runs new migrations, including any added by the new component.
- `uv run manage.py runserver` (or compose `up`) — confirm the dev server still starts and `/admin/` still loads.
- If pytest is wired: `uv run pytest` to catch regressions.

Wait for confirmation before moving to the next add-on.

## 5. README updates

Same rule as new projects: append decisions to `README.md` as you apply each reference, finalise at the end. For existing projects, don't rewrite the existing README — append a section like `## Added by seedkit (<date>)` with the new components and any new commands.
