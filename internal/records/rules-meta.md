# Rule-Meta System (RM) — design record

> Status: **ACTIVE BUILD-OUT** — pilot running since 2026-10-14 on
> `feature/rules-meta-pilot`. This is the design record for the
> rule-rationale system; the governed rule texts live in `agent/*.md`
> and in the `## Rules` section of `AGENTS.md`. Where this record
> conflicts with the implemented audit script, the code wins. The
> decisions in this record are being equipped with rule-metas as the
> second pilot wave (the record documents itself).

## Problem

Rules in `agent/*.md` and `AGENTS.md ## Rules` were correct when they
were introduced, but change — version bumps, restructures, insights
from review waves — makes them obsolete or imprecise, and that rot
surfaces only by accident. The rule-meta system gives every rule a
falsifiable rationale, a revisit cycle, and a history, so a reviewing
agent can detect obsolescence by checking whether the rationale still
holds.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Main rule | every rule carries a rationale, externalized into a meta file referenced from the rule (RM-00020) |
| 2 | Rule unit | one bullet / list item (not file, not section) — an estimated 100+ metas at full rollout (RM-00021) |
| 3 | ID format | `RM-NNNNN` — 5 digits zero-padded; globally sequential; never recycled, never renumbered (a retired rule keeps its number). Allocation is chronological (next free number), not positional; `RM-00001` stays reserved for the main rule itself (RM-00022) |
| 4 | Reference syntax | `(RM-NNNNN)` at the end of the bullet (last line of the item); no dates or history inline in rule files (RM-00023) |
| 5 | Storage | `internal/rules-meta/` — flat, no subfolders (naming precedent: `internal/reviews-meta/`) (RM-00024) |
| 6 | Index | `internal/rules-meta/INDEX.md`, regenerated on every audit run, grouped by source file + section (precedent: the generated review `INDEX.md`) (RM-00025) |
| 7 | Pilot scope | `agent/` (4 files) + `AGENTS.md ## Rules` from the start |
| 8 | Language | English — repo rule: all content is English (RM-00026) |

## Meta format v1.1

```markdown
---
id: RM-NNNNN
rule: agent/conventions.md#shell-security-untrusted-input
quote: "first words of the bullet"
created: 2026-10-14
status: active            # active | retired
revisit-interval: 1m      # ladder: 1m 6m 1y 2y — always starts at 1m
next-revisit: 2026-11-14
---
<3-6 plain sentences: the external, checkable fact that makes the
rule necessary — not a paraphrase of the rule.>
Check: <one sentence — how a revisit verifies the fact still holds.>
Source: <one line finding/directive/issue — only if one exists.>

## Review log
- 2026-10-14 created — agent draft; maintainer review pending.
```

Body rules:

- 3-6 simple sentences; no long paragraphs; `Check:` and `Source:`
  lines are optional.
- **The review log names the true author** ("agent draft" vs. "from
  maintainer raw note") — provenance is never overstated. Rationale
  content originates with the maintainer wherever possible; the agent
  formalizes.

## Quality bar for rationales

A rationale is a falsifiable claim about the world — the external
fact that necessitates the rule (version pin, incident, upstream
behavior, environment property). Revisit question: *does this fact
still hold?* A rationale that merely restates the rule is a defect. (RM-00027)

## Revisit ladder

- Every new meta starts at `1m`. (RM-00031)
- Clean revisit → up one step: `1m → 6m → 1y → 2y` (`2y` is the max). (RM-00028)
- Revisit with findings or changes → back to `1m`. (RM-00032)
- `next-revisit` = revisit date + new interval — never computed from
  the stale due date (lateness must not compound). (RM-00033)

## Audit invariants (deterministic, CI)

`scripts/rules-audit.sh`, pinned by `tests/unit/test-rules-meta.sh`:

1. Every rule unit in audit scope carries exactly one `(RM-000xx)` ref.
2. Every ref resolves: `internal/rules-meta/RM-000xx.md` exists.
3. 1:1 — no meta is referenced by two units; an active meta without a
   back-ref fails (orphan).
4. Filename ↔ `id:` identical; IDs unique.
5. The `rule:` back-ref exists; the `quote:` prefix is findable in the
   target file.
6. Frontmatter complete, ISO dates, `next-revisit` ≥ `created`.
7. Report (non-blocking): overdue list, sorted by lateness.
8. `INDEX.md` is regenerated on every run.

CI blocks on 1–6; an overdue meta is a maintenance signal, not a
broken build. (RM-00030)

## Retire

The rule bullet is removed from the rule file; the meta stays with
`status: retired`. Metas are never deleted — they are the
institutional memory. Retired metas are exempt from the back-ref
invariant. (RM-00029)

## Rollout

| Phase | Content | Status |
|---|---|---|
| 0 | Pilot `conventions.md`: RM-00003 approved (`c3b1a5b`), RM-00002 committed as draft (`c3755be`), interval policy (`9c8f109`) | running |
| 1 | Remaining `conventions.md` units (`RM-00004` ff.) | open |
| 2 | `scripts/rules-audit.sh` + `tests/unit/test-rules-meta.sh` + CI wiring + INDEX | open |
| 3 | Remaining `agent/` files + `AGENTS.md ## Rules` | open |
| 4 | Revisit workflow: `make rules-report` + agent revisit command | open |
| 5 | Self-application: the main rule gets `RM-00001` | open |

## Open defaults (the pilot validates them)

- Table rows in rule files are not rule units (lookup info).
- Narrative-heavy sections start outside the audit scope; the section
  allowlist lives in the audit script and is reviewable.
- `learnings.md` "Keep doing (trend-proven)" is in scope — starts at
  `1m` like everything else; the ladder shapes intervals from there.

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
