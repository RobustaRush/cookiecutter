# Database

Docs: <https://django-environ.readthedocs.io/en/latest/types.html#environ-env-db-url> · <https://docs.djangoproject.com/en/stable/ref/databases/> · <https://litestream.io/>

`django-environ` parses `DATABASE_URL`. No extra config beyond `DATABASES = {"default": env.db("DATABASE_URL")}`.

## SQLite

The in-code default in `base.py` already anchors the file to `BASE_DIR` (4-slash absolute URL), so dev works without setting `DATABASE_URL`. Only set it when you want a path outside the project:

```sh
DATABASE_URL=sqlite:////absolute/path/to/db.sqlite3
```

Three-slash URLs (`sqlite:///db.sqlite3`) are CWD-relative — running `manage.py` from a sub-dir creates a second DB file. Always use four slashes.

No extra dependency. Add `db.sqlite3` to `.gitignore`.

### SQLite production defaults (applied automatically)

When DB=SQLite, the skill writes these into `production.py` at Foundation §3 without asking — they're settings, not a package choice. The cache and tasks questions later in §5 also default to the SQLite-only path (`cache.sqlite3` + `django-tasks-db`). Trade-off: single host (no horizontal scaling), brief deploy blip without external replication. **Requires Django 5.1+** for the `transaction_mode` and `init_command` `OPTIONS` keys.

`production.py`:

```python
DATABASES["default"]["OPTIONS"] = {
    "transaction_mode": "IMMEDIATE",   # avoid SQLITE_BUSY under concurrent writers
    "timeout": 5,                      # seconds to wait on a locked DB
    "init_command": (
        "PRAGMA journal_mode=WAL;"          # writers don't block readers
        "PRAGMA synchronous=NORMAL;"        # safe with WAL, much faster than FULL
        "PRAGMA mmap_size=134217728;"       # 128 MiB memory-mapped reads
        "PRAGMA journal_size_limit=27103364;"
        "PRAGMA cache_size=2000;"           # pages (~ 8 MiB)
    ),
}
```

Django sets `PRAGMA foreign_keys=ON` for SQLite already.

Place the file on a persistent volume:

```sh
DATABASE_URL=sqlite:////data/site.sqlite3   # four slashes = absolute path
```

#### Cache on a separate SQLite

Applied when §5.3 cache backend = `sqlite` (the default when DB=SQLite). All three blocks go in `base.py` so dev and prod share the cache DB (and dev can run `createcachetable --database cache`); `production.py` only adds the WAL `OPTIONS` to the cache entry.

```python
# base.py
DATABASES["cache"] = {
    "ENGINE": "django.db.backends.sqlite3",
    "NAME": env("CACHE_DB_PATH", default=BASE_DIR / "cache.sqlite3"),
}

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "cache_table",
    },
}

DATABASE_ROUTERS = ["config.routers.CacheRouter"]
```

```python
# production.py — reuse the default's WAL pragmas for the cache DB too
DATABASES["cache"]["OPTIONS"] = DATABASES["default"]["OPTIONS"]
```

Set `CACHE_DB_PATH=/data/cache.sqlite3` in the prod `.env` so the cache file lives on the persistent volume.

`config/routers.py`:

```python
class CacheRouter:
    """Route django.core.cache reads/writes/migrations to the `cache` database."""
    label = "django_cache"

    def db_for_read(self, model, **hints):
        return "cache" if model._meta.app_label == self.label else None

    def db_for_write(self, model, **hints):
        return "cache" if model._meta.app_label == self.label else None

    def allow_migrate(self, db, app_label, **hints):
        if app_label == self.label:
            return db == "cache"
        return None
```

Once during deploy:

```sh
uv run manage.py createcachetable --database cache
```

#### Background tasks on SQLite

`django-tasks-db` (`references/tasks-django.md` Backend A) runs against the default DB, no broker needed. Other no-broker options: `django-q2`, `huey` (DB consumer mode).

#### Backup — Litestream

