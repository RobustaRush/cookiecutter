# Deploy — GitHub Actions via SSH

Docs: <https://docs.github.com/en/actions> · <https://github.com/appleboy/ssh-action>

This pattern is built on top of `references/deploy-vps.md`. Read that first
— this file only adds the GitHub Actions wrapper. In particular, it inherits
`docker-compose.prod.yml`, the Caddy reverse proxy, and the `/healthz`
container healthcheck.

One change to the inherited `docker-compose.prod.yml`: the `web` image line is
built and pushed by CI, and the owner isn't known at scaffold time. Point it at
the exported env vars, not a hardcoded `{owner}/{project_slug}`:

```yaml
    image: ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest}
```

The deploy workflow exports `IMAGE_TAG` as the commit SHA, so every deploy is
addressable and `## Rollback` below can pin any previous one; manual compose
calls without the var fall back to `:latest`.

## Secrets

Set in repo settings:
- `SSH_HOST`
- `SSH_USER`
- `SSH_KEY`
- `GHCR_TOKEN` — a PAT with `read:packages`, used by the **server** to pull
  private images. `${{ secrets.GITHUB_TOKEN }}` is only valid inside Actions;
  the VPS needs its own credential.

## deploy/.env.prod.example — ship this in the repo

`references/deploy-vps.md` defines the base template. Append one section for
the GHCR image path:

```sh
# Image
GITHUB_REPOSITORY=owner/repo        # the GHCR image path
```

`IMAGE_TAG` is not listed — the deploy workflow exports it as the commit SHA and
the compose file falls back to `:latest`.

## .github/workflows/deploy.yml

```yaml
name: deploy

on:
  push:
    branches: [main]

# Two pushes in quick succession must serialize, not race on the same host.
concurrency:
  group: deploy
  cancel-in-progress: false

permissions:
  contents: read
  packages: write

jobs:
  # The gate: red tests never reach the server. Requires the `workflow_call`
  # trigger on test.yml (references/ci.md). If CI wasn't applied, drop this
  # job and the `needs: test` line.
  test:
    uses: ./.github/workflows/test.yml

  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v7
        with:
          push: true
          # :latest for humans, :<sha> so every deploy stays pullable for rollback.
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          target: prod                              # matches the `prod` stage in references/docker.md
          build-args: |
            GIT_SHA=${{ github.sha }}                # feeds SENTRY_RELEASE (references/error-reporting.md)

      # Pin third-party deploy actions to a commit SHA, not a tag — this step
      # runs arbitrary shell on prod. Resolve the SHA of the latest release:
      #   gh api repos/appleboy/ssh-action/git/ref/tags/<latest-tag> --jq .object.sha
      - uses: appleboy/ssh-action@<SHA>  # v1.2.5
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            set -euo pipefail
            cd /srv/{project_slug}
            # Compose reads `${GITHUB_REPOSITORY}` from the shell env, not
            # `env_file:`. Without the export `compose pull` resolves to
            # `ghcr.io/:latest`. `--env-file deploy/.env.prod` is required
            # on every compose call — auto-`.env` discovery only loads
            # `.env`, not `deploy/.env.prod`.
            export GITHUB_REPOSITORY="${{ github.repository }}"
            export IMAGE_TAG="${{ github.sha }}"
            # Server-side docker login for the private ghcr image.
            echo "${{ secrets.GHCR_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web python manage.py migrate
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
            # Wait for the container healthcheck (defined in deploy-vps.md)
            # to flip to "healthy" — don't sleep-and-curl on plain HTTP if
            # SECURE_SSL_REDIRECT is on, that returns 301 and `curl` without
            # `-L` reads success regardless of the upstream actually being up.
            status=starting
            for i in $(seq 1 30); do
              status=$(docker inspect -f '{{.State.Health.Status}}' \
                $(docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml ps -q web) 2>/dev/null || echo starting)
              [ "$status" = "healthy" ] && break
              sleep 2
            done
            [ "$status" = "healthy" ] || { echo "web never became healthy"; exit 1; }
            # Prune only after a healthy deploy — old :latest layers otherwise
            # accumulate until the disk fills.
            docker image prune -f
```

When this reference is applied together with `references/ci.md`, remove the
`push:` trigger from `test.yml` — the deploy workflow already runs it on every
main push via `workflow_call`, and both triggers firing doubles every CI run.

## Rollback

Every deploy is tagged with its commit SHA, and the deploy script prunes images
only after a healthy deploy — so the previous image is still pullable when a
deploy goes bad:

```sh
ssh user@vps
cd /srv/{project_slug}
export GITHUB_REPOSITORY=owner/repo IMAGE_TAG=<known-good commit sha>
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull web
docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d web
```

Migrations are not auto-reversed: rolling back assumes the old code runs against
the current schema, which holds for additive migrations. If the bad deploy
shipped a destructive migration, reverse it explicitly (`manage.py migrate <app>
<previous_migration>`) before `up -d`.

## Test workflow — also pin `DJANGO_SETTINGS_MODULE`

`references/pytest.md` pins `DJANGO_SETTINGS_MODULE = config.settings.test`
in the pytest config — CI inherits it, no test-job override needed. Keep the
`manage.py check --deploy` step against `config.settings.production`
(`references/ci.md`) so regressions in security settings (SSL_REDIRECT
without proxy, missing HSTS, etc.) fail CI rather than first-deploy.
