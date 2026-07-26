# Changelog

Versioned `YY.WW.D` — `date +%y.%V.%u` — year / ISO week / ISO weekday. One section per day; all of a day's commits collapse into one block. Trim to ≤ 200 lines; git keeps the rest.

## 26.30.7 — 2026-07-26

### Fixed
- `SKILL.md` §4 — the foundation smoke poll swallowed its own failure. `for … curl -sf … && break; sleep 1; done` exits 0 when the server never comes up, so "if the curl fails, fix the foundation" never fired and a dead foundation passed into §5. Now sets a flag inside the loop and tests it after.
- `deploy-managed.md` — health-check comment pointed at `references/health.md`; the file is `healthcheck.md`.
- `existing-project.md` §2 — derive request handling (`wsgi` / `asgi` / `asgi+channels`) from `INSTALLED_APPS` and the deploy artefacts. SKILL.md §5.7 and `async.md` both branch on it, so an existing channels project used to skip the channel-layer question entirely.
- `tasks-celery.md` — `REDIS_URL` now `.rstrip("/")` like `redis.md` and `realtime.md`; a provider URL with a trailing slash built `redis://host:6379//1`.
- `dev-tools.md` — orbit middleware insert computes the `SecurityMiddleware` index instead of hardcoding 1, matching the silk block.

Full line-by-line audit of the remaining 43 references (previously checked only mechanically) — 36 findings, each adversarially verified:

- Image-build failures: `tailwind.md` called bare `python` in the builder stage, which never puts `/opt/venv/bin` on `PATH` (and duplicated a `collectstatic` RUN `docker.md` already owns); `i18n.md`'s `compilemessages` RUN lacked the production-settings + `DJANGO_DEBUG=True` shim, so it raised `ImproperlyConfigured`; `database.md`'s Litestream entrypoint ran `createcachetable --database cache` unconditionally, but `--database` validates against configured aliases and exits 2 unless §5.3 cache=`sqlite` was chosen; `docker.md`'s `collectstatic` names the single-file settings module alongside the split one.
- `storage-s3.md` keeps `STATIC_ROOT` — base leaves static on Django's local backend, which raises without it. The prose said the opposite.
- `analytics.md` — self-hosted GoatCounter mounted its volume at a path the image doesn't use, so the SQLite DB vanished on container recreate. Volume path fixed and `GOATCOUNTER_DB` set explicitly.
- `error-reporting.md` — `glitchtip-worker` inherited the *app's* `.env.prod` instead of GlitchTip's own DB/Redis/SECRET_KEY; `SENTRY_RELEASE=${GIT_SHA}` in `.env.prod` never resolved, so it moves to a build `ARG` fed by `deploy-github-ssh.md`'s new `build-args`.
- Boot checks that reported success on failure: `rest-bolt.md` and `favicon.md` now test the poll flag and stop the server — the same defect as SKILL.md §4. `rest-bolt.md` also pins `runbolt --port 8001` throughout; it defaults to 8000, so the documented two-server dev workflow couldn't run.
- `realtime.md` — `config/asgi.py` import after `django.setup()` gains `# noqa: E402`; `lint.md` selects the whole `E` ruleset and E402 has no autofix, so CI failed.
- `tasks-django-cron.md` — the `cron` prod service gains `logging: *logging`, which `conventions.md` requires of every service.
- Factual corrections: `django-otp-totp` is not a package (TOTP ships inside `django-otp`); `WHITENOISE_USE_FINDERS` does exist; `django-modern-rest` needs Django 5.0+, not 4.2; `pyjwt` belongs to its `[jwt]` extra, not the `[msgspec]`/`[openapi]` chain; `dmr` *does* belong in `INSTALLED_APPS` when the OpenAPI UI serves static files; `django-bolt` does publish aarch64-linux wheels, so the `linux/amd64` pin is about matching the deploy target; `LocaleMiddleware` resolves URL prefix → cookie → `Accept-Language`.
- Contract and pointer drift: `dbbackup.md` applies to `github-ssh` as well as `vps` and lists the AWS keys in `.env.example`; `deploy-vps.md` now owns `deploy/.env.prod.example` (only `deploy-github-ssh.md` authored it); `healthcheck.md`'s Fly pointer names the `[[services.http_checks]]` block that actually exists; `new-project.md`'s boot check drops `createsuperuser` (SKILL.md §7 owns it); `tailwind.md`'s custom-error-page default aligns to SKILL.md's **no**; `tasks-celery.md` host commands carry the `DJANGO_SETTINGS_MODULE` prefix its own prose assumes, and `dev-tasks.md`'s `worker` task follows.
- Smaller: duplicate host-run sections removed from the three `tasks-django-*` references; `security.md` stray URL rendering as a heading; `auth-hardening.md` restated `ACCOUNT_LOGIN_METHODS`; `devcontainer.md` notes the single-settings module; `robots.md` rationale corrected (staging runs `DEBUG=False`, which is why the explicit toggle is needed).

