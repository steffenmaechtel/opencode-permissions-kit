<!-- review-meta
ID: pr-00224
Snapshot: b
Subject: issue-197 micro wave — fixes for a W1/W3/W4/W6 (offline fallback lane preference, pin labels, pin ordering)
Scope: wave
Base: feature/e2e-default-2x @ 46d4998
Diff: d7c7a26..46d4998 (fix wave 3956c70 + record-only addendum 46d4998)
Date: 2026-10-23
Reviewer: GLM-5.3 (external review session, single pass — micro wave, no fan-out)
-->

# Micro-wave review — pr-00224 snapshot b — a-wave fixes (3956c70)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Scope is the fix commit
`3956c70` (lib.sh offline fallback, test-e2e-sources.sh pins/labels,
record sentence) plus the record-only addendum `46d4998`. The tree is a
clean checkout of `46d4998` on `feature/e2e-default-2x`; nothing was
mutated in it (sabotage probes ran on /tmp/opencode copies).

## Findings index

| ID | Sev | Location | One-line summary | Verified | Prov |
|---|---|---|---|---|---|
| W1 | INFO | internal/reviews/0/0/2/2/pr-00224/resolution.md:76-77 (L1 walkthrough) | the L1 sentence claims the empty-cache hard-fail "keeps its FAIL and its pin" — the FAIL exists (lib.sh:328) but NO pin covers it: `grep -rn 'cannot resolve opencode' tests/` hits only lib.sh itself, pre-wave neither; deleting the FAIL branch (`exit 1` included) leaves every pin green (OC_VERSION stays empty and fails later, messily, in e2e_fetch_opencode). Record-accuracy gap plus a named unpinned surface — fix is either a one-line reword of the resolution (bookkeeping, loop closes per RM-0066) or a new hard-fail pin (test code, owes micro-wave c) | yes (grep across tests/ pre- and post-wave; pin-green-under-deletion traced by reading all fallback pins) | wave-introduced |

Verified clean (all re-verified against the code this session):

- **a W1 fix mechanism (lib.sh:317-330)**: on-lane glob
  `opencode-2.*` → newest cached 2.x via `sort -V | tail -1`; empty
  result (unmatched glob passes literally to ls, stderr suppressed)
  falls through to the generic glob with the named off-major warning +
  `E2E_OC_VERSION` escape hatch; empty both → FAIL + exit 1 preserved.
  Glob semantics consistent with the anchored gate: `opencode-2.*`
  excludes a hypothetical `opencode-20.x` exactly like `^2\.` does.
  Behavior-compatible with pre-flip offline caches (same binary picked,
  now loudly named) — matches the resolution's deliberate
  warn-not-fail rationale and the record sentence in opencode-2x.md.
- **a W1 pins discriminate (sabotage, /tmp copies)**: deleting the
  `opencode-2.*` line reds the glob pin; deleting the off-major warning
  line reds the warning pin — each for the reason the pin exists (the
  text vanished, not an rc fallthrough).
- **a W6 order pin (test-e2e-sources.sh:82-88)**: both grep patterns are
  unique in lib.sh (pin 304, resolve 306 — `head -1` is therefore the
  execution-relevant pair); sabotage red on BOTH failure branches:
  assignment moved below resolve (307 vs 305 → "order violated") and
  assignment deleted ("pin line: missing"). Pin sits before the summary
  gate (L4).
- **a W3 label accuracy**: both `OPK_GH_TOKEN` sites in test-e2e.yml
  (302, 359) are the -1x resolvers (anchored `^1\.` confirmed);
  run-ddev.sh is the only `gh_latest_tag` caller (default lane makes no
  api.github.com call — the narrowed premise is TRUE); the pointer to
  test-workflows.sh's lane pins resolves (lines 266/276/285).
- **a W4 header accuracy**: the file header now names the behavioral
  fake-curl probes next to the structural greps — matches the file's
  content.
- **Class sweep reconciled (RM-0082 — re-run independently)**: the
  addendum's grep reproduces exactly: 7 hits, 7/7 classified the same
  (lib.sh 319/321/323/325 = the wave's own lines; the pin pattern
  itself; run-ddev.sh:88 ddev fallback with no major-lane contract
  claimed anywhere — honest non-sibling; advisories.sh:48 version
  comparison). No missed sibling site.
- **Suites**: `sh tests/unit/test-e2e-sources.sh` 40/40 green; full
  `make test` green on this tree (independently confirms the addendum's
  claim); `sh -n` clean.

## Retracted/ghost findings

None — one candidate investigated and dropped: "off-major warning says
`no cached 2x` while house style writes `2.x`" — cosmetic string inside
a pinned message, not worth churn.

## Provenance, gates, recommendation

- Model: GLM-5.3 (zai-coding-plan), external review session, single
  pass, no fan-out — micro wave (~5 min discipline: batched greps,
  targeted reads only).
- Tree: `46d4998` on `feature/e2e-default-2x`, clean (no uncommitted
  changes); tree untouched during the pass (sabotages in /tmp/opencode).
- Gates run: test-e2e-sources.sh (40/40), full `make test` (green),
  sabotage spot-checks S1–S4 (all red for the right reason).
- Recommendation: **GO for round b disposition of b W1** — one INFO
  finding, record-text. Recommended disposition: reword the L1 sentence
  ("keeps its FAIL; the FAIL branch is unpinned — pre-existing") —
  bookkeeping only, loop closes (RM-0066). Alternative (add a
  `cannot resolve opencode version` pin) touches test code and would
  owe micro-wave review c; take it only if the pin is wanted now.
