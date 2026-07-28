# Storage — S3

Docs: <https://django-storages.readthedocs.io/en/latest/backends/amazon-S3.html> · <https://min.io/docs/minio/linux/index.html>

Static and media in an S3-compatible bucket. Works on every deploy target including managed platforms with ephemeral filesystems.

Compatible providers: AWS S3, DigitalOcean Spaces, Cloudflare R2, Backblaze B2, MinIO.

## Install

```sh
uv add 'django-storages[s3]'
```

## Settings

This block **replaces** any `MEDIA_URL` / `MEDIA_ROOT` set in the foundation. `STATIC_URL` / `STATIC_ROOT` stay — base keeps Django's local staticfiles backend, which needs `STATIC_ROOT` to run `collectstatic` at all; `production.py` flips static to the bucket.

`STORAGES` (Django 4.2+) replaces legacy `STATICFILES_STORAGE` / `DEFAULT_FILE_STORAGE`. Don't set the legacy keys alongside it.

```python
# Gated defaults match the foundation pattern: dev/build runs zero-config,
# prod (DEBUG unset) raises ImproperlyConfigured if any of these is missing.
AWS_ACCESS_KEY_ID     = env("AWS_ACCESS_KEY_ID",     default="" if DEBUG else env.NOTSET)
AWS_SECRET_ACCESS_KEY = env("AWS_SECRET_ACCESS_KEY", default="" if DEBUG else env.NOTSET)
AWS_STORAGE_BUCKET_NAME = env("AWS_STORAGE_BUCKET_NAME", default="" if DEBUG else env.NOTSET)
AWS_S3_REGION_NAME = env("AWS_S3_REGION_NAME", default="us-east-1")
# Non-AWS providers (MinIO, R2, B2, Spaces): set the endpoint, skip
# AWS_S3_CUSTOM_DOMAIN so django-storages signs URLs against the endpoint.
AWS_S3_ENDPOINT_URL  = env("AWS_S3_ENDPOINT_URL",  default="")
AWS_S3_CUSTOM_DOMAIN = env("AWS_S3_CUSTOM_DOMAIN", default="")

# Media to S3 when a bucket is configured (MinIO in dev, real S3 in prod);
# fall back to local FileSystemStorage when AWS_STORAGE_BUCKET_NAME is empty
# so a fresh `runserver` boots before the operator wires up MinIO. Static
# stays on Django's local backend in base — collectstatic + admin CSS work
# in `runserver` without bucket creds. production.py flips static to S3.
if AWS_STORAGE_BUCKET_NAME:
    _default_storage = {
        "BACKEND": "storages.backends.s3boto3.S3Boto3Storage",
        "OPTIONS": {"location": "media"},
    }
else:
    _default_storage = {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    }

STORAGES = {
    "default": _default_storage,
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
    },
}

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"   # S3StaticStorage ignores it in prod; collectstatic needs it here

# Derive scheme + host for media URLs. AWS_S3_CUSTOM_DOMAIN wins (CloudFront /
# bucket vhost). Otherwise fall back to the endpoint host (MinIO in dev) so
# generated URLs are reachable from the browser — `https://minio:9000/...`
# is fine inside Docker but a host-side dev browser can't resolve it; set
# AWS_S3_CUSTOM_DOMAIN=localhost:9000 + AWS_S3_URL_PROTOCOL=http: for that.
# Browsers re-download every media object on every view without this.
AWS_S3_OBJECT_PARAMETERS = {"CacheControl": "max-age=86400"}

AWS_S3_URL_PROTOCOL = env("AWS_S3_URL_PROTOCOL", default="https:")
if AWS_S3_CUSTOM_DOMAIN:
    MEDIA_URL = f"{AWS_S3_URL_PROTOCOL}//{AWS_S3_CUSTOM_DOMAIN}/media/"
else:
    MEDIA_URL = "/media/"
