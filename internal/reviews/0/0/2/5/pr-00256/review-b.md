<!-- review-meta
ID: pr-00256
Snapshot: b
Subject: micro pass — the four claim-drift pins in tests/unit/test-docs.sh from the a-wave fix (docs-side changes excluded by commission)
Scope: wave
Base: 0.0.56 @ f984b13
Diff: f984b13..d01c7eb -- tests/unit/test-docs.sh
Date: 2026-10-25
Reviewer: GLM-5.3 house session (opk-review-pass skill), single-agent pass — no reviewer subagents (USER instruction)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — micro pass on the a-wave fix's test-docs.sh pins (pr-00256)

Round b over the test-file half of the fix commit d01c7eb (base f984b13 =
snapshot a). Material: the four new pins in `tests/unit/test-docs.sh`
(+49 lines: #256 a W1, W2, W3, W5). The docs-side changes of d01c7eb and
the resolution/INDEX bytes are **out of scope by commission** (USER:
"Micro Review b, nur focus auf test-docs.sh"). Scope keyword **micro**
(diff ≈ 49 lines, under the ~50-line threshold), executed as a solo
main-session pass — 0 reviewer subagents, USER instruction (precedent:
pr-00243 g).

**Result: 2 findings, both LOW** — no MED/HIGH, no retractments. Both are
pin-quality defects introduced by the fix wave itself (fix-induced): the
W5 pin's "unmapped-letter guard" is unreachable dead code, and the W1 pin
is one-directional (the reverse direction the same suite added for its
F36 sibling as #211 b W30). Fail-loud holds in every sabotaged direction
— neither finding creates a green-on-red path. The suite is green on the
clean tree; all four pins sit before the summary gate; naming and
sandbox discipline match the suite's conventions.

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| B1 | LOW | W5 pin's "unmapped-letter guard" is unreachable — the sed captures only `[mcs]`, so a default letter outside the vocabulary misfires the *anchor-drift* tripwire instead and the guard branch can never execute | fix-induced |
| B2 | LOW | W1 pin is one-directional — docs listing a root-file type the code matcher lacks (the addition direction of the original W1 class) stays green; the same suite added this reverse for F36 as #211 b W30 | fix-induced |

## Details

### B1 — LOW: the W5 "unmapped-letter guard" is dead code

`tests/unit/test-docs.sh:226` extracts the menu default with a capture
class of exactly the mapped letters:

```sh
_w5_def="$(sed -n 's/.*ui_menu "Bring the developer.s agent resources over?" "\([mcs]\)".*/\1/p' \
    "$REPO_ROOT/files/install.sh" | head -n 1)"
```

then maps all three possible values (:231-235) and guards the rest
(:236-238):

```sh
case "$_w5_def" in
    m) _w5_word="move" ;;
    c) _w5_word="copy" ;;
    s) _w5_word="skip" ;;
esac
if [ -n "$_w5_def" ] && [ -z "$_w5_word" ]; then
    echo "FAIL getting-started.md: unmapped agent-resources menu default '$_w5_def' (#256 a W5)" >> "$TMP"
fi
```

The sed can only ever capture `m`, `c`, or `s` — whenever `_w5_def` is
non-empty, the case maps it, so `[ -n "$_w5_def" ] && [ -z "$_w5_word" ]`
is unsatisfiable. The scenario the guard announces (a default letter
outside the vocabulary) actually breaks the sed *match* instead:
`_w5_def` comes back empty and the **anchor-drift** tripwire (:227-229)
fires with "extraction empty — anchor drift?" — red, but misattributed
(a vocabulary drift reported as an anchor drift). Verified both
statically and by simulation: default `"s"` → `"x"` in a /tmp copy of
install.sh → extraction empty, guard silent. Why LOW, not MED: every
drift direction still goes red (fail-loud intact); the defects are the
dead branch, the misleading failure attribution, and
[resolution.md:88](resolution.md) calling it an "unmapped-letter guard"
— a guard that cannot guard. Realistic trigger: a future fourth menu
option whose key is not m/c/s while the question text stays stable.
Likely fix shapes (next fix wave, not this round): widen the capture to
`\(.\)` so the case+guard discriminate, or drop the guard and correct
the comment plus the resolution wording.

### B2 — LOW: the W1 pin lacks the reverse direction (its own W30 class)

`tests/unit/test-docs.sh:205-208` iterates only the code side:

```sh
for _w1_t in codeigniter $_w1_types; do
    grep -qF "\`$_w1_t\`" "$_w1_doc" \
        || echo "FAIL ddev-integration.md: root-file type '$_w1_t' missing from the docs (#256 a W1)" >> "$TMP"
done
```

so the pin asserts code-types ⊆ docs-types. The other direction — docs
listing a root-file type the matcher does not know — stays green.
Simulated on a /tmp copy of ddev-integration.md with `` `laravel` ``
added to the root-file list: all three code types still found, pin
green. The wave-a W1 finding itself was docs-side drift (rename
`shopware6` → `shopware`), which this direction *does* catch (the code
type goes missing); the invisible shape is the addition direction. That
is exactly the class the same suite already learned: #211 b W30 added
the reverse direction to the F36 flag pin because "a documented `-y`
the parser rejected was invisible to it". Sibling sweep: no other unit
test pins docs root-file types against the matcher (grep over
tests/unit/ — only test-docs.sh touches this join). LOW: the current
tree is correct; the trigger is a future docs edit adding or restoring
a type value, which is the demonstrated error class of this corpus.
Fix shape: extract the docs page's backticked root-file types (the
"Root-file types" paragraph anchor) and require each to appear in the
extracted matcher set.

## Verification log (main session)

| # | Claim | Verified how | Verdict |
|---|---|---|---|
| 1 | Suite green on clean tree | `sh tests/unit/test-docs.sh` at a9de7c1 → "docs link check: OK" | HOLDS |
| 2 | W1 anchor live, single site | sed extraction over ddev-handover.sh → `shopware6\|symfony`; exactly one `codeigniter\|` arm line in the file (:466) | HOLDS |
| 3 | W5 anchor live, unique | sed extraction over install.sh → `s`; the ui_menu question text occurs once (grep -c = 1) | HOLDS |
| 4 | B1 guard unreachable | static: `[mcs]` capture + exhaustive case ⇒ guard unsatisfiable; dynamic: /tmp copy with default `"x"` → extraction empty (tripwire path), guard silent | HOLDS |
| 5 | B2 reverse invisible | /tmp copy of ddev-integration.md with `` `laravel` `` added → loop finds all three code types, no FAIL line | HOLDS |
| 6 | No sibling pin covers the docs↔matcher join | grep `shopware\|TOCTOU\|skipped security checks\|defaults to` over tests/unit/*.sh — W1/W2/W3/W5 pins exist only in test-docs.sh | HOLDS |
| 7 | Code-side matcher drift not invisible tree-wide | test-ddev-as-opencode.sh:593 (type shopware6 → 2755 handover, behavioral) and :603-604 (bootstrap-hint matcher string pinned) already guard the code side | HOLDS |
| 8 | Pins sit before the summary gate | all four blocks precede `if [ -s "$TMP" ]` (test-docs.sh:244) — the L-rule placement holds | HOLDS |
| 9 | Sandbox + conventions clean | pins write only to `$TMP` (mktemp, /tmp); `_w1_*`/`_w5_*` naming matches the `_f36_*`/`_cli_md` convention; every FAIL line names its finding (`#256 a W*`) | HOLDS |
| 10 | Fix-commit gates | resolution.md:150-155 records unit/line-length/lint/reviews gates green at d01c7eb; line-length re-run at this pass → OK (662 over 120, all at baseline) | HOLDS |

## Retracted/ghost findings

None. Two candidate findings were consciously recorded below instead of
flagged — both fail the realistic-trigger or house-pattern test:

- **W1 pins handover.sh only; ddev-terminal.sh:357/:400 unpinned** —
  the pin's comment states its scope honestly ("every root-file type
  ddev-handover.sh matches"), and the code side is behaviorally pinned
  elsewhere (verification row 7); a terminal-only drift is a code
  consistency issue with its own coverage, not a docs-pin green-on-red.
- **W2/W3 bare-phrase anchors can false-red on meaning-preserving
  rewording** — that is the house content-anchor pattern by design
  (resolution.md records the W3 wrap catch as witnessed live); fail-loud
  false positives are the accepted direction, not a defect.

## Carried forward

Nothing open from round a: all eleven dispositions (W1-W11) landed or
were accepted in the fix wave and its resolution. This round adds B1
and B2 as the only open items.

## Run provenance

- **Commission:** USER (maintainer), in-session — "Micro Review b, nur
  focus auf test-docs.sh (Die Docs Anpassungen ignorieren)". Scope
  micro; material narrowed to the test-file half of d01c7eb by the
  commission itself.
- **Pass shape:** solo main-session pass (GLM-5.3, strong tier) — 0
  reviewer subagents on USER instruction; the reporting and verification
  duty collapsed into one session (axis named under Calibration).
- **Host timestamps:** solo pass, section-budgeted; end stamp
  `2026-10-24T23:02:01Z` (git commit stamp corroborates); no subagent
  windows exist to normalize.
- **Mutation/sabotage windows:** none in the reviewed tree —
  `git status --porcelain` clean before and after; both sabotage
  simulations ran on copies under `/tmp/opencode/pr-00256-b/`, outside
  the tree; no readers existed during them (solo pass), so no
  bidirectional screening owed.
- **Environment:** checkout at `/var/www/opencode-permissions-kit`,
  branch `feature/docs-end-user-optimizations`, clean at a9de7c1
  (base f984b13, VERSION 0.0.56).

## Gates

Run before this snapshot commit (check-then-commit, RM-0117):

- `sh tests/unit/test-docs.sh` — PASS (pins green on the clean tree).
- `sh tests/unit/test-line-length.sh` — PASS (baseline held).
- `python3 scripts/gen-review-index.py` — INDEX regenerated.
- `sh tests/unit/test-reviews-lint.sh` — PASS.
- `sh tests/unit/test-reviews-parity.sh` — PASS.

## Calibration

Single snapshot, micro scope — no second independent pass owed. The
reviewer/verifier redundancy axis is collapsed by design of this pass
(solo, USER instruction): the same session that hunted also verified,
so a shared blind spot cannot be caught by a second axis here — the
strong-tier model and the /tmp-anchored simulations are the only
mitigations, and the `Skills:` line records that this pass ran with
the opk-review-pass skill loaded.

## Recommendation

Two dispositions owed, both small and neither blocking: B1 is a
dead-guard cleanup (or a one-character capture widening plus a
resolution-wording correction), B2 is an optional reverse-direction
extension following the suite's own W30 precedent — proportionate to
record and skip if the maintainer judges docs-addition drift better
hunted at review time. The hard seam holds: this round fixes nothing;
dispositions land in the next fix wave on the maintainer's go.
