<!-- review-meta
ID: pr-00208
Snapshot: b
Subject: issue-205 fix wave — micro-wave review of the a-wave fixes (phrase alignment, agreement pin, docs third shape)
Scope: wave
Base: v0.0.53 @ bc1a5db
Diff: 4bca8e1..7c790b8 (fix commit; tree also carries bc1a5db — resolution/INDEX bookkeeping, outside the diff, audited as the wave's claim record)
Date: 2026-10-20
Reviewer: GLM-5.3 (house session — fresh session per rotation; main-agent verification + 2 glm-5.3-flash reviewer axes on checkpoints /tmp/opencode/pr-00208-b/ — maintainer first waived the fan-out, then left the already-started pair running; every finding below was verified by the main agent)
-->

# Review — pr-00208 snapshot b — micro-wave of the a-wave fixes (7c790b8)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Fix = `7c790b8`: both ON
sites in config.sh aligned to status.sh's em-dash parenthetical, the
test pin grew a cross-file agreement check (both phrases must appear
in status.sh), the how-to gained the markers-present shape + the
re-render note. Result: **the code fix is correct, byte-exact, and
sabotage-discriminating in both directions — but the resolution
commit `bc1a5db` landed with the unit suite RED**: the line-length
ratchet fails on the two new dispositions rows (b W1, MED). One LOW
(scope comment that enabled the misread) and one INFO (markers hint
is git-config-status-only) complete the set.

## Findings index

| ID | Severity | Site | Summary | Provenance |
|---|---|---|---|---|
| b W1 | MED | resolution.md:10-11 | committed-red suite: `test-line-length.sh` rc=1 at HEAD — both dispositions rows exceed the 120-col rule the ratchet enforces over internal/ markdown (182/140 cols); the wave's gate run covered only test-git-config.sh, so PR #208 CI fails as committed | delta-introduced |
| b W2 | LOW | tests/unit/test-line-length.sh:2-3, 39-43 | header scope comment names only the shell/workflow half of the ratchet's scope; the docs_scope half (agent/, internal/ incl. resolution.md, docs/, root *.md — lines 54-67) is unmentioned — the misread that produced b W1 (wave author, axis-1 reviewer and the main agent's first pass all fell for it) | pre-existing |
| b W3 | INFO | status.sh:205-209 | `opk status` has no markers-present branch: for a markers config it renders the plain OFF row, no detail, no hint — the `(markers present, rules inactive)` hint exists only in `opk config git-config status` (config.sh:414-416); the how-to sentence stays literally true under the page's naming convention (bare `status` = the subcommand; top-level is always written `opk status`, line 34), and config.sh:408-410's "both outputs agree" holds at phrase level | delta-introduced (doc sentence) over pre-existing behavior |

No HIGH.

## b W1 (MED) — resolution rows break the line-length ratchet; suite red at HEAD

`sh tests/unit/test-length.sh`-class gate, observed the way production
observes it (the unit suite):

```
FAIL internal/reviews/0/0/2/0/pr-00208/resolution.md: 2 new line(s) over 120 chars (not in the baseline)
line length ratchet: FAILED  (rc=1)
```

The two dispositions rows measure 182 and 140 content columns against
the review-README rule "Rows stay ≤ 120 columns … Evidence that does
not fit a row goes into the Evidence detail prose section below"
(internal/reviews/README.md:106-108). The ratchet genuinely covers
this: `docs_scope()` (test-line-length.sh:62-66) scans
`agent internal docs` markdown and exempts only immutable snapshots
(`internal/reviews/*/pr-*/review-*`), INDEX/legacy-index — resolution
files are deliberately living text in scope. All the overflow content
already exists in the Evidence detail blocks; the fix is a pure trim
of both rows to ≤120 (bookkeeping — closes the chain under the stop
rule, no `--regen` needed: the file has no baseline entry to burn).
How it passed: the fix wave verified only `test-git-config.sh`
(34/34); no full unit-suite run happened after the resolution landed
— exactly the L6/L4 shape "the wave's own output wasn't gate-checked".

