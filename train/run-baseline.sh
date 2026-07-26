#!/usr/bin/env bash
#
# Generate the "no-skill" control arm for each testcase: a fresh agent
# CLI with no /seedkit skill reachable, given the same ## Prompt and the
# same ## Boot check as the skill arm, into seedkit-baselines/<case>/.
#
# For the comparison to mean anything the two arms must differ in ONE
# variable — whether the skill is loaded. So this script mirrors
# run-tests.sh: same prompt, same boot check, same auto-fix instruction,
# same scorecard. What it does NOT share is the testcase's `## Review`
# section, which asserts seedkit-specific structure the control arm was
# never told to produce; both arms are graded on train/scorecard.md
# instead, which is arm-neutral and emits `SCORE n/8`.
#
# Output lives OUTSIDE $WORKSPACE on purpose. run-tests.sh symlinks the
# skill into $WORKSPACE/.claude/skills/, and anything under that path
# can reach it — a control group that can see the treatment is not a
# control group. assert_skill_unreachable() below refuses to start if
# the skill is reachable from the baseline root or installed globally.
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
# Sibling of $WORKSPACE, never under it — see the header. Logs go here
# too, so review-logs.sh (which globs $WORKSPACE/logs/*.log) never picks
# up a baseline log and tries to review it as a testcase run.
BASELINE_ROOT="${BASELINE_ROOT:-$WORKSPACE/../seedkit-baselines}"
mkdir -p "$BASELINE_ROOT"
BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
LOGS="$BASELINE_ROOT/logs"
SCORECARD="$SCRIPT_DIR/scorecard.md"
BASELINE_CLI="${BASELINE_CLI:-claude}"
case "$BASELINE_CLI" in
    claude) DEFAULT_MODEL="claude-sonnet-5" ;;
    agy) DEFAULT_MODEL="gemini-3.5-flash" ;;
    codex) DEFAULT_MODEL="" ;;  # let the CLI apply its own default
    *) echo "BASELINE_CLI must be one of: claude codex agy (got: $BASELINE_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_MODEL}"
SCORECARD_MODEL="${SCORECARD_MODEL:-claude-opus-5}"
# Match run-tests.sh's per-phase ceiling — a control arm on half the
# budget produces truncated projects that read as "the unaided agent did
# worse" when the real cause was the watchdog.
TIMEOUT_PER_CASE="${TIMEOUT_PER_CASE:-7200}"
STAMP="$(date +%Y%m%d-%H%M%S)"

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
cli_require "$BASELINE_CLI" || exit 1

if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

# The control arm must not be able to reach the skill. run-tests.sh
# symlinks it into $WORKSPACE/.claude/skills/ and `agy plugin install`
# copies it into the user's global plugin dir — either would silently
# turn this into a second treatment run. Refuse to start rather than
# telling the agent "no skill is loaded" and hoping.
assert_skill_unreachable() {
    local probe=$1 found=0 d
    while :; do
        for d in "$probe/.claude/skills/seedkit" \
                 "$probe/.codex/skills/seedkit" \
                 "$probe/.gemini/skills/seedkit"; do
            [[ -e "$d" ]] && { echo "  reachable: $d" >&2; found=1; }
        done
        [[ "$probe" == "/" ]] && break
        probe="$(dirname "$probe")"
    done
    for d in "$HOME/.claude/skills/seedkit" "$HOME/.gemini/config/plugins/seedkit"; do
        [[ -e "$d" ]] && { echo "  installed: $d" >&2; found=1; }
    done
    if [[ $found -eq 1 ]]; then
        cat >&2 <<'MSG'

The seedkit skill is reachable from the baseline root. A control group that
can see the treatment measures nothing. Remove the paths listed above (the
project-scoped ones are symlinks run-tests.sh creates; the agy one comes off
with `agy plugin uninstall seedkit`), or point BASELINE_ROOT somewhere the
skill cannot be discovered from.
MSG
        exit 1
    fi
}

mkdir -p "$LOGS" "$BASELINE_ROOT"
assert_skill_unreachable "$BASELINE_ROOT"
[[ -f "$SCORECARD" ]] || { echo "scorecard not found: $SCORECARD" >&2; exit 1; }

