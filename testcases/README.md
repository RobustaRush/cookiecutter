# Seedkit test cases

End-to-end checks for the `seedkit` skill. Each test case is a single self-contained prompt that fully specifies every answer the skill would otherwise ask for, so the agent can run it without stopping for clarification.

The point is to catch drift between the skill's references and reality (Django version bumps, uv flags, Docker quirks, package renames) by running real builds.

## How a test case is structured

Each test case is one `.md` file with three sections — four when it exercises a production artefact. `train/run-tests.sh` extracts them by heading, so the names are exact:

```
# <Title>

## Prompt
<Fenced block: the literal `/django-seedkit` invocation plus every answer. No open
questions. The harness also prepends this block to the generated project's
README.md, so it doubles as the reproduction record.>

## Boot check
<Fenced `sh` block the build agent runs after scaffolding. Boots the project,
asserts endpoints, tears down. Auto-fixes are expected when one fails — the
goal is a project that boots.>

## Deploy check   (optional)
<Fenced `sh` block exercising the production image: gunicorn, DEBUG=False,
collectstatic, security headers. Catches what dev-mode boot can't.>

## Review
<Prompt for the independent reviewer — a fresh `claude -p` with read-only
tools, run from the generated project dir with no knowledge of how the build
went. Lists the structural facts to verify, then the standard filter.>
```

### Boot-check rules

- Capture the PID of anything backgrounded (`RUNSERVER_PID=$!`) and `kill` that. `kill $(jobs -p)` doesn't work — the harness runs the snippet in a non-interactive shell with no job control.
- Use `--noreload` on `runserver` so the PID you captured is the process serving requests, not an autoreloader parent.
- A readiness poll must report its own failure. `for i in …; do curl -sf … && break; sleep 1; done` exits 0 even when the server never came up. Set a flag inside the loop and test it after:

```sh
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "$up" ] || { echo "BOOT CHECK FAILED"; kill "$RUNSERVER_PID"; exit 1; }
```

- `pre-commit run` takes an explicit `--files` list, never `--all-files`. Generated projects have no `.git` of their own — they sit inside the examples repo — so `--all-files` resolves the repo root upward and lints every sibling project, reporting their failures as this case's.
- Run a formatting hook twice: the first pass rewrites files and exits non-zero by design, so allow it to fail (`|| true`) and assert on the second. A second-pass failure means a broken hook id or `rev:`, which is the thing worth catching.

### Review-section rules

The reviewer prompt is short and identical across cases: verify the listed structural facts quoting the literal substring read, report only boot-blockers / assertion violations / security holes, no nitpicks, `"No issues found."` is a valid report.

Don't add per-case lists of the skill's intentional design decisions. The quote-the-substring rule and the boot-blocker filter already keep the reviewer off them, and such lists go stale faster than the skill does.

## Requirements for the test set

Coverage rules. Use these to regenerate the suite when the skill changes.

1. **Test case 1 is the minimal example.** SQLite, single-file settings, no lint, no add-ons, no production. This is the smallest path that boots a working project. If this fails, nothing else matters.

2. **Group orthogonal answers into the smallest number of test projects** that still touches every option at least once. Do not enumerate the full Cartesian product. Pairwise coverage across the variation dimensions below is the target.

3. **Variation dimensions to cover** (every value of each must appear in at least one test case):

   **Foundation**
   - Settings layout: `single` / `split`
   - Database: `sqlite` / `postgres`
   - Request handling: `wsgi` / `asgi` / `asgi+channels`
   - Postgres location (only when `postgres`): `host` / `docker-db-only`
   - Dev loop: `host` (default) / `container` — `container` appears in case 03 only, where it also covers the worker and beat as sibling services
   - Custom user model (`AUTH_USER_MODEL`): `yes` / `no`
   - Lint (Ruff): `yes` / `no`
   - Test runner: `pytest` / `manage.py test` (default)
   - Type check (pyright): `yes` / `no` (default)
   - Pre-commit hooks: `yes` / `no` (default) — `yes` appears in cases 02 (with templates, so the HTML formatters fire) and 07 (without)
   - i18n (`gettext`): `yes` / `no` (default)
   - Task runner: `mise` / `just` / `make` / `poe` / `none` (mise + just appear in cases 02 / 03)

   **Add-ons** (each at least once across the suite, but not in the minimal case)
   - Auth: `django-allauth` / `django-mail-auth` / `none`
   - Debug: `django-orbit` / `django-silk` / `none`
   - Browser auto-reload (`django-browser-reload`): `yes` / `no` (yes appears in case 02)
   - Cache backend: `sqlite` / `redis` / `locmem` / `none` (sqlite appears in case 07)
   - Redis: `yes` / `no`
   - Storage: `whitenoise` / `s3` / `none`
   - Tasks: `celery` / `django-tasks-db` / `django-tasks-rq` / `none`
   - Email: `console` / `smtp` / `mailpit` / `anymail` / `none`
   - Structured logging (`structlog`): `yes` / `no`
   - Analytics: `goatcounter` / `umami` / `shynet` / `ga4` / `none`
   - CORS: `yes` / `no` (default no)
   - Database safety: `zeal` / `migration-linter` / `test-migrations` / `none` (each independently; all three appear in case 06)
   - Billing: `stripe` (raw SDK) / `dj-stripe` / `none` (raw stripe appears in case 02)

   **Production** (separate test cases focused on deploy)
   - Security settings: applied / not applied
   - Error reporting: `bugsink` / `sentry` / `glitchtip` / `none`
   - GDPR: `yes` / `no`
   - CI: `yes` / `no`
   - Deploy target: `vps` / `managed` / `github-ssh`
   - Production Dockerfile: multi-stage by default (uv builder → slim runtime) — `references/docker.md`

4. **Respect dependencies between options.** If the skill requires Redis for Celery, the test case must enable Redis. Don't write impossible combinations.

5. **Each prompt must be self-contained.** The AI should never need to ask follow-up questions. Phrase the prompt as a complete spec: project name, purpose, every choice listed explicitly.

6. **Each test case must run end-to-end**, including `migrate` and the boot check (admin login). Commands run on the host (`uv run manage.py …`), except in the container dev loop where they run through `docker compose exec -T web python manage.py …`. Postgres / Redis / Mailpit / MinIO services come from `docker compose up -d --wait`. Add-on-specific checks (e.g. "enqueue and consume a Celery task") belong in the `## Boot check` block.

7. **The reviewer is a separate phase and never sees the build.** `run-tests.sh` runs `## Review` as a fresh `claude -p` from the generated project dir, read-only tools, no skill access, no build context — so file and content assertions live there and the build agent can't game them. Never let the model that built the project grade its own output.

8. **Keep the suite small.** Aim for ~6–10 test cases total. Beyond that, maintenance cost outweighs coverage value. Drop a case before adding a redundant one.

## Running a test case

`train/run-tests.sh` is the runner. From inside `seedkit/train/`:

```sh
./run-tests.sh              # every case
./run-tests.sh 02 07        # specific cases
```

Each case runs in two isolated phases — build, then review — streaming into one log per run under `seedkit-examples/logs/`. Generated projects land in `seedkit-examples/`. `train/review-logs.sh` then walks those logs and patches the skill from what they surfaced.

## When to regenerate

Regenerate the suite (delete current test files and rewrite from this README) whenever:

- A new variation dimension is added to the skill.
- A reference file is split or merged in a way that changes the question flow.
- Multiple test cases end up reporting the same fix — that's a signal the suite is redundant.
