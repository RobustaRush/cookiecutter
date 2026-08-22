# Content Security Policy — Django 6.1

Docs: <https://docs.djangoproject.com/en/6.1/howto/csp/>

Layer this on top of `references/security.md`. Django 6.1 includes CSP support, so do not add `django-csp`. Apply it only when the user selected security and CSP.

## `production.py` only

Append the middleware; do not re-declare `MIDDLEWARE`, which would drop additions from `base.py` such as WhiteNoise.

```python
from django.utils.csp import CSP

MIDDLEWARE = [*MIDDLEWARE, "django.middleware.csp.ContentSecurityPolicyMiddleware"]

SECURE_CSP = {
    "default-src": [CSP.SELF],
    "script-src": [CSP.SELF],
    "style-src": [CSP.SELF, CSP.UNSAFE_INLINE],  # Admin needs inline styles.
    "img-src": [CSP.SELF, "data:"],
    "font-src": [CSP.SELF],
    "connect-src": [CSP.SELF],
    "frame-ancestors": [CSP.NONE],
    "base-uri": [CSP.SELF],
    "form-action": [CSP.SELF],
}
```

## Per-add-on sources

Add a host only when its add-on is selected. Extend directives instead of replacing them: selected add-ons can need the same directive.

| Add-on | Directives | Source |
|---|---|---|
| `django-allauth` social providers | `connect-src`, `img-src` | provider domains, such as `https://accounts.google.com` |
| `analytics-ga4` | `script-src`, `connect-src`, `img-src` | `https://www.googletagmanager.com`, `https://www.google-analytics.com` |
| `analytics-umami` | `script-src`, `connect-src` | `ANALYTICS_HOST` |
| `analytics-goatcounter` | `script-src`, `connect-src` | `https://gc.zgo.at` |
| `storage-s3` | `img-src` | S3 or CDN host when media appears in `<img>` |
| `error-reporting-sentry` | `connect-src`, `script-src` | Sentry or GlitchTip ingest host |

For GA4, the inline initialization block needs a nonce and its context processor:

```python
SECURE_CSP["script-src"] += [
    CSP.NONCE,
    "https://www.googletagmanager.com",
    "https://www.google-analytics.com",
]
SECURE_CSP["connect-src"] += [
    "https://www.googletagmanager.com",
    "https://www.google-analytics.com",
]
SECURE_CSP["img-src"] += [
    "https://www.googletagmanager.com",
    "https://www.google-analytics.com",
]
TEMPLATES[0]["OPTIONS"]["context_processors"] += [
    "django.template.context_processors.csp",
]
```

For env-driven Umami:

```python
_UMAMI = [ANALYTICS_HOST] if ANALYTICS_HOST else []
SECURE_CSP["script-src"] += _UMAMI
SECURE_CSP["connect-src"] += _UMAMI
```

## Inline scripts

Use a nonce for an inline script, never `'unsafe-inline'` in `script-src`:

```html
<script nonce="{{ csp_nonce }}">
```

The nonce works only when the directive contains `CSP.NONCE` and `django.template.context_processors.csp` is configured. The middleware then creates one nonce per response and adds the matching source expression to the header.

## Report-only first

For the first deploy, use `SECURE_CSP_REPORT_ONLY` instead of `SECURE_CSP` so violations are visible before they block assets:

```python
SECURE_CSP_REPORT_ONLY = {
    "default-src": [CSP.SELF],
    "script-src": [CSP.SELF],
    "style-src": [CSP.SELF, CSP.UNSAFE_INLINE],
    "img-src": [CSP.SELF, "data:"],
    "font-src": [CSP.SELF],
    "connect-src": [CSP.SELF],
    "frame-ancestors": [CSP.NONE],
    "base-uri": [CSP.SELF],
    "form-action": [CSP.SELF],
}
```

Once the reports are clean, rename it to `SECURE_CSP`.

## Pitfalls

- Do not add `'unsafe-inline'` to `script-src`. If a third-party widget needs it, isolate that widget in a narrower iframe policy.
- CSP applies to document responses, not JSON API responses; REST endpoints need no exemption.
- A response with a nonce must not be served from a cache that reuses an HTML body with a different CSP header.
