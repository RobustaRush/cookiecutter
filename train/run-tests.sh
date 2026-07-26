#!/usr/bin/env bash
#
# Run seedkit testcases in two isolated phases:
#
#   1. Build  — the agent receives `## Prompt` + `## Boot check` from the
#               testcase. It scaffolds the project and runs runtime smokes
#               (boots the server, hits an endpoint). Auto-fixes are
#               expected when a smoke fails. Build CLI is pluggable
#               (claude, codex, or agy) via $BUILD_CLI.
#   2. Review — always `claude -p`, regardless of which CLI built it.
#               Reads the generated tree against the testcase's
#               `## Review` section. Read-only tools, no skill access, no
#               awareness of how the build went. File existence and
#               content assertions live here so the build context can't
#               game them.
#
# Both phases stream into the same per-case log file. There is no separate
# summary — the per-case logs are the record.
#
# Usage (run from inside seedkit/train/):
#   ./run-tests.sh                          # run all testcases (claude build)
#   ./run-tests.sh 02 07                    # run specific ones
#   MODEL=claude-opus-5 ./run-tests.sh    # override build model
#   BUILD_CLI=codex MODEL=gpt-5.2-codex ./run-tests.sh
#   BUILD_CLI=agy ./run-tests.sh            # build with Antigravity (gemini-3.5-flash)
#
# Requires: claude CLI (always, for the review phase), jq, python3, and
# whichever CLI $BUILD_CLI names.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTCASES="$REPO/testcases"
# shellcheck source=agents.sh
source "$SCRIPT_DIR/agents.sh"
# Generated projects land in the sibling `seedkit-examples` submodule of
# the parent repo. Logs live under `seedkit-examples/logs/` (gitignored
# inside the examples repo). Override via $WORKSPACE.
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
LOGS="$WORKSPACE/logs"
BUILD_CLI="${BUILD_CLI:-claude}"
case "$BUILD_CLI" in
    claude) DEFAULT_BUILD_MODEL="claude-sonnet-5" ;;
    agy) DEFAULT_BUILD_MODEL="gemini-3.5-flash" ;;
    codex) DEFAULT_BUILD_MODEL="" ;;  # let the CLI apply its own default
    *) echo "BUILD_CLI must be one of: claude codex agy (got: $BUILD_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_BUILD_MODEL}"
REVIEW_MODEL="${REVIEW_MODEL:-claude-opus-5}"
SCORECARD_MODEL="${SCORECARD_MODEL:-claude-opus-5}"
SCORECARD="$SCRIPT_DIR/scorecard.md"
# Hard ceiling per phase. The build phase occasionally improvises a bash
# command that orphans a forking child tree under PID 1; bash's `wait`
# then blocks forever. setsid + watchdog + post-phase pgrp sweep below
# clean that up.
TIMEOUT_PER_PHASE="${TIMEOUT_PER_PHASE:-7200}"
STAMP="$(date +%Y%m%d-%H%M%S)"

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
cli_require claude || exit 1       # review phase always runs claude
cli_require "$BUILD_CLI" || exit 1

# Keep the Mac awake while we run (macOS only; no-op elsewhere). The
# `-w $$` ties caffeinate to this shell, so it exits with the script.
if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

mkdir -p "$LOGS"
[[ -f "$SCORECARD" ]] || { echo "scorecard not found: $SCORECARD" >&2; exit 1; }

# One row per (case, arm), shared with run-baseline.sh — the `arm` column
# separates them, so comparing is one `column -t`. `score` is
# train/scorecard.md's arm-neutral rubric; `tool_calls` is the effort proxy
# — reaching a working project in fewer tool calls is an outcome, not just
# reaching it at all. Split per CLI: comparing a claude skill run against a
# codex baseline measures the CLI, not the skill.
#
# upsert_result() REPLACES the row for this (case, arm). Re-running a case
# after a skill fix must update its row, not append a second one next to
# the stale result. Committed to the examples repo, so it stays sorted.
RESULTS_TSV="$WORKSPACE/results-$BUILD_CLI.tsv"

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

cleanup_testcase() {
    # Remove the generated project dir(s) for a single testcase. The
    # project name set inside the testcase doesn't always match the
    # testcase filename (e.g. `01-blog.md` → `01-minimal-blog/`), so
    # match by the leading `NN-` numeric prefix shared by both. Leaves
    # siblings, logs, and examples-repo metadata untouched so a partial
    # run (`./run-tests.sh 02`) doesn't nuke unrelated outputs.
    local tc_name=$1 prefix
    [[ -n "$tc_name" ]] || return 0
    prefix="${tc_name%%-*}-"   # `02-shop` → `02-`
    shopt -s nullglob
    local match
    for match in "$WORKSPACE/$prefix"*/; do
        [[ -d "$match" ]] && rm -rf "$match"
    done
    shopt -u nullglob
}

