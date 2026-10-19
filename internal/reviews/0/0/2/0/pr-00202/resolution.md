# Resolution — pr-00202 (issue-168 mktemp fallback class-sweep widening)

Chain: [review-a.md](review-a.md) · [review-b.md](review-b.md) ·
[review-c.md](review-c.md) — micro-wave reviews of the #168 wave
(63c9f02), its fixes (119b122, dd25de8) and the c-wave fix (d19919c).
Base v0.0.52 @ 5975524.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `119b122` | canary beside the sweep, SAME expression; sabotage A → canary FAIL; restored → green |
| a W2 (INFO) | **implemented** | `119b122` | comment now states brace-assign fixed path matches shape (a) by design |
| b W1 (LOW) | **implemented** | `dd25de8` | canary pins all 7 comment claims; brace-blind + over-broad sabotage red, restored green |
| c W1 (LOW) | **implemented** | `d19919c` | canary pins all remaining claims — 6 match / 8 spared incl. multi-line; alternation-narrow + strip-to-path sabotage red, restored green |

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

### c W1 (LOW) — remaining discrimination claims pinned

Canary grew from 7 to 14 scratch lines, closing the gap between the
"every discrimination claim" sentence and its coverage (L2 class sweep
— beyond the finding's named four lines, the multi-line non-sweep
claim is the same class sibling and went in too; the sentence would
otherwise keep over-claiming). New pins, still the SAME
`$W2_FIXPATH_A|$W2_FIXPATH_B` expression:

- offending (must match): `_w2_can_d=… || _w2_can_d="/tmp"` (quoted
  /tmp literal), `_w2_can_e=$(sudo mktemp) || … /var/tmp` (prefix +
  /var/tmp), `_w2_can_f=$(mktemp || echo /tmp)` (un-muffled shape b) —
  asserted via `^8:`/`^9:`/`^11:`;
- must NOT match: `_w2_can_ok5=$(mktemp 2>/dev/null)` (bare redirect,
  no `||` — asserted absent via `^10:`) and the three-line multi-line
  fallback `_w2_can_g` (asserted absent via `^12:`–`^14:`).

Every claim sentence in the sweep comment (shapes, literals, quoting,
prefix, sanctioned forms, deliberately-unswept forms) now has a line.

Mutation verification (work committed at `d19919c` first, tree
restored green after each run):

- fixed-path alternation narrowed `(dev/null|tmp|var/tmp)` →
  `(dev/null)` in both shapes (the W1 drift scenario): canary FAIL
  "blind or over-broad (got: 1:… 2:… 3:…)" — precisely the three new
  offending lines (`^8:`/`^9:`/`^11:`) going uncaught; suite rc=1;
- shape A stripped to the bare path alternation
  (`'/dev/null|/tmp|/var/tmp'`): canary FAIL over-broad with got
  1,2,3,8,9,10,11,13 — the new negatives `^10:` (bare `2>/dev/null`)
  and `^13:` (multi-line middle line) fire; suite rc=1;
- restored → `sh tests/unit/test-status.sh` green rc=0 ("catches all
  six offending lines … spares all eight non-match lines"),
  `make lint` green.

## Stop-rule note

The a-wave fix touched test code → snapshot b ran (1 LOW). The b-wave
fix (`dd25de8`) also touched test code → snapshot c ran (1 LOW). The
c-wave fix (`d19919c`) again touches test code → one final micro-wave
pass (snapshot d) is owed in a fresh session per the rotation rule
(review-concept.md, "Session rotation").
