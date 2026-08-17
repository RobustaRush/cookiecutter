# Frontend — django-tailwind-cli

Docs: <https://django-tailwind-cli.readthedocs.io/> · <https://daisyui.com/>

Tailwind CSS via the prebuilt standalone CLI. **No Node.js, no npm, no webpack.** The package downloads a single binary at first run and rebuilds CSS via a Django management command. Inspired by the Phoenix tailwind integration.

Requires Django 4.2+ and Python 3.10+.

## Install

```sh
uv add django-tailwind-cli
```

## settings — `base.py`

```python
INSTALLED_APPS = [
    # ...
    'django_tailwind_cli',
]

# Tailwind CLI scans templates listed via @source directives in the source CSS;
# STATICFILES_DIRS = [BASE_DIR / "assets"] is where the compiled CSS lands.
STATICFILES_DIRS = [BASE_DIR / 'assets']
```

The directory must exist on disk before `runserver` boots — Django raises at startup otherwise.

```sh
mkdir -p assets
```

Use the current compatible Tailwind 4 release when generating the project. Do not hardcode its patch version in this skill. Set the custom source path in `base.py` or single-file settings:

```python
TAILWIND_CLI_SRC_CSS = "tailwind-src/css/source.css"   # custom source — outside STATICFILES_DIRS
```

For production images, also set `TAILWIND_CLI_AUTOMATIC_DOWNLOAD = False` and bake the binary in at build time, OR run `python manage.py tailwind build` during the image build (preferred — no extra binary management).

## Templates

```
templates/
  base.html
  index.html
```

Document the `templates/` directory in `TEMPLATES[0]['DIRS']` if `APP_DIRS` alone isn't enough:

```python
TEMPLATES = [{
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [BASE_DIR / 'templates'],
    'APP_DIRS': True,
    # ...
}]
```

### `templates/base.html`

```django
{% load tailwind_cli %}
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}{{ project_name }}{% endblock %}</title>
    {% tailwind_css %}
</head>
<body class="bg-gray-50 text-gray-900">
    <div class="container mx-auto px-4 py-8">
        {% block content %}{% endblock %}
    </div>
</body>
</html>
```

`{% tailwind_css %}` injects the right `<link>` for dev (live-rebuilt) and prod (collected) without conditionals in templates.

## Dev workflow

```sh
# One process — runserver + tailwind watcher under Django's autoreloader:
python manage.py tailwind runserver

# Or, two terminals:
python manage.py tailwind watch
python manage.py runserver
```

`tailwind runserver` is a transparent passthrough — every flag of `runserver` (or `runserver_plus`) works.

In the container dev loop, keep the one-process form: make `tailwind runserver` the `web` service's `command:` (`references/docker.md`, "Django in the container"). The download lands in the bind-mounted `.django_tailwind_cli/`, and the standalone CLI is a platform-specific binary — after a switch between the host loop and the container loop, delete that directory so the first run fetches the right one.

First run downloads the CLI to `<BASE_DIR>/.django_tailwind_cli/` and creates an auto-generated `source.css`. The directory is auto-gitignored — don't add it manually.

## Production build

The compiled CSS must exist in `STATICFILES_DIRS[0]` before `collectstatic` runs.

In the multi-stage Dockerfile from `references/docker.md`, add this RUN to the
builder stage immediately above the `collectstatic` RUN that file already owns:

```dockerfile
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
    /opt/venv/bin/python manage.py tailwind build
```

The step needs the production settings + `DJANGO_DEBUG=True` shim:
`manage.py` defaults to `local.py`, which requires env vars (`SECRET_KEY`,
`DATABASE_URL`) that don't exist at image-build time. `DJANGO_DEBUG=True`
keeps those gated as dev-only. `/opt/venv/bin/python` because the builder
stage never puts the venv on `PATH` — only the prod stage does.

