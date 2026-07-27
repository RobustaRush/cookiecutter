#!/usr/bin/env bash
#
# Shared agent-CLI plumbing for seedkit's harness scripts (run-tests.sh,
# run-baseline.sh, review-logs.sh). Source this file — it defines
# functions only, no top-level side effects.
#
# Supported CLIs: claude, codex, agy (Google Antigravity).
# Each has its own non-interactive invocation, permission-bypass flag,
# and JSON event schema; cli_dispatch() is the one place that knows
# about all three so the calling scripts don't have to.
#
# What each CLI needed, confirmed by hand against the installed binaries:
#   claude — `-p PROMPT --output-format stream-json`, events are
#            `.event.delta.type == "text_delta"` envelopes.
#   codex  — `exec --json PROMPT`, items arrive whole (not token deltas):
#            `{"type":"item.completed","item":{"type":"agent_message","text":...}}`,
#            `{"type":"item.completed","item":{"type":"command_execution",...}}`.
#   agy    — `--print PROMPT` has no JSON/streaming mode; it prints the
#            final response as plain text once the turn completes.

# Settings overlay applied to every claude invocation, for the same reason
# as CLAUDE_CODE_DISABLE_AUTO_MEMORY: operator config must not shape a
# harness run.
#
#   advisorModel — a user setting. On a machine that sets it (`opus` here),
#   the build agent can consult a stronger model on demand. That makes the
#   `model` column a lie for both arms, and in the CONTROL arm the advisor
#   supplies exactly the Django scaffolding guidance the skill does,
#   compressing the gap the baseline exists to measure.
#
# `--disallowedTools advisor` does NOT work — the advisor isn't a
# permission-system tool, and the CLI answers "deny rule matches no known
# tool". Blanking the setting is what actually removes it from the tool
# list (verified against the installed binary; `null` does not work, it
# reads as unset and falls back to the user value).
# Exported: cli_dispatch runs inside `setsid_exec bash -c 'cli_dispatch'`,
# so a plain shell var would not cross into it and claude would receive
# `--settings ""`.
export CLAUDE_HARNESS_SETTINGS='{"advisorModel":""}'

# Deny list for GENERATION phases (build + baseline), passed as CASE_DENY.
# The build agent works in $WORKSPACE, a git repo holding every previously
# generated project — `git log` / `git show` hand it earlier outputs to copy
# from, which is not what the case is meant to measure. Deny rules win over
# --dangerously-skip-permissions (checked against the installed binary).
#
# NOT applied to review-logs.sh: its prompt commits and pushes.
export GENERATION_DENY='Bash(git:*)'

# Portable setsid via Python — macOS ships no `setsid` binary. Puts the
# exec'd process in its own session/process group so a watchdog can kill
# the whole tree with `kill -- -$pgid`.
setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

# cli_require <cli> — checks the CLI binary is on PATH.
cli_require() {
    case "$1" in
        claude|codex|agy)
            command -v "$1" >/dev/null || { echo "$1 CLI not found in PATH" >&2; return 1; } ;;
        *)
            echo "unknown CLI: $1 (want: claude, codex, agy)" >&2; return 1 ;;
    esac
}

# _kill_watchdog_tree <watchdog-pid> — the watchdog subshell shares the
# script's own process group (no job control, so plain `&` gets no new
# pgid), and killing it doesn't reap its `sleep` child (SIGTERM to a
# parent never cascades to children). Kill the child(ren) by ppid first,
# `.` as pgrep's pattern since macOS pgrep requires one and matches
# every command name.
_kill_watchdog_tree() {
    local wd=$1 child
    [[ -n "$wd" ]] || return 0
    for child in $(pgrep -P "$wd" . 2>/dev/null); do
        kill -TERM "$child" 2>/dev/null || true
    done
    kill -TERM "$wd" 2>/dev/null || true
}

