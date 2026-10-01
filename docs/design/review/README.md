# Code reviews (design/review/)

Model-generated code reviews of the kit live in this folder. The convention
keeps two things separate: **what the review found** (immutable) and **what
the maintainers did about it** (the resolution). When to review at all,
which scope (full vs diff) and the loop's stop rule:
[review-concept.md](../review-concept.md).

## File naming

| File | Meaning |
|---|---|
| `template.md` | The skeleton a new review snapshot starts from (header fields, table shapes, finding-ID scheme) |
| `YYYY-MM-DD-v<VERSION>.md` | The review snapshot — findings as reported, never edited after the fact. Several snapshots of the same date-version get variant suffixes `-a`, `-b`, … in review order |
| `YYYY-MM-DD-v<VERSION>-resolution.md` | The disposition of every finding (same date-version stem) |

## Rules

1. **The review file is a snapshot.** Findings are referenced by ID (S1, C15,
   …) from commit messages and the resolution — later edits would blur what
   the reviewer found versus what was fixed. Corrections happen in the
   resolution, not by rewriting history. (The review's own "Retracted/ghost
   findings" section is part of the snapshot: retractions stay visible.)
   Outside the snapshot, IDs always carry the review stem — `0.0.38 S1`,
   never a bare `S1` — because every review restarts at S1/C1; the mapping
   lives in the [index](#index) below and
   [conventions.md](../conventions.md#referencing-review-findings).
2. **The snapshot carries one pointer line** at the top — `> Resolution:
   <file>` — once a resolution exists. That is the only edit allowed.
3. **The resolution dispositiones every finding**, one of:
   - *implemented* — with the commit SHA that carries it
   - *implemented differently* — with what changed on the way and why
   - *deliberately not done* — with the rationale
4. **Follow-ups the implementation itself required** (a fix that regressed
   something the review could not see, and its fix) are recorded in the
   resolution — they are expected reading for the next review.
5. Resolutions reference commits, not branch names or issue numbers alone —
   the SHA survives rebases of everything else.

## Process

Reviews are run by a model against a clean working tree of the version under
review (see a review's header for model, scope, and verification state). The
review report is committed first, fixes follow on a feature branch with the
finding IDs in the commit messages, then the resolution closes the loop.

## Index

Every review restarts its finding IDs at S1/C1, so a bare ID (an `S1` in a
comment, a commit message, a chat log) is ambiguous across reviews. Resolve
it in two steps: take the review stem from the reference — `(0.0.38 S1)`
points at row 0.0.38 below — or, for a bare legacy ID, grep the candidate
snapshots (`grep -n "C13" 2026-09-26-v0.0.38.md`).

| Stem | Snapshot | IDs used | Resolution | Notes |
|---|---|---|---|---|
| 0.0.17 | — (pre-snapshot era) | — | — | findings summarized in `project-history-summary.md`; in-code references use the `review 0.0.x` prose form |
| 0.0.22 | — (pre-snapshot era) | — | — | referenced as `review 0.0.22` (`files/install.sh`, agents-migration scope) |
| 0.0.29 | — (pre-snapshot era) | — | — | referenced as `review 0.0.29` (`management/update.sh`, binary-path fetch guard) |
| 0.0.38 | [2026-09-26-v0.0.38.md](2026-09-26-v0.0.38.md) | S1–S6, C1–C23, D1–D7 | [2026-09-26-v0.0.38-resolution.md](2026-09-26-v0.0.38-resolution.md) | the bare IDs in shipped comments all date from this review's fix commits (C11, C12, C13, C14, C19, C22, C23, S1) — qualified in place as `0.0.38 …` |
| 0.0.39a | [2026-09-27-v0.0.39-a.md](2026-09-27-v0.0.39-a.md) | S1–S9, C1–C9, D1–D25 | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | same-day variant a |
| 0.0.39b | [2026-09-27-v0.0.39-b.md](2026-09-27-v0.0.39-b.md) | S1–S4, C1–C6, D1–D3, Q1–Q3 | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | same-day variant b; independent of -a (overlaps are confirmations) |
| 0.0.39c | [2026-09-27-v0.0.39-c.md](2026-09-27-v0.0.39-c.md) | — (no new findings) | — | provenance analysis of the -a/-b rows vs. tag `0.0.38`: 57/59 pre-existing, 1 fix-wave regression (0.0.39a D12, cosmetic), 1 post-tag feature nit (0.0.39a S9) |
| 0.0.39d | [2026-09-28-v0.0.39-d.md](2026-09-28-v0.0.39-d.md) | S1–S8, C1–C8, D1–D5, 1 retraction | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | review of the 0.0.39 fix wave itself (20 commits, `7692cb1..84a31da`, pre-PR) |
| 0.0.39e | [2026-09-28-v0.0.39-e.md](2026-09-28-v0.0.39-e.md) | S1–S8, C1–C17, D1–D4 | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | full-scope stop-rule gate pass (method comparison run, review-project without checkpoint skill); loop continued — 5 new MEDs |
| 0.0.39f | [2026-09-29-v0.0.39-f.md](2026-09-29-v0.0.39-f.md) | F1–F8, 1 retraction-fold | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | wave review of the 0.0.39e fix wave (10 commits, `e7c101c..389db26`); all findings fixed in `099b14b` |
| 0.0.39g | [2026-09-29-v0.0.39-g.md](2026-09-29-v0.0.39-g.md) | S1–S4, C1–C6, D1, Q1–Q7 | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | full-scope stop-rule gate pass; loop continues — 2 new HIGH (symlink-operand write/chown primitives), 5 MED; fixed in `2db6517` (full-class sweep beyond the listed lines); wave review: snapshot h |
| 0.0.39h | [2026-09-29-v0.0.39-h.md](2026-09-29-v0.0.39-h.md) | F1–F13, 3 retraction-folds | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | wave review of the 0.0.39g fix wave (1 commit `2db6517`); loop continued (1 HIGH missed sibling, 1 MED parent axis); fixed in `62bcbc8` (F1/F2/F3/F5) + the part-2 commit (F4, F6–F13) |
| 0.0.39i | [2026-09-30-v0.0.39-i.md](2026-09-30-v0.0.39-i.md) | F1–F7 (1 LOW, 1 LOW, 5 Q/INFO), 1 retraction | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | wave review of the 0.0.39h fix wave (2 commits `62bcbc8`+`1b1f912`); wave arm converges — no new MED/HIGH; fixed in `16dace3` (F1–F4), F5–F7 dispositioned |
| 0.0.39j | [2026-09-30-v0.0.39-j.md](2026-09-30-v0.0.39-j.md) | F1–F5 (1 MED, 2 LOW accepted, 2 INFO) | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | mini wave review of the 0.0.39i fix wave (`16dace3`); found the i-wave's fresh-install ownership regression on `.config/opencode` (live-verified) — fixed in `69431d9` with e2e ownership assertions (baseline 272); chain closed on maintainer's call |
| 0.0.39k | [2026-09-30-v0.0.39-k.md](2026-09-30-v0.0.39-k.md) | F1–F3 (2 LOW fixed, 1 INFO) | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | micro wave review of the 0.0.39j fix wave (`69431d9`); no MED/HIGH — chain converges; impact-wording + e2e-assertion LOWs fixed in `c31f4df` |
| 0.0.39l | [2026-10-01-v0.0.39-l.md](2026-10-01-v0.0.39-l.md) | C1–C2, D1–D3 (5 LOW), 1 ghost retracted | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | full-scope stop-rule gate pass — **stop rule MET** (no MED/HIGH after verification); LOW batch fixed in `e461b3e`; release gate green (e2e 272/0 + 47/0) |
| 0.0.39m | [2026-10-01-v0.0.39-m.md](2026-10-01-v0.0.39-m.md) | C1 (1 LOW), C2–C3 INFO, D1 LOW, Q1 | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | full-scope re-confirmation after the carrier sweep — no MED/HIGH (second consecutive clean pass); LOW/INFO batch fixed in `0a9734a` (wrapper NO_COLOR guard, l pointer, comments); release gate re-confirmed |
| 0.0.39n | [2026-10-01-v0.0.39-n.md](2026-10-01-v0.0.39-n.md) | F1–F2 LOW (test quality), F3–F4 INFO | [2026-09-28-v0.0.39-resolution.md](2026-09-28-v0.0.39-resolution.md) | micro wave review of the issue-#116 fix wave (`349a5a5`+`2073878`, branch `fix/issue-116` off master — git ≥ 2.55 fatals from an unreadable sudo-inherited CWD → `git -C /`); no MED/HIGH; test hardening fixed in `62e5985` |
| 0.0.39o | [2026-10-01-v0.0.39-o.md](2026-10-01-v0.0.39-o.md) | S1 INFO, C1 LOW (7 sites), D1–D5, Q1–Q6, 2 retraction notes | — | full-scope pass post-merge of PR #121 (line-length wave — merged without its own wave snapshot; this pass reads the full wave diff); no MED/HIGH — stop rule still met; wave-introduced C1 space-loss class (7 wrap sites) + update-one-liner drift (D1) pending a fix branch |
| 0.0.39p | [2026-10-01-v0.0.39-p.md](2026-10-01-v0.0.39-p.md) | F1–F4 LOW (fixed), F5 INFO | — | micro wave review of the 0.0.39o fix wave (`63df285`+`c6c14d9` on `fix/review-0.0.39-o`); no MED/HIGH; guard hardening + chmod uniformity fixed in `9effed0`; e2e 272/0 + 47/0 on the fixed tree |
| 0.0.40a | [2026-10-01-v0.0.40-a.md](2026-10-01-v0.0.40-a.md) | F1–F3 LOW, F4–F10 INFO, 1 ghost retracted | — | micro wave review of the issue-#112 perf wave (`3f9387b` on `feature/112-handover-scan-performance` — handover scan-skip stamps, top-inode fast path, `.git` prune); no MED/HIGH; e2e 272/0 + 47/0 + 70/0 on the wave tree |
