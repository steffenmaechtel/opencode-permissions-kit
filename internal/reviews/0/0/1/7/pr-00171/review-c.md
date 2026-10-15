# Code Review — opencode permissions kit — 0.0.49, snapshot-c micro wave review (0.0.49b fix wave: C1 atomic umask deploys + C2 comment rider)

> Resolution: [resolution.md](resolution.md)

- **Date:** 2026-10-12
- **Reviewer:** GLM-5.3 (OpenCode v2 agent), run in the repo session at the
  maintainer's request (provenance: this session produced none of the
  reviewed waves — both commits under review are the maintainer's).
  Single lead pass, no subagents — the wave diff is small (+181/−6 across
  4 code/test files, plus 1 docs-only commit), every claim was verified
  against full-file reads, every recorded sabotage was independently
  re-derived on a scratch clone, and two derived probes beyond the
  recorded set were run (mode-argument mutation, decoy call site).
- **Tree reviewed:** `feature/issue-163-corrupt-binary-status` @ `12b9840`
  (VERSION 0.0.49), working tree clean. **Wave under review:** the 0.0.49b
  fix wave, `e3ab8f6..12b9840` — `cb33e98` (C1: shared
  `copy_file_atomic <src> <dst> <mode>` in `sh/secure-binary.sh`, both
  umask deploy sites routed through it, fallback twins; C2: deploy-lib.sh
  comment rider) and `12b9840` (docs: resolution stem-b rows C1–C4, W5
  sentence + W1 line-number corrections, README index).
- **Result:** **1 LOW, 3 INFO. No new MED/HIGH — the C1 fix is verified
  implemented and effective.** All five recorded sabotages reproduce with
  their exact counts (2/1/2/2/4). The LOW (F2) is a pin-coverage gap, not
  a defect in the shipped behavior: the `644` mode argument at both call
  sites is pinned nowhere — a `644→600` mutation stays green across every
  suite including e2e. Under the revised stop rule the chain's next move
  depends on F2's disposition: fixing the pin touches test code (one more
  converging micro round), record-only dispositions close the 0.0.49
  chain now.

## Method