# Ctrl-C at the terminal only signals processes in the terminal's
# foreground process group. The cmd run_watched backgrounds is setsid'd
# into its own detached session (see setsid_exec) precisely so a stuck
# tree can be reaped later — which also means it never sees the
# terminal's SIGINT. This trap, installed for the run_watched() call's
# duration, kills that pgrp too so Ctrl-C actually tears the run down.
_run_watched_interrupt() {
    local sig=$1
    echo >&2
    if [[ -n "${RUN_WATCHED_PGID:-}" ]]; then
        echo "[interrupt] SIG$sig — killing pgrp $RUN_WATCHED_PGID" >&2
        kill -TERM -- -"$RUN_WATCHED_PGID" 2>/dev/null || true
        sleep 2
        kill -KILL -- -"$RUN_WATCHED_PGID" 2>/dev/null || true
    fi
    # The watchdog's own `(sleep ...) &` is an async job of this
    # non-interactive script, so SIGINT/SIGQUIT never reach it (bash
    # ignores those two signals for async commands started without job
    # control) — TERM it explicitly or it outlives our own exit.
    _kill_watchdog_tree "${RUN_WATCHED_WATCHDOG_PID:-}"
    exit 130
}

# run_watched <timeout_seconds> <label> <cmd...>
#
# Runs cmd in the background (cmd must already setsid itself — see
# setsid_exec above — so it's its own process group leader), applies a
# watchdog that TERMs then KILLs the group on timeout, and sweeps
# stragglers (orphaned celery/gunicorn/runserver, a stuck git push) once
# the command exits. Sets $RUN_WATCHED_RC to the command's real exit code.
run_watched() {
    local timeout=$1 label=$2; shift 2
    trap '_run_watched_interrupt INT' INT
    trap '_run_watched_interrupt TERM' TERM

    "$@" &
    local pid=$! pgid=$!
    RUN_WATCHED_PGID=$pgid

    (
        sleep "$timeout"
        if kill -0 "$pid" 2>/dev/null; then
            echo >&2
            echo "[watchdog] $label exceeded ${timeout}s — killing pgrp $pgid" >&2
            kill -TERM -- -"$pgid" 2>/dev/null || true
            sleep 5
            kill -KILL -- -"$pgid" 2>/dev/null || true
        fi
    ) &
    local watchdog=$!
    RUN_WATCHED_WATCHDOG_PID=$watchdog

    wait "$pid"
    RUN_WATCHED_RC=$?

    _kill_watchdog_tree "$watchdog"
    wait "$watchdog" 2>/dev/null || true

    kill -TERM -- -"$pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$pgid" 2>/dev/null || true

    unset RUN_WATCHED_WATCHDOG_PID RUN_WATCHED_PGID
}

# extract_section <file> <section-name>
#
# Pulls the body of a `## <name>` markdown section, stopping at the next
# `## ` heading or EOF. The heading line itself is dropped.
extract_section() {
    local file=$1 section=$2
    awk -v want="$section" '
        /^## / {
            if (in_section) exit
            sub(/^##[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            in_section = ($0 == want)
            next
        }
        in_section { print }
    ' "$file"
}

