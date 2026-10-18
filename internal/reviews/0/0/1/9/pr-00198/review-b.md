<!-- review-meta
ID: pr-00198
Snapshot: b
Subject: issue-164 a-wave fix (a W1/W2/W3/W4/W5/W7) micro-wave review
Scope: wave
Base: v0.0.52 @ 0ce2e6b
Diff: 1738948..7d90557 (fix bdcf9ed + resolution bookkeeping 7d90557 as claims object)
Date: 2026-10-18
Reviewer: GLM-5.3 (house session, fresh — session-rotation pass C; main agent + 2 GLM-5.3-Flash axis subagents — pins/sabotage, shipped-code/claims; every finding main-agent-verified incl. a re-run 3-mutation sabotage matrix)
-->

# Review — pr-00198 snapshot b — fix wave (a W1, a W2, a W3, a W4, a W5, a W7)

> Resolution: [resolution.md](resolution.md)

Wave under review: fix commit `bdcf9ed` (3 files, +65/−25) plus the
resolution bookkeeping `7d90557` (reviewed as a claims object, per the
pr-00196 c precedent). The wave moved the legacy sudoers symlink gate
to the rm's authority (a W1), rewrote the sweep account as a
reproducible 12-hit ledger (a W2, riding a W7's anchors), balanced the
S3 sabotage and added the uid-0 skip (a W3), widened the negative
static pin (a W4), and bounded the block extraction (a W5). Question
per review-concept: did the fixes break or lie?

**Bottom line: no behavior bug — every fix does what its commit
claims, all six new/changed pins discriminate (proven by a re-run
sabotage matrix), and both suites are green.** All four findings are
claim/ledger drift of the exact classes the wave was closing: the new
sweep account dispositions only 11 of its own 12 hits (B1), the W1
class-sweep roster stops at the file boundary (B2), the resolution's
uid-0-guard rationale states the wrong consequence (B3), and one
ledger count is off by one (B4). None requires a code change; the
chain can close on comment/ledger dispositions.

## Findings index

| ID | Sev | Location | Summary |
|----|-----|----------|---------|
| B1 | MED | test-update-flags.sh:531-546 + resolution (a W2) | Sweep account dispositions 11 of its own 12 hits; uninstall's `[ -d /etc/opencode ]` gate-before-sudo-rm unaccounted |
| B2 | LOW | resolution (a W1 evidence) | W1 class-sweep roster scoped to uninstall.sh; same-shape site update.sh:670-673 (plain gate → `sudo rm -f`) unrecorded — benign, operative "one live sibling" claim verified true |
| B3 | LOW | resolution (a W3 evidence) | Inverted consequence: without the uid-0 guard, root hosts pass S3 VACUOUSLY (write fires, content-equal else branch) — the guard converts vacuous green to honest SKIP, it prevents no break |
| B4 | INFO | resolution (a W5 evidence) | "actual 16+1" — the block is 16 lines by the pin's own `wc -l` |

## B1 (MED) — the reproducible sweep account is off by one site

The a W2 repair's whole job was a sweep account that reproduces from
its own pattern. The count now does: `\[ -[fde] /etc` over the three
scripts yields exactly 12 hits at the wave base (reproduced this pass:
install.sh 669, 784, 880, 883, 1060, 1063, 2046; update.sh 731, 937;
uninstall.sh 240, 246, 557). But the comment's categories map only 11:
3 fixed (the openchamber gates), 8 deliberately plain (5 install.sh
conf/backup reads, the opt-in detection, the alpine detect, the
`[ -e /etc/sudoers.d/opencode ]` message-only arm), plus 2
out-of-pattern class sites that are not hits. Unaccounted hit #12:
uninstall.sh:246 at base (250 at HEAD), `if [ -d /etc/opencode ]` — a
plain developer-authority gate whose branch runs
`run sudo rm -f "/etc/opencode/$_un_leg"` (sudoers, install.conf,
projects.conf, setup.conf) plus `sudo rmdir`. That is precisely the
enumerated gate-before-sudo-write class, in uninstall.sh, inside the
pattern's letters. The resolution's a W2 row ("its 12 base hits, the
per-site dispositions") inherits the gap — a maintainer auditing the
account per its own recipe finds a site with no disposition: the
residual a W2 shape, reduced from 8 unaccounted hits to 1.

Severity is the claim, not the site: the missed site is fail-safe —
blinding `[ -d /etc/opencode ]` requires a non-searchable /etc (not a
realistic host state), disagreement leaves inactive legacy files, and
no active grant is involved (that sibling was a W1 and is fixed).
Impact is documentation-only; the false-exhaustiveness sits in the
artifact built to close a MED claim-drift finding. Repair: one
sentence in the sweep comment (deliberately plain, /etc world-search
premise, benign-leftover direction) and the matching resolution line.

## B2 (LOW) — W1 class sweep stops at the file boundary

The a W1 evidence records its sweep as "pattern `\[ -L\ ` + `readlink`
over uninstall.sh" — which reproduces exactly (281-284, 377-381, both
benign, both correctly left plain). But the class ("plain gate at
developer authority, removal via sudo") has a third same-shape site in
another file the roster never names: update.sh:670-673,
`[ -L /usr/local/bin/xdg-open ]` + `readlink` marker gate →
`sudo rm -f /usr/local/bin/xdg-open`. The W2 comment's out-of-pattern
category names only the never-shadow `ln` branch at update.sh:680-682
— its ln-without-`-f` rationale does not fit the rm site. Verified
benign (/usr/local/bin is 0755 by convention; marker-gated on the
readlink target; disagreement keeps a stale shim, no grant), so the
operative disposition — "the /etc/sudoers.d site was the class's one
live-relevant sibling" — remains TRUE counting it. install.sh:2072
(never-shadow twin) likewise stays unclaimed, as review-a W9 already
recorded. Residual: L2 evidence completeness — record the cross-file
sites with their rationale, or scope the sweep claim to the file
explicitly. Downgraded from the reporting subagent's MED on this
verification: no false claim survives, only an unstated site.

## B3 (LOW) — the uid-0 guard's stated consequence is inverted

The resolution's a W3 evidence says the uid-0 skip exists because
"without the guard the correction would break root-run suite hosts."
It would not. Static trace of root-run S3 (guard removed): S3 inherits
S2's fixture, whose policy.json holds KIT-SHAPED content; as root the
balanced `[ -f path ]` succeeds through mode 000 (CAP_DAC_OVERRIDE),
the stub-opened `sudo cat` returns content equal to `_oc_expected`,
`!=` is false → the else branch fires the sudo write → SUDO-WRITE
appears → S3 PASSES — vacuously green, indistinguishable from the S2
control, proving nothing. This is the same else-branch mechanism
snapshot a's own M4 retraction traced for the broken form ("rc 2 …
takes the else branch — S3 passes on uid 0"); the W3 fix guidance's
"takes the warn branch, and never writes" assumed divergent content,
which S3-time content is not. The shipped guard is still exactly right
— it converts the vacuous green into an honest, environment-marked
SKIP (house L4b form per test-browser-bridge.sh:487), and the in-code
comment's rationale ("uid 0 has no caller-blind state") is accurate.
Only the ledger's consequence sentence is wrong (and snapshot a's
guidance sentence it echoes — immutable there, correctable here).

## B4 (INFO) — ledger count nit

The a W5 evidence says the extracted block is "actual 16+1" lines; the
extraction is 16 lines by the pin's own `wc -l` measure (verified).
The shipped comment ("the block is 16 lines") is correct; the ≤20
bound holds with 4 lines of margin. Ledger prose only.

## Fix verification (positive results)

- **Sabotage matrix re-run against the committed wave** (red → restore
  → green, per AGENTS): a W1 plain-`[ -L ]`/plain-`readlink` re-plant
  → exactly the two claimed FAILs (call-sequence + static marker pin);
  a W4 non-`if` re-plant → FAIL at the widened negative pin (the old
  if-anchored form verifiably stayed green on the same mutation —
  discrimination genuinely improved); a W5 closing-`fi` re-indent →
  FAIL at the extract check ("anchor drift?"), S1/S2/S3 correctly
  skipped via `OC164_BLOCK=""`.
- **a W3 mechanism verified**: the balanced sed yields
  `if [ -f <path> ] \` over the real block (single occurrence, trailing
  space consumed); suite output carries no `[: missing ]`; S3 passes
  at uid 1001 through the blind-probe path (plain probe false under
  mode 000 → else → write), not an rc-2 fallthrough.
- **a W1 semantics verified** (both axes + main): no `set -e`; probes
  read-only, deliberately outside `run()` so dry-run exercises them;
  `sudo readlink` failure → `|| true` → leave-untouched arm (fail-safe
  leftover, unchanged shape); marker case `/etc/opencode/*` intact;
  up-front sudo validation (l.109-118) makes the no-sudo edge
  unreachable; allowlist additions are anchored full-line, read-only
  verbs — deny-by-default holds (a variant like `sudo readlink -f …`
  would fall out of the allowlist and go red).
- **S1/S2 pass-either-way confirmed**: every S1/S2 probe routes through
  the stub's chmod-700 window (stub runs as the fixture owner for any
  uid); only S3 probes at caller authority, and it alone carries the
  environment mark.
- Claim audit beyond the findings: three openchamber gates genuinely
  sudo'd at the fix; "root==root" install rationale confirmed
  (install.sh root-user gate); "12 hits" count exact; "16 lines" exact;
  docs/how-to/uninstall.md needs no change (describes behavior, not
  probe authority).

## Severity calibration

Both B1 (reported LOW by the pins axis, MED by the claims axis) and
B2 (reported MED by the claims axis) were re-verified and set by the
main agent: B1 to MED — a false-exhaustiveness claim in the exact
artifact commissioned to close a MED claim-drift finding, corpus L3
precedent; B2 to LOW — no surviving false claim, only an unrecorded
benign site. No retracted findings this pass; no ghosts.

## Provenance, gates, recommendation

- Provenance: B1 fix-induced (the wave's comment rewrite and
  resolution row); B2 fix-induced evidence gap over pre-existing
  sites; B3 fix-induced ledger echo of a pre-existing (snapshot-a)
  wrong sentence; B4 fix-induced ledger prose.
- Gates run (uid 1001, WSL2 host): `sh tests/unit/test-update-flags.sh`
  (108 pass, incl. S1/S2/S3 green, no `[: missing ]`),
  `sh tests/unit/test-uninstall.sh` (72 pass, incl. the three new W1
  pins), `make lint` clean, `sh tests/unit/test-sandbox-policy.sh`,
  `sh tests/unit/test-reviews-lint.sh`, `sh tests/unit/test-reviews-parity.sh`
  — all green; sabotage matrix as above; base-hit and roster greps
  reproduced at `0ce2e6b`/`bdcf9ed`. E2e suites NOT run by this review
  — still owed before merge (the wave touches uninstall.sh; AGENTS
  both-suites class).
- Recommendation: **fix-then-close.** B1's one-sentence comment +
  resolution repair, B2's roster completion, B3/B4's ledger
  corrections are comment/bookkeeping-only — per the stop rule such a
  round closes the chain without a successor pass (any disposition
  that stays in comments/docs/ledger closes it; only code-touching
  dispositions would extend it).
