# Resolution — pr-00200

Case: [pr-00200](review-a.md) · birth-PR #200 · snapshot a reviewed
eed9604 (99e3fd1..eed9604) on 2026-10-19; fix wave e563874.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `e563874` | `stat -L` + dangling/no-x-target pins; sabotage red→green |
| a W2 (LOW) | **implemented** | `e563874` | 4400 pin + corrupt-007 compound pin; before the summary gate |
| a W3 (INFO) | **implemented** | `e563874` | cli.md parenthetical widened to the mode-bit rule |
| a W4 (INFO) | **deliberately not done** | — | pre-existing 0.0.48b-W3 cell; out of wave scope (backlog) |

## Evidence detail

### a W1 (MED) — stat without -L defeated the re-scoped gate

Fix is the snapshot's own recommendation: one token, `stat -L`. With
`-L` a dangling link makes stat fail → empty → `ADV_BIN_ANYX=false` →
counted warn (the old `[ ! -x ]` verdict restored, and the comment's
"dangling symlink … empty stays false — the loud direction" claim
becomes true). A healthy symlink now feeds the TARGET's bits (root's
`[ -x ]` equivalence holds again — the "sudo resolves it" premise of
the unknown arm is valid for every shape that reaches it). Pins
(discriminating, root-run-safe — `stat -L` fails for every user on a
dangling link): `#200 a W1: dangling symlink counts the warn` and
`#200 a W1: symlink judged by its TARGET's bits`. Sabotage matrix:
deleting `-L` turns both pins red (verified post-commit); restored,
the suite is green again.

### a W2 (LOW) — pin deficit closed

New pins riding the same harness block: `4400 → counted warn` (the
comment's special-digit claim, pinned; root-safe — no x bit means even
root's `[ -x ]` is false) and the corrupt-content-behind-007 compound
pin (caller-denied arm is content-independent — the #163 classifier is
`[ -x ]`-gated and unreachable there; inside the existing root-skip
guard, same 0.0.46a-F2 honesty). The 4096-mode brute force over the
case patterns was re-run in snapshot a's verification (mismatches=0);
the patterns are untouched by the fix.

### Class sweep (L2, for the fix wave)

Pattern: `stat -[Lc]` / `stat --` across `files/`. Sites beyond the
fixed one: fs-baseline.sh:32,38 (`%A`/`%G` against the deploy
manifest — a symlink reads 777 and mismatches: loud, not a downgrade;
operands are kit-deployed regular files); ddev-handover.sh:290 (%A on
project dirs; :615 is explicitly `[ ! -L ]`-gated); status.sh:433,440
(`_st_ancestor_grants_x` — report-only, documented-loose-by-purpose);
update.sh:882 (`/mnt/c` DrvFs mount mode — fixed system path); the
remaining `%U`/`%G` reads are ownership checks on kit-managed paths.
No sibling repeats the wave's shape (a mode-bit any-x verdict silently
downgrading a counted broken-kit warn) — C1 is the only instance.

### Stop-rule status

The fix wave touched production and test code → snapshot b (micro-wave
review of 88aad0d) is owed in a fresh session before the PR can close.
