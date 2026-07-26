# django-bolt

Docs: <https://bolt.farhana.li/>

Rust-powered API framework for Django. Runs its own HTTP server (Actix Web + PyO3 + msgspec), invoked through `manage.py runbolt`. Targets high-RPS JSON APIs while keeping access to Django ORM, admin, and packages.

Pre-1.0 — README explicitly says "under active development". Pin a version.

## Install

```sh
uv add django-bolt msgspec
```

`msgspec` is a transitive dep of `django-bolt`, but the API module imports it directly — pin it explicitly so the lockfile records it as a runtime dep.

The wheel includes a precompiled Rust extension; uv installs it on x86_64 / arm64 macOS and on x86_64 and aarch64 Linux without a toolchain. Pin both stages to `linux/amd64` when the deploy target is amd64 (Fly's default machines) so the image built on an Apple Silicon host matches the one that runs in production:

```dockerfile
FROM --platform=linux/amd64 ghcr.io/astral-sh/uv:python3.13-trixie-slim AS builder
# ...
FROM --platform=linux/amd64 python:3.13-slim-trixie AS prod
```

On Apple Silicon the amd64 build runs under emulation (slower locally); CI and Fly builders are native amd64 and build fast.

## settings.py / base.py

Add the Django app:

```python
INSTALLED_APPS = [
    # ...
    'django_bolt',
]
```

(Unlike `django-modern-rest`, this one *is* a Django app — it ships management commands, including `runbolt`.)

## Layout

`runbolt` discovers `BoltAPI()` instances via three paths, in order:

1. **Explicit** — `settings.BOLT_API = ["dotted.path:attr", ...]`. Wins if set.
2. **Project-level** — `<project>.api` or `<project>.bolt_api`, where `<project>` is `ROOT_URLCONF.split(".")[0]`. For stock `config.urls` that's `config/api.py`. No app, no `INSTALLED_APPS` entry.
3. **Per-app** — `<app>.api` / `<app>.bolt_api` for each app in `INSTALLED_APPS`. AppConfig may set `bolt_api = "dotted:attr"`.

Default to **project-level** — drop `config/api.py` next to `config/urls.py`. Do not auto-create an `api/` app.

Switch to **per-app** when the API grows its own models, admin, migrations, or splits across modules.

Use **`settings.BOLT_API`** for monorepos or shared API modules outside the `<project>` namespace.

## Minimal endpoint — `config/api.py`

```python
import msgspec
# Import the concrete model — `get_user_model()` returns a generic type
# that hides `.id` / `.username` from pyright.
from django.contrib.auth.models import User
from django_bolt import BoltAPI

api = BoltAPI()


class UserSchema(msgspec.Struct):
    id: int
    username: str


@api.get('/users/{user_id}')
async def get_user(user_id: int) -> UserSchema:
    user = await User.objects.aget(id=user_id)
    return UserSchema(id=user.pk, username=user.username)
```

If the project has a custom user model, import it from `users.models` instead.

Schemas must be `msgspec.Struct` — django-bolt is bound to msgspec and does not accept pydantic.

## Running

Two servers, two ports:

- `uv run manage.py runserver` — admin, classic Django views, port 8000.
- `uv run manage.py runbolt --dev --port 8001` — Bolt API. `runbolt` also defaults to 8000, so the port flag is required or the second process fails to bind.

Document both in `README.md`. In production, deploy `runbolt` behind the same reverse proxy as gunicorn (different upstream blocks, different paths). The README states "no gunicorn or uvicorn needed" for the Bolt side specifically.

## Fast-path settings (optional, advanced)

By default, `runbolt` and `runserver` / `gunicorn` share the same settings module — process separation comes for free, settings separation is a second, opt-in step. Only do this if RPS was the explicit reason for picking django-bolt over django-modern-rest. The cost is two settings modules that can drift: every new app, signal, or middleware added to `base.py` requires a conscious decision about whether the bolt process needs it.

Add `config/settings/bolt.py` that imports from `base` and strips what the API path doesn't need:

```python
from .base import *
from .base import INSTALLED_APPS, MIDDLEWARE

# Auth happens in Rust (JWT / API key) — Django auth middleware adds no value.
# Sessions / messages / CSRF only apply to browser flows that don't reach bolt.
_DROP_MIDDLEWARE = {
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
}
MIDDLEWARE = [m for m in MIDDLEWARE if m not in _DROP_MIDDLEWARE]

# Admin / sessions / messages / staticfiles aren't served by bolt.
_DROP_APPS = {
    'django.contrib.admin',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
}
INSTALLED_APPS = [a for a in INSTALLED_APPS if a not in _DROP_APPS]

# No HTML rendering on the API path.
TEMPLATES = []

ROOT_URLCONF = 'config.urls_bolt'  # API-only URLConf, no admin / accounts
```

`config/urls_bolt.py` is the API-only URLConf. `runbolt` discovers routes from the `BoltAPI()` instances directly — `BoltAPI` has no `.urls` attribute to mount, so the URLConf stays empty:

```python
# config/urls_bolt.py
urlpatterns: list = []
```

Keep `config/urls.py` as the full URLConf for `runserver` / `gunicorn`.

Run bolt against the slim settings; leave the full stack on the regular settings:

```sh
# API process (high RPS path)
DJANGO_SETTINGS_MODULE=config.settings.bolt uv run manage.py runbolt --dev --port 8001

# Admin / classic views (separate process, full middleware stack)
uv run manage.py runserver
```

In production: same split — bolt service uses `DJANGO_SETTINGS_MODULE=config.settings.bolt`, gunicorn uses `config.settings.production`. Reverse proxy routes `/api/*` to bolt, everything else to gunicorn.

### When NOT to do this

- The user picked bolt without a specific RPS target — keep one settings module, skip this.
- The API touches `request.user` via `django.contrib.auth` (sessions). The fast-path drops auth middleware; only viable when auth is fully token-based and validated in Rust.
- The team is small and the drift cost outweighs the per-request savings.

## Auth

`django-bolt` validates JWT / API keys in Rust without taking the Python GIL. Configuration goes through its own settings — see https://bolt.farhana.li/topics/authentication/. Do **not** wire DRF-style auth classes; they don't apply.

If the user picked `django-allauth` / `django-mail-auth` for the Django side, those continue to handle session / magic-link auth on the `runserver` side. The Bolt side uses tokens.

## OpenAPI

Auto-generated. The library ships Swagger, ReDoc, Scalar, and RapidDoc UIs — pick one in settings. Gate the docs UI on `DEBUG` unless a public schema is wanted.

## Boot check

Standard `migrate` + `createsuperuser` first. Then verify the Bolt server boots:

```sh
uv run manage.py runbolt --dev --port 8001 &
BOLT_PID=$!
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:8001/users/1 > /dev/null && up=1 && break
  sleep 1
done
kill "$BOLT_PID"
[ -n "$up" ] || echo "BOOT CHECK FAILED"
```

## Pitfalls

- Two HTTP servers in dev — make sure the user understands `runserver` and `runbolt` are different processes.
- Production deploy: the production Dockerfile must expose / launch `runbolt`, not gunicorn, for the API path. Update `references/docker.md` snippets accordingly when both are present.
- msgspec-only — if the user wants pydantic, they want `django-modern-rest`, not `django-bolt`.
- Pre-1.0; pin the version.
