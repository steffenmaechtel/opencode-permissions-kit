# Code reviews (internal/reviews/)

Model-generated code reviews of the kit live here: one folder per
case, keyed by the pull request that carried the review into the repo.
Reviews are **evidence** — for the agent (pins, learnings corpus) and the
maintainer (release gates). When to review at all, which scope (full vs
diff), and the loop's stop rule:
[review-concept.md](../../agent/review-concept.md).

## Layout and naming

```
internal/reviews/
├── README.md        # this file — mechanics only (the index is generated)
├── INDEX.md         # GENERATED — never hand-edit (parity test pins it)
├── legacy-index.md  # frozen map: old file names → new locations
└── N/N/N/N/         # digit shard — the first four digits of the PR number
    └── pr-NNNNN/    # one case; NNNNN = 5-digit birth-PR number
        ├── review-a.md  # first snapshot; chain letters a, b, c … (aa after z)
        ├── review-b.md  # micro-wave review of the a-wave's fixes
        └── resolution.md
```

- **Shard rule:** case `pr-ABCDE` lives at `internal/reviews/A/B/C/D/`
  — four one-digit levels, at most 10 entries per node, the path
  computable from the key alone. Enforced by
  `tests/unit/test-reviews-lint.sh`.

- **Birth-PR rule:** the case key is the PR that carries the FIRST
  snapshot into the repo. One birth-PR = one case. Later snapshots of
  the chain may ride other PRs. Open the (draft) PR before the review
  runs — GitHub allocates the number, so parallel features can never
  collide.
- **Snapshot letters** are uniform from `a` — no special case for the
  first file. Beyond `z`: `review-aa.md`.
- Exactly **one `resolution.md`** per case.
- Legacy corpus (snapshots 0.0.38–0.0.49, cases pr-00109…pr-00171):
  pre-restructure citation format stays valid — see legacy-index.md.

## Snapshot format

The snapshot body is the reviewer's output **verbatim** (external
machine format since 0.0.45d; older house-format snapshots keep their
era's shape — both stay citable as history). House-owned parts:

- The **mandatory header** (new cases, first lines of the file):

  ```
  <!-- review-meta
  ID: pr-0176
  Snapshot: b
  Subject: issue-175 schnellsuche (feature wave)
  Scope: wave            (full | wave | gate | analysis)
  Base: v0.0.50 @ 1a2b3c4
  Diff: e26f379..24ad0d2
  Date: 2026-10-15
  Reviewer: GLM-5.3 (external /review session)
  -->
  ```

  The lint test pins ID↔folder and Snapshot↔file name. (Legacy cases
  predate the header; their stem + dates live in legacy-index.md.)
- The **one pointer line**

```
> Resolution: [resolution.md](resolution.md)
```

  once a resolution exists — the only edit ever allowed on a snapshot.
- The **reviewer output contract**: the body stays verbatim, but it is
  an interface the house reads — every snapshot must deliver:

  1. **stable, unique finding IDs** (scheme free — W1, F3, Q7 … — one
     scheme per snapshot; citations and dispositions use them),
  2. **a severity per finding** on the house scale
     `HIGH / MED / LOW / INFO` (the stop rule reads MED/HIGH; a
     foreign scale is mapped during verification),
  3. **a findings index early** in the document (table), and
  4. **provenance, gates, and a recommendation** at the end (model,
     tree, gates run).

  A review that cannot deliver these four is reshaped by the embedding
  agent before commit — a snapshot without citable IDs or severities
  breaks disposition, citation, and the stop rule at once.
- The **finding-provenance classification** (fifth deliverable): every
  finding is classified where the defect comes from, using the
  meta-analysis vocabulary so extraction stays comparable —
  `wave-introduced` (the reviewed wave itself) · `fix-induced` (an
  earlier fix wave's output) · `delta-introduced` (this delta over the
  last reviewed state) · `pre-existing` (older backlog) · `unstated`
  only when the reviewer genuinely cannot tell. Cheap for the reviewer
  (the diff is in scope); the split feeds regression-rate vs detection
  yield and the meta runs' `prov` dimension. This is finding-level
  provenance — distinct from point 4's run provenance (model, tree,
  gates); the deep release-dating method for full scopes lives in
  [review-concept: Finding provenance](../../agent/review-concept.md).

## Resolution format

The resolution's core is a **dispositions table** — one row per finding
ID, in ID order, qualified with the snapshot letter for findings from an
earlier snapshot of the chain (`a W1` = W1 from review-a.md). Rows stay
**≤ 120 columns** (the line-length ratchet pins this): the table is the
control panel, not the narrative. Evidence that does not fit a row goes
into the **Evidence detail** prose section below — nothing is dropped.

```markdown
## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `abc1234` | DD13 decoupled; 4 e2e pins; sabotage red→green |
| a W2 (LOW) | **deliberately not done** | — | never-fails contract; riders disclose |

## Evidence detail

### a W1 (MED) — <topic>

<full narrative as wrapped prose: mechanism, pins, sabotage counts,
class-sweep pattern and sites — the row above links to it by finding>
```

- Dispositions: `implemented` / `implemented differently` /
  `deliberately not done` — nothing else.
- **Key evidence or a blocker reason, never a bare claim** — if the
  row cannot carry it, the Evidence detail block must (and does).
- The resolution is created with the FIRST fix commit of the chain and
  grows one row (and, where needed, one detail block) per disposition
  as fixes land — never reconstructed afterwards. Referenced commits
  carry SHAs, not branch names.
- Legacy resolutions (pr-00109…pr-00171) predate the two-part form:
  their long rows are baseline-pinned and stay as written — the format
  binds everything written from here on.

## Rules

1. **Snapshots are immutable.** Findings are cited by ID; corrections
   happen in the resolution, not by rewriting history. The one
   `> Resolution:` pointer line is the only allowed post-hoc edit.
2. **Every finding gets dispositioned** in the resolution (three verbs
   above).
3. **Citations:** `#176 a W1` (PR number, snapshot letter, finding ID)
   in commit messages, in-code comments, and resolutions. Legacy
   citations `0.0.49b C1` stay valid — resolve them via
   [legacy-index.md](legacy-index.md) or `grep`.
4. **First the snapshot, then the fix.** The snapshot is committed
   before any fix wave starts; the maintainer gives the go.
5. **Fix waves get their micro-wave review** (the chain grows: b, c, …)
   until the stop rule is met.
6. Follow-ups the implementation itself required are recorded in the
   resolution — expected reading for the next review.

## Process

Reviews run against a clean working tree of the version under review
(each snapshot's header carries model, scope, and verification state).

1. Maintainer opens the (draft) birth-PR; the agent runs the reviewer
   (parallel subagents per review-concept.md).
2. Verify every finding against the code — **no fixing while
   verifying**.
3. Write the snapshot (+ README index row is generated) and commit it.
4. Default: no pause — the review session proceeds to its fixes
   directly (session rotation, see agent/review-concept.md); a
   maintainer pause is a per-case override, recorded in the
   resolution.
5. Fix wave on the feature branch; the resolution is created with the
   first fix commit and grows per disposition; the loop closes per the
   stop rule. Run the L1–L7 checklist
   ([agent/learnings.md](../../agent/learnings.md)) before committing.

## Index

[INDEX.md](INDEX.md) is **generated** by
`scripts/gen-review-index.py` — one row per case (key, linked to its
case folder like the rules-meta index, stem/subject, scope, base, date,
snapshots, status). The parity test pins index ↔
folders in both directions. The frozen
[legacy-index.md](legacy-index.md) maps every pre-restructure file name
(`0.0.39a`) to its new home.
