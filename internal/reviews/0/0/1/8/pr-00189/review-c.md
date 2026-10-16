<!-- review-meta
ID: pr-00189
Snapshot: c
Subject: issue-187 fix wave (a W1/W2) micro-wave review — session-rotation backup pass
Scope: wave
Base: v0.0.50 @ 43bd33e
Diff: e901276..2074884
Date: 2026-10-17
Reviewer: GLM-5.3 (fresh session C — backup pass over b's scope; main agent + 2 Flash subagents)
-->

# Review — pr-00189 snapshot c — fix wave re-review (fresh session)

> Resolution: [resolution.md](resolution.md)

Why this snapshot exists: review `b` verified fix commit `4fb7ebd`
inside the session that had implemented the wave and written review
`a` — the exact situation the session-rotation standard
(agent/review-concept.md, added 2026-10-17 from this case) now
prohibits. `c` re-runs b's scope with fresh context in a new session:
the fix wave (`4fb7ebd`, code: ui.sh `IFS=` dropped ×2, opk fallback
read, uninstall comment, check-host `script` row, +8 padded pins,
records) plus the post-b delta (`4fb7eb159`..`2074884`: resolution,
snapshot b, and the process-docs commits `284ad26`..`2074884` —
docs/bookkeeping only). Question per review-concept: did the fixes
break or lie?

**Verdict: 0 HIGH/MED, 0 LOW, 6 INFO — b's "fix wave clean" result
independently confirmed; merge-ready stands.**

## Findings index

| ID | Severity | Provenance | Summary |
|---|---|---|---|
| C1 | INFO | wave-introduced | relabeled `'y '` pin's label asserts trim-explicitness its rc-0 observable cannot discriminate |
| C2 | INFO | wave-introduced | 4fb7ebd message "+4 incl. relabel" — actually 4 new pins + 1 separate relabel |
| C3 | INFO | wave-introduced | 4fb7ebd message: "both real ui_ask callers" — there are three call sites (two flows) |
| C4 | INFO | wave-introduced (wording) | trim claims say "whitespace"; read trims IFS whitespace — a CR survives in pipes |
| C5 | INFO | delta-introduced | review-concept "honestly labeled in the header" — b's header cannot encode session identity |
| C6 | INFO | wave-introduced | whitespace-only ui_ask input now resolves to the default — unpinned |

## Verified (independently, this session)

1. **Sabotage matrix reproduced.** `IFS=` re-added at all three fix
   sites (ui.sh ×2, opk ×1): test-ui 4 FAILs (the four new padded
   pins), test-kit-cli 2 FAILs — exactly the resolution's documented
   4/2/2; restored, both suites green again. The relabeled `'y '`
   pin stayed green under sabotage (deliberately non-discriminating,
   as the resolution discloses). Pins sit before the summary gate
   (`exit 1` on failures > 0) — FAILs fail the suite (L4a).
2. **Trim-class sweep (L2).** `grep -rn "read -r" files/`: exactly
   four un-prefixed sites, all answer readers (ui.sh:171/:178,
   opk:46, uninstall.sh:144); every other read is an IFS-prefixed
   data/line reader — none flipped, none missed. No bare `read`
   without `-r`.
3. **Ambient-IFS probe.** `read -r` trims only under an IFS
   containing space/tab (verified: `IFS='|'` disables it; dash and
   bash trim identically by default; whitespace-only input → empty;
   internal runs survive). The only non-prefix IFS assignment in
   shipped code (`wsl-browser-bridge.sh:196`, `IFS=:`) is
   save/restored on every path and prompts nobody in the window —
   no shipped prompt path runs under a foreign IFS.
4. **check-host row truth.** `script -qec` used by exactly the four
   named suites (test-ui:74, test-kit-cli:611, test-uninstall:462,
   test-browser-bridge:479); header comment matches the probes;
   placement in the required section is truthful (kit-cli/uninstall
   pins hard-fail without it).
5. **Records vs code (L3).** conventions.md trim bullet, RM-0006
   body/check/log, the three code comments, and RM-0006's
   "padded pins under both defaults in three suites" all verified
   true at HEAD (pins seen passing in the full sweep + diff count).
   Rotation docs net state consistent across review-concept.md,
   process/review.md and reviews/README.md after the beb8f0c revert;
   the [GO] diagram matches the bullets (axis-2 section checks).
6. **Gates.** check-host OK; `make lint` green; full unit sweep
   (`make test`) green at HEAD incl. reviews lint + index parity,
   line-length ratchet, sandbox policy. E2e not owed (no
   install.sh/update.sh/wrapper/backend semantics change — a/b
   precedent; install.sh answer handling only widens accepted
   input). POSIX probes ran outside the tree.

## Findings

### C1 (INFO) — the relabeled `'y '` pin label overstates its proof

test-ui.sh's relabeled check says "trailing-space 'y ' trimmed to an
explicit yes" and asserts rc 0 — but under the OLD V17 semantics
('y ' = unknown → y default) the rc is also 0. The observable cannot
discriminate; only the adjacent `'no '`-under-y pin (added in the
same commit) does. The resolution honestly documents the split; the
in-test comment ("'y ' is EXPLICIT input (pin below)") does not flag
the pin as keep-green-only. Sabotage confirms: pin green with and
without the trim. Options: align label/comment (a string-only touch
in a test file), or no action.

### C2 (INFO) — commit-message pin count off by structure

4fb7ebd: "test-ui +4 incl. relabel" reads as the relabel being one
of four; the diff has 4 NEW pins plus 1 separate relabel (5 touches).
The resolution already carries the correct count ("test-ui +4 (the
four new pins)" + relabel separately). Commit messages are immutable
history — no fix site; calibration for future message precision.
(Reported LOW by the claims axis; downgraded INFO on verification:
no actionable site, authoritative record correct.)

### C3 (INFO) — commit-message ui_ask caller count

4fb7ebd: "both real ui_ask callers take paths" — three call sites
exist: install.sh:985 (project directory), config.sh:775 (paths to
add), config.sh:780 (path to remove) — two arms of one config flow.
Substance holds: every site takes path(s), so the trim rationale is
unaffected (internal spaces are separators there and survive).

### C4 (INFO) — "whitespace trimmed" is IFS-whitespace in reality

conventions.md's RM-0006 bullet and RM-0006's body say
"leading/trailing whitespace is trimmed"; `read` strips IFS
whitespace (space/tab/newline) only. A trailing CR survives the trim
— on ptys ICRNL converts it to NL first (probed; padded input trims
fine there), but a CRLF answer piped into the stdin-fallback read
(tests/expect scripts) would fall to the default instead of being
honored. Pre-fix behavior for that shape was the same class
(unknown → default); defensible, unpinned either way. Optional:
tighten wording to "edge whitespace" / "space and tab" when next
touched.

### C5 (INFO) — "honestly labeled in the header" overstates the artifact

agent/review-concept.md:58 says snapshot b's same-session fact was
"honestly labeled in the header". review-b.md's Reviewer line reads
"GLM-5.3 (house session, main agent — single-pass micro-wave
review, empirical verification)" — IDENTICAL wording shape to
review-a.md's header. "house session" encodes the house/external
axis, not session identity; if it sufficed, every fresh house pass
would also count as "labeled". Nothing in b's header or body states
or implies it shared a's session, so the rotation is not auditable
from the committed artifacts — which is exactly what the new
Reviewer-line bullet demands. Reviewer disagreement recorded: the
claims axis accepted the house-idiom reading ("supported via the
house idiom") and proposed no action; verification disagrees on the
reading (the idiom cannot carry the meaning) but concedes the
sentence has a weaker defensible reading, hence INFO not LOW.
Snapshots are immutable — the fix is rewording the concept-doc
sentence when next touched (docs-only, closes per 0.0.45f).

### C6 (INFO) — whitespace-only ui_ask input now defaults, unpinned

With the trim, `"   "` at ui_ask resolves to the default (pre-fix:
honored as a literal whitespace answer). Direction is right and
matches B1's acceptance at install.sh's loops — but B1's coverage
pins the `_ui_read` selection loops (W6/W14), not ui_ask itself; no
pin locks ui_ask's whitespace-only→default. A one-line pin would;
implementing it touches test code and would owe micro-wave `d`
(stop rule) — deliberately-not-done also closes.

## Retracted / ghost findings

- C5 initially rated LOW by the main agent before the claims axis's
  counter-reading ("house session" idiom is honest labeling) arrived;
  downgraded to INFO with both readings recorded rather than
  retracted — the sentence is imprecise about a checkable fact, not
  demonstrably false under every reading.
- "ui.sh's /dev/tty branch (:171) is unpinned": the padded pins in
  test-ui exercise the stdin-fallback branch (:178) — setsid has no
  controlling tty. The /dev/tty read class is pty-pinned via opk's
  fallback and prompt_yn, and both branches are the identical
  `read -r "$1"` statement. Residual, recorded in C-verification
  notes, no finding.

## Provenance, gates, recommendation

- **Model:** GLM-5.3 main agent (fresh session C) + 2 fresh-context
  GLM-5.3-Flash axis subagents (semantics; claims/records —
  checkpoint files /tmp/opencode/pr-00189-c/axis-{1,2}-*.md,
  outside the tree). Every subagent finding re-verified by the main
  agent; one severity downgraded (C2), one disagreement recorded
  (C5). Merge C-foundings: T2≡C3, S1→C1, S3→C6, T1→C2, T3→C4.
- **Tree:** `feature/y-n-prompt-consistency` @ `2074884`, clean;
  base code `43bd33e` (v0.0.50). Diff `e901276..2074884` = fix
  commit `4fb7ebd` (code) + `f1f8847`/`4e6b159` (bookkeeping) +
  `284ad26`..`2074884` (process docs).
- **Gates run:** check-host OK; make lint green; full unit sweep
  green; sabotage matrix 4/2/2 reproduced and restored green;
  dash/bash/pty probes. E2e not owed (see Verified 6).
- **Index mechanics:** review-c lands with a regenerated INDEX
  (snapshots a–c); the generator copies resolution.md's Status line
  — if any finding below is implemented in code, the Status must be
  hand-edited and the chain re-opens per the stop rule.
- **Recommendation:** b's closure result confirmed independently —
  0 HIGH/MED/LOW. Suggested dispositions: C1–C5 deliberately not
  done (all six no-action closes the loop; C1/C4/C5 could instead
  be tightened as comment/docs-only touches, which also close per
  the 0.0.45f precedent); C6 optionally implemented as a one-line
  pin — the only option that would owe a micro-wave `d`. The
  maintainer's go decides; this session applies whatever is chosen.
