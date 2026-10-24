# Resolution — pr-00241 (issues #237/#238 review-process docs + parity pin)

Status: closed (maintainer, 2026-10-24) — confirmed the stop rule:
the last round (fix wave 2, #241 b T1/W1/T2) dispositioned all three
findings as ledger edits and touched no review-relevant code —
files touched = resolution.md only (bookkeeping, RM-0065, loop
closed per RM-0066).

Chain: [review-a.md](review-a.md) (micro-wave snapshot 2026-10-24, 6
findings, in-session pass on maintainer commission — single-session
chain, USER decision) → fix wave 1 (`400ff20` fixes + this ledger,
`4711c82` SHA fill, `793b8e2` Q3 sweep + `8170a43` fill) →
[review-b.md](review-b.md) (micro-wave snapshot 2026-10-24, 3
findings) → fix wave 2 (this file: b-round ledger corrections). Birth
PR #241, branch `feature/237-238-review-process-docs`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a Q1 (MED) | **implemented** | `400ff20` | bullet separates the two incidents; meta log records the fix |
| a Q2 (LOW) | **implemented** | `400ff20` | README + RM-0118 Check: form binds from 2026-10-24, corpus stays |
| a S1 (LOW) | **implemented** | `400ff20` | fixture 1 prose carries "closed"; substring regression red (sabotaged) |
| a Q4 (INFO) | **implemented** | `400ff20` | README: parser takes the FIRST Status line, kept top vs prose shadow |
| a Q3 (INFO) | **implemented** | `793b8e2` | maintainer override: all 4 label sites swept to reviews/README.md |
| a S2 (INFO) | **deliberately not done** | — | nothing silent — both directions red; triage steer only (detail) |
| b T1 (LOW) | **implemented** | this file | Q2 evidence re-measured: 10 grandfathered lines; snapshot's 16 → 15 |
| b W1 (INFO) | **implemented** | this file | Q1 record path rewrapped — code span unbroken, renders resolvable |
| b T2 (INFO) | **implemented** | this file | Gates parenthetical corrected: rules INDEX byte-identical, no commit |

## Evidence detail

### a Q1 (MED) — rule bullet teaches the real mechanism now

The RM-0117 unit's closing sentence now separates the two pr-00234
shapes instead of conflating them: the a-wave committed gate claims
that were false at its own HEAD (rows unwrapped past 120, a missing
pointer and a stale INDEX red with them — the claims predated the
resolution file), and the b-wave ran its ratchet only AFTER the
`<SHA>`-fill commit (benign: +2 bytes/row stayed under the bound).
This matches the b W1 record in
`internal/reviews/0/0/2/3/pr-00234/resolution.md`, "b W1 (MED) —
ratchet + reviews-parity red at the a-wave HEAD", and the RM-0117 meta body, which had been correct all
along; the meta's Review log now carries the correction entry. The
bullet's first five words (the meta's quote anchor) are untouched —
rules-audit inv5 stays green, re-run below.

### a Q2 (LOW) — binds-from-here-on boundary

