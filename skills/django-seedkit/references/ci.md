# GitHub Actions — Tests

Docs: <https://docs.github.com/en/actions> · <https://github.com/astral-sh/setup-uv>

The workflow below runs `uv run pytest`. If pytest wasn't picked at foundation time, swap `uv run pytest` for `uv run manage.py test` (the workflow itself stays the same). Test runner setup — `pytest`, `pytest-django`, `pytest.ini` — lives in `references/pytest.md`.

## .github/workflows/test.yml

```yaml
name: test

on:
  push:
    branches: [main]   # bare `push:` + `pull_request:` double-runs every PR commit
  pull_request:
  workflow_call:       # lets deploy.yml run this workflow as its test gate

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5
      # Add this block only when redis is wired (cache / celery / django-tasks-rq).
      redis:
        image: redis:8
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5

    env:
      # For SQLite, swap the URL — never drop the var. `base.py` requires
      # DATABASE_URL once `DJANGO_DEBUG=False`, so the workflow fails import
      # at the first `manage.py` / `pytest` step without it.
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
      # DATABASE_URL: sqlite:////tmp/ci.sqlite3
      # 50+ chars, 5+ unique, no `django-insecure-` prefix — a short key or
      # that prefix trips security.W009 at the `check --deploy` step below.
      DJANGO_SECRET_KEY: ci-placeholder-secret-key-not-a-real-secret-0123456789-abcxyz
      DJANGO_DEBUG: "False"
      DJANGO_ALLOWED_HOSTS: "*"
      # `DEBUG=False` triggers the gated `env.NOTSET` branch on every
      # required env var. Provide safe placeholders so settings load:
      EMAIL_URL: consolemail://
      DEFAULT_FROM_EMAIL: test@example.com
      SERVER_EMAIL: test@example.com
      REDIS_URL: redis://localhost:6379       # only when redis / celery / django-tasks-rq is wired
      POSTMARK_SERVER_TOKEN: ci-placeholder   # only when django-anymail[postmark] is wired
      ANYMAIL_WEBHOOK_SECRET: ci-placeholder  # only when the Anymail webhook URL is wired
      AWS_ACCESS_KEY_ID: ci-placeholder       # only when django-dbbackup is wired
      AWS_SECRET_ACCESS_KEY: ci-placeholder   # only when django-dbbackup is wired
      DBBACKUP_BUCKET: ci-placeholder         # only when django-dbbackup is wired

    steps:
      - uses: actions/checkout@v7

      # Pin the latest release from github.com/astral-sh/setup-uv/releases.
      - uses: astral-sh/setup-uv@v8.2.0
        with:
          enable-cache: true

      - run: uv sync --frozen

      # Catches security-setting regressions (SSL_REDIRECT without proxy,
      # missing HSTS, etc.) at CI time instead of first-deploy.
      - run: uv run manage.py check --deploy --fail-level WARNING
        env:
          DJANGO_SETTINGS_MODULE: config.settings.production

      # Fails when a model change landed without its migration.
      - run: uv run manage.py makemigrations --check --dry-run

      - run: uv run pytest        # or `uv run manage.py test` if pytest wasn't chosen
```

Don't add a `manage.py migrate` step before tests. `pytest-django` and Django's own test runner each build a `test_<dbname>` database from migrations on every run — a pre-step migrate touches the service DB, doesn't affect the test DB at all, and pollutes state for any later step that reuses the same connection.
