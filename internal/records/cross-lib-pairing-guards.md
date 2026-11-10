# Cross-lib pairing guards — the two-tier skew protection

> Status: **CURRENT** (living architecture reference). Decided in
> [issue #456](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/456)
> (filed from PR #455 review round a Q1; maintainer approved the hybrid on
> 2026-11-10). Builds on the #413/#452 core pairing guards. Branch:
> `feature/issue-456-cross-lib`.

## 1. Problem

The #413/#452 pairing guards pin exactly the functions the PAIRED CORE
defines (guard list == core definitions, both directions, enforced by
test riders). Functions the runs call from OTHER sourced libs were
deliberately outside (#455 a Q1 scoped the comments, #456 carried the
mechanism):

- `status.sh` resolves ui.sh checkout-first with a deployed `$LIBDIR`
  fallback — a deployed ui.sh predating `ui_kv_ok`/`ui_kv_bad` (the
  issue #158 shape) passed the core guard green while the verdict rows
  AND their `UI_ROWS_*` counters silently vanished; the summary tallied
  a broken report green.
- `update.sh`'s ui.sh fallback stubs fire only on a MISSING file — a
  present-but-skewed one rc-127'd a bare `ui_*` call mid-run under
  `set -e`: cryptic, no named cause, after earlier phases already ran.
- The #250 stub sweep had covered only the functions the ENTRY calls;
  functions the CORE calls (`agent_home_sane` — 14 gated sites;
  `xdg_shim_needed_for`; `ddev_migrate_gap`/`_export`;
  `ddev_rootless_bindmounts`) were unstubbed: a truncated lib aborted
  the run exactly as cryptically.

## 2. Decision — two tiers, two different pinning sets

**Tier 1, the paired core (#413/#452):** guard list == the core's
DEFINITIONS, both directions. Entry and core are same-vintage by
construction (one tree, one fetch), so the full definition set is the
right surface — internal helpers the entry never names directly are
exactly the helper-level skew #452 closed.

**Tier 2, cross-lib (#456):** guard list == the USED set — the union of
what entry AND core actually CALL. Pinning a lib's full definition set
here would refuse legitimately older deployed libs for functions the
run never calls; the used set is what the entry can vouch for. Three
mechanisms by surface:

1. **ui.sh consumers (status, update, install, config, doctor):** a
   used-set guard right after the resolver — any used `ui_*` function
   missing refuses loud BEFORE the first section/phase (exit 1; under
   status's fail-soft philosophy a wiring abort is not a verdict and
   must not collide with the `--short` probe codes). A MISSING ui.sh
   keeps each entry's documented legacy semantics (config/update:
   old-kit stubs so ancient installs stay configurable/updatable;
   status/doctor: loud abort; install: `kit_source`, see §3).
2. **Other cross-lib functions:** entry stub arms after the sourcing
   (#250 pattern) with per-surface semantics — loud for actions,
   no-op for advisories/stamps, fail-closed for policy gates,
   never-shadow for the xdg probes (rc such that a shim is never
   deployed on uncertainty).
3. **Fail-soft report surfaces (status):** `command -v` call-site
   guards + a COUNTED warn row (#165 idiom) — a truncated
   ddev-migrate/ddev-handover must degrade into a visible "not checked
   — outdated (fix: sudo opk update)" row, never a silently swallowed
   scan behind a green summary.

The load-bearing discriminator: **missing-FILE** (an old kit — compat
stubs or loud abort per the entry's contract) versus
**present-but-skewed** (a broken kit — refuse loud or count the
degradation; never proceed silently).

## 3. install.sh's C5 fallback retirement

The 0.0.45c C5 output-stub fallback (ui.sh-less `--yes` runs proceed
on stubbed output helpers) is retired: ui.sh rides `kit_source` like
the twelve other libs. A ui.sh-less fetched tree is a BROKEN FETCH —
proceeding with degraded output behind a green run is the #165
silent-degradation class. Contract change: ui.sh-less installs now
refuse loud at the sourcing instead of limping to their first prompt.

## 4. Rider discipline (what keeps this true)

- `test-ui.sh`: per-consumer used-set riders, BOTH directions over
  comment-stripped sources with the entry's own guard function removed
  from the call extraction (else the list matches itself), boundary
  anchored, emptiness-probed (#455 a C2); plus behavioral pairs in
  fresh children (real ui.sh passes; a truncated copy refuses naming
  the function).
- Cross-lib stub riders in the four core suites: iterate the libs the
  RUN actually sources (install: live from its `kit_source` lines +
  log.sh; the others: explicit lists) — NOT the whole `sh/` glob,
  whose wrapper-side scripts (ddev-terminal.sh, as-opencode-core.sh)
  define agent-shell hooks (`ddev()`, `note()`) that false-red as
  binary-name prose.
- Token extraction must keep line separation: `tr -d '[:space:]()'`
  concatenates a lib's definitions into one loop token and the rider
  goes vacuous — found by the #456 sabotage cycle, not by any green
  run (the L4 argument for sabotage-verify).
- Executed failure paths (L1): the status truncation gates are driven
  in fresh children against scratch truncated libs, warn row observed
  on stdout the way production renders it.
