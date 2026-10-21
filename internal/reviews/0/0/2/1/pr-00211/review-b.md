<!-- review-meta
ID: pr-00211
Snapshot: b
Subject: wave review of the a-wave fixes (37 dispositions, 56 commits)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: snapshot-a commit 2e7d781)
Diff: 2e7d781..6d082565
Date: 2026-10-21
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 5x GLM-5.3-Flash reviewer subagents, one per axis — S security/root-operand, M management surface, U install/update, T tests/pins, C commit-vs-claim/docs/bookkeeping (checkpoints under /tmp/opencode/pr-00211-review-b/checkpoints/, LAUNCH/RETURN 21:02-21:21 UTC)
-->

# Wave review — pr-00211 snapshot b — the a-wave fix diff

Wave-scope pass ("did the fixes break or lie?") over the a-wave: 56
commits `2e7d781..6d082565`, +1818/-112 across 18 shipped files, 13
unit suites, 2 docs pages, Makefile + CI workflow, dispositioning all
37 findings of [review-a.md](review-a.md) (33 implemented, 4
deliberately not done). Five reviewer subagents ran five axes; the
main agent re-verified every reported finding against the code before
it entered this snapshot — all 30 survived verification, none
retracted. Reported IDs were renumbered into the W-scheme; the
original axis ID is preserved in the Reported-by column.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| W1 | MED | uninstall.sh:418 + :174-180 | F28's rc-conditioned else arm is dead code: run_q ends in `\|\| true` and returns 0 unconditionally — a failed gpasswd still prints "Removed … from group" and logs the removal; the pin drives an rc-propagating run_q fake, never the real contract | M1 | yes (code read: run_q body, call site, pin) |
| W2 | MED | docs/reference/cli.md:217 vs install.sh:391 | cli.md's install table lists `-y` as an alias; install.sh's parser has no `-y` case and dies `unknown option: -y` — a doc lie on the primary entry command, invisible to the one-directional F36 pin | C1 | yes (grep parser + doc) |
| W3 | MED | management/update.sh:1493 + :1505 | F2 class sweep missed its own class in the file it fixed: `fs_baseline_root() { :; }` stays silent under an unconditional "group baseline refreshed" ui_success — config.sh's stub is loud (config.sh:235-238), the ddev_handover_root twin 600 lines up is loud (update.sh:869-877) | C2 | yes (code read, both siblings) |
| W4 | MED | resolution.md:55-60 vs tests | F30's deliberately-not-done rationale ("test-bypass-guard PINS the 755s") is false for 3 of 4 libs: bypass-guard pins shell-warn.sh only; log.sh via test-deploy-lib.sh:69; advisories.sh and ui.sh have no 755 pin anywhere | C3 | yes (greps over tests/) |
| W5 | MED | tests/unit/test-kit-cli.sh:814 | F24 pin sets `target=/home/oc/.config/opencode/settings.json` — a real-tree-shape literal in new test code; inert today (both arms FS-free) but breaks the sandbox shape (RM-0016 inert-literal rule) and sits off the enforced ratchet | T2 | yes (code read; arms traced FS-free) |
| W6 | MED | tests/unit/test-browser-bridge.sh:631-641 | F18 pin's "strip + prepend still work" assert cannot fail on a dead/no-op browser_bridge_write_conf — the fixture's original block satisfies it; only the foreign-comment-survival half discriminates | T6 | yes (assert-by-assert trace) |
| W7 | LOW | sh/fs-baseline.sh:195-199 | F1 component walk silently voids itself on an unnormalized root: with a trailing slash, `case "$_p" in "$_root"/*)` never matches (empirically confirmed) and the pass degrades to the pre-F1 leaf-only gate with no warning; all current callers pass project_path_sane-normalized roots | S1 | yes (empirical + caller walk) |
| W8 | LOW | bin/opk:224-228 + update.sh:774-778 | F17 staged temps `policy.json.opk-new.$$` are unregistered and uncleared on the failure/abort path — opk has no trap at all; update.sh's EXIT/INT/TERM cleanup trap + _tmp_track registry exist but the temp is never registered; the wave's own F12 class, at the F17 sites | S3+U2 | yes (code read, trap greps both files) |
| W9 | LOW | sh/ddev-handover.sh:440-456, 631-633 | F14 sweep stopped at the three `-R` pairs: four single-inode pairs (project-root handback/handover ×3, dev-owned root-inode handback) keep `chown/chmod … \|\| true` + unconditional success echoes | S5 | yes (code read, all four sites) |
| W10 | LOW | bin/setup-container-backend:135-137 | F16 validation passes digit-only overflow: a 20-digit all-numeric field survives the case gate and wraps in `$(( ))` (u32 kernel field); unreachable via useradd-written files — validation-completeness, not a live break | S6 | yes (case-pattern read) |
| W11 | LOW | management/uninstall.sh:362-363 | F27 sweep stopped at the consent arm: the no-markers arm calls `browser_bridge_remove` bare (rc ignored) and logs "wsl browser bridge removed (no wsl.conf content found…)" unconditionally — with the now-failing stub the audit log claims a removal that did not run | M2 | yes (code read) |
| W12 | LOW | tests/unit/test-kit-cli.sh:705-710 | The update.sh F2-sweep pin is presence-only (`[ -s ] && grep -q 'unavailable'`): it never executes the stub nor asserts rc — the "loud rc 1" claim for the update.sh twin is verified by message text only | T1 | yes (pin read) |
| W13 | LOW | tests/unit/test-fs-baseline.sh:394-397 | Spaces-walk drive `sh -c '… _fsb_pass …'` is unguarded under the suite's `set -e`: a walker regression aborts the whole suite before the summary tally instead of recording a FAIL (gates red, but skips every later pin) | T9 | yes (pin read, set -e traced) |
| W14 | LOW | tests/unit/test-uninstall.sh:557-558 | F27 extraction spans the declined-consent arm carrying a live `sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl`, and the eval subshell does not stub sudo — inert only while the prompt_yn stub answers `y`; one stub edit away from a real deletion on a kit-managed host | T10 | yes (sed range + arm trace) |
| W15 | LOW | resolution.md:366-367 | F2 sweep ledger text is stale: it still lists uninstall.sh's browser_bridge_remove among "remaining silent shapes" — F27 made it fail loud (`return 1`) in the same wave | C4 | yes (stub read) |
| W16 | LOW | resolution.md:218-223 | F12 sweep enumeration incomplete: `grep -rn mktemp files/` shows 45 hits in 12 files, the ledger enumerates ~8; six spot-checked sites are safe (inline rm or _tmp_track), so the conclusion stands — the enumeration as written is not the sweep | C5 | yes (grep re-run, 2 spot checks) |
| W17 | LOW | docs/reference/cli.md (config section) vs config.sh:131 | config.sh accepts `--yes\|-y` but its cli.md section documents neither — the same drift class F23 was closing (vacuously holds: no `--yes` row exists there) | C8 | yes (grep both sides) |
| W18 | LOW | resolution.md:430 (F1 gates line) | "unit suite + both e2e suites run on the fix — results recorded in the chain": no e2e results exist anywhere in the range's commit bodies or the resolution (only "e2e" hit is an unrelated F1-adjacent word) — an unfulfilled recorded gate for root-script behavior changes (RM-0077) | main agent (verification) | yes (grep over all 56 commit bodies + ledger) |
| W19 | INFO | bin/opk:228 + update.sh:778 | F17 changes inode semantics: `mv -f` replaces a symlink at policy.json where the old truncate-write followed it; fires only on the diverged/replace path whose UI announces the replacement — noting the delta | S4 | yes (code read) |
| W20 | INFO | management/config.sh:139 | The `status`-as-SUB consumption clobbers an already-set SUB: `config.sh git-config off status` silently becomes the read-only status view (toggle not applied); pre-wave the toggle ran and the token was ignored | M3 | yes (loop read, dispatch traced) |
| W21 | INFO | bin/opencode-as-opencode:102, 250-251 | Stale `%b` comments after F29's `%s` switch: :102 still explains "printf '%b' … so the \033 escapes render", contradicting the function body below it | M4 | yes (both comments read) |
| W22 | INFO | management/update.sh:649 | F2 sweep enumeration misses `browser_bridge_install() { :; }` — a mutator-named silent stub; unreachable-in-silence (the is_wsl stub at :648 keeps the block closed), but the "guards, not mutators" enumeration is not exact | U1 | yes (stub pair + call site read) |
| W23 | INFO | tests/unit/test-kit-cli.sh:719, 805 | F11/F24 sed end-anchors are a shipped marker comment / first `fi` — the F7 EOF-drift shape if the marker dies; currently non-vacuous (both failure modes trip loudly) | T3 | yes (anchors verified unique) |
| W24 | INFO | tests/unit/test-update-flags.sh:574-577 | Comment claims the OC164 block "is 23 lines since #211 a F17"; the extraction is 21 lines — bound (-le 26) still correct | T4 | yes (wc -l on the extract) |
| W25 | INFO | resolution.md (F17 evidence) | "Three legacy pins asserting the old direct-write literals were carried along (test-update-flags ×2 …)": only one write-literal pin exists there (:512, correctly updated to the mv form); substance right — no stale direct-write assertion remains | T5 | yes (pin walk) |
| W26 | INFO | tests/unit/test-browser-bridge.sh:637 | Dead disjunct: lowercase `managed by the opencode permissions kit (issues #91` never matches the actual `Managed by` text — the assert always falls through to the count arm | T7 | yes (literal vs fixture) |
| W27 | INFO | tests/unit/test-fs-baseline.sh:206-212 | W11's root arg changed `$_bstub/failmid` → `/nonexistent-opk-root` with no rationale in the diff; behavior-neutral (drives still discriminate) — a one-line comment would prevent re-litigation | T8 | yes (drives traced) |
| W28 | INFO | tests/unit/test-docs.sh:147-158 | F36's flag loop has no extraction tripwire: if parse_args disappears, the loop iterates zero times and the claim-drift guard silently passes | T11 | yes (loop read) |
| W29 | INFO | resolution.md:164 (F16 sweep) | The recorded sweep pattern `grep -n '\$((\$' bin/ sh/` matches nothing at HEAD — including the fixed site itself; the prose conclusion holds within bin/+sh/, the recorded pattern cannot reproduce it | C6 | yes (pattern re-run) |
| W30 | INFO | tests/unit/test-docs.sh:147-158 | F36's pin is one-directional (parser → docs): a documented alias the parser rejects (W2's exact shape) is invisible to it — a docs → parser direction would have caught W2 | C7 | yes (mechanism read; W2 as live proof) |

