# Resolution — pr-00208 (issue-205 git-config wording)

Chain: [review-a.md](review-a.md) · birth PR #208 · branch
`feature/205-git-config-status-wording`. Fix commit: `7c790b8`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `7c790b8` | ON phrase = status.sh em-dash form at both sites; pin now requires both phrases verbatim in status.sh too; both sabotage directions red |
| a W2 (LOW) | **implemented** | `7c790b8` | how-to shows the markers-present shape + notes on/off re-render drops the markers (docs-only) |

## Evidence detail

### a W1 (LOW) — ON phrase equality with `opk status`

Both ON sites (`config.sh:412`, `478`) now render
`ON — protected (soft-only — agent tools blocked)` — the parenthetical
is byte-identical to `status.sh:206`; the OFF phrase already matched at
all three sites. The equality claim (PR body, code comment,
`secure-git-config.md:33-34`) now holds verbatim.

The pin in `tests/unit/test-git-config.sh` grew the agreement check the
a-wave lacked (that lack is why the drift passed a green suite):
beyond config.sh's internal shape (`-ge 2` ON / `-ge 3` OFF, no bare
`"ON  (` / `"OFF  (` rows) it now requires
`protected (soft-only — agent tools blocked)` and
`access allowed (agent tools may edit git config)` in status.sh
(`grep -qF` against `$STATUS`), so drift on EITHER side fails the suite.

Sabotage (work committed first per the house rule; mutate → red →
restore → green, both directions observed the way production observes
it — the suite):

1. config.sh ON site back to comma form → `FAIL issue #205: git-config
   row wording regressed`, rc=1 (33/34). Restored, green.
2. status.sh phrase to comma form → same FAIL, rc=1. Restored, green
   (34 passed, `All tests passed.`).

Class sweep (pattern `soft-only,` across files/, docs/, tests/): the
ON-phrase comma form is gone everywhere; the three remaining hits are
unrelated prose (`soft-only, ddev-safe` / `not OS-blocked (soft-only,`
in docs:8, e2e/run.sh:1062, test-jsonc-parser.sh:134) — different
strings, not the git-config phrase.

### a W2 (LOW) — third status shape documented

`docs/how-to/secure-git-config.md` now carries a sentence naming the
markers-present state (configs left over from older kit versions or
hand-edited; current render paths do not produce it — `off` deletes the
`//SECURE_GIT:` lines, `on` activates the rules) plus a third example
block showing the `(markers present, rules inactive)` detail line.
Docs-only; no code change.

## Follow-ups the implementation required

None beyond the wave itself. Note for the next round: the fix touches
production strings and pin literals (review-relevant code) → owes
snapshot b per the stop rule; the a-wave snapshot header claim
"how-to shows the output" is now complete for all three shapes.
