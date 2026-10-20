# Resolution — pr-00211 (release 0.0.55 full-scope review)

Status: open — a F1 implemented; F2–F37 await disposition (follow-up
waves; maintainer prioritization pending).

Chain: [review-a.md](review-a.md) — full-scope snapshot (10 reviewer
subagents, 37 findings). Base v0.0.55 @ ad9467d.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a F1 (HIGH) | **implemented** | `fd13a19` | race + spaces pins, sabotage red→green, class sweep — detail below |

## Evidence detail

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
