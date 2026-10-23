# Resolution — pr-00234 (issue #215 exec-time symlink gate on the .ddev pair)

Chain: [review-a.md](review-a.md) (wave review of 395fee7, five-axis
fan-out) → fix wave (this chain). Snapshot a's severity mapping note
(C1 reported HIGH, mapped MED with rationale) is accepted as recorded.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `d1dcf34` | gate hoisted above `_ddev_tree_conforms` (ddev-handover.sh); conforming-victim drive red without it |
| a W2 (LOW) | **implemented** | `d1dcf34` | 2 new drives (10 pins): conforming race 5x, dev-owned flag race 5x; old fixture comment re-scoped |
| a W3 (LOW) | **implemented** | `d1dcf34` | warn now "a path component (parent or operand) is a symlink" |
| a W4 (LOW) | **implemented** | `d1dcf34` | loud `/` refusal in the walk (mirrors `_fsb_pass`); header contract edges documented |
| a W5 (LOW) | **implemented** | `d1dcf34` | security-model.md "Known residual gaps" entry (gate + residual window) |
| a W6 (INFO) | **deliberately not done** | — | operator-invoked surface, validation→exec window incl. `exec sudo` hop; Follow-ups below |
| a W7 (INFO) | **deliberately not done** | — | inherent non-atomic window + F8 documented in code and now in security-model.md (a W5) |
| a W8 (INFO) | **implemented** | `d1dcf34` | "consume-time leaf gate" wording; find's `-type d` named as the plant filter |
| a W9 (INFO) | **deliberately not done** | — | verification finding (sweep exact, 44 hits re-run); nothing owed |

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

### Gates (this fix wave)

`sh tests/unit/test-ddev-as-opencode.sh` green (288 PASS incl. the 10
new race pins + 4 walk-edge pins); `make test` green; `make lint`
green; `make check-version` green; line-length ratchet green (no new
offenders); sandbox policy green. Sabotage, executed on the committed
tree (d1dcf34), observed the way production observes (suite output),
restore + re-run green after each:

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

## Follow-ups

- **a W6 (INFO):** `bin/opk` handover executors recheck the operand
  leaf but not the ancestor chain — same class under the parent-swap
  definition, but operator-invoked on operator-chosen paths with a
  validation→exec window that includes the `exec sudo` hop (micro-
  seconds, requires the operator to run the command at all). Next
  class pass over `chmod -R|chown -R` should decide between an
  ancestor walk there or an explicit accepted-residual record.
- **Owed micro-wave review (review-b):** this fix wave changed
  production code (ddev-handover.sh), tests and docs — per the stop
  rule it owes a wave review of the fix diff; fires on the
  maintainer's go.
- **e2e:** both suites run green on the fix-wave tree (d1dcf34):
  `make e2e` 309/0, `make e2e-rootless` 47/0 — recorded in Gates above.