## b W2 (LOW) — ratchet header comment misstates its own scope

test-line-length.sh lines 2-3 ("over the shipped scripts and the CI
workflows") and 39-43 (scope list + exclusions) describe only the
shell/workflow half; the markdown scope added by the structure wave
2026-10 (E4, lines 54-67) appears nowhere in the header. Anyone
reading the comment concludes internal/ is unpinning — the resolution
author wrote >120 rows believing exactly that, and both reviewer axes
plus the main agent's first pass repeated the misread until the test
was actually run. One comment sentence closes it; comments are not
review-relevant, so the fix closes the chain.

## b W3 (INFO) — markers hint exists in only one of the two status outputs

Pre-existing asymmetry surfaced by the wave's docs work: `opk status`
detects only rule-active vs not (status.sh:205-209), so a
markers-present config shows the same plain "access allowed" row as a
clean OFF — the hint line this wave documented lives exclusively in
`opk config git-config status`. No claim breaks: the how-to credits
`status` (the subcommand, same referent as line 33) with the hint,
and the phrase-parity claim covers the rows both commands render.
Recorded so a future wave that wants `opk status` to mirror the hint
starts here; no action owed in this chain.

## Verification (main agent)

- **Byte-identity**: config.sh:412/478 and status.sh:206/208 compared
  by grep -F with the literal phrases and by the sed sabotage
  round-trip below (a byte-level proof: the comma-form sed matched
  and flipped the suite red, the restore flipped it back). OFF phrase
  identical at config.sh:415/418/480 and status.sh:208. Population
  (`grep -rn 'agent tools blocked'` repo-wide): config.sh ×2,
  status.sh ×1, docs:37, test literals — no other rendering site;
  test-status.sh:868 pins status.sh's row unchanged (pre-existing,
  consistent). install.sh:2137 is a different message (axis-1).
- **Pin logic** (test-git-config.sh:287-310): `$STATUS` derived like
  `$CONFIG` (same `$SCRIPT_DIR/../../` pattern); the grep literals
  sit on the actual rendering lines (only occurrences — no
  comment/variable masking today); block sits before the summary
  gate, `fail()` → `failures>0` → `exit 1`.
- **Sabotage, both directions, independently reproduced** (work
  committed first per the house rule; tree clean at bc1a5db):
  1. config.sh ON sites → comma form: rc=1, `FAIL issue #205:
     git-config row wording regressed to bare ON/OFF` (33/34).
     Restored → 34/34 green.
  2. status.sh phrase → comma form: rc=1, same FAIL. Restored →
     green. This reproduces the resolution's red→green claims in
     both directions exactly as recorded.
- **Docs**: all three example blocks byte-exact against the rendered
  strings (ui_kv `  %-14s %s%s%s` puts the value at col 17 for the
  10-char key — docs' 5 spaces match; ui_detail 5-space indent;
  suffix `(markers present, rules inactive)` = config.sh:416). All
  five clauses of the new markers sentence verified against the
  code: detection keys on `//SECURE_GIT` (config.sh:414), `off` =
  `sed '/\/\/SECURE_GIT:/d'` deletes the marker lines, `on` =
  uncomment (render-agent-config.sh), the template exists and both
  apply paths render through it, "rules present but inactive" is the
  accurate description of commented deny rules. e2e greps match only
  the `ON` prefix + deny-rule presence — unaffected (axis-2).
- **Class sweep** (independent): `soft-only,` → exactly the 3 hits
  the resolution names (docs:8, e2e/run.sh:1062,
  test-jsonc-parser.sh:134), all unrelated strings; comma form of
  the git-config phrase survives nowhere in files/, docs/, tests/.
- **Bookkeeping**: review-a.md received only the `> Resolution:`
  pointer line in bc1a5db (git show); INDEX `open` is the generated
  default for a resolution without a `Status:` field
  (gen-review-index.py status()) — correct for a chain owing this
  snapshot; resolution vocabulary and SHAs correct.

