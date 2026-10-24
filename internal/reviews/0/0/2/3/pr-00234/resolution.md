# Resolution — pr-00234 (issue #215 exec-time symlink gate on the .ddev pair)

Status: closed (maintainer, 2026-10-24) — confirmed the stop rule: the
last round (b, review-b) saw all three findings dispositioned and its
fix wave touched no review-relevant code — files touched =
resolution.md, review-a.md pointer line, INDEX.md (bookkeeping,
RM-0065).

Chain: [review-a.md](review-a.md) (wave review of 395fee7, five-axis
fan-out) → fix wave d1dcf34 → [review-b.md](review-b.md) (micro-wave
review of the fix diff, single-pass) → b-wave fix (this chain's latest).
Snapshot a's severity mapping note (C1 reported HIGH, mapped MED with
rationale) is accepted as recorded.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `d1dcf34` | gate hoisted above the conform probe; conforming drive red without it |
| a W2 (LOW) | **implemented** | `d1dcf34` | 2 new drives (10 pins); old fixture comment re-scoped |
| a W3 (LOW) | **implemented** | `d1dcf34` | warn now "a path component (parent or operand) is a symlink" |
| a W4 (LOW) | **implemented** | `d1dcf34` | loud '/' refusal; contract edges documented |
| a W5 (LOW) | **implemented** | `d1dcf34` | security-model.md "Known residual gaps" entry (gate + residual window) |
| a W6 (INFO) | **deliberately not done** | — | operator-invoked surface; Follow-ups below |
| a W7 (INFO) | **deliberately not done** | — | inherent window + F8; also in security-model.md |
| a W8 (INFO) | **implemented** | `d1dcf34` | consume-time wording; -type d as the plant filter |
| a W9 (INFO) | **deliberately not done** | — | verification finding (sweep exact, 44 hits re-run); nothing owed |
| b W1 (MED) | **implemented** | `f1fd24e` | 6 rows wrapped, pointer added; make test green re-run |
| b W2 (INFO) | **deliberately not done** | — | headline residual claim true; rewording optional |
| b W3 (INFO) | **implemented** | `f1fd24e` | sweep recorded: _fsb_pass refuses, agent_home_sane base never / |

The retracted ghost (a-review C2, sabotage-count asymmetry) needs no
disposition; the derivation lives in the snapshot.

## Evidence detail

### a W1 (MED) — gate hoisted above the fast-path probe

The `_ddev_components_sane` call moved from inside the `else` of
`_ddev_tree_conforms` to immediately after the consume-time leaf gate,
so it runs on EVERY branch of the iteration — a fired gate skips the
whole iteration including `ddev_devowned_flag` and the
`ddev_handover_project*` tail. The walk's cost is O(depth) lstats per
emitted `.ddev`, negligible against the find scan itself; the fast
path keeps skipping the recursive pair for conforming trees. The
comment block now states the relocation reason (swap victim = exactly
a conforming top inode; resolved containment canonicalizes both sides
through the swap) and the class-sweep boundary was re-scoped: the F8
sentence now names the flag write's own mid-write TOCTOU (the
through-a-swapped-parent variant is closed by the walk for this scan;
the `--opk-devowned-flag` trigger path stays the accepted F8 residual,
opencode-privilege-capped).

Pins: `tests/unit/test-ddev-as-opencode.sh` — the conforming-victim
drive (victim `.ddev` `chmod 775` = conforming, settings dir 755/600 =
non-conforming, same buffered find seam) pins
`victim/config/system/settings.php` stays 600, warn present, no
`ddev settings handover:` echo, rc 0. Without the hoist the forward
settings pair chmod -R g+w's the victim through the link (620) and the
drive goes red — pinned through exactly the W1 mechanism.

### a W2 (LOW) — the unpinned branches get drives

- Conforming-victim race drive (5 pins, see W1).
- Dev-owned flag race drive (5 pins): `DDEV_DEV_OWNED=true` + seam;
  pins victim config.yaml gains NO `disable_settings_management:`,
  no `dev-owned flag written:` echo, settings 600, rc 0, seam fired.
  Sabotaged (gate deleted), the flag write reaches the victim's
  committed config through the link and both flag pins go red — the
  previously unexercisable "flag write included" half.
- The plain drive's `chmod 755` fixture comment now states its real
  reason (pair-half discrimination) instead of the pre-fix reasoning
  ("fast-path probe must not void the gate" — obsolete under the
  hoist).

### a W3 (LOW) / a W8 (INFO) — message and comment truth

