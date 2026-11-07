# Statistics — subagent staffing run 2026-11-07

> Point-in-time measurement (see the [run README](README.md) for scope,
> commission and caveats). All data frozen in [data/](data/):
> `rounds.jsonl` (132 rounds), `subagents.jsonl` (339 sessions),
> `markers-parsed.jsonl` (171 raw markers). Era terms: **pilot**
> 10-26 → 10-28 (gates unwritten), **adoption** 10-29 → 11-01 (gates
> fresh, PR #291), **settled** 11-02 → 11-06.

## Role × tier economics (339 subagent sessions)

| Role | Tier | n | median min | p10 | p90 | total h | in-tok (M) | out-tok (M) |
|---|---|---|---|---|---|---|---|---|
| reviewer | fast | 218 | 8.0 | 4.7 | 11.7 | 29.9 | 15.0 | 1.15 |
| reviewer | strong | 3 | 9.6 | 6.3 | 14.6 | 0.5 | 0.23 | 0.03 |
| curator | fast | 34 | 3.0 | 1.8 | 4.8 | 1.9 | 1.14 | 0.19 |
| verifier | strong | 81 | 5.6 | 2.6 | 10.3 | 8.6 | 4.51 | 0.54 |
| verifier | fast | 2 | 4.4 | 3.5 | 5.3 | 0.1 | 0.07 | 0.01 |
| other (research probe) | strong | 1 | 1.8 | — | — | 0.0 | 0.02 | 0.00 |

Sessions per role over time (pilot → adoption → settled): reviewers
42 → 62 → 117; curators 15 → 12 → 7; verifiers 15 → 28 → 40. Round
volume grew (18 → 63 → 51 rounds); curator use per round FELL from
1.0+ to 0.14 while verifier use held ~0.4–0.8/round — the curator gate
biting, the verifier gate still firing on count.

## Verifier sizing gate (RM-0127) — compliance simulation

Gate as written: ≤ 5 curated findings AND all LOW/INFO → main inline;
otherwise exactly one verifier batch. 132 rounds; 9 pure closing
summaries and split-part duplicates excluded before simulation.

| Era | Rounds | As prescribed | Over-fired | Skipped owed | No field |
|---|---|---|---|---|---|
| pilot (gates unwritten) | 18 | — | — | — | 8 |
| adoption | 63 | 55 | 7 | 1 | 0 |
| settled | 51 | 51 | 0 | 0 | 0 |

Over-fired rounds (batch ran although LOW/INFO-only, ≤ 5 curated):
#309 d (1), #316 a (5), #326 a (4), #331 a (3), #337 b (5), #341 a (4),
#351 a (4). Skipped owed batch: #329 b (4 findings, **2 MED**, 10-31).

## The calibration zone — LOW/INFO-only rounds with > 5 curated findings

Every round that ever hit the count arm of the gate (gate era), with
what the batch produced:

| Round | Curated | Tier | Track | Verifier batch | Retractions |
|---|---|---|---|---|---|
| #336 a | 7 | med | non-shipped | 1 | 0 |
| #338 a | 6 | med | shipped | 1 | 0 |
| #360 b | 7 | low | shipped | 1 | 0 |
| #386 c | 6 | low | shipped | 1 | 0 |
| #399 b | 6 | low | non-shipped | 1 | 0 |
| #404 a | 8 | med | shipped | 1 | 1 |

6 batches ≈ 6 strong-tier sessions ≈ ~34 min agent time, ~0.33M input
tokens — 1 retraction, unattributable (main audit co-verifies; verdict
files live in deleted session scratch). Pilot-era zone rounds without a
batch (#301 d, 6 curated; #320 close, 8) suffered no measurable harm
either — the arm is cost without yield in BOTH directions.

## Retraction yield by round shape (gate era, 114 rounds)

| Shape | Rounds | Retractions | Rate/round |
|---|---|---|---|
| MED/HIGH present | 37 | 9 | 24% |
| LOW/INFO only, ≤ 5 | 53 | 4 | 7.5% |
| LOW/INFO only, > 5 | 6 | 1 | 17% (single case) |
| 0 findings (fix-wave re-reviews) | 18 | 0 | 0% |

The one main-inline retraction with `verifiers:0` (#349 a, 3 LOW/INFO)
shows main's audit catches LOW/INFO ghosts without a batch. LOW/INFO
ghost risk is additionally netted by the next round's fresh re-review
of any fix.

## Curator gate (RM-0126) — compliance

| Era | Curator subagent | Main curated | Over-deployed |
|---|---|---|---|
| pilot (gate unwritten) | ~15 sessions / 18 rounds (field unrecorded) | 0 | n/a (pre-gate default) |
| adoption | 14 | 49 | 9 |
| settled | 9 | 42 | 0 |

The 9 adoption-week over-deployments are 2-reviewer or low-raw rounds
that spawned a curator anyway (#309 b/c/d, #314 a, #316 a, #317 a/b,
#318 b, #331 a). Settled era is clean in BOTH directions: all 9
gate-owed rounds (3 reviewers AND > 10 raw) got their curator, all 42
non-owed rounds curated main, 0 over, 0 under. (An earlier pass of
this table counted #337 close / #387 e as gate-owed mains — those were
closing-summary aggregates with case-wide counters, not rounds; the
final round set contains neither.)

## Reviewers by round tier (132 rounds)

| Marker tier | Reviewer counts |
|---|---|
| low | 51× one axis, 3× `reviewers:0` |
| micro | 22× one axis, 2× `reviewers:0` |
| med | 16× 3 axes, 3× 2 axes |
| wave (legacy med label) | 11× 2, 9× 3, 4× 1, 1× `reviewers:0` |
| high (snapshot pass) | 1× 10 axes (#370) |
| none / unlabeled | 2× `reviewers:0`, 7× 2–3 axes |

The ladder holds: every low/micro round that staffed at all ran exactly
one axis; the 8 `reviewers:0` rows are tier-none rounds or disclosed
main-direct deviations (RM-0132's vocabulary), not a staffing pattern.

## Marker ↔ db cross-check

| Quantity | Markers (rounds) | db (sessions) |
|---|---|---|
| Reviewer slots / sessions | 210 | 221 |
| Verifier batch rounds / sessions | 59 | 83 |
| Curator subagent rounds / sessions | 28 | 34 |

Deltas are expected: batches staff 1–5 sessions each, early markers
lack fields, and #407's retroactively-posted rounds (b–e posted as one
batch after the fixes) still carried per-round counters. Totals across
all rounds: 574 curated findings (81 MED, 5 HIGH), 20 retractions.

## Model-map deviations (5 sessions, none since 11-01)

- 10-28: 3 reviewer axes on glm-5.3 (strong) — pilot-era "Achse A/B/C"
  round, pre-map.
- 10-31: 2 verifier sessions on glm-5.3-flash ("V3 verify: #285/#282
  round a") — fast-tier verification, the direction the skill calls
  out as quietly breaking the calibrated policy.

## Recipe

See [data/extract.py](data/extract.py) — re-runnable end to end
(gh marker fetch → parse with the #287 hand-fix → round dedup →
sqlite read-only subagent extraction with role classification).
Gotchas baked in: **`verif` must classify before `digest`** ("Verify
digest batch 1" is a verifier — the first pass of this run mis-filed 6
sessions as curators), split-part comments duplicate markers (dedup on
issue+wave), pure closing summaries aggregate whole cases (exclude by
`state=closing-proposed` + wave/raw shape), timestamps are ms-epoch,
V2 sessions live in `session_v2` (`session` holds only legacy V1).
Validation: the script reproduced the frozen outputs byte-identically.