- Full read of the wave diff and every touched region in context:
  `sh/secure-binary.sh` (whole file — the new helper against
  `copy_binary_atomic`'s shape), the umask deploy sites with their
  surrounding phase bodies (`install.sh` `do_deploy_phase` :1786–1804 incl.
  the plain-statement phase calls at :2497–2499; `update.sh` :697–712),
  both fallback-twin blocks (`install.sh` :280–286 after `kit_source`;
  `update.sh` :384–393 with the `_sbl` gate), `sh/deploy-lib.sh` (whole
  file — C2's comment in the manifest loop), `etc/umask.sh` (the deployed
  content), `test-secure-binary.sh` §5–6 (whole file — stub reuse, pin
  placement before the summary gate), `test-bypass-guard.sh` (whole file —
  the six new wiring pins in suite order).
- Sabotage re-derivations on a scratch clone (clone of the branch @
  `12b9840`, both touched suites green at baseline, tree restored clean
  and re-run green after each sabotage): update.sh wiring reverted to the
  in-place `sudo cp` + `chmod` → exactly **2** FAILs (helper-call pin +
  no-in-place pin); install.sh wiring reverted → exactly **2**; helper
  reverted to in-place cp+chmod → exactly **4** (killed-cp bytes,
  failing-mv rc, failing-mv bytes, mode-at-mv); rm-cleanup legs deleted →
  exactly **2** (both temp-litter pins); chmod moved after the mv →
  exactly **1** (the mode-ordering pin). All match the resolution C1
  row's recorded 2/1/2/2/4.
- Derived probes beyond the recorded set: fallback-definition line
  deleted from update.sh → exactly 1 FAIL (caught); **mode argument
  `644→600` at BOTH call sites → 0 FAILs** in any suite (F2); decoy third
  `copy_file_atomic` call site with mode 600 added to install.sh → 0
  FAILs (F3).
- Empirical shell semantics: the old install shape's failure behavior
  probed under `set -e` (a failing cp aborts before any following log
  line — rc 1, no output; basis for F1). e2e umask assertions read from
  `tests/e2e/run.sh` (:583–614: `grep -q shell-warn.sh` content check +
  `test -f` existence check — **no mode assertion**; F2's blast radius).
- L2 class sweep re-run: `grep -rn 'sudo cp\|_sudo cp' files/` — every
  remaining site classified (atomic-helper temps, sudoers/staged-write
  temp legs, the W5 restore temp, jsonc/theme data payloads, `cp -a`
  payload migrations, `|| true` backups); no in-place cp onto an
  executed/sourced path remains.
- L5 operand inventory: the helper's operands are the root-owned
  `/etc/profile.d` tree (destination + pid-suffixed sibling temp — not
  pre-creatable by the agent) and the root-owned fetched-tree source;
  no agent-writable operand in the new paths. Tests write only to their
  `mktemp -d` scratch (sandbox policy respected).
- Gates re-run by this review: `sh tests/check-host.sh` OK, **all 34 unit
  suites** green (touched: test-secure-binary 31/0, test-bypass-guard
  31/0), `make lint` green, `make check-version` green (0.0.49). E2e
  corroborated from the same-day workspace logs: the 23:29:12 pair —
  started 40 s after the `cb33e98` commit — **301/301 + 47/47**, clean
  summaries, umask checks PASS ("umask script deployed", "umask profile
  re-deployed"); the docs commit `12b9840` landed mid-run but touches
  only `docs/design/review/`, so the shipped code under test is identical
  to the fix tip. e2e-ddev not owed (no ddev-path delta in the wave).

## Per-commit verdicts

| Commit | Claim | Verdict |
|---|---|---|
| `cb33e98` | atomic umask profile deploys via `copy_file_atomic` (0.0.49b C1) + C2 comment rider | Implemented and effective — sibling temp in the target dir (same fs ⇒ rename), mode before the mv, `rm -f` on every failure leg; both sites fail loud in their house shapes (update.sh `die`, install.sh `echo`+`exit 1`); fallback twins match the sibling helpers' pattern; class sweep clean; sabotages 2/1/2/2/4 reproduced. **F2's unpinned mode argument and F3's missing count pin live in this commit's pins; F1's false historical claim lives in its message** |
| `12b9840` | docs: resolution rows C1–C4, W5/W1 corrections, README index | Rows match the code and the sabotages; C2's comment-only rider correctly does not extend the loop; C4 record-only with rationale; **the C1 row's "the old shape even logged 'umask profile installed' over a failed cp" aside is false (F1)** |

## Findings index

| ID | Severity | File:line | Summary |
|---|---|---|---|
| F1 | INFO | resolution C1 row + `cb33e98` message | False historical claim: under `set -eu` (install.sh:46) and the plain phase call (:2499), the old shape never logged over a failed cp — the failing cp aborted first (probed); correction owed in the resolution's next edit |
| F2 | LOW | `test-bypass-guard.sh:130–133, 149–152`; `e2e/run.sh:583–614` | The deployed mode `644` is pinned nowhere: a `644→600` mutation at both call sites stays green in every suite (unit pins grep the call prefix only; e2e checks existence + content, not mode) — the silent-unreadable-profile loss the helper's own header names would ship undetected |
| F3 | INFO | `test-bypass-guard.sh` (new pins) | No count pin on `copy_file_atomic` call sites — a decoy third site (mode 600) passes green; W6's own `-eq 4` rationale applies verbatim to the new helper |
| F4 | INFO | `test-secure-binary.sh` §6 | The §6 mode discrimination (explicit 640 vs cp-natural 644) collapses under an invoking umask of 027 or 007 (cp-natural of the 644 source is exactly 640) — pins stay green but stop discriminating; the house already pins umask where mode discrimination matters (`test-ddev-as-opencode.sh:49`, `umask 022`) |

## Details

### F1 (INFO) — the resolution and commit message misdescribe the old install failure shape

The C1 resolution row says install.sh now fails via `echo`+`exit 1`
"(house shape; the old shape even logged 'umask profile installed' over
a failed cp — now loud)", and the `cb33e98` message carries the same
claim. It is false for the shape the commit replaced: install.sh has
`set -eu` at :46, `do_deploy_phase` is called as a plain statement
(:2497–2499, deliberately — the comment there documents that no
condition context may wrap the phases), and the old `sudo cp` +
`sudo chmod` + `log` stood as plain statements in the phase body. A cp
returning nonzero therefore aborted the install **before** the log line;
probed empirically (`bash -ec 'cp <missing> <dst>; echo LOG'` — no LOG,
rc 1).

The old shape's real gaps — both correctly closed by the fix — were:
(a) a cp **killed mid-write** (the #163 reachability: no rc at all, the
process is dead) left the truncated profile with no output whatsoever;
(b) a failing cp aborted with only cp's/sudo's own stderr, no
kit-context message. The new `|| { echo …; exit 1; }` adds the message;
the atomicity removes (a). Only the historical characterization is
wrong. L3 claim-audit class, record-only: correct the aside in the
resolution's next edit (the snapshot itself never made the claim — its
C1 describes the killed-mid-write shape accurately).

### F2 (LOW) — the 644 mode argument is pinned nowhere

The wiring pins grep the call prefix
(`copy_file_atomic "$SCRIPT_DIR/etc/umask.sh"` /
`copy_file_atomic "$FILES_ROOT/etc/umask.sh"`) — the mode argument is
not part of any pin, and §6's behavioral pins exercise the helper with
640 in scratch, not the production 644 at the real sites. Verified by
sabotage: `644→600` at **both** call sites → 0 FAILs in test-bypass-guard
and test-secure-binary; the e2e suite cannot catch it either — its umask
checks are `grep -q shell-warn.sh <profile>` and `test -f <profile>`
(run.sh:583–614), no mode assertion.

Why it matters: the helper's own header (and both call-site comments)
name the failure this parameter prevents — "a cp-natural mode under a
stricter root umask (077) would deploy an unreadable profile that
non-root shells silently skip". A future edit that "hardens" the profile
to 600 (or typos 444) ships exactly that silent protection loss with
every gate green; nothing reports it, and the next update re-deploys the
same wrong mode. Unpinned load-bearing claim on a protection layer —
the 0.0.45a C1 class (call-site wiring unpinned), narrowed to the mode
argument. Fix shape: widen the two wiring pins to carry the mode (grep
for `opencode-permissions-kit-umask.sh 644` per script), or add an e2e
`stat -c %a` assertion at :613; one string either way.

### F3 (INFO) — no count pin on the new helper's call sites

`copy_binary_atomic` got `-eq 4` in 0.0.49a W6 precisely so that "adding
a fifth site must be a conscious pin update, not a silent pass". The new
helper's pins are presence-only (`grep -Fq`): a decoy third
`copy_file_atomic` call site — with mode 600 — added to install.sh
passes both touched suites green (verified). Any future file deployed
through the helper escapes the review discipline the binary helper
already has. Rides F2's one-string fix naturally (`-eq 1` per script, or
`-eq 2` repo-wide on the quote-carrying pattern).

