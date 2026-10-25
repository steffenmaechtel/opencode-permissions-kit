<!-- review-meta
ID: pr-00263
Snapshot: e
Subject: micro-wave review of the pr-00263 d-round fixes (backup sites, plugins loop, exact-count pins)
Scope: wave
Base: 0.0.57 @ 5171eb3 (snapshot d; the reviewed range ends at 054a39a)
Diff: 5171eb3..054a39a (4 commits; 3 review-relevant files + 3 test suites, +92/-33 code; resolution bookkeeping +108/-11)
Date: 2026-10-25
Reviewer: GLM-5.3 (house session, verification duty held in-session) + 2x GLM-5.3-Flash reviewer subagents (W mechanical sweep / Q quality)
Skills: opk-review-pass
-->

# Micro-wave review — pr-00263 snapshot e — the d-round fixes

> Resolution: [resolution.md](resolution.md)

Micro pass ("did the d fixes break or lie?") over the round that
dispositioned all 13 snapshot-d findings: three fix commits (uninstall
`116339b` — #246 site 7 + d Q2; install `755de9a` — d W1/W2/W3; tests
`a51874b` — d W4) plus the d-round resolution bookkeeping (`054a39a`).
Two reviewer subagents ran two axes (mechanical sweep, quality) on the
provider's fast tier; the main session re-verified every finding
against the code, re-ran the key coverage claims first-hand, and
executed one sabotage spot-check against the round's central pin.

Severity counts: **1 LOW, 3 INFO** — no MED, no HIGH. The d fixes
hold: all three exact-count pins recount clean first-hand (`_bk_fail`
= 10, `_dc_start_rc` = 5, `run sudo rm` = 0, zero comment-line
contamination), the BACKUP_DIR class sweep re-run independently comes
up empty, the plugins-loop interplay is correct, the stale-anchor grep
over tests/ + docs/ finds nothing, and the sabotage spot-check drove
the `= 10` pin's failure path red → restore → green. The findings are
ledger precision (W1) and convention residuals (W2/W3/Q1).

## Findings index

