# Resolution — pr-00202 (issue-168 mktemp fallback class-sweep widening)

Status: closed — chain a–e; stop rule met at the e-round disposition
(bookkeeping only, no review-relevant code touched)

Chain: [review-a.md](review-a.md) · [review-b.md](review-b.md) ·
[review-c.md](review-c.md) · [review-d.md](review-d.md) ·
[review-e.md](review-e.md) — micro-wave reviews of the #168 wave
(63c9f02), its fixes (119b122, dd25de8), the c-wave fix (d19919c), the
d pass and its follow-up. Base v0.0.52 @ 5975524.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `119b122` | canary beside the sweep, SAME expression; sabotage A red, restored green |
| a W2 (INFO) | **implemented** | `119b122` | comment now states brace-assign fixed path matches shape (a) by design |
| b W1 (LOW) | **implemented** | `dd25de8` | canary pins all 7 claims; brace-blind + over-broad sabotage red, green |
| c W1 (LOW) | **implemented** | `d19919c` | canary pins remaining claims (6 match / 8 spared); sabotages red, green |
| d W1 (INFO) | **implemented** | — | correction below: "165 PASS" was an output label, not a count (138 passes) |
| e W1 (INFO) | **implemented** | — | correction below: 138 passes; the lowercase summary never matched the count |

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

### d W1 (INFO) — gate-count correction ("165 PASS" is a test label, not a count)

Snapshot d could not reproduce the "165 PASS" gate figure carried by
review-a.md:96, review-b.md:84 and review-c.md:111. Measured with
`grep -c PASS` over `sh tests/unit/test-status.sh` output at every
chain tree (`119b122`, `dd25de8`, `d3b7afc`, HEAD): **138** — 138 test
passes; the closing "All status tests passed." summary is lowercase and
does not itself match the case-sensitive count (split corrected by
#202 e W1) — with 0 FAIL and 0 SKIP, rc=0 (the canary contributes
exactly one pass line in every version, so the count is chain-stable).

Mechanism: the issue-#165 test block labelled its messages with a
bare `165:` prefix — 32 PASS lines read `PASS 165: …` near the log's
end, and the output carries no counter. The a-session read the
highest visible label as a running pass count and recorded "165
PASS"; b and c repeated the gates line without recounting. (The
c-session transcript — maintainer-provided, outside the repo —
noticed 138 vs 165 late and attributed it to the label, but the
committed snapshots stayed. Snapshot d's own guess that the figure
came from counting static `pass` sites was wrong; this note is the
correction.) Authoritative figure for the whole chain: 138 passes,
0 FAIL, 0 SKIP, rc=0.

Class closure: the 65 bare `165:` message prefixes in test-status.sh
were normalized to `#165:` in `fcb815a` (#202 d W1 follow-up,
maintainer-commissioned), matching the `#166:` label style already
in the same file. Sweep `(pass|fail) "[0-9]+:` across tests/unit and
tests/e2e now returns zero hits — no bare numeric label prefix
remains that could masquerade as a counter. Test code, messages
only: suite 138 PASS / 0 FAIL / 0 SKIP rc=0, `make lint` green.

### e W1 (INFO) — pass-count split corrected (138 passes, not 137)

Snapshot e re-measured on HEAD (`9a39433`): 138 lines match
case-sensitive `grep -c PASS`, and every one of them matches the
pass-helper shape (`\033[0;32mPASS\033[0m` + two spaces; `grep -v` for
that exact shape returns zero lines). The closing summary
"All status tests passed." is lowercase and cannot contribute to the
count. Correct decomposition: **138 test passes**, summary separate —
the 138 grep figure cited since snapshot d was right, the
"137 passes + summary" split (review-d.md, d W1 evidence above) was
off by one; both occurrences above are corrected and cite `#202 e W1`.
No shipped code involved; bookkeeping only.

### Addendum (e-disposition session): line-length ratchet restored

While committing the e W1 correction,
`tests/unit/test-line-length.sh` failed: resolution.md is ratchet docs
scope (only `review-*` snapshots are exempt) and had grown from 0 to 5
lines over 120 columns across the chain (`dd25de8`: 1, `d19919c`: 2,
`e516be7`: 3, `9a39433`: 4, the e W1 row: 5) without ever entering the
baseline — a regression the wave gates never saw: snapshots b–e gated
on test-status, lint, check-version and reviews lint/parity; the
ratchet runs in `make test` and CI (test-unit.yml line 143). First
breach: the b-wave fix `dd25de8`. Fix: all six dispositions-table rows
reflowed under 120 columns (the reviews-README row limit all along;
full narratives live in the evidence sections below) — the file now
carries zero long lines and needs no baseline entry. Resolution
bookkeeping only; the stop rule is unaffected.

## Stop-rule note

The a-wave fix touched test code → snapshot b ran (1 LOW). The b-wave
fix (`dd25de8`) also touched test code → snapshot c ran (1 LOW). The
c-wave fix (`d19919c`) again touched test code → snapshot d ran
(1 INFO, bookkeeping — the correction note above). The d W1
disposition itself changed no review-relevant code, but the
maintainer-commissioned label normalization (`fcb815a`) touches test
code → snapshot e ran over that diff (fresh session per the rotation
rule; 1 INFO, bookkeeping). The e W1 disposition is again
resolution-only: the round touched no review-relevant code — **the
chain closes under the stop rule.**
