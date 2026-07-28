# Docker

Docs: <https://docs.astral.sh/uv/guides/integration/docker/> · <https://docs.docker.com/compose/>

Two artefacts:

- **Production `Dockerfile`** — multi-stage. uv builds the venv in a builder stage; the runtime stage copies the venv into a slim Python image with no uv binary. Smaller image, faster cold start, no build toolchain at runtime.
- **`docker-compose.yml`** — local services only (Postgres, Redis, Mailpit when wired). Django runs on the host via `uv run manage.py runserver`; the compose file never includes a `web` service.

## Image choice

| Tier | Image | Use it for |
|---|---|---|
| **Slim uv builder** *(default)* | `ghcr.io/astral-sh/uv:python3.13-trixie-slim` | Builder stage. Handles every wheels-based Django dep (`psycopg[binary]`, `pillow`, `cffi`). |
| **Slim runtime** | `python:3.13-slim-trixie` | Final stage. No uv, no build tools — just the copied venv and the app. |
| **Full uv (escape hatch)** | `ghcr.io/astral-sh/uv:python3.13-trixie` + `apt-get install -y --no-install-recommends build-essential libpq-dev` | Use as the builder when a dep has no manylinux wheel (`mysqlclient`, source-built `lxml`, hand-rolled `cffi`). For `django-bolt` pin the build to `linux/amd64` instead — see `references/rest-bolt.md`. |

Skip Alpine (musl breaks manylinux wheels), distroless (no shell blocks debug), and full Debian (slim covers every wheels-based project).

Match the `python3.X` tag to `requires-python` in `pyproject.toml`. `uv sync --frozen` refuses to install on a mismatch.

## .dockerignore

```
.venv/
.git/
__pycache__/
*.pyc
*.sqlite3
.env
.ruff_cache/
.pytest_cache/
.mypy_cache/
staticfiles/
node_modules/
.django_tailwind_cli/
```

`.venv/` is load-bearing — without it, `COPY . .` drags the host venv into the build context and bloats the image.

---

## Local services — docker-compose.yml

Only the services Django talks to over the network. The web process runs on the host via `uv run manage.py runserver`, so the compose file has no `web` service and nothing to bind-mount source into.

```yaml
name: <project-slug>   # matches pyproject.toml [project].name; isolates volumes/networks per project

services:
  db:
    image: postgres:17
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "127.0.0.1:5432:5432"   # host Django reaches it via localhost
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

Key order inside each service follows dclint's expected sequence: `image` → `volumes` → `environment` → `ports` → `command` → `healthcheck` (full list in the dclint `service-keys-order` rule). Apply the same order in every service added to this file.

`.env`: `DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres`.

Add `redis` from `references/redis.md` and `mailpit` from `references/email.md` to the same file when those add-ons land.

For SQLite, skip the compose file entirely — Django writes to `db.sqlite3` next to `manage.py`.

### Boot check

```sh
docker compose up -d --wait
uv run manage.py migrate
uv run manage.py runserver
```

`--wait` blocks on the compose-side healthchecks and exits non-zero if a service
never becomes healthy. Without it, `up -d` returns as soon as containers are
*running* and the next command races the service's listener. Give every service
a `healthcheck:` block so `--wait` has something to wait on — that is the whole
mechanism, so a service without one is waited on only for `running`.

Don't poll `docker compose ps --format json` to hand-roll a readiness loop.
Compose v2.6+ emits newline-delimited JSON, not an array, so `json.load` reads
the whole stream and raises — the loop then never exits successfully.

---

## Production Dockerfile

Multi-stage by default. Builder stage installs deps with uv; runtime stage copies the venv into `python:3.13-slim-trixie`. The runtime image has no `uv` binary — `/opt/venv/bin` is on `PATH` so `python manage.py …` and `gunicorn` run directly.

**Add the production server before building:**

```sh
uv add gunicorn
```

The Dockerfile's `CMD` calls `gunicorn` directly. Without it the image build skips it and the container exits with `gunicorn: not found`.

```dockerfile
# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# DELETE this RUN if storage is S3 (collectstatic needs bucket creds at
# deploy time, not build). See references/storage-s3.md.
# DJANGO_DEBUG=True unlocks dev defaults so collectstatic boots without
# real SECRET_KEY / DATABASE_URL. SETTINGS_MODULE → production so STORAGES
# (manifest static storage) applies; otherwise manage.py uses local.py.
# Split layout: `config.settings.production`; single-file: `config.settings`.
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True \
    /opt/venv/bin/python manage.py collectstatic --noinput


