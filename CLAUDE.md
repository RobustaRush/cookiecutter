# seedkit

Claude Code skill for bootstrapping Django projects + the testcase harness that exercises it.

Layout:
- `skills/django-seedkit/SKILL.md` + `skills/django-seedkit/references/*.md` — the skill itself.
- `testcases/0[1-9]-*.md` — scripted runs that exercise the skill end-to-end.
- `train/` — the testcase harness: `run-tests.sh` pipes each testcase through an agent CLI and writes per-run logs; `run-baseline.sh` generates the no-skill control arm; `review-logs.sh` auto-patches the skill from those logs; `agents.sh` is the shared multi-CLI (claude/codex/agy) dispatch the three scripts source.
- `workspace/` — gitignored scratch where generated projects live; wiped between runs.
- `site/` — the static landing page and blog, rsynced to django-seedkit.viewflow.io by `ansible/deploy.yml`.
- `docs/` — plans and notes that aren't published: `articles-plan.md` is the blog backlog.

## Writing blog articles

`site/blog/<slug>/index.html`, one per **integration aspect** — not one per reference file. A reference
covers a whole topic and often two mutually exclusive packages; an article covers one thing the reader
wants to do. `docs/articles-plan.md` holds the backlog, the format rules, and what's deliberately
unpublished.

An article is not a reference in prose. The reference is imperative and rationale-free by design; the
article supplies exactly what the reference omits — why you'd want this, and what breaks without it.
Show the minimum snippet and link the reference on GitHub for the full wiring, so the snippet has one
canonical home.

Article prose follows the **ASD-STE100** writing rules — short active one-idea sentences, no `-ing`
verb forms, no contractions, no idiom, condition before instruction in a `.gotcha`. The limits, the
scope, and the nabokov rules STE overrides are in `docs/articles-plan.md`, "Approved English". Titles
are not all "How to"; the same file has the forms and when each applies.

Every new article needs three companions in the same commit: a row in `site/blog/index.html`, a `<url>`
in `site/sitemap.xml`, and a line in the blog smoke-test loop in `ansible/deploy.yml`. The deploy
playbook passes green on a 404 unless the URL is in that loop.

## Writing reference files

Each reference is a paste-ready snippet plus the minimum prose needed to use it correctly.

**Show the correct sample.** Imperative, specific, copyable. The agent uses snippets verbatim (`SKILL.md` "Snippet integrity" pitfall) — anything not in the snippet won't make it into the generated project.

**Drop the matching "don't".** When a positive sample shows the right way, don't follow it with "Don't write X" / "Never use Y". The correct line is the canonical answer; the redundant warning adds tokens, invites the agent to second-guess, and ages badly. Keep negative guidance only when it stands alone — a behavior rule with no positive code sample (e.g. "Don't strip the `Host`-header check globally", "Don't log request bodies").

**One reason, not two.** If the snippet needs context, follow it with a short rationale (`# comment` inside the snippet, or one sentence after). Don't pile on alternatives, anti-patterns, or "you might also want to" tangents — every additional sentence is one the agent might cargo-cult into output.

**No prose drift.** No significance inflation ("crucial", "robust", "production-ready"), no fake -ing analysis ("…, ensuring proper handling of…"), no vague attribution ("experts recommend"), no podium voice ("clearly", "obviously"). The simple-english-writing skill enumerates the patterns; we follow it.

**Cross-reference, don't duplicate.** When a snippet belongs in another reference (e.g. `test.py` settings live in `new-project.md`, not `pytest.md`), point to it with one sentence and stop. Two copies drift.

**Good path only — no artefacts, no history.** A reference describes the path we want followed today. No "surfaced by run X", no "the agent used to do Y instead", no "previously we shipped Z". CHANGELOG is the place for that. A reader of the reference doesn't need provenance to follow the snippet.

## Changelog

`seedkit/CHANGELOG.md` tracks user-facing changes. Versions are dated `YY.WW.D` — `date +%y.%V.%u` — one section per day; all of a day's commits collapse into one block. After every skill edit, append (or extend) one short bullet under today's section using Keep-a-Changelog headings (`Added` / `Changed` / `Fixed` / `Removed`). Batch related fixes into a single bullet. Bump `version` to the same date string in both `.claude-plugin/plugin.json` and `skills/django-seedkit/SKILL.md` frontmatter. If `CHANGELOG.md` exceeds ~200 lines, trim the oldest sections — git keeps the rest. `train/review-logs.sh` does this inline per log iteration — version bump + changelog edit happen in the same commit as the reference fix.

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

`cli_dispatch` appends the agent CLI's stderr to the case log — session/usage limits, auth failures, and network errors are reported there, and the stdout `jq | tee` pipeline never sees them. After the generation phase both scripts call `assert_agent_ran()`: zero `[tool:…]` markers means the CLI never got a turn, so the harness writes no result row and aborts the sweep with exit 3. A generation phase that reaches a project always calls tools, and whatever stopped one case stops every later one within seconds — recording those would fill the table with infrastructure failures dressed as failed builds.

`assert_phase_ok()` catches the other half of that class: an agent that worked for 200 tool calls and then lost its connection. `claude -p` exits 0 whenever the agent completes its turn, whatever it concluded about the project — a project that won't boot still exits 0, and shows up in the score instead. So a non-zero exit from any phase is the CLI failing, never a build result, and it aborts the sweep the same way. That is also why the TSV carries no exit column: with the guard in place a written row could only ever hold `0`. Nothing in the harness measures boot success directly.

