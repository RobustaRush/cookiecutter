# Django Tasks (Django 6.0+)

Docs: <https://docs.djangoproject.com/en/dev/topics/tasks/>

Django 6.0 ships the `django.tasks` API in core: vendor-neutral `@task` decorator + `enqueue` / `enqueue_on_commit` / result-checking, modelled after `django.core.cache`. Pick a third-party backend for the actual queue. Lighter footprint than Celery (no broker if you pick the DB backend); but no Beat-equivalent scheduler, no chained workflows, no Flower-class UI yet.

Ask the user:

- **Database** — `references/tasks-django-db.md`. Simplest, no extra infrastructure.
- **Redis Queue** — `references/tasks-django-rq.md`. Needs Redis; better throughput.

Ask separately about **periodic tasks** (django-crontask) — `references/tasks-django-cron.md` if yes.

## Register tasks

`django.tasks` does **not** auto-scan apps — a task module is only visible once imported. Register it from `AppConfig.ready()`:

```python
# myapp/apps.py
from django.apps import AppConfig

class MyappConfig(AppConfig):
    name = "myapp"

    def ready(self) -> None:
        from . import tasks  # noqa: F401  — register @task functions
```

When the project already has a domain app, add `<app>/tasks.py` with `@task`-decorated functions. On a fresh project with no app yet, the worker boots and idles — the user creates an app and adds `tasks.py` when they have real work.
