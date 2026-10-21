<!-- review-meta
ID: pr-00211
Snapshot: c
Subject: wave review of the b-wave fixes (30 dispositions, 32 commits)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: snapshot-b commit f439832)
Diff: f439832..47954da
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 5x GLM-5.3-Flash reviewer subagents, one per axis — S security/root-operand, M management surface, U install/update, T tests/pins, C commit-vs-claim/docs/bookkeeping (checkpoints under /tmp/opencode/pr-00211-review-c/checkpoints/, LAUNCH/RETURN 2026-10-21 22:29-22:52 UTC)
-->

# Wave review — pr-00211 snapshot c — the b-wave fix diff

Wave-scope pass ("did the fixes break or lie?") over the b-wave: 32
commits `f439832..47954da`, +530/-78 across 22 files (9 shipped files,
12 unit suites, docs/reference/cli.md, resolution.md), dispositioning
all 30 findings of [review-b.md](review-b.md) (30 implemented) plus the
post-b spaced-path race follow-up (`82cdd4a`). Five reviewer subagents
ran the same five axes as snapshot b; the main agent re-verified every
reported finding against the code before it entered this snapshot —
all 11 survived verification, none retracted. Reported IDs were
renumbered into the W-scheme; the original axis ID is preserved in the
Reported-by column.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| W1 | MED | uninstall.sh:500-502 + :614-616 | b W1's own sweep claim is false as written: silenced `run_q sudo userdel -r` still ends in unconditional "User … removed." echo + log, and the audit-log arm logs "audit log removed" BEFORE the `run_q sudo rm -rf` — the exact lie shape the wave fixed at gpasswd, mischaracterized by the resolution as "bare best-effort cleanup calls by design" | M1 | yes (code read, both sites; resolution text re-read) |
| W2 | LOW | sh/fs-baseline.sh:156 | b W7's `/` refusal message names the wrong operand: `shift 2` at :143 renumbers positionals, so inside the refusal branch `${_fsbp_root:-$2}` expands to the post-shift `$2` — the second find-expression word, never the refused root; the pin greps only `*never*` | S1 | yes (code read + empirical probe of the prologue) |
| W3 | LOW | management/update.sh:777-783 | b W8's `_tmp_track "$_ocp_tmp"` sits AFTER the staging tee: under `set -eu` (:38) a tee that creates the temp then fails mid-write (ENOSPC) aborts BEFORE registration — stranding the unregistered root-owned temp, the exact residue class W8 closes | S2+U3 | yes (code read: order tee→register, set -eu, trap registry) |
| W4 | LOW | tests/unit/test-docs.sh:170-173 | b W30's reverse direction has no empty-extraction tripwire — the exact W28 class the same hunk fixed on the sibling direction: if cli.md's `## install.sh` heading drifts, the sed range matches nothing, the loop iterates zero times and the reverse claim-drift guard silently passes | T1 | yes (extraction read; verified 5 flags + -y at HEAD, so silent-pass not permanent-red) |
| W5 | LOW | tests/unit/test-install-args.sh:97-99 | the new `-y` drive runs `parse_args -y` bare under the suite's `set -e`: a reverted alias aborts the whole suite pre-tally instead of recording a FAIL — the file's own documented convention for abort-shaped drives is the `( parse_args "$@" )` subshell (:66-87, 0.0.42g C1) | T2 | yes (drive + convention read; mitigations noted below) |
| W6 | LOW | resolution.md:92 + 82cdd4a | Follow-ups prose overstates the race fixture: "spaces in every component" is false — `proj` and `a` (and the scan root) carry no spaces; only `dir two`, `has space.txt`, `victim dir` do; same phrase in the commit body | C1 | yes (git show 82cdd4a fixture paths) |
| W7 | INFO | bin/opk:225 | opk's staging `printf > "$_ocp_tmp"` has no rc gate and opk has no `set -e`: a partial write (create ok, write fails) flows through chown `|| true` into the chmod+mv guard — which succeeds — installing truncated policy.json content under ui_success; update.sh's twin is rc-covered by set -e + pipeline semantics | S3 | yes (code read; `grep set -e bin/opk` empty) |
| W8 | INFO | bin/opk:224-233 | the abort half of b W8 stays open at opk: a kill between staging (:225) and the chmod/mv guard (:233) still strands the root-owned pid-suffixed temp (no trap; no later-run cleanup) — disclosed by the in-code comment and the resolution row, hence INFO | M2 | yes (code read; disclosed-residual framing confirmed) |
| W9 | INFO | bin/setup-container-backend:141-146 | the `???????????*` cap (11 `?`s) rejects only ≥11 digits: a 10-digit value above u32 max (4294967295, e.g. 9999999999) still passes — the comment equates the 11-digit cap with u32; W10's crash shape IS closed (bash arithmetic is 64-bit) | U1 | yes (pattern counted; comment read) |
| W10 | INFO | bin/setup-container-backend:141-146 | undocumented loosening inside a fix framed as pure gap-closing: a zero-START field (`u:0:1000`) was rejected by the a-wave concat gate (`"01000"` matched `0?*`) and is now accepted (`0` matches no alternative); arguably safer, but the comment drops the old rationale silently | U2 | yes (both gate generations traced) |
| W11 | INFO | resolution.md:70 | b W18's "rootless 47 at baseline" has no independently recorded pre-wave comparator — review-a.md:175 records the rootless gate only as rc=0 (the 303 e2e count IS corroborated at :182); 47 is consistent at all three in-ledger sites, just unanchored | C2 | yes (review-a.md re-read) |

