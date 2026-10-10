# Review learnings — the per-wave checklist

> **Status: CURRENT (derived from the analysis run 2026-10-10, corpus 0.0.38–0.0.46).**
> This is the enforcement short-form — every rule here is backed by a recurring
> defect class measured across the review corpus. Evidence, chains and full
> tables: [README.md](README.md) · [statistics.md](statistics.md) ·
> [further-analyses.md](further-analyses.md). Agents get this page via
> [AGENTS.md](../../../AGENTS.md); reading the statistics is NOT required to
> apply the rules.

## Why these rules exist

The meta-analysis found the same error classes recurring with every new
feature — a new feature means a new instance of a known class at a new site,
not a new kind of mistake (`silent-failure` showed up in all 9 version groups;
the snapshots themselves cross-reference earlier findings as a "class" 45
times; 20 % of all findings were introduced by our own fix waves). Classes
collapsed to zero only after an **enforced process step** existed — naming a
class alone never stopped it. Each rule below is that step for its class.

## The rules (L1–L7)

### L1 — Fail-loud pins for new fail-soft spots
*Class: `silent-failure` — 62 findings, 13 MED/HIGH, all 9 version groups.*

Every new `|| true`, stderr redirect, or probe pipe in feature code gets a pin
that **executes the failure path** — a stub or `chmod 000` that forces the
error — and asserts the failure is observed (a skip/failed note), not silence.
The pin must observe the message the way production does: if a caller discards
stderr, a `2>&1` pin proves nothing (`0.0.46b W1` — "loud" was unreachable at
the named caller).

### L2 — Class sweep before "implemented"
*Class: `sibling-sweep` — 46 findings, 13 MED/HIGH; zero in 0.0.46 after this
discipline landed.*

A fix for a finding is only dispositioned *implemented* after sweeping **all
same-shape sibling sites**, and the resolution records the evidence: the grep
pattern used and the sites checked. "Fixed at the site the finding named" is
the definition of this defect class (`0.0.39h F1` HIGH: "missed sibling
despite full-class claim").

### L3 — Claim audit per wave
*Class: `claim-drift` — 77 findings, rank 1 by count, still nonzero in 0.0.46.*

Every behavior claim the wave touches — comment blocks, hint/message strings,
doc sentences — either **carries a pin** or is **deleted/weakened**. Claims
age outside diffs, so wave reviews never catch their drift ("never abort"
`0.0.45c C1`, "race-free" `0.0.45d W1`, "31 suites" for 27 `0.0.39d D1`).

### L4 — Pins must discriminate, and sit before the summary gate
*Class: `test-vacuous` — 37 findings; named "the 0.0.42d class" three times.*

Sabotage-verify (AGENTS.md, Testing) covers green-when-broken — keep it for
every pin, including pins for wave mechanisms themselves. Two more shapes to
check: (a) the pin block sits **before** the suite's summary exit gate, or its
FAIL cannot fail the suite (`0.0.44c C1`, fail-but-green); (b) environment-
dependent pins are marked as such (vacuous on CI where no kit is deployed,
`0.0.46a F2`).

### L5 — Root-operand inventory check
*Classes: `perm-model` + `race-toctou` — 53 findings, 23 MED/HIGH, most HIGHs
of any class.*

Before any new root operation on agent-writable (shared) trees, walk the
inventory questions — and when touching an existing site, check it still
passes:

1. `[ -L ]` on **every** path component (gates that check only the final
   component are bypassed via parents — `0.0.39h F2`; trailing slashes defeat
   lexical gates — `0.0.43a F16`, reopened by `0.0.44a V2`).
2. Re-check the operand **immediately before** acting (scan-then-act windows:
   `0.0.45c S4/S5`).
3. **chmod before chown** on recursive walks (the walk order decides who can
   plant what — `0.0.45e W1`).

### L6 — Fix waves are first-class code
*Class: `fix-regression` — 19 findings, 11 MED/HIGH; 20 % of all findings are
fix-induced.*

Every fix wave gets its micro-wave review before the PR (binding since 0.0.42
— keep it), and fixes bring **their own pins**: "the wave's own mechanisms
unpinned" was repeatedly its own finding (`0.0.44d F4`). A fix to a
root/symlink class also re-runs the L5 inventory check.

### L7 — New scripts start from the skeleton
*Class: `shell-semantics` — 46 findings; scaffolding-era forms are
structurally fixed, individual forms remain.*

New shell files start from the house skeleton: `set -euo pipefail`, guarded
empty-match greps (`grep … || true` where empty output is rc 1), `IFS= read -r`
for TSV/line reads, no bare `cd` under `set -e`, full quoting pass. (Candidate
for a skeleton block in [conventions.md](../conventions.md).)

## Keep doing (trend-proven)

These already collapsed their classes — they stay binding:

- **Same-PR docs** (`docs-policy` 25 → 0)
- **Sabotage-verify per pin** (`test-vacuous` 12 → 2)
- **Class-sweep discipline** (`sibling-sweep` → 0 in 0.0.46)
- **External pre-release full review** — the only reliable source of
  `perm-model` HIGHs (internal 2 MED vs external 2 HIGH + 6 MED on the same
  tree, `0.0.42d`/`0.0.42e`)
- **Snapshot with the first fix commit** — chain convergence fell from 16
  snapshots (0.0.39) to 3 (0.0.46)

## When a rule fails

If a re-run of the meta-analysis shows a class recurring **after** its rule
landed (e.g. an L1-pattern `silent-failure` in a version > 0.0.46), the rule
is not enforced hard enough — escalate: sharpen the checklist wording here,
or turn it into a gate/test that fails the suite.
