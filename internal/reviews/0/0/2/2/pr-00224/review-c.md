<!-- review-meta
ID: pr-00224
Snapshot: c
Subject: issue-197 micro wave c — b W1 follow-up pin: empty-cache hard fail (FAIL + adjacent exit 1)
Scope: wave
Base: feature/e2e-default-2x @ 5a5aaad
Diff: bd4fe50..871f1b1
Date: 2026-10-23
Reviewer: GLM-5.3 (fresh rotating session per FU 4 — single pass, no fan-out)
-->

# Micro-wave review — pr-00224 snapshot c — b W1 follow-up pin (871f1b1)

> Resolution: [resolution.md](resolution.md)

Wave question: did the round-c fix break or lie? Scope is the fix commit
`871f1b1` (tests/unit/test-e2e-sources.sh +6: the empty-cache hard-fail
pin, b W1's optional follow-up taken via FU 4 on the maintainer's go
2026-10-23). The ledger commits after it (`02860c2` round-c ledger,
`5a5aaad` e2e-debt discharge) are bookkeeping — read for the claim
audit, not reviewed as code. Tree: clean checkout of `5a5aaad`; this
pass is the fresh-session review FU 4 owed (rotation honored — the pin
wave's authoring session did not review it).

## Findings index

None — zero findings.

## Verified clean (all verified against the code this session)

- **The pin pins the real construct, uniquely**: the pinned pair is
  `tests/e2e/lib.sh:328-329` (`FAIL ... cannot resolve opencode version
  and no cached version available.` + adjacent `exit 1`). The adjacency
  anchor `cannot resolve opencode version` occurs exactly ONCE in lib.sh
  (`grep -c` = 1), so the `grep -A1` window covers exactly the FAIL line
  and its successor — no cross-occurrence false-green is possible. The
  message half matches the lib text (trailing period outside the
  pattern, substring-safe).
- **All three sabotages red for the pin's own reason** (deletion, never
  comment-out; /tmp/opencode/pr00224-microc copy — the review-b pattern,
  tree untouched during the pass): S1 delete the FAIL echo line → red
  (message half); S2 delete exactly the adjacent `exit 1` (diff
  confirmed the one-line deletion) → red (adjacency half); S3 keep BOTH
  halves but interpose an echo between them → red — the
  both-present-not-adjacent state the comment names as the false-green
  adjacency exists to catch. Each run: exactly one failure (the new
  pin), restore green. A reversed order (`exit 1` before the echo)
  would also red — the correct discrimination, that order is the
  silent-failure shape.
- **L4 placement + discrimination chain**: the pin sits at
  test-e2e-sources.sh:83-84, mid-file, before the summary gate
  (211-217); `check` → `fail()` bumps `failures` and the summary exits 1
  — a FAIL fails the suite (suite runs `set -u` without `set -e`, so a
  failed pin does not skip later pins).
- **L2 class sweep (recorded)**: `grep -n 'exit 1' tests/e2e/lib.sh` →
  11 sites. The empty-cache site (329) is now pinned. The npm-gate exit
  (311) is presence-pinned by the a-wave gate pins (anchored `^2\.[0` +
  escape-hatch message), not adjacency-pinned — no record or doc claims
  it is; the other nine (npm/GitHub download+extract, tarball layout,
  OS check, empty binary, installer fetch, old-binary check, run.sh
  guard) are e2e scaffolding, unpinned and unclaimed pinned anywhere
  (greps over internal/, docs/ and the test headers). No missed sibling
  of the claimed class.
- **L3 claim audit (wave-touched claims)**: the pin label ("empty cache
  fails loud") and comment block hold — "OC_VERSION empty → messy
  failure far downstream" confirmed by code read: without the exit,
  `OC_VERSION` stays empty → `OC_BIN="$OC_CACHE_DIR/opencode-/opencode"`
  → not executable → `e2e_fetch_opencode ""` → the 341 empty-binary
  FAIL, exactly what b W1 traced. Resolution FU 4, the ledger row
  ("b W1 pin (FU 4) | implemented | `871f1b1`") and the status header
  match the committed reality; "sabotage both halves" re-verified as
  S1/S2 above. Citation format `#224 b W1` in label and commit message
  correct.
- **Form**: tests/ are deliberately outside the line-length ratchet;
  the 175-column `sh -c` one-liner matches the file's established
  idiom (same shape at lines 148/150/152). Exec bit 100755 preserved.
  Sandbox policy green (in `make test`).

## Retracted / ghost findings

None — three candidates investigated and dropped:

- `grep -A1` is a GNU/BusyBox extension, not POSIX — dropped: the suite
  already depends on GNU `sort -V` (pinned by the a-wave glob pin) and
  GNU grep flags throughout; kit hosts are Linux/WSL.
- "structural pin cannot catch an unreachable FAIL branch" — dropped:
  consistent with the file's documented lib.sh treatment (the block is
  inline in e2e_resolve_cache, not extractable; a-wave pins are the
  same class); the decision is recorded in the resolution's a-W1
  evidence.
- The resolution's L1 walkthrough still reads "the FAIL branch itself
  carries no pin" — dropped: that text is scoped to the b-wave round
  ("this wave") and is reconciled in the same file by the ledger row
  and FU 4 (pinned since `871f1b1`); no reader following the chain can
  be misled for longer than one section.

## Provenance, gates, recommendation

- Model: GLM-5.3 (zai-coding-plan), fresh rotating session, single
  pass, no fan-out — micro wave (~5 min discipline: batched greps,
  targeted reads only).
- Tree: `5a5aaad` on `feature/e2e-default-2x`, clean; reviewed range
  `bd4fe50..871f1b1`; nothing in the tree was mutated (sabotage probes
  ran on the /tmp/opencode copy; no parallel readers existed).
- Gates run: `sh tests/unit/test-e2e-sources.sh` green (real tree and
  copy), full `make test` green on `5a5aaad`, sabotage spot-checks
  S1–S3 (all red for the right reason, restores green).
- Recommendation: **GO — zero findings.** Round c's disposition
  (`871f1b1`) is verified as claimed. Loop-closure expectation per
  RM-0115, check cited: this round's own disposition is the snapshot
  plus ledger bookkeeping only — files touched =
  `internal/reviews/0/0/2/2/pr-00224/review-c.md` (new snapshot),
  `INDEX.md` (regenerated), `resolution.md` (status header + FU 4
  marker) — none of them review-relevant code under RM-0065, so the
  loop is expected to close; closure for the maintainer to confirm.
