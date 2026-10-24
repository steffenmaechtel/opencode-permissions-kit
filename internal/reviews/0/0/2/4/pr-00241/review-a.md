<!-- review-meta
ID: pr-00241
Snapshot: a
Subject: review-process docs + parity pin, issues #237/#238 (micro-wave review of the feature wave's diff)
Scope: wave
Base: master @ d179acb (VERSION 0.0.56)
Diff: d179acb..c8c7671
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (axes Q/S) — in-session micro-wave, single-session chain = USER decision (maintainer commission 2026-10-24, review-concept "Session rotation")
Skills: opk-review-pass
-->

# Review a — review-process docs + parity pin (issues #237/#238)

Micro-wave review of the feature wave's whole diff (one commit,
8 files, 183 insertions: documentation + rule units RM-0117/RM-0118 +
one new parity pin). Commissioned in-session by the maintainer —
rotation deviation recorded above; the reviewed tree is the committed
HEAD c8c7671, clean at fan-out.

## Findings index (combined)

| ID | Severity | One-liner |
|---|---|---|
| Q1 | MED | RM-0117 bullet attributes the pr-00234 a-wave red to the `<SHA>`-fill byte trap — the record says the red was long rows + pointer + stale INDEX, and the fill itself never went red |
| Q2 | LOW | New closed-line prescription (confirmer + stop-rule check) doesn't match ~8 existing post-legacy resolutions; RM-0118's audit Check fails against today's corpus |
| S1 | LOW | Check 4 pins status *direction*, not that the column derives from the `Status:` line — a substring-searching `status()` passes both directions |
| Q3 | INFO | New link label `[review/README.md]` (missing "s") propagates the file's existing label typo |
| Q4 | INFO | "The `Status:` line near the top of the file" is convention only — parser searches the whole file, first match wins |
| S2 | INFO | If `META_FIELDS` grows, the fixture's meta parses as None → `resolved` branch → loud red, but the diagnostic misattributes the regression to the status direction |

Provenance: all six wave-introduced.

---

## Axis Q (quality — docs claim-vs-behavior drift), verbatim

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | MED | RM-0117 bullet attributes the pr-00234 a-wave red to the `<SHA>`-fill byte trap — the record says the red was long rows + pointer + stale INDEX, and the fill itself never went red | wave-introduced |
| Q2 | LOW | New closed-line prescription (confirmer + stop-rule check) doesn't match ~8 existing post-legacy resolutions; RM-0118's audit Check fails against today's corpus | wave-introduced |
| Q3 | INFO | New link label `[review/README.md]` (missing "s") propagates the file's existing label typo | wave-introduced (pattern pre-existing) |
| Q4 | INFO | "The `Status:` line near the top of the file" is convention only — parser searches the whole file, first match wins | wave-introduced claim, pre-existing behavior |

### Details

### Q1 — MED — a-wave red misattributed to the SHA-fill mechanism

`agent/review-concept.md:155-158`:

> The recurring trap is the `<SHA>` fill — a real SHA is 2 bytes longer per row than the placeholder; pr-00234's a-wave gate claims went red exactly this way (#234 b W1). (RM-0117)

"Exactly this way" grammatically points at the SHA-fill byte trap just described. The cited record says otherwise — `internal/reviews/0/0/2/3/pr-00234/resolution.md:106-112` (b W1):

> The a-wave's disposition rows ran 124-146 content columns while the ratchet scope includes review resolutions … and two reviews-parity members were red with them: review-a.md lacked its `> Resolution:` pointer line and the committed INDEX still said pr-00234 "no-resolution".

The a-wave red was three members (ratchet from unwrapped 124–146-col rows, pointer, stale INDEX); its rows already carried real SHAs, no fill involved. The SHA fill was the **b-wave** incident and it never went red — RM-0117's own meta body says so (`internal/rules-meta/0/1/1/RM-0117.md:20-21`: "Both ended benignly (the +2 bytes per replaced row stayed under the 120-column bound)"), and the README bullet in the same commit attributes the ordering problem correctly to "pr-00234's **b-wave** fill" (`internal/reviews/README.md:185-186`). The commit thus contradicts itself: same incident, two different mechanisms in two files, and the rules-file version is the wrong one.

