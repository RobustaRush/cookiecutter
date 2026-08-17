# Error reporting

Docs: <https://docs.sentry.io/platforms/python/integrations/django/> · <https://www.bugsink.com/docs/> · <https://glitchtip.com/documentation>

Sentry-protocol error tracker. Three backends share one SDK setup — only `SENTRY_DSN` differs.

## Install

```sh
uv add sentry-sdk
```

## Settings

Wire in `config/settings/production.py` (or single-file: gate on `not DEBUG`). Not `base.py` — a local/test run with `SENTRY_DSN` set would otherwise ship telemetry.

```python
SENTRY_DSN = env("SENTRY_DSN", default="")
if SENTRY_DSN:
    import sentry_sdk
    from sentry_sdk.integrations.django import DjangoIntegration

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[DjangoIntegration()],
        release=env("SENTRY_RELEASE", default=None),
        # traces_sample_rate=0.1,  # tracing — Sentry SaaS / GlitchTip only
    )
```

PII / scrubbing — see `references/gdpr.md`.

## Background workers

The same `sentry_sdk.init` covers Celery worker processes because they load the same settings module. After deploy, run a task that raises and confirm it appears in the tracker.

## .env

```sh
SENTRY_DSN=
```

## .env.prod

```sh
SENTRY_DSN=<dsn>
```

`SENTRY_RELEASE` comes from the image, not `.env.prod` — the commit is known at
build time, not at run time. In the production Dockerfile's `prod` stage:

```dockerfile
ARG GIT_SHA=unknown
ENV SENTRY_RELEASE=${GIT_SHA}
```

and pass it from CI — in `references/deploy-github-ssh.md`, add to the
`docker/build-push-action` step:

```yaml
          build-args: |
            GIT_SHA=${{ github.sha }}
```

---

## Backend A: Bugsink (self-hosted, recommended)

### docker-compose.prod.yml

```yaml
services:
  bugsink:
    image: bugsink/bugsink:latest
    restart: unless-stopped
    environment:
      SECRET_KEY: ${BUGSINK_SECRET_KEY}
      CREATE_SUPERUSER: "admin:${BUGSINK_ADMIN_PASSWORD}"
      BEHIND_HTTPS_PROXY: "true"
      BASE_URL: https://bugsink.example.com
    volumes:
      - bugsink_data:/data

volumes:
  bugsink_data:
```

Reverse-proxy `bugsink.example.com` → `bugsink:8000` in the Caddyfile. Open the UI, create a project, copy the DSN into `SENTRY_DSN`.

## Backend B: Sentry SaaS

Create a Django project at sentry.io (EU region available at signup), copy the DSN.

## Backend C: GlitchTip (self-hosted)

```yaml
services:
  glitchtip-web:
    image: glitchtip/glitchtip:latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://glitchtip:${GLITCHTIP_DB_PASSWORD}@glitchtip-db:5432/glitchtip
      SECRET_KEY: ${GLITCHTIP_SECRET_KEY}
      REDIS_URL: redis://glitchtip-redis:6379/0
    depends_on: [glitchtip-db, glitchtip-redis]

  glitchtip-worker:
    image: glitchtip/glitchtip:latest
    command: ./bin/run-celery-with-beat.sh
    restart: unless-stopped
    environment:                            # GlitchTip's own config, not the app's
      DATABASE_URL: postgres://glitchtip:${GLITCHTIP_DB_PASSWORD}@glitchtip-db:5432/glitchtip
      SECRET_KEY: ${GLITCHTIP_SECRET_KEY}
      REDIS_URL: redis://glitchtip-redis:6379/0
    depends_on: [glitchtip-db, glitchtip-redis]

  glitchtip-redis:
    image: redis:8-alpine
    restart: unless-stopped
    # GlitchTip's Celery keys carry no TTL, so on the app's redis the
    # `volatile-lru` maxmemory policy evicts the app's cache to hold them.

  glitchtip-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: glitchtip
      POSTGRES_USER: glitchtip
      POSTGRES_PASSWORD: ${GLITCHTIP_DB_PASSWORD}
    volumes:
      - glitchtip_pgdata:/var/lib/postgresql/data

volumes:
  glitchtip_pgdata:
```

Reverse-proxy → `glitchtip-web:8000`.

---

## Release tracking

```dockerfile
ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
```

```sh
docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t app .
```
