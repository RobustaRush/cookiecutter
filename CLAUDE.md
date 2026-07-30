# seedkit

Claude Code plugin: a skill for bootstrapping Django projects. The repo root is the plugin root, so
everything here ships to anyone who installs it.

Layout:
- `.claude-plugin/plugin.json` — the plugin manifest. `.claude-plugin/marketplace.json` — this repo
  serving as its own single-plugin marketplace.
- `skills/django-seedkit/SKILL.md` + `skills/django-seedkit/references/*.md` — the skill itself.
- `testcases/0[1-9]-*.md` — scripted runs that exercise the skill end-to-end. Specs, not scripts: the
  harness that runs them lives elsewhere.

Two sibling repos hold everything that is not the skill. Keep it that way — a plugin repo is downloaded
in full by every user, and its whole tree is read by the marketplace review pipeline.
- **[seedkit-examples](https://github.com/viewflow/seedkit-examples)** — the generated projects and the
  `train/` harness that produces them. It reads `skills/` and `testcases/` from here via `$SEEDKIT`
  (default `../seedkit`) and is the only thing that writes back. Its `CLAUDE.md` holds the harness and
  baseline contracts.
- **viewflow-pro/seedkit/** (private) — the django-seedkit.viewflow.io landing page and blog, its
  deploy playbook, and the article backlog. Its `CLAUDE.md` holds the blog rules.

Run `claude plugin validate .` after touching either manifest.

## Writing reference files

Each reference is a paste-ready snippet plus the minimum prose needed to use it correctly.

**Show the correct sample.** Imperative, specific, copyable. The agent uses snippets verbatim (`SKILL.md` "Snippet integrity" pitfall) — anything not in the snippet won't make it into the generated project.

**Drop the matching "don't".** When a positive sample shows the right way, don't follow it with "Don't write X" / "Never use Y". The correct line is the canonical answer; the redundant warning adds tokens, invites the agent to second-guess, and ages badly. Keep negative guidance only when it stands alone — a behavior rule with no positive code sample (e.g. "Don't strip the `Host`-header check globally", "Don't log request bodies").

**One reason, not two.** If the snippet needs context, follow it with a short rationale (`# comment` inside the snippet, or one sentence after). Don't pile on alternatives, anti-patterns, or "you might also want to" tangents — every additional sentence is one the agent might cargo-cult into output.

**No prose drift.** No significance inflation ("crucial", "robust", "production-ready"), no fake -ing analysis ("…, ensuring proper handling of…"), no vague attribution ("experts recommend"), no podium voice ("clearly", "obviously"). The simple-english-writing skill enumerates the patterns; we follow it.

**Cross-reference, don't duplicate.** When a snippet belongs in another reference (e.g. `test.py` settings live in `new-project.md`, not `pytest.md`), point to it with one sentence and stop. Two copies drift.

**Good path only — no artefacts, no history.** A reference describes the path we want followed today. No "surfaced by run X", no "the agent used to do Y instead", no "previously we shipped Z". CHANGELOG is the place for that. A reader of the reference doesn't need provenance to follow the snippet.

## Changelog

`CHANGELOG.md` is read by people who installed the skill and want to know what changed **in the
skill**. Only `skills/` earns an entry: `SKILL.md`, the references, the questionnaire. Nothing else
does — not `README.md`, not this file, and nothing in the two sibling repos. Testcase and harness work
goes under its own `### Testcases and harness` heading, below the user-facing ones, or nowhere.

Versions are dated `YY.WW.D` — `date +%y.%V.%u` — one section per day; all of a day's commits collapse
into one block. After every skill edit, append (or extend) one short bullet under today's section using
Keep-a-Changelog headings (`Added` / `Changed` / `Fixed` / `Removed`). Batch related fixes into a
single bullet. Bump `version` to the same date string in both `.claude-plugin/plugin.json` and
`skills/django-seedkit/SKILL.md` frontmatter. If `CHANGELOG.md` exceeds ~200 lines, trim the oldest
sections — git keeps the rest. `seedkit-examples/train/review-logs.sh` does this inline per log
iteration — version bump + changelog edit happen in the same commit as the reference fix.

## Maintaining testcases

Each testcase has the same closing block:

```
- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
```

When a testcase log surfaces a real bug the agent had to fix in-flight, that fix moves into the matching
reference so the next run doesn't hit it. The agent's "Suggested skill changes" line is signal but not
authoritative — verify each claim against the actual reference before patching.

The reviewer prompt at the bottom of every testcase is identical and short: report only boot-blockers /
smoke-failures / security holes, quote the literal substring read, no nitpicks, "No issues found." is a
valid report. Don't re-add per-case "INTENTIONAL design decisions (a)–(k)" exemption lists — the
substring-quote rule and the boot-blocker filter cover it.

## Submodule workflow

`seedkit/` is a submodule of `RobustaRush/Robusta`. So is `seedkit-examples/` — they're siblings,
neither nested in the other (so cloning `seedkit` alone doesn't drag the examples).

Commit and push inside `seedkit/` and stop there. Don't touch the parent repo — the pointer bump is the
user's, and a checkout of `seedkit` often has no parent repo above it at all.
