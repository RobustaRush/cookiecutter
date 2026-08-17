# Developer tools

Docs: <https://github.com/jazzband/django-silk> · <https://github.com/kmmbvnr/django-orbit> · <https://github.com/adamchainz/django-browser-reload> · <https://github.com/taobojlen/django-zeal> · <https://github.com/3YOURMIND/django-migration-linter> · <https://django-test-migrations.readthedocs.io/> · <https://django-extensions.readthedocs.io/>

Dev-only Django add-ons. Each section is independent — apply only the ones the user opts into.

- **Debug toolbar** (orbit / silk) — pick one or none.
- **Browser auto-reload** — `django-browser-reload` refreshes the tab on code / template / static changes.
- **django-extensions** — `shell_plus`, `runserver_plus`, `show_urls`.
- **Database safety** — pick any of `django-zeal`, `django-migration-linter`, `django-test-migrations`.

## Debug toolbar

Two options:

- **Orbit** — observability dashboard: requests, SQL, logs, exceptions, cache, ORM events, emails, background jobs, Redis, outgoing HTTP. Optional MCP server lets AI assistants query live telemetry. Pick for general debugging.
- **Silk** — profiling dashboard with `@silk_profile` for specific Python functions. Pick when you need to pinpoint CPU time inside known code paths.

### django-orbit

Dashboard at `/orbit/`. Per-request event correlation via `family_hash`. Dev-only.

#### Install

```sh
uv add --dev "django-orbit[mcp]"
```

The `[mcp]` extra ships the `orbit_mcp` server so AI assistants can query live telemetry. Drop it (`uv add --dev django-orbit`) only when MCP was declined.

#### Settings

In `config/settings.py` (or `config/settings/local.py` for split):

```python
if DEBUG:
    INSTALLED_APPS += ["orbit"]
    # Insert AFTER SecurityMiddleware so SSL redirect / HSTS / host validation
    # still run first. Putting Orbit ahead of it lets it observe requests that
    # SecurityMiddleware would have rejected — the data is noisy and the
    # security stack should be honoured even in dev. Compute the index rather
    # than hardcoding 1; another add-on may already have prepended middleware.
    sec_idx = MIDDLEWARE.index("django.middleware.security.SecurityMiddleware")
    MIDDLEWARE.insert(sec_idx + 1, "orbit.middleware.OrbitMiddleware")

    ORBIT_CONFIG = {
        "IGNORE_PATHS": ["/orbit/", "/static/", "/media/"],
        "HIDE_REQUEST_HEADERS": ["Authorization", "Cookie", "X-API-Key"],
        "HIDE_REQUEST_BODY_KEYS": ["password", "token", "api_key", "secret"],
        "SLOW_QUERY_THRESHOLD_MS": 100,
    }
```

#### URLs

```python
from django.conf import settings

if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("orbit/", include("orbit.urls"))]
```

#### Migrate

```sh
uv run manage.py migrate
```

#### Logging

Wire the orbit log handler whenever orbit is installed — otherwise the dashboard misses log records. `django-orbit` is a dev dep, so the handler lives in `config/settings/local.py` for the split layout. Keep `LOGGING` itself at module scope in `base.py` — gating the whole dict on `if DEBUG:` leaves production on Django's bare defaults. The `local.py` `if DEBUG:` block only **appends** the orbit handler:

`base.py` (always loaded):

```python
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
    },
    "root": {"handlers": ["console"], "level": "INFO"},
}
```

`local.py` (dev-only — adds the orbit handler on top):

```python
LOGGING["handlers"]["orbit"] = {"()": "orbit.handlers.OrbitLogHandler"}
LOGGING["root"]["handlers"].append("orbit")
LOGGING["root"]["level"] = "DEBUG"
```

Single-file layout: keep the baseline at module scope, then guard only the orbit-handler append with `if DEBUG:`.

#### MCP — AI assistant integration

Write `.mcp.json` at the project root, so the server ships with the project instead of living in one developer's machine config:

```json
{
  "mcpServers": {
    "django-orbit": {
      "command": "uv",
      "args": ["run", "manage.py", "orbit_mcp"],
      "env": {"DJANGO_SETTINGS_MODULE": "config.settings"}
    }
  }
}
```

Split layout: `"config.settings.local"`.

Tools: recent requests, slow queries, exceptions, N+1 patterns, keyword search, performance stats.

#### Dashboard

- `http://localhost:8000/orbit/` — live event feed.
- `http://localhost:8000/orbit/stats/` — Apdex, P50–P99, error rate, cache hit rate.

### django-silk

Profiling dashboard at `/silk/`. Stores request / response and SQL data in the database. Unique feature: `@silk_profile` for profiling specific Python functions. Dev-only.

