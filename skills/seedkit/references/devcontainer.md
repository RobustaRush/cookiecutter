# Devcontainer

Docs: <https://containers.dev/> · <https://code.visualstudio.com/docs/devcontainers/containers>

Wraps a Python image with `uv` so VS Code / Codespaces / JetBrains Gateway open the project in a pre-configured container.

Skip this when the user works in a plain shell — there's nothing else to set up.

## `.devcontainer/devcontainer.json`

```json
{
  "name": "{{project_name}}",
  "image": "mcr.microsoft.com/devcontainers/python:3.13-trixie",
  "features": {
    "ghcr.io/va-h/devcontainers-features/uv:1": {}
  },
  "postCreateCommand": "uv sync --frozen",
  "containerEnv": {
    "DJANGO_SETTINGS_MODULE": "config.settings.local"   // single-file layout: "config.settings"
  },
  "forwardPorts": [8000],
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "batisteo.vscode-django"
      ],
      "settings": {
        "python.defaultInterpreterPath": "${containerWorkspaceFolder}/.venv/bin/python",
        "python.testing.pytestEnabled": true
      }
    }
  }
}
```

If the project's local services (Postgres / Redis / Mailpit) live in `docker-compose.yml`, the devcontainer's network reaches them via `host.docker.internal` rather than service names. Document that in the README so the user runs `docker compose up -d` on the host before reopening in the container.

## Ruff / pyright / pre-commit

Add the matching extensions only if the corresponding add-on was chosen — don't ship `charliermarsh.ruff` if Ruff wasn't selected. Same for `ms-python.mypy-type-checker` (skip if pyright instead).

## Pitfalls

- `forwardPorts` is dev-only — don't add 5432 / 6379 unless the user wants Postgres / Redis exposed *from inside* the editor (e.g., for a DB GUI). Most don't need it.
- Don't bake secrets into `containerEnv`. Devcontainer files are committed; the project's `.env` is not, and that's where credentials belong.
- Don't pin the devcontainer Python image to a different minor than `pyproject.toml`'s `requires-python`. Drift here is the most common "works locally, breaks on the host" failure.
