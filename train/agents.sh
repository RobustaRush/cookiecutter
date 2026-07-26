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
#   CASE_TOOLS  claude-only: --allowedTools value. When set, claude runs
#               in the read-only reviewer mode instead of full-bypass —
#               this is the ONLY per-CLI mode switch in the harness today
#               (every other caller runs CLIs in full-bypass/build mode).
#   CASE_LOG    optional; when set, output is teed there as well as stdout.
#
# Exits with the underlying CLI's real exit code (not jq's — via
# PIPESTATUS), so callers can tell a genuine failure from a clean run.
cli_dispatch() {
    case "$CASE_CLI" in
        claude)
            # CLAUDE_CODE_DISABLE_AUTO_MEMORY — harness runs must be
            # reproducible on any machine, not shaped by this operator's
            # persistent memory (~/.claude/projects/.../memory/).
            if [[ -n "${CASE_TOOLS:-}" ]]; then
                CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --allowedTools "$CASE_TOOLS" \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            else
                CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --dangerously-skip-permissions \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            fi \
            | jq --unbuffered -j -r '
                if .event.delta.type? == "text_delta" then .event.delta.text
                elif .event.content_block?.type? == "tool_use" then "\n[tool:\(.event.content_block.name)]\n"
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
                elif .type == "item.completed" and .item.type == "file_change" then "\n[tool:file_change] \(.item.path // (.item | tostring))\n"
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
    grep -c '^\[tool:' "$1" 2>/dev/null || echo 0
}

# upsert_result <tsv> <case> <arm> <row>
#
# Replaces the row for this (case, arm) rather than appending one. Re-running
# a case after a skill fix must UPDATE its row — appending would leave the
# stale row next to the new one and every comparison would read both. Keeps
# the body sorted so the committed file diffs cleanly.
RESULTS_HEADER=$'case\tarm\tcli\tmodel\tboot_rc\tscore\tbuild_s\ttool_calls\trun_at'
upsert_result() {
    local tsv=$1 case_name=$2 arm=$3 row=$4 tmp body
    tmp="$(mktemp)"
    body="$(mktemp)"
    if [[ -f "$tsv" ]]; then
        awk -F'\t' -v c="$case_name" -v a="$arm" \
            'NR > 1 && !($1 == c && $2 == a)' "$tsv" > "$body"
    fi
    printf '%s\n' "$row" >> "$body"
    { printf '%s\n' "$RESULTS_HEADER"; sort -t$'\t' -k1,1 -k2,2 "$body"; } > "$tmp"
    mv "$tmp" "$tsv"
    rm -f "$body"
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