#### Install

```sh
uv add --dev django-silk
```

#### Settings

```python
if DEBUG:
    INSTALLED_APPS += ["silk"]
    # AFTER SecurityMiddleware, not before. Prepending at index 0 routes
    # the profiler around Django's security headers on every request.
    sec_idx = MIDDLEWARE.index("django.middleware.security.SecurityMiddleware")
    MIDDLEWARE.insert(sec_idx + 1, "silk.middleware.SilkyMiddleware")
```

#### URLs

```python
if settings.DEBUG:
    from django.urls import include, path
    urlpatterns += [path("silk/", include("silk.urls", namespace="silk"))]
```

#### Migrate

```sh
uv run manage.py migrate
```

#### Function profiling

`silk` is removed from `INSTALLED_APPS` outside `DEBUG`, so its tables don't exist in production. A bare top-level `from silk.profiling.profiler import silk_profile` in app code raises at import on a prod boot; an unconditional `@silk_profile` decorator runs the profiling context manager and tries to write a `Request`/`Profile` row that has no table. Either pattern crashes prod.

Do **not** decorate app code with `@silk_profile` outright. The middleware above already profiles every request — that's enough for most cases.

If you need to profile a specific block:

```python
from django.conf import settings

if settings.DEBUG:
    from silk.profiling.profiler import silk_profile
else:
    class silk_profile:  # no-op decorator + context manager for prod
        def __init__(self, *_a, **_kw): pass
        def __call__(self, fn): return fn
        def __enter__(self): return self
        def __exit__(self, *_a): return False

@silk_profile(name="my expensive operation")
def expensive_operation():
    ...
```

Don't wrap task bodies with `silk_profile` — it only records inside a request-scoped `DataCollector`, which a worker process has none of, so it logs `Cannot execute silk_profile as silk is not installed correctly` and records nothing. Profile the same logic from a request-scoped view instead.

#### Clear old data

Silk accumulates indefinitely. Clear manually:

```sh
uv run manage.py silk_clear_request_log
```

Or auto-cap in settings:

```python
SILKY_MAX_RECORDED_REQUESTS = 1000
SILKY_MAX_RECORDED_REQUESTS_CHECK_PERCENT = 10
```

#### Dashboard

`http://localhost:8000/silk/`

## Browser auto-reload — django-browser-reload

Reloads the browser tab when Python code, templates, or static files change under `runserver`. Requires `django.contrib.staticfiles` in `INSTALLED_APPS` (the `startproject` default has it). WSGI and ASGI both supported.

### Install

```sh
uv add --dev django-browser-reload
```

### Settings (local / DEBUG-gated)

```python
# config/settings/local.py  (or DEBUG-gated block in single settings)
if DEBUG:
    INSTALLED_APPS += ["django_browser_reload"]
    # Append last — it must run after any middleware that encodes the response
    # (e.g. GZipMiddleware); it injects the reload <script> before </body>.
    MIDDLEWARE += ["django_browser_reload.middleware.BrowserReloadMiddleware"]
```

### URLs

```python
# Gate on the app, not on DEBUG: the Dockerfile build runs collectstatic with
# DJANGO_DEBUG=True against production settings, where the dev-only package is
# absent (`uv sync --no-dev`) — a bare `if settings.DEBUG` import crashes it.
if "django_browser_reload" in settings.INSTALLED_APPS:
    from django.urls import include, path
    urlpatterns += [path("__reload__/", include("django_browser_reload.urls"))]
```

The script tag is only injected when `DEBUG=True`, and the dep + app live behind the dev gate — production responses are untouched.