### Changed
- `SKILL.md` — the new-project path is §2 → §8, not §2 → §6; §7 and §8 are both mandatory.
- `SKILL.md` §5.4 — periodic tasks (`django-crontask`) is now an explicit follow-up under the django-tasks options, not something reachable only by reading `tasks-django.md`.
- `SKILL.md` §6.6 — a deploy target other than `none` applies `docker.md` first; with `none`, skip the production image.
- `existing-project.md` §2 — the settings-layout bullet points at the delta rule in `new-project.md`, which existing-project runs never read as preflight.
- `docker.md` — the local-services boot check uses `docker compose up -d --wait`, with the two rules that were living in `train/run-tests.sh`'s build prompt: give every service a `healthcheck:` so `--wait` has something to block on, and don't hand-roll a `docker compose ps --format json` readiness loop (Compose v2.6+ emits NDJSON, so `json.load` raises). Removed from the harness — the skill carries it now.
- `SKILL.md` §5.6 — when the user already named a REST library, skip the `rest.md` comparison and read the leaf reference directly.

### Testcases and harness
- All nine testcases: boot-check poll loops now report their own failure, and every backgrounded process is killed by captured PID. Six loops exited 0 even when the server never came up, and five used `kill $(jobs -p)` — which SKILL.md §4 forbids, because the harness runs the snippet without job control. The suite could not fail on a dead server.
- `testcases/README.md` — the structure template described `## Expected outcome` / `## Run` / `## Check report` / `## Cleanup`; the real cases use `## Prompt` / `## Boot check` / `## Deploy check` / `## Review`. Rewritten against reality, with the boot-check rules above. Dropped the "no automated runner" claim (`train/run-tests.sh` is the runner) and the per-case list of the skill's intentional design decisions.
- `CLAUDE.md` — `agents.sh` dispatches claude/codex/agy, not gemini; the watchdog variable is `TIMEOUT_PER_PHASE` in `run-tests.sh` and `TIMEOUT_PER_CASE` in `run-baseline.sh`.
- Model pins across `train/` and `testcases/README.md` → `claude-opus-5` (were split across 4-7 and 4-8).
- `run-baseline.sh` produced a control arm that wasn't controlled. It wrote into `seedkit-examples/baselines/`, below the `.claude/skills/seedkit` symlink `run-tests.sh` creates, while telling the agent "there is no skill loaded" — and for `agy`, the skill is installed globally. Baselines still publish from `seedkit-examples/baselines/`, but isolation is now enforced rather than asserted: `unlink_skill()` removes the project-scoped symlinks before the run, `assert_skill_unreachable()` walks up from the baseline root and refuses to start if anything is still reachable, and `run-tests.sh` recreates the symlink on its next invocation. Don't run the two scripts concurrently.
- Baseline logs go to `seedkit-examples/logs/baselines/` — inside the wholesale-gitignored `logs/`, outside `review-logs.sh`'s non-recursive glob. `run-tests.sh` no longer mistakes `baselines/` for a generated project or indexes it in the examples README.
- Both arms now run the same `## Boot check` with the same auto-fix instruction, on the same 7200s ceiling. Previously only the skill arm got to iterate until the project booted, which confounded "the skill helps" with "the skill's arm got a fix-until-green loop"; the baseline also ran on half the timeout, so watchdog kills read as the unaided agent doing worse.
- New `train/scorecard.md` — eight arm-neutral static checks (deps, env-driven settings, secret failsafe, DB config, DEBUG default, gitignored secrets, README accuracy, layout) emitting `SCORE n/8`. Both arms are graded on it; the testcase `## Review` stays skill-arm-only because it asserts structure the control was never asked to produce.
- Both arms write one `results-<cli>.tsv` in the examples repo (`case / arm / cli / model / boot_rc / score / build_s / tool_calls / run_at`), so comparing them is `column -t` rather than eyeballing two trees. Split per CLI so a claude skill run can't be compared against a codex baseline — that measures the CLI, not the skill. `upsert_result()` replaces the row for a `(case, arm)` pair, so re-running a case after a skill fix updates its result instead of appending a second row beside the stale one.
- Timing in the results table is build-phase only (`build_s`, renamed from `duration_s`). It had measured the whole case, so the skill arm was charged for its `## Review` phase — an extra opus agent run the control arm never performs — and would have read as consistently slower for doing more verification. `tool_calls` was already captured before the verification phases.
- `review-logs.sh` skips `baseline-*.log` and any log with no `BUILD` phase — it was globbing `logs/*.log` and trying to review baseline runs as testcase runs. `agents.sh` emits `[tool:NAME]` markers for claude (codex already did) and `count_tool_calls` totals them — reaching a working project in fewer loops is an outcome the skill gets credit for.


