# seedkit

Claude Code skill for bootstrapping Django projects + the testcase harness that exercises it.

Layout:
- `skills/seedkit/SKILL.md` + `skills/seedkit/references/*.md` — the skill itself.
- `testcases/0[1-9]-*.md` — scripted runs that exercise the skill end-to-end.
- `train/` — the testcase harness: `run-tests.sh` pipes each testcase through an agent CLI and writes per-run logs; `run-baseline.sh` generates the no-skill control arm; `review-logs.sh` auto-patches the skill from those logs; `agents.sh` is the shared multi-CLI (claude/codex/agy) dispatch the three scripts source.
- `workspace/` — gitignored scratch where generated projects live; wiped between runs.

## Writing reference files

Each reference is a paste-ready snippet plus the minimum prose needed to use it correctly.

**Show the correct sample.** Imperative, specific, copyable. The agent uses snippets verbatim (`SKILL.md` "Snippet integrity" pitfall) — anything not in the snippet won't make it into the generated project.

**Drop the matching "don't".** When a positive sample shows the right way, don't follow it with "Don't write X" / "Never use Y". The correct line is the canonical answer; the redundant warning adds tokens, invites the agent to second-guess, and ages badly. Keep negative guidance only when it stands alone — a behavior rule with no positive code sample (e.g. "Don't strip the `Host`-header check globally", "Don't log request bodies").

**One reason, not two.** If the snippet needs context, follow it with a short rationale (`# comment` inside the snippet, or one sentence after). Don't pile on alternatives, anti-patterns, or "you might also want to" tangents — every additional sentence is one the agent might cargo-cult into output.

**No prose drift.** No significance inflation ("crucial", "robust", "production-ready"), no fake -ing analysis ("…, ensuring proper handling of…"), no vague attribution ("experts recommend"), no podium voice ("clearly", "obviously"). The simple-english-writing skill enumerates the patterns; we follow it.

**Cross-reference, don't duplicate.** When a snippet belongs in another reference (e.g. `test.py` settings live in `new-project.md`, not `pytest.md`), point to it with one sentence and stop. Two copies drift.

**Good path only — no artefacts, no history.** A reference describes the path we want followed today. No "surfaced by run X", no "the agent used to do Y instead", no "previously we shipped Z". CHANGELOG is the place for that. A reader of the reference doesn't need provenance to follow the snippet.

## Changelog

`seedkit/CHANGELOG.md` tracks user-facing changes. Versions are dated `YY.WW.D` — `date +%y.%V.%u` — one section per day; all of a day's commits collapse into one block. After every skill edit, append (or extend) one short bullet under today's section using Keep-a-Changelog headings (`Added` / `Changed` / `Fixed` / `Removed`). Batch related fixes into a single bullet. Bump `version` to the same date string in both `.claude-plugin/plugin.json` and `skills/seedkit/SKILL.md` frontmatter. If `CHANGELOG.md` exceeds ~200 lines, trim the oldest sections — git keeps the rest. `train/review-logs.sh` does this inline per log iteration — version bump + changelog edit happen in the same commit as the reference fix.

## Maintaining testcases

Each testcase has the same closing block:

```
- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
```

When a testcase log surfaces a real bug the agent had to fix in-flight, that fix moves into the matching reference so the next run doesn't hit it. The agent's "Suggested skill changes" line is signal but not authoritative — verify each claim against the actual reference before patching.

The reviewer prompt at the bottom of every testcase is identical and short: report only boot-blockers / smoke-failures / security holes, quote the literal substring read, no nitpicks, "No issues found." is a valid report. Don't re-add per-case "INTENTIONAL design decisions (a)–(k)" exemption lists — the substring-quote rule and the boot-blocker filter cover it.

## train/run-tests.sh contract

Each case runs in its own session (portable `setsid_exec` Python shim, `train/agents.sh`) so the post-case sweep `kill -- -$pgid` reaches every descendant — orphaned celery workers, gunicorn, `runserver` autoreloader. A watchdog terminates the group if a phase overruns — `TIMEOUT_PER_PHASE` in `run-tests.sh`, `TIMEOUT_PER_CASE` in `run-baseline.sh`, both 7200. Cleanup is harness-side; the skill and testcase prompts must not invoke `pkill -f` (it matches the parent agent-CLI process).

