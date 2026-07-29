# Pre-commit hooks

Docs: <https://pre-commit.com/>

Run lint / format / type checks on `git commit` so broken code never reaches the remote. `pre-commit` is a Python tool; hooks themselves can be from any language.

Apply `references/lint.md` first — most of the value here is wiring Ruff into the commit flow.

## Install

```sh
uv add --dev pre-commit
uv run pre-commit install
```

`pre-commit install` writes `.git/hooks/pre-commit` so hooks run on staged files only.

## Config

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: check-toml

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.20
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/astral-sh/uv-pre-commit
    rev: 0.9.17
    hooks:
      # Blocks the commit when uv.lock drifts from pyproject.toml; CI runs `uv sync --locked`.
      - id: uv-lock

  - repo: https://github.com/adamchainz/django-upgrade
    rev: 1.29.1
    hooks:
      # Rewrites deprecated Django APIs. Ruff's UP ruleset covers Python syntax, not Django's.
      - id: django-upgrade

  - repo: https://github.com/adamchainz/djade-pre-commit
    rev: 1.7.0
    hooks:
      # Same, for template syntax: `{% load %}` removals, `{% if %}` operators.
      - id: djade

  - repo: https://github.com/rtts/djhtml
    rev: 3.0.10
    hooks:
      - id: djhtml
        entry: djhtml --tabwidth 2

  # Only if references/typecheck.md is applied:
  - repo: https://github.com/RobertCraigie/pyright-python
    rev: v1.1.411
    hooks:
      - id: pyright
```

`django-upgrade` and `djade` read the target Django version from the `django>=…` pin in
`pyproject.toml`, so neither takes a `--target-version` arg here.

If `references/tailwind.md` is applied, add the class-sorting hook from that file too.

Immediately after writing the file, run `uv run pre-commit autoupdate` and commit the bumped `rev:` values — the pins above age. A `rev:` older than the project's `ruff` dev dependency makes the hook and `uv run ruff format` fight over formatting.

## Run all hooks once

```sh
uv run pre-commit run --all-files
```

Useful first-run after adopting on an existing project — flags everything that isn't currently clean.

## CI

Mirror the local hook in CI so a developer who didn't `pre-commit install` can't sneak past it. In `.github/workflows/test.yml` (or a separate `lint.yml`):

```yaml
      - run: uv run pre-commit run --all-files
```

## Skipping a hook

- Single commit: `git commit --no-verify` — use sparingly; CI will catch you anyway.
- Specific hook: `SKIP=ruff-check git commit -m "..."`.
- Permanently exclude a path: `exclude:` regex in the hook config.

## Updating versions

```sh
uv run pre-commit autoupdate
```

Bumps every `rev:` in the config. Commit the diff like any dependency update.
