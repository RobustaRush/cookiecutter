# REST API

Docs: <https://django-modern-rest.readthedocs.io/> · <https://bolt.farhana.li/>

Stock Django doesn't ship a REST framework. The seedkit offers two opt-in options. Both are typed, schema-validated, and async-aware — they differ on how they run and how invasive they are.

Ask the user: `django-modern-rest` / `django-bolt` / `none`. Default `none`.

## Comparison

| Trait | `django-modern-rest` | `django-bolt` |
|---|---|---|
| Server | Stock Django (WSGI **or** ASGI). Same `runserver` / `gunicorn`. | Own Rust HTTP server (Actix Web + PyO3). Run via `manage.py runbolt`. |
| Schema libraries | pydantic, msgspec, attrs, dataclasses, TypedDict — pluggable | msgspec only |
| Async support | Sync and async handlers; no `sync_to_async` shims | Async-first; integrates with Django's async ORM (`aget`, etc.) |
| Auth / permissions | Lean on Django's auth + decorators; optional JWT extra | Built-in JWT / API key (validated in Rust without GIL); DRF-style guards |
| OpenAPI | First-class, schema-validated, msgspec-backed | Auto-generated; Swagger / ReDoc / Scalar / RapidDoc UIs |
| Maturity | 0.x; pre-1.0 API stability not yet promised | 0.x; "under active development", same caveat |
| When to pick | You want a typed REST layer that stays fully inside the standard Django request/response cycle, plays well with all middleware, and lets you choose the schema lib. | You need raw RPS (60k–188k benchmarked) and don't mind a Rust binary plus a separate `runbolt` server next to (or instead of) gunicorn. |

If the user says "I just want REST endpoints in my Django project," recommend **`django-modern-rest`** — it doesn't change the runtime. Recommend **`django-bolt`** only when high-throughput JSON APIs are the explicit goal.

When picking `django-bolt`, ask a follow-up: do you want a separate slim settings module for the bolt process (`config/settings/bolt.py`) to strip middleware / apps the API path doesn't need? **Default no.** Only opt in when raw RPS was the explicit reason for picking bolt — see the *Fast-path settings* section in `rest-bolt.md` for the trade-off (two settings files can drift).

Then load the matching file:

- `rest-modern-rest.md` for `django-modern-rest`
- `rest-bolt.md` for `django-bolt`

## Before a public deploy

Neither library enables auth, rate limiting, or pagination by default — wire all three from the chosen library's docs before exposing an endpoint to the internet.

## CORS + REST

If `cors=yes` (`references/cors.md`), `corsheaders.middleware.CorsMiddleware` must sit **above** any REST middleware in `MIDDLEWARE`.

## .env.example

Neither library needs new env vars by default. Only add JWT secrets if the user opts into JWT auth — the per-library file documents the exact keys.
