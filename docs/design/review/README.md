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
4. **The resolution grows WITH the chain, not after it** (learning from
   the 0.0.41 chain, where the resolution was reconstructed at the end
   while dispositions had already front-run into index rows, snapshot
   prose and commit messages): the resolution file is created with the
   FIRST fix commit of a chain and gains one row per disposition as the
   fix lands. Contemporaneous rows cost seconds; a retroactive
   reconstruction re-derives SHAs and rationales that were current
   minutes ago and invites drift. The README index row stays a
   one-line summary — it never substitutes for the resolution.
5. **Follow-ups the implementation itself required** (a fix that regressed
   something the review could not see, and its fix) are recorded in the
   resolution — they are expected reading for the next review.
6. Resolutions reference commits, not branch names or issue numbers alone —
   the SHA survives rebases of everything else.

## Process

Reviews are run by a model against a clean working tree of the version under
review (see a review's header for model, scope, and verification state).

**Hard ordering for a review session** (made explicit after 0.0.42d, where
the maintainer had to ask for the snapshot before fixing started):

1. Run the reviewer agents (parallel subagents per review-concept.md).
2. Verify every agent finding against the code (main agent) — **no fixing
   while verifying**: a fix would change the tree later findings are
   checked against.
3. Write the snapshot (and its README index row) and **commit it**. The
   snapshot is the review's deliverable — it must exist in git before any
   fix touches the tree. Findings that live only in chat scrollback are
   lost; the snapshot is what survives.
4. **Pause for the maintainer.** The fix wave starts on their go — the
   committed snapshot is the visibility point: what was found is
   inspectable before what will be done about it begins.
5. Fix wave on a feature branch with the finding IDs in the commit
   messages; the resolution is created with the first fix commit and grows
   one row per disposition (rule 4), then the loop closes per
   review-concept.md's stop rule.

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
| 0.0.40a | [2026-10-02-v0.0.40-a.md](2026-10-02-v0.0.40-a.md) | F1–F3 LOW, F4–F10 INFO, 1 ghost retracted | [2026-10-02-v0.0.40-resolution.md](2026-10-02-v0.0.40-resolution.md) | micro wave review of the issue-#112 perf wave (`3f9387b` on `feature/112-handover-scan-performance` — handover scan-skip stamps, top-inode fast path, `.git` prune); no MED/HIGH; F1–F3 fixed in `2718238`, F4/F6/F7 in `08278a5`, F5/F8/F9/F10 deliberately not done; e2e 272/0 + 47/0 + 70/0 on the fixed tree |
| 0.0.40b | [2026-10-02-v0.0.40-b.md](2026-10-02-v0.0.40-b.md) | F1–F5 LOW (fixed), Q1–Q2 INFO (fixed), Q3–Q4 INFO | [2026-10-02-v0.0.40-resolution.md](2026-10-02-v0.0.40-resolution.md) | micro wave review of the 0.0.40a fix wave (`e1ede97..bda1c77`: `2718238`+`908f708`+`08278a5`+`bda1c77`); no MED/HIGH; docs/test-hygiene batch fixed in `4dbf56c`; suite-count + e2e-timing corrections carried in the resolution; e2e 272/0 + 47/0 + 70/0 on the fixed tree |
| 0.0.40c | [2026-10-02-v0.0.40-c.md](2026-10-02-v0.0.40-c.md) | F1 LOW (fixed), Q1–Q3 INFO (Q1–Q3 fixed/Disposition), Q4–Q5 INFO | [2026-10-02-v0.0.40-resolution.md](2026-10-02-v0.0.40-resolution.md) | micro wave review of the 0.0.40b fix wave (`bda1c77..381f8a4`: `4dbf56c`+`381f8a4`, shipped delta comment-only); no MED/HIGH — wave chain converged (two consecutive review-of-review passes clean); audit-log event completed, comment twins fixed in `36d7317`; snapshot-b imprecisions corrected via the resolution |
| 0.0.41a | [2026-10-02-v0.0.41-a.md](2026-10-02-v0.0.41-a.md) | F1–F4 (2 LOW, 2 INFO) | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | micro wave review of the issue-#113 phase extraction (`1f6d18a` on `feature/113-install-sh-phase-functions` off `740d650` — install.sh wrapped into `do_plan_phase`/`do_ddev_phase`/`do_deploy_phase`, verbatim, +32/−0); no MED/HIGH; author self-review with mechanical verification; e2e 272/0 + 47/0 |
| 0.0.41b | [2026-10-02-v0.0.41-b.md](2026-10-02-v0.0.41-b.md) | F1 LOW, F2–F4 INFO | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | wave review of dedup point 1 (`2ab6e7b`: shared sudoers pipeline `sh/sudoers-deploy.sh`, replacing the triple duplication in install/config/update); no MED/HIGH; F1/F3 dispositioned keep/optional; ratchet caught a 122-char draft line (shortened); make test 31 suites + lint green, e2e deferred to the dedup-wave final gate |
| 0.0.41c | [2026-10-02-v0.0.41-c.md](2026-10-02-v0.0.41-c.md) | F1 MEDIUM-verdict-clean (deliberate silent→fail-loud change), F2–F4 INFO | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | wave review of dedup point 2 (`fe7666a`: shared binary hardening `sh/secure-binary.sh`, dissolving install.sh's nested `secure_binary`, update.sh's silent re-assert and the `install_binary` pair); no MED/HIGH; bypass-guard 750 assertions rewired to wiring+enforcement; make test 32 suites + lint green |
| 0.0.41d | [2026-10-02-v0.0.41-d.md](2026-10-02-v0.0.41-d.md) | F1–F2 LOW (recorded/accepted), F3–F4 INFO | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | wave review of dedup point 3 (`8bc0414`: library deploy through ONE manifest `sh/deploy-lib.sh` — install/update twin cp listings dissolved, ~95/~70 lines out; test-kit-files gains bidirectional manifest↔fetch equality + canary; 7 suites' wiring greps rewired); no MED/HIGH; make test 33 suites + lint green |
| 0.0.41e | [2026-10-02-v0.0.41-e.md](2026-10-02-v0.0.41-e.md) | F1 LOW (deliberate fail-loud unification), F2 LOW (test-side, fixed in-wave), F3–F4 INFO | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | wave review of dedup point 4 (`623d575`: shared `sh/render-agent-config.sh` SECURE_GIT render + `sh/tui-plugin.sh` per-user plugin sync; update.sh's silent sync aborts now die with a message); no MED/HIGH; make test 33 suites + lint green; dedup wave 1–4 complete pending the final e2e gate |
| 0.0.41f | [2026-10-02-v0.0.41-f.md](2026-10-02-v0.0.41-f.md) | C1/S1 **HIGH** (silent post-apply `opk update` abort on a skip rc — delta-introduced by 0.0.41e, missed by its snapshot, e2e-invisible; both agents converged), C2–C5 LOW, S2–S3 + Q1–Q5 INFO, 1 pre-existing canary typo | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | full-scope pass on the branch tip `547a4cd` (release-tier trigger: ~1.7k lines + blast radius) with independent `review-security` + `review-quality` subagents; e2e-ddev (70/0) retro-added to the gate; all findings fixed in `0d2e349`; suites re-run on the final tip — branch PR-ready after 272/47/70 re-confirm |
| 0.0.41g | [2026-10-02-v0.0.41-g.md](2026-10-02-v0.0.41-g.md) | F1–F2 LOW (recorded/accepted), F3–F4 INFO | [2026-10-02-v0.0.41-resolution.md](2026-10-02-v0.0.41-resolution.md) | micro wave review of the 0.0.41a-F1 re-indent (`a4d1c73`: +4 on the three phase bodies; `git diff -w` empty + pairwise proof 1517/1517; heredoc + 37 quote-joins excluded; test-project-paths extract made indent-tolerant); no MED/HIGH; e2e 272/47/70 re-confirmed on the indented tree |
| 0.0.42a | [2026-10-03-v0.0.42-a.md](2026-10-03-v0.0.42-a.md) | C1 **MED** (wave-introduced ratchet violation — `make test` red on the tip, pipe-masked green claim in `a2403c7`), C2 LOW (ddev golden warm start silently ignores an exported `E2E_GIT_CHANNEL`), D1–D3 LOW, Q1–Q7 INFO, 2 retraction notes | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | wave review of the issue-#118 git-matrix wave (`b3f1b26`+`a2403c7` on `feature/issue-118`); three parallel Flash reviewer agents + main-agent verification; fixes in the C1/C2/D1–D3/Q1 batch; loop continues with snapshot b |
| 0.0.42b | [2026-10-03-v0.0.42-b.md](2026-10-03-v0.0.42-b.md) | — (no new findings) | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | micro wave review of the 0.0.42a fix wave (`24385b2` + docs/bookkeeping `983ab56`+`1f8adb7`); no MED/HIGH — wave arm converges; e2e 272/47/70 re-confirmed on the fixed tip; branch PR-ready |
| 0.0.42c | [2026-10-03-v0.0.42-c.md](2026-10-03-v0.0.42-c.md) | D1–D2 LOW (fixed / superseded by template deletion), Q1–Q3 INFO | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | micro wave review of the issue-#123 chmod-list wave (`c05d8ef` on `feature/issue-123` — workflow chmod lists removed, exec bits normalized in the git index, test-workflows guard rewrite); no MED/HIGH; e2e 272/47/70 on the tip |
| 0.0.42d | [2026-10-03-v0.0.42-d.md](2026-10-03-v0.0.42-d.md) | S1–S3, C1–C4, D1, Q1–Q4 | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | full-scope release review before 0.0.43 (tree `b3418ac`; three parallel Flash agents + main-agent verification; delta focus on the un-wave-reviewed `86a55d7`/`540666c`/`ccebffb`); 2 MED (`make test` runs 30/33 suites, `make lint` list omits 7 shipped scripts) + xdg-open never-shadow guard drift (LOW); loop continues; full gate green on the tree (272/47/70, zero skips) |
| 0.0.42e | [2026-10-03-v0.0.42-e.md](2026-10-03-v0.0.42-e.md) | S1–S2, C1–C10, D1–D12, Q1 | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | independent external full-scope pass (GPT-6 Luna, same tree `b3418ac`) integrated with per-finding main-agent verification: 25/26 confirmed, 1 MED retracted at review time (S3 later carved out as a live LOW per the reviewer's counter-feedback); 2 HIGH (uninstall chown through symlink; unit suite `rm -rf` on fixed host paths — executed as an incident on the external host) + 6 MED; cross-calibration section vs -d (union drives the fix wave); loop continues |
| 0.0.42f | [2026-10-04-v0.0.42-f.md](2026-10-04-v0.0.42-f.md) | S1–S2, C1–C3, D1–D3, Q1–Q2 | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | wave review of the 0.0.42d/e fix wave (`e26f379..24ad0d2`, 8 commits; three parallel Flash agents + main-agent verification); 5 MED, all fix-induced/fix-incomplete (back-function containment sibling, glob gate after expansion, staging siblings, group-name ACL qualifier, guard continuation blindness); loop continues with fix wave 2; gate on the tip green (34 suites, e2e 273/47/70, zero skips) |
| 0.0.42g | [2026-10-04-v0.0.42-g.md](2026-10-04-v0.0.42-g.md) | S1, C1–C3, D1–D3, Q1–Q3 | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | wave review of fix wave 2 (`74a3751..1338c9b`; three parallel Flash agents + main-agent verification); 4 MED — ACL principal mismatch (removal targets dev-gid, baseline writes the opencode group), conventions policy names the dropped sed pattern, ratchet blind to quoted literals, expect_rc-0 suite-kill shape; loop continues with fix wave 3; gate green on the tip |
| 0.0.42h | [2026-10-04-v0.0.42-h.md](2026-10-04-v0.0.42-h.md) | S1–S2, C1–C2, D1, Q1 | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | wave review of fix wave 3 (`4e22481..75bdb6c`; three parallel Flash agents + main-agent verification, live-executed); 2 MED — one-unknown-gid silent principal skip with lying log line, and the surviving FIRST-line comment (cross-confirmed by all three agents); wave-3 substance verified clean; minimal fix wave 4 follows; gate green on the tip |
| 0.0.42i | [2026-10-04-v0.0.42-i.md](2026-10-04-v0.0.42-i.md) | Q1–Q3 (INFO) | [2026-10-03-v0.0.42-resolution.md](2026-10-03-v0.0.42-resolution.md) | wave review of fix wave 4 (`2373ea5..838de21`; three parallel Flash agents, live-executed); **zero MED/HIGH — stop rule met, wave chain d–i closes** (3 INFO dispositioned with the closure commit); final gate green (34 suites, e2e 273/47/70, zero skips); branch PR-ready |
| 0.0.43a | [2026-10-04-v0.0.43-a.md](2026-10-04-v0.0.43-a.md) | F1–F19 (6 MED, 13 LOW), 1 false positive rejected | [2026-10-04-v0.0.43-resolution.md](2026-10-04-v0.0.43-resolution.md) | full-scope pass on the 0.0.43 release tip (`master` @ `34e9764`, post-PR #139); GLM-5.3 lead review + four parallel sub-reviews, every finding lead-verified (shell-semantics claims empirically, advisory-feed claims against the live API); stop rule not met (6 MED) — fix wave follows |
| 0.0.43b | [2026-10-04-v0.0.43-b.md](2026-10-04-v0.0.43-b.md) | W1–W7 (4 LOW, 3 INFO), 13 rejections | [2026-10-04-v0.0.43-resolution.md](2026-10-04-v0.0.43-resolution.md) | wave review of the 0.0.43a fix wave (`89bb547`+`e2102d6`+`638f231`, diff `3d6c9a9..HEAD`); GLM-5.3 via the maintainer's `/review` + main-agent verification, per-claim check of all 19 dispositions; **zero MED/HIGH — stop rule met**; W1–W3 sibling-closure LOWs (hardcoded homes on the sudo paths, unbounded status/update probes incl. one stale parity comment), W4 F10 find-failure residual; W5–W7 acceptance/test-quality notes |
