<!-- review-meta
ID: pr-00208
Snapshot: c
Subject: issue-205 b W3 alignment — opk status shows the markers hint (micro-wave)
Scope: wave
Base: v0.0.53 @ f1dc37e
Diff: da6b08a..f1dc37e (fix commit f1dc37e; no bookkeeping in range)
Date: 2026-10-20
Reviewer: GLM-5.3 (house session — same-session c per maintainer instruction after reopening b W3 post-closure; rotation deviation recorded here — fresh-context glm-5.3-flash reviewer axis + main-agent verification, checkpoint /tmp/opencode/pr-00208-b/axis-c.md)
-->

# Review — pr-00208 snapshot c — micro-wave of the b W3 alignment (f1dc37e)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fix break or lie? Fix = `f1dc37e`: status.sh
gains the markers-present elif (same neutral OFF row plus the hint
line `$f (markers present, rules inactive)`, byte-identical to
config.sh:416), the agreement pin grows the markers literal on BOTH
sides, and the how-to sentence now credits both commands with the
hint. Result: **zero findings** — the alignment is exact, pinned, and
behavior-verified.

## Findings index

None (0 HIGH / 0 MED / 0 LOW / 0 INFO).

## Verification (main agent + reviewer axis)

- Branch logic, behavior-verified against the REAL template via
  `agent_config_render`: rendered `on` → ON branch (active rules
  win), raw template → MARKERS branch, rendered `off` → CLEAN
  branch — same precedence as config.sh:411-419.
- Byte-identity of the hint suffix status.sh:212 ↔ config.sh:416
  (string-compared); `ui_detail` mutes under `UI_SILENT=1`
  (ui.sh:78), so `opk status --short` stays one verdict line —
  symmetric with git-config status.
- Sabotage both directions (work committed first; mutate → red →
  restore → green): suffix reworded in status.sh → suite rc=1 (the
  issue-#205 pin); suffix reworded in config.sh → rc=1; restored →
  34/34 green.
- Claim audit: the docs sentence "Both `status` and `opk status`
  report that state with the same hint" is true; no stale asymmetry
  claim survives (grep sweep — only the 4 aligned sites carry the
  literal: docs example, config.sh, status.sh, test pin; the ddev
  docs' "markers" mentions are unrelated).
- Sibling sweep: the apply site (config.sh:478-482) renders the
  post-apply state — markers unreachable after a template re-render;
  install.sh's git-config row is install-time ON-only; tui/ has no
  git-config rows. status.sh was the only reachable markers display
  without the hint — now aligned.
- Regression: test-status.sh green (existing #158 presence/absence
  pins hold; the new branch adds no raw color args — the
  semantic-helper sweep pin unaffected).

## Gates

- `sh tests/unit/test-git-config.sh` — 34/34, rc=0; sabotage ×2
  rc=1; restored green.
- `sh tests/unit/test-status.sh` — green, rc=0.
- `make lint` — green. `sh tests/unit/test-line-length.sh` — rc=0.
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- e2e: not owed — display-only status.sh change (same scope call as
  snapshots a/b).
- Environment: WSL2/GNU/Linux review host, clean tree at `f1dc37e`
  throughout except the two sabotage mutations (each restored
  immediately).

## Retracted/ghost findings

- Pin greps source text and cannot prove branch reachability
  (suffix-only literal) — same shape as the pre-existing
  `_gc_prot`/`_gc_allow` pins; the behavioral smoke above covers
  reachability for this round. Not a finding.

## Provenance

Zero findings — nothing to classify. Run provenance: header.

## Recommendation

**GO.** Zero findings; the chain closes here: this round's
dispositions (resolution bookkeeping only) leave review-relevant
code untouched — no snapshot d owed.
