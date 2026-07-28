# Type checking — pyright + django-stubs

Docs: <https://microsoft.github.io/pyright/> · <https://github.com/typeddjango/django-stubs>

Pyright plus `django-stubs` add static types for the ORM, querysets, and request/response cycle. The same `[tool.pyright]` block in `pyproject.toml` is read by CI and the editor.

Skip this if your project doesn't use type hints — checking untyped code only produces noise.

## Install

```sh
uv add --dev pyright django-stubs django-stubs-ext
```

`django-stubs-ext` is the runtime companion that makes generics like `Manager[User]` and `QuerySet[Order]` evaluate at import time. The activation call sits at the bottom of `config/settings/base.py` (or `config/settings.py` for single-file), guarded so the prod image (`uv sync --no-dev`, no dev group) just skips it:

```python
try:
    import django_stubs_ext
except ImportError:
    pass                       # dev-only dep; prod doesn't need it
else:
    django_stubs_ext.monkeypatch()
```

Without the guard, the dev-only dep would have to be promoted to main deps to keep `runserver` / `gunicorn` from `ImportError`-ing on startup. The guard keeps the runtime image lean.

## Config

`pyproject.toml`:

```toml
[tool.pyright]
include = ["."]
exclude = [
    "**/migrations/**",
    "**/__pycache__",
    ".venv",
    "staticfiles",
    "media",
    # django-environ's conditional default pattern (`default="x" if DEBUG else env.NOTSET`)
    # produces false-positive reportArgumentType errors — pyright sees `str | NoValue`
    # where `NoValue` is expected. Excluding settings avoids dozens of spurious errors.
    "config/settings",
]
venvPath = "."
venv = ".venv"
pythonVersion = "3.13"               # the concrete runtime pin — see references/conventions.md
typeCheckingMode = "basic"           # "standard" once code is typed; "strict" is noisy on Django
useLibraryCodeForTypes = true        # read source for packages without stubs (allauth, axes, …)
reportMissingTypeStubs = "none"      # third-party stubs are optional
strictListInference = true
```

## Run

```sh
uv run pyright
uv run pyright path/to/file.py    # one file
```

## CI

In `.github/workflows/test.yml`, before `pytest`:

```yaml
      - run: uv run pyright
```

Failing pyright should fail the build — type errors don't surface at test time.

## Pre-commit hook

If `references/pre-commit.md` is applied, add:

```yaml
  - repo: https://github.com/RobertCraigie/pyright-python
    rev: v1.1.411
    hooks:
      - id: pyright
```

## Add-on stub packages

Most third-party packages don't ship stubs. With `useLibraryCodeForTypes = true` (set above) and `reportMissingTypeStubs = "none"` pyright reads source for inference and stays quiet about missing `.pyi` files — no action needed in most cases. Two exceptions worth installing when the matching add-on is selected:

| Add-on selected | Extra dev dep |
|---|---|
| Celery (`references/tasks-celery.md`) | `uv add --dev celery-types` |
| Stripe billing (`references/billing.md`) | none — `stripe` ships PEP 561 types |
| structlog (`references/logging.md`) | none — `structlog` ships types |
| sentry-sdk (`references/error-reporting.md`) | none — ships types |
| django-modern-rest / django-bolt (`references/rest-*.md`) | none — both ship types |

Allauth, axes, django-tasks, django-tailwind-cli, dj-stripe — no stubs, fall back to `useLibraryCodeForTypes`.

## Pragmatics

- Migrations rarely type-check cleanly — already excluded above.
- Admin `ModelAdmin` subclasses often need `# type: ignore[attr-defined]` on lines that touch dynamically-added attributes.
- Use `if TYPE_CHECKING:` to import heavy types (factories, test fixtures) without runtime cost.
- For `request.user` to type as your custom `User` (not `AbstractBaseUser | AnonymousUser`), import `django.contrib.auth.models.AbstractBaseUser` and narrow with `assert request.user.is_authenticated` before access — django-stubs handles the rest.
- `get_user_model()` returns the generic `_UserModel` stub, so `user.email` (or any custom field) trips `reportAttributeAccessIssue`. Import the concrete model under `TYPE_CHECKING` instead of paying for `getattr` at runtime: `if TYPE_CHECKING: from users.models import User`, then `user: "User" = get_user_model().objects.get(...)`.
- Bump `typeCheckingMode` to `"standard"` once the codebase has real type hints; jump straight to `"strict"` only after that pass is clean.