`tailwind build` produces a minified, purged CSS file at `STATICFILES_DIRS[0] / "css" / "tailwind.css"` (configurable via `TAILWIND_CLI_DIST_CSS`). `collectstatic` then picks it up and WhiteNoise / S3 serves it.

## Class sorting

Only when `references/pre-commit.md` is applied. Add to `.pre-commit-config.yaml` so every
`class="…"` lands in Tailwind's canonical order and two developers editing one template stop
producing conflicting attribute orders:

```yaml
  - repo: local
    hooks:
      - id: rustywind
        name: rustywind Tailwind class sorter
        language: node
        additional_dependencies: [rustywind@latest]
        entry: rustywind
        args: [--write]
        types_or: [html]
```

Pre-commit installs the Node package into its own environment — the project stays Node-free.

## DaisyUI (optional)

DaisyUI is a component layer on top of Tailwind: instead of stringing utilities you write `btn btn-primary`, `card`, `navbar`, `alert alert-warning`. Apply only when the skill's DaisyUI follow-up got `yes`.

We follow the upstream Django guide (<https://daisyui.com/docs/install/django/>) — register DaisyUI as a Tailwind 4 plugin via a `@plugin` directive in the source CSS. No `TAILWIND_CLI_USE_DAISY_UI` flag, no fork of the binary; the regular `django-tailwind-cli` Tailwind CLI loads the plugin.

### 1. Drop the DaisyUI bundle next to the source CSS

DaisyUI ships single-file `.mjs` plugin bundles per release. Resolve a compatible current DaisyUI 5 release before writing these commands. Place them under `tailwind-src/css/` — **outside `STATICFILES_DIRS`**. `CompressedManifestStaticFilesStorage` walks every file in `STATICFILES_DIRS` and tries to resolve each `@import` / `@plugin` reference as a static-file URL; with `source.css` inside, `collectstatic` fails with `MissingFileError: css/tailwindcss`. Keep only the compiled `tailwind.css` output under `assets/`.

```sh
mkdir -p tailwind-src/css
curl -fsSL -o tailwind-src/css/daisyui.mjs \
    https://github.com/saadeghi/daisyui/releases/download/v{daisyui_version}/daisyui.mjs
curl -fsSL -o tailwind-src/css/daisyui-theme.mjs \
    https://github.com/saadeghi/daisyui/releases/download/v{daisyui_version}/daisyui-theme.mjs
```

Commit both files — they're vendored assets, not build artefacts. Reproducible builds depend on the exact bundle that was committed.

### 2. Point the CLI at a custom source CSS

```python
# settings (base.py or single settings.py)
TAILWIND_CLI_SRC_CSS = 'tailwind-src/css/source.css'
```

### 3. Author the source CSS

```css
/* tailwind-src/css/source.css */
@import "tailwindcss";

@source not "./tailwindcss";
@source not "./daisyui{,*}.mjs";

@plugin "./daisyui.mjs";
```

The two `@source not` lines exclude the CLI binary and the bundle file from Tailwind's template scan. The `@plugin` line loads DaisyUI; the relative path is resolved against the source CSS file's location, so `daisyui.mjs` must sit next to it.

### 4. Build / watch

Standard commands work unchanged:

```sh
python manage.py tailwind build       # production
python manage.py tailwind runserver   # dev (watch + runserver)
```

### Theme

DaisyUI ships light/dark via `data-theme`. Set the default in `templates/base.html`:

```django
<html lang="en" data-theme="light">
```

For server-driven theme switching (user preference column), pass the value into the template context — first paint matches the user's saved theme without a JS flash.

### Smoke test

```django
{% extends "base.html" %}
{% block content %}
<button class="btn btn-primary">DaisyUI works</button>
{% endblock %}
```

A working integration: rendered button has DaisyUI's primary-colour background, and the served CSS contains `.btn` and `.btn-primary` rules.

### Pitfalls

- DaisyUI component-class specificity isn't always lower than utility classes. Confirm before mixing them on the same element.
- Bundle adds ~10–30 KB gzipped depending on enabled themes. Worth knowing for landing pages.
- DaisyUI defines its own `prose` / `card` — only enable `@tailwindcss/typography` if there's a real conflict.
- When you bump the pinned daisyUI version, re-run both `curl` commands and commit `daisyui.mjs` + `daisyui-theme.mjs` together. Mismatched bundles break theme tokens.

## Pitfalls

- **Empty `STATICFILES_DIRS[0]`**: must exist as a real directory before boot.
- **Tailwind 4.x discovers templates only via `@source` directives** in `source.css`. Adding a new `templates/` location means adding a matching `@source` line — Tailwind won't auto-find it.
- **Production without `tailwind build`**: `collectstatic` runs but ships an empty / stale CSS file. Always `tailwind build` first.
- **Don't put the binary in the image cache layer above `uv sync`**: changes to lockfile shouldn't invalidate the binary download.
- **`{% tailwind_css %}` needs `{% load tailwind_cli %}`**: easy to forget when copying snippets.

## Index view (smoke test)

Add a trivial root URL to confirm Tailwind classes render. In any registered Django app:

```python
# pages/views.py
from django.views.generic import TemplateView


class IndexView(TemplateView):
    template_name = 'index.html'
```

```python
# config/urls.py
from django.urls import path
from pages.views import IndexView

urlpatterns = [
    # ...
    path('', IndexView.as_view(), name='index'),
]
```

```django
{# templates/index.html #}
{% extends "base.html" %}
{% block content %}
<h1 class="text-4xl font-bold text-blue-600">It works.</h1>
<p class="mt-4 text-lg text-gray-700">Tailwind classes resolved against this page.</p>
{% endblock %}
```

A working integration: `curl -sf /` returns 200, the response body contains `text-blue-600`, and the `<link>` injected by `{% tailwind_css %}` resolves (200) to a CSS file containing the corresponding class.

## Custom error templates (404 / 403 / 500)

Apply when the user opts into custom error pages (follow-up question after Frontend; default **no**). Without these, a 500 in production renders Django's default page — visually inconsistent with the rest of the site.

Django picks up `404.html`, `403.html`, `500.html` from the project's template root automatically (no URL wiring) when `DEBUG = False`. They render with **no** request context — `RequestContext` is unavailable for 500. Keep them static.

```
templates/
  base.html
  404.html
  403.html
  500.html
```

Minimal `templates/404.html`:

```django
{% load tailwind_cli %}
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Not found</title>
    {% tailwind_css %}
</head>
<body class="bg-gray-50 text-gray-900">
    <div class="container mx-auto px-4 py-24 text-center">
        <h1 class="text-6xl font-bold text-gray-700">404</h1>
        <p class="mt-4 text-lg">This page doesn't exist.</p>
    </div>
</body>
</html>
```

`403.html` and `500.html` follow the same shape — different heading and copy. Don't extend `base.html` for `500.html` specifically: any template error in `base.html` would itself raise during rendering, masking the original 500.

### Verifying

In production-shaped settings (`DEBUG=False`, `ALLOWED_HOSTS` set):

```sh
curl -sf -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/this-route-does-not-exist
# expect: 404
curl -s http://127.0.0.1:8000/this-route-does-not-exist | grep -q 'text-6xl'
```

### Pitfalls

- `DEBUG=True` always renders Django's debug page, ignoring `404.html`. Test with `DEBUG=False` (and a real `ALLOWED_HOSTS`) or the templates appear "not picked up" when they actually are.
- Don't reference user-data context in `500.html`. The exception handler runs *outside* the normal request cycle — anything that touches the DB or the session can re-trigger an exception inside the error page.
- The `@source` directives in `source.css` must cover the error templates; otherwise their utility classes get purged out of the production CSS bundle.
