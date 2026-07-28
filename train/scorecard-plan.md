# Scorecard plan — raising discrimination, not the maximum

Status: planned, not implemented. Written 2026-07-27.

The question this answers is not "what else could we check?" It is "what would
catch a skill regression?" Those have different answers, and the first one is
how a benchmark saturates.

## Why now

The eight static checks in `scorecard.md` separate the arms and then stop
moving. Sonnet, 01–04, 2026-07-27:

| case | baseline | skill |
|---|---|---|
| 01-blog | 5/8 | 8/8 |
| 02-shop | 7/8 | 8/8 |
| 03-jobs-board | 4/8 | 8/8 |
| 04-media-vault | 7/8 | 8/8 |

The skill arm has scored 8/8 in every case ever graded and has never failed a
single check. As a floor test that is the correct result; as a signal for
iterating on the skill it is dead.

The opus control arm then closed the gap from the other side. Same prompts, no
skill, `claude-opus-5`:

| case | opus baseline | sonnet baseline |
|---|---|---|
| 01-blog | 6/8 | 5/8 |
| 02-shop | **8/8** | 7/8 |
| 03-jobs-board | 7/8 | 4/8 |

A control run reaching 8/8 is the ceiling arriving from below. On a stronger
model the eight checks stop separating anything.

`fixes` did not follow it down — opus baseline 02-shop took **12** fixes
against the skill arm's 2 on the same case. The rework metric still
discriminates where the score no longer does, which is the evidence that the
problem is the rubric rather than the arms.

## Blocker — the totals are not computed

`scorecard_value()` (`agents.sh:485`) greps the `SCORE n/8` line the grading
model writes. Nothing checks it against the CHECK lines above it, and one of
four disagreed:

```
baseline-01-blog          PASS=5 FAIL=3   SCORE 5/8   ok
baseline-02-shop          PASS=7 FAIL=1   SCORE 7/8   ok
baseline-03-jobs-board    PASS=4 FAIL=4   SCORE 5/8   wrong — 4/8
baseline-04-media-vault   PASS=7 FAIL=1   SCORE 7/8   ok
```

All eight logs emit exactly 8 CHECK lines, so the checks ran correctly every
time; only the addition was wrong. The error flatters the control arm.

Fix `scorecard_value()` to derive the total, and return `-` when the CHECK
lines don't add up to the expected count — a truncated scorecard phase then
reads as missing instead of as a plausible number:

```sh
scorecard_value() {
    local p f
    p=$(grep -c '^CHECK .* PASS ' "$1" 2>/dev/null) || true
    f=$(grep -c '^CHECK .* FAIL ' "$1" 2>/dev/null) || true
    (( p + f == 8 )) || { printf '%s' '-'; return; }
    printf '%s/8' "$p"
}
```

Do this first. Every number in this document comes from that grep, and the
existing rows can be recomputed from logs already on disk — no re-run, and it
moves the sonnet baseline mean from 6.0 to 5.75.

## Two groups

### Group A — static file reads (the current 8, and no more)

These are done. Every obvious addition lands in this group, and the skill arm
passes all of them by construction, so each one widens the arm gap while
teaching nothing. Rejected candidates, recorded so they don't get re-proposed:

| candidate | why not |
|---|---|
| `prod-security` — `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, HSTS | Correlated with `secret-failsafe`, which already fails 4/4 sonnet baselines. Amplifies an existing signal |
| `dockerfile-hygiene` — non-root `USER`, `.dockerignore` | No observed failure in either arm |
| `ci-runs-checks` — workflow runs the project's own lint/test commands | Applies to 3 of 9 cases; no observed failure |
| `env-example-complete` — every env var the settings read has an entry | Speculative; both arms plausibly pass |
| `pinned-deps` — pre-1.0 packages pinned with `==` | Contradicts the design. `pyproject.toml` carries ranges and `uv.lock` carries the resolved versions, which is what "pins re-resolve at generation time" means. The skill states a pin only where a specific release is known-bad (`rest-modern-rest.md`); there is no general pinning rule for it to be violating |

### Group B — run the project's own declared tooling

The scorecard has never done this, and it is where skill-arm defects live: the
skill produces structurally correct projects, so its bugs hide in details only
the toolchain surfaces.

**`lint-clean`** — if the project configured Ruff, `ruff check` and
`ruff format --check` both pass.

The only candidate anywhere in the evidence with a demonstrated skill-arm
failure. `04-media-vault` was graded 8/8 today while shipping
`api/models.py` as `"\n# Create your models here.\n"` — a leading blank line
left by `ruff check --fix` deleting an unused import, which the formatter
would have stripped had it run second. `ruff format --check` fails on 8 files
in that tree. Neither the scorecard nor `fixes` saw it: no check covers
formatting, and the agent never noticed, so there was no rework to report.

Applies to 6 of 9 cases (02, 04, 05, 06, 07, 08, 09 configure Ruff; 01 and 03
specify "Lint with Ruff: no").

**`typecheck-clean`** — if pyright is configured, 0 errors.

Contingent on `lint-clean` working. Sonnet baselines 02 and 04 each burned
several fixes on pyright errors (`env(...)` → `env.str(...)`, `pyright:
ignore` on `env.list`/`env.db`/`env.email_url`) and the skill arm burned
none — so it discriminates between arms. There is no evidence it can catch a
skill regression, and it needs the venv resolved, which is slower and adds a
version-drift surface. Applies to 4 of 9 cases.

## Two contract decisions, unresolved

### The static rule

`scorecard.md:5-6` says every check is decided by reading files, never by
running the project. `lint-clean` breaks that as written.

The distinction that saves it: `ruff check` is a read-only deterministic
analyzer — no network, no server, no side effects — a different risk class
from booting the project. That amendment has to be stated in `scorecard.md`
in one line, or the next grading agent will refuse the check or invent a
static approximation of it.

### Applicability — open, decide before implementing

Ruff is configured in 6 of 9 cases, pyright in 4. `SCORE n/8` has no way to
say "not applicable". Three options, none free:

1. **Varying denominator** — `SCORE passes/applicable`. N/A drops out of both
   numerator and denominator; 01-blog reads 8/8, 04-media-vault reads 9/10.
   Honest per case. A cross-case mean over unequal denominators is
   meaningless, so the README reports per case. Needs a TSV schema change to
   carry both numbers.
2. **N/A counts as PASS, fixed `/10`** — one comparable number, no schema
   change. 01-blog reads 10/10 having never been tested on two of the ten
   checks. The score hides untested ground, which is how the current
   saturation arose.
3. **Keep `/8`; report toolchain results outside the score** — Group B runs
   and logs `TOOLCHAIN <name> PASS|FAIL|N/A` lines that never enter `SCORE`.
   The score keeps exactly the meaning it has in all existing rows; the
   toolchain result becomes its own TSV column. Nothing already published
   shifts meaning.

Bearing on the choice: the testcases already carry a skill-arm-only `## Review`
section for assertions the control was never asked for. If conditional checks
belong anywhere other than the arm-neutral scorecard, that is the precedent.

## Sequence

1. Fix `scorecard_value()`; recompute existing rows from logs on disk.
2. Decide the applicability question above.
3. Amend the static rule in `scorecard.md`, one line.
4. Add `lint-clean` alone. Re-run the 6 Ruff cases, both arms.
5. Read whether it discriminated before considering `typecheck-clean`.

One new check at a time. Four at once and a score change can't be attributed
to any of them.

Neither step 1 nor step 4 may run while a harness sweep holds the workspace
lock — the running script rewrites `results-<cli>.tsv` on every case
completion, and a recompute would be clobbered.
