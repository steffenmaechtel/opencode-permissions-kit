# Resolution — pr-00211 (release 0.0.55 full-scope review)

Status: open — a F1 implemented; F2–F37 await disposition (follow-up
waves; maintainer prioritization pending).

Chain: [review-a.md](review-a.md) — full-scope snapshot (10 reviewer
subagents, 37 findings). Base v0.0.55 @ ad9467d.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a F1 (HIGH) | **implemented** | `fd13a19` | race + spaces pins, sabotage red→green, class sweep — detail below |
| a F2 (MED) | **implemented** | `e7349e5` | loud stubs + abort pin + update.sh twin swept — detail below |
| a F3 (MED) | **implemented** | `56bc585` | if/fi tail; real-binary pins both ways; sabotage red→green |
| a F4 (LOW) | **implemented** | `31a755a` | three honest arms, both twins; 3-arm stub pins; sabotage red→green |
| a F5 (LOW) | **implemented** | `e3dd92c` | first-wins loops at both sites; origin-marker pins; sabotage red→green |
| a F6 (LOW) | **implemented** | `724e4f8` | else-log like the sudoers twin; both arms pinned; sabotage red→green |
| a F7 (LOW) | **implemented** | `9dee2f3` | fail-safe stub rc 0 (never-shadow); pin evals the real line |

## Evidence detail

### a F7 (LOW) — unguarded xdg_open_real_exists

update.sh now carries the same guard its sibling status.sh has had
since 0.0.46a F4: a `command -v` fail-safe stub. Semantics: rc 0 =
"assume a real xdg-open might exist" — with the probe's lib missing,
the keep-arm removes a kit shim (a real one may have appeared) and the
install-arm withholds the shim (cannot prove absence): both err on the
never-shadow side of 0.0.42d S1 instead of the 127-driven shadowing
side. Pin greps the real stub line out of update.sh, evals it and
asserts rc 0; sabotage (stub flipped to rc 1) → red; restored →
green. The sed-range extraction this pin originally used ran to EOF —
this sed build never closes a range on its start line — noted here so
the next pin author greps single lines instead.

### a F6 (LOW) — silent umask skip

The umask re-deploy's missing-template arm now logs its conservative
skip with the same shape as the sudoers twin directly above it
(0.0.41f S2: "the skip must not be silent"). Pins extract the real
block and drive both arms (missing → skip log; present → deploy path
unchanged). Sabotage (deleting the skip arm, syntax kept valid) → red
at the skip-log assert; restored → green. Sweep: the fetch list +
heal loop guarantee the file, so no other silent-template-skip
remains — `grep -n 're-deploy' update.sh` shows both arms logging.

### a F5 (LOW) — dual-source last-wins vs "prefer checkout"

Both update.sh sites (wsl-browser-bridge.sh, ddev-handover.sh) now use
the sibling for/break first-wins shape; the deployed LIBDIR copy can
no longer override a present checkout copy. Pins extract both real
loops (sed-anchored on the per-site fix comments — the handover loop's
`done` is indented, its end anchor is `^    done$`) and drive them
with fixture libs whose marker functions name their origin: CHECKOUT
must win when both exist, LIBDIR answers only in the fallback.
Sabotage (reverting one site to back-to-back sourcing) → red;
restored → green. Sweep: `grep -n '&& . "\$LIBDIR' update.sh` — no
remaining back-to-back source pair; config.sh/install.sh lookups were
already first-wins.

### a F4 (LOW) — safe.directory audit claims ensured over failure