```

In `config/settings/production.py`, flip static to S3. Always set `STATIC_URL`
in prod — without a fallback, missing `AWS_S3_CUSTOM_DOMAIN` leaves the base
`/static/` value pointing at a path the prod app does not serve, so every
admin asset 404s:

Guard the override with `if AWS_STORAGE_BUCKET_NAME:` so ASGI projects
that load `production.py` in dev (where the bucket env may be empty)
still boot via the `base.py` FileSystemStorage fallback — without the
guard, boto3 raises `ParamValidationError: Invalid bucket name ""` on
every admin asset request.

```python
if AWS_STORAGE_BUCKET_NAME:
    STORAGES = {
        **STORAGES,
        "staticfiles": {
            "BACKEND": "storages.backends.s3boto3.S3StaticStorage",
            "OPTIONS": {"location": "static"},
        },
    }

    if AWS_S3_CUSTOM_DOMAIN:
        STATIC_URL = f"{AWS_S3_URL_PROTOCOL}//{AWS_S3_CUSTOM_DOMAIN}/static/"
    elif AWS_S3_ENDPOINT_URL:
        # Non-AWS provider without a custom domain: serve from the endpoint host.
        STATIC_URL = f"{AWS_S3_ENDPOINT_URL.rstrip('/')}/{AWS_STORAGE_BUCKET_NAME}/static/"
    else:
        # AWS without CloudFront — bucket vhost. us-east-1 omits the region.
        _region = "" if AWS_S3_REGION_NAME == "us-east-1" else f".{AWS_S3_REGION_NAME}"
        STATIC_URL = f"https://{AWS_STORAGE_BUCKET_NAME}.s3{_region}.amazonaws.com/static/"
```

## .env / .env.prod

```sh
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=...
AWS_S3_REGION_NAME=us-east-1
# AWS_S3_ENDPOINT_URL=http://minio:9000      # non-AWS providers
# AWS_S3_CUSTOM_DOMAIN=cdn.example.com       # AWS + CloudFront
# AWS_S3_URL_PROTOCOL=https:                 # override to http: for plain MinIO
```

## Dev — MinIO in docker-compose

Append to the compose file from `references/docker.md`:

```yaml
services:
  minio:
    image: minio/minio:latest
    volumes: ["miniodata:/data"]
    environment:
      MINIO_ROOT_USER: ${AWS_ACCESS_KEY_ID}
      MINIO_ROOT_PASSWORD: ${AWS_SECRET_ACCESS_KEY}
    ports:
      - "127.0.0.1:9000:9000"   # S3 API — loopback only; production uses real S3
      - "127.0.0.1:9001:9001"   # web console
    command: server /data --console-address ":9001"
    healthcheck:
      # `wget` isn't in minio/minio:latest — use curl, which is.
      test: ["CMD", "curl", "-sf", "http://localhost:9000/minio/health/live"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  miniodata:
```

`STORAGES` falls back to FileSystemStorage when the bucket env is empty, so host Django boots whether or not MinIO is up.

## Dockerfile — remove build-time collectstatic

The Dockerfile in `references/docker.md` runs `collectstatic` at build. That works for WhiteNoise (local dir baked in) but **fails for S3** — collectstatic uploads to the bucket and needs real AWS credentials, which must not enter the build context. Delete the line:

```dockerfile
# Delete this RUN — collectstatic moves to deploy.
# RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
#     python manage.py collectstatic --noinput
```

Run `collectstatic` at deploy with real env vars. Patterns below.

## VPS — deploy script

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
# --env-file is required on every compose call — see references/deploy-vps.md
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py collectstatic --noinput
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
```

Enable versioning on the media bucket (provider console or `aws s3api put-bucket-versioning`) — it's the undo button for accidental overwrites and deletes, and the reason `dbbackup`'s `mediabackup` is skipped on this path.

## Managed — fly.toml

```toml
[deploy]
  # `python` not `uv run`: the multi-stage runtime image (python:3.X-slim-trixie)
  # has no uv binary — only the venv at /opt/venv with /opt/venv/bin on PATH.
  # `sh -c` because the release machine execs the argv directly: the Dockerfile
  # declares no ENTRYPOINT, so a bare `&&` arrives as a manage.py app label.
  release_command = "sh -c 'python manage.py migrate && python manage.py collectstatic --noinput'"
```

## Managed — Railway / Render

Release command:

```sh
python manage.py migrate && python manage.py collectstatic --noinput
```

AWS env vars go in the platform dashboard.