Why it matters: this is a binding rules unit whose evidence citation teaches a false mechanism; anyone reconciling it against #234 b W1 or RM-0117.md gets two different stories, which erodes the citation discipline the rule itself demands. Realistic trigger: any reader/maintainer auditing RM-0117 or reusing the incident as precedent.

### Q2 — LOW — new closed-line format doesn't match the existing modern corpus

`internal/reviews/README.md:151-156` prescribes: the closed line "names who confirmed closure (maintainer or next round …) and cites the stop-rule check"; `internal/rules-meta/0/1/1/RM-0118.md` Check: "closed chains' resolutions carry the Status line naming the confirmer". The corpus: of 16 resolutions with `Status: closed`, only pr-00211, pr-00221, pr-00224, pr-00234, pr-00235 match the prescription. These post-legacy (two-part-form) chains do not:

- bare line, no confirmer, no check: `pr-00179/resolution.md:3` (`Status: closed`), `pr-00196:15`, `pr-00198:13`, `pr-00222:6`
- evidence cited, no named confirmer: `pr-00199:12`, `pr-00200:6`, `pr-00208:9`, `pr-00209:3`

The legacy grandfathering bullet (`README.md:186-188`) covers only pr-00109…pr-00171, so these eight are bound by the new format as written. Generator impact: none — all read `closed` regardless (severity is conditional on someone actually running RM-0118's Check against the repo, which is its stated purpose). No migration note tells the auditor these lines predate the prescription.

### Q3 — INFO — link label typo propagated

`agent/review-concept.md:127`: `[review/README.md](../internal/reviews/README.md)` — label says "review/", file is "reviews/". The target resolves correctly; lines 5, 36, 40 of the same file already use the same mislabeled form, so the new bullet is consistent with its neighbors, not new drift. Cosmetic.

### Q4 — INFO — "near the top" is unenforced; parser is whole-file, first-match-wins

`internal/reviews/README.md:151` says the Status line sits "near the top of the file"; `scripts/gen-review-index.py:78` (`status()`) does `re.search(r'^Status:\s*(\w+)', read(res), re.M)` — whole file, first match wins, nothing enforces position. Edge shapes probed: capitalized `Status: Closed` → matched and lowercased → reads `closed` (generator more lenient than docs — docs claim holds); leading-whitespace line → no match → reads `open`; dispositions-table rows start with `|` → can't match; a column-0 `Status:` line inside a fenced block would match, but no current resolution has fences (grep count 0 in pr-00234) or a second Status-shaped line (all 16 files carry exactly one, at lines 3–15). Residual nuance: resolutions are append-as-you-grow ledgers, and a second Status line appended at the bottom would be silently ignored in favor of the first — no corpus instance today, hence INFO, not LOW.

## Claims verified clean

- **"2 bytes longer per replaced row (7 → 9 bytes)"** — measured: `` `<SHA>` `` = 7 chars; corpus short SHAs are all 7 chars (`d1dcf34`, `f1fd24e`, `a3ecc9b`) → 9 in backticks. `README.md:181` holds; `LIMIT=120` confirmed at `tests/unit/test-line-length.sh:69`.
- **Ratchet scope** — `docs_scope()` (`test-line-length.sh:78-87`): `find agent internal docs .agents -name '*.md'` minus `internal/reviews/*/pr-*/review-*`, `INDEX.md`, `legacy-index.md` → resolution.md IN, review-*.md OUT, SKILL.md IN. Matches `README.md:176-179`.
- **"reviews lint/parity" gates** — both exist (`tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh`); the three named gates match b W1's three red members.
- **Generator directions** — `status()` (`gen-review-index.py:74-85`): absent line → `'open'` (new-style with resolution); `nothing fails` claims (`README.md:161`, `SKILL.md:168-169`) hold — lint has zero Status checks; parity only pins directions. The one-commit closure mechanics (`SKILL.md:164-167`, `process/review.md:32-34`, `README.md:220-223`) all cite the real "Resolution format" heading (`README.md:122`).
- **Parity pin (check 4)** — mechanics sound: fixture meta carries all 8 META_FIELDS; `ROOT` resolves to the scratch tree; fail-loud `||` pins on both generator runs; discriminating patterns `'| open |'`/`'| closed |'` match the real row format; pin sits before the summary gate; doesn't disturb `$TMP.rows` (written at line 32, read at 110).
- **Rules-audit compliance** — both metas' `quote:` prefixes are exact bullet prefixes; rule anchors `#who-records-what` (heading at `review-concept.md:138`) and `#the-loop-and-the-stop-rule` (line 27) are real headings; bodies carry only their own RM id; zero stray RM tokens in `README.md`, `SKILL.md`, `process/review.md`; RM-0117 bullet sits under "Who records what", RM-0118 under "The loop and the stop rule" — INDEX grouping (`INDEX.md:114,139`) consistent.
- **INDEX counts** — 118 meta files on disk, 116 `status: active`, 2 retired → `INDEX.md:9` line accurate; "next due 2026-11-14" correctly unchanged (new metas due 2026-11-24).
- **RM-0118 vs RM-0115** — no contradiction: RM-0115 (`review-concept.md:117-120`) bans a round *declaring* its own closure; RM-0118 records closure *after* maintainer/next-round confirmation and the meta body reconciles the two explicitly.
- **Cross-references** — `[review-concept.md](../../agent/review-concept.md)` from `internal/reviews/README.md` and `[review README](../reviews/README.md)` from `internal/process/review.md` both resolve; the "The loop and the stop rule" citation is a real section.

## Unverified (one follow-up spent, then stopped)

- `RM-0117.md:17-19` claims the b-wave SHA fill ran "in a command chain shaped `git commit … && test-line-length` — deliberately commit-then-check". Command orderings aren't recorded in git history; commit `f1fd24e`'s message records only the gate *results* ("b-wave gates, measured on this tree: … rc 0"), consistent with either ordering. Source cited is off-repo (issue #237). Not flagged — unverifiable here, not contradicted.

## Coverage

Covered: full diff; every factual claim about `gen-review-index.py` probed against `status()`/`main()` including the four edge shapes; byte claim measured; ratchet scope read from `docs_scope()`; lint/parity gate existence; all new links/anchors/headings resolved; meta frontmatter (quote, rule anchor, ids, counts, grouping, revisit arithmetic); stray-RM sweep over all touched living files; corpus check of the Status-line format against 16 existing resolutions; pr-00234 b W1 record vs all three commit-internal retellings of the incident; RM-0115/RM-0118 compatibility; parity-pin mechanics and fixture completeness. Deferred: `test-reviews-lint.sh` read only via grep (no Status hits; full 113 lines unread — no claim in the diff depends on its internals beyond existence); the `<SHA>`-chain-shape claim left unverified as above; `Base: v0.0.55` in the pin fixture not checked against `VERSION` (generator doesn't validate it).

---

## Axis S (security + test mechanics), verbatim

## Findings index

| ID | Severity | One-liner |
|---|---|---|
| S1 | LOW | Check 4 pins status *direction*, not that the column derives from the `Status:` line — a substring-searching `status()` passes both directions |
| S2 | INFO | If `META_FIELDS` grows, the fixture's meta parses as None → `resolved` branch → loud red, but the diagnostic misattributes the regression to the status direction |

No HIGH/MED findings.

### Detail

### S1 — LOW · Pin verifies the two-direction mapping only, not the source line · wave-introduced

Evidence — the header claims source-pinning (`tests/unit/test-reviews-parity.sh:12-16`):

```
#   4. status directions (issue #238): the generator derives the INDEX
#      Status column from the resolution's "Status:" line — absent
```

and the block comment doubles down (`tests/unit/test-reviews-parity.sh:70-71`):

```
#    claim the closure rule stands on: the INDEX Status column comes
#    from that one line, and its absence fails nothing.
```

but the mechanics only test absence→`open`, `Status: closed`→`closed`. A regression of `status()` (`scripts/gen-review-index.py:78`, `re.search(r'^Status:\s*(\w+)', …)`) to a substring search — e.g. `re.search(r'closed', read(res))` returning `'closed' if found else 'open'` — passes both check-4 directions: fixture 1's prose (`chain still running.`, test line 87) contains no "closed", fixture 2's does. Under that generator, a resolution *mentioning* "closed" anywhere without a `Status:` line reads closed — exactly the misattribution the rule exists to prevent. Realistic trigger: a refactor of `status()`'s matching. Hardening is cheap (put the word "closed" in fixture 1's prose so a content-grepping generator fails direction 1); as written the claim is one notch stronger than the pin. Severity LOW: the current implementation is line-anchored and both wrong-output directions (always-open, always-closed) *are* caught.

### S2 — INFO · New mandatory meta field degrades the pin's diagnostic · wave-introduced

`parse_meta` is all-or-nothing (`scripts/gen-review-index.py:45-46`: `return None if missing else out`). If the generator later grows a `META_FIELDS` entry, the scratch fixture header (test lines 75-86, frozen via quoted heredoc) parses as `meta = None`, so `status()` takes the legacy branch (`scripts/gen-review-index.py:82-83`, `return 'resolved'`). Both directions then fail loudly — hermeticity holds — but the message reads `FAIL status pin: no Status line must read open, got: … | resolved |` (test line 93), pointing at the status direction when the actual break is meta parsing. The other scratch-dependency worry is clean: no `legacy-index.md` in the scratch is safe (`scripts/gen-review-index.py:53-54` guards with `os.path.exists`). INFO because nothing passes silently; only the triage path gets a wrong steer.

## Verified clean (checked, no finding)

- **Fail-loud shape**: both case branches have default-`*)` FAIL arms; empty `row` (grep miss / generator wrote nowhere) falls to the FAIL arm; generator non-zero rc (python3 missing → rc 127) pinned per direction (test lines 88-89, 97-98); generator stderr only ever carries `WARN` (`gen-review-index.py:107-108`), failures surface via rc. Pin sits **before** the summary gate (`if [ -s "$TMP" ]`, test line 105).
- **Discrimination**: status is the last column (`gen-review-index.py:126`), so the end-anchored `*'| open |'` / `*'| closed |'` patterns cannot false-match on a pipe-bearing Subject (column 2); status is a single lowercased `\w+` token (`:78-80`), so the row ending is determined by the status alone. No green-while-broken state found beyond S1's narrowed-source case.
- **Sandbox**: `mktemp -d` scratch under `/tmp` (sanctioned prefix, conventions.md:131); heredocs and `printf` write only into `$GENDIR`; the subshell `(cd "$GENDIR" && python3 …)` lets the copy write only under its own scratch `ROOT`. `rm -rf "$GENDIR"` is a pure-variable operand — explicitly exempt (conventions.md:150; scanner agrees, test-sandbox-policy.sh:273). No real-tree literals in the new block.
- **Generator-copy contract**: `ROOT` derives from the script's own path (`gen-review-index.py:23`), so the copy reads scratch fixtures only; pattern matches two siblings (`test-rules-meta.sh:89`, `test-rules-revisit.sh:476`).
- **Both regenerated INDEXes**: `gen-rules-index.py` and `gen-review-index.py` run on a `git archive c8c7671` export reproduce the committed INDEX.md files **byte-identically**. RM-0117/RM-0118 rows correct: bucket `0/1/1/` consistent with sibling RM-0115, `**pending**` review flag + review-pending count (2) consistent with the "maintainer review pending" review-log lines, grouping sections match the metas' anchors — both anchors resolve to real headings (`agent/review-concept.md:138` `## Who records what`, `:27` `## The loop and the stop rule`).
- **Docs+test-only claim verified**: diff touches only `.agents/`, `agent/`, `internal/` (process/reviews/rules-meta) and `tests/unit/test-reviews-parity.sh` — no `files/`, Makefile, workflows, or `scripts/` changes.
- **Sibling sweep**: the only other Status parser is `test-docs.sh:130` (`> Status: **WORD**` in `internal/records/*.md`) — a different file family with no shared logic with `gen-review-index.py`; not a missed same-shape site. All four wave claim-sites (SKILL.md, review-concept.md, process/review.md, reviews/README.md) point at behavior the new pin actually covers.

## Coverage

Covered: full diff; check-4 fail-loud/discrimination/placement audit against the generator source; sandbox-policy + trap/cleanup against conventions.md and the sandbox-policy scanner; generator-copy hermeticity (code-read + export run); both INDEX regens byte-verified at c8c7671; anchor resolution; sibling greps for status-parsing and copy-into-scratch patterns; docs+test-only claim. Deferred: did not run `test-reviews-parity.sh` itself (its check 2 rewrites the real `internal/reviews/INDEX.md` in place — mutation of the shared tree during a review fan-out; regen equivalence was proven hermetically on the export instead); did not audit the six doc files' prose beyond the claims tied to pinned behavior (content-axis reviewers' ground); multi-`row` grep concatenation (future second fixture matching `pr-00420` in prose) noted but not flagged — contrived under the current single-case scratch.

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| Q1 | **confirmed** | `pr-00234/resolution.md` b W1 (lines 106–122): a-wave red = rows at 124–146 cols + missing pointer + stale INDEX; a-wave rows cite real SHAs (`d1dcf34`, filled by 4554530); the fill-related ordering was the b-wave (f1fd24e→c8bbb32) and stayed green. The RM-0117 sentence "went red exactly this way" misattributes. |
| Q2 | **confirmed** | `grep -rn '^Status: closed$'` → bare lines in pr-00179/196/198/222; evidence-without-confirmer in pr-00199/200/208/209 (grep corpus, this session). Legacy bullet covers only pr-00109…171. |
| Q3 | **confirmed** | Label at `review-concept.md:127`; 4 pre-existing same-label sites in the file; target resolves. |
| Q4 | **confirmed** | `gen-review-index.py:78` whole-file `re.search` with `re.M`, first match wins; no position enforcement; corpus: one Status line per file, lines 3–15. |
| S1 | **confirmed** | Fixture 1 prose `chain still running.` (test line 87) contains no "closed"; a substring-matching `status()` regression passes both directions. |
| S2 | **confirmed** | `parse_meta` all-or-nothing at `gen-review-index.py:45-46`; legacy branch `return 'resolved'` at `:82-83`; fixture frozen via quoted heredoc. |

None retracted; no ghosts. The Q-axis "Unverified" item (the exact
b-wave command-chain shape in RM-0117's body) stays unverified-claim
status: off-repo source (issue #237, the authoring session's own
account), not contradicted by git — recorded, not escalated.

## Retracted/ghost findings

None — both axes' findings all survived verification.

## Run provenance

- Commission: maintainer, in-session, 2026-10-24 ("mach Micro-Wave-Review
  hier in der Session") — single-session chain, USER decision per
  review-concept "Session rotation"; birth-PR #241 allocated before the
  pass (case key pr-00241).
- Tree: c8c7671 (feature/237-238-review-process-docs), clean at
  fan-out (`git status --porcelain` empty). Material: diff d179acb..c8c7671.
- Host timestamps (main session, UTC): fan-out start 2026-10-24T11:59:58Z,
  end (both returned) 2026-10-24T12:10:19Z.
- Reviewer subagents: 2 (cap 5 respected), fast tier GLM-5.3-Flash
  (variants: default), fresh contexts, axis prompts built from
  `.agents/skills/opk-review-pass/axis-prompt.md`.
- Checkpoints: `/tmp/opencode/pr-00241-a/checkpoints/{quality,security}.md`
  (outside the reviewed tree), absorbed here: quality window
  14:00:45→14:08:40, security 14:00:45→14:06:13 (sandbox clocks ~2h
  ahead of host — skew noted, windows normalized against host stamps).
- Sabotage/mutation windows: none during the fan-out (the tree was a
  read-only substrate; the axis-S reviewer proved INDEX-regen
  equivalence hermetically on a `git archive` export instead of
  running the in-place-regenerating suite). An earlier sabotage
  verification of the new pin (both directions, restore + green
  re-run) executed BEFORE the fan-out launched on the committed tree —
  no overlap with reader windows.
- Gates at snapshot time: `make test` green, `make lint` green on
  c8c7671 (this session, before fan-out).

## Recommendation

Q1 is the round's payload: a binding rule unit teaching a false
mechanism — fix before merge. Q2 needs a boundary sentence (binds
from here on) to keep RM-0118's Check honest against the corpus.
S1's hardening is one fixture-word change and makes the pin match its
claim. Q3/Q4/S2 are small precision/disposition calls.
