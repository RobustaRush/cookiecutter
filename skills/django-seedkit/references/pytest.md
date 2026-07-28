# Test runner — pytest

Docs: <https://docs.pytest.org/> · <https://pytest-django.readthedocs.io/> · <https://coverage.readthedocs.io/>

Stock Django ships `manage.py test` (unittest-based). `pytest-django` swaps in pytest: shorter test files, fixtures, parametrization, better failure output. Adds two dev deps; doesn't change production code.

If you skip this, write tests with `django.test.TestCase` and run `uv run manage.py test`.

## Install

```sh
uv add --dev pytest pytest-django
```

## Config

`pytest.ini` (or `[tool.pytest.ini_options]` in `pyproject.toml`):

```ini
[pytest]
DJANGO_SETTINGS_MODULE = config.settings.test
python_files = tests.py test_*.py *_tests.py
```

For a single-settings layout, point at `config.settings`. The split layout already ships `config/settings/test.py` — see `references/new-project.md`.

## Seed a smoke test

`pytest` exits 5 ("no tests collected") when a project ships only empty `startapp` stub `tests.py` files — that turns CI (`references/ci.md`) red on the first push. Ship at least one real test per app you touched:

```python
# users/tests.py
import pytest


@pytest.mark.django_db
def test_smoke(client):
    assert client.get("/health/").status_code in (200, 302, 404)
```

## Run

```sh
uv run pytest
uv run pytest -k user        # only tests with "user" in the name
uv run pytest path/to/tests.py::test_signup
```

`pytest-django` builds a fresh `test_<dbname>` from migrations on first run, then reuses it. Add `--create-db` to force a rebuild after a schema change.

## Coverage

`pytest-cov` plugs `coverage.py` into the pytest run.

```sh
uv add --dev pytest-cov
```

`pyproject.toml`:

```toml
[tool.coverage.run]
source = ["."]
omit = [
    ".venv/**",
    "**/migrations/**",
    "**/tests/**",
    "**/test_*.py",
    "config/wsgi.py",
    "config/asgi.py",
    "manage.py",
]

[tool.coverage.report]
show_missing = true
skip_covered = true
```

Add `fail_under = <threshold>` to `[tool.coverage.report]` once the app has real code — on a fresh scaffold, the seeded smoke tests land at an arbitrary percentage and any gate just turns first-push CI red.

Run:

```sh
uv run pytest --cov                # terminal report
uv run pytest --cov --cov-report=html   # writes htmlcov/
```

In CI, emit Cobertura XML for upload to a coverage service (Codecov / Coveralls):

```yaml
      - run: uv run pytest --cov --cov-report=xml
      - uses: codecov/codecov-action@v7    # optional
```

Add `htmlcov/` and `.coverage` to `.gitignore`.

## CI

`references/ci.md`'s GitHub Actions workflow runs `uv run pytest` after `uv sync --frozen`. The dev deps installed above are what makes that step actually succeed.