README "Resolution format": the confirmer + check form "binds lines
written from 2026-10-24 on — post-legacy lines already in the corpus
stay as written, like the legacy rows", mirroring the legacy
grandfathering bullet one screen down. RM-0118's Check is scoped
identically ("chains closing from 2026-10-24 on"). Corpus state that
motivated the boundary — first written here by restating snapshot a's
enumeration (#241 b T1), now measured at the files: bare lines in
pr-00179/196/198/222; evidence-without-confirmer in
pr-00189/199/200/202/208/209 — **ten** pre-prescription lines, all
still reading `closed` in the INDEX (the generator ignores the form
entirely). Snapshot a's "of 16 resolutions with `Status: closed`"
overcounts by one: 15 files carry an anchored Status line (measured
2026-10-24; the snapshot is immutable — this correction lives here
per README rule 1, corrections happen in the resolution).

### a S1 (LOW) — the pin discriminates the source line now

Fixture 1's prose is now `chain still running; nothing closed yet.` —
the word "closed" appears WITHOUT a `Status:` line, so a `status()`
regression to substring search reads `closed` on direction 1 and the
pin goes red. Verified by sabotage (below): regex swapped for a
substring search → open direction FAILs with `| closed |` in the
output; restore → green. Direction 2 (Status line present → closed)
is unchanged. The load-bearing word is commented at the fixture so a
future edit cannot silently drop it.

### a Q4 (INFO) — first-match precision

README now states the parser takes the FIRST `Status:` line in the
file and the line stays at the top so later prose cannot shadow it —
matching `gen-review-index.py` `status()` (whole-file `re.search`,
first match wins) instead of implying a position guarantee.

### a Q3 (INFO) — label sweep done on maintainer override

First dispositioned deliberately-not-done (single-site rename would
have split the label forms inside the file); the maintainer overrode
in-session ("hätten wir das nicht schnell fixen können") — the cheap
class-correct move is the sweep, and it ran: all four
`[review/README.md]` labels in `agent/review-concept.md` (the three
pre-existing sites + this wave's bullet) now read `reviews/README.md`,
matching the file they point at. Frozen corpus mentions of the old
label (pr-00115/pr-00133 history) stay as written — snapshots are
immutable.

### a S2 (INFO) — diagnostic steer accepted

If `META_FIELDS` grows, the frozen fixture header parses as None and
`status()` returns `resolved` — both pin directions fail LOUD (rc 1,
FAIL lines); only the message's triage hint is off. Hardening the
message would couple the pin to `parse_meta` internals for an
INFO-grade steer; the failure mode is documented here and in snapshot
a's S2 detail instead.

### Gates (this fix wave — measured on the pre-commit tree)

`make test` green (full unit suite); `make lint` green; `make
check-version` green; `sh scripts/rules-audit.sh` 0 blocking (rules
INDEX verified current — the metas' frontmatter is unchanged, so the
generated rules INDEX is byte-identical; nothing to commit, and none
was, #241 b T2); `sh
tests/unit/test-line-length.sh` OK; `sh tests/unit/test-reviews-lint.sh`
OK (28 cases); `sh tests/unit/test-reviews-parity.sh` OK (28 rows,
status directions pinned — the hardened fixture ran green pre-commit).
The ratchet earned its keep on this very tree: the first row draft ran
128–171 content columns and the gate went red BEFORE the commit —
rows were trimmed to ≤ 118 (leaving the +2-byte SHA-fill headroom),
overflow preserved in the Evidence detail blocks above. Sabotage of
the S1 hardening, on the committed tree after this wave, observed the
way production observes (suite output): `status()` regex swapped to
substring search → open direction red (`| closed |`); line-anchored
restore → green. Class sweep: the `<SHA>` pattern's only in-flight
instance is this resolution's own rows (filled by the chain's next
commit, ratchet re-run before it — the RM-0117 discipline this wave
documents).

### b round (T1, W1, T2) — ledger-truth fixes in this file

All three fixes are edits to this resolution, so their rows carry
"this file" in the Commit column (the pr-00208 b W1 precedent — no
`<SHA>` placeholder when the ledger IS the fix). T1 re-measured the
grandfathered corpus at the files (ten lines: four bare + six
evidence-only including pr-00189/202, each verified at its own line 3)
and records snapshot a's 16 → 15 overcount where the snapshot cannot
correct itself. W1 rewrapped the Q1 record citation so the code span
stays on one line and renders a resolvable path. T2 states what
actually happened to the rules INDEX (byte-identical, no commit
content — `git show 400ff20 --stat` shows no rules INDEX path).

## Gates (fix wave 2 — measured on the pre-commit tree)

`sh tests/unit/test-line-length.sh` OK; `sh tests/unit/test-reviews-
lint.sh` OK (28 cases); `sh tests/unit/test-reviews-parity.sh` OK
(28 rows, status directions pinned). Resolution-only wave — no code,
test, or shipped file touched, so the wave-1 gate runs above still
describe the tree. Incident, recorded for the class ledger: the
ratchet DID go red pre-commit (the b T1 row at 130 columns), but the
session ran it as `sh … | tail -1` — the pipe's rc is tail's, the red
was not observed, and the first commit of this wave landed with the
row over the bound (caught in the same session's post-commit check;
row trimmed, gates re-run clean, commit amended — the L1/L4 pipe
shape: a gate observed through a pipe that discards its rc is no
gate; run gates bare, read the rc).

## Follow-ups

- **Stop-rule expectation (check cited, RM-0115):** this round's
  dispositions touched no review-relevant code — files touched =
  `resolution.md` only (bookkeeping, RM-0065) — so per RM-0066 the
  chain closes with this round once the maintainer confirms; on that
  confirmation the closure is recorded per RM-0118 (`Status: closed`
  naming the confirmer + INDEX regen, one commit).