Warn line reworded to "a path component (parent or operand) is a
symlink (swapped mid-scan?)" — the walk's last step checks the operand
itself, so a leaf swapped in the (now smaller) window between the leaf
gate and the walk no longer produces a wrong message. The rewritten
block calls the `[ -L "$dhr_d" ]` a consume-time gate and names find's
`-type d` as the filter that keeps planted links out of the scan
output (the old text claimed the gate catches "statically planted
links at SCAN time").

### a W4 (LOW) — walk contract edges

Root `/` now normalizes to the empty string and the walk refuses loud
(`warn: refusing scan root '/' ...` + return 1), mirroring `_fsb_pass`
(fs-baseline.sh) instead of silently walking the whole filesystem.
The header documents the remaining contract edge honestly: operand ==
root or outside the root returns 0 — nothing below the root to walk,
the caller's leaf gate covers the operand; no registered root is
`.ddev`-named (config.sh:390, install.sh:1805 pass registered project
roots).

### a W5 (LOW) — docs

`docs/concepts/security-model.md` "Known residual gaps" ... entry
"Scan→exec symlink swaps on handover trees (gated; a window remains)"
added: the gate, the skip-with-warning semantics, and the honest
residuals (non-atomic gate→op window, leaf-only mid-recheck, accepted
flag-write TOCTOU with a link to ddev-integration.md).

### b W1 (MED) — ratchet + reviews-parity red at the a-wave HEAD

The a-wave's disposition rows ran 124-146 content columns while the
ratchet scope includes review resolutions (only review-* snapshots are
exempt — verbatim over wrap), and two reviews-parity members were red
with them: review-a.md lacked its `> Resolution:` pointer line and the
committed INDEX still said pr-00234 "no-resolution". The a-wave Gates
section's "make test green / line-length ratchet green" claims were
therefore false at d1dcf34..ca4c564 (three red members; the claim was
written before the resolution file existed and never re-verified —
review-b reproduced all three on the pristine HEAD). Fixed: the six
rows wrapped (full content preserved in the Evidence detail blocks
above), the pointer line added to review-a.md (the one allowed
post-hoc snapshot edit), INDEX regenerated with the review-b snapshot
commit (a3ecc9b, flipping the stale "no-resolution" row to open). Class sweep: the ratchet
itself is the class gate — its green re-run below is the sweep
evidence (no other in-scope file grew).

### b W2 (INFO) — residual wording

The security-model residual sentence names "the recursive pair" as the
op exposed in the gate→op window; on the conforming branch the first
unguarded ops are the flag write and the settings pairs. The headline
claims (non-atomic gate, leaf-only mid-recheck) are true and the entry
names the residuals honestly — deliberately not reworded; a future
touch of that entry can generalize to "the iteration's first op".

### b W3 (INFO) — a W4 sweep recorded

Same-shape walker sweep for the loud '/' refusal (pattern: chain
walkers normalizing a scan root): `_fsb_pass` (fs-baseline.sh) already
refuses '/' loudly — the "mirrors _fsb_pass" claim holds;
`agent_home_sane` (staged-write.sh) walks below a base of
`/home/<user>` (OPK_AGENT_HOME override is test-only) — structurally
never '/'. No sibling site needs the refusal.

### Gates (this fix wave)

`sh tests/unit/test-ddev-as-opencode.sh` green (288 PASS incl. the 10
new race pins + 4 walk-edge pins); `make lint` green; `make check-version`
green. Correction (b W1): this section originally claimed "`make test`
green; line-length ratchet green (no new offenders)" — false at this
wave's tree: the ratchet, the reviews-parity pointer and the INDEX were
all red (see b W1 above); the claims were written before resolution.md
existed and not re-verified after. The b-wave re-run below is the
verified state. Sabotage, executed on the committed tree (d1dcf34),
observed the way production observes (suite output), restore + re-run
green after each — all three counts re-executed and confirmed by
review-b on the pristine tree:

- gate-call deletion: **10 pins red** (plain drive 4 — victim .ddev
  620, victim settings 620, warn absent, success echo; spaced 1 —
  mode 620; conforming 3 — settings 620, warn absent, settings echo;
  flag 2 — flag written into the victim's config, success echo).
- position sabotage (gate re-inserted inside the `else`, the pre-fix
  shape): **5 pins red** — exactly the two new drives; the
  pre-existing drives stay green (their victims are non-conforming),
  proving the new drives pin the HOIST, not just the gate's existence.
- '/' refusal deletion: **2 pins red** (rc 0 instead of 1, warn
  absent).

Both e2e suites on the fix-wave tree (d1dcf34): `make e2e` **309/0**,
`make e2e-rootless` **47/0** (opencode 2.1.4, cache warm from the
birth wave's run).

### Gates (b-wave fix) — measured on this tree

`make test` green (full unit suite, rc 0, includes the ratchet,
reviews-parity and reviews-lint that were red before the wrap);
`sh tests/unit/test-line-length.sh` rc 0 (resolution.md now 0 lines
over 120; no other in-scope file grew — the ratchet itself is the
class-sweep gate); `test-reviews-parity` OK (26 rows, pointer added);
`test-reviews-lint` OK (26 cases). No production file touched by this
wave — the ddev suite's 288/0 (review-b) still describes the code.

## Follow-ups

- **a W6 (INFO):** `bin/opk` handover executors recheck the operand
  leaf but not the ancestor chain — same class under the parent-swap
  definition, but operator-invoked on operator-chosen paths with a
  validation→exec window that includes the `exec sudo` hop (micro-
  seconds, requires the operator to run the command at all). Next
  class pass over `chmod -R|chown -R` should decide between an
  ancestor walk there or an explicit accepted-residual record.
- **Owed micro-wave review (review-b):** ran — snapshot
  [review-b.md](review-b.md) (a3ecc9b) over the fix diff; all three
  findings dispositioned above. This b-wave's dispositions touched no
  review-relevant code (files touched: resolution.md, review-a.md
  pointer line, INDEX.md — bookkeeping only), so per the stop rule the
  chain closes with this round; confirmation belongs to the maintainer
  or the next round per RM-0115.
- **e2e:** both suites run green on the fix-wave tree (d1dcf34):
  `make e2e` 309/0, `make e2e-rootless` 47/0 — recorded in Gates above.
