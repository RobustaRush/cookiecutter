# Blog articles plan

Short how-to articles at `https://django-seedkit.viewflow.io/blog/<slug>/`, one per **integration
aspect** — not one per reference file.

## Why this exists

The reference files under `skills/django-seedkit/references/` hold current, tested wiring for ~50
packages, and none of it is reachable by search or by an LLM answering "how do I add X to Django". A
reference is agent instructions: imperative, snippet-first, no rationale (`CLAUDE.md`, "Writing
reference files"). An article is one piece of that written for a person who hasn't decided yet.

## Granularity

**One aspect per article.** A reference covers a whole topic and usually several packages — `auth.md`
alone holds two mutually exclusive libraries, and `billing.md` holds two. Splitting per file would
produce pages that sprawl and rank for nothing. Splitting per aspect gives each page one job:

- one package's setup → one article
- each distinct thing you'd then do with it → its own article ("verify the webhook", "gate a view by
  subscription", "run the worker in Docker")
- a pitfall sharp enough to be its own search query → its own article

`### Install` / `### Settings` / `### Migrate` are steps *inside* one aspect, not aspects.

## Format

- **~300 words** of prose plus one or two code blocks. Not 150: a hundred 150-word pages on one domain
  is a thin-content cluster, which is the failure mode that would sink the point of publishing them.
- **Title is the query.** "How to add magic-link login to Django", not "Magic-link login".
- **One thing that breaks.** Every reference holds at least one non-obvious failure the test loop
  found. That failure is the article's reason to exist — build the body toward it, in a `.gotcha` block.
- **Link the reference, don't fork it.** Show the minimum snippet, link the reference on GitHub for
  full wiring. Two copies drift; the reference stays canonical.
- **No comparison tables.** Those live on the landing page and in the reference.

## Page template

`site/blog/<slug>/index.html`, styled by `/assets/blog.css`, carrying `TechArticle` JSON-LD, canonical
and OG tags, and a closing `/django-seedkit add …` line. Every new article also needs a row in
`site/blog/index.html` and a `<url>` in `site/sitemap.xml`.

---

## Batch 1 — shipped

| Slug | Title | Source | Gotcha it turns on |
|---|---|---|---|
| `django-magic-link-login` | How to add magic-link login to Django | `auth.md` §B | Stock `auth.User.email` isn't unique; the backend picks the first match |
| `django-stripe-checkout` | How to add Stripe Checkout to Django | `billing.md` §A checkout | Idempotency key stops concurrent first-checkouts making duplicate customers |
| `django-celery-redis` | How to add Celery to Django with Redis | `tasks-celery.md` setup | No time limits means one hung task pins a worker forever |
| `django-tailwind-without-node` | How to use Tailwind CSS in Django without Node | `tailwind.md` setup | `STATICFILES_DIRS[0]` must exist on disk or Django raises at boot |
| `django-brute-force-lockout` | How to lock out brute-force logins in Django | `auth-hardening.md` axes | `AxesBackend` not first in `AUTHENTICATION_BACKENDS` disables lockout silently |

---

## Aspect inventory

Priority: **P1** next up, **P2** after, **P3** long tail. Split against the file when the batch is
written — the sections below are read off each reference's real headings, but a section can still turn
out too thin to stand alone and should merge upward when it does.

### Auth — `auth.md`, `auth-hardening.md`, `custom-user.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-allauth-signup` | How to add signup and email verification to Django | `auth.md` §A |
| P1 | `django-custom-user-email` | How to use email as the Django username | `custom-user.md` |
| P2 | `django-social-login` | How to add Google and GitHub login to Django | `auth.md` §A social |
| P2 | `django-allauth-custom-user` | How to use django-allauth with a custom user model | `auth.md` §A "With a custom user model" |
| P2 | `django-two-factor-totp` | How to add two-factor auth to Django | `auth-hardening.md` §2FA |
| P2 | `django-axes-behind-proxy` | How to make django-axes see the real client IP behind a proxy | `auth-hardening.md` pitfalls |
| P3 | `django-emailuser-passwordless` | How to use a passwordless EmailUser model in Django | `auth.md` §B user model |
| P3 | `django-site-domain-emails` | Why Django account emails link to example.com | `auth.md` §A migrate |
| P3 | `django-axes-redis-handler` | How to keep django-axes off the database hot path | `auth-hardening.md` cache handler |

### Billing — `billing.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-stripe-webhook` | How to verify a Stripe webhook in Django | §A webhook |
| P1 | `django-stripe-subscription-gate` | How to gate a Django view by Stripe subscription | §B querying |
| P2 | `django-stripe-customer-portal` | How to let Django users manage their own subscription | §A portal |
| P2 | `django-stripe-webhooks-locally` | How to test Stripe webhooks locally with Django | §A/§B local dev |
| P2 | `django-dj-stripe-sync` | How to sync Stripe data into Django models | §B setup + sync |
| P3 | `django-dj-stripe-webhook-endpoint` | How to register a dj-stripe webhook endpoint | §B URLs |
| P3 | `django-stripe-billing-signals` | How to react to Stripe billing events in Django | §B signals |

### Background work — `tasks-*.md`, `redis.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-celery-task-discovery` | Where to put Celery tasks so Django finds them | `tasks-celery.md` define |
| P1 | `django-tasks-no-broker` | How to run Django background tasks without a broker | `tasks-django-db.md` |
| P1 | `django-redis-cache` | How to cache Django with Redis | `redis.md` |
| P2 | `django-celery-beat` | How to run scheduled Celery tasks in Django | `tasks-celery.md` Beat |
| P2 | `django-celery-docker-compose` | How to run a Celery worker in Docker Compose | `tasks-celery.md` VPS |
| P2 | `django-rq-queue` | How to add an RQ queue to Django | `tasks-django-rq.md` |
| P2 | `django-cron-tasks` | How to run cron jobs from Django | `tasks-django-cron.md` |
| P3 | `django-task-results-pruning` | How to stop Django task results filling the database | `tasks-django-db.md` prune |
| P3 | `django-rq-failed-jobs` | How to handle failed RQ jobs in Django | `tasks-django-rq.md` failed |
| P3 | `django-tasks-in-tests` | How to run Django background tasks synchronously in tests | `tasks-django-db.md`/`-rq` test settings |
| P3 | `django-task-status` | How to check a Django task's result status | `tasks-django.md` |

### Async and realtime — `async.md`, `realtime.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-async-views` | How to write async views in Django | `async.md` |
| P1 | `django-websockets-channels` | How to add WebSockets to Django with Channels | `realtime.md` setup |
| P2 | `django-asgi-gunicorn-worker` | How to run Django under ASGI in production | `async.md` CMD + workers |
| P2 | `django-channels-scaling` | How to scale Django Channels with sticky sessions | `realtime.md` scale |
| P3 | `django-websocket-idle-timeout` | How to stop idle WebSocket connections dropping | `realtime.md` idle |
| P3 | `django-channels-tests` | How to test Django Channels consumers | `realtime.md` tests |

### API — `rest-modern-rest.md`, `rest-bolt.md`, `cors.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-typed-rest-api` | How to add a typed REST API to Django | `rest-modern-rest.md` |
| P1 | `django-cors-headers` | How to enable CORS in Django | `cors.md` |
| P2 | `django-high-rps-api` | How to serve a high-RPS Django API | `rest-bolt.md` |
| P2 | `django-openapi-schema` | How to publish an OpenAPI schema from Django | both REST refs, OpenAPI |
| P2 | `django-cors-csrf-cookies` | How to make CORS and Django's CSRF cookie work together | `cors.md` CSRF |
| P3 | `django-api-jwt-auth` | How to authenticate a Django API with JWT | `rest-bolt.md` auth |

### Frontend — `tailwind.md`, `favicon.md`, `i18n.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-tailwind-production-build` | How to build Tailwind CSS in a Django Docker image | `tailwind.md` production |
| P1 | `django-custom-error-pages` | How to add custom 404 and 500 pages to Django | `tailwind.md` error templates |
| P2 | `django-daisyui` | How to add DaisyUI to a Django project | `tailwind.md` DaisyUI |
| P2 | `django-favicon` | How to serve a favicon from Django | `favicon.md` |
| P2 | `django-translations` | How to translate a Django site | `i18n.md` |
| P3 | `django-language-prefix-urls` | How to add a language prefix to Django URLs | `i18n.md` URLs |
| P3 | `django-daisyui-theme` | How to set a DaisyUI theme in Django templates | `tailwind.md` theme |

### SEO and privacy — `seo.md`, `robots.md`, `analytics.md`, `gdpr.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-sitemap` | How to add a sitemap to Django | `seo.md` sitemap |
| P1 | `django-privacy-analytics` | How to add cookie-free analytics to Django | `analytics.md` |
| P2 | `django-meta-og-tags` | How to add meta and Open Graph tags to Django templates | `seo.md` meta |
| P2 | `django-robots-txt` | How to serve robots.txt from Django | `robots.md` |
| P2 | `django-gdpr-user-export` | How to export and delete a Django user's data | `gdpr.md` export |
| P3 | `django-sentry-strip-pii` | How to stop Sentry collecting PII from Django | `gdpr.md` Sentry |
| P3 | `django-block-staging-crawlers` | How to keep crawlers off a Django staging site | `robots.md` disallow |

### Email — `email.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-email-settings` | How to configure email in Django with one env var | §settings |
| P1 | `django-html-email-template` | How to send HTML email from Django | §HTML base template |
| P2 | `django-anymail-provider` | How to send Django email through a provider API | §anymail |
| P2 | `django-mailpit-local-email` | How to preview Django email locally with Mailpit | §Mailpit |
| P3 | `django-email-webhooks` | How to track email bounces in Django | §webhooks |

### Storage — `storage-s3.md`, `storage-whitenoise.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-whitenoise-static` | How to serve Django static files with WhiteNoise | `storage-whitenoise.md` |
| P1 | `django-s3-static-media` | How to serve Django static and media files from S3 | `storage-s3.md` |
| P2 | `django-minio-local-s3` | How to test Django S3 storage locally with MinIO | `storage-s3.md` MinIO |
| P3 | `django-s3-collectstatic-docker` | Why collectstatic must leave your Docker build when using S3 | `storage-s3.md` Dockerfile |

### Production settings — `new-project.md`, `security.md`, `csp.md`, `database.md`, `healthcheck.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-settings-from-env` | How to load Django settings from environment variables | `new-project.md` .env |
| P1 | `django-secret-key-no-fallback` | Why your Django SECRET_KEY must have no default | `new-project.md` settings |
| P1 | `django-security-headers` | How to set Django's production security headers | `security.md` |
| P1 | `django-split-settings` | How to split Django settings into base, local, and production | `new-project.md` §B |
| P2 | `django-csp-header` | How to add a Content-Security-Policy to Django | `csp.md` |
| P2 | `django-csp-nonce` | How to allow inline scripts under CSP in Django | `csp.md` nonce |
| P2 | `django-healthcheck-endpoint` | How to add a health-check endpoint to Django | `healthcheck.md` |
| P2 | `django-postgres-database-url` | How to configure Postgres for Django with DATABASE_URL | `database.md` Postgres |
| P2 | `django-sqlite-production` | How to run SQLite in Django production safely | `database.md` SQLite |
| P3 | `django-persistent-db-connections` | How to reuse Django database connections | `database.md` persistent |
| P3 | `django-healthcheck-allowed-hosts` | Why your Django health check returns 400 | `healthcheck.md` gotcha |

### Deploy — `docker.md`, `deploy-vps.md`, `deploy-managed.md`, `deploy-github-ssh.md`, `dbbackup.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-docker-compose-local` | How to run Django and Postgres in Docker Compose | `docker.md` local |
| P1 | `django-production-dockerfile` | How to write a production Dockerfile for Django | `docker.md` production |
| P1 | `django-vps-deploy-caddy` | How to deploy Django to a VPS with automatic HTTPS | `deploy-vps.md` |
| P2 | `django-fly-deploy` | How to deploy Django to Fly.io | `deploy-managed.md` Fly |
| P2 | `django-deploy-github-actions-ssh` | How to deploy Django over SSH from GitHub Actions | `deploy-github-ssh.md` |
| P2 | `django-database-backups` | How to schedule Django database backups | `dbbackup.md` |
| P2 | `django-wait-for-postgres` | How to make Django wait for Postgres in Docker | `docker.md` waiting |
| P3 | `django-deploy-rollback` | How to roll back a Django deploy | `deploy-github-ssh.md` rollback |
| P3 | `django-railway-render-deploy` | How to deploy Django to Railway or Render | `deploy-managed.md` |
| P3 | `django-encrypted-backups` | How to encrypt Django database backups | `dbbackup.md` encryption |
| P3 | `django-restore-backup` | How to restore a Django database backup | `dbbackup.md` restore |

### Observability — `error-reporting.md`, `logging.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-sentry-errors` | How to track Django errors with Sentry | `error-reporting.md` §B |
| P1 | `django-structlog-json-logs` | How to get structured JSON logs out of Django | `logging.md` |
| P2 | `django-self-hosted-error-tracking` | How to self-host Django error tracking with Bugsink | `error-reporting.md` §A |
| P2 | `django-request-log-context` | How to add request context to every Django log line | `logging.md` per-request |
| P3 | `django-worker-error-reporting` | How to report errors from Celery workers | `error-reporting.md` workers |
| P3 | `django-sentry-releases` | How to tag Django releases in Sentry | `error-reporting.md` releases |

### Code quality — `pytest.md`, `lint.md`, `typecheck.md`, `pre-commit.md`, `ci.md`, `dev-tools.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-pytest-setup` | How to test Django with pytest | `pytest.md` |
| P1 | `django-ruff-lint` | How to lint and format Django code with Ruff | `lint.md` |
| P1 | `django-github-actions-ci` | How to set up CI for a Django project | `ci.md` |
| P1 | `django-n-plus-one-detection` | How to catch N+1 queries in Django tests | `dev-tools.md` zeal |
| P2 | `django-type-checking` | How to type-check a Django project | `typecheck.md` |
| P2 | `django-pre-commit` | How to add pre-commit hooks to a Django project | `pre-commit.md` |
| P2 | `django-test-coverage` | How to measure Django test coverage | `pytest.md` coverage |
| P2 | `django-migration-linter` | How to catch unsafe Django migrations before they ship | `dev-tools.md` migration-linter |
| P3 | `django-debug-toolbar` | How to profile Django requests in development | `dev-tools.md` toolbar |
| P3 | `django-browser-reload` | How to auto-reload the browser when a Django template changes | `dev-tools.md` browser-reload |
| P3 | `django-extensions-shell-plus` | How to get a better Django shell | `dev-tools.md` extensions |
| P3 | `django-test-migrations` | How to test a Django data migration | `dev-tools.md` test-migrations |

### Tooling — `uv.md`, `dev-tasks.md`, `devcontainer.md`

| P | Slug | Title | Source |
|---|---|---|---|
| P1 | `django-uv-dependencies` | How to manage Django dependencies with uv | `uv.md` |
| P2 | `django-task-runner` | How to give a Django project a task runner | `dev-tasks.md` |
| P3 | `django-devcontainer` | How to open a Django project in a devcontainer | `devcontainer.md` |

## Not published

- `conventions.md` — the skill's cross-file contract (env names, Redis DB map). Means nothing outside a
  generated project.
- `existing-project.md` — the skill's own inventory workflow, not a Django integration.
- `rest.md` — a chooser between the two REST options. Comparisons stay on the landing page.
