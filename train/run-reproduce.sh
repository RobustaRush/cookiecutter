#!/usr/bin/env bash
#
# Reproduce phase — can a fresh agent get a published project running from
# its README alone?
#
# Every other grader reads files. train/scorecard.md decides all eight of its
# checks by reading, and the testcase `## Review` section is read-only by
# construction. Structure is the one thing the skill is reliably good at, so
# both graders sit at their maximum and stop moving. This one asks the
# question neither can: does the artefact work for somebody who wasn't there
# when it was built.
#
# It is NOT a boot test. The build agent already boots the project and
# auto-fixes until it does, so "does it boot" passes by construction. What is
# untested is whether it boots for a second party following only what got
# written down — which is where this week's defects lived: host ports remapped
# for the build machine, an env var the settings read that .env.example never
# lists, a step performed but never documented.
#
# Arm-neutral. The baseline arm has a README too, and the control was asked
# for one by the same `## Prompt`.
#
# The tree under test comes from `git archive HEAD` — exactly what a user gets
# by cloning, with .venv, .env and the database left behind. That is the whole
# point, so the script refuses to run against a project with uncommitted
# changes rather than grade something nobody can download.
#
# Usage (run from inside seedkit/train/):
#   ./run-reproduce.sh                       # every case, skill arm
#   ./run-reproduce.sh 02 07                 # specific ones
#   ARM=baseline ./run-reproduce.sh          # control arm, baselines/sonnet/
#   ARM=baseline MODEL=claude-opus-5 ./run-reproduce.sh
#
# Requires: claude CLI, jq, python3, git, and whatever the projects need
# (uv, docker) — a missing project dependency is reported as BLOCKED, not
# FAIL, since it says nothing about the generated project.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=agents.sh
source "$SCRIPT_DIR/agents.sh"
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
LOGS="$WORKSPACE/logs/reproduce"
ARM="${ARM:-skill}"
REPRODUCE_CLI="${REPRODUCE_CLI:-claude}"
MODEL="${MODEL:-claude-opus-5}"
# Long: a reproduce run installs dependencies, pulls images, and boots
# services. Most of that is network and disk, not agent turns.
TIMEOUT_PER_CASE="${TIMEOUT_PER_CASE:-3600}"
STAMP="$(date +%Y%m%d-%H%M%S)"

case "$ARM" in
    skill)    PROJECT_ROOT="$WORKSPACE" ;;
    baseline) PROJECT_ROOT="$WORKSPACE/baselines/$(model_slug "$MODEL")" ;;
    *) echo "ARM must be skill or baseline (got: $ARM)" >&2; exit 1 ;;
esac

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
command -v git     >/dev/null || { echo "git not found in PATH"; exit 1; }
cli_require "$REPRODUCE_CLI" || exit 1

[[ -d "$PROJECT_ROOT" ]] || { echo "no projects under $PROJECT_ROOT" >&2; exit 1; }

if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

# Reads the workspace and writes logs into it — same exclusion as the other
# two scripts, and a concurrent sweep would be rewriting the very trees this
# one is archiving.
acquire_workspace_lock "$WORKSPACE"
mkdir -p "$LOGS"

# Its own file. The build TSV's columns describe a generation run — score,
# build_s, fixes — and none of them mean anything for a phase that generates
# nothing. `upsert_result` keys on fields 1, 2 and 4, so case/arm/cli/model
# stay in those positions and it works unchanged.
RESULTS_TSV="${RESULTS_TSV:-$WORKSPACE/reproduce-$REPRODUCE_CLI.tsv}"
RESULTS_HEADER=$'case\tarm\tcli\tmodel\tverdict\tgaps\tduration_s\ttool_calls\trun_at'

