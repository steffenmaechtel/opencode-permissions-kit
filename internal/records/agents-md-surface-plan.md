# AGENTS.md surface plan — deferred options and the nested-file budget

> Status: **CURRENT.** Records the deferred decisions of issue #768 so
> they stay findable instead of living in chat history: the e2e-split
> and O3-skill triggers, the cap-retune procedure, and why the nested
> `tests/AGENTS.md` carries no size budget today. The three deferral
> items are the plan as decided in the issue's follow-up comment
> (2026-11-25), adapted only where this repository's citing rules and
> the implementation reality required it — each adaptation is noted
> inline.

## Nested AGENTS.md budget (status after the O4 wave)

≤ 4 KB was the pre-implementation target for `tests/AGENTS.md` — a
good target size in the abstract, set in the research comment before
any content moved. The implementation then showed the moved sandbox
policy weighs ~8 KB, and reaching 4 KB would have meant compressing
rule text very heavily. Deliberately NOT compressed: the risk of
losing important details in the fast process outweighed the size
target — the section moved verbatim instead (the rule metas mirror
the rationale, but not every operational nuance). The compression
question is its own follow-up decision, taken with the M1/M2
re-measurement (two weeks after the split) as input; until then NO
budget is pinned or documented for nested AGENTS.md files.

## Deferred options

1. **E2e-split trigger** — when `tests/AGENTS.md` presses against its
   budget (the research figure was ≤ 4 KB; the status note above is
   where the decision stands today), splitting into
   `tests/e2e/AGENTS.md` and/or `tests/unit/AGENTS.md` is the next
   option (research: #768; nesting depth root + max one level per the
   survey).
2. **O3 skill trigger** — if fix waves again produce losses of the
   class "wave sequence wrong/forgotten", consider a fix-wave skill
   on the opk-review-pass pattern: process sequence in the skill,
   knowledge stays in `agent/` (entry-point content → skill;
   declarative content → files).
3. **Cap-retune procedure** — three touchpoints move together:
   `tests/unit/test-docs-loop.sh` (the `AGENTS_MD_CAP` assignment),
   the Rules byte-cap bullet in `AGENTS.md` (at ~line 153 before the
   O2 rewrite — adapted: the line number moved with the rewrite), and
   the byte-cap meta (the AGENTS.md#rules byte-cap unit's own meta
   file, bucket `internal/rules-meta/0/2/1/` — adapted: cited by file
   and section, the bare ID would trip the no-fake-findings pin). A
   retune that misses one of the three fails claim-audit /
   rules-meta parity.

## What landed (context)

The implementing session ran the issue's sequencing: M3 baseline
first (review-efficiency extraction, `internal/reviews-meta/
2026-11-25/`), then the O2 root rewrite (AGENTS.md 27,351 → 12,758
bytes; detail to `agent/gates.md`), then the O4 nested file
(this wave). The cap retune is its own wave at the end.
