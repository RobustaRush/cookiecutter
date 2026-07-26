# Health check endpoint

Reverse proxies, container platforms, and uptime monitors expect `/healthz` (or similar) to return 200 cheaply. Stock Django doesn't ship one — every prod-ready deploy needs to expose this themselves.

We don't pull in `django-health-check`. Two trivial views beat a dependency that adds 8 backends and a settings block.

Put the views in `config/views.py`. If a suitable app already exists (a `core` app, an existing landing-page app), put them there instead — don't add a new app just for these views.

## `config/views.py`

```python
from django.db import connection
from django.db.utils import OperationalError
from django.http import HttpResponse


def liveness(_request):
    """Process is alive. No external checks — must never block."""
    return HttpResponse('ok', content_type='text/plain')


def readiness(_request):
    """Process can serve traffic — DB reachable."""
    try:
        with connection.cursor() as cur:
            cur.execute('SELECT 1')
    except OperationalError:
        return HttpResponse('db down', status=503, content_type='text/plain')
    return HttpResponse('ready', content_type='text/plain')
```

## `config/urls.py`

```python
from django.urls import path
from config.views import liveness, readiness

urlpatterns = [
    # ...
    path('healthz', liveness, name='healthz'),
    path('readyz', readiness, name='readyz'),
]
```

No trailing slash — kubelets / Caddy / Fly probes call exactly `/healthz`.

## Deploy wiring

- **Caddy / nginx** (`references/deploy-vps.md`): `health_uri /healthz` block on the upstream.
- **Fly.io** (`references/deploy-managed.md`): a `[[services.http_checks]]` block in `fly.toml` with `path = "/readyz"`.
- **GitHub Actions deploy** (`references/deploy-github-ssh.md`): post-deploy curl `/readyz` before declaring success.

If any deploy reference is applied, **also** add the matching probe wiring there. Don't leave the endpoint dangling.

## Allowed hosts gotcha

Probes hit the container by IP, not hostname. Either:

- Add the platform's probe IP / `*` to `ALLOWED_HOSTS` (Fly does this automatically; check before adding).
- Or run probes against the public hostname (slower path, more failure modes).

Don't strip the `Host`-header check globally to make probes work. Scope the bypass to the probe view if needed.