Only one harness script may hold a workspace at a time — `acquire_workspace_lock()` takes `$WORKSPACE/.harness-lock` (a `mkdir`, since macOS ships no `flock`) and both scripts call it. `run-tests.sh` identifies each case's output by mtime, so a second script writing the same tree makes a sibling look like this case's project, and review, scorecard, and the README prepend all follow the wrong path.

Generated projects land in `../seedkit-examples/` (the sibling submodule). Per-run logs land in `../seedkit-examples/logs/` (gitignored inside that repo). The harness prepends each testcase's `## Prompt` block to the generated project's `README.md` and writes a top-level `seedkit-examples/README.md` index after every run.

## Baseline contract

`run-baseline.sh` is the control arm: same `## Prompt`, same `## Boot check`, same auto-fix instruction, no skill. The two arms must differ in one variable only, so anything given to one is given to both.

- Output goes to `seedkit-examples/baselines/<model>/<case>/` — `model_slug()` in `agents.sh` turns `claude-sonnet-5` into `sonnet` — so the control arm publishes with the skill arm and each model's control sits beside the others instead of overwriting them. That sits under the `.claude/skills/django-seedkit` symlink `run-tests.sh` creates, so `unlink_skill()` removes the project-scoped symlinks before the run and `assert_skill_unreachable()` walks up from the baseline root and refuses to start if anything is still reachable (a hand-placed real directory, or a global install under `~/.claude/skills/` or `~/.gemini/config/plugins/`). `run-tests.sh` recreates the symlink at the top of its next run, so the removal costs nothing. The two scripts can't run concurrently anyway — they share one workspace lock.
- Baseline logs go to `seedkit-examples/logs/baselines/`: inside the wholesale-gitignored `logs/`, and outside `review-logs.sh`'s non-recursive `logs/*.log` glob. `review-logs.sh` also rejects any `baseline-*.log` by name and any log with no `BUILD` phase, so an explicit argument can't get one through either.
- Both arms are graded on `train/scorecard.md` — eight arm-neutral static checks emitting `SCORE n/8`. The testcase's `## Review` section is skill-arm-only; it asserts structure the control was never asked for.
- Both arms write to one `results-<cli>.tsv` in the examples repo (`case / arm / cli / model / score / build_s / tool_calls / fixes / rewrites / run_at`); the `arm` column separates them, so comparing is `column -t < results-claude.tsv`. Split per CLI because comparing a claude skill run against a codex baseline measures the CLI, not the skill.
- Every claude invocation carries `--settings '{"advisorModel":""}'` (`CLAUDE_HARNESS_SETTINGS` in `agents.sh`), for the same reason as `CLAUDE_CODE_DISABLE_AUTO_MEMORY`: operator config must not shape a harness run. `advisorModel` is a user setting, so on a machine that sets it the build agent can consult a stronger model on demand — making the `model` column a lie for both arms, and in the control arm supplying exactly the scaffolding guidance the skill does. `--disallowedTools advisor` does not work; the advisor is not a permission-system tool.
- Generation phases (build and baseline) pass `CASE_DENY='Bash(git:*)'` (`GENERATION_DENY` in `agents.sh`). The build agent works in `seedkit-examples`, a git repo holding every earlier generated project, so `git log` / `git show` hand it prior outputs to copy from. Deny rules win over `--dangerously-skip-permissions`. It is opt-in per caller because `review-logs.sh` commits and pushes through the same dispatcher and must keep git. Both generation prompts also forbid reading sibling directories — denying git closes one route to earlier outputs, the prompt closes the rest.
- `build_s`, `tool_calls`, `fixes`, and `rewrites` are **build-phase only**, captured before review and scorecard run. Only the skill arm has a `## Review` phase, so a wall-clock total would charge it for verification the control never performs and make the skill read as slower. `tool_calls` counts `[tool:…]` markers in the log — reaching a working project in fewer loops is an outcome the skill gets credit for, not just reaching it. Any metric added later goes in the same place, for the same reason.
- `fixes` is the metric to watch when iterating on the skill; `score` is not. The scorecard is a floor test the skill passes by construction — it reads 8/8 in every scored case and has never once failed a check against skill output, so it separates the arms and then stops moving. A fix, by contrast, is a reference file that was wrong: the agent had to repair its own output. `fix_report_block()` in `agents.sh` supplies the `FIXES n` tail both generation prompts end with — shared rather than duplicated, because the arms must differ in one variable only. `rewrites` is its witness: `fixes` is self-reported by the agent under test and undercounts (agents file routine repairs under "Notes" and report zero), while `rewrites` counts writes to a path already written this run, from `[file:…]` markers `cli_dispatch` emits. Read them together — one number the agent chose, one it didn't.
- `upsert_result()` (`agents.sh`) **replaces** the row for a `(case, arm, model)` triple. Re-running a case after a skill fix updates its row in place — appending would leave the stale result beside the new one and every comparison would read both. Model is part of the key because baselines are per-model: without it an opus control run silently overwrites the sonnet one it exists to be compared against. The file stays sorted on the same three fields so the committed diff is legible.

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
