# Conventions — the cross-file contract

Shared names and shapes the other references conform to. When two references disagree, this file wins; when adding a snippet, match it.

## Env var names

- Settings core: `DJANGO_DEBUG` / `DJANGO_SECRET_KEY` / `DJANGO_ALLOWED_HOSTS` / `DJANGO_CSRF_TRUSTED_ORIGINS` / `DJANGO_BEHIND_PROXY` / `DJANGO_SETTINGS_MODULE`.
- Infrastructure: `DATABASE_URL`, `REDIS_URL`, `WEB_CONCURRENCY`.
- Every var a reference reads gets a line in `.env.example`.

## Redis database map

`REDIS_URL` is bare — `redis://host:port`, no trailing slash, no `/<db>`. Each consumer appends its own database:

| DB | Consumer |
|----|----------|
| `/0` | cache (`redis.md`) |
| `/1` | Celery broker (`tasks-celery.md`) |
| `/2` | Celery results (`tasks-celery.md`) |
| `/3` | django-tasks-rq (`tasks-django-rq.md`) |
| `/4` | channels layer (`realtime.md`) |
| `/5` | GlitchTip internal (`error-reporting.md`) |

## Production compose service shape

Fragments merge into `deploy/docker-compose.prod.yml` (`deploy-vps.md`), which defines the `x-logging` anchor. Every service follows:

```yaml
  <name>:
    image: ghcr.io/{owner}/{project_slug}:latest   # ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest} when deploy=github-ssh
    restart: unless-stopped
    command: <role command>          # omit for web (image CMD)
    env_file: .env.prod
    logging: *logging
    depends_on:
      db:
        condition: service_healthy   # db and redis both define healthchecks
```

Key order inside a service: `image` → `restart` → `volumes` → `environment` / `env_file` → `ports` → `command` → `logging` → `healthcheck` → `depends_on` (dclint `service-keys-order`).

## Cookies — SameSite

`SESSION_COOKIE_SAMESITE = "Lax"` (`gdpr.md`) is the default posture. `cors.md` switches it to `"None"` only when a frontend on another origin authenticates with session cookies; that condition wins when both references are applied.

## Version pins

Pinned artifacts in references age between skill releases: GitHub Actions tags, `.pre-commit-config.yaml` revs, base-image tags, downloaded binaries (Litestream, Tailwind CLI, DaisyUI). Before writing one into the project, resolve the current release — `uv run pre-commit autoupdate` after writing the pre-commit config; `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name` (or the releases page) for actions and binaries. Keep the major version the reference states unless it no longer exists.

## Python version

`requires-python = ">=3.12"` is the floor. Every concrete pin — Docker base image, devcontainer, mise `[tools]`, pyright `pythonVersion` — is 3.13. Bump them together.

## Test settings module

`config.settings.test` (defined in `new-project.md`, wired by `pytest.md`). CI and deploy references describe that module, not `local`.
