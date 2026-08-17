# Django Tasks — Periodic (django-crontask)

Docs: <https://github.com/codingjoe/django-crontask>

Add this only if the user needs scheduled core Django Tasks.

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
from django.tasks import task
from crontask import cron

@cron("0 8 * * *")  # daily at 08:00 (crontab syntax)
@task()
def daily_report() -> None:
    ...
```

`crontask` schedules the core `django.tasks` task through its configured backend.

## Run

```sh
uv run manage.py crontask
```

Run it as a separate process alongside the web process.

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

Add a cron process alongside the web process.
