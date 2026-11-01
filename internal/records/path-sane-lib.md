# path-sane.sh — one project-root policy gate

> Status: **IMPLEMENTED** — decided and shipped 2026-11-01 (issue #216,
> PR feature/issue-216-path-sane-lib). The policy function
> `project_path_sane` moved from two verbatim copies (install.sh's
> `do_plan_phase` + config.sh top level) into the leaf lib
> `sh/path-sane.sh`, sourced by both callers with fail-closed stubs.

## Context

`project_path_sane` bounds the recursive group baseline (chgrp -R +
setfacl -R, run as root over every project root) — the place where a
path bug has the kit's maximum blast radius. Until 0.0.58 it existed
twice, content-identical by pin (`tests/unit/test-project-paths.sh`
failed on drift, the PR #109 C15 guard). The duplication survived two
waves' dispositions ("own wave, not a drive-by" — PR #109 C15,
PR #211 a F32) on a chicken-and-egg argument: install.sh is streamed
via `curl | sudo bash`, has no siblings at startup, and needs the gate
before the library is deployed.

## Decision

Move the gate into `sh/path-sane.sh` (a leaf lib: defines the function,
no side effects) and source it from both callers:

- **install.sh** `kit_source`s it (line ~260) with a fail-closed stub;
  the fetch list carries the file. `kit_source` aborts loud when the
  lib is missing outright — the install refuses to run without its
  gate.
- **config.sh** sources it with the standard two-leg lookup
  (`$SCRIPT_DIR/../sh/` checkout copy first, `$LIBDIR/sh/` deployed
  fallback — same rules as staged-write.sh) plus a fail-closed stub.
- **update.sh** `KIT_FILES` and the `sh/deploy-lib.sh` manifest carry
  the file (enforced identical by `tests/unit/test-kit-files.sh`).
- The stubs are the old drift pin's successor: both must stay
  identical and fail CLOSED — rc 1 + a loud stderr line. A damaged
  library must refuse every project path, never allow them; callers
  treat rc 1 as "system path" and abort/skip. Pinned behaviorally in
  `tests/unit/test-project-paths.sh` (the stub cell executes the
  extracted stub).

## Deploy-order evaluation (the old chicken-and-egg, closed)

The fear was "install.sh needs the gate before the library is
deployed". Three facts dissolve it:

1. **Streamed installs fetch everything first.** install.sh's
   bootstrap (trap, KIT_BRANCH gate, fetch_kit definition) needs no
   kit file; at the "not a local checkout" branch `fetch_kit()`
   downloads the COMPLETE file list before any `kit_source` call runs,
   and the first `project_path_sane` call sits over 800 lines later
   (measured 807–872 depending on anchor: the gate's own kit_source
   at :265 / the first kit_source at :240 → the first call at :1072),
   deep inside the interactive `do_plan_phase`. Both streamed and
   checkout runs hold the full library long before the first call.
   (The old argument was true only for sourcing **config.sh itself** —
   a management script with side effects. A leaf lib is the
   established pattern; install.sh sources a dozen of them.)
2. **`opk update` from an older install heals.** The old installed
   update.sh fetches with its OLD list (without path-sane.sh), re-execs
   the freshly fetched copy (update.sh line ~287), and that copy's
   heal loop (`ensure_local_file`, ~line 297) re-fetches every
   KIT_FILES entry missing from the fetched tree before `lib_deploy`
   runs — the new entry lands in the same update.
3. **A genuinely missing lib fails closed everywhere.** install.sh
   aborts at `kit_source`; config.sh's stub refuses every path. The
   failure mode of a broken fetch is a loud refusal, never an ungated
   baseline.

Fetch-list position (head of the sh/ block, as issue #216 suggested
"very front") is convention, not load-bearing: the fetch completes
wholesale before the first source, so order only decides which 404
aborts first.

## Alternatives considered

- **Keep the duplication, sharpen the comments** (the C15/F32 status
  quo): zero deploy-order risk, but every future change to the gate
  keeps reasoning about two sites plus the drift pin. Rejected — the
  pin made the copies safe, not cheap.
- **Source config.sh's copy from install.sh**: config.sh parses args,
  sources install.conf and defines `die`/`banner` at top level —
  sourcing it from install.sh is side-effect soup. Rejected.
- **Inline the gate into `fs-baseline.sh`** (its closest consumer):
  couples the policy to one consumer; config.sh's projects/handover
  paths would source a baseline helper for a pure predicate. Rejected
  for the dedicated leaf lib.

## Consequences

- One copy of the security gate; changes to the policy reason about one
  definition site (plus the two stubs, which are 4 lines each and pinned
  identical). Blocklist changes carry two parity mirrors by design: the
  uninstall.sh reader blocklist (set-equality-pinned by
  `tests/unit/test-uninstall.sh`) and bin/opk's handover form filter
  (form arms, self-declared parity — `path-sane.sh`'s own comment
  asserts it back).
- The unit suite's drift pin became structural: the lib must define
  the gate, the callers must not (exactly one `project_path_sane() {`
  block each — the stub), wiring and stub behavior are pinned
  (`tests/unit/test-project-paths.sh`), and `tests/unit/test-uninstall.sh`
  extracts the writer blocklist from the lib.
- Shipped surface grows by one 644 lib (fetch list, KIT_FILES,
  deploy manifest, `docs/reference/files.md` row).
