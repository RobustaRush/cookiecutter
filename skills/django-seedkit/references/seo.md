# SEO — meta tags + sitemap

Docs: <https://docs.djangoproject.com/en/stable/ref/contrib/sitemaps/> · <https://ogp.me/>

Stock Django pages ship no `<meta name="description">`, no Open Graph tags, and no sitemap. Search results fall back to guessed snippets, and links pasted into chat apps or social feeds show a bare URL instead of a preview card. One template block plus `django.contrib.sitemaps` covers both.

## Meta tags

Add inside the `<head>` of `templates/base.html` (scaffolded in `references/tailwind.md`), after `<title>`:

```django
{% block meta %}
<meta name="description" content="{{ meta_description|default:'<one-line project purpose>' }}">
<link rel="canonical" href="{{ request.scheme }}://{{ request.get_host }}{{ request.path }}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="<project name>">
<meta property="og:title" content="{{ meta_title|default:'<project name>' }}">
<meta property="og:description" content="{{ meta_description|default:'<one-line project purpose>' }}">
<meta property="og:url" content="{{ request.scheme }}://{{ request.get_host }}{{ request.path }}">
<meta name="twitter:card" content="summary">
{% endblock %}
```

Replace `<project name>` / `<one-line project purpose>` at scaffold time with the answers from the Foundation questionnaire. Views pass `meta_title` / `meta_description` in context to customize per page; a page with special needs (an `og:image`, an `article` type) overrides `{% block meta %}` wholesale.

The canonical/`og:url` value is rebuilt from `scheme`/`host`/`path` rather than `request.build_absolute_uri` — the latter includes the query string, and `?page=2` variants would each declare themselves canonical.

## Sitemap

`django.contrib.sitemaps` generates `sitemap.xml` from querysets and named URLs. No `django.contrib.sites` needed — the view falls back to the request's host.

### Settings

```python
INSTALLED_APPS += ["django.contrib.sitemaps"]

# Absolute URL advertised to crawlers; robots.md's view appends a
# `Sitemap:` line when this is set.
SITEMAP_URL = env("SITEMAP_URL", default=None)
```

`.env.prod`:

```sh
SITEMAP_URL=https://example.com/sitemap.xml
```

### `config/sitemaps.py`

Same placement rule as `references/robots.md`: `config/` by default, or an existing `core`/landing app.

```python
from django.contrib.sitemaps import Sitemap
from django.urls import reverse


class StaticViewSitemap(Sitemap):
    changefreq = "weekly"
    priority = 0.5

    def items(self):
        return ["<url-name>"]  # named URLs of the public pages

    def location(self, item):
        return reverse(item)


sitemaps = {"static": StaticViewSitemap}
```

For public model pages, add a `Sitemap` subclass whose `items()` returns the queryset — `location` defaults to each object's `get_absolute_url()`.

### `config/urls.py`

```python
from django.contrib.sitemaps.views import sitemap

from config.sitemaps import sitemaps

urlpatterns += [
    path("sitemap.xml", sitemap, {"sitemaps": sitemaps}, name="sitemap"),
]
```

## Verifying

```sh
curl -sf http://127.0.0.1:8000/sitemap.xml | grep -q '<urlset'
curl -sf http://127.0.0.1:8000/ | grep -q 'property="og:title"'
```