Generated projects land in `../seedkit-examples/` (the sibling submodule). Per-run logs land in `../seedkit-examples/logs/` (gitignored inside that repo). The harness prepends each testcase's `## Prompt` block to the generated project's `README.md` and writes a top-level `seedkit-examples/README.md` index after every run.

## Baseline contract

`run-baseline.sh` is the control arm: same `## Prompt`, same `## Boot check`, same auto-fix instruction, no skill. The two arms must differ in one variable only, so anything given to one is given to both.

- Output goes to `seedkit-examples/baselines/<case>/`, so the control arm publishes with the skill arm. That sits under the `.claude/skills/seedkit` symlink `run-tests.sh` creates, so `unlink_skill()` removes the project-scoped symlinks before the run and `assert_skill_unreachable()` walks up from the baseline root and refuses to start if anything is still reachable (a hand-placed real directory, or a global install under `~/.claude/skills/` or `~/.gemini/config/plugins/`). `run-tests.sh` recreates the symlink at the top of its next run, so the removal costs nothing — but don't run the two scripts concurrently.
- Baseline logs go to `seedkit-examples/logs/baselines/`: inside the wholesale-gitignored `logs/`, and outside `review-logs.sh`'s non-recursive `logs/*.log` glob. `review-logs.sh` also rejects any `baseline-*.log` by name and any log with no `BUILD` phase, so an explicit argument can't get one through either.
- Both arms are graded on `train/scorecard.md` — eight arm-neutral static checks emitting `SCORE n/8`. The testcase's `## Review` section is skill-arm-only; it asserts structure the control was never asked for.
- Both arms write to one `results-<cli>.tsv` in the examples repo (`case / arm / cli / model / boot_rc / score / build_s / tool_calls / run_at`); the `arm` column separates them, so comparing is `column -t < results-claude.tsv`. Split per CLI because comparing a claude skill run against a codex baseline measures the CLI, not the skill.
- Every claude invocation carries `--settings '{"advisorModel":""}'` (`CLAUDE_HARNESS_SETTINGS` in `agents.sh`), for the same reason as `CLAUDE_CODE_DISABLE_AUTO_MEMORY`: operator config must not shape a harness run. `advisorModel` is a user setting, so on a machine that sets it the build agent can consult a stronger model on demand — making the `model` column a lie for both arms, and in the control arm supplying exactly the scaffolding guidance the skill does. `--disallowedTools advisor` does not work; the advisor is not a permission-system tool.
- `build_s` and `tool_calls` are **build-phase only**, captured before review and scorecard run. Only the skill arm has a `## Review` phase, so a wall-clock total would charge it for verification the control never performs and make the skill read as slower. `tool_calls` counts `[tool:…]` markers in the log — reaching a working project in fewer loops is an outcome the skill gets credit for, not just reaching it. Any metric added later goes in the same place, for the same reason.
- `upsert_result()` (`agents.sh`) **replaces** the row for a `(case, arm)` pair. Re-running a case after a skill fix updates its row in place — appending would leave the stale result beside the new one and every comparison would read both. The file stays sorted by case so the committed diff is legible.

## Submodule workflow

`seedkit/` is a submodule of `RobustaRush/Robusta`. So is `seedkit-examples/` — they're siblings, neither nested in the other (so cloning `seedkit` alone doesn't drag the examples).

After committing inside `seedkit/`, bump the parent pointer:

```sh
# inside seedkit/
git push origin main
# in parent
git -C .. add seedkit && git -C .. commit -m "chore: bump seedkit/ — <reason>" && git -C .. push origin main
```

Refresh the examples after a clean run:

```sh
cd seedkit-examples
git add -A && git commit -m "refresh: $(date -u +%Y-%m-%d) run" && git push
cd ..
git add seedkit-examples && git commit -m "chore: bump seedkit-examples/" && git push
```
