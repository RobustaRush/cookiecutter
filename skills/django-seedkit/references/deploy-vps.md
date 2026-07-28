# Deploy — VPS with Docker + Caddy

Docs: <https://caddyserver.com/docs/> · <https://docs.docker.com/compose/>

## deploy/docker-compose.prod.yml

```yaml
# The default json-file log driver grows without bound — cap it once here
# and attach to every service, or the VPS disk fills in a few months.
x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  web:
    image: ghcr.io/{owner}/{project_slug}:latest
    restart: unless-stopped
    env_file: .env.prod
    logging: *logging
    healthcheck:
      # python+urllib instead of curl — the prod image only installs
      # postgresql-client and slim has no curl. DJANGO_ALLOWED_HOSTS must
      # include localhost (see deploy/.env.prod.example) or this probe 400s.
      test: ["CMD-SHELL", "python -c 'import urllib.request,sys; sys.exit(0 if urllib.request.urlopen(\"http://localhost:8000/healthz\",timeout=2).status==200 else 1)'"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    logging: *logging
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    logging: *logging
    depends_on:
      - web

volumes:
  pgdata:
  caddy_data:
  caddy_config:
```

Every service added later (`redis`, `celery`, `celery-beat`, `ws`) gets the same `logging: *logging` line.

On SQLite + Litestream (`references/database.md`): drop the `db` service, its `pgdata` volume and `web`'s `depends_on`; declare a `data:` volume and mount it at `/data` in `web` and in every worker service; drop the `migrate` line from `## Deploy` below — `entrypoint.sh` runs it on each container boot.

Stock `postgres` ships `shared_buffers=128MB` — laptop sizing. On a dedicated box, add `command: postgres -c shared_buffers=<25% of RAM> -c effective_cache_size=<75% of RAM>` to the `db` service (<https://pgtune.leopard.in.ua/> generates the full set).

## deploy/.env.prod.example — ship this in the repo

Lives next to `deploy/docker-compose.prod.yml`. The compose file references many
vars; without a checked-in template the first deploy fails with cryptic compose
errors. Provide every var:

```sh
# Django
DJANGO_SETTINGS_MODULE=config.settings.production   # the rqworker / db_worker
                                                    # commands inherit this.
                                                    # manage.py defaults to
                                                    # config.settings.local —
                                                    # without this, prod runs
                                                    # with NO security hardening.
DJANGO_SECRET_KEY=
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=example.com,localhost,127.0.0.1,web   # localhost/127.0.0.1 for the
                                                    # in-container healthcheck; `web` for Caddy's
                                                    # active probe, which dials the upstream and
                                                    # sends `Host: web:8000`. Drop it and Django
                                                    # answers 400, Caddy flags the only upstream
                                                    # down, and every request gets 502.
DJANGO_CSRF_TRUSTED_ORIGINS=https://example.com
DJANGO_BEHIND_PROXY=True            # Caddy terminates TLS; required for
                                    # SECURE_SSL_REDIRECT to work right.
DATABASE_URL=postgres://postgres:CHANGE_ME@db:5432/postgres
REDIS_URL=redis://redis:6379
WEB_CONCURRENCY=4                   # gunicorn worker count — 2×cores+1 sync, cores for uvicorn

# Postgres
POSTGRES_PASSWORD=CHANGE_ME
```

Every add-on appends its own vars here — same rule as `.env.example`.

## deploy/Caddyfile

```
example.com {     # replace with the real domain — Caddy fails to issue TLS for example.com
    encode zstd gzip          # Caddy doesn't compress by default; WhiteNoise only covers /static/
    request_body {
        max_size 10MB         # Caddy's default is unlimited — raise per project if uploads need more
    }
    reverse_proxy web:8000 {
        # Probe `/healthz` (process up) — NOT `/readyz` (DB+deps).
        # A transient DB blip on /readyz flips the upstream to "down" and
        # Caddy stops serving 200s; better to let /readyz feed monitoring
        # while the load-balancer probe stays liveness-only.
        health_uri /healthz
        health_interval 10s
        health_timeout 3s
    }
}
```

The Caddyfile only proxies. WhiteNoise inside the `web` container handles `/static/`. Don't add a `handle /static/*` block pointing at a host path — `web` is the only thing that has the collected files (they live inside the image), so a Caddy block would 404.

If the project also serves user-uploaded media via a shared volume (i.e. media on the VPS host, not S3 — see `references/storage-whitenoise.md`), serve it through Caddy:

```
example.com {     # replace with the real domain
    encode zstd gzip
    request_body {
        max_size 10MB
    }
    handle /media/* {
        uri strip_prefix /media   # without this, file_server resolves /srv/media/media/<file>
        root * /srv/media
        file_server
    }
    reverse_proxy web:8000
}
```

Mount the same `media` named volume into the `caddy` service in `docker-compose.prod.yml` (`media:/srv/media:ro`) — the same volume `web` mounts at `/app/media`, so both read the same files.

## Deploy

```sh
ssh user@vps
cd /srv/{project_slug}
git pull
# --env-file is required on every compose call — compose auto-loads only ./.env, not deploy/.env.prod
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
docker image prune -f   # old :latest layers otherwise accumulate until the disk fills
```

`up -d` recreates `web` in place — expect a few seconds of downtime per deploy; this stack trades zero-downtime for one-box simplicity.

Migrations run as a one-shot `docker compose run` *before* `up -d`. Compose's `depends_on: condition: service_healthy` (wired in `references/docker.md`) gates `web` on Postgres being ready — no `entrypoint.sh`, no `pg_isready` loop, no `migrate --noinput` baked into container start. The container's job is `gunicorn`, full stop. (Exception: the SQLite + Litestream pattern in `references/database.md` legitimately uses an entrypoint to restore the DB from S3 before launching gunicorn under `litestream replicate`.)
