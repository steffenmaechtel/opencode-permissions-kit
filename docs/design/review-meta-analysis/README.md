# Review meta-analysis — recurring error classes and learnings

> **Status: CURRENT (analysis run 2026-10-10).** Corpus: every review snapshot
> and resolution under [design/review/](../review/README.md) for versions
> **0.0.38–0.0.46** (2026-09-26 → 2026-10-09): 54 snapshots, 9 resolutions,
> 620 extracted finding rows. The numbers in this folder are a **point-in-time
> measurement of that corpus**, not a live statistic — re-run the extraction to
> extend them (recipe at the bottom). Enforcement short-form:
> [learnings.md](learnings.md) — the per-wave checklist every agent gets
> (linked from AGENTS.md; no statistics reading required to apply it).
> Companion pages:
> [statistics.md](statistics.md) (full tables, as of this run),
> [further-analyses.md](further-analyses.md) (review precision, provenance,
> blind spots, convergence). Finding-level data, taxonomy spec and aggregation
> script: [data/](data/) (run 2026-10-10).

## Why this record exists

The review loop produces snapshots and resolutions per version, but nothing
aggregate: *do the same mistakes come back with every new feature?* This
analysis answers that once for the whole corpus, and turns the answer into
the per-wave checklist in [learnings.md](learnings.md) (linked from
[AGENTS.md](../../../AGENTS.md)) so the learnings are enforced, not just
recorded.

## Headline results (as of 2026-10-10)

1. **Yes — the same classes recur.** `silent-failure` appears in all 9 version
   groups; the snapshots themselves cross-reference earlier findings as a
   "class" 45 times ("the 0.0.42d class", `0.0.39g S2`, `#112 class`).
2. **Fix waves are the most productive defect source.** 20 % of all reported
   findings are *fix-induced* (112/553) — the wave that repairs a review
   finding introduces the next one.
3. **Enforced process steps demonstrably kill classes.** `docs-policy`
   25→0 (same-PR docs rule), `sibling-sweep` → 0 in 0.0.46 (class-sweep
   discipline), `test-vacuous` 12→2 (sabotage-verify). Merely *naming* a class
   did not stop it — the enforced step did.
4. **`tests-unit` is hotspot #1** (92 findings; dominated by `test-vacuous` +
   `test-gap`): the tests themselves are the least-verified code we ship.
5. **External full reviews are the only reliable source of `perm-model`
   HIGHs.** Same tree `b3418ac`: internal pass 0.0.42d found 2 MED; the
   external pass 0.0.42e found 2 HIGH + 6 MED (incl. the uninstall-symlink
   chown and the `rm -rf` sandbox breach).

## Recurring classes, with their chains

Every chain below is evidenced by the snapshots' own cross-references (all 45
backward edges in [data/stats.json](data/stats.json), `crossref_backward`).

### `silent-failure` — 62 findings, 13 MED/HIGH, all 9 version groups

The most persistent class: swallowed errors, silent aborts, lying success
messages. Probe-abort sub-chain (timeout/pipe probes kill the installer
silently under `set -eu + pipefail` — each time at a NEW feature site):

```
0.0.39b C2 → 0.0.42d S3 → 0.0.45a S1 → 0.0.45c C1/C2
```

### `sibling-sweep` — 46 findings, 13 MED/HIGH, 8 version groups → 0 in 0.0.46

A class gets fixed at the site the finding named; the same-shape siblings stay
broken: `0.0.38 C2` → `0.0.39e C1/C3` → `0.0.39h F1` (HIGH, "missed sibling
despite full-class claim") → `0.0.42f` → `0.0.44d F1` → `0.0.45e W1` (closure
stopped at `bin/opk`, the `ddev-handover` pairs stayed chown-first).

### `claim-drift` — 77 findings, rank 1, still nonzero in 0.0.46

Comments, docs, log lines and hints assert behavior the code does not deliver:
"never abort" (`0.0.45c C1`), "race-free" (`0.0.45d W1`), "make test runs 31
suites" (really 27, `0.0.39d D1`). The only large class without a collapsed
trend — claims move outside diffs, so wave reviews never see them age.

### `test-vacuous` — 37 findings, the "0.0.42d class"

Pins that stay green when the mechanism breaks: source-grep pins
(`0.0.39a C4`), revert-nondiscriminating pins (`0.0.44b W11/W12`), guard
blindness to continued lines (`0.0.42f C3`), pins placed after the summary
gate — fail-but-green (`0.0.44c C1`), pins vacuous on CI where no kit is
deployed (`0.0.46a F2`). Named three times: `0.0.42d` → `0.0.44g G1` →
`0.0.45a C1`.