[Litestream](https://litestream.io) streams every WAL frame to S3-compatible storage (R2, B2, Hetzner Object Storage, AWS S3). The container restores from the bucket on boot, then `litestream replicate` wraps `gunicorn`.

Production `Dockerfile`:

```dockerfile
# v0.5.13 — check the latest tag on github.com/benbjohnson/litestream/releases.
RUN apt-get update && apt-get install -y --no-install-recommends wget \
 && ARCH=$(dpkg --print-architecture | sed 's/amd64/x86_64/') \
 && wget -q "https://github.com/benbjohnson/litestream/releases/download/v0.5.13/litestream-0.5.13-linux-${ARCH}.deb" \
 && dpkg -i "litestream-0.5.13-linux-${ARCH}.deb" \
 && rm "litestream-0.5.13-linux-${ARCH}.deb" \
 && rm -rf /var/lib/apt/lists/*
# Release assets name amd64 as x86_64 while arm64 keeps dpkg's name — the sed
# keeps the image building on M-series Macs too.

# Pre-create /data before `USER django` — the named volume mounts as root:root,
# so the django user can't write site.sqlite3 / cache.sqlite3 / WAL files otherwise.
RUN mkdir -p /data && chown django:django /data

# Bake the litestream config and entrypoint into the image at fixed paths.
# Bind-mounting `./litestream.yml` from `deploy/docker-compose.prod.yml` resolves
# against the compose-file directory and silently fails when the file lives at
# the project root.
COPY litestream.yml /etc/litestream.yml
COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD []
```

`litestream.yml`:

```yaml
dbs:
  - path: /data/site.sqlite3
    replica:
      type: s3
      endpoint: ${S3_ENDPOINT}
      bucket: ${S3_BUCKET}
      path: site/site.sqlite3
      access-key-id: ${S3_ACCESS_KEY_ID}
      secret-access-key: ${S3_SECRET_ACCESS_KEY}
```

`entrypoint.sh`:

```sh
#!/bin/sh
set -eu
# Pass-through for ad-hoc commands (`docker run img which gunicorn`, `id -un`).
# Without this, the entrypoint hijacks every invocation and the smoke checks fail.
if [ "$#" -gt 0 ]; then exec "$@"; fi
mkdir -p /data
litestream restore -config /etc/litestream.yml -if-db-not-exists -if-replica-exists /data/site.sqlite3
python manage.py migrate --noinput
python manage.py createcachetable --database cache   # only when cache backend = sqlite; delete this line otherwise — `--database` validates against configured aliases and exits 2
exec litestream replicate -config /etc/litestream.yml -exec "gunicorn config.wsgi --bind 0.0.0.0:8000 --max-requests 1000 --max-requests-jitter 100 --access-logfile -"
```

Trade-offs:

- **Gain**: no managed-DB cost, no network hop, simpler infra.
- **Watch**: single host (scale CPU/workers, not containers); deploys briefly stop writes during container swap.
- **Don't** pick this when you need horizontal write scaling, multi-region replicas, or strict zero-downtime — go PostgreSQL.

## PostgreSQL

```sh
uv add 'psycopg[binary]'
```

### Persistent connections

`env.db()` returns `CONN_MAX_AGE=0` by default — every request opens a new
Postgres connection. Behind gunicorn this wastes one TCP handshake per
request. Configure keep-alive via URL query parameters; django-environ
lifts `conn_max_age`, `conn_health_checks`, `atomic_requests`, and
`autocommit` to the top of the parsed dict where Django expects them:

```sh
# .env / .env.prod
DATABASE_URL=postgres://user:pass@host:5432/dbname?conn_max_age=60&conn_health_checks=True
```

```python
DATABASES = {"default": env.db("DATABASE_URL", default=...)}
```

Safe to keep on the URL even when SQLite is the dev fallback —
`conn_health_checks` is a no-op there.

### Variant A — Postgres on host

```sh
createdb {project_slug}
```

`.env`:

```sh
DATABASE_URL=postgres://{user}:{password}@localhost:5432/{project_slug}
```

### Variant B — Postgres in Docker

Run the `db` service from `references/docker.md`:

```sh
docker compose up -d db
```

`.env` (host Django connects to the published port):

```sh
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
```
