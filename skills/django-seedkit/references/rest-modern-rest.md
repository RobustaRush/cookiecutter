# django-modern-rest

Docs: <https://django-modern-rest.readthedocs.io/>

Typed REST framework for Django. Sits inside the normal request/response cycle — no new runtime. Sync or async handlers; pluggable schema libs (pydantic, msgspec, attrs, dataclasses, TypedDict).

Requires `django>=5.0`, Python 3.11+.

## Install

`msgspec` is the recommended schema engine (fastest JSON path). Add it as the default:

```sh
uv add 'django-modern-rest[msgspec,openapi]>=0.11,<1.0' 'pyjwt[crypto]'
```

Pre-1.0 release — constrain it below 1.0. `pyjwt` comes along even without dmr's JWT auth: its throttling module imports `jwt` unconditionally. For DMR JWT auth itself, add the `jwt` extra (`'django-modern-rest[msgspec,openapi,jwt]>=0.11,<1.0'`).

If the user wants pydantic schemas instead, swap `msgspec` → `pydantic`. Both extras can co-exist.

Add `'dmr'` to `INSTALLED_APPS` only to serve the OpenAPI UI's static files (needs `django.contrib.staticfiles` with `AppDirectoriesFinder`). Plain endpoints and a YAML/JSON schema view need no app entry.

## Layout

REST endpoints live inside a registered Django app, not at project root. If the user has no app yet, create one: `uv run manage.py startapp api`.

```
api/
  __init__.py
  apps.py
  controllers.py    # Controller classes
  schemas.py        # request / response models
  urls.py           # router wiring
```

## Minimal endpoint

Use msgspec by default. The user can substitute pydantic by importing `dmr.plugins.pydantic.PydanticFastSerializer` and `pydantic.BaseModel`.

```python
# api/schemas.py
import uuid
import msgspec


class UserCreate(msgspec.Struct):
    email: str


class User(msgspec.Struct):
    uid: uuid.UUID
    email: str
```

```python
# api/controllers.py
import uuid
from dmr import Body, Controller
from dmr.plugins.msgspec import MsgspecSerializer

from .schemas import User, UserCreate


class UserController(Controller[MsgspecSerializer]):
    async def post(self, parsed_body: Body[UserCreate]) -> User:
        return User(uid=uuid.uuid4(), email=parsed_body.email)
```

`Controller.post` / `.get` / `.patch` / `.delete` map to HTTP verbs. Both sync and async are supported — pick whichever matches the surrounding code.

## URL wiring — `api/urls.py`

```python
from dmr.routing import Router
from django.urls import path

from .controllers import UserController

router = Router(
    'api/',
    [
        path('users/', UserController.as_view(), name='users'),
    ],
)
```

## `config/urls.py`

```python
from django.urls import include, path
from api.urls import router

urlpatterns = [
    # ... existing routes
    path(router.prefix, include((router.urls, 'api'), namespace='api')),
]
```

## OpenAPI

The `[openapi]` extra adds schema validation, a YAML view, and richer examples via polyfactory. Wire the schema view per the upstream docs (https://django-modern-rest.readthedocs.io/) — keep the URL behind `if settings.DEBUG` unless the user wants a public schema.

## Boot check

Adds nothing to the standard boot check. After `migrate` + `createsuperuser`:

```sh
curl -sf -X POST http://127.0.0.1:8000/api/users/ \
  -H 'content-type: application/json' \
  -d '{"email":"a@b.com"}'
```

## Pitfalls

- Don't put controllers in `config/` — Django app discovery only scans `INSTALLED_APPS`.
- `dmr` belongs in `INSTALLED_APPS` only for the OpenAPI UI's static files — see Install. Adding it for plain endpoints buys nothing.
