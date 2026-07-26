# seedkit

Claude Code skill for bootstrapping Django projects + the testcase harness that exercises it.

Layout:
- `skills/seedkit/SKILL.md` + `skills/seedkit/references/*.md` — the skill itself.
- `testcases/0[1-9]-*.md` — scripted runs that exercise the skill end-to-end.
- `train/` — the testcase harness: `run-tests.sh` pipes each testcase through an agent CLI and writes per-run logs; `run-baseline.sh` generates the no-skill control group; `review-logs.sh` auto-patches the skill from those logs; `agents.sh` is the shared multi-CLI (claude/codex/agy) dispatch the three scripts source.
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

Each case runs in its own session (portable `setsid_exec` Python shim, `train/agents.sh`) so the post-case sweep `kill -- -$pgid` reaches every descendant — orphaned celery workers, gunicorn, `runserver` autoreloader. A watchdog terminates the group if a phase overruns — `TIMEOUT_PER_PHASE` (7200) in `run-tests.sh`, `TIMEOUT_PER_CASE` (3600) in `run-baseline.sh`. Cleanup is harness-side; the skill and testcase prompts must not invoke `pkill -f` (it matches the parent agent-CLI process).

Generated projects land in `../seedkit-examples/` (the sibling submodule). Per-run logs land in `../seedkit-examples/logs/` (gitignored inside that repo). The harness prepends each testcase's `## Prompt` block to the generated project's `README.md` and writes a top-level `seedkit-examples/README.md` index after every run.

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
