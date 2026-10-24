<!-- review-meta
ID: pr-00234
Snapshot: b
Subject: issue-215 fix wave (gate hoist + race pins) — micro-wave review
Scope: wave
Base: v0.0.56 @ 395fee7
Diff: 395fee7..ca4c564
Date: 2026-10-23
Reviewer: GLM-5.3 (main session, single-pass micro; no fan-out)
-->

# Micro-wave review — pr-00234 snapshot b — the a-wave fix diff

Micro pass over the a-wave's fixes: d1dcf34 (gate hoist above the
`_ddev_tree_conforms` fast path, warn rewording, loud '/' refusal in
`_ddev_components_sane`, rewritten comment blocks, security-model.md
residual entry, 2 new race drives + walk-edge pins) plus the two
resolution bookkeeping commits (4554530, ca4c564). Single-pass shape:
diff scope only, verification duty held by the reviewing main agent
(review-concept: fan-out is preferred but single-pass is adequate for
wave scope). Every load-bearing claim of the a-wave's resolution was
re-executed, including all three sabotage counts.

> Resolution: [resolution.md](resolution.md)

## Findings index

| ID | Sev | Location | One-line summary | Verified | Prov |
|---|---|---|---|---|---|
| b W1 | MED | resolution.md | ratchet + reviews-parity RED at HEAD; the wave's Gates claims green | yes | fix-induced |
| b W2 | INFO | security-model.md | residual names only the recursive pair, not the tail ops | yes | fix-induced |
| b W3 | INFO | resolution.md | a-W4 row lacks the same-shape walker sweep record; sweep run here | yes | fix-induced |

## Findings detail

### b W1 (MED) — ratchet red at HEAD + false gate claim

`sh tests/unit/test-line-length.sh` exits 1 at the clean HEAD:

    FAIL internal/reviews/0/0/2/3/pr-00234/resolution.md:
    6 new line(s) over 120 chars (not in the baseline)

The offenders are the disposition table's rows 11, 12, 14, 16-18
(124-146 content columns), present since d1dcf34 — the same commit
whose Gates section claims "`make test` green ... line-length ratchet
green (no new offenders)", a claim reiterated by ca4c564. The ratchet
scope deliberately includes internal/ "INCLUDING review resolutions",
and `test-line-length` is a dependency of the Makefile's `test` target,
so `make test` cannot be green at HEAD. Two further members of the same
false claim, both reproduced on the pristine HEAD by this review:
`test-reviews-parity` fails because review-a.md lacks its mandatory
`> Resolution:` pointer line (resolution created in d1dcf34, pointer
never added) and the committed INDEX.md still says pr-00234
"no-resolution" (the a-wave never regenerated it) — so at HEAD `make
test` was red through at least three members. The pr-00208 b W1 shape
(ratchet red at a committed HEAD) plus claim-drift on a gate line. No
production impact; it blocks the PR's CI and falsifies the ledger.
Fix: wrap the six rows <=120 content cols (preferred) or a reviewed
--regen exception; add the pointer line (the one allowed snapshot
edit); regenerate the INDEX; re-run make test; make the Gates line
true.

### b W2 (INFO) — residual entry names only the recursive pair

The security-model.md entry: "a swap in the short window between the
gate and the recursive pair itself stays undetected". On the conforming
(fast-path) branch — the steady state a W1 itself called out — the
first unguarded ops after the hoisted gate are the dev-owned flag write
and the settings pairs, not the pair. The headline claims (non-atomic
gate, leaf-only mid-recheck) are true; the named op is branch-specific.
A one-line rewording ("the iteration's first op") would be precise;
optional, not owed.

### b W3 (INFO) — a W4 disposition lacks recorded sweep evidence

L2 wants the grep pattern + sites checked recorded with a disposition.
Sweep run by this review: `_fsb_pass` (fs-baseline.sh) already refuses
'/' loudly — the "mirrors _fsb_pass" claim holds; `agent_home_sane`
(staged-write.sh) walks below a base of `/home/<user>` (OPK_AGENT_HOME
override is test-only) — structurally never '/'. Boundary holds,
nothing owed in code; recording the sweep completes the L2 record.

