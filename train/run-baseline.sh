#!/usr/bin/env bash
#
# Generate the "no-skill" baseline for each testcase: a fresh agent CLI
# with no /seedkit skill loaded, given just the ## Prompt section, into
# seedkit-examples/baselines/<case>/. No boot smoke, no deploy smoke,
# no review — just the raw output of an unaided AI.
#
# The baselines are the control group: comparing them against the
# skill-generated projects under seedkit-examples/NN-*/ shows what the
# skill adds.
#
# Manual invocation — run once, refresh by hand when the testcases
# change or the model changes. Run from inside seedkit/train/.
#
#   ./run-baseline.sh                       # all testcases (claude)
#   ./run-baseline.sh 02 07                 # specific ones (matched by NN prefix)
#   MODEL=claude-opus-5 ./run-baseline.sh
#   BASELINE_CLI=codex ./run-baseline.sh    # or agy
#
# Requires: jq, python3, and whichever CLI $BASELINE_CLI names.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTCASES="$REPO/testcases"
# shellcheck source=agents.sh
source "$SCRIPT_DIR/agents.sh"
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
BASELINE_ROOT="$WORKSPACE/baselines"
LOGS="$WORKSPACE/logs"
BASELINE_CLI="${BASELINE_CLI:-claude}"
case "$BASELINE_CLI" in
    claude) DEFAULT_MODEL="claude-sonnet-5" ;;
    agy) DEFAULT_MODEL="gemini-3.5-flash" ;;
    codex) DEFAULT_MODEL="" ;;  # let the CLI apply its own default
    *) echo "BASELINE_CLI must be one of: claude codex agy (got: $BASELINE_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_MODEL}"
TIMEOUT_PER_CASE="${TIMEOUT_PER_CASE:-3600}"
STAMP="$(date +%Y%m%d-%H%M%S)"

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
cli_require "$BASELINE_CLI" || exit 1

if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

mkdir -p "$LOGS" "$BASELINE_ROOT"

# Resolve the testcase files to run.
shopt -s nullglob
declare -a FILES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ -f "$arg" ]]; then
            FILES+=("$arg")
        elif [[ -f "$TESTCASES/$arg" ]]; then
            FILES+=("$TESTCASES/$arg")
        elif [[ -f "$TESTCASES/$arg.md" ]]; then
            FILES+=("$TESTCASES/$arg.md")
        else
            matches=("$TESTCASES/$arg"-*.md)
            if [[ ${#matches[@]} -eq 1 ]]; then
                FILES+=("${matches[0]}")
            else
                echo "skip: '$arg' did not match a single testcase" >&2
            fi
        fi
    done
else
    FILES=("$TESTCASES"/[0-9][0-9]-*.md)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "no testcases to run" >&2
    exit 1
fi

declare -a RESULTS=()

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    prefix="${name%%-*}-"   # `02-shop` → `02-`

    # Pick the case dir name from the matching skill output if it
    # exists, so baseline and skill outputs share folder names. Falls
    # back to the testcase basename otherwise.
    case_dir_name="$name"
    for match in "$WORKSPACE/$prefix"*/; do
        [[ -d "$match" ]] || continue
        match_name="$(basename "$match")"
        [[ "$match_name" == "baselines" ]] && continue
        case_dir_name="$match_name"
        break
    done

    case_dir="$BASELINE_ROOT/$case_dir_name"
    log="$LOGS/baseline-$name-$STAMP.log"

    echo
    echo "==> $name"
    echo "    out:   $case_dir"
    echo "    log:   $log"

    rm -rf "$case_dir"
    mkdir -p "$case_dir"
    : > "$log"

    prompt_section=$(extract_section "$tc" "Prompt")

    # Strip the leading `/seedkit` / `/seedkit-slim` invocation — with
    # no skill loaded, that line is dead text and biases the agent.
    prompt_body=$(printf '%s\n' "$prompt_section" \
        | sed -E '/^\/seedkit(-slim)?$/d')

    prompt="Bootstrap a Django project per the answers below. Use whatever conventions you think are best — there is no skill loaded.

Work strictly inside the current working directory. Do not read, list, or reference any path outside it (no \`ls ..\`, no \`Read ../...\`, no \`Glob ../**\`). This is a fresh control-group run — sibling directories may contain unrelated projects and looking at them would bias the output.

$prompt_body"

    {
        echo "════════ BASELINE ($BASELINE_CLI / $MODEL) ════════"
        echo "testcase: $tc"
        echo "out:      $case_dir"
        echo
    } >> "$log"

    start=$(date +%s)

    pushd "$case_dir" >/dev/null

    export -f cli_dispatch _cli_sink
    PROMPT="$prompt" CASE_LOG="$log" CASE_MODEL="$MODEL" CASE_CLI="$BASELINE_CLI" \
    run_watched "$TIMEOUT_PER_CASE" "$name" setsid_exec bash -c 'cli_dispatch'
    rc=$RUN_WATCHED_RC

    popd >/dev/null

    duration=$(( $(date +%s) - start ))
    {
        echo
        echo "════════ DONE ════════"
        printf '[exit: %s, duration: %ss]\n' "$rc" "$duration"
    } >> "$log"

    printf '    done: exit=%s duration=%ss\n' "$rc" "$duration"
    RESULTS+=("$(printf 'exit=%-3s %5ss  %s' "$rc" "$duration" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done
echo
echo "baselines under: $BASELINE_ROOT"
