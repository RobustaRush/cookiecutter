#!/bin/bash
# Fake /django-seedkit REPL for the README demo GIF.
# Reads the typed prompt, replays generation steps, prints the real
# file tree of the 07-vps-sqlite-saas example.
# Needs the sibling seedkit-examples checkout (../../../seedkit-examples).
cd "$(dirname "$0")/../../../seedkit-examples" || exit 1
printf '\033[2J\033[H'
printf '\033[1;32m❯\033[0m '
read -r _line
sleep 0.6

step() {
  printf '\033[38;5;208m⏺\033[0m %s\n' "$1"
  sleep "$2"
}

step "Reading references: new-project, auth, analytics, email, error-reporting, deploy-vps" 1.1
step "Writing config/settings/{base,development,production}.py" 0.7
step "Writing Dockerfile, deploy/Caddyfile, deploy/docker-compose.prod.yml" 0.7
step "Writing .github/workflows/test.yml" 0.6
step "uv sync · migrate · manage.py check ✓" 0.9
echo
tree -a -L 2 --dirsfirst --noreport -I '.git|__pycache__|uv.lock|migrations|AGENTS.md|CLAUDE.md|mise.toml|.dockerignore|.gitignore|__init__.py|admin.py|apps.py|views.py|tests.py|routers.py|README.md|entrypoint.sh|asgi.py|wsgi.py' 07-vps-sqlite-saas | sed 's/^07-vps-sqlite-saas/your-project/' | while IFS= read -r l; do printf '%s
' "$l"; sleep 0.06; done
echo
printf '\033[1;32m✓\033[0m a running project — uv run manage.py runserver\n'
sleep 3