# Extract the fenced block under "## Prompt" — the literal /seedkit
# invocation, used to prepend to the generated project's README.
extract_prompt_block() {
    awk '
        /^## Prompt[[:space:]]*$/ { in_prompt = 1; next }
        in_prompt && /^```/        { fence_count++; if (fence_count == 2) exit; next }
        in_prompt && fence_count == 1 { print }
    ' "$1"
}

prepend_prompt_to_readme() {
    local project_dir=$1 tc=$2
    local readme="$project_dir/README.md"
    [[ -d "$project_dir" ]] || return 0
    local prompt
    prompt=$(extract_prompt_block "$tc")
    [[ -n "$prompt" ]] || return 0
    local existing=""
    [[ -f "$readme" ]] && existing=$(cat "$readme")
    {
        echo "## Prompt"
        echo
        echo '```'
        echo "$prompt"
        echo '```'
        echo
        if [[ -n "$existing" ]]; then
            echo "---"
            echo
            echo "$existing"
        fi
    } > "$readme"
}

# Wires the seedkit skill into $WORKSPACE for the given CLI. Review
# always runs claude, so its symlink is set up unconditionally; the
# build CLI gets an extra branch if it's not claude.
link_skill_for() {
    local cli=$1
    case "$cli" in
        claude)
            # Project-scoped skill so claude -p in $WORKSPACE finds it.
            mkdir -p "$WORKSPACE/.claude/skills"
            ln -snf "$REPO/skills/seedkit" "$WORKSPACE/.claude/skills/seedkit"
            ;;
        codex)
            # codex auto-discovers a project-local `.codex/skills/<name>/
            # SKILL.md` the same way claude discovers `.claude/skills` —
            # confirmed by asking a codex session to list its skills with
            # this symlinked in. No CLI subcommand needed.
            mkdir -p "$WORKSPACE/.codex/skills"
            ln -snf "$REPO/skills/seedkit" "$WORKSPACE/.codex/skills/seedkit"
            ;;
        agy)
            # Antigravity has no project-scoped skill directory (a
            # symlink under .gemini/skills/ is not picked up — checked).
            # Its only hook is `agy plugin install <dir>`, which reads
            # .claude-plugin/plugin.json + skills/ at the repo root and
            # COPIES them into the real, global ~/.gemini/config/plugins/
            # <name> — so this registers the dev skill in the user's own
            # agy install rather than scoping it to $WORKSPACE. Re-run
            # every time so a skill edit is picked up on the next build.
            agy plugin install "$REPO" >/dev/null
            ;;
    esac
}

link_skill() {
    link_skill_for claude
    [[ "$BUILD_CLI" != "claude" ]] && link_skill_for "$BUILD_CLI"
}

# Run a single agent invocation in its own session, with a watchdog and
# a post-phase pgrp sweep. Streams output to $log_target, returns the
# CLI's exit code. Caller passes the prompt on stdin. The per-CLI
# invocation + JSON parsing lives in agents.sh's cli_dispatch().
run_phase() {
    local label=$1 cli=$2 model=$3 cwd=$4 log_target=$5 allowed_tools=$6
    local prompt
    prompt=$(cat)

    # Phase header in the log.
    {
        echo
        echo "════════ $label ($cli / $model) ════════"
        echo
    } >> "$log_target"

    pushd "$cwd" >/dev/null

    # Agy-specific prompt rewrites, done out here so cli_dispatch stays
    # generic across callers (review-logs.sh/run-baseline.sh never send a
    # `/seedkit` prompt, so this can't live in the shared dispatcher).
    if [[ "$cli" == "agy" ]]; then
        prompt=$(printf '%s' "$prompt" \
            | sed 's|^/seedkit$|Use the seedkit skill to scaffold the project per the questionnaire below.|')
        prompt="Shell-tool note: your run_shell_command runs each call synchronously and does not preserve & backgrounding across calls. When the smoke / deploy snippet backgrounds a process with &, run the whole snippet inside a single \"timeout 60 bash -c '...'\" invocation so it executes in one child shell and self-terminates.

$prompt"
    fi

    export -f cli_dispatch _cli_sink
    PROMPT="$prompt" CASE_LOG="$log_target" CASE_MODEL="$model" \
    CASE_TOOLS="$allowed_tools" CASE_CLI="$cli" \
    run_watched "$TIMEOUT_PER_PHASE" "$label" setsid_exec bash -c 'cli_dispatch'
    local rc=$RUN_WATCHED_RC

    popd >/dev/null
    return "$rc"
}

