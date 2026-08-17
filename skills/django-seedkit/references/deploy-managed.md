# Deploy — Managed (Fly.io / Railway / Render)

Docs: <https://fly.io/docs/django/> · <https://docs.railway.com/> · <https://render.com/docs>

## Fly.io

### fly.toml

```toml
app = "{project_slug}"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[env]
  PORT = "8000"
  DJANGO_BEHIND_PROXY = "True"        # Fly's edge terminates TLS

# Required prod settings come from `fly secrets set` (below) — do NOT
# hardcode here:
#   DJANGO_SECRET_KEY        — generate with secrets.token_urlsafe
#   DJANGO_ALLOWED_HOSTS     — your fly.dev hostname + custom domain.
#                              Without it ALLOWED_HOSTS=[] and DEBUG=False
#                              return 400 for every request.
#   DJANGO_CSRF_TRUSTED_ORIGINS — https://<host> for each allowed host
#   DATABASE_URL             — auto-set by `fly postgres attach`
#   DJANGO_MAIL_HOST          — see references/email.md
#   SENTRY_DSN               — if error-reporting wired

[deploy]
  # `python` not `uv run`: the multi-stage Dockerfile's runtime stage
  # (python:3.X-slim-trixie) has no uv binary — only the venv at /opt/venv
  # with /opt/venv/bin on PATH per the Dockerfile, so `python` resolves there.
  release_command = "python manage.py migrate"

[[services]]
  internal_port = 8000
  protocol = "tcp"
  # With [processes] below, bind this service to the web process:
  #   processes = ["web"]

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  # Gate rollouts on readiness when health endpoints exist (references/healthcheck.md):
  [[services.http_checks]]
    interval = "15s"
    timeout  = "2s"
    path     = "/readyz"
```

### Per-process env (multi-process apps)

`[env]` applies to every process in `[processes]`. To set a different `DJANGO_SETTINGS_MODULE` (or any other var) for one process — e.g. when `references/rest-bolt.md` is in scope and the `bolt` process needs `config.settings.bolt` — inline the var on the command line; Fly's command runner is a plain shell:

```toml
[processes]
  web    = "gunicorn config.wsgi --bind 0.0.0.0:8000"
  worker = "celery -A config worker -l info"
  bolt   = "env DJANGO_SETTINGS_MODULE=config.settings.bolt python manage.py runbolt --port 8002"
```

### Commands

```sh
fly launch --no-deploy
fly postgres create
fly postgres attach <db-name>
fly secrets set \
    DJANGO_SECRET_KEY=$(python -c 'import secrets; print(secrets.token_urlsafe(50))') \
    DJANGO_ALLOWED_HOSTS=$(fly status -j | jq -r '.Hostname'),example.com \
    DJANGO_CSRF_TRUSTED_ORIGINS=https://example.com \
    DJANGO_MAIL_HOST=smtp.example.com \
    DJANGO_MAIL_USERNAME=<username> \
    DJANGO_MAIL_PASSWORD=<password>
fly deploy
```

## Railway / Render

Same pattern: point at `Dockerfile`, set env vars in dashboard, configure release command to `python manage.py migrate` (not `uv run` — the multi-stage runtime image only ships the venv).