### `perm-model` + `race-toctou` — 53 findings, 23 MED/HIGH, 5 of the 12 HIGHs

The root/symlink family with the longest technical chain in the corpus:

```
0.0.39g S1/S2 (root cp/chown dereferences planted symlinks)
→ 0.0.39h F2 (parent component ungated) → 0.0.42e S1/S2 (uninstall chown)
→ 0.0.43a F16 (trailing-slash gate bypass) → 0.0.44a V2 (reopened F16!) / V24
→ 0.0.45c S2 (finalize chown on manifest symlink) / S4 (scan-then-act)
→ 0.0.45d W1 → 0.0.45e W1 (chmod/chown walk order) → 0.0.46a F8
```

### `fix-regression` — 19 findings, 11 MED/HIGH

The fix itself breaks something: `0.0.39j F1` (gate reorder left
`.config/opencode` root-owned on fresh installs), the 0.0.44 chain (7 in one
day; W1 HIGH: the wave broke the rule it had added hours earlier),
`0.0.45d W1` (reorder closed one direction only), `0.0.46b W1` (fix claim
false at the very path the finding named).

### `shell-semantics` — 46 findings, 14 MED/HIGH (front-loaded)

The scaffolding era (0.0.38/0.0.39: bare `set -e`, eval, unguarded `grep -v`
under new pipefail) is structurally fixed; what remains are individual forms
(TSV/IFS collapse, unquoted spaced homes, bare `cd` under `set -e`).

## Learnings (per-wave checklist)

The rules live in **[learnings.md](learnings.md)** — one page, no statistics
required to apply them: **L1** fail-loud pins · **L2** class sweep · **L3**
claim audit · **L4** pins discriminate + sit before the summary gate · **L5**
root-operand inventory · **L6** fix waves are first-class code · **L7** script
skeleton. Each rule carries its verification criterion and a one-line evidence
citation there; [AGENTS.md](../../../AGENTS.md) links the same list as the
agent-facing short form.

## What worked (keep doing it)

- Same-PR docs rule → `docs-policy` collapsed 25 → 13 (spike) → 0.
- Sabotage-verify (AGENTS.md, Testing) → `test-vacuous` 12 → 2.
- Class-sweep culture (0.0.45e/f, 0.0.46c "in one class disposition") →
  `sibling-sweep` 0 in 0.0.46.
- External pre-release full reviews (0.0.42e, 0.0.45b–c) → the only source of
  `perm-model` HIGHs; keep before every release.
- Snapshot-with-first-fix-commit (README rule 4) → chain convergence time fell
  from 16 snapshots (0.0.39) to 3 (0.0.46) — see
  [further-analyses.md](further-analyses.md#4-convergence-speed).

Open flanks: `silent-failure` and `claim-drift` have no enforced step yet —
L1 and L3 are the proposals.

## Caveats

- Classification came from extraction agents (9 batches, one taxonomy);
  judgment calls are documented in [data/](data/README.md).
- A few known duplicate rows where parallel in-review agents found the same
  defect (e.g. `0.0.42d S1=C1`) — negligible for trends.
- Severity partly inferred (Q-tier and ghost rows), flagged per row in the
  JSON (`severity_inferred`).
- Read counts **relatively**, not absolutely: `n` is finding rows, weighted by
  the H/M columns for significance.

## Re-running this analysis

The corpus grows with every review; this record is designed to be re-measured
(not patched by hand). Recipe (details in [data/README.md](data/README.md)):

1. Freeze the corpus cut (which snapshots are in scope) and note the run date.
2. Extract with parallel subagents per [data/extraction-spec.md](data/extraction-spec.md)
   — batches of ~8–10 files / ≤110 KB, one JSON per batch. Parallelism rule
   from the 2026-10-10 run: at most 5 concurrent GLM-5.3 subagents; larger
   batches (or retries after rate-limit failures) run on GLM-5.3-Flash.
3. Aggregate: `cd docs/design/review-meta-analysis/data && python3 aggregate.py`
   → fresh `stats.json`.
4. Archive the previous run's files into `data/<YYYY-MM-DD>/` (runs are
   immutable once written, like snapshots), put the new run's files in
   `data/`, update the tables in statistics.md / this page with the new
   run date in the header, and check [learnings.md](learnings.md#when-a-rule-fails):
   a class recurring after its rule landed means the rule needs sharpening.
5. Compare: the class × version matrix grows to the right; a class that
   recurs after its learning landed is a failed learning — escalate it
   (AGENTS.md checklist wording, or a gate).
