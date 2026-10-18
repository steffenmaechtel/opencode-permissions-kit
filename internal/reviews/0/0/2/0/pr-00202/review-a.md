<!-- review-meta
ID: pr-00202
Snapshot: a
Subject: issue-168 fix wave — widen the mktemp fixed-path fallback class sweep repo-wide (test-status.sh only)
Scope: wave
Base: v0.0.52 @ 5975524
Diff: 5975524..63c9f02 (single wave commit, tests/unit/test-status.sh +24/-5)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — single-pass main agent, no subagents — micro wave 29-line diff, maintainer-requested quick pass)
-->

# Review — pr-00202 snapshot a — issue-168 (W2 class sweep widened to pattern form)

Wave question: did the fix break or lie? Wave = 63c9f02 (PR #202):
rewrites the 0.0.48b W2 class-sweep pin in `tests/unit/test-status.sh`
from a var-name-scoped grep (`_(share_list|hosts_list|gap_roots)=/dev/null`
against status.sh only) into a pattern-based repo-wide grep over `files/`
(two ERE alternations: assignment fallback to a fixed path, and
in-substitution `|| echo <fixed path>` fallback). Closes pr-00160
review-c C7 (INFO: the old sweep was var-name-scoped).

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | widened sweep has no canary — its fail branch never executes in-suite | wave-introduced |
| W2 | INFO | pin comment over-claims "sanctioned fallbacks … do not match" for `|| { … }` | wave-introduced |

## W1 (LOW) — no canary for the widened sweep pattern

The new sweep greps real `files/` and (by design, verified) finds zero
matches — so within the suite only the PASS branch ever runs. The FAIL
branch (offending line present → `fail`) has no pin: if a future edit
breaks the regex (stray quote, alternation typo, `[:space:]` slip), the
sweep stays green while blind — the 0.0.42e C2 ground-truth class
("guards are themselves review objects"; a token-blind guard reported
green while an argument-position suite never ran). The repo already
codifies the fix as a convention: `tests/unit/test-kit-files.sh` §4
"canary: the guards themselves catch drift" — *"A guard that cannot
fail is decoration."* The old fixed-string pin carried near-zero
blinding surface; the new two-alternation ERE creates it.

Fix shape (test-only, ~6 lines in test-status.sh next to the sweep):
echo one offending line (e.g. `_x=$(mktemp) || _x=/dev/null`) and one
sanctioned line (e.g. `_x=$(mktemp) || return 1`) into `$WORK`, grep
the scratch file with the SAME `$W2_FIXPATH_A|$W2_FIXPATH_B` expression
(not a re-implementation), assert exactly the offending line matches.
That pins both directions the comment claims: offending shapes are
caught, sanctioned shapes pass.

Reviewer verification performed (this session, scratch under
/tmp/opencode, tree untouched): the exact combined expression matched
all 7 probed offending shapes — unquoted/quoted values, no-space `||`,
`/tmp` and `/var/tmp` literals, `sudo mktemp` prefix, in-substitution
`|| echo /dev/null` incl. `2>/dev/null` muffling — and none of the 6
probed sanctioned shapes (`|| return 1`, `|| X=""`, `|| { …; return 1; }`,
`|| exit 1`, `mktemp -p /tmp` with sanctioned fallback,
`|| echo warn >&2`). The pattern discriminates today; W1 is only about
keeping that true across future edits.

## W2 (INFO) — comment over-claim on `|| { … }` sanctioned fallbacks

The pin comment states "The sanctioned fallbacks (|| return 1, || X="",
|| { ... }) do not match." The brace claim is over-broad: a brace
fallback that ASSIGNS a fixed path — `X=$(mktemp) || { X=/dev/null; }`
— matches shape A (`[^|]*=` reaches inside the brace). That is the
desirable direction (this is a dangerous form and SHOULD flag), but as
worded the comment implies all brace fallbacks are invisible. All LIVE
`|| {` sites (ddev-migrate.sh:579) assign no fixed path, so the green
run pins the live forms. Docs-only tightening if dispositioned; no code
behavior at stake.

## Verified claims (commit-message audit)

- "verified zero-match against files/" — re-run of the exact combined
  grep over `files/`: zero hits. Holds.
- Manual enumeration of every `mktemp` line in `files/` (11 sites incl.
  install.sh, sudoers-deploy.sh, ddev-migrate.sh, status.sh ×3,
  setup-container-backend): all sanctioned forms (`|| return 1`,
  `|| X=""`, `|| { … }`, `|| exit 1`). No fixed-path fallback exists —
  the sweep's zero-match is a true negative, not a regex miss.
- Scope decision (files/ only, tests/ excluded) is correct: the danger
  class is shipped root-running code; tests/fixtures may legitimately
  carry offending strings.
- Multi-line fallbacks deliberately not swept — documented at the pin;
  accepted residual (grep is line-scoped; a wrapping `|| \`n`X=/dev/null`
  escapes both shapes).
- Sibling sweep check: no other var-name-scoped sweep pins remain —
  the only surviving reference to the old pattern is the pr-00160
  review-c C7 finding row (evidence, correctly untouched).

## Gates

- `sh tests/unit/test-status.sh` — green rc=0, 165 PASS incl. the new
  "W2 class sweep: no mktemp fixed-path fallback in any shipped script
  (#168)".
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, GNU grep 3.11,
  /bin/sh → dash, clean tree at 63c9f02. No sabotage-mutation run this
  pass (scratch-file probe used instead — tree never mutated, so the
  secured-work precondition of in-tree sabotage does not apply).

## Retracted/ghost findings

One, retracted during verification: "shape A's `[^)]*` before `\)` can
span `|`, so sanctioned `$(mktemp ... || echo x)` substitutions might
false-positive via shape A" — shape A still requires an `||` AFTER the
closing paren plus `= <fixedpath>`, so the in-substitution form cannot
trip A; and shape B targeting that form matched every probed offending
variant while passing all sanctioned ones. Not a finding.

## Provenance

W1 wave-introduced (blinding surface created by the new two-alternation
ERE; the old fixed-string pin had none worth a canary). W2
wave-introduced (new comment). Run provenance: header.

## Recommendation

**GO.** The widening is correct, discriminates empirically, and closes
pr-00160 C7 as claimed. W1 is a test-only canary addition (would itself
owe the next micro wave under the stop rule — code-touching round);
W2 is comment-only. Both can ride one small fix commit on this branch;
neither blocks the PR.