# Resolve which projects to run: `NN` prefixes, or everything.
shopt -s nullglob
declare -a PROJECTS=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        matches=("$PROJECT_ROOT/$arg"-*/)
        if [[ ${#matches[@]} -eq 1 ]]; then
            PROJECTS+=("${matches[0]%/}")
        else
            echo "skip: '$arg' did not match a single project under $PROJECT_ROOT" >&2
        fi
    done
else
    for d in "$PROJECT_ROOT"/[0-9][0-9]-*/; do PROJECTS+=("${d%/}"); done
fi

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
    echo "no projects to reproduce under $PROJECT_ROOT" >&2
    exit 1
fi

# verdict <log> — the agent's REPRODUCE line. `-` when it never emitted one,
# which is a phase that died rather than a project that failed.
verdict() {
    grep -oE '^REPRODUCE (PASS|FAIL|BLOCKED)' "$1" 2>/dev/null \
        | tail -1 | awk '{print $2}' || true
}

# count_gaps <log> — GAP lines, each one a thing the agent had to work out
# that the README should have said.
count_gaps() {
    grep -cE '^GAP ' "$1" 2>/dev/null || true
}

read -r -d '' PROMPT_TEMPLATE <<'EOF' || true
You have just cloned this repository. The current working directory is its
root. You have never seen it before and you know nothing about it beyond what
is written down here.

Your job: get it running locally, following its own documentation.

Rules:

- `README.md` is your instructions. Read it first and follow it literally.
- You may read any file in this directory to diagnose a problem, but the
  README is what you are testing. Every time you have to work something out
  that the README did not tell you, that is a finding — record it.
- Do not edit any file in the project to make it work. This is an audit of
  what was published, not a repair job. The one exception is a value you are
  clearly expected to supply yourself (copying `.env.example` to `.env` and
  filling it in, for instance) — that is normal setup, not a fix.
- If a host port is already taken by an unrelated service on this machine,
  that is this machine's problem, not the project's. Work around it and record
  it as a NOTE, not a GAP.
- Stop as soon as the project is demonstrably running: the documented run
  command works and the documented entry point answers. Do not go on to
  exercise features.

When you are done, finish your reply with this block and nothing after it:

REPRODUCE PASS|FAIL|BLOCKED
GAP <one line: what you had to work out that the README should have said>
NOTE <one line: machine-local workarounds — taken ports, missing daemons>

Use PASS when it ended up running. Use FAIL when it did not, and make the
first GAP line the reason. Use BLOCKED only when this machine cannot run it at
all through no fault of the project — no Docker daemon for a project that
needs one, say — and name what was missing on the NOTE line.

A GAP is not a style complaint. It is something a competent person following
the README would get stuck on or get wrong.
EOF

total=${#PROJECTS[@]}
idx=0
declare -a RESULTS=()

for project in "${PROJECTS[@]}"; do
    idx=$((idx + 1))
    name=$(basename "$project")
    rel="${project#$WORKSPACE/}"
    log="$LOGS/reproduce-$ARM-$name-$STAMP.log"

    echo
    echo "==> ($idx/$total) $name [$ARM]"
    echo "    from:  $rel"
    echo "    log:   $log"

    # Grade what is published, not what is on disk. An uncommitted tree cannot
    # be cloned by anybody, so archiving it would test something nobody can get.
    if [[ -n "$(git -C "$WORKSPACE" status --porcelain -- "$rel" 2>/dev/null)" ]]; then
        echo "    skip: uncommitted changes under $rel — commit first" >&2
        RESULTS+=("$(printf '%-8s %s' "skip" "$name")")
        continue
    fi

    scratch="$(mktemp -d "${TMPDIR:-/tmp}/reproduce-$name-XXXXXX")"
    if ! git -C "$WORKSPACE" archive HEAD -- "$rel" | tar -x -C "$scratch" --strip-components=1 2>/dev/null; then
        echo "    skip: nothing committed at $rel" >&2
        rm -rf "$scratch"
        RESULTS+=("$(printf '%-8s %s' "skip" "$name")")
        continue
    fi

    {
        echo "════════ REPRODUCE ($REPRODUCE_CLI / $MODEL) ════════"
        echo "arm:      $ARM"
        echo "source:   $rel @ $(git -C "$WORKSPACE" rev-parse --short HEAD)"
        echo "scratch:  $scratch"
        echo
    } >> "$log"

    start=$(date +%s)
    pushd "$scratch" >/dev/null

    export -f cli_dispatch _cli_sink
    PROMPT="$PROMPT_TEMPLATE" CASE_LOG="$log" CASE_MODEL="$MODEL" CASE_CLI="$REPRODUCE_CLI" \
    run_watched "$TIMEOUT_PER_CASE" "reproduce-$name" setsid_exec bash -c 'cli_dispatch'
    rc=$RUN_WATCHED_RC

    popd >/dev/null
    duration=$(( $(date +%s) - start ))

    # Harness-side teardown, as in run-tests.sh: the agent may have left
    # containers and servers behind, and `docker compose down` has to happen
    # while the compose file still exists.
    if [[ -f "$scratch/docker-compose.yml" ]] && command -v docker >/dev/null; then
        (cd "$scratch" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
    fi
    rm -rf "$scratch"

    tool_calls=$(count_tool_calls "$log")
    assert_agent_ran "$log" "reproduce $name"
    assert_phase_ok "$rc" "$log" "reproduce $name"

    v=$(verdict "$log"); v=${v:--}
    gaps=$(count_gaps "$log")

    {
        echo
        echo "════════ DONE ════════"
        printf '[verdict: %s, gaps: %s, duration: %ss, tool_calls: %s]\n' \
            "$v" "$gaps" "$duration" "$tool_calls"
    } >> "$log"

    upsert_result "$RESULTS_TSV" "$name" "$ARM" "$MODEL" \
        "$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
            "$name" "$ARM" "$REPRODUCE_CLI" "$MODEL" "$v" "$gaps" \
            "$duration" "$tool_calls" "$(date -u +%Y-%m-%dT%H:%MZ)")"

    printf '    done: verdict=%s gaps=%s duration=%ss tools=%s\n' \
        "$v" "$gaps" "$duration" "$tool_calls"
    RESULTS+=("$(printf '%-8s gaps=%-4s %6ss  %s' "$v" "$gaps" "$duration" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done
echo
echo "results: $RESULTS_TSV"
echo "    column -t < $RESULTS_TSV"
