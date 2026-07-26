# robots.txt

Trivial endpoint — no package needed.

Put the view in `config/views.py`. If a suitable app already exists (a `core` app, a landing-page app), put it there instead — don't add a new app just for this view.

## Settings

In `config/settings.py` (or `config/settings/base.py`):

```python
ROBOTS_DISALLOW_ALL = env.bool("ROBOTS_DISALLOW_ALL", default=False)
```

Without this line the `.env` toggle below is silently ignored — `settings` never reads the env var.

## `config/views.py`

```python
from django.conf import settings
from django.http import HttpResponse
from django.views.decorators.http import require_GET


@require_GET
def robots_txt(_request):
    if settings.DEBUG or settings.ROBOTS_DISALLOW_ALL:
        body = 'User-agent: *\nDisallow: /\n'
    else:
        body = (
            'User-agent: *\n'
            'Disallow: /admin/\n'
            'Disallow: /accounts/\n'
            'Allow: /\n'
        )
        sitemap = getattr(settings, 'SITEMAP_URL', None)
        if sitemap:
            body += f'\nSitemap: {sitemap}\n'
    return HttpResponse(body, content_type='text/plain')
```

## `config/urls.py`

```python
from django.urls import path
from config.views import robots_txt

urlpatterns = [
    # ...
    path('robots.txt', robots_txt, name='robots'),
]
```

## When to disallow everything

Staging deploys, preview environments, internal tools — set `ROBOTS_DISALLOW_ALL=True` in `.env` for those, leave it unset in production. Don't rely on `DEBUG` alone — staging and preview boxes run with `DEBUG=False`, so only the explicit toggle keeps them out of the index.

## What this is NOT

Not a sitemap (`references/seo.md` wires `django.contrib.sitemaps` and `SITEMAP_URL`) and not a security control — `/admin/` is gated by Django's auth.
