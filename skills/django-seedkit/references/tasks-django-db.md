# Django Tasks — Database backend

Docs: <https://github.com/RealOrangeOne/django-tasks-database>

`django-tasks-db` stores tasks in your existing DB. No broker, no extra service.

## Install

```sh
uv add django-tasks-db django-tasks
```

`django-tasks-db` 0.12.0 is built against the standalone `django-tasks` backport (import path `django_tasks`) — Django 6's stdlib `django.tasks` is a separate module. Use `from django_tasks import task` in app code. `django-tasks` is listed explicitly because `django_tasks` registers in `INSTALLED_APPS`; the adapter's own pin is not a declaration.

## INSTALLED_APPS

`django_tasks` (the backport app) is the Tasks API; `django_tasks_db` ships the task-table migrations. Both register:

```python
INSTALLED_APPS = [
    ...
    "django_tasks",
    "django_tasks_db",
]
```

## Settings

```python
TASKS = {"default": {"BACKEND": "django_tasks_db.DatabaseBackend"}}
```

## Test settings

The eager backend in `config/settings/test.py` comes from the backport too:

```python
TASKS = {"default": {"BACKEND": "django_tasks.backends.immediate.ImmediateBackend"}}
```

## Migrate

```sh
uv run manage.py migrate
```

## Prune finished results

Finished and failed task rows stay in the table forever. Schedule the bundled command — host cron on a VPS (next to the `dbbackup` lines if present), or the task runner:

```sh
python manage.py prune_db_task_results --min-age-days 14
```

## Local — run on the host

```sh
uv run manage.py db_worker
```

Open a second terminal alongside `uv run manage.py runserver`. The worker shares the project venv and reads from the same DB.

## VPS — docker-compose.prod.yml

Production image has `/opt/venv/bin` on `PATH`:

```yaml
services:
  worker:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py db_worker
    env_file: .env.prod
    logging: *logging
    depends_on:
      db:
        condition: service_healthy
```

## Managed platforms

- **Fly.io** — `fly.toml`:
  ```toml
  [processes]
    web = "gunicorn config.wsgi --bind 0.0.0.0:8000"
    worker = "python manage.py db_worker"
  ```
- **Railway / Render** — second service on the same image, command `python manage.py db_worker`.