## Retracted / ghost findings

None.

## Verified clean (no findings)

- **The hoist itself:** `_ddev_components_sane` has exactly one
  production caller (the hoisted gate); the walk now runs on every
  branch before the conform probe; a fired gate skips the whole
  iteration — flag write and project handovers included; walk mechanics
  unchanged apart from the '/' refusal.
- **No-false-trip property holds under the new placement:** find never
  descends or prints through a link, so an emitted operand's components
  were link-free at scan time — a symlinked component at walk time can
  only be a swap (placement-independent, verified in snapshot a).
- **L5 inventory on the changed construct:** `[ -L ]` on every component
  below the root, the operand included (walk's last step); operand
  re-tested immediately before the iteration acts; chmod-before-chown
  order intact; the leaf-only mid-recheck still covers only the second
  op and says so.
- **'/' refusal is fail-loud and pinned:** stderr warn + rc 1, pinned
  both ways (rc + message); single caller; unreachable in the shipped
  call shape (registered roots only) — defense in depth, mirroring
  `_fsb_pass`.
- **New drives are non-vacuous:** `DDEV_DEV_OWNED=true` short-circuits
  `ddev_devowned_enabled` (OPK_INSTALL_CONF is irrelevant on that path);
  the conforming-victim drive discriminates through exactly the a W1
  mechanism (both `readlink -f` sides canonicalize through the swap,
  gates pass, the settings pair chmods through the link — verified in
  `ddev_handover_project`); seam shape identical to the vetted drives
  (real find baked at write time, buffered swap, rc preserved).
- **Sabotage counts reproduce exactly** (reviewer-executed on the
  committed tree, constructs deleted not commented, observed via suite
  output, restore + green re-run after each): gate-call deletion 10 red
  (plain 4 / spaced 1 / conforming 3 / flag 2); position sabotage (gate
  moved back inside the else) 5 red — only the two new drives, proving
  they pin the HOIST, not gate existence; '/' refusal deletion 2 red.
- **Suite + neighbor gates at HEAD:** test-ddev-as-opencode 288 PASS /
  0 FAIL (matches the resolution's claim); make lint green;
  make check-version green; test-string-continuations OK;
  test-sandbox-policy rc 0; test-reviews-lint OK; pins sit before the
  summary gate.
- **Comment/message truth (L3):** "a path component (parent or operand)"
  matches the walk (operand checked last); consume-time wording (a W8)
  accurate; "no legitimate tree trips this gate" unchanged.
- **e2e classification:** 309/0 + 47/0 on d1dcf34 remain author-observed
  restatements, not re-executed here — same classification snapshot a
  gave the birth wave's counts.
- **Process:** snapshot a committed before its fixes; all nine a-findings
  dispositioned; docs moved in the same wave (RM-0100).

## Provenance, gates, recommendation

- **Run provenance:** single-pass micro review, GLM-5.3 main session,
  tree clean at ca4c564 throughout; three reviewer-executed sabotage
  rounds (mutate -> run -> restore -> re-run green) inside this session,
  no subagent readers outstanding.
- **Gates run (this session, this tree):** sh
  tests/unit/test-ddev-as-opencode.sh 288/0 green; make lint green;
  make check-version green; sh tests/unit/test-line-length.sh **rc 1
  (b W1)**; test-string-continuations OK; test-sandbox-policy rc 0;
  test-reviews-lint OK; test-reviews-parity **fails on the pristine
  HEAD twice (b W1: pointer + stale INDEX)**; make test not run to
  completion — its failure at HEAD is proven by the member results
  above; e2e not re-run.
- **Recommendation: [GO with condition]** — condition: b W1 (wrap the
  six rows <=120 content cols, or a reviewed --regen exception; re-run
  make test green; make the Gates line true). b W2 optional wording;
  b W3 closes with the sweep recorded in the resolution.
