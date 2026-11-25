# Review learnings — the per-wave checklist

> **Status: CURRENT (derived from the analysis runs 2026-10-10 and
> 2026-10-22).** This is the enforcement short-form — every rule here is
> backed by a recurring defect class measured across the review corpus.
> Evidence, chains and full tables:
> [README.md](../internal/reviews-meta/2026-10-22/README.md) ·
> [statistics.md](../internal/reviews-meta/2026-10-22/statistics.md) ·
> [further-analyses.md](../internal/reviews-meta/2026-10-22/further-analyses.md)
> (current run, corpus 0.0.47–0.0.55) and
> [2026-10-10/](../internal/reviews-meta/2026-10-10/README.md) (first run,
> corpus 0.0.38–0.0.46). Agents get this page via
> [AGENTS.md](../AGENTS.md); reading the statistics is NOT required to
> apply the rules.

## Why these rules exist

The meta-analyses found the same error classes recurring with every new
feature — a new feature means a new instance of a known class at a new site,
not a new kind of mistake (`silent-failure` appeared in 8 of 15 groups of
the current corpus after all 9 groups of the first; `sibling-sweep`
returned at 25 findings after a one-version dip to zero; 20 % of the first
corpus's findings were fix-induced — the enforced micro-wave-review
discipline (today's low-tier re-review) cut that to 9.3 % in the second).
Classes collapsed only after
an **enforced process step** existed — naming a class alone never stopped
it, and two "collapsed" trends did not survive contact with the next
corpus (see "Keep doing" below). Each rule below is that step for its
class.

## The rules (L1–L7)

### L1 — Fail-loud pins for new fail-soft spots
*Class: `silent-failure` — run 1: 62 findings, 13 MED/HIGH, all 9 version
groups; run 2: 23 findings, 6 MED/HIGH, 8 of 15 groups.*

Every new `|| true`, stderr redirect, or probe pipe in feature code gets a
pin that **executes the failure path** — a stub or `chmod 000` that forces
the error — and asserts the failure is observed (a skip/failed note), not
silence. The pin must observe the message the way production does: if a
caller discards stderr, a `2>&1` pin proves nothing (`0.0.46b W1` — "loud"
was unreachable at the named caller). The unconditional-success-line shape
recurs across both corpora (`0.0.47a F1` policy overwrite, `pr-00211 a F2`
missing-lib fallbacks printing success) — the mktemp-fallback chain
(`0.0.48b W2` root `rm -f /dev/null` → `pr-00221 a W3` false-green over a
dead scan) is this class at its most expensive.

The pin demand is cost-bounded, not absolute: a fixture that would
exceed ~30 lines for a LOW/INFO finding is not shipped — the finding
is dispositioned as an accepted residual with the breach named
(rule: [conventions.md](conventions.md) "Pin-cost budget"; origin
#262 P4 / §11e).

### L2 — Class sweep before "implemented"
*Class: `sibling-sweep` — run 1: 46 findings, 13 MED/HIGH, zero in 0.0.46;
run 2: **returned** — 25 findings, 6 MED/HIGH, 9 of 15 groups. The
one-version zero was a dip, not a trend.*

A fix for a finding is only dispositioned *implemented* after sweeping **all
same-shape sibling sites**, and the resolution records the evidence: the grep
pattern used and the sites checked. "Fixed at the site the finding named" is
the definition of this defect class (`0.0.39h F1` HIGH: "missed sibling
despite full-class claim"; `pr-00196 b B1`: the V14 pin family one file
short). Diagnostic messages that ENUMERATE causes ("non-numeric or
leading-zero …") are sweep sites of the same rank as a doc claiming the
invariant: a fix that adds a rejection/skip/failure cause sweeps every
message that enumerates causes, not just the code and the docs. The sweep
claim itself is a claim: twice this corpus a recorded sweep proved false
(`pr-00211 c W1`, `pr-00222 b W1` — the sweep missed the site the fix wave
itself had just added). Prose claims have sibling copies like code sites
do: when a wave updates, invalidates or copies a claim (comment, PR body,
commit message), grep the claim's distinctive text tree-wide (`#515 a Q1`
MED — the write-path claim corrected at one of two sites, the shipped
copy kept asserting the opposite of the code 115 lines below it); and when
a claim asserts a host/interpreter mechanism the wave's own tooling can
measure in one probe, measure instead of copying (`#521 a S1` — a
PYTHONUTF8 mechanism claim copied from a harness comment, disproven on
the very host it names).

A correction's sweep key is the claim's MEANING, not its literal
token: a claim's substance — a notice's lifetime, a state machine's
bounds — lives in many wordings, so a claim-correction fix lists the
old claim's substance first and checks every NEW sentence of the fix
against the code's actual behavior. The distinctive-text tree-wide
grep above stays the necessary first leg — alone it is the known
false-clean: PR #706's "one-time migration" correction swept the
claim's wording tree-wide (the old wording fully gone, the remaining
bare `one-time` hits unrelated contexts) while the fix's own comment
re-asserted the same false lifetime as "until a refresh ran" — round
b B1, fix-induced, #708. Output-string sweeps carry a key
discipline of their own: a message held in a VARIABLE that later
flows into a `ui_*` call or a note field is a sweep site of the same
rank as the call site — the rider's `ui_*` call-site grep read clean
while the DET_NOTE twins (doctor-core.sh) held the `#NNN` strings in
variables two `ui_*` lines away (PR #710 a A2, #714).

### L3 — Claim audit per wave
*Class: `claim-drift` — rank 1 by count in BOTH runs (77 and 89 findings;
7 MED/HIGH in the current corpus).*

Every behavior claim the wave touches — comment blocks, hint/message
strings, doc sentences — either **carries a pin** or is **deleted/weakened**.
Claims age outside diffs, so diff-scope reviews never catch their drift ("never
abort" `0.0.45c C1`, "race-free" `0.0.45d W1`, "31 suites" for 27
`0.0.39d D1`, "swept ×4" unproven by the wave's own matrix `pr-00196 c C10`,
gate lines that do not reproduce `pr-00202 d W1`). History narratives are
the prose shape of this class: a resolution narrative about what shifted
what is a claim like a SHA citation — verify each hop at its ref before
writing it, and date line anchors by MEASURING at the named commit
(`git show <ref>:<file> | grep -n`), never by restating an earlier review's
numbers (those describe a different tree by definition). Guard comments
narrating the OLD failure mode are this class too: execute the old shape
once with the realistic trigger (one dead dir, one unreadable file) and
describe the mode that actually occurs — total vs partial death are
different claims (`#516 a B3`, a differential claim refuted by its own
log; `#520 a B2+B3`, "empty list" wording overstated a partial-list
death that stayed green over missing coverage). Review-history claims
are the invisible variant: sabotage proofs, round dispositions and
B-axis executed proofs never enter git history by design (AGENTS.md
Testing), so the prose itself must carry the citation — PR + round +
finding ID — or every fresh reader hits a `git log -S` dead end
(pr-00537 round a A2's sandbox-policy comment read `unverified` until
main resolved it at PR #520 a B1; the carried-ref shape is fix commit
ad93f5cf). Issue-sourced claims are the inheritance arm: a wave that
ships an issue's mechanism claim verbatim in commit/PR/test text
inherits an UNVERIFIED claim as if audited — issue #594's own
"false green" analysis text was the error source, caught in flight by
pr-00621 round a Q2 (#626). For the shipping wave, an issue's
mechanism claims are claim-audit objects like any other: verify, do
not inherit (the docs-loop's re-probe duty for mechanism claims is
the rule-text sibling). The issue's own QUOTATION MARKS are the
arm's deepest channel (2026-11-20, PR #685 round a A2 plus the
fix-wave sweep sibling, #688): a reflection issue compresses and
re-wraps its sources, so quotation marks in an issue body are not
evidence — a wave re-quoting an issue's quoted strings in rule
text, metas or PR bodies verifies each at the PRIMARY source
(shipped bytes, test files, the PR timeline) before re-quoting, or
paraphrases without quotes; the compressed-header channel rides the
same arm (an item header's finding-ID parenthetical can disagree
with its own narrative three sentences later — derive citations
from the narrative and the PR timeline, never the header shape).
Subagent research summaries are the same
arm's second carrier (2026-11-18, PR #642): a delegated researcher's
external-tool claims read authoritative enough to skip the audit —
re-measure every claim against the primary source (the local clone
where one exists) before it enters shipped comments, docs or
records; the wave's shipped comment went in only after re-measuring
every claim at the local clone, and the pre-verification draft's
hedge was exactly the unaudited remainder.

Prose the wave NEWLY WRITES is an audit surface of the same rank as
the sites it corrects: verification of the named claim never extends
to the adjacent sentences around it — every factual assertion in
ADDED or REWRITTEN text (provenance, "who writes this file", version
eras, SHAs, counts) carries its own primary-source lookup, and the
lookup performed for the corrected claim never covers it (PR #711
round a Q1 MED: the corrected opt-in sentence's "agent-authored file
by definition" half was the session's own inference, refuted by the
installer's own shapes — it writes the default global config itself,
preserves user-authored ones (#372 I6), and names the file
"agent-replaceable after any completed install"; #712).
Review-finding prose is the same arm's carrier beside issue bodies
and research summaries: a CONFIRMED verdict covers the finding's
MECHANISM, never the incidental factual tokens of its prose — fix
text that re-quotes a finding's numbers, eras or names re-measures
each at the primary source before it lands (PR #711 round b B1 LOW:
the re-quoted "0.0.36-era" stamp was 0.0.11–0.0.14 by `git log -S`,
one lookup ahead of the fix commit would have pre-empted the round;
#712).

### L4 — Pins must discriminate, and sit before the summary gate
*Class: `test-vacuous` — run 1: 37 findings; run 2: 45 findings, 4 MED/HIGH,
rank 2 (tests remain the least-verified code: `tests-unit` is hotspot #1 in
both corpora).*

Sabotage-verify (agent/gates.md) covers green-when-broken — keep it for
every pin, including pins for wave mechanisms themselves — and run it only
against secured work, re-checked before EVERY cycle (PR #441 round b D1
lost a fix in the SECOND cycle): the restore resets to the index and wipes
unstaged edits, and the post-restore check greps the construct the fix
introduced, never rc alone — rc 0 holds for the pre- and post-fix version
both, the wipe is invisible to rc by construction (rule sharpened
2026-11-10 in AGENTS.md Testing; restated in
[review-concept.md](review-concept.md) "Verification duty"). A mid-cycle quick
fix in the sabotaged file itself is secured by the unconditional
pre-restore copy — the 2026-11-16 recurrence (PR #568 round c Z3,
same-file wipe) closed 2026-11-18 as #577 option 2.a (AGENTS.md
Testing). Two more shapes to
check: (a) the pin block sits **before** the suite's summary exit gate, or
its FAIL cannot fail the suite (`0.0.44c C1`, fail-but-green; confirmed at
scale by `pr-00211 b W13` / `c W5`: an `set -e` abort mid-suite skips every
later pin and the suite still tallies); (b) environment-dependent pins are
marked as such (vacuous on CI where no kit is deployed, `0.0.46a F2`). A
sabotage pin that discriminates through the WRONG mechanism (rc-2
fallthrough instead of the claimed blind probe, `pr-00198 a W3`) is
vacuous too — the pin must fail for the reason it exists. And an arm's
grep phrase must be leg-specific: it occurs in exactly ONE guard
message of that producer — a phrase another guard message also carries
reroutes the death through the wrong leg and the arm still passes
(`#520 a B1`: a one-token readability change rerouted a death through
the empty-set guard undetected; the discriminating phrase shape
existed in the same wave). And a guard pin makes the guard's REMOVAL
change the observable outcome — the failure path executes because of
the construct, never because of environment luck: the first n10j arm
stayed green with the dot-dot guard deleted (`../../etc/passwd`
failed `-f` anyway — /tmp/etc/passwd happens not to exist) until the
arm planted the reachable marker the guard exists to reject (PR #564
round b D1, fixed in 86850e0b). Fixture shape is pin shape, twice
over (November 2026): an assertion must match the producer's EXACT
output shape — `stat -c %a` prints minimal digits, so once the
baseline's dirs have passed, sticky modes are [1357]??? (setgid and
setuid ride along on the sticky bit), never `1*`; a count-pin over
mktemp-recorded logs matches stem + the exact mktemp chars + suffix,
never a trailing-char shape: a pattern matching bare names ending in
one specific char flakes at 1−(61/62)^N per run — N recorded names,
62-char mktemp alphabet (PR #655 round e, ~6%/run at N=4, #666; NOT
the `.*suffix$` attribution first drafted here — a dot-led pattern
matches any middle and never flakes on random chars, pr-00668 a Q3).
And a probe fixture must contain the construct it claims
before a verdict derives from its output: `$(printf '\n')` is EMPTY
(POSIX strips trailing newlines from command substitution), so the
intuitive embedded-newline operand silently builds the wrong fixture
— its plausible-looking output can flip a verdict to REFUTED. Build
embedded newlines via a variable (`NL=$(printf '\nX'); NL=${NL%X}`)
and verify the fixture itself with `od -c`/`cat -A` before reading
its output (PR #657 round a S3, #659).
An environment-dependent RED that appears while a non-default
environment (TMPDIR, PATH, GIT_CONFIG_*) is active on the chain is
re-derived once under the DEFAULT environment before any external
attribution — the differential probe must hold the mitigation
CONSTANT, and a scratch-worktree re-run inherits the exported
TMPDIR, so the clean-HEAD leg re-applies the same confound and
confirms nothing (pr-00746, 2026-11-22: a long private TMPDIR
crossed the pty draw width and truncation ate the very substring
the pin grepped — mechanism and pin in #745 — and the wrong
environmental attribution survived both a clean-HEAD worktree run
and a manual repro that sat on the truncation boundary; issue #749
incident 1).

### L5 — Root-operand inventory check
*Classes: `perm-model` + `race-toctou` — run 1: 53 findings, 23 MED/HIGH,
most HIGHs of any class; run 2: 9 findings, of which the corpus's ONLY HIGH
— and it is this class's own `0.0.39h F2` shape again (`pr-00211 a F1`).*

Before any new root operation on agent-writable (shared) trees, walk the
inventory questions — and when touching an existing site, check it still
passes. The walk's scope includes every dereferencing act the wave's own
diff ADDS to a touched site: "the finding's site" is not the boundary —
a fix's new chown/chgrp/mv acts re-open the class the fix closes (PR
#606: round a's S1 fix passed its gates, round b found the M3 fix's
restore acts unpaired, B1). Pair each new act with its
immediately-preceding check; enumerating the acts (awk, stat, chmod,
chown, chgrp, mv, rm) against their checks is the shape that finally
found nothing left:

1. `[ -L ]` on **every** path component (gates that check only the final
   component are bypassed via parents — `0.0.39h F2`, reopened by
   `0.0.44a V2`, and AGAIN by `pr-00211 a F1` HIGH: the group-baseline
   recheck gated the leaf only, a parent-dir symlink swap inside the
   scan→act window redirects root chgrp/chmod outside the tree; trailing
   slashes defeat lexical gates — `0.0.43a F16`).
2. Re-check the operand **immediately before** acting (scan-then-act
   windows: `0.0.45c S4/S5`).
3. **chmod before chown** on recursive walks (the walk order decides who
   can plant what — `0.0.45e W1`).

The run-2 HIGH was found by the staged release full pass, not by the wave
or micro passes over the same code — diff scope does not surface this
class's ceiling (keep the snapshot-scope-pass rule below).

### L6 — Fix waves are first-class code
*Class: `fix-regression` — run 1: 19 findings, 11 MED/HIGH, 20 % of all
findings fix-induced; run 2: 9 findings, 2 MED/HIGH, fix-induced share
halved to 9.3 %. The discipline measurably works; the class remains.*

Every fix wave gets its low-tier re-review before the PR merges
(binding since 0.0.42 — keep it; the birth-PR exists before round a,
and re-reviews run as rounds on the PR timeline — "The PR-native
loop"), and fixes bring **their own pins**: "the wave's own mechanisms
unpinned" was repeatedly its own finding (`0.0.44d F4`). A fix to a
root/symlink class also re-runs the L5 inventory check. The stop rule
agrees since 2026-10-11 ([review-concept.md](review-concept.md),
revised from the 0.0.46a→0.0.46b chain): a round whose fixes touch code —
LOW fixes included, the 0.0.46b W1 MED arrived through exactly those —
owes its low-tier re-review; only comment/docs/disposition-only rounds
close the loop without one. And the pin discriminates the FIX's own
mechanism, not only the finding's behavior — the negative arm of a
new guard, the registration calls of new tracking, the failure path
of a new degradation: PR #655 shipped the construct and pinned it one
round later three times in one loop (rounds b–e, every gap found by a
reviewer, none by the wave — #666, 2026-11-19). Cheapest form while
writing the fix: list the constructs and ask per construct "which pin
reddens if exactly THIS is deleted?"

### L7 — New scripts start from the skeleton
*Class: `shell-semantics` — run 1: 46 findings, 14 MED/HIGH; run 2: 7
findings, 1 MED/HIGH. Scaffolding-era forms stay structurally fixed; the
skeleton is doing its job.*

New shell files start from the house skeleton: `set -euo pipefail`, guarded
empty-match greps (`grep … || true` where empty output is rc 1), `IFS= read
-r` for TSV/line reads, no bare `cd` under `set -e`, full quoting pass.
(Candidate for a skeleton block in [conventions.md](conventions.md).)

## Keep doing — with era-marked evidence

- **Same-PR docs** (`docs-policy` 25 → 0 in 0.0.46; **6 returned** in
  0.0.47–0.0.55 — the rule holds, the vigilance never ends)
- **Docs deltas may be deliberate policy** (`pr-00263 b B1`/`b B4`/
  `c C7`, all retracted 2026-10-25): a removed or shortened docs
  passage is not automatically a regression — read the issue and PR
  that carried the removal before restoring anything (#252/#256 had
  recorded the ultra-legacy removal as intended; the external
  reviewers, on a sparse checkout without that history, flagged it).
  One-sentence corrections of remaining falsehoods stay correct;
  bulk restores of removed text are not.
- **Gate runs: one unbroken `&&` chain ending in the commit**
  (`wiring-gate` mechanics; two live 2026-10-25 instances: a piped
  gate masked a red ratchet into a commit, a `;` after a gate did the
  same) — no `| tail`, no `;`, `set -o pipefail` when wrapping; and
  resolution rows checked ≤ 120 BEFORE the commit, with the
  `<SHA>`-fill's +2 bytes per row budgeted (issue #237; the rule
  itself lives in the review README — agent/gates.md owns the
  chain mechanics, including its post-rebase exception where the
  chain ends in `make test` after the manifest's own commit); and
  a diff touching `files/` owes `make sums`
  inside the chain — the regenerated repo-root `SHA256SUMS` is
  committed with the wave, `make test`'s freshness pin reddens on a
  stale manifest (issue #478)
- **Comment-strip riders on source-counting pins** (#261, PR #284) —
  a `grep -c` count pin over shipped source without the rider is
  pass-green on commented-out code. Census: 39 strip sites across 14
  suites; 34 are this wave's (10 of those were sweep finds beyond the
  issue list), the other 5 are non-sweep strips — the 4 #244-era
  test-install-args riders plus the wave-created #261 pin's sed-bearing
  leg (that pin's BARE leg stays un-ridden by design, per the
  conventions carve-out). Census-grep note: 2 of the 39 sites live in
  escaped-dollar form (`sed 's/^[[:space:]]*#.*\$//'`), invisible to
  the unescaped literal. The rider convention lives in
  [conventions.md](conventions.md) "Source-counting pins"; known
  residual classes: awk-pattern order pins, raw negative `grep -q`
  legs — issue #285 carries the inventory
- **Sabotage-verify per pin** (the ONLY reliable discriminator we have;
  `test-vacuous` reappeared at scale in run 2 — partly corpus composition,
  partly real: the fail-but-green shape (a) above) — and only against
  secured work, re-checked per cycle: the 2026-10 AGENTS.md rule alone
  did not stop the loss — PR #441 round b D1 (2026-11-10) pushed a pin
  without its recursion-break marker after a second cycle's restore
  wiped the unstaged marker edit, and the rc-based restore check could
  not see it (roughly every third session, 2026-11 maintainer estimate);
  sharpened 2026-11-10 (per-cycle invariant + content-based restore
  verification + amend indicator, AGENTS.md Testing), restated in
  [review-concept.md](review-concept.md) "Verification duty" and L4
- **Pre-release snapshot-scope pass via opencode v2's built-in
  `/review`** (fresh
  external session, staged fan-out) — still the only reliable source of
  `perm-model`/`race-toctou` HIGHs: internal v1 2 MED vs external 2 HIGH +
  6 MED on the same tree (`0.0.42d`/`0.0.42e`); opencode 1.18.34 zero
  MED/HIGH vs 2.0.22 eight on the same tree one day apart (`0.0.45b`/
  `0.0.45c`); and run 2's only HIGH (`pr-00211 a F1`, an L5 core shape)
  came from the staged 10-subagent full pass that the wave passes had
  missed
- **Round comment posted before the first fix commit** — the PR-native
  hard seam (review-concept, "The PR-native loop": the comment posts
  BEFORE any fix starts; it replaced the retired snapshot-with-first-
  fix mechanic, #296) — chain convergence: feature/fix waves close in
  1–3 rounds; release full passes pay more (pr-00211: 7 snapshots,
  corpus era)
- **Wrapped-string byte-identity is execution-proven, never
  gate-inferred** (#300 tier 1, 2026-10-31): the broken single-quote
  wrap forms — 4-indent spaced-word continuations (fmt-stable at top
  level — the stable continuation indent follows the command's
  nesting; the col-0 spelling is fmt-red), sq splices with literal
  backslashes — pass `make lint`, the line-length ratchet AND the join
  guard while changing the executed bytes; the e2e rc greps survive
  too (the path substrings stay intact). Only executing old vs new and
  `cmp`-ing the output discriminated. Idiom matrix:
  [conventions.md](conventions.md#formatting-shfmt) "Formatting (shfmt)".
- **Trust the file, not your memory of the edit** (2026-11-15, two
  sessions) — re-grep the construct before building a sabotage patch:
  shfmt had reformatted the anchor text the writer remembered typing
  (`#519`, first-cycle assert-fail; a live instance of the PR #441
  wipe class AGENTS.md names); and after a non-trivial edit to a
  Python file, parse and read before trusting the edit rc
  (`python3 -c "import ast; ast.parse(open(<f>).read())"` plus the
  diff hunk — a lenient edit match mis-indented 8-vs-12 spaces in
  tui-register.py and 12 test rows caught it immediately, `#513`
  series).
- **Trust the recorded result, not reconstructed order** (2026-11-15;
  the command-RESULTS arm of the family above, whose file-edit arm is
  "trust the file, not your memory of the edit") — numbers returned by
  parallel tracker calls (`gh issue create`) land next to their
  subject AT creation time, read from each call's own output;
  reconstructing the mapping afterward from assumed launch sequence
  crossed the work-order mapping — all three of #541/#542/#543 vs the
  PR-body table (PR #544 round a A3 MED). The timeline arm
  (2026-11-21, PR #716 round a C3): per-round statistics — counts,
  severities, findings-by-round — derive from each round comment's
  OWN findings table or headline count line, never from greps over
  the merged comment stream; the unit is the comment, not the
  stream, and a merged-stream extraction smeared one PR's
  closing-summary work-order lines into another round's census
  (corrected only in the fix wave, across four surfaces).
- **No history-dependent test pins — CI checkouts are depth-1**
  (2026-11-17, pr-00599): test code that resolves historical git
  objects at runtime (`git show <historical-sha>:<path>`) passes every
  local gate on a full clone and breaks every CI lane deterministically
  — actions/checkout defaults to depth-1, the SHAs are absent, the
  unit lane dies loud on its fallback while an e2e plant pipeline
  ending in `tr` planted an empty file silently (round b S1, HIGH).
  Sanctioned shapes: committed fixtures
  (`tests/fixtures/opencode-deny-all-pre570.jsonc`, commit 5ec21c02)
  or a weighed `fetch-depth: 0` (rejected there for cost); sweep
  marker: "history-dependent pin".
- **Walk process proposals through the incident's states, not beside
  them** (2026-11-18, #577): a process-sketch option is ranked only
  after replaying the incident's exact state sequence under it — the
  scratch-worktree-as-default sketch looked strictly safer until the
  worst-case walkthrough showed it relocates the wipe instead of
  preventing it (sabotage target and quick fix share ONE file;
  maintainer counter-example, #577 option-2 comment), and it was
  demoted in the option paper. The code-side sibling (review through
  the failure mode) lives in review-concept.md; this is the
  proposal-side arm: BEFORE ranking or recommending, replay the
  incident under the sketch (#620).
- **A surprising probe result is a harness suspect before it is a
  semantics finding** (2026-11-18, #623 item 1): a probe pair read
  "bash -nt DETECTED / dash missed" — one interpretation step from a
  false shell-semantics rule — and the clean re-probe (variables set
  INSIDE the shell under test, PATH never stripped of the
  interpreter) showed dash detects 50 ms write gaps fine: the
  single-quoted test expression had run with its variable unexported,
  so dash compared a nonexistent `/c` against `/m3`; a sibling bug in
  the same session hard-overrode PATH until `sh` itself vanished. The
  near-miss is the inverse of codified-unprobed (#578 §3): probed
  with a broken probe whose output CONFIRMED the expected story — the
  surprise direction matched a plausible prior, so the harness went
  unexamined. A surprising result re-runs as a minimal self-contained
  script before it is believed, and the corrected re-probe lands in
  the wave's provenance (the docs-loop's probe-before-codify duty,
  surprise arm).
- **oldString anchors: verify the anchor bytes, never reconstruct
  from the numbered read view** (2026-11-18, PR #634 wave; sharpened
  2026-11-19, PR #668 wave — the same trust-the-file family as the
  two 2026-11-15 bullets above in this list) — an edit-tool oldString
  is never reconstructed from the read view alone, whatever the
  character class: the numbered read's `NNN: ` prefix adjoins the content's
  indent, so leading-whitespace counts are not visually recoverable
  (a 3-space read that was 2-space, a 2-space read that was
  flush-left), and a wrap point reconstructed from memory puts a
  phrase believed at line start mid-line. On any miss — and before
  the first attempt on an indented or wrapped target — verify the
  anchor bytes (`sed -n Np <file> | od -c`, or anchor on
  byte-verified unique text) instead of re-aiming longer
  reconstructions from memory. Three failed edits in one wave, all on
  plain-ASCII anchor lines, all recovered by the byte check (PR
  #668, #669); the 2026-11-18 failure pair's typographic-character
  theory (em-dash, apostrophe — #636) was one historical suspicion,
  not the trigger. When the anchor line does carry typographic
  characters, the shortest special-char-free anchor remains the
  cheapest recovery.
- **Indent-anchored extractions re-check after re-nesting**
  (2026-11-21, PR #710 F2, #714) — a test pin that extracts a
  construct by indent-anchored sed/awk ranges breaks when the
  construct moves one nesting level out, in two shapes — one loud,
  one silent: both anchors over-specific and the extraction comes
  back EMPTY — the pin drives nothing and the suite reds loud at
  rc 127, one gate cycle paid (test-kit-cli.sh's fs-baseline stub
  after #696's 12→8 re-nest; the fixed 8-space form sits at the sed
  call today) — or an anchored END pattern keeps matching past the
  construct and captures the file TAIL silently, all pins green (the
  pr-00381 comment block in test-ddev-as-opencode.sh documents that
  sibling; its awk end pattern is deliberately unanchored since).
  After re-nesting shipped code, sweep the test tree for
  indent-anchored sed/awk extractions over the touched files before
  the gate run.
- **Consumer sweeps key on the data the consumers assert, not the
  producer's message names** (2026-11-19, PR #680 round a B1 HIGH) —
  a wave that changes a producer's output shape sweeps the consumers
  by what THEY pin: path literals, row prefixes, exact bytes; a sweep
  grepping the producer's message or success-label names concludes
  "no coupling" while a sibling suite holds the pin (the #662 plan
  rows: the consumer suite pinned the dry-run rows by the bare
  `/usr/local/bin/opencode` and `/usr/local/bin/opk` path literals,
  end-anchored — the message-name sweep
  found nothing). And "local make test green" is evidence only for
  hosts shaped like the local one — the dev host had the kit
  installed, so both rows printed and the pins held; the bare CI
  runner redden them (environment-dependent suites are L4's marking
  duty, `0.0.46a F2`). The fidelity twin — the coupling hides in a
  sibling unit suite, not e2e — is told in
  [test-fidelity.md](test-fidelity.md) §2.

## When a rule fails

If a re-run of the meta-analysis shows a class recurring **after** its rule
landed, the rule is not enforced hard enough — escalate: sharpen the
checklist wording here, turn it into a gate/test that fails the suite, or —
when it is the demand itself the class keeps recurring against — change the
process shape so the safe path is also the cheap one. All three escalations
have live examples: L2's wording was sharpened twice after the class
returned (#214 5 above), L1/L4's pin-placement shape became a
suite-mechanics rule (pins before the summary gate), and the sabotage-vs-
uncommitted-tree class gained the pre-restore copy as a sanctioned securing
move after the class survived the 2026-10 rule and its 2026-11-10
sharpening (#577 option 2.a). The sabotage-vs-
uncommitted-tree incident (2026-10) never entered a review snapshot — it
lived as an AGENTS.md Testing rule alone until the class recurred anyway
(2026-11; roughly every third session, maintainer estimate). The
recurrence DID enter a round comment (PR #441 round b, D1 HIGH — the
fix-wave re-review caught what the wave's own rc-based self-checks
could not see)
and on 2026-11-10 took this section's first escalation path: wording
sharpened (AGENTS.md Testing — per-cycle invariant, content-based
restore verification, amend indicator) and restated in
[review-concept.md](review-concept.md) "Verification duty" plus L4 and
Keep doing here. The class then recurred a SECOND time after that
sharpening (2026-11-16, PR #568 round c Z3 — a mid-cycle quick fix in
the sabotaged file, a state where commit and stash cannot secure), and
the 2026-11-18 escalation changed the process shape instead of
sharpening the demand again: a sanctioned securing move (the
unconditional pre-restore copy) so the safe path is also the cheap one
(#577 option 2.a, agent/gates.md). Incidents outside the round
comments belong in AGENTS.md — restated in the pages the working
session reads, not one page alone.

## Era & next-run notes (issue #175 pre-pass, closed 2026-10-22)

- The restructure-wave candidates are **not** new classes: language
  violations (1 finding, `pr-00211 a F21`) are covered by the all-English
  rule (AGENTS.md, ## Rules); the
  exec-bit/ratchet failures are `wiring-gate` (6, 2 MED — incl. the
  line-length ratchet RED at a committed HEAD, `pr-00208 b W1`); two
  more ratchet-commission instances went live on 2026-10-25 outside
  snapshots (piped gate, `;` separator — the chain-mechanics rule
  lives in agent/gates.md, the checklist pointer in "Keep doing");
  sabotage-vs-uncommitted-tree produced zero corpus findings (agent/gates.md
  owns it; its 2026-11 recurrence — PR #441 round b D1 — is
  post-corpus: rule sharpened 2026-11-10, per-cycle invariant +
  content-based restore verification, restated in review-concept.md
  "Verification duty" and L4/Keep doing above).
- Numbers the NEXT run should collect: a snapshot-scope pass INSIDE the
  corpus (perm-model HIGH detection is pass-scope-bound); the `internal`
  area trend (59 findings — project memory became a review surface);
  `wiring-gate` recurrence (ratchet-red-at-HEAD shape); whether the
  fix-induced share stays ≤ 10 %.
