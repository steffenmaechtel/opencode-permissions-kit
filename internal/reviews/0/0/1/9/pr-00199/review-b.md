<!-- review-meta
ID: pr-00199
Snapshot: b
Subject: issue-165 fix wave — a W1–W5 dispositions (micro-wave review)
Scope: wave
Base: v0.0.52 @ 9a73186
Diff: 9a73186..696e3a3 (fix commit; resolution 9f4fea3 is bookkeeping only)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per the rotation rule, not the a-wave fixing session; main agent + 2 GLM-5.3-Flash axis subagents: mechanical/regression, claims/pins/sweep; every finding main-agent-verified; sabotage matrix S1/S2/S3b/S4b/S5 re-executed by the main agent)
-->

# Review — pr-00199 snapshot b — fix wave of the issue-165 chain (micro-wave)

> Resolution: [resolution.md](resolution.md)

Wave under review: fix commit `696e3a3` (3 files, +232/−20) — the
dispositions of snapshot a's W1–W5: handover elif row (a W1), git-floor
fallback row + noop-stub retirement (a W3), readiness-semantics execution
pins (a W2, implemented differently), class-set ratchet pin (a W5), docs
six-family paragraph (a W4). `9f4fea3` (resolution + INDEX) is
bookkeeping, not review-relevant code. The wave question — "did the
fixes break or lie?" — is answered: **no fix-induced regression found,
0 HIGH / 0 MED**; the findings below are staleness, ledger-precision and
docs-precision residuals, all comment/docs/bookkeeping-only in their fix
shape.

## Findings index

| ID | Sev | One-line | Site | Prov |
|---|---|---|---|---|
| F1 | LOW | stale "(fail-soft: no helper, no row)" contract comment survives in the test file the wave edited — the wave retired that contract in status.sh | test-status.sh:39 | wave-introduced (staleness) |
| F2 | LOW | resolution evidence counts don't reproduce under minimal mutations (S1/S2/S5 FAIL counts, "10 new pass lines" vs 13) | resolution.md a-W1/a-W3/a-W5 evidence, :118 | wave-introduced (ledger) |
| F3 | LOW | docs paragraph promises the missing-lib row unconditionally; four of six families gate it on caller/state preconditions the text never names | cli.md:366-370 vs status.sh:574/644/795/894 | wave-introduced claim, pre-existing gating |
| F4 | INFO | class-set ratchet pins only the exact row phrasing — a reworded over-sweep row escapes; documented residual in the pin's own comment | test-status.sh:1901-1920 | wave-introduced (pin) |
| F5 | INFO | d3 pins cannot see a result-override mutation (hardcoded `_st_hosts_ready=true` after the `fi`, line 853 kept verbatim) — contrived shape | test-status.sh:1679-1751 | wave-introduced (pin gap) |
| F6 | INFO | double `id -u` evaluation if/elif at the handover guard is benign — no uid transition mid-script exists; record | status.sh:609 vs :644 | wave-introduced, no defect |

## Findings

### F1 (LOW) — retired contract still documented in the sibling comment

`696e3a3` rewrote the status.sh comment block (:58-62) to record that the
old fail-soft contract ("a missing helper just drops the row") **is
retired** — a W3's own ruling — but the 0b section comment in the test
file the same wave edited still documents the retired contract verbatim:
"(fail-soft: no helper, no row)" (test-status.sh:39). The tree now
documents two opposite contracts for the same call site. Comment-only:
the 0b pins (:40-42) pass and g2 pins the real behavior; the risk is the
next reader trusting the stale comment. One-line fix, or
deliberately-not-done with a pointer to the g2 block.

### F2 (LOW) — resolution sabotage/pass-line counts not reproducible as written

