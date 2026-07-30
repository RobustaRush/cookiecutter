# Dev task runner

One short name per workflow step so the README can show `mise run dev` instead of `uv run manage.py runserver`, `just test` instead of `uv run pytest`, etc.

## Pick the runner

Ask the user. Default: **mise** (recommended). If unsure what's installed, detect with `command -v mise just make poe` and offer the first hit.

| Runner | File written | Install |
| --- | --- | --- |
| mise | `mise.toml` | `curl https://mise.run \| sh` |
| just | `justfile` | `brew install just` |
| make | `Makefile` | ships with most systems |
| poe | `[tool.poe.tasks]` in `pyproject.toml` | `uv add --dev poethepoet` |
| none | — | skip the whole reference |

Mise is the recommended pick because it also pins the Python toolchain (`[tools] python = "3.13"`), so the project gets one tool instead of `pyenv` + `just`.

## Task list

Generate one task per command the README would otherwise spell out. Include only the tasks for add-ons the project actually applied. The bodies below assume the host dev loop; for the container loop see "Container dev loop" further down.

| Task | Command |
| --- | --- |
| `install` | `uv sync` |
| `dev` | `uv run manage.py runserver` |
| `migrate` | `uv run manage.py migrate` |
| `makemigrations` | `uv run manage.py makemigrations` |
| `shell` | `uv run manage.py shell` |
| `superuser` | `uv run manage.py createsuperuser` |
| `test` | `uv run pytest` *(or `uv run manage.py test`)* |
| `lint` | `uv run ruff check .` *(ruff = yes)* |
| `fmt` | `uv run ruff format .` *(ruff = yes)* |
| `typecheck` | `uv run pyright` *(pyright = yes)* |
| `collectstatic` | `uv run manage.py collectstatic --noinput` |
| `worker` | `DJANGO_SETTINGS_MODULE=config.settings.local uv run celery -A config worker -l info` *(celery)* or `uv run manage.py db_worker` *(django-tasks)* |
| `tailwind` | `uv run manage.py tailwind runserver` *(tailwind)* |
| `deploy-migrate` | one-shot `docker compose … run --rm web python manage.py migrate` *(deploy=vps / github-ssh)* |
| `deploy` | `deploy-migrate` then `docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d` *(deploy=vps / github-ssh)* or `fly deploy` *(deploy=managed/fly)* |

Deploy tasks: only generate when §6.6 deploy target was picked. `--env-file deploy/.env.prod` is required on every compose call — compose auto-loads only `./.env`, and the image line's `${GITHUB_REPOSITORY}` interpolates from that file (`references/deploy-github-ssh.md`).
- `vps` / `github-ssh`: `deploy` depends on `deploy-migrate` so the one-shot migrate always precedes `up -d` — that's the gap a bare `docker compose up -d --build` hits on first boot against an empty DB.
  - Exception: the SQLite + Litestream pattern (`references/database.md`) runs `migrate --noinput` inside `entrypoint.sh` on every boot, so skip `deploy-migrate` — `deploy` is a bare `up -d`.
- `managed` (Fly.io): single `deploy = fly deploy` task — Fly's release command runs migrations, no separate `deploy-migrate` needed.
- `managed` (Railway / Render): skip — those platforms deploy on `git push`, no task to alias.

## Container dev loop

When `manage.py` runs in a `web` container (`references/docker.md`), every task body changes: `uv run <cmd>` becomes `docker compose exec -T web <cmd>`, and `python` replaces `uv run` inside the container. Three tasks change shape rather than prefix — `install` builds the image, `dev` runs the stack in the foreground, and `worker` / `tailwind` disappear because those are sibling services the stack already starts.

```just
dc := "docker compose exec -T web"

install:
    docker compose build

dev:
    docker compose up

migrate:
    {{dc}} python manage.py migrate

test:
    {{dc}} pytest

shell:
    docker compose exec web python manage.py shell

superuser:
    docker compose exec web python manage.py createsuperuser
```

`-T` on every scripted task: without it `exec` demands a TTY and fails wherever there is none — CI, a hook, a `just` recipe run from an editor. `shell` and `createsuperuser` are the exceptions; both need the TTY they would otherwise be denied.

mise, make and poe take the same bodies. Neither mise nor make has `just`'s variable interpolation, so write the prefix out in each task, or set it once — `[env] DC = "docker compose exec -T web"` in `mise.toml`, `DC = docker compose exec -T web` in a `Makefile` — and use `$DC`.

## mise.toml

```toml
[tools]
python = "3.13"

[tasks.install]
run = "uv sync"

[tasks.dev]
run = "uv run manage.py runserver"

[tasks.migrate]
run = "uv run manage.py migrate"

[tasks.test]
run = "uv run pytest"

[tasks.deploy-migrate]
run = "docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate"

[tasks.deploy]
depends = ["deploy-migrate"]
run = "docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d"
```

Run with `mise run dev`. First-time setup: `mise trust && mise install`.

## justfile

```just
install:
    uv sync

dev:
    uv run manage.py runserver

migrate:
    uv run manage.py migrate

test:
    uv run pytest

deploy-migrate:
    docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate

deploy: deploy-migrate
    docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
```

Run with `just dev`. `just --list` enumerates tasks.

## Makefile

Indent with **tabs**, not spaces. Every target is `.PHONY` because none produce a file matching the target name.

```make
.PHONY: install dev migrate test deploy-migrate deploy

install:
	uv sync

dev:
	uv run manage.py runserver

migrate:
	uv run manage.py migrate

test:
	uv run pytest

deploy-migrate:
	docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate

deploy: deploy-migrate
	docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
```

## poethepoet

```sh
uv add --dev poethepoet
```

```toml
[tool.poe.tasks]
install = "uv sync"
dev     = "python manage.py runserver"
migrate = "python manage.py migrate"
test    = "pytest"
deploy-migrate = { shell = "docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate" }
deploy = { sequence = ["deploy-migrate", { shell = "docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d" }] }
```

Poe strips `uv run` because it executes inside the venv. Run with `uv run poe dev`.

## README

Replace the `uv run …` block in the README with the chosen runner's commands. Keep one fallback line at the bottom for users who don't want to install the runner — point them at `uv run manage.py <cmd>`.