# cli_dispatch — runs one non-interactive turn on $CASE_CLI and streams
# the result to stdout (and to $CASE_LOG, if set).
#
# Must run inside a fresh `bash -c 'cli_dispatch'` spawned via
# setsid_exec, with `export -f cli_dispatch` done beforehand in the
# parent shell — that's how the function crosses into the exec'd
# process (see run-tests.sh / run-baseline.sh / review-logs.sh for the
# call site). Reads its config from env vars rather than arguments for
# that reason:
#
#   CASE_CLI    claude | codex | agy
#   CASE_MODEL  model id/name; empty means "let the CLI pick its default"
#   PROMPT      the full prompt text
#   CASE_DENY   claude-only: --disallowedTools value, applied to the
#               build/full-bypass path. Deny rules win over
#               --dangerously-skip-permissions (checked against the
#               installed binary). Opt-in per caller: run-tests.sh and
#               run-baseline.sh set GENERATION_DENY to keep the build
#               agent out of git; review-logs.sh must NOT, because its
#               own prompt commits and pushes.
#   CASE_TOOLS  claude-only: --allowedTools value. When set, claude runs
#               in the read-only reviewer mode instead of full-bypass —
#               this is the ONLY per-CLI mode switch in the harness today
#               (every other caller runs CLIs in full-bypass/build mode).
#   CASE_LOG    optional; when set, output is teed there as well as stdout.
#
# Exits with the underlying CLI's real exit code (not jq's — via
# PIPESTATUS), so callers can tell a genuine failure from a clean run.
cli_dispatch() {
    # The CLI reports session/usage limits, auth failures, and network
    # errors on stderr, which the stdout jq|tee pipeline never sees.
    # Without this the log of a limited-out run is empty and reads like a
    # build that simply did nothing. Appended directly, not teed through a
    # process substitution: run_watched kills the process group as soon as
    # the command exits, and callers read the log on the next line.
    [[ -n "${CASE_LOG:-}" ]] && exec 2>> "$CASE_LOG"

    case "$CASE_CLI" in
        claude)
            # CLAUDE_CODE_DISABLE_AUTO_MEMORY — harness runs must be
            # reproducible on any machine, not shaped by this operator's
            # persistent memory (~/.claude/projects/.../memory/).
            if [[ -n "${CASE_TOOLS:-}" ]]; then
                CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --allowedTools "$CASE_TOOLS" \
                    --settings "$CLAUDE_HARNESS_SETTINGS" \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            else
                local -a deny=()
                [[ -n "${CASE_DENY:-}" ]] && deny=(--disallowedTools "$CASE_DENY")
                CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --dangerously-skip-permissions \
                    --settings "$CLAUDE_HARNESS_SETTINGS" \
                    "${deny[@]}" \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            fi \
            | jq --unbuffered -j -r '
                if .event.delta.type? == "text_delta" then .event.delta.text
                elif .event.content_block?.type? == "tool_use" then "\n[tool:\(.event.content_block.name)]\n"
                # `stream_event` lines carry the tool NAME but not its input —
                # the arguments arrive later as input_json_deltas. The complete
                # `assistant` message repeats each tool_use with input filled
                # in, which is the only place the edited path is readable.
                # Distinct prefix so count_tool_calls (^\[tool:) is unaffected.
                elif .type? == "assistant" then
                    ([.message.content[]?
                      | select(.type == "tool_use")
                      | select(.name == "Edit" or .name == "Write" or .name == "NotebookEdit")
                      | "\n[file:\(.name)] \(.input.file_path // .input.notebook_path // "?")\n"]
                     | join(""))
                else empty end' \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        codex)
            local -a margs=()
            [[ -n "${CASE_MODEL:-}" ]] && margs=(-m "$CASE_MODEL")
            # --dangerously-bypass-approvals-and-sandbox is codex's
            # analogue of claude's --dangerously-skip-permissions.
            # `< /dev/null` — exec's stdin-append feature ("Reading
            # additional input from stdin...") otherwise waits on a
            # pipe that's already closed by the outer prompt=$(cat).
            codex exec --json --skip-git-repo-check \
                --dangerously-bypass-approvals-and-sandbox \
                "${margs[@]}" "$PROMPT" < /dev/null \
            | jq --unbuffered -j -r '
                if .type == "item.completed" and .item.type == "agent_message" then .item.text + "\n"
                elif .type == "item.completed" and .item.type == "command_execution" then "\n[tool:shell] \(.item.command)\n[result:exit \(.item.exit_code)] \(.item.aggregated_output // "")\n"
                elif .type == "item.completed" and .item.type == "file_change" then "\n[tool:file_change] \(.item.path // (.item | tostring))\n[file:file_change] \(.item.path // "?")\n"
                elif .type == "turn.failed" then "\n[error] \(.error.message // (.error | tostring))\n"
                else empty end
              ' \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        agy)
            local -a margs=()
            [[ -n "${CASE_MODEL:-}" ]] && margs=(--model "$CASE_MODEL")
            # No JSON/streaming mode in this CLI (confirmed against the
            # installed binary) — --print blocks until the turn is done,
            # then prints the final response as plain text. So no jq
            # stage: log liveness for agy runs is worse than the other
            # three CLIs until it grows one.
            agy --print --dangerously-skip-permissions "${margs[@]}" "$PROMPT" \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        *)
            echo "unknown CLI: $CASE_CLI" >&2
            exit 2
            ;;
    esac
}

# count_tool_calls <log> — how many tool invocations the agent made,
# from the `[tool:NAME]` markers cli_dispatch emits for claude and codex.
# A proxy for effort: reaching a working project in fewer tool calls is
# an outcome the arms are compared on, not just whether they got there.
# agy has no structured event stream, so this reads 0 for that CLI.
count_tool_calls() {
    # `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so a trailing
    # `|| echo 0` emits "0\n0" — the newline lands mid-row and splits the
    # TSV. Capture first, default only when the capture itself is empty
    # (file missing).
    local n
    n=$(grep -c '^\[tool:' "$1" 2>/dev/null) || true
    printf '%s' "${n:-0}"
}

