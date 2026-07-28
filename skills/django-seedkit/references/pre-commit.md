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

  # Only if references/typecheck.md is applied:
  - repo: https://github.com/RobertCraigie/pyright-python
    rev: v1.1.411
    hooks:
      - id: pyright
```

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
