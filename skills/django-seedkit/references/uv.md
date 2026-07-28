# uv

Docs: <https://docs.astral.sh/uv/>

## Install

**macOS / Linux**
```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Homebrew**
```sh
brew install uv
```

## Project

```sh
uv init --bare {project_name}   # --bare: no main.py / README.md / .python-version
uv add django
uv add --dev pytest ruff   # examples; lint/pytest are optional foundation choices
uv remove django
uv sync
uv run manage.py runserver
uv run pytest
```

## Python

```sh
uv python install 3.13
uv python pin 3.13
```

## Tools

```sh
uvx ruff check .
uv self update
```