FROM python:3.13-slim-trixie AS prod
ENV PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*
# postgresql-client ships pg_dump / pg_isready for django-dbbackup and
# ad-hoc shell debugging. Trixie's client is major 17 — keep it ≥ the
# `postgres:` image major or pg_dump aborts on "server version mismatch".
# Drop the line when DB=SQLite — Postgres tools add ~25 MB for nothing.

RUN groupadd --system django && useradd --system --gid django django

WORKDIR /app
COPY --from=builder --chown=django:django /opt/venv /opt/venv
COPY --from=builder --chown=django:django /app /app

USER django

CMD ["gunicorn", "config.wsgi", "--bind", "0.0.0.0:8000", "--max-requests", "1000", "--max-requests-jitter", "100", "--access-logfile", "-"]
```

Worker count comes from `WEB_CONCURRENCY` — gunicorn reads it natively and defaults to **1 worker** without it. Set it in `.env.prod`: `2×cores+1` for sync (WSGI) workers, cores for uvicorn workers (`references/async.md`). `--max-requests` + jitter recycle workers periodically so slow memory leaks don't accumulate on a long-lived box.

Common settings — `UV_COMPILE_BYTECODE=1` (pre-compile `.pyc`), `UV_LINK_MODE=copy` (silence hardlink errors), two-step `uv sync` (deps first, project after), `UV_PROJECT_ENVIRONMENT=/opt/venv`. The cache-mount on `/root/.cache/uv` persists uv's wheel cache across builds — Rust-backed deps without a manylinux/aarch64 wheel compile once and the wheel is reused.

### Waiting for Postgres

No `entrypoint.sh`, no `pg_isready` loop. Compose's `depends_on: condition: service_healthy` (wired on the `db` service in `references/deploy-vps.md`) gates `web` startup until Postgres reports healthy. Migrations run as an explicit one-shot — see `references/deploy-vps.md` and `references/deploy-github-ssh.md`:

```sh
docker compose -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate
```

`python` not `uv run` — the runtime image has no uv binary, only `/opt/venv/bin/python` on `PATH`. Keeping the container's job to "run gunicorn" makes restarts cheap and avoids re-running migrations on every replica boot.

### Pitfalls

- **Image tag mismatch.** Builder and runtime must share the same `python3.X` tag **and the same Debian suite** (both `trixie`, or both `bookworm`). The Python tag must match `requires-python` — `uv sync --frozen` refuses to install otherwise. A newer-suite builder with an older-suite runtime fails later, at import time, with `GLIBC_x.xx not found` on any compiled wheel.
- **Bookworm runtime against `postgres:17`.** Bookworm's apt only carries the major-15 client, so `pg_dump` aborts on "server version mismatch". Add the PGDG repo in the runtime stage instead of the plain `postgresql-client` line:
  ```dockerfile
  RUN apt-get update && apt-get install -y --no-install-recommends \
      wget gnupg ca-certificates \
      && install -d /usr/share/postgresql-common/pgdg \
      && wget --quiet -O /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
      && apt-get update && apt-get install -y --no-install-recommends postgresql-client-17 \
      && apt-get purge -y --auto-remove wget gnupg \
      && rm -rf /var/lib/apt/lists/*
  ```
- **`uv sync` hardlink warnings.** `UV_LINK_MODE=copy` (set in the Dockerfile) silences them.
- **`Ignoring existing virtual environment linked to non-existent Python interpreter`.** A host `.venv` slipped into the image build (missing `.dockerignore` entry). Add `.venv` to `.dockerignore` and `docker build --no-cache`.
