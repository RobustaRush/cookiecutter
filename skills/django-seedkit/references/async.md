# Request handling — WSGI / ASGI / ASGI + channels

Docs: <https://docs.djangoproject.com/en/stable/topics/async/> · <https://www.uvicorn.org/> · <https://docs.gunicorn.org/en/stable/settings.html#worker-class>

Three modes the skill supports. Decide at Foundation §2.4 — switching later means rewriting Dockerfile `CMD`, gunicorn worker class, and the `manage.py`/`wsgi.py`/`asgi.py` defaults.

| Mode | Why pick it | What it ships |
|---|---|---|
| **wsgi** *(default)* | Stock Django, no async views, no WebSockets. | `gunicorn config.wsgi`. `manage.py` → `local`, `wsgi.py` → `production`, `asgi.py` left at the `startproject` default. |
| **asgi** | `async def` views, async middleware, `StreamingHttpResponse` over a long-running upstream. No WebSockets. | `gunicorn -k uvicorn_worker.UvicornWorker config.asgi:application`. `asgi.py` → `production`; `wsgi.py` left at the `startproject` default. |
| **asgi+channels** | Real WebSockets / long-lived connections / chat / live notifications. See `references/realtime.md`. | Same gunicorn invocation as `asgi`; channels routing wraps the ASGI app. |

## When to prefer stock ASGI over channels

`django-channels` activity has slowed. For one-shot async work — calling an HTTP API from a view, streaming a generated response, async ORM queries — stock Django 5+ async views are enough and add no dependency. Reach for channels only when you actually need WebSockets, long-lived connections, or out-of-band server pushes via a channel layer.

## Install

```sh
# asgi or asgi+channels
uv add 'uvicorn[standard]' uvicorn-worker gunicorn
```

`uvicorn[standard]` pulls `httptools` + `uvloop` for the fast loop; `uvicorn-worker` provides the `uvicorn_worker.UvicornWorker` class for gunicorn; `gunicorn` stays the process manager so `--workers` / signal handling / preload behave the same as the WSGI path.

## Settings module defaults

| File | wsgi | asgi / asgi+channels |
|---|---|---|
| `manage.py` | `config.settings.local` | `config.settings.local` |
| `wsgi.py` | `config.settings.production` | unchanged (the `startproject` default) — file isn't loaded |
| `asgi.py` | unchanged | `config.settings.production` |

Only one of `wsgi.py` / `asgi.py` gets the production pointer — whichever the deploy actually loads.

## Dockerfile `CMD`

```dockerfile
# wsgi
CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000", "--max-requests", "1000", "--max-requests-jitter", "100", "--access-logfile", "-"]

# asgi or asgi+channels
CMD ["gunicorn", "-k", "uvicorn_worker.UvicornWorker", "config.asgi:application", "--bind", "0.0.0.0:8000", "--max-requests", "1000", "--max-requests-jitter", "100", "--access-logfile", "-"]
```

Replace the `gunicorn config.wsgi …` line in `references/docker.md` and `references/deploy-vps.md` with the ASGI variant when the mode is `asgi` or `asgi+channels`.

## Worker count

gunicorn reads `WEB_CONCURRENCY` natively as the worker count (default 1). The `2 * cpu + 1` formula assumes sync workers. For ASGI/uvicorn workers, **start with the CPU count**; each worker already handles many concurrent requests inside its event loop, so multiplying inflates memory without throughput.

```sh
# .env.prod
WEB_CONCURRENCY=4   # cores for uvicorn workers; 2×cores+1 for sync WSGI workers
```

## Healthcheck

The `/healthz` / `/readyz` views in `references/healthcheck.md` work unchanged — gunicorn+uvicorn serves them with the same routing. The Caddyfile / compose healthcheck blocks don't change either.

## Tests

`pytest-django` runs sync tests against ASGI apps the same way it runs them against WSGI. For testing `async def` views, mark with `@pytest.mark.asyncio` and use `async def test_...` — `pytest-asyncio` is the standard plugin.

```sh
uv add --dev pytest-asyncio
```

`pytest.ini` / `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

## Pitfalls

- Mixing sync ORM calls in an `async def` view: Django raises `SynchronousOnlyOperation`. Wrap with `sync_to_async(...)` or use the async ORM (`await Model.objects.aget(...)`, `async for obj in Model.objects.filter(...)`).
- `manage.py runserver` uses the WSGI handler regardless of `asgi.py` settings. For local ASGI behaviour parity (WebSocket upgrades, long-lived requests), run `uvicorn config.asgi:application --reload` directly.
- `gunicorn --preload` plus `UvicornWorker` shares the event loop across forks in surprising ways. Don't use `--preload` with the uvicorn worker class unless you've measured the win.
