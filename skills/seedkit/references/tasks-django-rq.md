# Django Tasks — Redis Queue backend

Docs: <https://github.com/RealOrangeOne/django-tasks-rq> · <https://python-rq.org/>

Requires Redis (`references/redis.md`).

`django-rq` provides the `rqworker` management command + admin. `django-tasks` (the standalone backport, import path `django_tasks`) is the Tasks API — `from django_tasks import task`. `django-tasks-rq` is the adapter from that API to RQ.

## Install

```sh
uv add django-tasks-rq django-rq
```

`django-tasks-rq` 0.12.0 is built against the standalone `django-tasks` backport (import path `django_tasks`) and pulls it in as a dependency — Django 6's stdlib `django.tasks` is a separate module. Use `from django_tasks import task` in app code.

## INSTALLED_APPS

`django_rq` and `django_tasks` (the backport app) both register. `django_tasks_rq` is a backend module, not an app — don't list it:

```python
INSTALLED_APPS = [
    ...
    "django_rq",
    "django_tasks",
]
```

## Settings

```python
TASKS = {
    "default": {
        "BACKEND": "django_tasks_rq.RQBackend",
        "QUEUES": ["default"],
    }
}

# django-rq reads RQ_QUEUES separately from TASKS. URL form so host/port
# come from REDIS_URL. /3 is django-tasks-rq's slot in the Redis DB map
# (references/conventions.md).
RQ_QUEUES = {
    "default": {"URL": f"{REDIS_URL}/3"},
}

# JOB_CLASS goes in the top-level RQ dict (not RQ_QUEUES[queue]) — django-rq
# reads it from settings.RQ. Missing this, rqworker falls back to rq.job.Job
# and every task raises `'Task' object is not callable`.
RQ = {"JOB_CLASS": "django_tasks_rq.Job"}
```

## URLs

```python
# config/urls.py
path("django-rq/", include("django_rq.urls")),
```

`django_rq.urls` is a module, not a URLconf — wrap with `include()`.

## Local — run on the host

```sh
uv run manage.py rqworker default
```

`settings.RQ["JOB_CLASS"]` is read globally by `rqworker`. No `--job-class` flag needed.

Open a second terminal alongside `uv run manage.py runserver`. `docker compose up -d redis` (and `db` if Postgres-in-Docker) must be running.

## VPS — docker-compose.prod.yml

```yaml
services:
  worker:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py rqworker default
    env_file: .env.prod
    logging: *logging
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
```

## Managed platforms

- **Fly.io** — `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "python manage.py rqworker default"
  ```
- **Railway / Render** — second service on the same image, command `python manage.py rqworker default`.

## Failed jobs

Failed tasks land in RQ's failed registry and sit there — nothing retries or surfaces them on its own. Inspect from the project venv (`rq` ships as a dependency):

```sh
uv run rq info --url "$REDIS_URL/3"
```

Requeue or clear from the same CLI (`rq requeue`) once the cause is fixed.
