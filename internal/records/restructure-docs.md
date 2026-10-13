# restructure-docs — the docs/* restructure (issue #170)

> Status: **IMPLEMENTED** — landed 2026-10-14 on
> `feature/issue-170-restructure-docs` (commits `1e1fdc3`…
> `d8ba19e`). Where wording differs from the tree, the tree wins.

## 1. Problem & goal

`docs/` had grown to 157 files — the internal part outnumbered the user
manual five to one: 79 review evidence files flat in one folder, a
hand-maintained review index with 3,800-character lines, five document
characters mixed under `design/`, no audience separation, and a naming
scheme whose version stem (`v0.0.49`) never said what a review actually
reviewed. Goal (issue #170): a future-proof structure by audience
(USER / AGENT / MAINTAINER), review evidence that scales, and the
discipline enforced by tests instead of memory.

## 2. Decisions

| Decision | Result |
|---|---|
| Geometry | two-world split: `agent/` top level + `internal/` umbrella; root keeps 7 dirs; `docs/` = user manual only |
| Internal areas | `internal/{process, records (+_archive), reviews, reviews-meta}` |
| Archive rule | no global `_archive/`; each area owns one; old `_archive/` + `evaluate/` → `records/_archive/` |
| Review key | birth-PR `pr-NNNNN/` (5-digit; GitHub allocates — parallel-safe) |
| Case naming | `review-a.md`, `review-b.md`, … (uniform from a, `aa` after z) + exactly one `resolution.md` |
| Retrofit | B — move + normalize; snapshot bodies byte-identical except the pointer line |
| Legacy bridge | frozen `reviews/legacy-index.md` (stem → case map); legacy citations `0.0.49b C1` stay valid |
| Citation | new cases: `#176 a W1` (PR number, snapshot letter, finding ID) |
| Index | generated `reviews/INDEX.md` (`scripts/gen-review-index.py`); parity test pins byte-identity |
| Review subject | mandatory `review-meta` header for new snapshots; subjects are metadata, never folder names |
| Meta-analysis | runs under `reviews-meta/{YYYY-MM-DD}/`; tool in `scripts/reviews-meta-aggregate.py` |
| Docs wrap | prose ≤ 120 content columns; line-length ratchet extended to agent/, internal/, docs/, root files |
| Exemptions | frozen history may carry stale links; INDEX/legacy-index are generated, never hand-edited |
| Status words | corpus vocabulary IMPLEMENTED / CURRENT / SUPERSEDED; consistency pin record ↔ records index |
| AGENTS.md | router only — always-on rules plus routing to `agent/` and `internal/` |
| Terminology | "case" everywhere (English-only rule; the German planning term must not ship) |

## 3. Rejected alternatives (kept for context)

- **Sequential `NNNN` case ids** — collide when features run in
  parallel (both take "the next free number"); PR allocation removes
  the coordinator entirely.
- **Date- or branch-keyed folders** — dates pin badly (cases span days,
  midnight flips); branches die and are not 1:1 with cases (0.0.45d–f
  all rode `feature/release-0.0.46`).
- **`docs/internal/` umbrella (one gate)** — the root would say nothing
  about the two worlds; always-on agent rules deserve a top-level home
  next to AGENTS.md.
- **Keeping a hand-maintained index** — the old one grew 3.8k-char
  lines; generation plus a parity test scales for free.
- **ADR-style numbering for records** — issues plus status lines
  already give stable identity; a second numbering adds bookkeeping.
- **Clean-cut legacy block (`reviews/_legacy/`)** — two visible schemas
  forever; the birth-PR reconstruction (git merge subjects, validated
  against the GitHub API, 78/78 files) made one namespace possible.
- **`internal/evaluations/` as a living area** — third-party tool
  assessments are an information collection: relevant verdicts flow
  into records, the rest archives (`records/_archive/evaluations/`).

## 4. Final layout

```
repo/
├── agent/            conventions, learnings (L1–L7), test-fidelity
├── docs/             user manual only (concepts / how-to / reference)
├── internal/
│   ├── process/      review-concept, release-handling, ci-review
│   ├── records/      14 design records + this one; _archive/{design,
│   │                 security, evaluations}
│   ├── reviews/      README, INDEX (generated), legacy-index (frozen),
│   │                 pr-00109…pr-00171 case folders
│   └── reviews-meta/ one frozen folder per analysis run
└── scripts/          gen-review-index.py, reviews-meta-aggregate.py
```

## 5. Enforcement

- `tests/unit/test-docs.sh` — link check over docs/ + agent/ +
  internal/, frozen-history exemption, records status pin
- `tests/unit/test-reviews-lint.sh` — folder and file naming, snapshot
  letter contiguity, header ID/snapshot consistency
- `tests/unit/test-reviews-parity.sh` — INDEX ↔ cases both directions,
  generator byte-parity, pointer ↔ resolution
- `tests/unit/test-line-length.sh` — docs scope added (limit 120);
  snapshots, archive, and generated files exempt

## 6. Verification

All unit suites, lint, and check-version green at every commit; e2e
not owed (docs/tooling-only waves). Discrimination proven by sabotage
against committed state (each red, restored, green again): frozen
exemption, letter gap, index hand-edit, phantom folder, missing
pointer, status flip.

Incidents the guards caught — kept as learnings for future waves:

- exec bits set via `git update-index --chmod=+x` were reset by a later
  `git add -A` (the documented procedure exists for exactly this);
- path-lengthening edits tripped the line-length ratchet twice —
  reflowed instead of regenerating the baseline;
- three records were misclassified in the first index pass — the new
  status pin caught them (the files are the truth);
- one historical snapshot (0.0.39-c) had never carried its resolution
  pointer — repaired via the one sanctioned edit;
- a sabotage round ran against an uncommitted tree and its restore
  wiped work-in-progress — the AGENTS sabotage rule, relearned;
- the German planning term leaked into 21 shipped spots — maintainer
  catch; the claim audit now includes a language pass.

## 7. Touch points

Commits on `feature/issue-170-restructure-docs`: `1e1fdc3` (geometry
wave), `b8fbd26` + `0dd7c26` (review-system wave + exec-bit fix),
`78b8ae1` + `9c68b09` + `d8ba19e` (status vocabulary, AGENTS router,
baseline burn-down, case rename). The full planning trail — including
the 19-project research base and the double-verified birth-PR map —
lives in the maintainer's dev workspace (`local/restructure-docs/`,
not shipped).
