# Storage — WhiteNoise + Local Media

Docs: <https://whitenoise.evans.io/>

WhiteNoise serves **static files only**. User-uploaded media goes elsewhere:

- **VPS**: Caddy serves media from a Docker volume.
- **Managed platforms**: ephemeral filesystems lose media on redeploy — use `storage-s3.md`.

## Install

```sh
uv add whitenoise
```

## Settings — base / single-file

Static + media paths only (no middleware in base — runserver serves
static via finders in dev, and WhiteNoise's manifest storage needs
`collectstatic` to have run):

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
```

## Settings — production.py

Insert `WhiteNoiseMiddleware` directly after `SecurityMiddleware`, and
flip `staticfiles` to manifest storage:

```python
sec_idx = MIDDLEWARE.index("django.middleware.security.SecurityMiddleware")
MIDDLEWARE.insert(sec_idx + 1, "whitenoise.middleware.WhiteNoiseMiddleware")

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
}
```

(Single-file layout: gate both on `not DEBUG`.)

`CompressedManifestStaticFilesStorage` is the only switch needed for compression + hashed filenames.

`STORAGES` (Django 4.2+) replaces legacy `STATICFILES_STORAGE` and `DEFAULT_FILE_STORAGE`. Don't set the legacy keys alongside it.

## config/urls.py

Serve media in dev:

```python
from django.conf import settings
from django.conf.urls.static import static

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

## VPS — docker-compose.prod.yml

Shared `media` volume between `web` and `caddy`. The production Dockerfile
runs gunicorn as `USER django`, but Docker copies image contents into a
**fresh** named volume only on first creation — and the resulting mount
point is owned by root. Pre-create `/app/media` with `chown django:django`
in the Dockerfile *before* the volume mounts in, otherwise the first upload
fails with `EACCES`:

```dockerfile
# In the production Dockerfile, before `USER django`:
RUN mkdir -p /app/media && chown django:django /app/media
```

```yaml
services:
  web:
    volumes:
      - media:/app/media

  caddy:
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - media:/srv/media:ro

volumes:
  pgdata:
  caddy_data:
  caddy_config:
  media:
```

## VPS — Caddyfile

Media block: see `references/deploy-vps.md` (`## deploy/Caddyfile`, the `handle /media/*` block with `uri strip_prefix /media`).

## Managed platforms

WhiteNoise serves static from the container — nothing extra. Media on managed platforms needs external storage; use `storage-s3.md`.
