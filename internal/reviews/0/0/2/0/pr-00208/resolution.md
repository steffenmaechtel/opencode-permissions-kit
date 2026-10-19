# Resolution — pr-00208 (issue-205 git-config wording)

Chain: [review-a.md](review-a.md) · [review-b.md](review-b.md) ·
[review-c.md](review-c.md) · birth PR #208 · branch
`feature/205-git-config-status-wording`. Fix commits: `7c790b8`
(a-wave), `670aa41`/`da6b08a` (b-wave), `f1dc37e` (b W3, reopened);
snapshots b (`f6fe328`) and c reviewed them.

Status: closed — b-wave was 1 MED bookkeeping + comments; the
maintainer reopened b W3 post-closure (`f1dc37e`); snapshot c found
zero findings; chain closed.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `7c790b8` | ON phrase = status.sh form, both sites; agreement pinned both ways |
| a W2 (LOW) | **implemented** | `7c790b8` | how-to shows the markers shape + on/off re-render note (docs-only) |
| b W1 (MED) | **implemented** | this file | rows trimmed into the 120-col budget; overflow in Evidence detail |
| b W2 (LOW) | **implemented** | `670aa41` | ratchet header names both scope halves; resolutions named as pinned |
| b W3 (INFO) | **implemented** | `f1dc37e` | maintainer reopened post-closure; hint aligned + pinned both sides |

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

### b W1 (MED) — resolution rows vs the line-length ratchet

The dispositions rows above measured 182/140 content columns against
the review-README's ≤120 rule; `test-line-length.sh` failed at HEAD
(`2 new line(s) over 120 chars (not in the baseline)`, rc=1) — the
ratchet's markdown half genuinely covers resolutions (only review-*
snapshots are exempt). Red observed pre-fix, green post-fix (gates
below); both trimmed rows keep their key evidence, the overflow
already lived in the a-wave detail blocks. Class sweep (L2): the 12
baseline `resolution.md` entries are all legacy cases pr-00109…
pr-00171 — the README's baseline-pinned legacy range — no living
resolution exceeds the limit.

### b W2 (LOW) — ratchet header understated its own scope

`670aa41`: the header (lines 2-3 and the scope block) now names BOTH
halves — shell/yml and the markdown docs_scope — and states that
review resolutions are pinned. Comment-only: tests/ is outside the
ratchet's scan, so no baseline effect; shellcheck green.

### b W3 (INFO) — markers hint is git-config-status-only

Initially deliberately not done (pre-existing behavior, no claim
breaks, no consumer parses it). The maintainer reopened it
post-closure — the alignment is the chain's own spirit, and the
#158 neutrality rationale covers only CONSCIOUS OFF choices, not
leftovers. `f1dc37e`: status.sh gains the markers-present elif
(same neutral OFF row + `ui_detail "$f (markers present, rules
inactive)"`, byte-identical to config.sh:416, muted under --short);
the agreement pin requires the markers literal in BOTH files
(sabotage: rewording either side → suite rc=1, restored green);
behavioral smoke via `agent_config_render` over the real template
(on → ON, raw → MARKERS, off → CLEAN); how-to sentence now credits
both commands. Snapshot c (`da6b08a..f1dc37e`): zero findings.

## Follow-ups the implementation required

None beyond the wave itself. Note for the next round: the fix touches
production strings and pin literals (review-relevant code) → owes
snapshot b per the stop rule; the a-wave snapshot header claim
"how-to shows the output" is now complete for all three shapes.

### Stop-rule status

Snapshot b (`f6fe328`) reviewed the a-wave fix `4bca8e1..bc1a5db`:
the fix itself verified correct (byte-identity, sabotage both
directions reproduced, docs rendering-exact); 1 MED was this
resolution's own rows breaking the line-length ratchet. The b-wave
dispositions trim resolution rows and complete a test-file comment —
no review-relevant code. The maintainer then reopened b W3: `f1dc37e`
touches status.sh (review-relevant → one more review owed); snapshot
c reviewed `da6b08a..f1dc37e` and found zero findings, so the
c-round disposition is this bookkeeping only. Stop rule met (twice);
chain closed; no snapshot d owed. Release gate remains: both e2e
suites at baseline with zero skips before tagging.