Optional companion: [django-watchfiles](https://github.com/adamchainz/django-watchfiles) makes the underlying file watching faster.

## django-extensions

Optional dev-only toolbox. Adds management commands and `runserver_plus` (Werkzeug-based debugger). Useful when the team actually uses these; pure noise otherwise.

Default **no**. Only apply when the user explicitly opts in.

### Install

```sh
uv add --dev django-extensions
```

`--dev` is intentional — these tools shouldn't ship to production. The dependency is dev-only in `pyproject.toml`, and `INSTALLED_APPS` adds the app conditionally.

### `local.py` only — never `base.py`

```python
from .base import *
from .base import INSTALLED_APPS

INSTALLED_APPS += ["django_extensions"]
```

`base.py` runs in production too; importing a dev-only dep there crashes the boot.

For single-settings layouts, gate it on `DEBUG`:

```python
if DEBUG:
    INSTALLED_APPS += ['django_extensions']
```

### What it adds

The commands worth knowing about:

- `shell_plus` — opens an IPython / bpython shell with every model, `timezone`, and common utils auto-imported. With `--print-sql`, also echoes every ORM-generated query.
- `runserver_plus` — Werkzeug-backed dev server with an interactive in-browser traceback debugger. `tailwind runserver` (`references/tailwind.md`) forwards to this if installed.
- `show_urls` — flat list of every URL pattern in the project; great for "where is this route defined".
- `graph_models` — dumps an ER diagram of the model graph (requires graphviz).
- `clean_pyc` / `reset_db` / `clear_cache` — rare, but occasionally useful.

### Pitfalls

- `runserver_plus`'s in-browser traceback can execute arbitrary Python from the URL bar. Never expose it on a network anyone else can reach. `DEBUG=True` plus `runserver_plus` plus `0.0.0.0` is a remote-code-execution invitation.
- `graph_models` needs `graphviz` installed at the OS level (`brew install graphviz` / `apt install graphviz`). Document that or skip the command.
- Keep `django_extensions` strip-out-able — confine usage to local shells and management commands, not template tags or model imports.

## Database safety

Three tools that catch database mistakes before they reach production.

- **django-zeal** — raises an exception in dev when ORM code produces N+1 queries. No configuration beyond `INSTALLED_APPS`; catches the problem at the exact line that caused it.
- **django-migration-linter** — static-analyses every migration for dangerous operations: adding a NOT NULL column without a default on a large table, dropping a column, renaming without a transition period, etc. Runs as a management command or in CI.
- **django-test-migrations** — pytest fixture that applies and rolls back individual migrations in tests. Verifies a migration is reversible and that the `RunPython` forwards/backwards functions are correct.

Ask: which of these to include? Each is independent; all three are dev-only deps.

### django-zeal

#### Install

```sh
uv add --dev django-zeal
```

#### Settings (local / DEBUG-gated)

```python
# config/settings/local.py  (or DEBUG-gated block in single settings)
if DEBUG:
    INSTALLED_APPS += ["zeal"]
    MIDDLEWARE += ["zeal.middleware.zeal_middleware"]   # required to scope detection per request
    ZEAL_RAISE_ON_VIOLATION = True
```

#### Silencing intentional N+1s

When a queryset is genuinely unavoidable (e.g. a management command that processes rows one at a time by design):

```python
from zeal import zeal_ignore

with zeal_ignore():
    for obj in MyModel.objects.all():
        do_something(obj.related_set.all())
```

Or silence a specific access pattern permanently:

```python
# config/settings/local.py
ZEAL_SILENCED_WARNINGS = [
    {"model": "myapp.MyModel", "field": "related_set"},
]
```

#### pytest

Zeal works automatically in pytest-django tests that hit the DB — no extra setup needed.

### django-migration-linter

#### Install

```sh
uv add --dev django-migration-linter
```

#### Settings (local / DEBUG-gated)

```python
# config/settings/local.py
if DEBUG:
    INSTALLED_APPS += ["django_migration_linter"]   # registers the `lintmigrations` command
```

#### Run

```sh
uv run manage.py lintmigrations
```

Exits non-zero if any migration contains a dangerous operation. Safe to run locally and in CI.

Exclude third-party apps (they maintain their own migrations):

```sh
uv run manage.py lintmigrations --exclude-apps allauth account socialaccount
```

#### CI step

Add after `uv sync --frozen` and before the test step in `.github/workflows/test.yml`:

```yaml
      - run: uv run manage.py lintmigrations --exclude-apps account socialaccount
```

#### setup.cfg (optional — persist the exclusion list)

`django-migration-linter` reads `setup.cfg`, not `pyproject.toml`. Entries are app **labels** (from `AppConfig.label`), not the `INSTALLED_APPS` name — some packages differ:

```ini
[django_migration_linter]
exclude_apps = silk,account,socialaccount
```

A wrong entry is ignored silently — the app stays linted. Read the labels off the running project when `lintmigrations` still flags an app you tried to exclude:

```sh
uv run manage.py shell -c "from django.apps import apps; print([a.label for a in apps.get_app_configs()])"
```

### django-test-migrations

Requires pytest + pytest-django (see `references/pytest.md`). Skip if the project uses `manage.py test`.

#### Install

```sh
uv add --dev django-test-migrations
```

The `migrator` pytest fixture ships with the package — no `conftest.py` wiring needed. Test patterns live in [the upstream docs](https://django-test-migrations.readthedocs.io/).

If `startapp` already created `myapp/tests.py` and you later need a `tests/` package, convert it without losing existing tests:

```sh
mkdir myapp/tests
git mv myapp/tests.py myapp/tests/test_initial.py
touch myapp/tests/__init__.py
```

Write a migration test whenever a `RunPython` operation transforms data or when the migration is irreversible by design (document with `reverse_code=migrations.RunPython.noop` and a comment explaining why).
