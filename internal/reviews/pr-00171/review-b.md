# Code Review — opencode permissions kit — 0.0.49, snapshot-b micro wave review (0.0.49a fix waves: W1 advice rows + W2/W5/W6 atomic lib deploys)

> Resolution: [resolution.md](resolution.md)

- **Date:** 2026-10-12
- **Reviewer:** GLM-5.3 (OpenCode v2 agent), run in the repo session at the
  maintainer's request (provenance: this session produced none of the
  reviewed waves — all four commits under review are the maintainer's).
  Single lead pass, no subagents — the wave diff is small (+174/−14 across
  6 code/test files, plus 2 docs-only commits), every claim was verified
  against full-file reads, and every recorded sabotage was independently
  re-derived on a scratch clone (0.0.49a precedent).
- **Tree reviewed:** `feature/issue-163-corrupt-binary-status` @ `d0bc10d`
  (VERSION 0.0.49), working tree clean. **Wave under review:** the 0.0.49a
  fix waves, `ad7a4ca..d0bc10d` — `2e5598c` (W1: name the working binary
  repair in both warn rows), `2deedd2` (docs: resolution row W1),
  `9797169` (W2 atomic per-entry lib deploys + W5/W6 riders),
  `d0bc10d` (docs: resolution rows W2/W5/W6 + the README resolution-format
  mini template).
- **Result:** **1 LOW, 3 INFO. No new MED/HIGH — both fix waves verified
  implemented and effective.** Under the revised stop rule the chain's next
  move depends on C1's disposition: record-only/comment-only dispositions
  close the 0.0.49 chain (0.0.45f precedent); a code fix for C1 owes a
  0.0.49c micro pass. C1 LOW: W2's class sweep stopped at the lib_deploy
  manifest — the kit's umask profile itself still deploys through a plain
  in-place `sudo cp` + `chmod` onto `/etc/profile.d/` (`update.sh:698`,
  `install.sh:1793`), a script every login shell *sources*: an update
  killed mid-write there leaves exactly the #163 shape (truncated content,
  intact mode) on a protection layer, and the resolution W5 row's claim
  "no in-place cp onto an executed path remains anywhere in repo code" is
  falsified by those two sites.

## Method

- Full read of the wave diff and every touched region in context:
  `management/status.sh` advisory block (:240–329) and the three staying
  `sudo opk update` advice rows (:881/894/901), `sh/deploy-lib.sh` (whole
  file, manifest included), `tests/unit/test-deploy-lib.sh` §4, the
  `test-status.sh` D1 block (:1296–1352), the `test-bypass-guard.sh`
  count pin (:108–121), e2e `run.sh` 12l in context.
- Repair-path verification for W1 (the advice must name a working repair):
  `bin/opk:169–179` maps `upgrade-opencode` → `update.sh --yes
  --only-binary`; `current_opencode_major` (:1011–1036) falls back to the
  `OPENCODE_MAJOR` install.conf stamp when the probe is empty (both the
  missing and the corrupt shape); `install_binary` (:925–942) probes the
  fresh CANDIDATE, not the corrupt deployed file, then deploys through
  `copy_binary_atomic`. The advice is accurate for both rows it now sits on.
- L2 sweeps: `sudo cp`/`*_sudo cp` over `files/` — every remaining site
  classified (temp-staged helpers, data payloads, backup copies, the
  stand-in `install`); advice-string sweep over `files/` for dead-end
  `opk update` fixes — the three staying rows verified semantically
  (stand-in re-applied by every update via `browser_bridge_install`,
  "re-deploys the library" is literally `lib_deploy`, the xdg-open shim
  ships in the manifest).
