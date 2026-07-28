#!/usr/bin/env bash
#
# Loop over seedkit-examples/logs/*.log, ask a fresh agent CLI to review
# each one against the skill, apply short fixes where a real defect is
# present, commit + push the submodule + parent pointer, then delete the
# log. One log at a time, sequential.
#
# Same session + watchdog + pgrp sweep mechanics as run-tests.sh so a
# stuck sub-agent can't livelock the loop.
#
# Usage (run from inside seedkit/train/):
#   ./review-logs.sh                    # review every *.log in the logs dir
#   ./review-logs.sh 02-shop-20260510-173829.log    # single file (basename)
#   MODEL=claude-opus-5 ./review-logs.sh
#   AGENT_CLI=codex ./review-logs.sh    # or agy
#   TIMEOUT_PER_LOG=1800 ./review-logs.sh
#
# Requires: jq, python3, git, and whichever CLI $AGENT_CLI names.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT="$(cd "$REPO/.." && pwd)"
# shellcheck source=agents.sh
source "$SCRIPT_DIR/agents.sh"
LOGS_DIR="${LOGS_DIR:-$PARENT/seedkit-examples/logs}"
AGENT_CLI="${AGENT_CLI:-claude}"
case "$AGENT_CLI" in
    claude) DEFAULT_MODEL="claude-opus-5" ;;
    agy) DEFAULT_MODEL="gemini-3.5-flash" ;;
    codex) DEFAULT_MODEL="" ;;  # let the CLI apply its own default
    *) echo "AGENT_CLI must be one of: claude codex agy (got: $AGENT_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_MODEL}"
TIMEOUT_PER_LOG="${TIMEOUT_PER_LOG:-3600}"

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
command -v git     >/dev/null || { echo "git not found in PATH"; exit 1; }
cli_require "$AGENT_CLI" || exit 1

# Keep the Mac awake while we run (macOS only; no-op elsewhere). The
# `-w $$` ties caffeinate to this shell, so it exits with the script.
if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

# Resolve targets: explicit basenames as args, or all *.log files.
shopt -s nullglob
declare -a LOGS=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ -f "$arg" ]]; then
            LOGS+=("$arg")
        elif [[ -f "$LOGS_DIR/$arg" ]]; then
            LOGS+=("$LOGS_DIR/$arg")
        else
            echo "skip: '$arg' not found" >&2
        fi
    done
