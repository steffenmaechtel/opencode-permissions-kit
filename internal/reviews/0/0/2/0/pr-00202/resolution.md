# Resolution — pr-00202 (issue-168 mktemp fallback class-sweep widening)

Chain: [review-a.md](review-a.md) — micro-wave review of the #168 wave
(63c9f02). Base v0.0.52 @ 5975524.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `119b122` | canary beside the sweep, SAME expression; sabotage A → canary FAIL; restored → green |
| a W2 (INFO) | **implemented** | `119b122` | comment now states brace-assign fixed path matches shape (a) by design |

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

## Stop-rule note

This fix wave touches test code → one more micro-wave pass (snapshot b)
is owed in a fresh session per the rotation rule (review-concept.md,
"Session rotation").