- Sabotage re-derivations on a scratch clone (clone of the branch, all
  three touched suites green at baseline, tree restored clean after):
  corrupt-row advice revert → exactly **1** FAIL (test-status D1/#163);
  missing-row revert → exactly **1**; both → **2**; deploy-lib reverted to
  in-place cp → exactly **4** direct FAILs (killed-cp bytes, failing-mv rc
  + bytes, 440-at-mv); rm-cleanup legs deleted → exactly **2** (both
  temp-litter pins); chmod-moved-after-mv (derived beyond the recorded
  set) → exactly **1** (the mode-ordering pin); one `copy_binary_atomic`
  call site deleted from install.sh → exactly **1** FAIL
  (test-bypass-guard). All match the resolution's recorded counts.
- Empirical shell semantics: GNU `install` unlinks the destination before
  copying (blocked-copy probe: dst absent, not truncated); in-place `cp`
  preserves an existing destination's mode while the temp+mv path lands
  umask-natural mode (C4); line-length ratchet re-checked — content widths
  114/90/35 after the leading-whitespace strip, limit 120, no baseline
  change (the wrapped corrupt-row string keeps its leading space).
- Gates re-run by this review: `sh tests/check-host.sh` OK, **all 34 unit
  suites** green (full rc-based sweep), `make lint` green,
  `make check-version` green (0.0.49). E2e corroborated from same-day
  workspace logs on **both** fix tips — the 22:50 pair (post-`2e5598c`)
  and the 23:03 pair (started 28 s after the `9797169` commit):
  **301/301 + 47/47** each, zero Failed/Skipped summary lines, all three
  12l checks PASS including the full-advice grep; e2e-ddev not owed (no
  ddev-path delta in the wave).

## Per-commit verdicts

| Commit | Claim | Verdict |
|---|---|---|
| `2e5598c` | name the working binary repair in the status warn rows (W1) | Implemented and effective — both rows (corrupt #163 block, missing 0.0.48c sibling) now advise `sudo opk upgrade-opencode`, verified repairable end-to-end (method above); pins discriminate (sabotages 1/1/2 reproduced); e2e 12l greps the full advice, PASS in both logs; cli.md documents the detection semantics without quoting advice strings — no docs drift |
| `2deedd2` | docs: resolution row W1 | Accurate dispositions and boundary; C3's stale line numbers ride here (record-only) |
| `9797169` | atomic per-entry lib deploys + pin/test riders (W2, W5, W6) | Implemented and effective — sibling-temp same-fs rename, mode before the mv (pinned both directions: in-place revert 4 FAILs, chmod-after-mv 1), loud failure legs with temp cleanup (rm-legs deleted → 2), W5 restore leg temp+mv, W6 count pin `-eq 4` on the quote-carrying pattern (one-site deletion → 1 FAIL); **C1's missed class siblings and C2's comment claim live in this commit's sweep/comment** |
| `d0bc10d` | docs: resolution rows W2/W5/W6 + README mini template | Rows match the code and the sabotages reproduce; the W5 row's "no in-place cp onto an executed path remains anywhere in repo code" sentence is over-broad — the falsifier is C1 |

## Findings index

| ID | Severity | File:line | Summary |
|---|---|---|---|
| C1 | LOW | `management/update.sh:698`, `files/install.sh:1793` | W2 class-sweep residual: the umask profile still deploys in-place (`sudo cp` + `chmod`) onto `/etc/profile.d/` — sourced at every login, the #163 shape on a protection layer; falsifies the resolution W5 row's "anywhere in repo code" claim |
| C2 | INFO | `sh/deploy-lib.sh:66–68` | Comment claims "the next run's cp overwrites" a stale `$$`-suffixed temp — the next run has a different pid and temp name; stale temps are never cleaned (inert litter). L3 class |
| C3 | INFO | resolution W1 row + README index | The staying rows are cited at status.sh:871/884/891 — pre-fix numbering; the fix's own +10 lines moved them to 881/894/901, so the pointers were stale when written |
| C4 | INFO | `sh/deploy-lib.sh` (`-` entries) | Behavior change: `-` manifest entries (jsonc templates) now land umask-natural on every deploy where in-place cp preserved an existing destination's mode — matches the documented contract, recorded |

## Details

### C1 (LOW) — the umask profile's own deploy is the remaining in-place site of the #163 class

`update.sh:697–699` (and the install twin `install.sh:1793–1794`):

```sh
sudo cp "$FILES_ROOT/etc/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
```

Scenario: the same interrupted-update reachability issue #163 recorded for
the binary and 0.0.49a W2 closed for the lib manifest. An update killed
during that `cp` leaves a truncated `/etc/profile.d/opencode-permissions-
kit-umask.sh` with intact mode bits — and unlike `bin/opk` or
`management/update.sh`, this path executes on **every login shell** of
every user on the host. Outcomes range from a visible shell error line at
login to the silent case (truncation landing parsing-clean, e.g. inside a
comment, losing the umask line): the soft layer's group-protective umask
simply stops applying, with nothing reporting it. Heal: the next
`opk update` re-deploys the file — and W2 is exactly what makes that heal
trustworthy now (the repair tooling itself can no longer be the corrupted
part). LOW, matching 0.0.49a W2's own calibration: it needs the
interrupted run, it heals on the next update, and the blast radius is one
profile script.

Why a finding and not just a residual note: the resolution W5 row asserts
"with W2 landed, no in-place cp onto an executed path remains anywhere in
repo code." Under the wave's own class language that is false — the W2 fix
manifest atomically deploys *sourced* `sh/` libs (644) precisely because
sourced scripts count, and a profile.d script is sourced-at-login. The
sweep recorded in the W2 row (`lib_deploy`'s manifest) is accurate; the
"anywhere" sentence in the W5 row over-generalizes it.

Boundary worth recording when C1 is dispositioned (verified, deliberately
not the same class):

- the data `sudo cp`s (`opencode-deny-all.jsonc` at update.sh:1269 /
  install.sh:2371, tui themes at update.sh:1374–1375 / install.sh:2425–2426,
  the `|| true` config backups): JSON data, not executed; a truncated
  config is loud at the next parse and re-deployed by update.
- the WSL stand-in's `install -m 755` (wsl-browser-bridge.sh:179):
  verified empirically that GNU `install` unlinks the destination before
  copying, so a killed run leaves a MISSING `powershell.exe` — detectable
  by `[ -f ]` shapes and re-applied by every update — not the silent
  corrupt-with-intact-mode shape the class is about.
- the agents-migration `cp -a` (install.sh:2179): payload migration into
  agent-owned data, not an executed path.

Fix shape if implemented: the same temp+mode+mv at both umask sites (or a
small shared helper), with one representative killed-cp/failing-mv pin
pair mirroring `test-deploy-lib.sh` §4.

### C2 (INFO) — stale-temp comment overstates the cleanup

`deploy-lib.sh:66–68`: "A run killed between the legs leaves one
`$$`-suffixed temp behind — inert, and the next run's cp overwrites it."
The next run has a different pid, hence a different temp name
(`dst.tmp.$$`); it deploys beside the stale temp, not over it, and nothing
glob-cleans old temps. Still harmless — the stale file is root-owned,
never referenced by name, never executed — so this is litter, not risk.
L3 claim-audit class: reword to the honest shape ("inert litter; nothing
executes it"), or pre-clean `rm -f "$_dl_dst".tmp.*` before the cp (with
the usual operand hygiene on the glob).

### C3 (INFO) — resolution/index line numbers pre-date the fix they cite

The W1 resolution row and the README index row place the staying
`sudo opk update` advice at status.sh:871/884/891 — the tree `ad7a4ca`
(the reviewed snapshot's numbering). The fix's own ten added comment lines
moved them to 881/894/901, and both docs commits landed after the fix, so
the pointers were stale at writing time. Content-identifiable (exactly
three `fix: sudo opk update` rows exist); record-only correction in the
resolution's next edit.

### C4 (INFO) — `-` entries reset mode on redeploy (contract-conforming)

Verified empirically: an in-place `cp` over an existing destination
preserves the destination's mode (600 stayed 600), while the temp+mv path
lands the cp-natural, umask-masked source mode (644). For the two `-`
manifest entries (the jsonc templates) this means an admin-modified mode
on a previously deployed copy now normalizes back to source-under-umask on
every deploy. That matches the function's documented contract ("`-` =
keep the copied mode — data templates whose mode follows the source under
the umask"), so it is a normalization in the contract's direction — the
same rider-benefit family as the 440-mode atomicity W2 records for
sudoers.template. Recording the behavior change; no action requested.

## Verified clean (no finding)

- **W1 advice accuracy:** `sudo opk upgrade-opencode` repairs both shapes
  end-to-end (wrapper mapping → `--yes --only-binary`, major resolution
  through the install.conf stamp when the probe is empty, candidate-side
  probing in `install_binary`, atomic re-deploy). The pre-fix in-code
  claim ("naming the fix that repairs it") is now true.
- **W1 sweep boundary:** the three staying `sudo opk update` rows advise
  library-content repairs a plain update does perform (stand-in, lib
  re-deploy, xdg-open shim — all re-applied by `lib_deploy`/
  `browser_bridge_install` on update). No other dead-end advice string
  remains in `files/` (grep sweep).
- **W2 mechanics:** sibling temp in the destination directory (same
  filesystem — the rename contract holds), mode applied before the mv,
  all three failure legs loud with temp cleanup, old entry byte-identical
  on both failure legs (pinned), `mv -f` over a destination symlink
  *replaces* it rather than writing through (safer than the old cp's
  follow-the-link — a riding hardening, not a regression).
- **L5 operand inventory:** all new operands sit on the root-owned
  `$LIBDIR` tree (or scratch dirs in tests); pid-suffixed temp
  pre-creation is not attacker-feasible there; parents are created
  root-side by `_dl_sudo mkdir -p`. No agent-writable operand anywhere in
  the new code paths.
- **Pin hygiene (L4):** all new pins sit before their suite's summary
  exit gate (test-deploy-lib §4 before `--- summary ---`; test-status D1
  before the tail `exit 1`); every pin observed through the production
  observation path (rendered rows / on-disk bytes and modes, not stderr).
- **W6:** exactly four `copy_binary_atomic "` call sites in install.sh
  (verified by grep); the tightened `-eq 4` pin fails on a single-site
  deletion (reproduced, exactly 1 FAIL).
- **Line-length ratchet:** green with no baseline change; the wrapped
  corrupt-row string keeps the leading space explicit (0.0.39o C1 class
  respected).
- **Docs riders:** the README resolution-format mini template matches the
  de-facto shape of the current resolutions; cli.md needed no change
  (documents semantics, not advice strings); no VERSION bump in the wave.

## Gates

- Re-run by this review: `sh tests/check-host.sh`; **all 34 unit suites**
  green; `make lint` green; `make check-version` green (0.0.49).
- Corroborated from same-day workspace logs on **both fix tips**
  (22:50 and 23:03 runs): e2e **301/301**, rootless **47/47**, zero
  Failed/Skipped lines, 12l ×3 PASS each (full advice string). e2e-ddev
  not owed (no ddev-path delta).

## Recommendation

No MED/HIGH — the 0.0.49a fix waves hold. **C1 is a judgment call for the
maintainer**, same shape as 0.0.49a's W2 was: a two-site completion of the
interrupted-write class (temp+mode+mv at `update.sh:698` /
`install.sh:1793` + one representative pin pair), rider-able before the
PR, or deferred with the boundary recorded — in which case the resolution
W5 row's "anywhere in repo code" sentence must be corrected either way
(docs-only). C2 is a comment reword or a pre-clean glob (comment-only
rounds close the loop); C3 rides the next resolution edit; C4 is
record-only. Dispositions touching no review-relevant code close the
0.0.49 chain; a C1 code fix owes the 0.0.49c micro pass.