Main-agent re-execution of the resolution's sabotage matrix against the
committed tree (mutate → `sh tests/unit/test-status.sh` → restore →
green): S3b and S4b reproduce **exactly** (4 and 1 FAILs); S1 (delete
the handover row line) yields **5** FAILs against the recorded 6; S2
(delete the git fallback row line) yields **4** against the recorded 5;
S5 (bogus bridge over-sweep row) is shape-dependent — 1 FAIL at an
inert insertion point here, 3 in the claims-axis reproduction, 6
recorded (the resolution itself notes the advisories anchor moved in
its run). Every mutation went red and the class-set pin fired where
claimed — the evidence DIRECTION holds — but three counts do not
reproduce under the natural minimal mutation, and the mutation shapes
are not specified. Likewise "all 165 pins incl. the 10 new pass lines":
the diff adds **13** `pass "` lines (d3:5, g:4, g2:3, f:1); 10 is right
only if the three extraction pins are silently excluded. The resolution
is the ledger the next review starts from — counts that don't
reproduce cost exactly the audit this pass had to do. Fix shape:
errata row in the resolution (counts as re-measured, mutation shapes
named), no code change.

### F3 (LOW) — docs promise rows for caller states that stay row-free

The W4-rewritten paragraph (cli.md:362-371) says a missing lib file
makes "the check family render a warning row … and counts toward the
verdict" for the six enumerated families — unconditionally. In code,
four of the six gate the row on preconditions the text never names:
terminal (:574) and migrate (:795) require a stamped `DEFAULT_USER`;
handover (:644) requires a non-agent-uid caller; hosts (:894) requires
the full readiness chain. An agent-uid run, an unstamped install, or a
no-`/mnt/c` host with the same damaged `sh/` tree stays row-free for
those families (by design — the checks themselves are gated; the
gating predates this wave from `28c2e0e`). A reader diagnosing a
damaged tree from exactly those contexts is promised rows that will
not render. Related narrow wording in the same wave's own text: the
handover comment (:648-650) and commit message say "developer-uid run"
while the elif equally fires for root (`sudo opk status`, uid 0) — the
primary diagnostic path; behavior is correct, only the wording is
narrow. The enumeration itself, the advisories row-naming carve-out,
and the "missing **or outdated**" git-floor wording are all accurate
(verified against every `ui_kv_warn` row). Fix shape: one qualifying
clause ("on runs where the family's preconditions hold"), or
deliberately-not-done.

### F4 (INFO) — class-set ratchet is wording-scoped (documented residual)

The W5 ratchet greps `kit file sh/[a-z0-9-]*\.sh missing`; an over-sweep
row reworded to e.g. "not found" exits coverage silently, and the
full-text `-qF` anchors pin only the five known rows. The realistic
copy-paste shape is caught (S5 reproduced red). The pin's own comment
scopes the guarantee to "this wording" — a documented residual, not a
lie; recorded here so the next wave knows the boundary.

### F5 (INFO) — d3 override-shape residual

The d3 arms execute the carved real uid condition (operator and
sentinel mutations reproduced red: 4 and 1 FAILs) and the smoke asserts
a boolean — all in-line semantic drift is caught. What slips: keeping
line 853 verbatim and hardcoding `_st_hosts_ready=true` after the `fi`
— extraction pin passes (text intact), smoke still yields a boolean,
d) arms inject the flag anyway. Contrived; the full-chain true leg is
host-unreachable by the recorded "implemented differently" rationale.
Residual of that deviation, disclosed here for the record.

### F6 (INFO) — double `id -u` evaluation at the handover guard (benign)

The elif (:644) re-evaluates verbatim the uid condition the if (:609)
already tested. status.sh never transitions uid mid-run (no sudo/su/
setuid between the two; both run in the same shell), so the two
evaluations cannot disagree. The duplication is the explicit
"guard stays compound" a-W1 decision. Recorded because the corpus asks
for double-evaluation sites by name; no defect.

## Verification (main agent)

Every reviewer finding was re-verified against the code before entering
this snapshot; none retracted, none reshaped:

- F1 confirmed by direct read + `grep -rn 'no helper, no row'` — one
  live hit (test-status.sh:39); the status.sh:59 hit is the wave's own
  "retired" wording quoting the old contract.