Severity counts: **0 HIGH, 1 MED, 5 LOW, 5 INFO** (11 findings).

## Key finding detail

### W1 (MED) — the b W1 sweep claims a design intent the file contradicts

The b W1 fix made the gpasswd site honest and its resolution recorded
the sweep as
`grep -rn 'if run_q' files/` → gpasswd the only rc-conditioned call,
"the remaining run_q uses are bare best-effort cleanup calls by
design." Two of the remaining uses are not best-effort cleanup:

- **:498-502** — `run_q sudo pkill -9 -u` (cleanup, fine), then
  `run_q sudo userdel -r "$OPENCODE_USER"` followed by unconditional
  `echo "User … removed."` + `log "user removed"`. `run_q` ends
  `|| true` (:174-181) and the file has no `set -e` (:163) — a failed
  `userdel -r` (the comment's OWN scenario two lines up: "userdel
  refuses while ANY process of the user runs"; a straggler spawned in
  the `sleep 1` window) still prints and logs the removal. This is the
  primary destructive op of the whole block, not a cleanup rider.
- **:613-616** — the audit-log arm logs "audit log removed" BEFORE
  `run_q sudo rm -rf /var/log/opencode-permissions-kit` runs, then
  echoes "Audit log removed." unconditionally — the log-then-fail lie
  shape (audit trail claims an outcome before knowing it).

Both sites are pre-existing (untouched by the wave's diff); what is
wave-introduced is the sweep claim: the ledger states a design intent
("by design") the file contradicts — the same false-invariant shape as
b W3/b W4 (both MED). Provenance: sites pre-existing; the claim
wave-introduced. Direction: honest arms at both sites (rc captured
outside run_q like the gpasswd fix) + correct the ledger; the class
sweep for the fix wave is `grep -n 'run_q' files/opencode-permissions-kit-lib/management/uninstall.sh` — walk EVERY hit, not just `if run_q` conditionals.

## LOW findings (compact)

- **W2** — the refusal behavior is correct (rc 1, nothing walked; all
  shipped callers run under `set -e`/`set -eu` so the rc aborts loud),
  only the diagnostic names the wrong word: the S agent's empirical
  probe (`_fsb_pass "refuse" "/" -type f -- chmod g+w`) printed
  `refusing scan root 'f'`. The pin (test-fs-baseline.sh) asserts rc 1
  and greps `*never*` only, so it cannot catch it. Direction: capture
  the original root before the `shift 2` and print that; extend the
  pin's message assert. Wave-introduced (the message is new in d071a16).
- **W3** — narrow window (tee must create then fail mid-write; every
  abort after :783 is trap-covered), hence LOW; the fix's own comment
  (:180-182) describes the set -e abort class but the registration
  only starts covering it AFTER staging completes. Direction: move
  `_tmp_track "$_ocp_tmp"` above the tee — `_tmp_track` only appends
  to the registry and the trap's `rm -f` tolerates absent paths, so
  registering before the file exists is safe. Fix-induced.
- **W4** — the sibling direction's tripwire (:160-162,
  `[ -z "$_f36_flags" ]`) is the exact template; one line
  (`[ -z "$_f36_docflags" ]` … anchor-drift FAIL) closes it. Same-hunk
  class miss, wave-introduced.
