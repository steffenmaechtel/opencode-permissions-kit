# Rule-Meta System (RM) — design record

> Status: **CURRENT** — rollout complete.
> This is the design record for the
> rule-rationale system; the governed rule texts live in `agent/*.md`
> and in the `## Rules` section of `AGENTS.md`. Where this record
> conflicts with the implemented audit script, the code wins. The
> decisions in this record are equipped with rule-metas — the record
> documents itself.

## Problem

Rules in `agent/*.md` and `AGENTS.md ## Rules` were correct when they
were introduced, but change — version bumps, restructures, insights
from review waves — makes them obsolete or imprecise, and that rot
surfaces only by accident. The rule-meta system gives every rule a
falsifiable rationale, a revisit cycle, and a history, so a reviewing
agent can detect obsolescence by checking whether the rationale still
holds.

## The main rule

- Every rule carries a falsifiable rationale in an externalized
  meta file, referenced from the rule — this rule included. (RM-0001)

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Main rule | every rule carries a rationale, externalized into a meta file referenced from the rule (RM-0020) |
| 2 | Rule unit | one bullet / list item (not file, not section) — an estimated 100+ metas at full rollout (RM-0021) |
| 3 | ID format | `RM-NNNN` — 4 digits zero-padded, globally sequential, never recycled or renumbered (RM-0022) |
| 4 | Reference syntax | `(RM-NNNN)` at the bullet's end; no dates or history inline in rule files (RM-0023) |
| 5 | Storage | `internal/rules-meta/N/N/N/` — three one-digit levels, 10 entries max per node (RM-0024) |
| 6 | Index & report | **both**: committed `INDEX.md` regenerated per audit run + the audit's stdout report (RM-0025) |
| 7 | Pilot scope | `agent/` (4 files) + `AGENTS.md ## Rules` from the start |
| 8 | Language | English — repo rule: all content is English (RM-0026) |
| 9 | Rule prose | rule-bearing paragraphs are rewritten as list items — paragraphs stay narrative/lookup (RM-0045) |
| 10 | learnings.md | out of meta scope: rationale = inline corpus stats, lifecycle = meta-analysis runs (RM-0046) |
| 11 | Rule-text detail | the rule plus a one-line why; detailed provenance lives in the meta rationale (RM-0056) |

## Meta format v1.1

```markdown
---
id: RM-NNNN
rule: agent/conventions.md#shell-security-untrusted-input
quote: "first words of the bullet"
created: 2026-10-14
status: active            # active | retired
reviewed: 2026-10-15      # maintainer approval date; absent = review pending
revisit-interval: 1m      # ladder: 1m 6m 1y 2y — always starts at 1m
next-revisit: 2026-11-14
---
<3-6 plain sentences: the external, checkable fact that makes the
rule necessary — not a paraphrase of the rule.>
Check: <optional: one sentence — how a revisit verifies the fact still holds.>
Source: <one line finding/directive/issue — only if one exists.>

## Review log
- 2026-10-14 created — agent draft; maintainer review pending.
```

Body rules:

