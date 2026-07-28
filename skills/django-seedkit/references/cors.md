# CORS — django-cors-headers

Docs: <https://github.com/adamchainz/django-cors-headers>

Browsers block cross-origin requests by default. `django-cors-headers` adds the response headers Django needs to allow them when the frontend lives on a different origin (separate SPA, third-party widget, mobile app talking to the API).

Skip if Django serves both API and templates from the same origin — same-origin requests don't need CORS.

## Install

```sh
uv add django-cors-headers
```

## Settings

```python
INSTALLED_APPS = [
    ...
    "corsheaders",
]

# Insert above CommonMiddleware.
common_idx = MIDDLEWARE.index("django.middleware.common.CommonMiddleware")
MIDDLEWARE.insert(common_idx, "corsheaders.middleware.CorsMiddleware")

CORS_ALLOWED_ORIGINS = env.list(
    "DJANGO_CORS_ALLOWED_ORIGINS",
    default=["http://localhost:3000", "http://127.0.0.1:3000"] if DEBUG else [],
)
CORS_ALLOW_CREDENTIALS = True   # send cookies / Authorization cross-origin
```

`CORS_ALLOWED_ORIGINS` is a strict allowlist. Don't use `CORS_ALLOW_ALL_ORIGINS = True` in production; it disables CORS protection entirely.

## CSRF + cookies

If the frontend sends authenticated requests (cookies or `Authorization` header), CSRF also needs the frontend origin trusted:

```python
CSRF_TRUSTED_ORIGINS = env.list(
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    default=["http://localhost:3000"] if DEBUG else [],
)
# "None" only because the cross-origin frontend authenticates with session
# cookies — projects without that keep the "Lax" from references/gdpr.md.
SESSION_COOKIE_SAMESITE = "None"
SESSION_COOKIE_SECURE = not DEBUG    # SameSite=None requires Secure (HTTPS) in browsers
CSRF_COOKIE_SAMESITE = "None"
CSRF_COOKIE_SECURE = not DEBUG
```

Without `Secure=True` in production browsers reject `SameSite=None` cookies — login silently fails.

## .env

```sh
DJANGO_CORS_ALLOWED_ORIGINS=https://app.example.com,https://staging.example.com
DJANGO_CSRF_TRUSTED_ORIGINS=https://app.example.com,https://staging.example.com
```

## Pragmatics

- `CORS_ALLOWED_ORIGIN_REGEXES` if you need pattern matching (e.g. preview deploys with random subdomains). Use sparingly.
- `CORS_EXPOSE_HEADERS` if the frontend needs to read non-default response headers (`X-Total-Count` for pagination, etc.).
- Preflight (`OPTIONS`) requests — django-cors-headers handles them; no view code needed.