Severity counts: **0 HIGH, 6 MED, 12 LOW, 12 INFO** (30 findings).

## Key findings detail

### W1 (MED) — F28's honesty fix is wired to a runner that cannot fail

`run_q` (uninstall.sh:174-180) silences by design — its live arm ends
`"$@" >/dev/null 2>&1 || true`, its DRY_RUN arm is a plain echo; both
return 0 unconditionally. F28's fix (`5496327`) wrapped the gpasswd
call in `if run_q sudo gpasswd -d …; then` with an honest else arm
(stderr WARN + FAILED log) — dead code by construction. Every trigger
the fix's own comment names ("the success echo printed over a
silenced gpasswd failure") still produces the false "Removed … from
group" echo and the removal audit log: missing gpasswd binary (rc 127
swallowed), sudo denial, stale /etc/group lock, primary-group
membership (the new exact `grep -qF "($OPENCODE_GROUP)"` probe matches
via `id`'s groups list, then gpasswd -d refuses). The pin
(test-uninstall.sh:600) stubs `run_q() { return "$F28GP"; }` — an
rc-propagating fake that contradicts the real function's contract, so
the shipped wiring is never exercised (test-fidelity: the pin cannot
fail against the real run_q). Direction: capture gpasswd's rc outside
run_q (or route through the rc-propagating `run`), then re-pin through
the real runner. Provenance: wave-introduced (the if/else and the rc
claim are new; the rc-blind runner is pre-existing design the fix
wired into).

### W2 (MED) — cli.md promises an install alias the parser rejects

F23's rule was "every `--yes` that accepts `-y` lists it" — e3b187e
listed `-y` for install.sh too, but install.sh's parse_args has only
`--yes)` (:391); `install.sh -y` dies with `error: unknown option: -y`
(:463's catch-all). The alias exists only in update.sh:483,
config.sh:131, uninstall.sh:26. A scripted `… bash -s -- -y` (the
documented streaming entry, cli.md:212) aborts. The F36 pin (W28/W30)
reads the parser direction only, so the doc side of this lie is
unguarded. Direction: drop `-y` from the install row (or add the
alias — but that changes the parser, the doc fix is the honest
minimum). Provenance: wave-introduced.

### W3 (MED) — the F2 sweep missed its own class in the same file

update.sh's `--refresh` section: `[ -n "$_fsbl" ] ||
fs_baseline_root() { :; }` (:1493) — the exact silent-mutator shape F2
retired — under an unconditional `ui_success "group baseline refreshed
(chgrp + setgid + g+rw + default ACLs)"` (:1505). The same file's
ddev_handover_root twin 600 lines up IS loud, its comment citing
"#211 a F2 sweep" (:869-877), and config.sh's fs_baseline_root stub is
loud (:235-238). The resolution's sweep paragraph
("Remaining silent `() { :; }` shapes are guards, not mutators") is
false as written. Trigger: fs-baseline.sh missing from both lookup
sites (damaged deploy) + `opk update --refresh` → success line and
audit entry over a pass that never ran. Provenance: site pre-existing
(72d474a, present at the wave base); the false sweep claim is
wave-introduced. Also unenumerated in that paragraph: update.sh's
stamp stubs (:878-879, guards — fine) and browser_bridge_install
(W22). Direction: loud stub like the siblings + correct the ledger.

### W4 (MED) — F30's "standing pin" rationale overstates coverage

The deliberately-not-done rationale for the 755 sourced-only sh/ libs
rests on "test-bypass-guard PINS the 755s … changing the manifest
would fight a standing pin". The four libs are advisories.sh, log.sh,
shell-warn.sh, ui.sh (deploy-lib manifest :114-129). test-bypass-guard
pins shell-warn.sh only (:98, :154, git-mode :182); log.sh's 755 is
pinned by test-deploy-lib.sh:69; **advisories.sh and ui.sh have no
mode pin anywhere in tests/**. The disposition (keep 755, accepted at
0.0.49) can stand — the evidence backing it covers 2 of 4 libs.
Direction: weaken the rationale to name what is actually pinned, or
add the two missing pins. Provenance: wave-introduced (the rationale
text); the modes themselves pre-existing.

### W5 (MED) — real-tree literal in new test code (inert today)

The F24 pin's eval context sets `target=/home/oc/.config/opencode/settings.json`
(test-kit-cli.sh:814). Both driven arms are FS-free today (the
extracted block is the command -v guard; agent_home_sane is stubbed or
127-dies before any path use), and the enforced ratchet's real-tree
prefixes (/var/www/vhosts, /srv/other/outside) don't cover /home — but
the sandbox convention's inert-literal rule (RM-0016) forbids exactly
this shape: one future edit away from a live /home path in a suite
that runs on contributor hosts. Direction: `$WORK` or `/var/tmp`
value. Provenance: wave-introduced.

### W6 (MED) — half of the F18 pin cannot fail

The F18 pin's second assert claims "the fresh kit block is written
(strip + prepend still work)" — but its passing condition (one
`Managed by the opencode permissions kit` line) is already true in the
untouched fixture: the marker-less kit block carries that line, and
`browser_bridge_write_conf` doing nothing at all leaves it green
(plus W26's dead lowercase disjunct). Only the first assert (foreign
comment + `[boot]` survive) discriminates; a regression that silently
stops writing the block after stripping passes. Direction: assert the
fresh block's `-- end` marker (absent from the fixture by design).
Provenance: wave-introduced.

## LOW findings (compact)

- **W7** — the F1 walk's `case "$_p" in "$_root"/*)` gate never matches
  when the root carries a trailing slash (GNU find emits normalized
  children — empirically confirmed: `find r/` → `r/sub`, pattern
  `r//*` → no match), silently degrading the pass to the leaf-only
  gate. Every shipped caller feeds project_path_sane-normalized roots
  (`${1%/}` + `//`/dot rejection, config.sh:307ff / install.sh:930),
  so this is a defense-in-depth void for future callers, not a live
  break. Direction: `_root=${_fsbp_root%/}` once in the worker, or
  fail loud on an unnormalized root. Wave-introduced.
- **W8** — the F17 temps: in bin/opk (no set -e, no trap, no
  _tmp_track anywhere in the file) a kill or chmod/mv failure between
  printf and mv strands a root-owned `/etc/openchamber/policy.json.opk-new.$$`
  forever; update.sh HAS the EXIT/INT/TERM cleanup + _tmp_track
  registry (:55-67) but never registers the temp — a set -e abort
  (sudo tee/chown/chmod/mv failure) strands it the same way, and each
  run picks a fresh pid. The live file is strictly safer than before
  (rename-only flip); the residue is the wave's own F12 class at the
  F17 sites. Direction: `_tmp_track "$_ocp_tmp"` in update.sh;
  best-effort `rm -f` on the non-success path in both. Wave-introduced.
- **W9** — four F14-shape sibling pairs unfixed (sites pre-existing,
  sweep gap): ddev-handover.sh:440-442 (typo3 dev-owned handback),
  :445-447 (typo3 root handover), :454-456 (root-file types handover),
  :631-633 (dev-owned root-inode handback) — each `chown/chmod … || true`
  + unconditional success echo; the fixed `_dhb_ok` pattern sits 25
  lines above the last of them. Direction: extend the honest-flag
  pattern to the four single-inode pairs.
- **W10** — F16's gate `case "$s$c" in *[!0-9]*|0?*|"")` passes a
  20-digit numeric field into `$(( ))` where it wraps (kernel field is
  u32); only hand-crafted root-written junk reaches it. Direction:
  length-cap the fields. Wave-introduced (residual).
- **W11** — the no-markers bridge arm: bare `browser_bridge_remove`
  call + unconditional success log; with F27's now-failing stub the
  audit log lies. Audit-truth only (no user-facing echo; library is
  removed moments later anyway). Wave-introduced leftover.
- **W12** — the update.sh handover-stub pin greps the stub's text but
  never executes it (its config.sh siblings are executed with rc
  asserts) — a `return 1` → `return 0` regression with the echo kept
  passes. Wave-introduced.
- **W13** — unguarded `_fsb_pass` drive under the suite's set -e: a
  walker regression aborts the suite pre-tally (gates red, skips the
  remaining pins — the fail-loud-with-tally shape every sibling drive
  uses is `|| rc=$?`). Wave-introduced.
- **W14** — F27's sed range includes the declined-consent arm's live
  `sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl`; sudo is
  unstubbed in the eval subshell. Inert only because prompt_yn
  answers `y`; the sandbox shape for extract-and-eval pins (controlled
  environment, RM-0017's sibling concern) says stub sudo or bound the
  extraction. Wave-introduced (latent).
- **W15** — resolution F2 paragraph lists browser_bridge_remove as
  remaining-silent; F27 made it `return 1` in the same wave. Ledger
  text fix. Wave-introduced.
- **W16** — F12's sweep enumeration lists ~8 of 45 mktemp hits in
  files/; spot-checks found no leak (inline rm / _tmp_track / trap
  contexts), so the conclusion holds — widen the enumeration or re-run
  to completion. Wave-recorded.
- **W17** — config.sh's `--yes|-y` (:131) is undocumented in its
  cli.md section; same drift class F23 closed for the other three
  commands. Pre-existing.
- **W18** — the resolution's closing gates line claims both e2e suites
  ran "on the fix" with "results recorded in the chain"; no such
  results exist in the 56 commit bodies or the ledger (only "e2e"
  hit: an unrelated word in the F11 message). RM-0077's gate for
  root-script behavior changes is open, not discharged. Wave-introduced
  (the claim); the release gate (RM-0091) independently owes both
  suites before tag.

## INFO findings (compact)

- **W19** — `mv -f` replaces a symlink at policy.json where the old
  write followed it; only on the announced replace path. Wave-introduced,
  no action requested.
- **W20** — `status` token clobbers a set SUB (config.sh:139):
  `git-config off status` renders the status view with the toggle not
  applied (pre-wave: toggle ran, token ignored). Not silent (wrong
  output is visible), neither error nor request. Wave-introduced.
- **W21** — stale `%b` comments (opencode-as-opencode:102 contradicts
  the `%s` body it describes; :250-251's parenthetical outdated).
  No behavioral impact (colors are literal ESC bytes). Wave-introduced.
- **W22** — `browser_bridge_install() { :; }` (update.sh:649)
  unenumerated by the F2 sweep; unreachable-in-silence via the is_wsl
  stub. Enumeration exactness. Site pre-existing.
- **W23** — F11/F24 extraction end-anchors (shipped marker comment /
  first `fi`) are EOF-drift shapes; both currently fail loudly, not
  vacuously. A line-count bound (OC164's shape) would drift-fail at
  the extraction. Wave-introduced.
- **W24** — comment says the OC164 block is 23 lines; it is 21 (bound
  -le 26 unaffected). Wave-introduced.
- **W25** — F17 evidence says three carried-along legacy pins
  (test-update-flags ×2); only one write-literal pin exists there and
  it asserts the NEW mv form. Substance right, count wrong.
  Wave-introduced text.
- **W26** — dead lowercase disjunct in the F18 pin's second assert
  (never matches `Managed by`). Wave-introduced.
- **W27** — W11's root arg swap (`/nonexistent-opk-root`) lands
  behavior-neutral but unexplained; add the one-line rationale.
  Wave-introduced.
- **W28** — F36's loop silently passes if parse_args vanishes
  (zero-iteration); `[ -n "$flags" ] || fail` tripwire. Wave-introduced.
- **W29** — F16's recorded sweep pattern matches nothing at HEAD
  (brace-less `$((start + count - 1))` at the fixed site); the prose
  conclusion holds within bin/+sh/ — record a pattern that can match
  (`grep -n '\$((' bin/ sh/`). Wave-recorded.
- **W30** — F36's pin reads parser → docs only; W2 is the live proof
  of the blind side. A docs → parser direction closes it.
  Wave-introduced.

## Retracted / ghost findings

None — all 30 reported findings survived main-agent verification.
(One near-retraction: W8 was reported independently by two axes
(S3 security, U2 install/update) with overlapping scope; merged into
one finding, both contributions kept in the detail.)

## Clean verdicts (axes' verified-clean areas, spot-checked)

- **F1 walker core** — peeling correct at every depth incl. operands
  directly under the root; walk runs per-operand immediately before
  the act (L5 items 1-2); skip-on-symlink-parent semantically right;
  spaces pinned through the real pass; the race pin drives a real
  find-swap replay. (W7 is the root-form edge, not the walk itself.)
- **F12 registration** — all three sourcing hosts define _tmp_track +
  registry + traps; guard covers standalone sourcing; plain rm
  covers the normal path.
- **F18 stripper core** — writer emits exactly 8 inner lines, bound
  fires on the 9th and stops before foreign content, both strip paths
  byte-identical, block shape frozen since introduction. (W6 is the
  pin's second half, not the stripper.)
- **F13/F15/F16 core** — three honest linger arms; readlink -f with
  honest degradation to the pre-fix behavior on rc 1; malformed-field
  rejection + counted warn after the loop. (W10 is the overflow edge.)
- **F2 config.sh, F24, F26, F8, F9, F25, F3, F29, F10, F11 core** —
  loud stubs abort before every success line under set -eu; usage gate
  breaks no documented shape (W20 is the SUB-clobber edge); deepened
  default chain verified live both ways; ddev-migrate rc verified live;
  note() callers carry no %b reliance.
- **F4/F5/F6/F7/F33/F34 core** — three honest arms with grep -qFx '*'
  detection (specific-path entries cannot satisfy); first-wins loops
  preserve the LIBDIR-only fallback and break correctly; umask skip
  mirrors its twin; the xdg stub is defined after lib sourcing (real
  probe wins) and errs never-shadow in both arms; the --refresh hint
  prints once outside the only-binary block; header matches the
  40-entry manifest. install.sh's 15-line diff is exactly F4's claim.
- **Tests corpus** — gate placement 13/13 before the summary; the
  cfe12f4 stale-capture class respected everywhere else; extraction
  anchors verified exact at HEAD; F13's pin implements the empty-PATH
  discipline; both carried-along F17 write-literal pins assert the NEW
  stage+mv form; no new hunk mutates outside scratch + sanctioned temp.
- **Bookkeeping** — review-a.md's only in-range edit is the allowed
  Resolution pointer; INDEX row consistent pre-b; disposition rows
  ≤ 120 cols; all 31 cited SHAs exist as ancestors of 6d082565; every
  fix/test commit cites `#211 a F<n>`.
- **Docs/build** — F19's four sudoers rules match the template
  exactly; F22's channel wording matches every Pages one-liner; F20's
  targets exist, are in the `test:` chain (confirmed live by this
  session's `make test`, which executed both), workflow steps
  untouched; F21's German is gone with no other German words
  remaining; 17336fc's re-pointed targets all exist; 6d08256's
  allow-arm adds a new $-anchored literal without weakening either
  original arm.

## Run provenance

- Tree: working tree at 6d082565 (branch release/0.0.55, clean);
  base of the reviewed wave 2e7d781 (snapshot-a commit) over
  v0.0.55 @ ad9467d.
- Reviewer fan-out: 5 subagents (glm-5.3-flash), one per axis
  (S security/root-operand, M management surface, U install/update,
  T tests/pins, C commit-vs-claim/docs/bookkeeping), checkpoint
  discipline per RM-0086/0092 — side files with LAUNCH/RETURN
  timestamps, window 21:02:23-21:21:06 UTC. Main agent (GLM-5.3)
  re-verified all 30 findings by code read / empirical probe
  (W7's slash-form case tested in a scratch dir); 0 retractions.
- Gates run on this host (kit-managed checkout, agent user opencode,
  UID-separated) during this review: `make test` rc=0 (shellcheck +
  unit suites, including the two F20-chained suites test-pages and
  test-rules-index-parity — F20's wiring confirmed live);
  `make check-version` rc=0 (stamp 0.0.55). E2e suites NOT run in
  this session; see W18 — the chain's recorded e2e evidence for the
  root-script fixes does not exist, and the release gate (RM-0091)
  owes both suites at baseline regardless.
- Finding provenance split: wave-introduced 25, pre-existing 5
  (W3, W9, W16, W17, W22 — older sites the wave's class sweeps
  should have covered), unstated 0.

## Recommendation

**Fix wave owed before the PR.** No HIGH and no fix-induced regression
of a main path: the wave's central claims (F1 walker, F18 bound, F17
atomicity, F5/F7 update semantics, F11 gate) held up under re-verification.
What the wave broke or lied about is smaller and concrete: one honesty
fix wired to a runner that cannot fail (W1 — the only finding that
fully reopens its snapshot-a finding's defect), one doc lie on the
install entry command (W2), one same-file sweep miss (W3), one
rationale overstatement (W4), and two pin-quality MEDs (W5, W6) —
plus the W18 gates debt: both e2e suites must actually run before the
release gate can close. The LOW/INFO tail is one normal fix wave
(ledger text W15/W16/W24/W25/W29, comments W21/W24/W27, pin polish
W12/W13/W14/W22/W23/W26/W28/W30, edges W7/W9/W10/W11/W17/W19/W20).
Per the stop rule, any code-touching disposition extends the loop
with a micro review (snapshot c).