- F2 confirmed by my own mutation runs (table below) and the claims
  axis's independent reproduction in a /tmp copy (S5=3 there vs my 1 —
  both differ from the recorded 6, demonstrating shape-dependence);
  `grep -c '^+.*pass "'` on the fix-wave diff → 13.
- F3 confirmed by guard-context reads (:574, :644, :795, :894) against
  the cli.md paragraph; every `ui_kv_warn` "not checked" row grepped
  (5 kit-file rows + advisories = six families, enumeration correct).
- F4 confirmed by running the exact `grep -o … | LC_ALL=C sort -u`
  against HEAD — reproduces `_k165_want` byte-exactly (5 entries,
  correct order, git-check's "missing or outdated" tail included via
  prefix match).
- F5 confirmed by static trace of the capture ranges (`_h165pre` ends
  at the first col-0 `fi`, :855; an appended override line sits outside
  every capture and no pin reads past :855).
- F6 confirmed by trace; no uid-transitioning construct in status.sh.
- Both axes' clean sections independently re-checked by the main agent:
  anchor uniqueness (`^_st_dhl=`, `^if command -v git_status_row`,
  `^# Readiness split`, `^   && \[ -n "${DEFAULT_USER:-}" \]` — one
  match each) and range termination (first col-0 `fi` at :652/:223/:855
  — each capture ends exactly where intended); `git_status_row` has no
  consumer outside status.sh + sh/git-check.sh (stub retirement blast
  radius zero; `make test` green incl. test-git-config.sh); the
  checkout-first candidate genuinely never exists under the harness
  (`$0` is the test path; `tests/` has no `sh/`); dash `[`-as-function
  rejection reproduced by the claims axis in /tmp (the a-W2 "implemented
  differently" rationale holds).

**Sabotage matrix re-executed (main agent; tree clean at `9f4fea3`,
mutate → red → `git restore` → green):**

| Mutation (minimal shape) | Result | Resolution recorded |
|---|---|---|
| S1 handover row line deleted | red, 5 FAILs (extraction, 3 arms, set pin) | "6 FAILs" |
| S2 git fallback row line deleted | red, 4 FAILs (extraction, 2 arms, set pin) | "5 FAILs" |
| S3b `!=` → `=` on :853 | red, 4 FAILs (extraction + 3 arms) | 4 ✓ |
| S4b sentinel dropped on :853 | red, 1 FAIL (extraction pin) | 1 ✓ |
| S5 bogus bridge row inserted | red, 1 FAIL (set pin, actual set printed) | "6 FAILs" |

All five mutations red, all restores green, tree clean after — the pins
discriminate and sit before the summary gate; the count deltas feed F2.

**Gates run:** `sh tests/unit/test-status.sh` (131 PASS, 32 labeled
`165:`, rc 0); `make test` (full unit suite + sandbox policy, green);
`make lint` (ShellCheck, green); `make check-version` (green). e2e not
owed — unchanged ruling from snapshot a: status.sh is not in AGENTS.md's
e2e-owed list, and no healthy install gains a row, so e2e status
assertions are unaffected by construction. Both e2e suites remain owed
before the next release tag, independent of this PR.

**Environment:** house session on the kit-managed WSL2 checkout (fresh
session per the rotation rule — the a-wave's fixing session did not
review its own fixes); reviewer subagents GLM-5.3-Flash, fresh context,
checkpointed per section (`/tmp/opencode/pr199-review-b-{mech,claims}.chk`);
no docker/e2e runs, so no opencode-binary version dependency this pass.

## Retracted/ghost findings

None — every subagent finding survived main-agent verification.

## Recommendation

**No regression blocks the merge; dispositions can close the chain.**
All six findings are comment-, docs- or ledger-only in their fix shape
(F1 test comment, F2 resolution errata, F3 docs qualifier; F4–F6
recorded residuals) — under the stop rule, no disposition of them can
touch review-relevant code, so the loop closes with this round's
dispositions whether they are fixed or deliberately not done. If the
maintainer prefers fixes: F1 (one line), F2 (errata row), F3 (one
clause) are each single-line edits that can ride any next wave without
owing a snapshot c for code.
