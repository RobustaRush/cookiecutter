# New Django Project

Docs: <https://django-environ.readthedocs.io/> · <https://docs.djangoproject.com/en/6.1/intro/tutorial01/>

Bootstrap with uv on the host. Docker (`references/docker.md`) only
changes how the project runs — its `.venv` rebuilds from the
`pyproject.toml` / `uv.lock` written here.

## Create

```sh
uv init --bare {project_slug}     # --bare: no main.py / README.md / .python-version
cd {project_slug}
# Pin to Django 6.1's floor BEFORE `uv add` — uv init's host pin is too tight.
sed -i.bak -E 's/^requires-python = .*/requires-python = ">=3.12"/' pyproject.toml && rm pyproject.toml.bak
uv add 'django>=6.1,<7.0' django-environ
uv run django-admin startproject config .
```

In `config/settings.py`, replace only `SECRET_KEY` / `DEBUG` /
`ALLOWED_HOSTS` / `DATABASES`. Leave everything else `startproject` wrote.

## Settings — ask which structure

Use the snippets verbatim.

### Option A — single file

Replace the four named values in `config/settings.py`:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else env.NOTSET)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])  # DEBUG already accepts localhost / 127.0.0.1 / [::1]
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else env.NOTSET)}  # 4 slashes = absolute, survives running manage.py from any cwd

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
```

Defaults are gated by `DEBUG`: in production `DJANGO_DEBUG` is unset and
`env.NOTSET` makes `django-environ` raise `ImproperlyConfigured` naming
the missing variable.

After inserting these lines at the top of `settings.py`, delete the
original hardcoded `DATABASES` block + `# Database` comment that
`startproject` emitted — leaving both makes `DATABASE_URL` dead code.

### Option B — split (base / local / production)

```sh
mkdir config/settings
mv config/settings.py config/settings/base.py
touch config/settings/__init__.py
```

`config/settings/base.py` — same four-value replacement (note `BASE_DIR`
jumps one level up):

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else env.NOTSET)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else env.NOTSET)}  # 4 slashes = absolute, survives running manage.py from any cwd
```

After inserting these lines at the top of `base.py`, delete the original
hardcoded `DATABASES` block + `# Database` comment that `startproject`
emitted in the file you moved — bottom wins, leaving both makes
`DATABASE_URL` dead code.

`local.py`, `production.py`, and `test.py` carry **only deltas** from
`base.py`. `test.py` overrides what tests need cheap and deterministic —
locmem email + cache, fast password hasher, eager task backend, in-memory
storage, `DEBUG=False` to surface template errors. Never restate values
base sets; never redeclare `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES`
/ `MAILERS` / `STORAGES`. Mutate inherited lists in place:

```python
# config/settings/local.py
from .base import *
```

```python
# config/settings/production.py
from .base import *

# MIDDLEWARE += [...]                      # order doesn't matter
# MIDDLEWARE.insert(1, "...")              # order matters (e.g. WhiteNoise after SecurityMiddleware)
```

```python
# config/settings/test.py
from .base import *

DEBUG = False                              # surface TemplateSyntaxError instead of swallowing it
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
MAILERS = {
    "default": {"BACKEND": "django.core.mail.backends.locmem.EmailBackend"},
}
CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.InMemoryStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
# Django Tasks: run inline in the request thread so tests see results without a worker.
TASKS = {"default": {"BACKEND": "django.tasks.backends.immediate.ImmediateBackend"}}
# Celery: same pattern — eager execution in the calling thread, no worker required.
# Harmless when Celery isn't installed; the keys are just ignored.
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True
```

Don't re-instantiate `env = environ.Env()` — it's already imported via
`from .base import *`.

Edit `os.environ.setdefault("DJANGO_SETTINGS_MODULE", ...)` in **all three** entry points — `startproject` left them pointing at `config.settings` (now the empty package dir):

- `manage.py` → `config.settings.local`
- `config/wsgi.py` → `config.settings.production`
- `config/asgi.py` → `config.settings.production`

Safety asymmetry: a prod box without `DJANGO_SETTINGS_MODULE` set still boots with hardening on; dev commands default to dev tooling.

## Static files

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## Root URL

`startproject`'s `config/urls.py` only routes `/admin/`, so `/` 404s.
Add a redirect so the starter is usable out of the box; replace once
the project has a real home view.

```python
# config/urls.py
from django.contrib import admin
from django.urls import path
from django.views.generic import RedirectView

urlpatterns = [
    path("", RedirectView.as_view(url="/admin/", permanent=False)),
    path("admin/", admin.site.urls),
]
```

## .env.example and .env

Commit `.env.example` with every env var settings reads:

```sh
DJANGO_SECRET_KEY=replace-me
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
```

Then `cp .env.example .env` and set a real dev key:

```sh
KEY=$(uv run python -c "import secrets; print(secrets.token_urlsafe(50))")
uv run python -c "
import pathlib, re
p = pathlib.Path('.env')
p.write_text(re.sub(r'^DJANGO_SECRET_KEY=.*$', f'DJANGO_SECRET_KEY=$KEY', p.read_text(), flags=re.M))
"
```

Use `secrets.token_urlsafe`, not Django's `get_random_secret_key()`.
The latter emits `$ & ( ) ' " \`, which breaks shell sourcing,
Compose's `$VAR` interpolation, and naive `sed` rewrites. `token_urlsafe`
produces `[A-Za-z0-9_-]` only.

`.env` is gitignored. Keep `.env.example` in sync as new `env(...)`
calls land.

## .gitignore

Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`,
`.ruff_cache/`. Add other standard Python / Django / editor / tooling
entries before the first commit.

## Boot check

```sh
uv run manage.py migrate
```

Then the backgrounded `runserver --noreload` + curl poll from SKILL.md §4.
`createsuperuser` and the browser login belong to SKILL.md §7 — they need a
stable task-runner name and a real browser. For docker-compose, see
`references/docker.md`.

## Scripts (optional)

See `references/dev-tasks.md` to wire short task names (`dev`, `migrate`, `test`, `lint`) onto the long `uv run …` commands above.