## Claim audit

| Claim (fix commit / resolution) | Verdict |
|---|---|
| ON phrase = status.sh em-dash form at both sites | ✅ byte-verified |
| Pin requires both phrases verbatim in status.sh | ✅ read + sabotage dir 2 |
| Both sabotage directions red | ✅ independently reproduced (rc=1 ×2) |
| "34 passed" | ✅ observed after each restore |
| Class sweep: 3 unrelated `soft-only,` hits | ✅ exactly reproduced |
| How-to markers shape + on/off drop the markers | ✅ render path verified |
| a W2 disposition "Docs-only; no code change" | ✅ 7c790b8 docs hunk only |
| "owes snapshot b per the stop rule" | ✅ this snapshot |
| (implicit) suite green after the wave | ❌ test-line-length rc=1 → b W1 |

## L1–L7

L1 no new fail-soft spots in the diff (no new `|| true`/redirects;
the pin's failure path IS executed — sabotage). L2 sweep above, both
directions of the phrase class. L3 every wave claim audited (table;
one ❌ = b W1). L4 the new agreement check discriminates both ways and
sits before the summary gate — proven by execution, not reading; the
wave's own gate miss (suite not re-run) is b W1 itself. L5 no root
operations in the diff (strings + test greps + docs only; apply-path
logic untouched). L6 this snapshot is the owed micro-wave review. L7
no new scripts.

## Gates

- `sh tests/check-host.sh` — green at session start.
- `sh tests/unit/test-git-config.sh` — 34/34, rc=0; sabotage ×2 rc=1;
  restored green (main agent, one machine).
- `make lint` — green (ShellCheck passed).
- `sh tests/unit/test-reviews-lint.sh` — OK (20 cases).
- `sh tests/unit/test-reviews-parity.sh` — green with this snapshot +
  regenerated INDEX.
- `sh tests/unit/test-line-length.sh` — **FAILED rc=1** at HEAD
  (b W1; review-b.md itself is exempt as a review-* snapshot).
- e2e: not owed — display-string + docs + test change only, same
  scope call as snapshot a (no root-script behavior change).
- Environment: WSL2/GNU/Linux review host, clean tree at bc1a5db
  throughout except the two sabotage mutations (each restored
  immediately); axis-2 performed a temporary checkout of bc1a5db for
  byte-comparison and restored the branch — tree verified clean and
  HEAD re-checked afterwards.

## Retracted/ghost findings

- "The ratchet doesn't cover internal/ — README's 'ratchet pins this'
  is wrong" — retracted after running the test: docs_scope() DOES
  cover internal/ markdown (only review-* snapshots are exempt); the
  README claim is accurate, the header comment is the incomplete part
  (b W2).
- `$STATUS` assigned twice identically in test-git-config.sh (:161,
  :296) — harmless duplicate; noted as a no-op for the next touch of
  that block, not a finding.
- Pin greps source text, not rendered output (a future comment in
  status.sh carrying the phrase could mask drift) — latent, consistent
  with the house grep-pin style, literals sit on the only occurrences
  today; not flagged.
- docs:53 runs 85 cols — inside a ```text block whose whole point is
  rendering-exactness; the ratchet limit is 120 anyway.

## Provenance

b W1 delta-introduced (rows landed with this chain's resolution
commit bc1a5db, outside the nominal diff range, audited as the wave's
claim record). b W2 pre-existing (docs_scope landed with the structure
wave 2026-10; the wave only tripped over it). b W3 delta-introduced
doc sentence over pre-existing status.sh behavior. Run provenance:
header.

## Recommendation

**GO** — fix wave owed before merge. b W1's trim (resolution rows
≤120) and b W2's comment sentence are bookkeeping/comment-only
dispositions: under the stop rule they leave review-relevant code
untouched and close the chain — no snapshot c unless code changes.
b W3 is recorded, no action. The a-wave fix itself (7c790b8) is
verified correct end to end and needs no rework.