Both twins (install.sh + update.sh) now carry three honest arms:
already-set (audit notes it, no redundant add — the old unconditional
log was at least true there), add-success (ui_success + ensured log),
add-failure (ui_warn naming 'dubious ownership' + NOT-ensured log).
Pins: the extracted REAL update.sh block runs through all three arms
with a sudo stub that answers both git invocations itself (hermetic —
a pass-through stub would choke on sudo's own -u/-H flags and read the
host's ~/.gitconfig, the 0.0.46a F2 class); the install twin is
grep-pinned for the NOT-ensured arm (sweep). Sabotage (deleting the
else arm) → red; restored → green. Sweep: `grep -rn '&& ui_success'`
over install/update — no other `&&`-tailed success-over-possible-
failure pair remains in the two scripts.

### a F3 (MED) — ddev-migrate list inverted rc

The `list` arm ended in `[ "$dm_found" = 0 ] && echo …` — under the
script's `set -u` (no `-e`) the failed test became the arm's exit
status: rc 1 with dumps present, rc 0 when none. Explicit `if/fi`
ends the arm; rc 0 now means "listed fine" both ways. Pins drive the
REAL bin/ddev-migrate against a scratch `DDEV_MIG_BACKUP_ROOT`
(present: rc 0 + dir listed; empty: rc 0 + "no dump directories"),
before the summary gate; sabotage (reverting to a bare `&&` tail)
turned the pin red, restore green. No sibling sites: no other case arm
in bin/ ends in a bare `&&` tail (swept `grep -n '&& echo' bin/`).

### a F2 (MED) — config.sh silent noops over success claims

config.sh's mutating-helper fallbacks became loud, fail-fast stubs
(error line naming the missing lib + rc 1): `fs_baseline_root`,
`ddev_handover_root`; `ddev_rootless_bindmounts` gained a stub returning
rc 2 (the backend switch's existing warn arm — the manual-fix hint
prints instead of an unevaluated gate reading as success). The stamp
stubs stay fail-safe by design (valid=1 forces a rescan; write is
unreachable after the loud abort) — commented in-code.

Sweep (L2): update.sh's `ddev_handover_root` twin carried the same
silent no-op under an unconditional "ddev handover pass completed" log
— now loud too (same commit). Remaining silent `() { :; }` shapes are
guards, not mutators: the two stamp stubs (above) and uninstall.sh's
`browser_bridge_remove` (own finding, a F27).

Pins (test-kit-cli.sh, before the summary gate): each stub is sed-
extracted from the real script and executed — rc + stderr message +
the set -e abort contract (a REACHED marker after the call must not
print) + the rc-2 arm + the sweep presence. Sabotage (reverting one
stub to `() { :; }`) first stayed GREEN — the capture variable `_rc`
was stale from the previous block — fixed by resetting before every
capture (`cfe12f4`), re-sabotaged RED at the right assert, restored
green. The masking itself is recorded here because it is the L4 class
in miniature: a pin that cannot fail is not a pin.

### a F1 (HIGH) — parent-symlink TOCTOU in the group baseline

Mechanism fixed: `_fsb_pass`'s xargs worker now receives the scan root
as a fixed argv element and re-tests EVERY component between the root
and the operand (`[ -L ]` chain walk, the `agent_home_sane` shape from
staged-write.sh) immediately before acting; a symlinked parent skips
the operand (skip ≠ failure — same semantic as the existing leaf skip).
String-ops only, no word splitting (spaces pinned).

Pins (tests/unit/test-fs-baseline.sh, section 9 — before the summary
gate):
- **Deterministic race**: a PATH-stubbed `find` runs the real find,
  then swaps `proj/x/y` (recorded dir) for a symlink to a victim dir
  OUTSIDE the tree, then exits — the replay chews the stale path.
  Asserts: victim mode stays 600 (sabotage expectation: 620), pass rc
  stays 0, seam-fired proof (`moved-away` exists, `x/y` is a link).
  This supersedes section 8's old "cannot be scripted deterministically"
  comment (narrowed to the leaf form).
- **Walker string safety**: component and file names with spaces still
  get chmod g+w applied (620) — the prefix peeling does not split.
- Existing pins 1–4 (final state via `fs_baseline_root`), section 8
  (leaf recheck) and 7b/7c (mid-batch failure) stay green — the walk
  changes no happy-path behavior (48/48).
- Sabotage (L4): walker deleted → race pin RED (victim 620); restored
  from `fd13a19` → 48/48 green. Recorded below in this chain.

Class sweep (L2 — pattern `[ -L ]` gates + find consumers, all shipped
files inspected):
- `sh/fs-baseline.sh` replay worker — the finding's site; the ONLY
  root-run temp-file replay in the kit — FIXED.
- `sh/ddev-handover.sh` `.ddev` handover pair (leaf-only `[ -L
  "$dhr_d" ]` ×2): same class ADJACENT but deliberately not changed in
  this wave — no temp-file replay (discovery→act within one loop
  iteration), guarded by the 0.0.45e W1 ORDER argument with the
  residual documented in-code, and pinned by an existing racing
  fixture. Recorded as a follow-up candidate for its own wave (needs
  its fixture updated with it).
- `bin/ddev-as-opencode` `--opk-ensure-shared` (`find -print0 | xargs
  chmod g+w`, NO gate): inspected, not applicable — runs unprivileged
  as the agent user (chmod on non-owned targets fails EPERM; no root
  operand), best-effort by design.
- `sh/staged-write.sh` `agent_home_sane`: already walks every
  component — the shape this fix adopts.
- `install.sh` sites (881, 1504/1547/1579, 2436–2450): single controlled
  operands with chain gates (0.0.39h F2 era) — conforming.

Docs (L3): no doc claims the recheck's leaf-only scope (grepped
security-model/sharing-group/manage-projects — no recheck wording);
nothing to amend.

Gates owed by a root-script behavior change (RM-0077): unit suite +
both e2e suites run on the fix — results recorded in the chain.
