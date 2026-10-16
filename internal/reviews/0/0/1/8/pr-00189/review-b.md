<!-- review-meta
ID: pr-00189
Snapshot: b
Subject: issue-187 fix wave (a W1/W2) micro-wave review
Scope: wave
Base: v0.0.50 @ 43bd33e
Diff: e901276..4fb7ebd
Date: 2026-10-17
Reviewer: GLM-5.3 (house session, main agent — single-pass micro-wave review, empirical verification)
-->

# Review — pr-00189 snapshot b — fix wave (a W1, a W2)

> Resolution: [resolution.md](resolution.md)

Wave under review: fix commit `4fb7ebd` (9 files, +61/−13): a W2 —
edge-trim in every y/n answer (`IFS=` dropped from `_ui_read` ×2 and
the opk fallback read; uninstall unchanged, now the reference) with 8
padded pins across three suites; a W1 — the `script` row in
check-host.sh. Question per review-concept: did the fixes break or
lie?

**Verdict: 0 HIGH/MED, 0 LOW, 2 INFO — dispositions touch no code,
the loop closes (stop rule met).**

## Findings index

| ID | Severity | Provenance | Summary |
|---|---|---|---|
| B1 | INFO | wave-introduced | whitespace-only input now counts as empty in install.sh's selection loops (5-empty abort) |
| B2 | INFO | wave-introduced | check-host `script` probe is presence-only — BSD script lacks `-qec` |

## Verified

1. **Read sweep (L2 for the fix itself).** `grep -rn "read -r" files/`:
   every remaining `IFS=` / `IFS='…'` read is a data/line reader
   (advisory lines, TSV registries, find pipes, passwd) that must stay
   verbatim (L7) — no data reader was flipped, no decision reader was
   missed. The only un-prefixed reads in shipped code are the three
   answer readers (ui.sh:171/178, opk:46, uninstall.sh:144) — the
   trim class is closed.
2. **`_ui_read` consumers beyond y/n.** install.sh's direct calls
   (:1206 selection `[Cc]*` glob, :1225 custom paths): padded input is
   now honored — an acceptance-widening change only (B1 records the
   whitespace-only nuance).
3. **Claims vs pins (L3).** Every claim the fix wave wrote carries a
   pin or is true: opk comment → 2 pty pins; ui_confirm note → 2 pins;
   uninstall's "padded ` y` is an explicit y in every implementation"
   → 2 pins in each of the three suites; the `'y '`-under-y pin is
   deliberately non-discriminating for the trim (it guards the V17
   class) — the split is documented in the resolution.
4. **RM-0006 record.** Quote unchanged and still a true prefix of the
   extended bullet (rules-meta audit green); body/check/log match
   reality; the stale wrapper reference is gone.
5. **Sabotage matrix** (resolution evidence): 4/2/2 FAILs — exactly
   the new pins — restored green; the first uninstall sabotage was
   invalid (sed typo broke the redirect, not the trim), discarded,
   redone clean, and recorded as such.
6. **Gates.** check-host renders the new probe (live run); full unit
   sweep green at the fix; the line-length ratchet caught three
   overlong resolution rows (155/200/172 chars) — rewrapped ≤120
   before this snapshot (pr-00171 W1 precedent).

## Findings

### B1 (INFO) — whitespace-only input counts as empty in selection loops

With the trim, an input of only spaces (`"   "`) reaches install.sh's
selection/custom loops as `""` and increments the 5-empty abort
counter (0.0.44a V6 design: "empty reads count toward a bail-out")
where it previously fell through the case arms as non-empty unknown
input and silently re-asked. Aligns with the loud-abort intent; a
user mashing space five times now gets the EOF guidance error. No
action.

### B2 (INFO) — presence-only probe for script(1)

`command -v script` succeeds on macOS with BSD script, which lacks
`-qec` — the probe would pass while the pty pins fail. The row's
why-text names "util-linux -qec" so the failure trail leads there, and
the repo's contributor surface is Linux/WSL2 + Linux CI (same shape as
the pre-existing setsid row). No action.

## Provenance, gates, recommendation

- **Model:** GLM-5.3 (house session, main agent, single pass; micro
  wave ≈60 changed lines, empirical verification as listed above).
- **Tree:** `feature/y-n-prompt-consistency` @ `4fb7ebd` + bookkeeping
  (`e901276` snapshot a, `f1f8847` resolution); base code `43bd33e`.
- **Gates run:** full unit sweep green at the fix; line-length green
  after the resolution rewrap; reviews lint + parity green; e2e not
  owed (no install.sh/update.sh/wrapper/backend semantics change —
  install.sh's answer handling only widens accepted input).
- **Recommendation:** chain closed — b's dispositions (B1/B2
  deliberately not done) touch no review-relevant code. Merge-ready;
  PR update/push is the maintainer's move.
