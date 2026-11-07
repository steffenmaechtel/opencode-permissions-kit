# Review meta-analysis 2026-11-07 — subagent staffing economics

> **Status: CURRENT.** First run of a new measurement dimension: not
> error classes (see [2026-10-22/](../2026-10-22/)) but the **economics
> of the review loop's subagent staffing** — reviewers, curator,
> verifiers: what they cost, what the sizing gates fired on, what the
> batches produced. Commissioned by the maintainer (2026-11-07): the
> reviewer fresh-context invariant is not in question; curator and
> verifier deployment are to be judged by numbers, not gut feeling.

## Corpus

The PR-native era's complete history: **2026-10-26 → 2026-11-06, 52 PRs
(#280–#407), 132 review rounds** (after split-part dedup, 9 pure closing
summaries excluded), **339 subagent sessions** from the opencode session
db. The sizing gates themselves landed 2026-10-28 (PR #291, RM-0126 /
RM-0127) — the corpus therefore splits into a **pilot week** (10-26 →
10-28, gates not yet written), an **adoption week** (10-29 → 11-01,
gates fresh) and the **settled era** (11-02 → 11-06).

## What numbers exist (data inventory)

- **`opk-review` markers (PR comments)** — per round: reviewers,
  curator (main/flash), verifiers, raw→curated counts, med/high,
  retracted, tier, track, mode, session. NOT carried: per-verdict
  attribution (who refuted a finding — verifier or main audit) and
  verifier CONFIRMED value (a batch confirming everything is
  invisible in the marker).
- **opencode db `session_v2`** (subagent = child session) — per
  session: role (from title), model, duration, in/out tokens,
  directory. NOT carried: dollar cost (subscription host:
  `cost` = 0.0) and verdict files (session scratch is deleted).
- **This run's join** — role × tier economics over 339 sessions;
  gate compliance simulation over 132 rounds. NOT possible:
  per-round session assignment beyond dates (marker counts and db
  sessions cross-check at aggregate level only).

Extraction is fully scripted and re-runnable:
[data/extract.py](data/extract.py) (gh + sqlite, read-only), frozen
outputs in [data/](data/) (`rounds.jsonl`, `subagents.jsonl`,
`markers-parsed.jsonl`). Recipe details and gotchas:
[statistics.md](statistics.md) §Recipe.

## Headline results

1. **The gates as written are followed.** Settled era (11-02 → 11-06):
   100% verifier-gate compliance (51/51 rounds). All deviations live in
   the adoption week — 7 over-fired
   batches on LOW/INFO-only rounds with ≤ 5 findings, 1 skipped batch
   on a MED round (#329 b, 2 MED — disclosed there). The gates
   discipline themselves; the *thresholds* are the open question.

2. **The verifier gate's count arm has no measured yield.** Rounds with
   > 5 curated findings but zero MED/HIGH ran a strong-tier verifier
   batch in **6 of 6 cases** (gate era) — #336 a, #338 a, #360 b,
   #386 c, #399 b (the maintainer's 4 LOW / 2 INFO example), #404 a —
   for a combined **1 retraction**, and that one is not attributable
   to the verifier (main audit co-verifies; verdict files are gone).
   Six strong sessions ≈ ~34 min agent time, ~0.33M input tokens. The
   severity arm is the opposite: **37 MED/HIGH rounds → 9 retractions**
   (24% of rounds) — that is where verification earns its cost, and
   the one skipped MED batch (#329 b) was a real deviation. A "≥ 3
   MED/HIGH findings" arm was considered and rejected: the yield
   spreads across count bands — 6 of 8 retraction rounds carried
   only 1–2 MED/HIGH (1–2 band: 29 rounds → 7 retractions; ≥ 3 band:
   8 rounds → 2) — so the batch stays owed at ANY MED/HIGH.

3. **Cost shape of the three roles** (339 sessions, 12 days): reviewers
   dominate by design — 221 sessions (218 fast tier), median 8.0 min,
   ~30 h total, 15.0M input tokens. Verifiers: 83 sessions (81 strong),
   median 5.6 min, ~8.6 h, 4.5M in. Curators: 34 sessions (all fast),
   median 3.0 min, ~1.9 h, 1.1M in. Reviewer cost is the process's
   backbone, not a savings target.

4. **The curator gate works and needs no change.** The adoption week
   over-deployed 9 times (a curator ran although the gate said main —
   2-reviewer rounds); the pilot week ran a curator by default, before
   the gate existed. The settled era is clean in both directions: 9
   gate-owed rounds, 9 curators; 42 non-owed rounds, all curated main;
   0 over, 0 under.

5. **The model map holds after adoption week.** 5 model-map deviations
   total (3 reviewers on strong 10-28, 2 verifiers on flash 10-31) —
   none since 11-01. The strong/fast split of the house map
   (SKILL.md §4) is stable in practice.

## Applied change (this PR)

The maintainer pre-approved changing the calibration **in this PR** if
the numbers are clear. They are (headline 2): verification sizing
becomes **severity-driven** — RM-0127
([agent/review-concept.md](../../../agent/review-concept.md),
"Curation and verification") drops the "≤ 5 curated findings" count
arm: LOW/INFO-only rounds verify main-inline at ANY count; any MED/HIGH
finding still owes exactly ONE fresh strong-tier verifier batch
(unchanged — the yield and the #329 b deviation both back it).
[.agents/skills/opk-review-pass/SKILL.md](../../../.agents/skills/opk-review-pass/SKILL.md)
§2/§6 sync with it.

Not touched: fresh-context reviewer staffing (the invariant this
process exists to keep — RM-0132), the ONE-batch rule, the curator
gate (headline 4), tier staffing (the reviewers-by-tier table confirms
the ladder: low/micro rounds run exactly 1 axis in 73 rounds; the 8
`reviewers:0` rows are tier-none or disclosed main-direct deviations).

## Why no learnings.md update

The 2026-10-22 recipe says every run updates
[agent/learnings.md](../../../agent/learnings.md) — that rule targets
error-class runs. This run measures process staffing; its outcome is a
rule recalibration, not a recurring code-error class. Stated here so
the convention is answered, not skipped silently.

## Recipe (re-run)

```sh
cd internal/reviews-meta/<new-run>/data
python3 extract.py [corpus-start-date]   # gh + sqlite, read-only
# then recompute the tables in statistics.md §Tables
```

Validation for this run: the script reproduced the frozen
`rounds.jsonl` / `subagents.jsonl` byte-identically (2026-11-07).
