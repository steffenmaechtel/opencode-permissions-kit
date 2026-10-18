<!-- review-meta
ID: pr-00198
Snapshot: a
Subject: issue-164 openchamber probe authority gates (fix wave)
Scope: wave
Base: v0.0.52 @ 0ce2e6b
Diff: 0ce2e6b..1738948
Date: 2026-10-18
Reviewer: GLM-5.3 (house session, fresh; main agent + 2 Flash axis subagents — pins, shipped-code/sweep; every finding main-agent-verified, one subagent MED retracted on runtime evidence)
-->

# Review — pr-00198 snapshot a — issue #164 openchamber probe authority gates

Wave scope: `git diff 0ce2e6b..1738948` (5 files, +147/−9). The wave
moves the openchamber presence probes in `install.sh` (~2046),
`update.sh` (~732), and `uninstall.sh` (~560) from invoking-user
authority (`[ -f ]`, plain `grep -q`) to the write's authority
(`sudo test -f`, `sudo grep -q`), adds static shape pins, a behavioral
gate-block harness (S1 blind-dir warn-no-write, S2 readable-dir write
control, S3 plain-`[ -f ]` sabotage discrimination) in
`test-update-flags.sh`, and extends the uninstall dry-run allowlist +
call-sequence pin.

**Bottom line: no behavior bug found in the shipped hunks.** Probe and
write now share authority at all three sites, the fail directions are
safe, and the uninstall premises (root refused, sudo validated up
front) hold. The three MED findings are the wave's own claims and pins:
an unswept same-class sibling (`[ -L ]` on `/etc/sudoers.d/opencode`),
a sweep list that does not reproduce from its own grep pattern, and a
sabotage pin that discriminates by accident (a broken test command),
not by the mechanism its comment claims.

## Findings index

| ID | Sev | Location | Summary |
|----|-----|----------|---------|
| W1 | MED | uninstall.sh:228-242 | Unswept same-class site: legacy sudoers symlink gate probes at developer authority, removal via sudo |
| W2 | MED | PR body + test-update-flags.sh:532-537 | Sweep claim doesn't reproduce: pattern yields 12 hits, 6 sites accounted (2 not hits), 8 hits unaccounted |
| W3 | MED | test-update-flags.sh:625-633 | S3 sabotage is a broken test command (`[ -f path` missing `]`); discrimination fires via rc-2 fallthrough, not the claimed blind-probe mechanism |
| W4 | LOW | test-update-flags.sh:541-545 | Negative static pin matches only the exact `if [ -f … ]` master shape |
| W5 | LOW | test-update-flags.sh:545+558 | Extraction range over-captures on `fi`-indent drift; guard passes polluted blocks |
| W6 | LOW | test-uninstall.sh:103-110 | Call-sequence pin asserts probe presence, not order |
| W7 | INFO | test-update-flags.sh:527-537 | Comment cites line numbers already drifted at HEAD |
| W8 | INFO | install.sh:2046, update.sh:731 | Sudo-absent edge: failure-shape note, no silent wrong write (pre-existing) |
| W9 | INFO | install.sh:1060, update.sh:618, 680 | All three "deliberately not changed" rationales verified correct |
| W10 | INFO | install.sh gate | Install twin pinned statically only; behavioral coverage rides on update.sh's harness |
| W11 | INFO | test-update-flags.sh harness | `sudo()` stub models DAC override on a suite-owned dir — coherent at unit scope |

## W1 (MED) — unswept same-class sibling: legacy sudoers symlink gate

`uninstall.sh:228-242` gates the removal of the legacy pre-0.0.10
sudoers symlink on `[ -L /etc/sudoers.d/opencode ]` + `readlink`
(evaluated at developer authority) while the removal itself runs via
`run sudo rm -f` — the exact issue-#164 shape. It is invisible to the
wave's sweep pattern because `-L` is not in `[fde]`; the adjacent
`[ -e /etc/sudoers.d/opencode ]` (line 240, which the pattern DOES
match) is likewise absent from the wave's account.

Trigger (all three needed): a pre-0.0.10 install cohort (legacy
`/etc/sudoers.d/opencode` → `/etc/opencode/sudoers` symlink, the
0.0.43a F5 cohort), an `/etc/sudoers.d` the developer cannot search
(0750 root:root occurs under distro hardening; this host is 0755), and
an uninstall run. Effect: the gate reads absent, the block is skipped
silently, and an ACTIVE kit sudoers grant survives behind
"Uninstall complete." — the exact harm the block's own comment
(lines 221-227) names. Fail direction is leftover-grant, not overwrite.
The current-name grant (`/etc/sudoers.d/opencode-permissions-kit`,
line 217) is removed ungated and is NOT exposed.