else
    LOGS=("$LOGS_DIR"/*.log)
fi

# Baseline logs are not testcase runs — they have no REVIEW phase and no
# skill was loaded, so "which skill defect does this show" has no answer.
# run-baseline.sh writes them to $LOGS_DIR/baselines/ (out of this
# non-recursive glob), but reject them by name too so an explicit argument
# or a stray copy can't get through.
declare -a KEPT=()
for candidate in "${LOGS[@]}"; do
    base=$(basename "$candidate")
    if [[ "$base" == baseline-* ]]; then
        echo "skip: $base is a baseline log, not a testcase run" >&2
        continue
    fi
    if [[ -f "$candidate" ]] && ! grep -q '════════ BUILD' "$candidate"; then
        echo "skip: $base has no BUILD phase — not a testcase run" >&2
        continue
    fi
    KEPT+=("$candidate")
done
# `LOGS=("${KEPT[@]}")` on an empty KEPT trips `set -u` on bash 3.2, which
# is what macOS ships.
if [[ ${#KEPT[@]} -gt 0 ]]; then LOGS=("${KEPT[@]}"); else LOGS=(); fi

if [[ ${#LOGS[@]} -eq 0 ]]; then
    echo "no logs to review under $LOGS_DIR"
    exit 0
fi

# Refuse to start if the submodule or parent has unrelated pending work
# — we'd attribute it to the wrong log otherwise.
if ! git -C "$REPO" diff-index --quiet HEAD --; then
    echo "seedkit submodule has uncommitted changes — commit or stash first" >&2
    exit 1
fi
if ! git -C "$PARENT" diff-index --quiet HEAD -- seedkit; then
    echo "parent repo has uncommitted seedkit pointer drift — bump or stash first" >&2
    exit 1
fi

# The agent receives this as a single prompt. LOGPATH and TODAY are
# substituted per iteration. The agent has full tool access — cli_dispatch
# (agents.sh) always runs $AGENT_CLI in its permission-bypass mode.
read -r -d '' PROMPT_TEMPLATE <<'EOF' || true
Review the seedkit testcase log at:

    LOGPATH

Today's version (year/ISO-week/ISO-weekday): **__TODAY__**

The log has two phases — `════════ BUILD ════════` (agent scaffolding a Django project from the seedkit skill) and `════════ REVIEW ════════` (a fresh claude -p auditing the result). Both end at `════════ DONE ════════`.

Workflow:

1. Read the log. Identify items that point at a real **skill defect** — a reference snippet that was wrong, missing, or led the agent into a footgun. Then also **inspect the generated artefact** for silent-omission pitfalls (project boots, but ships a known footgun that breaks in prod or on next deploy). Derive the case prefix `NN` from the log basename (e.g. `02-shop-20260510-173829.log` → `02`) and locate the project dir at `__WORKSPACE__/NN-*/`. From that dir, run the checklist below — each non-empty hit (or `MISSING:` line) is a skill defect:

   ```sh
   # uv inside Docker/compose/fly — must be `python manage.py`, not `uv run`
   grep -nH 'uv run' Dockerfile docker-compose.yml docker-compose.prod.yml fly.toml 2>/dev/null

   # Python version pin
   grep -H '^requires-python' pyproject.toml || echo "MISSING: requires-python in pyproject.toml"

   # Duplicate DATABASES block left behind by startproject
   grep -rn '^DATABASES = {' . --include='*.py' 2>/dev/null | awk -F: '{print $1}' | sort | uniq -c | awk '$1>1'

   # tasks.py at project root or under config/ — must live inside a registered app
   find . -maxdepth 3 -name tasks.py -not -path './.venv/*' -not -path './.git/*' \
     | grep -E '^\./tasks\.py$|/config/tasks\.py$' || true

   # .env.example trailing comments after values (django-environ reads the comment as part of the URL)
   grep -nE '^[A-Z_]+=[^#]*[[:space:]]+#' .env.example 2>/dev/null

   # Canonical DJANGO_* env vars
   for v in DJANGO_DEBUG DJANGO_SECRET_KEY DJANGO_ALLOWED_HOSTS; do
     grep -q "^$v=" .env.example 2>/dev/null || echo "MISSING: $v in .env.example"
   done

   # If deploy=vps or github-ssh, README's ## Deploy block must run migrate before `compose up -d`
   grep -A20 '^## Deploy' README.md 2>/dev/null | grep -B2 'compose up -d' | grep -q migrate \
     || echo "CHECK: README ## Deploy may be missing pre-up migrate step (skip if deploy=none/managed)"
   ```

   Skip:
   - Agent improvisations against strict testcase assertions (e.g. agent put healthchecks in `api/views.py` when the skill allows any registered app).
   - Findings already covered by an existing reference or `SKILL.md` pitfall — grep before editing.
   - Cosmetic preferences and "consider adding X" nudges.
   - Checklist items that aren't applicable to this case's configuration (no Docker artefact when deploy=none; no `## Deploy` block when deploy=none/managed).
2. For each real defect, make the smallest edit to the matching `skills/django-seedkit/SKILL.md`, `skills/django-seedkit/references/*.md`, or `testcases/*.md`. Follow `seedkit/CLAUDE.md`:
   - Show the correct sample. Drop redundant "don't" prose if the positive sample covers it.
   - No significance inflation, no fake -ing analysis, no podium voice.
   - Cross-reference, don't duplicate.
3. If nothing real surfaces, that's a valid outcome — say "no skill change", skip to step 7.
4. Bump the version to **__TODAY__** in both files (only if you made an edit in step 2):
   - `__REPO__/.claude-plugin/plugin.json` → set `"version": "__TODAY__"`.
   - `__REPO__/skills/django-seedkit/SKILL.md` frontmatter → set `version: __TODAY__`.
5. Update `__REPO__/CHANGELOG.md`: if a `## __TODAY__ — ` section already exists, extend the matching Keep-a-Changelog bullet (`### Added` / `### Changed` / `### Fixed` / `### Removed`) in place; otherwise insert a new section at the top under the `# Changelog` heading. One short, high-level, user-facing bullet per theme — never one bullet per edit. If CHANGELOG.md exceeds 200 lines after the edit, trim the oldest sections at the bottom to bring it near 150 lines.
6. Inside `__REPO__/`: `git add -A`, commit, and `git push origin main`. Use the host gitconfig — never pass `--author` or `-c user.email`.
7. Inside `__PARENT__/`: `git add seedkit`, commit `chore: bump seedkit/ — <one-line reason>`, push. Skip steps 6–7 if no edits were made.
8. `rm` the log file at LOGPATH (it's gitignored — plain `rm`, not `git rm`).
9. Final line: `[<log basename>] <one sentence outcome>`.

Hard constraints:
- Don't run `./run-tests.sh` or otherwise spawn a build.
- Don't invoke any skill.
- Don't commit unrelated files. If `git status` shows drift you didn't introduce, stop and report.
- Keep every edit short.
EOF
TODAY_VER=$(date +%y.%V.%u)
WORKSPACE_DIR="${WORKSPACE:-$PARENT/seedkit-examples}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__TODAY__/$TODAY_VER}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__REPO__/$REPO}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__PARENT__/$PARENT}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__WORKSPACE__/$WORKSPACE_DIR}"

total=${#LOGS[@]}
idx=0
declare -a RESULTS=()

for log in "${LOGS[@]}"; do
    idx=$((idx + 1))
    name=$(basename "$log")
    echo
    echo "==> ($idx/$total) $name"
    echo "    log:   $log"
    echo "    agent: $AGENT_CLI / $MODEL"

    if [[ ! -f "$log" ]]; then
        echo "    skip: file vanished"
        RESULTS+=("skip   $name")
        continue
    fi

    prompt="${PROMPT_TEMPLATE//LOGPATH/$log}"
    start=$(date +%s)

    # No CASE_LOG — output streams straight to this script's stdout so
    # the sub-agent's progress shows live; the log being reviewed is
    # $log itself, not something to append to.
    export -f cli_dispatch _cli_sink
    PROMPT="$prompt" CASE_MODEL="$MODEL" CASE_CLI="$AGENT_CLI" \
    run_watched "$TIMEOUT_PER_LOG" "$name" setsid_exec bash -c 'cli_dispatch'
    rc=$RUN_WATCHED_RC

    duration=$(( $(date +%s) - start ))
    printf '    done: exit=%s duration=%ss [%d/%d]\n' "$rc" "$duration" "$idx" "$total"
    RESULTS+=("$(printf 'exit=%-3s %5ss  %s' "$rc" "$duration" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done

echo
echo "done."
