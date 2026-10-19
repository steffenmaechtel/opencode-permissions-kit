# Resolution — pr-00202 (issue-168 mktemp fallback class-sweep widening)

Chain: [review-a.md](review-a.md) · [review-b.md](review-b.md) — micro-wave
reviews of the #168 wave (63c9f02) and its fixes (119b122).
Base v0.0.52 @ 5975524.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `119b122` | canary beside the sweep, SAME expression; sabotage A → canary FAIL; restored → green |
| a W2 (INFO) | **implemented** | `119b122` | comment now states brace-assign fixed path matches shape (a) by design |
| b W1 (LOW) | **implemented** | `dd25de8` | canary pins all 7 comment claims; brace-blind + over-broad sabotage red, restored green |

## Evidence detail

### a W1 (LOW) — sweep canary

`tests/unit/test-status.sh` gains a canary directly below the widened
sweep: a scratch file (`$WORK/w2-canary.sh`) with two offending shapes
(`_w2_can_a=$(mktemp) || _w2_can_a=/dev/null` — shape A;
`_w2_can_b=$(mktemp 2>/dev/null || echo /dev/null)` — shape B) and one
sanctioned line (`|| return 1`), grepped with the SAME combined
expression the sweep uses (not a re-implementation). The pin asserts
line 1 AND line 2 match while line 3 does not — so a regex edit that
blinds either alternation, or makes it over-broad, fails the suite.
Empty/renamed pattern variables degrade to match-everything, which the
`^3:` negative assertion catches as over-broad.

Mutation verification (work committed at `119b122` first): prefixing
`W2_FIXPATH_A` so shape A stops matching → canary FAIL with
"got: 2:_w2_can_b=…" (precisely the shape-A line going uncaught);
`git restore` → suite green rc=0.

### a W2 (INFO) — comment precision

The sweep comment's sanctioned-fallback sentence now reads: sanctioned
forms (`|| return 1` / `|| exit 1`, `|| X=""`, warn-only braces) do not
match, while a brace that ASSIGNS a fixed path does match shape (a) by
design — that is the dangerous form. Cites `#202 a W2`.

### b W1 (LOW) — all discrimination claims pinned

The canary grew from 3 to 7 scratch lines, pinning every claim the
comment makes (L2 class sweep — the finding named the two brace lines,
but `|| exit 1` and `|| X=""` were equally unpinned sanctioned claims):
three offending shapes (assignment `_w2_can_a=`, in-substitution
`_w2_can_b`, brace-assign `_w2_can_c`) asserted via `^1:`/`^2:`/`^3:`,
four sanctioned forms (`|| return 1`, `|| exit 1`, `|| X=""`, warn-only
brace) asserted absent via `^4:`–`^7:`. Still the SAME
`$W2_FIXPATH_A|$W2_FIXPATH_B` expression, no re-implementation.

Mutation verification (work committed at `dd25de8` first, tree restored
green after each run):

- brace sub-shape lost (`\|\|[^|]*=` → `\|\|[^{|]*[[:space:]]*=` in
  W2_FIXPATH_A only — shapes A/B still catch lines 1–2, brace line 3
  goes uncaught) → canary FAIL "blind or over-broad (got: 1:…)", suite
  reports 1 test failed;
- fixed-path tail dropped from shape A (pattern matches any
  `$(mktemp) || …`) → canary FAIL via the `^4:`–`^7:` negatives, suite
  rc=1;
- restored → `sh tests/unit/test-status.sh` green rc=0, `make lint`
  green.

## Stop-rule note

The a-wave fix touched test code → snapshot b ran (1 LOW). The b-wave
fix (`dd25de8`) also touches test code → one final micro-wave pass
(snapshot c) is owed in a fresh session per the rotation rule
(review-concept.md, "Session rotation").
