# 01 — Minimal example

Smallest path that boots a working Django project. Baseline — if this fails, everything else is moot.

## Prompt

```
/seedkit

Project name: 01-minimal-blog
Purpose: a tiny blog to verify the skill works end-to-end.

Settings layout: single file (`config/settings.py`).
Database: SQLite.
Lint with Ruff: no.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none (vanilla `django.contrib.auth`).
Structured logging: no.
Task runner: none.
Add-ons:
  - email: console backend (`EMAIL_URL=consolemail://`).
  - HTML email base template: no.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: no (this case is the bare floor — no extra views).
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.

Production setup: skip.

Run the foundation, the boot check (migrate + createsuperuser), and confirm /admin/ login works.
```

## Boot check

```sh
cd 01-minimal-blog
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
kill "$RUNSERVER_PID"
[ -n "$up" ] || { echo "BOOT CHECK FAILED: runserver never came up"; exit 1; }
test -f AGENTS.md && grep -qx '@AGENTS.md' CLAUDE.md
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

- Files present at the project root: `pyproject.toml`, `uv.lock`, `manage.py`, `config/settings.py`, `db.sqlite3`, `.env`, `.gitignore`.
- `AGENTS.md` present: lists the stack decisions (single-file settings, SQLite, no add-ons) and the key commands. `CLAUDE.md` contains exactly one line: `@AGENTS.md`.
- `pyproject.toml` declares `django>=6.0,<7.0` and `django-environ`. No Ruff config, no pyright config.
- `config/settings.py` reads `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`, `DATABASE_URL` via `environ.Env()`, and uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- No Docker files (`Dockerfile`, `docker-compose.yml`).
- `config/urls.py` redirects `/` to `/admin/`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks (docstrings, style, hypothetical scaling, "consider adding X"). Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for — a starter scaffold is supposed to be small. If unsure whether something is a real bug right now, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
