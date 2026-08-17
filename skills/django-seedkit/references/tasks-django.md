# Django Tasks (core)

Docs: <https://docs.djangoproject.com/en/6.1/topics/tasks/>

Django ships `django.tasks` in core. It provides task declaration, enqueueing, and result APIs; its built-in backends are `ImmediateBackend` and `DummyBackend`, not a worker queue. Use Celery when work must run asynchronously in a separate worker.

Use the default immediate backend unless the user needs a different explicitly supported backend. For periodic work, apply `references/tasks-django-cron.md`.

## Register tasks

`django.tasks` does not auto-scan apps. Register a task module from `AppConfig.ready()`:

```python
# myapp/apps.py
from django.apps import AppConfig

class MyappConfig(AppConfig):
    name = "myapp"

    def ready(self) -> None:
        from . import tasks  # noqa: F401  — register @task functions
```

When the project already has a domain app, add `<app>/tasks.py` with `@task`-decorated functions. On a fresh project with no app yet, the worker boots and idles — the user creates an app and adds `tasks.py` when they have real work.

## Result status

```python
from django.tasks import TaskResultStatus

result = greet.enqueue("world")
assert result.status == TaskResultStatus.SUCCESSFUL
```

The members are `READY`, `RUNNING`, `SUCCESSFUL`, and `FAILED`.
