Read-only audit of the Django project in the current directory. This is a
freshly generated scaffold with no business logic — that is expected and is
never a finding.

Score it against the eight checks below. Every check is static: decide it by
reading files, never by running the project. Quote the file path and the
literal substring you read for each verdict — if you cannot quote it, the
check is FAIL.

1. `deps` — a dependency manifest (`pyproject.toml` or `requirements.txt`)
   declares Django, and a lockfile (`uv.lock`, `poetry.lock`,
   `requirements.txt` with pinned versions) sits next to it.
2. `settings-env` — `SECRET_KEY`, `DEBUG`, and `ALLOWED_HOSTS` are all read
   from the environment rather than written as literals in settings.
3. `secret-failsafe` — the production path has no usable hardcoded fallback
   for `SECRET_KEY`. A missing value must raise at startup, not silently boot
   on a default string.
4. `db-env` — the database connection is configurable from the environment
   (a `DATABASE_URL`-style var, or per-field env reads). A hardcoded host,
   password, or absolute path is FAIL.
5. `debug-off` — the production settings path defaults `DEBUG` to False. A
   settings module that is True unless overridden is FAIL.
6. `gitignore-secrets` — `.gitignore` covers the environment file and the
   virtualenv, and no tracked file contains a real-looking credential
   (password, API key, or a `SECRET_KEY` literal long enough to be genuine).
7. `readme-run` — the README documents how to install and how to run, and
   the commands it shows match the manifest that is actually present (don't
   pass a README that says `pip install -r requirements.txt` when the project
   ships `pyproject.toml` + `uv.lock`).
8. `layout` — settings, URLs, and WSGI/ASGI entry points live in a package,
   apps are registered in `INSTALLED_APPS`, and no Python module sits at the
   repo root that should be inside an app.

Output format — nothing else, no preamble, no summary prose. One line per
check, in order, then the total:

```
CHECK <name> PASS <path:line — literal substring>
CHECK <name> FAIL <path:line — literal substring, or "absent">
SCORE <passes>/8
```

Do NOT create, generate, or modify any files. Do NOT invoke any skill. Do not
propose fixes, refactors, or additions — this is scoring, not review.
