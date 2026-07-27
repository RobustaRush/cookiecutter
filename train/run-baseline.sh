#!/usr/bin/env bash
#
# Generate the "no-skill" control arm for each testcase: a fresh agent
# CLI with no /seedkit skill reachable, given the same ## Prompt and the
# same ## Boot check as the skill arm, into
# seedkit-examples/baselines/<model>/.
#
# For the comparison to mean anything the two arms must differ in ONE
# variable — whether the skill is loaded. So this script mirrors
# run-tests.sh: same prompt, same boot check, same auto-fix instruction,
# same scorecard. What it does NOT share is the testcase's `## Review`
# section, which asserts seedkit-specific structure the control arm was
# never told to produce; both arms are graded on train/scorecard.md
# instead, which is arm-neutral and emits `SCORE n/8`.
#
# Output lands in $WORKSPACE/baselines/<model>/ so the control arm
# publishes with the skill arm, one subtree per model — sonnet, opus, and
# fable controls sit side by side instead of overwriting each other, and
# the results TSV keys rows on the model for the same reason. That path
# sits under the .claude/skills/seedkit symlink
# run-tests.sh creates, and a control group that can see the treatment is
# not a control group — so unlink_skill() removes the project-scoped
# symlinks for the duration of the run and assert_skill_unreachable()
# refuses to start if anything is still reachable. run-tests.sh recreates
# the symlink on its next invocation, so the removal costs nothing. Don't
# run the two scripts concurrently.
#
# Manual invocation — run once, refresh by hand when the testcases
# change or the model changes. Run from inside seedkit/train/.
#
#   ./run-baseline.sh                       # all testcases → baselines/sonnet/
#   ./run-baseline.sh 02 07                 # specific ones (matched by NN prefix)
#   MODEL=claude-opus-5 ./run-baseline.sh   # → baselines/opus/
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
# Inside the examples repo so the control arm and its scorecards publish
# alongside the skill arm. Safe only because unlink_skill() below removes
# the skill symlink for the run — see the header.
# Set after MODEL resolves — the root is per-model (baselines/sonnet/,
# baselines/opus/) so a second model's control arm lands beside the first
# instead of overwriting it.
BASELINE_ROOT="${BASELINE_ROOT:-}"
# Under $WORKSPACE/logs/, which the examples repo gitignores wholesale and
# which review-logs.sh globs NON-recursively — so baseline logs are both
# unpublished and invisible to the log reviewer.
LOGS="$WORKSPACE/logs/baselines"
SCORECARD="$SCRIPT_DIR/scorecard.md"
BASELINE_CLI="${BASELINE_CLI:-claude}"
case "$BASELINE_CLI" in
    claude) DEFAULT_MODEL="claude-sonnet-5" ;;
    agy) DEFAULT_MODEL="gemini-3.5-flash" ;;
    codex) DEFAULT_MODEL="" ;;  # let the CLI apply its own default
    *) echo "BASELINE_CLI must be one of: claude codex agy (got: $BASELINE_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_MODEL}"
BASELINE_ROOT="${BASELINE_ROOT:-$WORKSPACE/baselines/$(model_slug "$MODEL")}"
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
# symlinks it into $WORKSPACE/.claude/skills/ (and .codex/skills/ when it
# built with codex). Remove those so the control arm can't discover it;
# run-tests.sh recreates them unconditionally at the top of its next run,
# so nothing is lost.
unlink_skill() {
    local d
    for d in "$WORKSPACE/.claude/skills/seedkit" \
             "$WORKSPACE/.codex/skills/seedkit" \
             "$WORKSPACE/.gemini/skills/seedkit"; do
        if [[ -L "$d" ]]; then
            rm -f "$d" && echo "unlinked skill: $d"
        elif [[ -e "$d" ]]; then
            # A real directory here is not ours to delete — the operator
            # put it there and run-tests.sh only ever creates symlinks.
            echo "refusing to remove non-symlink: $d" >&2
            exit 1
        fi
    done
}

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