# count_fixes <log> — the `FIXES n` the generation agent reports.
#
# The primary iteration metric. Every fix is a reference file that was wrong:
# a skill whose snippets are correct means the agent never had to repair its
# own output. Unlike the scorecard — which the skill passes by construction,
# so it cannot move — this has real spread and it moves when a reference
# regresses.
#
# head -1, not tail -1: generation is the FIRST phase in the log, and review
# and scorecard append to the same file below it.
count_fixes() {
    local n
    n=$(grep -oE '^FIXES [0-9]+' "$1" 2>/dev/null | head -1 | awk '{print $2}') || true
    printf '%s' "${n:--}"
}

# count_rewrites <log> — writes to a path the agent had already written
# earlier in the same run.
#
# The witness for count_fixes, which is self-reported by the agent under test
# and undercounts: agents file repairs they consider routine under "Notes"
# instead of "What broke". This one is mechanical — first touch of a path is
# authoring, every touch after it is rework.
#
# agy has no structured event stream, so this reads 0 for that CLI, the same
# way count_tool_calls does.
count_rewrites() {
    grep -oE '^\[file:[A-Za-z_]+\] .+' "$1" 2>/dev/null \
        | sed -E 's/^\[file:[A-Za-z_]+\] //' \
        | awk '{ if (seen[$0]++) n++ } END { printf "%d", n + 0 }'
}