- **The review log names the true author** ("agent draft" vs. "from
  maintainer raw note") — provenance is never overstated. Rationale
  content originates with the maintainer wherever possible; the agent
  formalizes. (RM-0094)
- **RM references appear only where load-bearing** — the unit's
  trailing ref and genuine dependencies inside a rationale; never as
  narrative decoration in logs or prose. (RM-0034)
- **In meta bodies, cross-references name the rule's text, not its
  ID** — a reader holding one meta cannot resolve an RM number, and
  IDE search hits both refs and prose. (RM-0093)
- **Examples use the abstract token `RM-NNNN`**, never a real meta's
  number — a real number inside an example is indistinguishable from
  a reference in IDE searches. (RM-0035)

## Quality bar for rationales

A rationale is a falsifiable claim about the world — the external
fact that necessitates the rule (version pin, incident, upstream
behavior, environment property). Revisit question: *does this fact
still hold?* A rationale that merely restates the rule is a defect. (RM-0027)

## Revisit ladder

- Every new meta starts at `1m`. (RM-0031)
- Clean revisit → up one step: `1m → 6m → 1y → 2y` (`2y` is the max). (RM-0028)
- Revisit with findings or changes → back to `1m`. (RM-0032)
- `next-revisit` = revisit date + new interval — never computed from
  the stale due date (lateness must not compound). (RM-0033)

## Revisit workflow

The ladder defines the intervals; this is how a revisit runs (phase
4). `make rules-report` (`scripts/rules-report.sh`) is the worklist:
overdue metas first (most overdue first), then everything due within
a 30-day horizon (`HORIZON=<days>` overrides), then the approval
queue (metas without maintainer approval — the same membership the
INDEX reports). It is a report, not a gate: overdue work never
reddens CI (the audit's overdue lane is non-blocking by design), and
the report's exit code only signals usage or environment failures.

A revisit has two halves. The judgment half is the agent's: read the
rationale, run its `Check:` probe where present, and decide whether
the external fact still holds. The mechanical half is scripted —
`sh scripts/rules-revisit.sh RM-NNNN clean|findings ["note"]` bumps
the ladder (clean: up one step, 2y max; findings: reset to 1m),
computes the next date calendar-correct from the revisit day itself,
and appends one review-log line. A revisit log line is not an
approval — `reviewed:` stays with the maintainer. A `findings`
verdict enters the normal fix flow: rule text and rationale are
corrected like any other code, in a PR. The first real wave lands
2026-11-14 – 2026-11-20 (the pilot-era metas, ~100 at once — expect
a bulk session, not one-off touches).

## Audit invariants (deterministic, CI)

`scripts/rules-audit.sh`, pinned by `tests/unit/test-rules-meta.sh`:

1. Every rule unit in audit scope carries exactly one `(RM-xxxx)` ref.
2. Every ref resolves: `internal/rules-meta/<N>/<N>/<N>/RM-xxxx.md`
   exists (buckets = the ref's first three ID digits).
3. 1:1 — no meta is referenced by two units; an active meta without a
   back-ref fails (orphan).
4. Filename ↔ `id:` identical; IDs unique.
5. The `rule:` back-ref exists; the `quote:` prefix is findable in the
   target file (normalized: code backticks/bold stripped, wrapped
   lines joined; needle = the quote's first five words).
6. Frontmatter complete, ISO dates, `next-revisit` ≥ `created`.
7. Report (non-blocking): overdue list, sorted by lateness.
8. `INDEX.md` is regenerated on every run.
9. Approval consistency: `reviewed:` is set exactly when the review
   log carries an `approved by maintainer` entry of the same date —
   absent field with approval line, or field without line, both fail
   (provenance must never overstate; maintainer decision 2026-10-16).

CI blocks on 1–6 and 9; an overdue meta is a maintenance signal, not a
broken build. (RM-0030) The Phase-2 pending-unit parking valve
(prefix-matched ref-less units reported non-blocking) was retired
2026-10-17 when its five occupants received metas — a ref-less unit
in an active section now always blocks.

## Retire

The rule bullet is removed from the rule file; the meta stays with
`status: retired`. Metas are never deleted — they are the
institutional memory. Retired metas are exempt from the back-ref
invariant. (RM-0029)

## Rollout

| Phase | Content | Status |
|---|---|---|
| 0 | Pilot `conventions.md` — first metas landed, interval policy set | done |
| 1 | Remaining `conventions.md` units (metas 0004 ff.) | done — approved 2026-10-16 |
| 2 | `scripts/rules-audit.sh` + `tests/unit/test-rules-meta.sh` + CI wiring + INDEX | done |
| 2b | conventions.md coverage complete: every unit carries a meta | done — approved 2026-10-17 |
| 3 | agent files + AGENTS Rules | done — test-fidelity 2026-10-18; review-concept 2026-10-19; AGENTS 2026-10-20 |
| 4 | Revisit workflow: `make rules-report` + agent revisit command | done 2026-10-22 |
| 5 | Self-application: the main rule gets the first number, 0001 | done 2026-10-22 |

The 2026-10-19 review-concept step split the file: operative rules in
`agent/review-concept.md`, history and calibration data in
`internal/records/review-calibration.md`. The review-concept metas and
the record's own body rules and scope defaults were maintainer-approved
the same day (direct chat review); revision details live in the metas'
review logs.

The nine AGENTS Rules metas were maintainer-approved
2026-10-20 (direct chat review).

## Open defaults (the pilot validates them)

- Table rows in rule files are not rule units (lookup info). (RM-0095)
- Narrative-heavy sections start outside the audit scope; the section
  allowlist lives in the audit script and is reviewable. (RM-0096)

learnings.md is out of meta scope (decision 10): its rationales are
the inline corpus statistics and the meta-analysis runs own its
lifecycle; the run-L1–L7 obligation got its meta via the
`AGENTS.md ## Rules` bullet — one of nine Rules units equipped on
2026-10-20. The rule-bearing sentence moved out of
the "Review learnings" narrative (decision 9).

## Rejected alternatives

- `agent/meta/` as storage — violates `agent/`'s own definition
  ("always-on reading"; metas are read only at revisit), and root-level
  rules from `AGENTS.md` would live under `agent/`.
- Mirrored subfolders per source file — drift when rules move between
  files (that happens); needless audit complexity.
- Sidecar folders (`conventions.meta/`) — no repo pattern, poor
  globbing, no answer for `AGENTS.md`.
- Bare `#37` IDs — indistinguishable from GitHub issue numbers; the
  repo is grep-able by design.
- Shared metas for multiple rules — collides with revisit/history
  semantics (which rule is due?).
- Section/file granularity — rejected for single-rule precision; the
  price (100+ files) is paid down by the generated INDEX.
- Per-rule initial intervals (e.g. 2y for stable rules) — superseded
  2026-10-14 by the uniform `1m` start with escalation ladder.