Provenance: pre-existing (site predates the wave); the sweep MISS is
this wave's. Disposition candidates: fix (`sudo test -L` +
`sudo readlink`, same shape as the openchamber fix) or a follow-up
issue with a recorded deliberate skip.

## W2 (MED) — sweep claim does not reproduce from its own pattern

The PR body (mirrored in the test comment) presents the L2 sweep as
"pattern `\[ -[fde] /etc` over install.sh/update.sh/uninstall.sh" with
a 6-site result. Reproduced here: the pattern yields **12 hits at the
base** (install.sh 669, 784, 880, 883, 1060, 1063, 2046; update.sh 731,
937; uninstall.sh 240, 246, 557). Of the 6 accounted sites, two are not
hits of the pattern at all (update.sh:618 probes a variable under
`$LIBDIR`; update.sh:680 probes `/usr/local/bin`), and 8 genuine hits
are unaccounted. All 8 were verified benign in this review
(root-context reads, OS detection, print-only branches) — but the one
security-relevant same-class site (W1) sits outside the pattern's
letters entirely, which is how it escaped.

This is the L2/L3 claim class: a sweep account that reads as exhaustive
but is neither exhaustive over its own pattern nor defined over the
class it names ("gate whose branch writes via sudo"). Repair: widen the
sweep to the class (`[ -L`/`[ -r`/`[ -s` forms, gates on non-/etc
mutated paths) or record the pattern's full hit set with per-site
dispositions, and name the `[ -L ]` sibling explicitly (fix or skip).

## W3 (MED) — S3 sabotage pin discriminates by accident

The in-vitro discrimination proof builds its sabotage with
`sed 's|sudo test -f |[ -f |'`. The result is

```
if [ -f /path/policy.json \
    && [ "$(sudo cat …)" != "$_oc_expected" ]; then
```

— the first command is `[ -f /path/policy.json` with **no closing
`]`**: grammatically valid shell (`sh -n` passes), but a runtime
test-builtin error. Verified three ways: the live suite run prints
`tests/unit/test-update-flags.sh: 2: [: missing ]` right before the S3
PASS line; a standalone reproduction of the exact harness prints
`[: missing ']'` and still fires SUDO-WRITE; and a balanced sabotage
(`s|sudo test -f \([^ ]*\) |[ -f \1 ] |`) behaves identically as
non-root. Consequences:

- The write branch is reached via rc-2 fallthrough, not via the
  claimed mechanism ("the same blind state slips into the sudo write" —
  the plain probe reading absent under mode 000). The comment's
  mechanism claim is false as executed.
- The pin is mechanism-blind: it stays green in environments where the
  claimed mechanism does not hold. As uid 0 a *valid* plain
  `[ -f /path ]` succeeds through mode 000 (CAP_DAC_OVERRIDE), takes
  the warn branch, and never writes — yet the shipped broken-`[` form
  still returns rc 2 there and "passes" S3.
- stderr noise (`[: missing ]`) leaks into `make test` output.

Fix in one line plus a guard: balance the replacement (add the closing
`]`) AND skip/guard S3 for uid 0 — the balanced pin legitimately cannot
discriminate for root (no caller-blind state exists), so without the
guard the correction would break root-run suite hosts. Note `sh -n` is
not an adequate instrument for this class (see retracted M-claim).

## W4 (LOW) — negative static pin is shape-narrow

`! grep -qF 'if [ -f /etc/openchamber/policy.json ]'` catches only the
exact master regression shape. A re-planted plain probe in another
dress (`elif`, `[ -f … ] &&` without the `if ` prefix, `test -e`)
passes the static pair. The S1/S2 behavioral harness backstops the
update.sh gate semantically, so severity stays LOW.

## W5 (LOW) — extraction range drifts loudly but confusingly

The block extraction `/^    _oc_expected=/,/^    fi$/p` ends at the
first 4-space `fi`. If that indent drifts (and no later `    fi`
exists), the range over-captures to EOF; the extraction guard (non-empty
+ contains `sudo test -f`) passes the polluted block, and the failure
surfaces later as S1/S2 `got:` dumps rather than an extraction failure.
House-accepted sed-extraction fragility; a tighter closing anchor
(`^    else$/…^    fi$` pair or an end-marker grep) would localize it.

## W6 (LOW) — call-sequence pin asserts presence, not order

The new test-uninstall.sh pin greps both probe lines with independent
`grep -q`s — a regression that reorders them (content grep before
presence test) still passes. Minor; the pair's purpose (both probes
ride sudo) is unaffected.

## W7 (INFO) — line-number citations already drifted

The sweep comment cites update.sh:731 / install.sh:2046 /
uninstall.sh:557; at HEAD the sites live at 733-734 / 2048 / 560. Will
rot further; cite by anchor (`_oc_expected=` block) rather than line.

