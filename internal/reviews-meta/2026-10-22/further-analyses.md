# Further analyses — run 2026-10-22

Companion to the [run README](README.md) and
[statistics.md](statistics.md). Numbers cite
[data/stats.json](data/stats.json) unless noted.

## Review precision — who finds what, and what dissolves

| Group | Snapshots | Findings | Retracted | Downgraded |
|---|---|---|---|---|
| GLM-5.3-Flash (fan-out) | 28 | 260 | 20 (7.7 %) | 16 |
| GLM-5.3-family (lead single-pass) | 21 | 65 | 3 (4.6 %) | 0 |

- Fan-out snapshots produce ~4× the findings per snapshot and carry the
  higher dissolve rate — most retractions are *ghost findings*: subagent
  suspicions the lead dissolved during verification (pr-00222 a/b alone
  contribute 16 retracted rows; the b-wave recorded them explicitly as
  "dissolved"). The corpus keeps them as `status: retracted` rows by
  design — dissolution is itself evidence about precision.
- One dual-severity reading (pr-00200 a W1: subagent HIGH, lead MED) is
  recorded on both levels — the calibration datapoint the run 2026-10-10
  started ("tooling is the differentiator, not the model").
- The pr-00211 a full pass retracted one finding *in-snapshot* and its
  snapshot-a provenance split sums to 39 over 37 findings — a
  snapshot-internal inconsistency, noted in the batch's process notes,
  not smoothed over here.

## Provenance — the fix-wave engine cools

Fix-induced: 20.3 % (112/553) → **9.3 % (28/302)**. Wave-introduced stays
the dominant provenance (176/302 = 58.3 %). Reading: the
micro-wave-review-per-round rule (L6, binding since 0.0.42) plus
fixes-bring-their-own-pins have halved self-inflicted findings — but the
class did not vanish; 9 fix-regression findings (2 MED) remain, and
pr-00211 b W8 shows the F17 fix inheriting the F12 residue class (a
fix-induced sibling of a fix finding).

## Convergence — chain length by review scale

- Feature/fix waves close in 1–3 snapshots (10 of 14 PR-keyed wave cases
  closed at ≤ 3; stop rule met in the final round of every closed case).
- The one release full pass (pr-00211, 360 files) needed 7 snapshots,
  stop not met in 6 — the release-gate chain is the expensive one. Its
  resolution closes bookkeeping-only, with both e2e comparators recorded
  (303/47) — the release gate discipline held.
- 0.0.48 (5 snapshots) and 0.0.49 (4) sit between: legacy-era full-ish
  waves before the restructure.

## Issue #175 pre-pass — the restructure-era candidates, answered

The 2026-10-10 run predated the restructure wave (language pass, exec-bit
class, sabotage-vs-uncommitted-tree). Question: new L-classes? Answer:
**no — all three resolve into existing homes.**

1. **Language pass** — 1 finding in the corpus (pr-00211 a F21, German
   `Vorgang` in make/CI step names, LOW). The rule (AGENTS.md ## Rules
   "All shipped content is English" + conventions "Language") is enforced
   by review; the only catch came
   from a full pass. Not a class — a ratchet-able wiring-gate candidate
   if it ever recurs.
2. **Exec-bit class** — issue #123's invariant (755 ⇔ executed by path)
   produced no direct violation in the corpus; the adjacent failures are
   `wiring-gate`: four sourced-only libs deployed 755 (pr-00211 a F30,
   carried since 0.0.41d) and the line-length ratchet RED at a committed
   HEAD (pr-00208 b W1). wiring-gate: 6 findings, 2 MED — small,
   recurring, already-gated; stays in L4's orbit ("pins discriminate and
   sit before the gate") plus the CI checks themselves.
3. **Sabotage-vs-uncommitted-tree** — 0 findings: the 2026-10 incident
   never entered a review snapshot (it was a live-session loss, not a
   review finding). The rule lives in AGENTS.md Testing where the
   incident happened; it needs no meta numbers and no L-slot.

Consequence for [learnings.md](../../../agent/learnings.md): L1–L7 stay
at seven; their numbers are re-grounded (this run) and two "trend-proven"
claims are corrected — see the README headlines 2 and the learnings diff.

## Corpus comparability — read the tables with these caveats

1. **Composition shift.** 36 wave / 12 micro / 1 full snapshots here vs
   29 / 9 / 15 full-ish (12 full + 3 external-full + 1 other) previously.
   Severity shares are NOT comparable row-by-row: fewer full passes
   mechanically means fewer HIGH/MED (10.9 % vs 21.3 % H+M).
2. **INFO share is an artifact.** 50.7 % INFO here vs 28.4 % previously —
   fan-out snapshots count coverage notes and dissolved ghosts as rows.
   Class *shares* (of reported) are inflated for INFO-heavy classes
   (`test-vacuous`, `other`). The MED/HIGH columns are the honest
   comparator across runs.
3. **A new area exists.** `internal` (reviews, records, rules-meta)
   tracks 59 findings — project memory became a review surface with the
   restructure; the previous run had no such area.
4. **Extraction judgment calls** (kept in batch process notes): same-case
   refs normalized to `pr-NNNNN a W1`; `#165/#199`-style refs in
   pr-00211 a F2 read as PR refs (the corpus's own citation era makes
   bare `#NNN` ambiguous from 2026-10 onward); ghost findings carry
   synthetic IDs (G1–G8); pr-00171's conditional stop-rule statements
   recorded as `not_met` with a process note.
5. **Follow-ups under-counted** in the resolutions table (two batches
   noted follow-ups in prose) — count them from the resolution files.

## Blind spots

- e2e suites: 7 findings — little reviewed this corpus; the e2e debt
  rule (#214 6) tracks runs, not findings.
- `docs/` user-facing pages: 20 findings, but no full pass targeted docs
  since the reflow baseline (pr-00179).
- Only one full pass in 12 days — the HIGH/MED columns under-represent
  deep bugs; the next release full pass should land *inside* the next
  run's corpus if possible.
