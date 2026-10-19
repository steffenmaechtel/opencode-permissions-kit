<!-- review-meta
ID: pr-00202
Snapshot: e
Subject: d-wave follow-up — issue-165 test labels normalized from '165:' to '#165:' (test-status.sh messages only)
Scope: wave
Base: v0.0.52 @ 4b4b70a
Diff: fcb815a (single fix commit, tests/unit/test-status.sh +65/-65, message strings only; 9a39433 is resolution bookkeeping, not review-relevant)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per the rotation rule; single-pass main agent, no subagents — maintainer-requested micro pass)
-->

# Review — pr-00202 snapshot e — d-wave follow-up (165: → #165: labels)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `fcb815a` (d W1
follow-up, maintainer-commissioned): all 65 `165:` message prefixes in
tests/unit/test-status.sh become `#165:` so log tails read them as
issue IDs, not a running pass counter. Commit message: "65 sites,
messages only", style matched to the existing `#166:` labels.

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | INFO | the d W1 correction note's split "137 test passes + summary = 138 PASS" is off by one — measured 138 pass-helper lines and the closing summary is lowercase "passed", invisible to the case-sensitive `grep -c PASS`; correction belongs in the resolution, no code change | pre-existing |

## W1 (INFO) — resolution's authoritative pass count is 138, not 137

Re-measured this session on HEAD (`9a39433`): `sh tests/unit/test-status.sh`
yields **138** lines containing case-sensitive `PASS`, 0 FAIL, 0 SKIP,
rc=0 — and every one of those 138 lines matches the pass-helper shape
(`\033[0;32mPASS\033[0m` + two spaces; `grep -v` for that exact shape
returns zero). The closing summary line is `All status tests passed.`
— lowercase "passed", so it cannot be the +1 the d note claims. The
true decomposition: **138 test passes**, summary separate. Snapshot d
(line 37f) and resolution.md (d W1 evidence, "Authoritative figure …
137 passes") inherited the same off-by-one; the `138 PASS` grep figure
both cite is correct, its split is not. The wave under review neither
introduced nor touched the figure. Shipped code unaffected; snapshots
are immutable, so the correction is a resolution note (bookkeeping
only — closes the chain without touching review-relevant code). Same
shape as d W1 itself: a gate figure that does not decompose as written.

## Verified claims (commit/resolution audit)

- "65 sites, messages only": every changed line enumerated — all 65
  `-`/`+` pairs are `pass "…"` / `fail "…"` message strings (incl. the
  two case-branch forms at the readiness-chain pin); no assertion
  operand, pattern variable, or logic line touched; file mode stays
  100755 (CI executes it by path, test-unit.yml:120).
- The rename is output-only: CI gates on the exit code, no output
  parsing; no occurrence of `"165:` remains anywhere under tests/ or
  files/; nothing in `.github/`, `scripts/`, `Makefile` references the
  bare label form.
- "matching the '#166:' label style already in the same file": holds —
  `#166:` sites at test-status.sh lines 1437/1439/1464.
- Class-sweep claim "(pass|fail) `"[0-9]+:` → zero hits across
  tests/unit + tests/e2e": reproduced. Broadened beyond the claim
  (skip labels, single-quoted variants, whole tests/ tree): the only
  hit is the binary cache artifact
  `tests/e2e/cache/ddev-images-1.25.4-f1.tar` — not source.
- Suite/lint/version gates reproduce the resolution's figures verbatim
  (138 PASS / 0 FAIL / 0 SKIP rc=0, lint green, 0.0.52) — except the
  137 split (W1 above).

## Gates

- `sh tests/unit/test-status.sh` — green rc=0, 138 pass lines,
  0 FAIL / 0 SKIP; closing summary lowercase.
- `make lint`, `make check-version` — green (VERSION 0.0.52).
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, GNU grep 3.11, /bin/sh →
  dash; clean tree at `9a39433` throughout (no mutations needed —
  the wave is message text only, no pin references it).

## Retracted/ghost findings

None filed. Explicitly considered and dropped: a style-lint pin
forbidding future bare numeric pass/fail labels — the sweep has zero
hits and the phantom-counter class is closed by the normalization
itself; a new guard would be review-relevant code and extend the chain
for a failure mode that needs a human to misread a log, the exact
taste ping-pong the five-round stop rule prevents.

## Provenance

W1 pre-existing (bookkeeping): the 137/138 split entered the record
with review-d.md (`4b4b70a`) and was carried into resolution.md
(`9a39433`); the reviewed wave (`fcb815a`) neither introduced nor
touched it. Run provenance: header.

## Recommendation

**GO.** The d-wave follow-up does exactly what its commit message and
the resolution claim — 65 message-only sites, style matches `#166:`,
bare-label sweep zero hits, all gates green, no consumer of the old
form anywhere. W1 is a resolution-note correction (bookkeeping only).
Once its disposition lands, the round touches no review-relevant code
and the chain closes under the stop rule.
