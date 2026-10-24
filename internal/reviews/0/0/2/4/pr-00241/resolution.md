# Resolution — pr-00241 (issues #237/#238 review-process docs + parity pin)

Chain: [review-a.md](review-a.md) (micro-wave snapshot 2026-10-24, 6
findings, in-session pass on maintainer commission — single-session
chain, USER decision) → fix wave 1 (this chain's first). Birth PR #241,
branch `feature/237-238-review-process-docs`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a Q1 (MED) | **implemented** | `400ff20` | bullet separates the two incidents; meta log records the fix |
| a Q2 (LOW) | **implemented** | `400ff20` | README + RM-0118 Check: form binds from 2026-10-24, corpus stays |
| a S1 (LOW) | **implemented** | `400ff20` | fixture 1 prose carries "closed"; substring regression red (sabotaged) |
| a Q4 (INFO) | **implemented** | `400ff20` | README: parser takes the FIRST Status line, kept top vs prose shadow |
| a Q3 (INFO) | **deliberately not done** | — | label matches 4 neighbor sites; rename splits forms; Follow-ups |
| a S2 (INFO) | **deliberately not done** | — | nothing silent — both directions red; triage steer only (detail) |

## Evidence detail

### a Q1 (MED) — rule bullet teaches the real mechanism now

The RM-0117 unit's closing sentence now separates the two pr-00234
shapes instead of conflating them: the a-wave committed gate claims
that were false at its own HEAD (rows unwrapped past 120, a missing
pointer and a stale INDEX red with them — the claims predated the
resolution file), and the b-wave ran its ratchet only AFTER the
`<SHA>`-fill commit (benign: +2 bytes/row stayed under the bound).
This matches the b W1 record (`internal/reviews/0/0/2/3/pr-00234/
resolution.md`, "b W1 (MED) — ratchet + reviews-parity red at the
a-wave HEAD") and the RM-0117 meta body, which had been correct all
along; the meta's Review log now carries the correction entry. The
bullet's first five words (the meta's quote anchor) are untouched —
rules-audit inv5 stays green, re-run below.

### a Q2 (LOW) — binds-from-here-on boundary

README "Resolution format": the confirmer + check form "binds lines
written from 2026-10-24 on — post-legacy lines already in the corpus
stay as written, like the legacy rows", mirroring the legacy
grandfathering bullet one screen down. RM-0118's Check is scoped
identically ("chains closing from 2026-10-24 on"). Corpus state that
motivated the boundary (measured 2026-10-24, grep over resolutions):
bare lines in pr-00179/196/198/222; evidence-without-confirmer in
pr-00199/200/208/209 — eight pre-prescription lines, all still reading
`closed` in the INDEX (the generator ignores the form entirely).

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

### a Q3 (INFO) — label consistency kept

`[review/README.md]` matches the four pre-existing labels in
`agent/review-concept.md` (intro, loop, snapshot-seam, stop-rule
sites); the target resolves correctly. Renaming only the new site
would split the label forms inside one file; a full sweep is parked
in Follow-ups.

### a S2 (INFO) — diagnostic steer accepted

If `META_FIELDS` grows, the frozen fixture header parses as None and
`status()` returns `resolved` — both pin directions fail LOUD (rc 1,
FAIL lines); only the message's triage hint is off. Hardening the
message would couple the pin to `parse_meta` internals for an
INFO-grade steer; the failure mode is documented here and in snapshot
a's S2 detail instead.

### Gates (this fix wave — measured on the pre-commit tree)

`make test` green (full unit suite); `make lint` green; `make
check-version` green; `sh scripts/rules-audit.sh` 0 blocking
(rules INDEX regenerated with this commit); `sh
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

## Follow-ups

- **a Q3 (INFO):** label sweep `review/README.md` →
  `reviews/README.md` across `agent/review-concept.md` (5 sites) —
  cosmetic, ride the next wave that edits the file.
- Round b owed: this wave touches test code (`test-reviews-parity.sh`
  fixture + comment) — review-relevant per the stop rule; the
  micro-wave review of this fix diff starts on the maintainer's go.