The seedkit skill is still reachable from the baseline root. A control group
that can see the treatment measures nothing. unlink_skill() removes the
project-scoped symlinks automatically, so anything left is either a real
directory someone placed by hand or a global install — the agy one comes off
with `agy plugin uninstall seedkit`.
MSG
        exit 1
    fi
}

acquire_workspace_lock "$WORKSPACE"
mkdir -p "$LOGS" "$BASELINE_ROOT"
unlink_skill
assert_skill_unreachable "$BASELINE_ROOT"
[[ -f "$SCORECARD" ]] || { echo "scorecard not found: $SCORECARD" >&2; exit 1; }

# Both arms share one file per CLI — the `arm` column separates them, so
# a comparison is one `column -t` away. Split per CLI because comparing a
# claude skill run against a codex baseline measures the CLI, not the skill.
# Overridable for a variance pass — see the note in run-tests.sh.
RESULTS_TSV="${RESULTS_TSV:-$WORKSPACE/results-$BASELINE_CLI.tsv}"

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
        printf 'At the end, summarise: What worked out of the box / What broke / Fixes applied.\n\n'
        fix_report_block
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
    CASE_DENY="$GENERATION_DENY" \
    run_watched "$TIMEOUT_PER_CASE" "$name" setsid_exec bash -c 'cli_dispatch'
    rc=$RUN_WATCHED_RC

    popd >/dev/null

    build_duration=$(( $(date +%s) - start ))
    tool_calls_build=$(count_tool_calls "$log")
    fixes_build=$(count_fixes "$log")
    rewrites_build=$(count_rewrites "$log")
    drop_stray_git_hooks "$WORKSPACE"
    assert_agent_ran "$log" "baseline $name"
    assert_phase_ok "$rc" "$log" "baseline $name"

    # ── Scorecard — the arm-neutral rubric both arms are graded on ────
    {
        echo
        echo "════════ SCORECARD (claude / $SCORECARD_MODEL) ════════"
        echo
    } >> "$log"
    pushd "$case_dir" >/dev/null
    PROMPT="$(cat "$SCORECARD")" CASE_LOG="$log" CASE_MODEL="$SCORECARD_MODEL" \
    CASE_TOOLS="Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*),Bash(find:*)" CASE_CLI="claude" \
    run_watched 1800 "$name-scorecard" setsid_exec bash -c 'cli_dispatch'
    popd >/dev/null
    assert_phase_ok "$RUN_WATCHED_RC" "$log" "scorecard $name"

    duration=$(( $(date +%s) - start ))
    score=$(scorecard_value "$log"); score=${score:--}
    {
        echo
        echo "════════ DONE ════════"
        printf '[exit: %s, score: %s, build: %ss, total: %ss, tool_calls: %s, fixes: %s, rewrites: %s]\n' \
            "$rc" "$score" "$build_duration" "$duration" \
            "$tool_calls_build" "$fixes_build" "$rewrites_build"
    } >> "$log"

    upsert_result "$RESULTS_TSV" "$name" baseline "$MODEL" "$(printf '%s\tbaseline\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$name" "$BASELINE_CLI" "$MODEL" "$score" "$build_duration" "$tool_calls_build" \
        "$fixes_build" "$rewrites_build" "$(date -u +%Y-%m-%dT%H:%MZ)")"

    printf '    done: score=%s build=%ss tools=%s fixes=%s rewrites=%s\n' \
        "$score" "$build_duration" "$tool_calls_build" "$fixes_build" "$rewrites_build"
    RESULTS+=("$(printf 'score=%-5s build=%-6s tools=%-4s fixes=%-4s rewrites=%-4s %s' \
        "$score" "${build_duration}s" "$tool_calls_build" "$fixes_build" "$rewrites_build" "$name")")
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
echo "Compare the arms (skill rows come from run-tests.sh, same file):"
echo "    column -t < $RESULTS_TSV"