# Per CLI — see the note in run-tests.sh. Only ever concatenate the two
# arms' files for the SAME cli.
RESULTS_TSV="$BASELINE_ROOT/results-$BASELINE_CLI.tsv"
[[ -f "$RESULTS_TSV" ]] || printf 'case\tarm\tcli\tmodel\tboot_rc\tscore\tduration_s\ttool_calls\n' > "$RESULTS_TSV"

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
    boot_section=$(extract_section "$tc" "Boot check")

    # Strip the leading `/seedkit` / `/seedkit-slim` invocation — with
    # no skill loaded, that line is dead text and biases the agent.
    prompt_body=$(printf '%s\n' "$prompt_section" \
        | sed -E '/^\/seedkit(-slim)?$/d')

    # The boot check is written for run-tests.sh, where the agent works
    # in $WORKSPACE and creates `<project>/` beneath it — hence the
    # leading `cd <project>`. Here the case dir IS the project root, so
    # that line would fail. Drop it and say so.
    boot_body=$(printf '%s\n' "$boot_section" \
        | sed -E '/^cd [A-Za-z0-9._-]+$/d')

    # Same shape as run-tests.sh's build prompt, including the auto-fix
    # instruction. Handing only the treatment arm a fix-until-it-boots
    # loop would confound "the skill helps" with "the skill's arm got to
    # iterate", so both arms get it.
    prompt="$(
        printf 'Bootstrap a Django project per the answers below. Use whatever conventions you think are best.\n\n'
        printf 'The current working directory IS the project root — create files directly in it, do not make a subdirectory named after the project.\n\n'
        printf 'Work strictly inside the current working directory. Do not read, list, or reference any path outside it (no `ls ..`, no `Read ../...`, no `Glob ../**`). This is a fresh control-group run — sibling directories may contain unrelated projects and looking at them would bias the output.\n\n'
        printf '%s\n\n' "$prompt_body"
        if [[ -n "$boot_body" ]]; then
            printf 'After scaffolding completes, run these runtime smoke checks from the project root (the `cd <project>` line has been removed — you are already there). Auto-fix any failure (the goal is a project that boots and the smoke pipeline returns clean):\n\n'
            printf '%s\n\n' "$boot_body"
        fi
        printf 'At the end, summarise: What worked out of the box / What broke / Fixes applied.\n'
    )"

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

    # ── Scorecard — the arm-neutral rubric both arms are graded on ────
    {
        echo
        echo "════════ SCORECARD (claude / $SCORECARD_MODEL) ════════"
        echo
    } >> "$log"
    tool_calls_build=$(count_tool_calls "$log")
    pushd "$case_dir" >/dev/null
    PROMPT="$(cat "$SCORECARD")" CASE_LOG="$log" CASE_MODEL="$SCORECARD_MODEL" \
    CASE_TOOLS="Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*),Bash(find:*)" CASE_CLI="claude" \
    run_watched 1800 "$name-scorecard" setsid_exec bash -c 'cli_dispatch'
    popd >/dev/null

    duration=$(( $(date +%s) - start ))
    score=$(scorecard_value "$log"); score=${score:--}
    {
        echo
        echo "════════ DONE ════════"
        printf '[exit: %s, score: %s, duration: %ss, tool_calls: %s]\n' \
            "$rc" "$score" "$duration" "$tool_calls_build"
    } >> "$log"

    printf '%s\tbaseline\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$BASELINE_CLI" "$MODEL" "$rc" "$score" "$duration" "$tool_calls_build" \
        >> "$RESULTS_TSV"

    printf '    done: exit=%s score=%s duration=%ss tools=%s\n' \
        "$rc" "$score" "$duration" "$tool_calls_build"
    RESULTS+=("$(printf 'exit=%-3s score=%-5s %5ss  tools=%-4s %s' \
        "$rc" "$score" "$duration" "$tool_calls_build" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done
echo
echo "baselines under: $BASELINE_ROOT"
echo "results:         $RESULTS_TSV"
echo
echo "Compare the arms — same CLI only (skill rows come from run-tests.sh):"
echo "    cat $WORKSPACE/results-$BASELINE_CLI.tsv $RESULTS_TSV | sort -k1,1 -k2,2 | column -t"