## W8 (INFO) — sudo-absent edge, failure-shape note (pre-existing)

With no sudo binary at all, the new probes' rc-127 sends the gates to
the write branch, which then dies at `sudo mkdir` under `set -e`. No
silent wrong write is possible (the write needs sudo too), and both
scripts run dozens of sudo calls before these sites, so the edge is
unreachable behind earlier aborts. Pre-existing systemic premise, no
wave regression.

## W9 (INFO) — "deliberately not changed" rationales verified

- install.sh:1060 — detection-only (`_oc_seen=true`), branch writes
  nothing. A blind false-negative silently skips the opt-in prompt;
  fail-safe, recoverable via `sudo opk openchamber-secure`.
- update.sh:618 — `[ -e "$_opk_old" ] && sudo rm -f` under `$LIBDIR`
  (0755 world-traversable); disagreement direction is a benign
  leftover.
- update.sh:680 — `sudo ln -s` without `-f` cannot overwrite a hidden
  target; nuance: its failure aborts update mid-run under `set -e`
  (pre-existing). install.sh:2072 is the same shape with the same
  verdict (outside the claimed pattern, unclaimed).

## W10 (INFO) — install twin statically pinned only

The install.sh gate has no behavioral S1-equivalent; class coverage
rides on update.sh's harness (same block shape). Acceptable.

## W11 (INFO) — harness fidelity

The `sudo()` stub models root's DAC override by chmod-flipping a
suite-owned fixture dir around read-only probes. Coherent for the
caller-blind vs sudo-visible distinction at unit scope; it cannot
model a dir the caller truly cannot re-chmod (real root vs owner) —
that gap is what S3 was supposed to cover behaviorally (see W3).

## Retracted / ghost findings

- **M4 (Flash pins axis, MED as stated) — retracted on runtime
  evidence.** Claim: "S3 fails on root-run hosts (plain `[ -f ]`
  succeeds through mode 000 → warn branch → no write)". Unreachable
  through the shipped sabotage: the broken `[ -f path` (missing `]`)
  returns rc 2 regardless of uid and takes the else branch — S3 passes
  on uid 0 exactly as it does here (uid 1001). Verified by mechanism
  (rc 2 is uid-independent) and by the standalone repro. Residue kept
  as W3 fix guidance: the uid-0 guard becomes necessary only once the
  sabotage is balanced.
- **M-claim "L3 literal check passed — the sed sabotage yields a valid
  test command" — refuted.** The check ran `sh -n`, which validates
  grammar, not test-command arity; the runtime `[: missing ]`
  diagnostic proves the command is broken. Calibration note: `sh -n`
  is not an L3 instrument for `[`-form mutations.

## Core-fix verification (positive results)

- Authority agreement achieved at all three sites; empty-file and
  cat-failure edges fail safe (`"" != expected` → warn-and-skip;
  grep-no-match → keep).
- uninstall premises verified: root/opencode refused (103-107), sudo
  validated up front (109-118), no `set -e`; the probes sit outside
  `run()` so dry-run still exercises them read-only — consistent with
  the 0.0.45c C6 / 0.0.45d W2 agents-backup precedent, and the
  dry-run allowlist extension matches exactly the two new probe
  shapes.
- L5 pass: the new sudo probes are read-only on root-owned `/etc`
  paths; no new root operations on agent-writable trees; no
  write-through-symlink boundary crossed. Remaining probe→write TOCTOU
  windows are narrow, adversarial, and pre-existing in shape.
- Sandbox: all new fixture operations live under `mktemp -d` scratch;
  `test-sandbox-policy.sh` green.

## Provenance, gates, recommendation

- Provenance split: W1 pre-existing (site) with a delta-introduced
  sweep miss; W2 delta-introduced (the wave's claim); W3-W7
  wave-introduced; W8 pre-existing; W9-W11 informational.
- Gates run (uid 1001, WSL2 host, Linux 6.6.87.2-microsoft-standard):
  `sh tests/unit/test-update-flags.sh` (108 pass, incl. all 7 #164
  pins), `sh tests/unit/test-uninstall.sh` (all pass), `make lint`
  (clean), `sh tests/unit/test-sandbox-policy.sh` (pass), plus the
  standalone S3-mechanism reproduction. E2e suites NOT run by this
  review — owed by the fix wave before merge (the wave touches
  install.sh / update.sh / uninstall.sh, AGENTS both-suites class).
- Recommendation: **fix-then-ship.** W3 (balanced sabotage + uid-0
  guard) and W2 (sweep-claim repair, `[ -L ]` sibling named and
  dispositioned) belong in this wave; W1 fix or follow-up issue with a
  recorded disposition. No behavior bug blocks the shipped hunks.
