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
discipline cut that to 9.3 % in the second). Classes collapsed only after
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
itself had just added).

### L3 — Claim audit per wave
*Class: `claim-drift` — rank 1 by count in BOTH runs (77 and 89 findings;
7 MED/HIGH in the current corpus).*

Every behavior claim the wave touches — comment blocks, hint/message
strings, doc sentences — either **carries a pin** or is **deleted/weakened**.
Claims age outside diffs, so wave reviews never catch their drift ("never
abort" `0.0.45c C1`, "race-free" `0.0.45d W1`, "31 suites" for 27
`0.0.39d D1`, "swept ×4" unproven by the wave's own matrix `pr-00196 c C10`,
gate lines that do not reproduce `pr-00202 d W1`). History narratives are
the prose shape of this class: a resolution narrative about what shifted
what is a claim like a SHA citation — verify each hop at its ref before
writing it, and date line anchors by MEASURING at the named commit
(`git show <ref>:<file> | grep -n`), never by restating an earlier review's
numbers (those describe a different tree by definition).

### L4 — Pins must discriminate, and sit before the summary gate
*Class: `test-vacuous` — run 1: 37 findings; run 2: 45 findings, 4 MED/HIGH,
rank 2 (tests remain the least-verified code: `tests-unit` is hotspot #1 in
both corpora).*

Sabotage-verify (AGENTS.md, Testing) covers green-when-broken — keep it for
every pin, including pins for wave mechanisms themselves. Two more shapes to
check: (a) the pin block sits **before** the suite's summary exit gate, or
its FAIL cannot fail the suite (`0.0.44c C1`, fail-but-green; confirmed at
scale by `pr-00211 b W13` / `c W5`: an `set -e` abort mid-suite skips every
later pin and the suite still tallies); (b) environment-dependent pins are
marked as such (vacuous on CI where no kit is deployed, `0.0.46a F2`). A
sabotage pin that discriminates through the WRONG mechanism (rc-2
fallthrough instead of the claimed blind probe, `pr-00198 a W3`) is
vacuous too — the pin must fail for the reason it exists.

### L5 — Root-operand inventory check
*Classes: `perm-model` + `race-toctou` — run 1: 53 findings, 23 MED/HIGH,
most HIGHs of any class; run 2: 9 findings, of which the corpus's ONLY HIGH
— and it is this class's own `0.0.39h F2` shape again (`pr-00211 a F1`).*

Before any new root operation on agent-writable (shared) trees, walk the
inventory questions — and when touching an existing site, check it still
passes:

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
or micro passes over the same code — wave scope does not surface this
class's ceiling (keep the full-pass rule below).

### L6 — Fix waves are first-class code
*Class: `fix-regression` — run 1: 19 findings, 11 MED/HIGH, 20 % of all
findings fix-induced; run 2: 9 findings, 2 MED/HIGH, fix-induced share
halved to 9.3 %. The discipline measurably works; the class remains.*

Every fix wave gets its micro-wave review before the PR (binding since 0.0.42
— keep it), and fixes bring **their own pins**: "the wave's own mechanisms
unpinned" was repeatedly its own finding (`0.0.44d F4`). A fix to a
root/symlink class also re-runs the L5 inventory check. The stop rule
agrees since 2026-10-11 ([review-concept.md](review-concept.md),
revised from the 0.0.46a→0.0.46b chain): a round whose fixes touch code —
LOW fixes included, the 0.0.46b W1 MED arrived through exactly those —
owes its micro-wave review; only comment/docs/disposition-only rounds
close the loop without one.

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
  itself lives in the review README — AGENTS.md Testing owns the
  chain mechanics)
- **Comment-strip riders on source-counting pins** (#261, PR #284: 34
  of 39 strip sites across 14 suites — the 5 pre-#261 strips are the
  #244-era test-install-args riders plus the #261 pin's own fixture
  leg; census note: 2 of the 39 live in escaped-dollar form
  (`sed 's/^[[:space:]]*#.*\$//'`) and are invisible to the unescaped
  literal; 10 of the 34 were sweep finds beyond the issue list; the
  rider convention lives in
  [conventions.md](conventions.md) "Source-counting pins"; awk-pattern
  order pins and raw negative `grep -q` legs are the known residual,
  issue #285 carries the inventory) — a `grep -c` count pin over
  shipped source without the rider is pass-green on commented-out code
- **Sabotage-verify per pin** (the ONLY reliable discriminator we have;
  `test-vacuous` reappeared at scale in run 2 — partly corpus composition,
  partly real: the fail-but-green shape (a) above)
- **Pre-release full pass via opencode v2's built-in `/review`** (fresh
  external session, staged fan-out) — still the only reliable source of
  `perm-model`/`race-toctou` HIGHs: internal v1 2 MED vs external 2 HIGH +
  6 MED on the same tree (`0.0.42d`/`0.0.42e`); opencode 1.18.34 zero
  MED/HIGH vs 2.0.22 eight on the same tree one day apart (`0.0.45b`/
  `0.0.45c`); and run 2's only HIGH (`pr-00211 a F1`, an L5 core shape)
  came from the staged 10-subagent full pass that the wave passes had
  missed
- **Snapshot with the first fix commit** — chain convergence: feature/fix
  waves close in 1–3 snapshots; release full passes pay more (pr-00211:
  7)

## When a rule fails

If a re-run of the meta-analysis shows a class recurring **after** its rule
landed, the rule is not enforced hard enough — escalate: sharpen the
checklist wording here, or turn it into a gate/test that fails the suite.
Both escalations have live examples: L2's wording was sharpened twice after
the class returned (#214 5 above), and L1/L4's pin-placement shape became a
suite-mechanics rule (pins before the summary gate). The sabotage-vs-
uncommitted-tree incident (2026-10) never entered a review snapshot — it
lives as an AGENTS.md Testing rule; incidents outside snapshots belong
there, not here.

## Era & next-run notes (issue #175 pre-pass, closed 2026-10-22)

- The restructure-wave candidates are **not** new classes: language
  violations (1 finding, `pr-00211 a F21`) are covered by the all-English
  rule (AGENTS.md, ## Rules); the
  exec-bit/ratchet failures are `wiring-gate` (6, 2 MED — incl. the
  line-length ratchet RED at a committed HEAD, `pr-00208 b W1`); two
  more ratchet-commission instances went live on 2026-10-25 outside
  snapshots (piped gate, `;` separator — the chain-mechanics rule
  lives in AGENTS.md Testing, the checklist pointer in "Keep doing");
  sabotage-vs-uncommitted-tree produced zero corpus findings (AGENTS.md
  Testing owns it).
- Numbers the NEXT run should collect: a release full pass INSIDE the
  corpus (perm-model HIGH detection is pass-scope-bound); the `internal`
  area trend (59 findings — project memory became a review surface);
  `wiring-gate` recurrence (ratchet-red-at-HEAD shape); whether the
  fix-induced share stays ≤ 10 %.
