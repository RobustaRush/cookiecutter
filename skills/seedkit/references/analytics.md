# Analytics

Docs: <https://www.goatcounter.com/help/start> · <https://umami.is/docs> · <https://shynet.r1ke.io/> · <https://developers.google.com/analytics/devguides/collection/ga4>

Privacy-respecting site analytics. Pick one backend at setup time — only that snippet ships in templates. Empty `ANALYTICS_ID` disables tracking (e.g. in dev).

| Backend | Hosting | Cookies | Consent banner |
|---|---|---|---|
| GoatCounter (recommended) | self-host or SaaS | no | no |
| Umami | self-host or SaaS | no | no |
| Shynet | self-host | no | no |
| Google Analytics 4 | SaaS (US) | yes | **yes (EU)** |

GDPR / consent specifics — `references/gdpr.md`.

## Django wiring (shared)

Apply once for any chosen backend, then drop in the matching backend snippet below.

### .env

```sh
ANALYTICS_ID=
ANALYTICS_HOST=     # only for self-hosted GoatCounter / Umami / Shynet
```

### Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
ANALYTICS_ID   = env("ANALYTICS_ID", default="")
ANALYTICS_HOST = env("ANALYTICS_HOST", default="")   # omit for GA4
```

### Context processor

`config/context_processors.py`:

```python
from django.conf import settings

def analytics(request):
    return {
        "ANALYTICS_ID":   settings.ANALYTICS_ID,
        "ANALYTICS_HOST": settings.ANALYTICS_HOST,
        "DEBUG":          settings.DEBUG,
    }
```

Register in `TEMPLATES[0]["OPTIONS"]["context_processors"]`:

```python
"config.context_processors.analytics",
```

### Template

`templates/_analytics.html` wraps the chosen backend's snippet. The `not DEBUG` gate keeps beacons out of dev. Uppercase `DEBUG` comes from the custom processor above — not Django's built-in `django.template.context_processors.debug`, which only exposes a lowercase `debug` when the request IP is in `INTERNAL_IPS`.

```django
{% if ANALYTICS_ID and not DEBUG %}
  {# GA4 only needs ANALYTICS_ID; self-hosted backends also gate on ANALYTICS_HOST: #}
  {# {% if ANALYTICS_ID and ANALYTICS_HOST and not DEBUG %} #}
  {# backend snippet — see below #}
{% endif %}
```

In `templates/base.html`, before `</body>`:

```django
{% include "_analytics.html" %}
```

If no frontend reference created `templates/base.html` (e.g. `frontend: none`), ship a minimal one so the include resolves — without it the analytics snippet is dead:

```django
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>{% block title %}{% endblock %}</title></head>
<body>
  {% block content %}{% endblock %}
  {% include "_analytics.html" %}
</body>
</html>
```

Register `BASE_DIR / "templates"` in `TEMPLATES[0]["DIRS"]`.

## Backends

### GoatCounter

Tiny single Go binary, SQLite, cookieless. Lowest ops cost.

**SaaS:** free at goatcounter.com — `ANALYTICS_HOST=https://<code>.goatcounter.com`, `ANALYTICS_ID=<code>`.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  goatcounter:
    image: arp242/goatcounter:latest
    restart: unless-stopped
    environment:
      GOATCOUNTER_LISTEN: ":8080"
      # Point the DB at the mounted volume explicitly. The image's default
      # path is relative to its workdir, so a volume mounted anywhere else
      # leaves the SQLite file inside the container — gone on recreate.
      GOATCOUNTER_DB: "sqlite+/home/goatcounter/goatcounter-data/goatcounter.sqlite3"
    volumes:
      - goatcounter_data:/home/goatcounter/goatcounter-data

volumes:
  goatcounter_data:
```

Reverse-proxy `stats.example.com` → `goatcounter:8080`.

**Snippet** in `templates/_analytics.html`:

```html
<script data-goatcounter="{{ ANALYTICS_HOST }}/count"
        async src="//gc.zgo.at/count.js"></script>
```

### Umami

Polished UI, cookieless. Node + Postgres.

**SaaS:** umami.is.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://umami:${UMAMI_DB_PASSWORD}@umami-db:5432/umami
      DATABASE_TYPE: postgresql
      APP_SECRET: ${UMAMI_APP_SECRET}
    depends_on: [umami-db]

  umami-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: umami
      POSTGRES_USER: umami
      POSTGRES_PASSWORD: ${UMAMI_DB_PASSWORD}
    volumes:
      - umami_pgdata:/var/lib/postgresql/data

volumes:
  umami_pgdata:
```

Reverse-proxy `stats.example.com` → `umami:3000`. Create a website in the Umami UI to get the website ID.

**Snippet** in `templates/_analytics.html`:

```html
<script defer src="{{ ANALYTICS_HOST }}/script.js"
        data-website-id="{{ ANALYTICS_ID }}"></script>
```

### Shynet

Django + Postgres. Same stack as the project; cookieless via short-lived heartbeats.

**Self-host (docker-compose.prod.yml):**

```yaml
services:
  shynet:
    image: milesmcc/shynet:latest
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://shynet:${SHYNET_DB_PASSWORD}@shynet-db:5432/shynet
      DJANGO_SECRET_KEY: ${SHYNET_SECRET_KEY}
      ALLOWED_HOSTS: stats.example.com
    depends_on: [shynet-db]

  shynet-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: shynet
      POSTGRES_USER: shynet
      POSTGRES_PASSWORD: ${SHYNET_DB_PASSWORD}
    volumes:
      - shynet_pgdata:/var/lib/postgresql/data

volumes:
  shynet_pgdata:
```

Reverse-proxy `stats.example.com` → `shynet:8080`. Create a Service in the Shynet admin; it generates the snippet — paste into `_analytics.html`. The service ID is `ANALYTICS_ID`.

### Google Analytics 4

SaaS, US-hosted. Cookies required. **EU users need a consent banner before loading gtag** — see `references/gdpr.md`.

`ANALYTICS_ID=G-XXXXXXX` from analytics.google.com. `ANALYTICS_HOST` unused.

**Snippet** in `templates/_analytics.html`:

```html
<script async src="https://www.googletagmanager.com/gtag/js?id={{ ANALYTICS_ID }}"></script>
<script nonce="{{ request.csp_nonce }}">
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '{{ ANALYTICS_ID }}');
</script>
```

The `nonce="{{ request.csp_nonce }}"` is required when `references/csp.md` is active — `script-src` has no `'unsafe-inline'`, so the inline init block is blocked without a nonce. The attribute is harmless when CSP is off (browsers ignore unknown nonces).
