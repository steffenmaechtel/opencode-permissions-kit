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
  functions the CORE calls (`agent_home_sane` — 13 gated sites;
  `xdg_shim_needed_for`; `ddev_migrate_gap`/`_export`;
  `ddev_rootless_bindmounts`) were unstubbed. Their failure modes
  split by call shape (#461 a Q5 corrected this narrative): plain
  statements under `set -e` aborted cryptically (the update.sh ui
  surface), while if-condition and tolerant-arm call sites
  (`|| true`, `|| return 0`, `$(…)`) swallowed the rc-127 as a
  SILENT skip behind a green run — the quieter and worse shape.

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

**The intra-lib callee window (#461 b B1):** per-function arms only
fire when a function is ENTIRELY missing — a tail truncation that
keeps the CALLER and kills a later-defined CALLEE arms nothing.
ddev-migrate.sh's gap (:157) and export (:389) both call
`ddev_migrate_latest_dir` (def :651) inside `$(…)` — a third call
site, :665 inside `ddev_migrate_import`, is not install-reachable
(the import is deliberately not part of the install, #461 c C2); a
cut anywhere in
the :158–:650 window leaves both callers defined and kills only the
callee, and the tolerant call arms (`|| return 0`, `|| true`)
swallowed the rc behind the shell's bare "not found" — the gap scan
and the export skipped with no counted row. The callee therefore
rides its OWN stub arm (install) / the db-dumps probe set (status,
#461 a S5). Class sweep over the install-sourced libs found one
further window — ddev-handover.sh `ddev_handover_root` (:593) calls
`ddev_handover_project` (:865) / `_back` (:754) — which degrades
LOUD (plain call under `set -e`, no tolerant arm): the refuse-loud
direction, deliberately left as is. The X1 fail-closed
`agent_home_sane` stub routes the 13 install-core gated sites —
plus the tui-plugin.sh twin (:44, reached through
`tui_plugin_sync_user`): a 14th install-reachable gate, #461 d D1 —
into skip arms whose texts name BOTH causes (symlink user-managed,
or the gate unavailable — #461 b B3): under truncation no operand is
a link, and the persistent log must not assert one. Accepted cost (#461 c
C3): the amended tui-plugin.sh text also renders in UPDATE runs,
where update.sh's permissive rc-0 stub means the arm is entered
only via the REAL gate — the gate-unavailable disjunct is then
vacuously present and the hint self-referential; the arm cannot
distinguish the causes by rc.

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
- Shape pins anchor the migrate stub arms at column 0 (#461 a Q4,
  #461 b B1 incl. the callee arm): an indented, nested copy fails
  the anchor — the first cut nested the stubs inside the registry
  arm, where they armed only when the registry was undefined.
- Executed failure paths (L1): the status truncation gates are driven
  in fresh children against scratch truncated libs, warn row observed
  on stdout the way production renders it.