### F4 (INFO) — §6's mode discrimination depends on the invoking umask

§6 discriminates the explicit mode from the cp-natural one via
640-vs-644 (source `chmod 644`, test umask assumed 022 → cp-natural
644). Under an invoking umask of 027 (or 007) the cp-natural mode of a
644 source is exactly 640: the happy-path mode pin (6a) and the
mode-ordering pin (6d) stay green but stop discriminating — a
chmod-after-the-mv revert would also show 640 at rename time (S5's
sabotage becomes invisible to the pin). CI is unaffected (runners use
0022); this is a local-run fidelity note. The house pattern exists:
`test-ddev-as-opencode.sh:49` sets `umask 022` before mode-sensitive
assertions. Fix shape: `umask 022` at the top of §6 (or derive the
expected natural mode from `umask`).

## Verified clean (no finding)

- **C1 mechanics:** sibling temp in the destination directory (same
  filesystem — the rename contract; the W2 `staged_write` rejection
  recorded), mode applied before the mv, `rm -f` cleanup on every
  failure leg, old entry byte-identical on both failure legs (pinned),
  `mv -f` over a destination symlink replaces rather than writes
  through (riding hardening, same as `copy_binary_atomic`).
- **Loud failure shapes:** update.sh `die "umask profile re-deploy
  failed (atomic deploy)"`; install.sh `echo … >&2; exit 1` — both
  consistent with their house shapes, and the fallback twins echo their
  own error before the caller's message when neither checkout nor
  LIBDIR copy of secure-binary.sh exists (near-unreachable; same
  semantics the other helper twins already have).
- **Fallback-twin placement:** after `kit_source` (install.sh) and gated
  on `_sbl` (update.sh), matching the `copy_binary_atomic` twin line
  for line; `kit_source` still aborts on a file missing outright.
- **Class sweep:** no in-place cp onto an executed/sourced path remains
  in `files/` (pattern `sudo cp|_sudo cp`; remaining sites are
  temp-staged helper legs, data payloads, backups, payload migrations).
- **Manifest/fetch consistency:** the helper lives in the already-shipped
  `sh/secure-binary.sh` (manifest 644, fetch lists unchanged) — no
  test-kit-files delta owed.
- **Pin hygiene (L4):** all new pins sit before their suite's summary
  gate (§6 before the `--- summary ---` block; the wiring pins inside
  the suite body), and every recorded sabotage discriminates (counts
  above).
- **Docs duty:** no docs page describes the umask deploy mechanics
  (uninstall.md references the profile's removal, unchanged behavior);
  resolution and README index rows landed with the fix.
- **Version discipline:** no VERSION bump; `make check-version` green.

## Gates

- Re-run by this review: `sh tests/check-host.sh`; **all 34 unit suites**
  green (test-secure-binary 31/0, test-bypass-guard 31/0); `make lint`
  green; `make check-version` green (0.0.49).
- Corroborated from same-day workspace logs (23:29:12 pair, started 40 s
  after the fix commit; the mid-run docs commit touches `docs/` only):
  e2e **301/301**, rootless **47/47**, umask checks PASS. e2e-ddev not
  owed (no ddev-path delta).

## Recommendation

No MED/HIGH — the 0.0.49b fix wave holds; C1 is implemented and
effective with every recorded sabotage reproduced. **F2 is the
maintainer's judgment call**, the same shape 0.0.49b's C1 was: a
one-string pin widening (carry the mode in the two wiring pins, or an
e2e `stat` assertion) plus optionally F3's `-eq` count and F4's `umask
022` — one small commit that touches only test code and therefore owes
one more (immediately converging) micro round — or dispositioned
record-only, in which case the 0.0.49 chain closes here: F1 rides the
next resolution edit either way (docs-only), F3/F4 record cleanly.
