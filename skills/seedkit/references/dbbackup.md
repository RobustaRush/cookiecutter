# Database backups

Docs: <https://django-dbbackup.readthedocs.io/>

Production-only. Apply when `deploy = vps` or `deploy = github-ssh` — both deploy to self-managed hosts.

Managed platforms (`deploy-managed.md` — Fly.io, Railway, Render) provide their own snapshot / point-in-time-recovery story; using `django-dbbackup` on top is duplication that fights the platform's native tooling. For VPS deploys, there's nothing built-in — you have to ship a backup story or hope.

We use `django-dbbackup` over a hand-rolled `pg_dump` cron because it gives:

- One management command (`dbbackup`, `mediabackup`, `dbrestore`) usable from the same container shell as everything else.
- Encrypted-at-rest output via `--encrypt` (GPG) when the storage tier isn't trusted.
- The same storage backends as `django-storages` — backups land in S3 / Backblaze B2 / etc. without a second credentials story.

## Install

```sh
uv add django-dbbackup 'django-storages[s3]'
```

`django-storages[s3]` ships the `S3Boto3Storage` backend `DBBACKUP_STORAGE` points at. Skip if `references/storage-s3.md` is already in scope — it adds the same dep.

## `production.py` only

Wrap the **entire** block in `if not DEBUG:` — including `INSTALLED_APPS += [...]`. The Dockerfile build runs `collectstatic` with `DJANGO_DEBUG=True`; if `dbbackup` is in `INSTALLED_APPS` unconditionally, the build evaluates `env("AWS_ACCESS_KEY_ID")` (no default) and crashes with `ImproperlyConfigured`.

```python
if not DEBUG:
    INSTALLED_APPS += ["dbbackup"]

    # S3-compatible target. Reuse the s3 storage credentials from references/storage-s3.md.
    DBBACKUP_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"
    DBBACKUP_STORAGE_OPTIONS = {
        "access_key": env("AWS_ACCESS_KEY_ID"),
        "secret_key": env("AWS_SECRET_ACCESS_KEY"),
        "bucket_name": env("DBBACKUP_BUCKET"),  # SEPARATE bucket from media — different lifecycle policy
        "default_acl": "private",
    }

    DBBACKUP_CLEANUP_KEEP = 14            # daily backups retained
    DBBACKUP_CLEANUP_KEEP_MEDIA = 7
    DBBACKUP_FILENAME_TEMPLATE = "{databasename}-{servername}-{datetime}.{extension}"
```

`.env.example` additions:

```
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
DBBACKUP_BUCKET=
```

Skip the two AWS lines if `references/storage-s3.md` already added them.

## Schedule

A cron line on the VPS host running inside the web container. Cron starts in `/` with a bare environment, and the sixth field must name an existing host user — use the user that owns `/srv/{project_slug}` (`root` on a stock VPS setup, or the deploy user):

```cron
# /etc/cron.d/dbbackup — runs daily at 03:17 UTC
17 3 * * * root cd /srv/{project_slug} && docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml exec -T web python manage.py dbbackup --clean >> /var/log/dbbackup.log 2>&1
27 3 * * * root cd /srv/{project_slug} && docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml exec -T web python manage.py mediabackup --clean >> /var/log/dbbackup.log 2>&1
```

Drop the `mediabackup` line when media already lives on S3 (`references/storage-s3.md`) — copying one bucket into another duplicates provider-side durability; enable bucket versioning on the media bucket instead.

After the first scheduled run, check `/var/log/dbbackup.log` and `manage.py listbackups` — a broken cron line fails silently otherwise.

`--clean` honours `DBBACKUP_CLEANUP_KEEP*`. Don't rely on bucket lifecycle alone — the dbbackup-side cleanup keeps the *latest N*, while bucket lifecycle keeps *anything younger than X*. Different guarantees.

If the project uses `tasks-celery.md` Beat, you can move the schedule there instead — but cron on the host is simpler and survives a worker outage.

## Restore

```sh
cd /srv/{project_slug}
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml exec -T web python manage.py dbrestore --database=default
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml exec -T web python manage.py mediarestore
```

`dbrestore` is destructive — it drops and recreates the target database. Confirm the target before running on a non-staging host.

## Encryption

If the bucket isn't trusted (cross-region replication into a third-party account, etc.):

```python
DBBACKUP_GPG_RECIPIENT = env('DBBACKUP_GPG_RECIPIENT')
```

And run `dbbackup --encrypt`. Document key rotation in `README.md` — losing the key means losing every encrypted backup taken since.

## Pitfalls

- Postgres dumps require `pg_dump` in the container `PATH`. The production Dockerfiles in `references/docker.md` already install `postgresql-client` — don't drop that line. The client major must be ≥ the `postgres:` image major or `pg_dump` aborts with "server version mismatch"; Debian trixie ships client 17, matching `postgres:17`.
- Don't share the media bucket with the backup bucket. One is hot-served, the other is cold and private; mixing them complicates ACLs and lifecycle.
- Run a *real* restore drill at least once before declaring backups working. Untested backups are not backups.
