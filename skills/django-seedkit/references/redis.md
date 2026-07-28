# Redis

Docs: <https://github.com/jazzband/django-redis>

`django-redis` plugs Redis into Django's cache framework. Stock Django's local-memory / DB cache backends don't survive a restart and don't scale past one worker. Redis adds a shared, durable cache plus the broker Celery and django-tasks-rq need.

## Install

```sh
uv add django-redis
```

## Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
# Bare scheme://host:port form — no trailing slash, no /<db>. Per-purpose
# DBs are appended below. .rstrip("/") is a defensive guard so a stray
# trailing slash from a managed platform doesn't produce redis://host//0.
REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379").rstrip("/")

# Consumers append /<db> — full map in references/conventions.md.
# `cache.clear()` only touches /0 — brokers / queues stay intact.
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": f"{REDIS_URL}/0",
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}
```

## Local — docker-compose.yml

Add to the same compose file as the `db` service (`references/docker.md`):

```yaml
services:
  redis:
    image: redis:8-alpine
    ports:
      - "127.0.0.1:6379:6379"   # host Django / workers reach it via localhost
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
```

`.env`:

```sh
REDIS_URL=redis://localhost:6379   # bare — consumers append /<db>, map in references/conventions.md
```

## VPS — docker-compose.prod.yml

```yaml
services:
  web:
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  redis:
    image: redis:8-alpine
    restart: unless-stopped
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy volatile-lru
    logging: *logging
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  redis_data:
```

AOF + the volume keep queued Celery / RQ jobs across container restarts. `volatile-lru` evicts only keys with a TTL when `maxmemory` is hit — cache entries have one, broker / queue keys don't. Size `--maxmemory` to the box.

`.env.prod`:

```sh
REDIS_URL=redis://redis:6379
```

## Managed platforms

- **Fly.io** — managed Redis via Upstash:
  ```sh
  fly redis create
  fly redis attach <redis-name>
  ```
  `REDIS_URL` is set automatically.
- **Railway** — add Redis from the dashboard; `REDIS_URL` injects as a shared variable.
- **Render** — external [Upstash Redis](https://upstash.com/); paste the URL as `REDIS_URL`.