### Removed
- `SKILL.md` "Reference files" — the 73-line index of all 50 references. Every §2/§5/§6 question now names its own reference inline (`→ references/lint.md`), so the group listing and the questionnaire no longer drift apart. SKILL.md drops 19,769 → 17,629 chars (~535 fewer tokens per invocation).
- `SKILL.md` "Version pins" pitfall → `conventions.md`, which owns cross-file contracts.
- `SKILL.md` "Snippet integrity" — the settings-delta bullet ("Don't restate values in `local.py` / `production.py` that `base.py` already sets"). `new-project.md` owns the rule and states it in full, naming `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES` / `EMAIL_BACKEND` / `STORAGES`; the SKILL.md copy had already drifted to a shorter version.

## 26.30.5 — 2026-07-24

### Added
- `email.md` — SPF/DKIM/DMARC deliverability note under the provider `.env.prod` block: a correct `EMAIL_URL` still gets password-reset and verification mail dropped without the domain's DNS auth records. Closes the one gap the EuroPython 2026 "Deploying Web Apps in 2026" 10-step model surfaced against the skill (auth secretly depends on email, email secretly depends on DNS).

## 26.30.2 — 2026-07-21

### Removed
- `skills/seedkit-slim/` — the questionnaire-only slim variant is no longer part of the published skill; the repo now ships a single `/seedkit`. Its last state is preserved on the `slim` branch. Dropped the "Two variants" section from `README.md`.
- `REVIEW.md` and the README "Fable 5 Audited" badge + bullet — every finding from the review is fixed (see the `26.29.6` §1–§5 entries below), so the standalone audit file and its README links are retired.

## 26.29.6 — 2026-07-18

### Added
- Testcases follow the day's reference changes: case 02 opts into `django-browser-reload` (boot-check grep for the injected `__reload__` script + review assertions on dev-gated wiring) and asserts the new gunicorn CMD flags, Caddy `encode`/`request_body`, and the `x-logging` anchor; case 03 asserts Celery time limits; case 04 asserts the channel layer on Redis `/4`; case 07 asserts the new Litestream gunicorn flags and drops its stale `deploy-migrate` expectation (the Litestream exception skips it); case 09 asserts the test-gated deploy (`needs: test`, `workflow_call`), `:sha` tags + `IMAGE_TAG`, prune-on-healthy, and the `makemigrations --check` CI step; README gains the browser-reload dimension.
- `dev-tools.md` gains `django-browser-reload` — browser tab auto-reloads on code / template / static changes under `runserver`; dev-gated app + middleware (appended last, after response-encoding middleware) + `__reload__/` URLs. New §5.1 question, default no.
- `conventions.md` — the cross-file contract (env var names, Redis DB map `/0`–`/5`, prod compose service shape with key order, SameSite rule, Python pins, test settings module). Registered in SKILL.md's reference list with a pitfall rule: when two references disagree, conventions.md wins.