link_skill

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    log="$LOGS/$name-$STAMP.log"
    echo
    echo "==> $name"
    echo "    log:    $log"
    echo "    case:   $tc"

    cleanup_testcase "$name"
    : > "$log"

    # Marker so the project dir created during this case is identifiable
    # (the agent picks the dir name from its prompt; we don't know it
    # ahead of time).
    marker="$LOGS/.start-$name-$STAMP"
    touch "$marker"

    start=$(date +%s)

    # ── Phase 1: build ───────────────────────────────────────────────
    prompt_section=$(extract_section "$tc" "Prompt")
    boot_section=$(extract_section "$tc" "Boot check")
    deploy_section=$(extract_section "$tc" "Deploy check")
    {
        printf '%s\n\n' "$prompt_section"
        if [[ -n "$boot_section" ]]; then
            printf 'After scaffolding completes, run these runtime smoke checks. Auto-fix any failure (the goal is a project that boots and the smoke pipeline returns clean):\n\n'
            printf '%s\n\n' "$boot_section"
        fi
        if [[ -n "$deploy_section" ]]; then
            printf 'Then exercise the **production artifact** end-to-end. This catches what the dev-mode boot can'\''t: missing prod deps, DEBUG=False breakage, `migrate --check` drift, `collectstatic` failures, missing security headers. Auto-fix any failure:\n\n'
            printf '%s\n\n' "$deploy_section"
            printf 'Deploy-smoke rules:\n'
            printf -- '- Run gunicorn from the built prod image — never `runserver` against production settings.\n'
            printf -- '- Always tear down the smoke containers, network, and volumes at the end (even on failure) — orphaned `postgres:17` containers from a previous run will collide on the next.\n\n'
        fi
        printf 'At the end, summarise: What worked out of the box / What broke / Fixes applied / Suggested skill changes.\n'
    } | run_phase "BUILD" "$BUILD_CLI" "$MODEL" "$WORKSPACE" "$log" ""
    build_rc=$?

    # Locate the generated project: any subdir with files newer than the
    # marker, excluding the logs dir.
    project_dir=$(find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d \
        -not -name 'logs' -not -name 'baselines' -not -name '.claude' -not -name '.codex' \
        -not -name '.gemini' -not -name '.git' \
        -newer "$marker" 2>/dev/null | head -1)
    rm -f "$marker"

    # Prepend the testcase prompt to the project's README.
    if [[ -n "$project_dir" ]]; then
        prepend_prompt_to_readme "$project_dir" "$tc"
    fi

    # Effort proxy, read before the review/scorecard phases add their own
    # tool calls to the log.
    tool_calls_build=$(count_tool_calls "$log")

    # ── Phase 2: review ──────────────────────────────────────────────
    review_section=$(extract_section "$tc" "Review")
    review_rc=0
    if [[ -n "$review_section" && -n "$project_dir" ]]; then
        printf '%s\n' "$review_section" \
            | run_phase "REVIEW" "claude" "$REVIEW_MODEL" "$project_dir" "$log" \
                "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*),Bash(find:*)"
        review_rc=$?
    fi

    # ── Phase 3: scorecard — the arm-neutral rubric ──────────────────
    # Separate from the review on purpose: `## Review` asserts
    # seedkit-specific structure, which the baseline arm was never told
    # to produce. scorecard.md is what the two arms are compared on.
    if [[ -n "$project_dir" ]]; then
        cat "$SCORECARD" \
            | run_phase "SCORECARD" "claude" "$SCORECARD_MODEL" "$project_dir" "$log" \
                "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*),Bash(find:*)"
    fi

    end=$(date +%s)
    duration=$((end - start))
    score=$(scorecard_value "$log"); score=${score:--}
    {
        echo
        echo "════════ DONE ════════"
        printf '[build_exit: %s, review_exit: %s, score: %s, duration: %ss, tool_calls: %s]\n' \
            "$build_rc" "$review_rc" "$score" "$duration" "$tool_calls_build"
    } >> "$log"

    upsert_result "$RESULTS_TSV" "$name" skill "$(printf '%s\tskill\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$name" "$BUILD_CLI" "$MODEL" "$build_rc" "$score" "$duration" "$tool_calls_build" "$(date -u +%Y-%m-%dT%H:%MZ)")"
done

# Top-level README for the examples collection.
{
    echo "# seedkit-examples"
    echo
    echo "Reference Django projects scaffolded by the [seedkit](https://github.com/viewflow/seedkit) skill, paired with the prompts that produced them."
    echo
    echo "Each subdirectory is a fresh project generated end-to-end by \`claude -p\` running the matching testcase from \`seedkit/testcases/\`. The first section of every project's \`README.md\` is the verbatim \`/seedkit\` prompt — answers to every Foundation / add-on / production question — so the exact configuration is reproducible."
    echo
    echo "## Projects"
    echo
    for sub in "$WORKSPACE"/*/; do
        sub_name=$(basename "$sub")
        [[ "$sub_name" == "logs" || "$sub_name" == "baselines" ]] && continue
        [[ -f "$sub/README.md" ]] || continue
        purpose=$(awk '
            /^Purpose: / { sub(/^Purpose: */, ""); print; exit }
        ' "$sub/README.md" 2>/dev/null)
        if [[ -n "$purpose" ]]; then
            echo "- [\`$sub_name/\`]($sub_name/) — $purpose"
        else
            echo "- [\`$sub_name/\`]($sub_name/)"
        fi
    done
    echo
    echo "## Reproducing"
    echo
    echo "From the parent repo:"
    echo
    echo '```sh'
    echo "cd seedkit/train"
    echo "./run-tests.sh                  # all cases"
    echo "./run-tests.sh 02 07            # specific cases"
    echo '```'
    echo
    echo "Output lands directly here. Per-run logs (build phase + review phase) live in \`logs/\`."
} > "$WORKSPACE/README.md"

echo
echo "Logs:    $LOGS/"
echo "Index:   $WORKSPACE/README.md"
echo "Results: $RESULTS_TSV"