| ID | Sev | Location | One-line summary | Verified |
|---|---|---|---|---|
| W1 | LOW | resolution.md:181 (d W1+W2 evidence block) vs install.sh:2000-2001, 2478-2482, 2499-2503 | "Success keeps the original wording" overstates: two of three sites reorder/restructure the success announce, and all three log lines change shape on success ("backup:" → "backup attempt: … — verdict") — benign, deliberate-looking, but the ledger misdescribes the user-visible delta | yes (renders compared 5171eb3 → HEAD at all three sites; widened in verification — the re-render twin's log changes too) |
| W2 | INFO | test-install-args.sh:1128-1137 | Extract-eval recorder pin drives a degenerate label (`gitconfig-`) — `DEFAULT_USER` is never assigned in the suite; the resolution describes the accumulation as "label-a, label-b" | yes (no assignment exists; suite sets only `set -e`; pin self-consistent, discrimination unaffected) |
| W3 | INFO | uninstall.sh:164-170 | `run()` helper orphaned — the plugins-loop conversion removed its last two callers; kept as the file's run/run_q convention shape (d S2) | yes (zero call sites; `un_rc_q` echoes directly) |
| Q1 | INFO | uninstall.sh:408 | `_un_revert_failed=0` in the plugins-loop reset pair is a write-only store in its scope (reads at :821/:881 are dominated by later resets) — same pair-idiom as 12 sibling sites | yes (read/write map over the file) |

Provenance: W1 fix-induced (the d round's own ledger record of its
fix); W2/W3 wave-introduced (the d round's new pin / conversion);
Q1 wave-introduced store in a pre-existing pattern.

## Findings (reviewer output, verbatim)

### Axis W — mechanical sweep (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Resolution claims "success keeps the original wording"; two of three swept sites restructure/reorder their success announce (and W1's log line changes shape) | fix-induced |
| W2 | INFO | Extract-eval recorder pin drives a degenerate label (`gitconfig-`) — `DEFAULT_USER` is never assigned in test-install-args.sh; resolution describes the accumulation as "label-a, label-b" | wave-introduced |
| W3 | INFO | `run()` helper (uninstall.sh:164-170) is now dead code — the plugins ops were its last two callers | wave-introduced |

## Detail

### W1 — LOW: success-path announce restructured at 2 of 3 sites; resolution evidence block overstates preservation

Evidence — files/install.sh:2000-2001 (branch b; was `echo "Backup saved. Copied to $SYSTEM_BIN."` / `log "binary copied: $loc -> $SYSTEM_BIN (backup saved)"`):
```sh
echo "Copied to $SYSTEM_BIN. $_ocb_bk"
log "binary copied: $loc -> $SYSTEM_BIN ($_ocb_bk)"
```
files/install.sh:2478-2480 (was `echo "Default config installed (opencode.jsonc — backup saved)."`):
```sh
echo "Default config installed (opencode.jsonc) — .git/config blocked (soft). $_occ_bk"
...
echo "Default config installed (opencode.jsonc). $_occ_bk"
```
The resolution's d W1+W2 evidence block states "success keeps the original wording". True only for the re-render twin (install.sh:2500-2502, where `$_occ_bk="backup saved"` reproduces the old string byte-for-byte). Sites 1 and 2 reorder/restructure the success sentence (claim content preserved), and the branch-b success log now reads `(Backup saved.)` — capital B and trailing period inside the parens vs the old `(backup saved)`. Why it matters: the change looks forced by the restructure (the echo must follow `copy_binary_atomic`, so the appended slot moved to the end) and is benign, but the record misdescribes the user-visible delta — exactly the announce-reorder shape the sweep is told to catch. Trigger: every successful branch-b binary copy or existing-config replace.

### W2 — INFO: recorder pin exercises an empty-username label

Evidence — tests/unit/test-install-args.sh:1128-1137:
```sh
        eval "$_BKDEF"
        _bk_fail "gitconfig-$DEFAULT_USER"
        _bk_fail "sudoers"
        [ "$_BK_FAIL" = "gitconfig-$DEFAULT_USER, sudoers" ]
```
`DEFAULT_USER` is never assigned in test-install-args.sh (`grep 'DEFAULT_USER='` matches only message strings at :783/:785; the suite sets only `set -e` at :30, no `set -u`), so the driven label is the degenerate `"gitconfig-"`. The resolution's evidence block describes the pin as 'two failures accumulate to "label-a, label-b"'. Why it matters (mildly): the pin still discriminates — comma-join, order, and the accumulation shape are all exercised, and the comparison is self-consistent either way — but the suite drives a label shape production never produces. Unverified residual: whether a sourced shared lib assigns `DEFAULT_USER`; within the file itself it is unassigned.

### W3 — INFO: `run()` helper orphaned by the conversion

Evidence — files/opencode-permissions-kit-lib/management/uninstall.sh:164-170:
```sh
run() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    else
        "$@"
    fi
}
```
Word-boundary grep finds zero remaining call sites (`run_q` callers persist; only prose matches for `run `). Why it matters: none functionally — and the in-file run/run_q convention is a recorded deliberate shape (resolution d S2) — but the d conversion removed `run`'s last callers, leaving an unused helper. Not checked whether `make lint`/ShellCheck flags it.

## Coverage

**Covered, clean:** (1) BACKUP_DIR class re-swept first-hand — all 11 write sites enumerated (install.sh:723, 726, 728, 731, 735, 1394, 1843, 1949, 1989, 2470, 2492), every one rc-observed, zero `|| true` on any of them (resolution's "11 sites" + empty-grep claims verified against the file, not the record); extension to update.sh (backup copy at :1320 is fail-loud via `set -eu` — the :1325 "backup kept" claim is unreachable on failure; restore path :1344 observed), uninstall.sh and config.sh (no backup/recovery-material claims at all; all remaining `|| true` are probe idioms or comment-documented best-effort, incl. uninstall.sh:860 whose claim is scoped to the pin, not the dir). (2) uninstall.sh run-op sweep — zero rc-blind `run` invocations remain anywhere (stronger than the `run sudo rm = 0` pin); `un_rc_q` labels literal and double-quoted; loop interplay clean (guard-`continue` at :397-402 precedes the :407-408 reset, no iteration can hit a stale verdict, nothing reads `_un_partial` after the loop before the :475 reset; WARN >&2 + log at :414/:416; no success line invented; DRY_RUN shape byte-identical to the old `run`); `_un_revert_failed=0` reset at :408 is unread before the next section's reset but mirrors every sibling section's house shape. Operand provenance: `$BACKUP_DIR` mktemp, `$loc` fixed guarded list (:1970-1972), `$_un_dir` fixed two-element list with `agent_home_sane` chain-gate before the rm and `${_un_dir:?}` empty-guard — no menu input; `x/`, `x//` forms collapse harmlessly. (3) Pin arithmetic recounted at the files, zero comment contamination: `_bk_fail` = 10 (= 1 def :715 + 9 sites), `_dc_start_rc` = 5 (:328, :329, :339, :344, :346), `run sudo rm` = 0, `config backup FAILED…` = 2, `binary backup FAILED…` = 1, `no ACL recovery material` = 2; sed-extract ranges verified sound (`_BK_FAIL=""`…`    }` = install.sh:714-719, self-contained; plugins loop extract = lines 391-418, single `for _un_dir in` anchor, 28 < head-40, `un_rc_q "` count exactly 2 with the :404 comment not matching the quoted pattern); all new pins sit before their suites' summary gates (test-install-args.sh :1148 < :1157; test-uninstall.sh :1509 < :1540; test-container-backend.sh pin < :473). (4) Ordering verified at all three sites — backup copy observed before the overwrite it protects (:1989 < :1996; :2470 < :2476; :2492 < :2498); `_ocb_bk`/`_occ_bk` assigned in both arms before use under `set -eu`.

**Deferred / unverified:** whether ShellCheck (`make lint`) flags the orphaned `run()` (W3) — not run; whether any sourced lib in test-install-args.sh assigns `DEFAULT_USER` (W2) — within-file grep only, pin outcome unaffected either way.

### Axis Q — quality (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | INFO | `_un_revert_failed=0` at uninstall.sh:408 is a write-only store in its scope (dead store), kept for idiom parity | wave-introduced (pattern pre-existing) |

No HIGH/MED/LOW findings. Every enumerable claim I recountable verified exact; every new comment sentence is true against the code at HEAD; all new/changed pins discriminate.

## Detail

### Q1 (INFO) — dead store in the new plugins-loop reset
- **Evidence** — `files/opencode-permissions-kit-lib/management/uninstall.sh:407-416`:
  ```
        _un_partial=""
        _un_revert_failed=0
        un_rc_q "plugins rm" sudo rm -rf ...
  ...
        if [ -n "$_un_partial" ]; then
  ```
  `_un_revert_failed` is written at :408 but never read in this scope. The only reads in the file are :821 and :881, both dominated by later resets (:764, :840) — so :408's store is dead today.
- **Why it matters / why INFO**: zero behavioral impact, and the two-line reset pair is the file's established idiom — 12 sibling sites reset both vars together (:267-268, :293-294, :315-316, :336-337, :349-350, :367-368, :475-476, :494-495, :511-512, :530-531, :763-764, :839-840), most equally write-only. The wave line conforms to convention; removal would deviate from it. Recorded for the dead-code axis, no action implied. The commit message's "per-iteration `_un_partial`/`_un_revert_failed` reset" is factually accurate (both are reset).

## Verified clean (the checks that did NOT produce findings)

**Comment-truth (all six hunks)** — every new sentence true:
- install.sh :1986-1989 (W1): cp observed, `_bk_fail` feeds `_BK_FAIL`, summary degrades at :2680 (`INCOMPLETE: $_BK_FAIL`); announce degraded via `$_ocb_bk`, set in both arms before use.
- install.sh :2467-2470 + :2489-2492 (W2): "the re-render twin below shares this" — twin is converted identically; success wordings render as the originals ("Backup saved." / "(backup saved)").
- uninstall.sh :401-405: "failure WARNs and feeds the partial list; success stays quiet" matches `un_rc_q` (:195-202: failure appends `_un_partial`, no echo) plus the caller's WARN block (:413-416); "no success claim invented" — none added.
- test-container-backend.sh :462-463: "capture + default + three gate/print sites = 5" — exact: setup-container-backend :328 (capture), :329 (default), :339 (gate), :344 (WARN print), :346 (log print, socket var present).
- test-install-args.sh :1125-1127: "DRIVEN below (extract-eval, both arms)" — the drive exercises both branches of the `${_BK_FAIL:+…}` accumulator; "e2e drives install success paths, not failure arms" — grep over tests/e2e + docs for any backup-wording anchor: zero hits (stronger than claimed).
- test-uninstall.sh :1492-1494: "zero rc-blind `run sudo rm`" — `grep -c 'run sudo rm'` = 0 verified. Bare `sudo rm` sites (:325, :450, :859-860, :897) are conditional or rc-observing, pre-existing, outside the claim's stated class.

**Ledger (resolution.md at c3fcb7b)**:
- "11 BACKUP_DIR-writing sites" enumeration exact: :723, :726 (gitconfig x2), :728 (sudoers), :731 (usr-local-bin), :735 (lib tree), :1394 + :1843 (getfacl x2), :1949 (remove_shadow_binary), :1989, :2470, :2492 (the three swept) = 11; no unlisted writer exists.
- "`grep 'BACKUP_DIR' | grep '|| true'` over install.sh is now empty" — verified empty.
- d Q1: both named logs exist (`logs/e2e-20261025-225430.log`, `logs/e2e-rootless-20261025-225900.log`), tails read "Passed: 309" / "Passed: 47"; "zero skips" holds — no skip summary line in either tail, all 18+2 `skip` grep hits are scenario content or PASS titles; "opencode 2.1.4" present in both logs; "21:14–21:17Z" vs log name 221402 is consistent (log names local CET = UTC+1 on 2026-10-25). Fix-round logs (`*-221402.log`) also exist with matching mtimes.
- d Q3 recount **confirmed by diff walk**: 14 qualification sites across TEN suites — container-backend (#211 c W9), ddev-as-opencode (#211 b W7), docs (#256 a W1), e2e-sources (#224 b W1), fs-baseline (#244 b-S2 x2), git-config (#208 a W1 + b W3), kit-cli (#244 e-S1), rules-meta (#189 a W2), skills-lint (#235 b S3/c S1/b S4), uninstall (#243 b-S1). 049dd04's "nine suites" was the error; "the count 14 is correct" holds.
- Chain line: 13 findings = 1 MED (Q1) + 6 LOW (Q2, W1-W4, Q3) + 6 INFO (W5, W6, S1-S3, Q4) — matches the table. "Micro-wave review owed" was accurate at 054a39a (no review commit existed for `5171eb3..a51874b` then); c3fcb7b filled the d Q1/d Q3 placeholders with `054a39a` exactly as 054a39a's message promised.

**Commit-message recounts (all four)**:
- 116339b: `= 0` sweep ✓; invocation-anchored `un_rc_q "` excludes comments ✓ (no comment line matches); "11 rc-blind sites / site 7" internally consistent with the resolution's "10 in the a-wave, this one in the d round" (issue #246 itself is external, unverified in-repo).
- 755de9a: "for /usr/bin/opencode this cp is the ONLY backup attempt" ✓ — `remove_shadow_binary` case guard (install.sh :1944-1946) returns 0 for non-`.opencode` paths; "= 10 (def + 9 sites, was >= 7)" ✓ (def :715 + sites :723/:726/:728/:732/:736/:1954/:1992/:2473/:2495); "config backup FAILED x2" ✓ (`grep -cF` = 2), binary 1x ✓.
- a51874b: deletion arithmetic ✓ — 5 occurrences, removing capture+default leaves 3, old `>= 3` stayed green; new `= 5` discriminates.
- 054a39a: counts/zero-skips/warm-cache ✓ as above.

**Pin quality**: all discriminate. The extract-eval recorder: empty extract → `[ -n "$_BKDEF" ]` fails the pin; renamed/broken function → eval or call errors, rc gates the pin; delimiter change → comparison fails. The extracted body's `log` call may hit an undefined function in the harness — swallowed by `2>/dev/null`, accumulation happens before it, rc still gates (worst case false-FAIL, never false-PASS). PLGSEC extract: single `for _un_dir in` anchor (:391 only), loop spans ~28 lines vs `head -40` (12-line margin); truncation cuts anchors → fails loud, never vacuous; `= 2` invocation-anchored count is exact. All new pins sit before their summary gates (test-install-args.sh gate :1157, test-uninstall.sh gate :1541). Blind-spot rule: no bare line numbers in the new ledger text (the ":400-401" drift was dropped); every implemented d disposition carries its in-wave pin.

**Stale-anchor sweep**: repo-wide grep for the old wordings ("Backup saved. Copied to", "opencode.jsonc — backup saved", "(backup: $BACKUP_DIR", "opencode config replaced (backup:") over *.sh/*.md — only install.sh:1951, the pre-existing a-wave `remove_shadow_binary` line, untouched by this range and already conditional. Zero consumers in tests/e2e, docs/, tests/unit, tests/ux of either old or new backup wording.

## Coverage

Covered: comment-truth pass over all six hunks with surrounding-context reads; full resolution.md d-block ledger audit incl. ../logs existence, tails, skip scan, timezone and version claims; commit-message recounts for all four commits with arithmetic re-derivation; pin-quality analysis of all five new/changed pins incl. deletion simulation for each; repo-wide stale-anchor grep. Deferred: (a) issue #246's own 11-site list — external artifact, unverifiable in-repo, internal consistency checked only; (b) tree SHA `701b867` and `a51874b`-porcelain-clean claims — logs cannot be tied to tree SHAs from their content, taken on record; (c) `make lint`/reviews-lint "gates green" claims — not re-run (reader role, and outside the quality axis's recountable scope). Checkpoints at /tmp/opencode/pr-00263-e/checkpoints/Q-quality.md.

## Verification notes (house, GLM-5.3)

Every finding was re-verified against the code at c3fcb7b (the
reviewed range's code lines are identical at HEAD):

- **W1 verified and slightly widened**: resolution.md:181 reads
  "success keeps the original wording" — the renders compared
  5171eb3 → HEAD at all three sites: branch-b echo reorders
  ("Backup saved. Copied to X." → "Copied to X. Backup saved.") and
  its log goes "(backup saved)" → "(Backup saved.)"; the
  existing-config second arm restructures ("(opencode.jsonc — backup
  saved)" → "(opencode.jsonc). Backup saved."); and ALL THREE sites'
  log lines change shape on success ("backup: $DIR" → "backup
  attempt: $DIR — <verdict>") — including the re-render twin, whose
  *announce* stays byte-identical (the reviewer's "true only for the
  re-render twin" holds for the announce lines; its log changes too).
  Benign and plausibly deliberate (the restructure carries the
  conditional verdict), but the ledger sentence misdescribes the
  user-visible delta — LOW, prose-only, per the d Q2/Q3
  evidence-accuracy precedent.
- **W2 verified**: no `DEFAULT_USER` assignment exists in
  test-install-args.sh (grep rc 1; the suite sets only `set -e` at
  :30 and sources nothing), so the driven label is the degenerate
  "gitconfig-" and the comparison asserts "gitconfig-, sudoers" —
  self-consistent, discrimination (comma-join, order, accumulation)
  unaffected; production labels always carry a real username
  (install.sh:349 writes the canonical value). The reviewer's
  `unverified` residual (a sourced lib assigning it) is resolved:
  nothing is sourced. INFO stands; the resolution's "label-a,
  label-b" phrasing is the imprecise half of the finding.
- **W3 verified**: `run()` (uninstall.sh:164-170) has zero call sites
  (invocation-anchored grep count 0 — comment/prose matches only);
  `un_rc_q` (:195-203) echoes and executes directly, does not call
  `run`. Dead helper kept as the run/run_q convention shape recorded
  in d S2. INFO.
- **Q1 verified**: `_un_revert_failed` is read only at :821 and :881;
  resets at :764 and :840 dominate both reads; the :408 store inside
  the plugins loop can never be observed (the post-loop reset at :476
  precedes any read) — write-only in scope, pair-idiom parity with
  the 12 sibling resets. INFO.
- **Clean-verdict spot re-checks (first-hand, not via the
  reviewers)**: `_bk_fail` count in install.sh = 10, `_dc_start_rc`
  in setup-container-backend = 5, `run sudo rm` in uninstall.sh = 0,
  `BACKUP_DIR`-writer × `|| true` grep = 0, stale-anchor grep over
  tests/ + docs/ = 0 hits, and the d-round e2e log tails re-read:
  "Passed: 309" / "Passed: 47" — all confirmed as the reviewers
  reported.

No finding retracted; no severity changed; no reviewer `unverified`
residue remains.

## Retracted / ghost findings

None this pass — all 4 reported findings verified; the one reviewer
`unverified` residual (W2's sourced-lib question) was resolved by a
main-session read before entering the index.

## Calibration

Micro scope — two axes, one fast-tier agent each, no per-axis
redundancy (that is the micro budget; wave/full shapes get more).
Yield concentrated on ledger precision (W1 — the round's own record
of its fix overstates wording preservation) and convention residuals
(W2/W3/Q1 — degenerate driven label, orphaned helper, dead store),
consistent with the round being sweep- and pin-disciplined: its three
exact counts held under first-hand recount, its class sweeps re-ran
clean, and its comments verified true sentence-by-sentence. The two
axes overlapped exactly once (the plugins-loop reset pair: W's clean
interplay verdict, Q's dead-store finding) without contradicting —
the interplay is correct; one of the two reset stores is write-only.
No cross-axis duplicates; no retraction. The stop rule (MED/HIGH
reads) finds nothing to read: no finding demands a code fix — W1 is
ledger prose, W2/W3/Q1 are record-or-drop residuals (W2 optionally a
one-line harness `DEFAULT_USER=` assignment) — so if the
dispositions land bookkeeping-only, the round changes no
review-relevant code and the loop's stop condition becomes checkable
by the next round or the maintainer.

## Run provenance

- Host window (UTC): pre-launch stamp **2026-10-25T22:11:14Z**;
  reviewer launches ≈22:12:10–22:12:12Z (sandbox stamps 23:12:10 /
  23:12:12 local +0100); W returned 22:21:13Z, Q 22:23:41Z (sandbox
  stamps normalized, skew ≤ ~1 min); post-return host stamp
  **22:25:23Z**.
- Reviewer agents: 2x `zai-coding-plan/glm-5.3-flash` (explore
  reader agents, read-only): W mechanical sweep
  (ses_e8ae11321ffeLnPBhcASqOF1JZ), Q quality
  (ses_e8ae1131fffe5Z2r1lqR3TCARN). Checkpoints:
  `/tmp/opencode/pr-00263-e/checkpoints/{W-sweep,Q-quality}.md`
  (session scratch outside the reviewed tree; absorbed here).
- Sabotage spot-check (window a — BEFORE fan-out, no readers
  running): `_bk_fail "opencode-binary"` deleted from install.sh:1992
  (the d W1 failure routing itself) → `sh tests/unit/test-install-args.sh`
  FAILed exactly at "backup failure silence survived somewhere
  (pr-00263 a F6 + d W1/W2)", rc 1 → `git restore` on the
  committed-clean tree → suite green ("All install.sh arg-parsing
  tests passed") → tree porcelain-clean. No mutation window
  overlapped the fan-out; no two-direction screening owed (RM-0111).
- Pre-fan-out host activity (disclosed): the user-commissioned
  bookkeeping commit `c3fcb7b` (d Q1/d Q3 `<SHA>` fills with
  `054a39a`) landed before the pass started; its gate chain caught
  the issue #237 shape live (the d Q1 row tipped 119 → 121 chars
  with the +2-byte fill, shortened to 117 before the commit).
- Tree under review: `release/0.0.57 @ c3fcb7b`, porcelain-clean
  before and after the pass. The commissioned range ends at
  `054a39a`; two commits sit outside the range by commission
  (`6021be6` docs-only agent-rules, self-declared no-micro-wave-owed;
  `c3fcb7b` the placeholder fill) — neither touches review-relevant
  code (RM-0065).
- Gates run before this snapshot's commit: `sh
  tests/unit/test-reviews-lint.sh`, `sh
  tests/unit/test-reviews-parity.sh`, `sh
  tests/unit/test-line-length.sh`, INDEX regenerated via
  `python3 scripts/gen-review-index.py` (check-then-commit; the
  snapshot body is immutable frozen history per the ratchet's scope
  note — the in-scope resolution edit stays ≤ 120).
- Environment: opencode kit checkout at
  `/var/www/vhosts/opencode-permissions-kit/repo` (kit-managed
  install, agent user `opencode`); main session GLM-5.3.

## Recommendation

The d-round fixes hold — every recount, class sweep and comment
audit came back clean, and the executed failure path (sabotage)
red-lined exactly where the round's pin promised. Dispositions owed
(maintainer's call): **W1** (correct the evidence block's "success
keeps the original wording" to describe the actual success-path
rewording — bookkeeping only), **W2** (record-or-drop; optionally
assign `DEFAULT_USER=opencode` in the harness so the driven label is
a production shape — one test line), **W3** and **Q1**
(record-or-drop residuals; both are the file's convention shapes).
No MED/HIGH finding: if the dispositions land bookkeeping-only, this
round changes no review-relevant code and the stop rule is checkable
— closure remains the maintainer's or the next round's call, not
this snapshot's (RM-0106/RM-0107, RM-0115).
