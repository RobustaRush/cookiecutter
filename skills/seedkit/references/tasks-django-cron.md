# Django Tasks — Periodic (django-crontask)

Docs: <https://github.com/codingjoe/django-crontask>

Add this only if the user needs scheduled tasks. Works alongside either Database or Redis Queue backend.

## Install

```sh
uv add django-crontask
```

## INSTALLED_APPS

```python
INSTALLED_APPS = [
    ...
    "crontask",
]
```

## Define

```python
from django_tasks import task
from crontask import cron

@cron("0 8 * * *")  # daily at 08:00 (crontab syntax)
@task()
def daily_report() -> None:
    ...
```

`crontask`'s `@cron` calls `task.enqueue()` on whatever it wraps, so the decorated task must resolve through the same backend as the Database/Redis Queue worker — import `task` from the `django_tasks` backport, not Django 6's stdlib `django.tasks`.

## Local — run on the host

```sh
uv run manage.py crontask
```

Third terminal alongside the worker and runserver.

## VPS — docker-compose.prod.yml

```yaml
services:
  cron:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    command: python manage.py crontask
    env_file: .env.prod
    logging: *logging
    depends_on:
      db:
        condition: service_healthy
```

## Managed platforms

Add a third process for cron alongside web and worker.