### Changed
- Review §5 drift sweep (REVIEW.md 2026-07-18): `realtime.md` channel layer moves to `/4` per the DB map and its `ws` service conforms to the standard shape (`ghcr.io/{owner}/{project_slug}` image, `env_file: .env.prod`, `service_healthy`, `logging`); GlitchTip's internal Redis moves to `/5` (was colliding with the Celery broker on `/1`); `cors.md` and `gdpr.md` cross-reference the SameSite rule instead of silently contradicting; `auth-hardening.md` pins allauth ≥ 65.0 (matching the settings `auth.md` writes) and drops the 0.5x-era history; `typecheck.md` `pythonVersion` aligns to 3.13; `deploy-github-ssh.md`'s test-workflow note now describes the `config.settings.test` module `pytest.md` actually pins; both REST refs point Docs at the live `bolt.farhana.li` (readthedocs 404s); `redis.md` / task refs' DB comments defer to the map; `tasks-django-db/-rq` worker fragments gain the `logging` line.
- Review §4 missing-pieces sweep (REVIEW.md 2026-07-18): `error-reporting.md` gains a Background workers section — verified against sentry-sdk source that Celery/RQ integrations auto-enable and ERROR-level logs (which `django-tasks` workers emit on task failure, via the built-in `task_finished` receiver) become events, so the fix is documentation + a post-deploy check, not wiring; `gdpr.md` export now strips `password` and internal auth fields from the dump handed to the data subject, and deletion notes the required `stripe.Customer.delete` when billing is wired; `custom-user.md` email variant lowercases email in the manager and adds a `UniqueConstraint(Lower("email"))` backstop; `tasks-django-db.md` schedules `prune_db_task_results --min-age-days 14` (result rows otherwise grow forever — command verified in django-tasks-db source); `tasks-django-rq.md` documents the failed-job registry (`rq info --url "$REDIS_URL/3"`, requeue after fixing); `dbbackup.md` drops `mediabackup` when media is on S3 in favor of bucket versioning; `storage-s3.md` sets `AWS_S3_OBJECT_PARAMETERS` Cache-Control, notes media-bucket versioning, and its VPS deploy script gains the mandatory `--env-file`; `rest.md` states neither REST lib ships auth / rate limiting / pagination enabled — wire all three before a public deploy.
- Review §3 deploy-pipeline sweep (REVIEW.md 2026-07-18): `deploy-github-ssh.md` gates deploys on green tests (a `test` job running `test.yml` via `workflow_call`, `deploy` gets `needs: test`), pushes a `:<sha>` tag alongside `:latest`, parameterizes the compose image as `ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest}` with the deploy script exporting the commit SHA, and gains a `## Rollback` section (pull + `up -d` a known-good SHA; destructive migrations reversed explicitly); `ci.md` filters `push:` to `[main]` (kills the double PR run), adds the `workflow_call` trigger and a `makemigrations --check --dry-run` step, and drops the false "setup-uv releases are immutable" claim; `dev-tasks.md` deploy tasks in all four runners now carry `--env-file deploy/.env.prod` (required for compose interpolation of `${GITHUB_REPOSITORY}`), and the Makefile `.PHONY` line covers the deploy targets; `pytest.md` omits `.venv/**` from coverage and drops the scaffold-time `fail_under = 80` gate in favor of a set-it-when-real-code-exists note.
- Review §2 vertical-scaling sweep (REVIEW.md 2026-07-18): gunicorn `CMD` gains `--max-requests 1000` + jitter and `--access-logfile -`, with worker count driven by `WEB_CONCURRENCY` (gunicorn reads it natively; without it prod ran **1 sync worker**) — `docker.md`, `async.md` (both CMD variants, `GUNICORN_CMD_ARGS` snippet replaced), `database.md` Litestream entrypoint, `deploy-github-ssh.md` `.env.prod.example`; `redis.md` prod service gains a `redis_data` volume + `--appendonly yes` (queued Celery/RQ jobs survive restarts) and `--maxmemory … volatile-lru` (evicts only TTL'd cache keys, never broker keys); `deploy-vps.md` compose gains an `x-logging` anchor (json-file 10m×3 — unbounded logs fill the VPS disk) applied across all prod service fragments, a Postgres `shared_buffers` tuning pointer, Caddy `encode zstd gzip` + `request_body max_size 10MB` in both Caddyfile variants, `docker image prune -f` after deploy (also in `deploy-github-ssh.md`, prune-on-healthy only), a healthcheck comment tying the localhost probe to `DJANGO_ALLOWED_HOSTS`, and a sentence stating the few-seconds deploy blip; `tasks-celery.md` adds `CELERY_TASK_TIME_LIMIT`/`SOFT_TIME_LIMIT`, a `celery inspect ping` healthcheck on the worker service, and the Beat example path now targets `{app_label}.tasks` (a registered app) instead of the nonexistent `{project_slug}` module.

### Fixed
- Review §1 boot-blocker sweep (REVIEW.md 2026-07-18): `storage-whitenoise.md` replaces its broken Caddy media block (no prefix strip → every `/media/*` 404s) with a cross-reference to the canonical block in `deploy-vps.md`, whose prose now matches the named-volume mount (`media:/srv/media:ro`); `auth-hardening.md` restores the AND-form `AXES_LOCKOUT_PARAMETERS = [['ip_address', 'username']]` (flat list = username-lockout DoS / proxy-IP mass lockout — regression of the 26.27.6 fix), replaces the stale IPWARE pitfall with `django-axes[ipware]` + `AXES_IPWARE_*` settings for the Caddy-in-Docker path, and drops the false "forces 2FA in prod" comment (no such allauth setting); `billing.md` handles `customer.subscription.updated` with status-derived access (`active`/`trialing`) so payment failures revoke access; `csp.md`'s report-only rollout is now a real standalone `CONTENT_SECURITY_POLICY_REPORT_ONLY` dict replacing (not coexisting with) the enforcing setting; `tasks-django-cron.md` imports `from django_tasks import task` (backport, matching the db/rq siblings) and points Docs at the real repo `codingjoe/django-crontask`; `realtime.md` prefixes the dev uvicorn command with `DJANGO_SETTINGS_MODULE=config.settings.local` (asgi.py defaults to production) and wraps the WS test around `URLRouter` directly so the injected `scope["user"]` survives connect; `storage-s3.md` quotes `'django-storages[s3]'` (zsh globs brackets); `dev-tasks.md` poe tasks call `python manage.py …` and the `deploy-migrate` table row drops the in-container `uv run`; `rest-bolt.md`'s boot check polls with the PID-recorded `break`/`kill` idiom instead of `sleep 1` + bare curl.

## 26.28.2 — 2026-07-07

### Changed
- `rest-bolt.md` / `docker.md`: django-bolt Docker builds now pin `--platform=linux/amd64` on both stages so uv installs the published `manylinux2014_x86_64` wheel — no `build-essential`, no from-source Rust compile, and the image matches Fly's default amd64 machines. Replaces the old arm64-native compile-from-source guidance.

### Fixed
- `deploy-managed.md`: `fly.toml` example gained a `[[services.http_checks]]` block hitting `/readyz` (so Fly gates rollouts on readiness) and a note to bind the HTTP service to the `web` process (`processes = ["web"]`) when `[processes]` is set — the previous example was single-process with no health check.

## 26.28.1 — 2026-07-06

### Fixed
- `tasks-django-rq.md` / `tasks-django-db.md`: both 0.12.0 adapters are built against the standalone `django-tasks` backport (import `django_tasks`), not Django 6's stdlib `django.tasks` — register `django_tasks`, import `from django_tasks import task`, and use `django_tasks.backends.immediate.ImmediateBackend` as the test eager backend.
- `dev-tools.md`: `lintmigrations` `exclude_apps` used the wrong label `django_tasks_database`; the app label is `django_tasks_db`, so its migrations weren't skipped.
- `SKILL.md`: `startapp` ordering pitfall now also covers packages a settings block references (e.g. `orbit.handlers.OrbitLogHandler`) — `uv add` them before the next `startapp` imports settings.
- `ci.md`: CI `DJANGO_SECRET_KEY` placeholder dropped the `django-insecure-` prefix — that prefix trips `security.W009` at the `check --deploy` step regardless of length.

## 26.27.7 — 2026-07-05

### Added
- `seo.md` — meta/OG tags block for `base.html` + `django.contrib.sitemaps` wiring; defines the `SITEMAP_URL` that `robots.md`'s view already consumed. New §5.5 question (default no, skipped when Frontend = none).
- `favicon.md` — agent-drawn SVG favicon matching the project (initial/motif + theme colors), PNG fallbacks via `rsvg-convert`/`sips` when available (ImageMagick excluded — stock builds can't rasterize SVG `<text>`). Follow-up under Frontend, default yes with Tailwind.
- `email.md` gains an HTML email base template (table layout, inline styles) + `send_test_email` management command; follow-up under the email-backend question, default no. Testcase 05 exercises it end-to-end via Mailpit.
- SKILL.md §8: new-project runs now emit `AGENTS.md` (stack decisions, layout, key commands) plus a one-line `CLAUDE.md` (`@AGENTS.md`) so coding agents pick up project context.

### Fixed
- `ci.md`'s placeholder `DJANGO_SECRET_KEY` is now 50+ chars — the old `test-key` tripped `security.W009` at the workflow's own `check --deploy --fail-level WARNING` step.
- `pytest.md` seeds a smoke test per touched app — a project shipping only empty `startapp` stubs makes `pytest` exit 5 ("no tests collected"), turning CI red on first push. `dev-tasks.md` skips `deploy-migrate` for the SQLite + Litestream deploy (migrate runs in `entrypoint.sh`), so `deploy` is a bare `up -d`.
- Testcase 01 boot check no longer races: `runserver --noreload` + a `curl` poll loop, matching SKILL.md §4 (bare `runserver &` + one immediate `curl` fired before the WSGI listener was up).
- `dev-tools.md` drops the `silk_profile`-inside-a-`@task`-body example — Silk only records within a request-scoped `DataCollector`, so it silently no-ops in a worker; profile from a request-scoped view instead.
- `deploy-github-ssh.md` points the inherited compose `web` image at `ghcr.io/${GITHUB_REPOSITORY}:latest` — the CI-built tag — instead of the scaffold-time `{owner}/{project_slug}` placeholder that shipped a literal `{owner}` and broke `compose pull`.

## 26.27.6 — 2026-07-04

### Fixed
- seedkit-slim wrong correctives (REVIEW.md Part II, verified against installed packages): `django-modern-rest.md` rewritten around the real API — import name `dmr`, no `INSTALLED_APPS` entry, `dmr.routing.Router` + `Controller.as_view()` (the previous `modern_rest` module / `router.register` didn't exist); `django-zeal.md` drops the nonexistent `ZEAL_RAISE_ON_VIOLATION` (raising is `ZEAL_RAISE`'s default); `django-allauth.md` drops the `allauth.mfa.urls` include (auto-mounted at `accounts/2fa/`) and the optional `django.contrib.sites`/`SITE_ID`; `new-project.md` gates `ALLOWED_HOSTS` with `env.NOTSET` and compresses the root-URL section; `django-axes.md` uses the AND-form `[['ip_address', 'username']]` (flat list = username-lockout DoS), notes the allauth `login`-field gap and `[ipware]` behind proxies, drops LLM-known lines.

- REVIEW.md blockers: `email.md` anymail path relaxes the `EMAIL_URL` gate to an unconditional default (prod no longer sets the var — the `env.NOTSET` branch crashed boot); `billing.md` dj-stripe rewritten for 2.9+ (webhook endpoints are admin-created DB rows with UUID URLs — `DJSTRIPE_WEBHOOK_SECRET` and `DJSTRIPE_FOREIGN_KEY_TO_FIELD` dropped, `djstripe_receiver` replaces `WEBHOOK_SIGNALS`, checkout view sets `stripe.api_key` from `djstripe_settings`); `deploy-vps.md` deploy commands carry `--env-file deploy/.env.prod`; `dbbackup.md` cron lines get cwd + compose flags + a real host user + log redirect, restore commands get the same flags, pitfall notes pg_dump client ≥ server major; `i18n.md` installs `gettext` in the builder stage (`msgfmt` missing broke the image build) and on the dev host; `realtime.md` WS test sends an `Origin` header so `AllowedHostsOriginValidator` accepts the handshake; `async.md` pitfall drops the nonexistent `Model.objects.afilter(...)`.
- `typecheck.md` — `reportGeneralTypeIssues` / `reportOptionalMemberAccess` no longer downgraded to warnings (warnings never fail pyright's exit code, so CI passed on type errors). Verified 0 errors at error level across four generated example projects; django-stubs kept over django-types (whose stubs lack `UserChangeForm.Meta` and `django.tasks`).

### Added
- seedkit-slim anti-prior references where LLM priors are verifiably wrong: `dj-stripe.md` (2.9+ DB-row webhook endpoints, `djstripe_receiver`, SDK global not set), `deploy-pitfalls.md` (compose `--env-file`, pg_dump client ≥ server major, json-file log rotation, cron cwd/user/log traps); `csp.md` replaces `django-csp.md` — Django ≥ 6.0 ships CSP in core (`SECURE_CSP`, core middleware, `{{ csp_nonce }}`), don't install django-csp. SKILL.md: asgi modes use `uvicorn_worker.UvicornWorker`; deploy step reads deploy-pitfalls first.

### Changed
- Version refresh (all pins verified current 2026-07-04): base images `bookworm`/3.12 → `trixie`/3.13 across docker / rest-bolt / devcontainer / prose (trixie's `postgresql-client` 17 also fixes the pg_dump mismatch against `postgres:17`); `redis:7` → `redis:8`; Litestream 0.3.13 → 0.5.13 (new asset naming `linux-x86_64`, singular `replica:` config); `uvicorn.workers.UvicornWorker` (deprecated) → `uvicorn-worker` package; `checkout@v7`, `setup-uv@v8.2.0` (immutable — pin exact), `build-push-action@v7`, `codecov-action@v7`, `appleboy/ssh-action` SHA-pin placeholder; pre-commit revs bumped + `ruff` hook id → `ruff-check` + "run `pre-commit autoupdate` after writing the config"; DaisyUI downloads pinned to a versioned release URL; Tailwind CLI example 4.3.2; python pins 3.12 → 3.13 (mise, uv examples). New SKILL.md "Version pins" pitfall: resolve current releases at generation time instead of trusting reference pins.

## 26.21.1 — 2026-05-18

### Fixed
- `references/rest-bolt.md` — document all three `runbolt` discovery paths (explicit `BOLT_API`, project-level `config/api.py`, per-app). Default to project-level so an `api/` app isn't auto-created for stateless API surfaces; per-app stays the right choice once the API grows models/admin/migrations.

## 26.20.5 — 2026-05-15

### Fixed
- `testcases/04-media-vault.md` — align assertions with the storage-s3 reference: drop the stale `.dockerignore` requirement (deploy=none has no Dockerfile) and rename the expected MinIO volume `minio-data` → `miniodata`.
- `references/analytics.md` + `references/csp.md` — GA4 inline init `<script>` carries `nonce="{{ request.csp_nonce }}"` so the snippet survives the CSP policy (no `'unsafe-inline'` in `script-src`).
- `references/ci.md` — list `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `DBBACKUP_BUCKET` placeholders so `check --deploy` against `production` doesn't crash when `django-dbbackup` is wired. `testcases/09-internal-ops.md` CI env assertion updated to match (dropped stray `EMAIL_URL` requirement for the email=none path).
- `references/docker.md` + `references/storage-s3.md` + `references/email.md` — clean up `npx dclint` on the dev compose: add `name:` placeholder, reorder service keys to `image → volumes → environment → ports → command → healthcheck`, bind MinIO `9000`/`9001` to `127.0.0.1`, sort Mailpit ports alphabetically. `minio/minio` and `axllent/mailpit` stay on `:latest` — dev-only services, pin churn not worth it.

## 26.20.3 — 2026-05-13

### Added
- `skills/seedkit-slim/references/django-allauth.md` — modern `ACCOUNT_LOGIN_METHODS` / `ACCOUNT_SIGNUP_FIELDS` keys (allauth 0.65+) plus URL wiring for `allauth.mfa.urls`. Slim runs were emitting deprecated `ACCOUNT_AUTHENTICATION_METHOD` / `ACCOUNT_EMAIL_REQUIRED` / `ACCOUNT_USERNAME_REQUIRED` and getting startup warnings.
- `skills/seedkit-slim/references/new-project.md` — foundation snippets for §1 (settings with `DJANGO_*` env vars + `env.NOTSET` prod guards, `/` → `/admin/` redirect in `config/urls.py`, `.gitignore` contents, `django>=6.0,<7.0` pin, boot check using `--noreload`). Slim runs were missing all of these.
- `skills/seedkit-slim/references/django-mail-auth.md` — app label is `mailauth` (not `mail_auth`), backend `mailauth.backends.MailAuthBackend`, requires `django.contrib.sites` + `SITE_ID`, and ships no templates — `registration/login.html` + `registration/login_requested.html` must be scaffolded or `accounts/login/` returns 500.
- `skills/seedkit-slim/references/django-tasks-rq.md` — backend module is `django_tasks_rq.backend` (singular), `django_rq` must be in `INSTALLED_APPS` for its migrations, plus the `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}` setting.
- `skills/seedkit-slim/references/django-modern-rest.md` — `pyjwt` is an implicit dep (imported unconditionally) and router-mount wiring for `config/urls.py`.
- `skills/seedkit-slim/references/pyright.md` — `djangoSettingsModule` belongs under `[tool.django-stubs]`, not `[tool.pyright]`; channels `as_asgi()` needs `# type: ignore[arg-type]` in `path()`.
- `skills/seedkit-slim/references/django-orbit.md` and `references/mailpit.md` — debug-only gating for orbit (app, middleware at index 1, URL mount, logging handler all inside `if DEBUG:`) and Mailpit compose with loopback-only port binds + `EMAIL_URL` wiring. Without these the slim agent shipped orbit in INSTALLED_APPS unconditionally and bound 1025/8025 to all interfaces.
- `skills/seedkit-slim/references/django-tasks-db.md`, `django-zeal.md`, `django-migration-linter.md` — DB backend ships as the separate `django-tasks-db` package (`django_tasks_db.backend.DatabaseBackend`); zeal 2.x middleware is the lowercase function `zeal.middleware.zeal_middleware`; `lintmigrations` needs `django_migration_linter` in `INSTALLED_APPS` plus `MIGRATION_LINTER_OPTIONS.exclude_apps` for third-party migrations.
- `skills/seedkit-slim/references/healthcheck.md`, `django-axes.md`, `django-bolt.md` — trivial `/healthz` + `/readyz` views (avoid pulling `django-health-check`, whose v4 `INSTALLED_APPS` shape broke slim runs); axes v8 wiring without the removed `AXES_LOCKOUT_CALLABLE`; bolt `urls_bolt.py` needs `urlpatterns: list = []` and the builder stage needs `build-essential pkg-config` for the aarch64-linux source build. `pyright.md` notes `user.pk` (django-stubs has no `User.id`).

### Changed
- `new-project.md` directs dev tools through `uv add --group dev` (PEP 735 `[dependency-groups]`). The old `[tool.uv] dev-dependencies` table is deprecated in uv 0.11+.
- `new-project.md` runs `uv python pin 3.12` right after `uv init --bare` so the project doesn't inherit a host 3.14 prerelease.

### Added
- `skills/seedkit-slim/references/django-csp.md` — django-csp 4.0+ uses the nested `CONTENT_SECURITY_POLICY = {"DIRECTIVES": {…}}` shape; the legacy flat `CSP_*` keys raise `csp.E001` at startup.

### Fixed
- `django-tasks-db.md` backend path is `django_tasks_db.DatabaseBackend` (no `.backend.` infix) — the previous snippet raised `ImportError` on boot.
- `new-project.md` boot check runs `makemigrations` before the first `migrate` so the §1.6 custom `AUTH_USER_MODEL` doesn't abort the initial `migrate`.
- `new-project.md` appends `[tool.uv] package = false` to `pyproject.toml` right after `uv init --bare`. Django apps aren't installable; without this, `uv sync` invoked hatchling and failed mid-foundation.
- `new-project.md` settings snippet guards `environ.Env.read_env()` with `if _env_file.exists()`. Docker images have no `.env` and bare `read_env()` raised `FileNotFoundError` during `collectstatic`.

### Changed
- Testcase Prompt blocks no longer name specific reference files for the agent to read (`references/docker.md`, `references/realtime.md`, `references/database.md`, `references/email.md`). The skill picks references itself; prompts only state the requirement. Touched 02-shop, 03-jobs-board, 04-media-vault, 07-saas, 09-internal-ops.