- **W5** — mitigations: the pre-existing `parse_args --yes` drive
  (:92) shares the bare shape, and the resolution's "sabotage
  red-by-abort" claim is accurate (the suite DOES go red on a reverted
  alias — by aborting, skipping every later pin). The finding is the
  convention gap: the file documents the subshell as the shape for
  exactly this hazard. Direction: wrap the new drive
  (`if ( parse_args -y ) 2>/dev/null; then …`), or leave with the
  tally-vs-abort tradeoff accepted in the resolution. Wave-introduced.
- **W6** — wording only; the pin itself discriminates (the parent-swap
  lands on `dir two`, and both sabotage claims hold structurally).
  Direction: "spaces in the swapped parent, the operand and the victim"
  or similar. Wave-introduced (post-b follow-up text).

## INFO findings (compact)

- **W7** — content-integrity gate would be
  `printf … > "$_ocp_tmp" || { rm -f "$_ocp_tmp"; ui_error …; exit 1; }`.
  Realistic trigger is ENOSPC on a full /etc (rare; system in deep
  trouble anyway). Fix-induced (a F17's staging introduced the ungated
  printf; the b W8 guard covers chmod/mv only). No action requested
  beyond noting.
- **W8** — kill-window residue, disclosed in-code ("opk carries no
  cleanup trap") and in the resolution row ("opk arm cleans"). A trap
  would change opk's failure semantics (a F37-adjacent tradeoff);
  noting it here keeps the residual visible. Fix-induced, disclosed.
- **W9** — the residual is the same unreachable-via-useradd-files
  validation-completeness class as W10 itself; a `[ "$s" -gt
  4294967295 ]`-style check (or 10-digit + value compare) would close
  it if the maintainer wants the comment to be exact. Fix-induced
  (residual of f194ce8's cap).
- **W10** — zero-start acceptance is arguably safer (the empty range
  is registered as occupied instead of skipped-and-allocated-over);
  the finding is the unstated delta: a comment sentence recording the
  intentional loosening would make the parser change auditable.
  Fix-induced.
- **W11** — no contradiction anywhere; the rootless count simply lacks
  the external anchor the 303 count has. Recording the baseline count
  at the NEXT e2e run would anchor it. Wave-introduced (the recorded
  number).

## Retracted / ghost findings

None — all 11 reported findings survived main-agent verification.
(One merge: W3 was reported independently by two axes (S2 security,
U3 install/update) with identical scope; merged into one finding, both
contributions noted.)

## Clean verdicts (axes' verified-clean areas, spot-checked)

- **b W7 normalization core** — the normalized `_fsbp_root` is used at
  BOTH consumption points (find walk :183, xargs worker root :227);
  `//`, `///` and empty inputs all normalize into the loud refusal;
  quoted string ops only, no new operand risk. (W2 is the message
  operand, not the gate.)
- **b W9 four ddev-handover pairs** — flag logic correct at all four
  sites (:445-446, :456-457, :471-472, :656-657), success echoes
  strictly gated; the sibling sweep is complete (every other
  chown/chmod in the file already flagged via `_dhr_ok`/`_dhb_ok`/
  `_dhp_ok`; remaining `|| true` sites out of class — rc-checked
  writes, stamp touch, read-only getent).
- **b W1 gpasswd wiring** — rc reaches the arms on every path
  (`sudo … >/dev/null 2>&1 || _grp_rc=$?` at :435; no set -e in the
  file regardless); DRY_RUN arm matches the run/run_q convention;
  audit log honest in every arm. The pin drives the REAL seam (sudo
  stub) across ok/fail/exact-name/DRY.
- **b W11 + W14** — no-markers arm if-wrapped with WARN + FAILED log
  (:364-372), else arm genuinely reachable (stub returns 1); the F27
  extract's sudo stub sits inside the subshell before the eval — the
  live `rm -rf` can never execute for real.
- **b W20 SUB gate** — empirically verified in dash AND bash
  (subagent ran the suite): `git-config off status` now dies at the
  F11 usage gate naming the stray token; `status`-after-set and
  `ACTION=status` shapes unchanged; no documented shape breaks.
- **b W2 parser alias** — `--yes|-y)` parses identically (single
  token, no value), catch-all intact; cli.md row matches; `-y` is the
  parser's ONLY short alias, so the reverse-F23 rule holds for the
  install row too. Pin red on revert.
- **b W3 loud stub** — plain command call site under `set -eu`:
  the stub's rc 1 aborts BEFORE `ui_success "group baseline refreshed"`
  (:1507-1520); remaining `() { :; }` shapes re-enumerated — log
  (best-effort logger), git_check_report (advisory), stamp stubs
  (documented guards), browser_bridge_install (W22 note accurate).
- **b W10 crash shape** — the 20-digit wrap/crash and the
  leading-zero-count octal gap are closed; normal shapes
  (`100000:65536`) pass; pin fixture extended 3→5 with a
  false-reject guard (alloc still moves).
- **Pin quality (T axis, all verified at HEAD)** — W4's manifest pins
  assert mode inside fixed strings (row/mode change → red); the F2
  pin EXECUTES both update.sh stubs (rc 1 + stderr, `_rc` reset every
  capture); W6's `-- end` marker is absent from the untouched fixture
  and the `\r\?` pattern matches under GNU grep 3.11 (tested) — a
  no-op writer goes red; W13's rc captures present on every drive in
  the diff (`_brc`, `F1RC`, `F1RRC`, `F1SPRC`, `F1SPDRC`); the
  82cdd4a race pins' find-seam fires (real find runs, then the
  deterministic parent swap), seam-fired asserts block vacuous greens,
  victim-600 vs 620 discriminates both sabotage directions; W24's
  OC164 comment/bound exact (28 lines measured, `-le 30`); W9's
  ddev-as-opencode drive covers ok/chmodfail/chownfail with the
  three byte-twin sites wiring-grepped; all new pins sit before their
  suites' summary gates; no new hunk mutates outside scratch +
  /tmp,/var/tmp.
- **Ledger (C axis)** — all 29 pointed SHAs exist in
  `f439832..47954da`; every fix/test commit cites the correct
  `#211 b W<n>`; evidence phrases match the hunks they describe
  (content-level check on every row); b W18's `—` (no code commit) is
  coherent — the discharge is recorded by ledger commits
  (aac8d67/f62bab0) with 303/47 consistent at all three in-ledger
  sites; review-b.md's only in-range edit is the allowed Resolution
  pointer (+2); INDEX.md untouched; zero rows >120 cols; exactly 30
  b-rows, W1-W30, sorted.

## Run provenance

- Tree: working tree at 47954da (branch release/0.0.55, clean); base
  of the reviewed wave f439832 (snapshot-b commit) over v0.0.55 @
  ad9467d.
- Reviewer fan-out: 5 subagents (glm-5.3-flash), one per axis (S/M/U/
  T/C), checkpoint discipline per RM-0086/0092 — side files with
  LAUNCH/RETURN timestamps under /tmp/opencode/pr-00211-review-c/
  checkpoints/, window 2026-10-21T22:29:14Z-22:52:10Z UTC. Main agent
  (GLM-5.3) re-verified all 11 findings by code read (S1 additionally
  re-derived empirically by the S agent and re-checked structurally);
  0 retractions, 1 merge (S2+U3 → W3).
- Gates run on this host (kit-managed checkout, agent user opencode,
  UID-separated) during this review: `make test` rc=0 (shellcheck +
  unit suites); `make check-version` rc=0 (stamp 0.0.55). E2e suites
  not re-run in this session: the b W18 discharge (e2e 303, rootless
  47, both rc=0, zero skips) ran at aac8d67 — and
  `git diff aac8d67..HEAD -- files/` is EMPTY (only unit-test and
  ledger commits since), so that evidence carries to 47954da for
  every shipped file. (W11 records the rootless count's missing
  pre-wave anchor.)
- Finding provenance split: wave-introduced 5 (W2, W4, W5, W6, W11),
  fix-induced 5 (W3, W7, W8, W9, W10 — residual gaps or deltas of
  this chain's own earlier fix output), pre-existing 1 (W1 — sites
  older than the chain; the false sweep claim on them is
  wave-introduced), unstated 0.

## Recommendation

**One small fix wave owed before the PR.** No HIGH, no fix-induced
regression of a main path: the b-wave's central claims (W1 gpasswd
wiring, W7 root normalization gate, W8 trap registration on the
covered paths, W9 honest flags, W10 crash closure, W20 gate, W2/W17
doc parity, W28/W30 tripwires, the 82cdd4a race pins) all held up
under re-verification, and the ledger is row-for-row honest about its
SHAs and citations. What remains: one MED ledger-vs-code contradiction
over two pre-existing run_q sites (W1), one wrong diagnostic operand
(W2), one registration-order window (W3), two pin-convention gaps
(W4, W5), one prose overstatement (W6), and five INFO notes/residuals
(W7-W11) that can also be dispositioned deliberately-not-done.
Per the stop rule, any code-touching disposition of W1-W5 extends the
loop with a micro review (snapshot d); a wave that only touches
ledger text and comments (W6, W10's comment, W11's anchor) closes it.