# model_slug <model-id> — the directory name a model's baselines live under.
#
#   claude-sonnet-5 → sonnet     gemini-3.5-flash → gemini-3.5-flash
#
# Baselines are per-model (baselines/sonnet/, baselines/opus/) so a second
# model's control arm lands beside the first instead of overwriting it. An
# empty model means the CLI picks its own default and we can't name it.
model_slug() {
    local m=${1:-}
    [[ -z "$m" ]] && { printf 'default'; return; }
    m=${m#claude-}          # claude-sonnet-5 → sonnet-5
    m=$(printf '%s' "$m" | sed -E 's/-[0-9]+(\.[0-9]+)?$//')
    printf '%s' "$m"
}

# fix_report_block — the structured tail both generation prompts end with.
#
# Shared, not duplicated per script, because count_fixes reads it out of both
# arms' logs and the arms must differ in one variable only. Free-prose
# summaries don't survive parsing: agents route repairs they consider routine
# into "Notes" and report zero, and several control runs emitted no summary
# at all. Hence the fixed grammar and the explicit definition of a fix.
fix_report_block() {
    cat <<'BLOCK'
Finish your reply with this block and nothing after it:

FIXES <n>
FIX <one line: what you changed and why>    (one per fix; omit when n is 0)

A fix is any edit to a file you had already written earlier in this run, and
any departure from a snippet you were given. Count repairs you would call
routine — a wrong import, a version bump, a path correction all count.
BLOCK
}

# upsert_result <tsv> <case> <arm> <model> <row>
#
# Replaces the row for this (case, arm, model) rather than appending one.
# Re-running a case after a skill fix must UPDATE its row — appending would
# leave the stale row next to the new one and every comparison would read
# both. Model is part of the key because baselines are now per-model: without
# it an opus control run silently overwrites the sonnet one it exists to be
# compared against. Keeps the body sorted on the same three fields so the
# committed file diffs cleanly and a case's models group together.
#
# No cli_rc column: assert_phase_ok aborts the sweep on any non-zero phase
# exit, so a written row could only ever carry 0.
RESULTS_HEADER=$'case\tarm\tcli\tmodel\tscore\tbuild_s\ttool_calls\tfixes\trewrites\trun_at'
upsert_result() {
    local tsv=$1 case_name=$2 arm=$3 model=$4 row=$5 tmp body
    tmp="$(mktemp)"
    body="$(mktemp)"
    if [[ -f "$tsv" ]]; then
        awk -F'\t' -v c="$case_name" -v a="$arm" -v m="$model" \
            'NR > 1 && !($1 == c && $2 == a && $4 == m)' "$tsv" > "$body"
    fi
    printf '%s\n' "$row" >> "$body"
    { printf '%s\n' "$RESULTS_HEADER"; sort -t$'\t' -k1,1 -k2,2 -k4,4 "$body"; } > "$tmp"
    mv "$tmp" "$tsv"
    rm -f "$body"
}

# drop_stray_git_hooks <workspace>
#
# A generated project that runs `pre-commit install` writes into the WORKSPACE
# repo's .git/hooks/, not its own — the project is a subdirectory, so git
# resolves upward. The hook then runs that one project's ruff config over
# every published example on the next commit and rewrites them. Swept after
# each case, because the install happens mid-build.
drop_stray_git_hooks() {
    local hooks="$1/.git/hooks" h
    [[ -d "$hooks" ]] || return 0
    for h in "$hooks"/*; do
        [[ -f "$h" ]] || continue
        case "$h" in *.sample) continue ;; esac
        grep -q 'generated by pre-commit' "$h" 2>/dev/null || continue
        rm -f "$h" && printf '    dropped stray git hook: %s\n' "$h" >&2
    done
}

# acquire_workspace_lock <dir>
#
# One harness script per workspace. run-tests.sh finds each case's project by
# mtime, so a second script writing the same tree makes a sibling look like
# this case's output — that is how 04-media-vault's scorecard came to grade
# 02-shop. `mkdir` is the atomic test-and-set; macOS has no `flock` binary.
acquire_workspace_lock() {
    # Global, not local: the EXIT trap fires long after this function has
    # returned, so a local would be out of scope and the lock would leak.
    HARNESS_LOCK="$1/.harness-lock"
    if ! mkdir "$HARNESS_LOCK" 2>/dev/null; then
        printf '\n  Workspace is locked by another harness run: %s\n' "$HARNESS_LOCK" >&2
        printf '  Wait for it to finish, or remove the directory if it is stale.\n\n' >&2
        exit 4
    fi
    printf '%s\n' "$$" > "$HARNESS_LOCK/pid"
    trap 'rm -rf "$HARNESS_LOCK"' EXIT
}

# assert_agent_ran <log> <label>
#
# A generation phase always makes tool calls — it writes files. Zero
# markers means the CLI never got a turn: a session/usage limit, an auth
# failure, a network error. That is an infrastructure failure, not a build
# result, and every remaining case will hit the same wall within seconds.
# Abort the sweep instead of recording it, so a limit hit at case 03 can't
# fill the results table with six rows of nothing that read as failed
# builds.
assert_agent_ran() {
    local log=$1 label=$2
    [[ $(count_tool_calls "$log") -gt 0 ]] && return 0
    {
        echo
        echo "════════ ABORTED ════════"
        echo "$label made no tool calls — the agent never ran."
        echo "No result row written; remaining cases skipped."
    } >> "$log"
    printf '\n  ABORTED: %s made no tool calls — the agent never ran.\n' "$label" >&2
    printf '  Usually a session/usage limit. The CLI said:\n\n' >&2
    tail -n 15 "$log" | sed 's/^/    /' >&2
    printf '\n  No result row written. Re-run this case once the limit resets.\n\n' >&2
    exit 3
}

# assert_phase_ok <rc> <log> <label>
#
# The companion to assert_agent_ran, for the cutoff it can't see: an agent
# that worked for 200 tool calls and then lost its connection. `claude -p`
# exits 0 whenever the agent completes its turn, whatever it concluded about
# the project — a project that won't boot still exits 0 and shows up in the
# score. So a non-zero exit is the CLI failing, never a build result, and
# recording one is recording an API outage as an experimental outcome.
assert_phase_ok() {
    local rc=$1 log=$2 label=$3
    [[ $rc -eq 0 ]] && return 0
    {
        echo
        echo "════════ ABORTED ════════"
        echo "$label exited $rc — the CLI failed, so this is not a build result."
        echo "No result row written; remaining cases skipped."
    } >> "$log"
    printf '\n  ABORTED: %s exited %s.\n' "$label" "$rc" >&2
    printf '  The CLI failed mid-phase (usually a session/usage limit). It said:\n\n' >&2
    tail -n 15 "$log" | sed 's/^/    /' >&2
    printf '\n  No result row written. Re-run this case once the limit resets.\n\n' >&2
    exit 3
}

# scorecard_value <log> — the `SCORE n/8` the scorecard phase emitted,
# or `-` when the phase didn't run or the agent didn't follow the format.
scorecard_value() {
    grep -oE '^SCORE [0-9]+/[0-9]+' "$1" 2>/dev/null | tail -1 | awk '{print $2}' || true
}

_cli_sink() {
    if [[ -n "${CASE_LOG:-}" ]]; then
        tee -a "$CASE_LOG"
    else
        cat
    fi
}
