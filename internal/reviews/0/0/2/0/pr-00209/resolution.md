# Resolution — pr-00209 (issue-201 direct --version capture)

Status: closed — c-wave dispositions amended resolution bookkeeping
only (no review-relevant code); stop rule holds

Chain: [review-a.md](review-a.md) · [review-b.md](review-b.md) ·
[review-c.md](review-c.md) — wave reviews of the #201 wave (`4f98611`),
its fix (`1dc553f`) and the b-wave fix (`c776ab2`).
Base v0.0.53 @ f07f2fb.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `1dc553f` | 1.18.33/2.0.17 asserted per arm; M1–M3 sabotage red, green restored |
| a W2 (INFO) | **implemented** | `1dc553f` | typo "strenghtens" → "strengthens" |
| b W1 (LOW) | **implemented** | `c776ab2` | 2.0.19 asserted; 2.x-arm `= eq` mutation now red (survived review b) |
| b W2 (INFO) | **implemented** | `c776ab2` | nocmp pin asserts the fail-safe; guard-deletion mutation red |
| b W3 (LOW) | **implemented** | this amendment | sweep record corrected: wiring pins listed, no drift power |
| c W1 (LOW) | **implemented** | this amendment | b W2 sweep sentence narrowed to the comparator guard (see detail) |
| c W2 (LOW) | **implemented** | this amendment | wrapper parenthetical replaced with the real fail-safe mechanism |
| c W3 (INFO) | **deliberately not done** | — | env-inheritance edge, contrived preconditions; backlog note |
| c W4 (INFO) | **implemented** | this amendment | wiring-pin ranges corrected to 116–117 / 138–139 |
| c W5 (INFO) | **deliberately not done** | — | `unset -f` is deliberate F2 hardening; keep (see detail) |
| c W6 (INFO) | **deliberately not done** | — | `3.*)` arm owed only when opencode 3.x ships; fall-through is safe |

## Evidence detail

### a W1 (LOW) — bridge pin boundary gap closed

`tests/unit/test-status.sh`: the #201 bridge pin's condition grew the
two assertions its pass message names — `[ "$(w201_bridge 1.18.33)" = 1 ]`
(the 1.x arm's eq boundary) and `[ "$(w201_bridge 2.0.17)" = 0 ]` (the
2.x lt boundary) — placed with the `= 1` and `= 0` groups respectively.
Every boundary the message claims now has a discriminating assertion on
its own arm: 1.19.0 (1.x gt), 1.18.33 (1.x eq), 2.0.18 (2.x eq),
2.0.17 (2.x lt), 1.18.32 (1.x lt), `""` (unknown). The comment above
the pin now states exactly that scope (L3: the "discriminates all four
shapes" claim is gone — it under-described six assertions and hid the
gap the finding names).

Mutation verification (work committed at `1dc553f` first, tree restored
green after each run — `sh tests/unit/test-status.sh` rc=0,
`make lint` green):

- M1: 1.x arm `!= lt` → `= gt` (status.sh line 994) → bridge pin FAIL
  with the extract dump — the exact mutation that stayed green before
  this fix (verified in snapshot a against `4f98611`);
- M2: boundary constant `1.18.33` → `1.18.34` → FAIL;
- M3: boundary constant `2.0.18` → `2.0.17` → FAIL (both boundary
  constants are pinned now, not just the comparator direction).

Class sweep (L2): boundary-naming pins across `tests/unit/*.sh` via
`grep -rnE '1\.1[0-9]\.[0-9]+|2\.0\.[0-9]+' tests/unit/*.sh` — sites:
this pin, test-security-advisories.sh's comparator gate pins (block
spans lines 65–79: 1.18.32 lt / 1.18.33 eq / 2.0.17 lt / 2.0.18 eq /
empty fail-safe), and test-wsl-exposure.sh's wiring pins (116–117 on
the wrapper, 138–139 on status.sh; corrected per #209 b W3, c W4). No
sibling gap left: the wiring pins cannot discriminate comparator-line
drift — they presence-grep whole files and match the same literals in
status.sh's comment/detail prose (lines 985, 1000; observed: M2-style
constant drift leaves test-wsl-exposure.sh green) — so the behavioral
boundary pins remain this pin and the comparator gate pins.

Gates after the fix: `sh tests/unit/test-status.sh` green (all
#201/#163/#166/#200 pins PASS), full unit suite green, `make lint`
green, `make check-version` green.

### a W2 (INFO) — typo fixed

`tests/unit/test-status.sh`: "strenghtens" → "strengthens" in the
comment above the bridge pin. Comment-only.

### b W1 (LOW) — 2.x-above shape gap closed

`tests/unit/test-status.sh`: the pin condition grew
`[ "$(w201_bridge 2.0.19)" = 1 ]` — the 2.x arm's above boundary, the
one shape the "every shape" comment claimed without an assertion. The
comment now names its discriminators per arm (above 1.19.0/2.0.19,
below 1.18.32/2.0.17, eq 1.18.33/2.0.18, unknown `""`).

Mutation verification (work committed at `c776ab2` first, tree
restored green after — `sh tests/unit/test-status.sh` rc=0):

- M-b1: 2.x arm `!= lt` → `= eq` (status.sh:995) → bridge pin FAILs
  with the extract dump — the exact mutation that survived review b
  (observed rc=0 there, rc=1 now);
- control: the same mutation on the 1.x arm was already caught
  (verified in review b).

### b W2 (INFO) — comparator-availability guard pinned

`tests/unit/test-status.sh`: new `w201_bridge_nocmp` pin evals the
same extracted block with NO comparator available — `unset -f
advisories_version_cmp` plus an emptied `PATH`, so neither a leaked
function definition nor a host binary of the same name can satisfy
the `command -v` guard (the 0.0.46a F2 environment-dependence class,
RM-0017) — and asserts the carrier verdict survives (1.19.0 → 0,
2.0.18 → 0, `""` → 0). This is the failure path executing, observed
the way production observes it (`_st_bridge_unneeded` is the row
selector).

Mutation verification (committed at `c776ab2`, restored green):

- M-b2: deleting `&& command -v advisories_version_cmp …` from
  status.sh:992 → the nocmp pin FAILs ("bridge guard lost its
  fail-safe") — the false-"not needed" mechanism from review b
  becomes observable.

Class sweep (L2): `grep -rn "command -v advisories_version_cmp" files/`
— exactly one site (status.sh:992); no other extract eval'd by
test-status.sh carries a `command -v advisories_version_cmp` guard
(corrected per #209 c W1 — the adv/capture extracts do carry
`command -v` guards, for sudo/timeout; the c776ab2 message's "no
command -v" copy is immutable history). The wrapper uses the
comparator without an availability guard and still fails safe,
because it sources advisories.sh only when present
(opencode-as-opencode:186) and assigns ADV_VERSION solely inside that
block (:197, the only assignment site) — a missing lib leaves
`[ -n "${ADV_VERSION:-}" ]` (:347) to keep the carrier; no sibling
site (mechanism corrected per #209 c W2).

### b W3 (LOW) — class-sweep record corrected

The a W1 evidence paragraph above was amended (this commit): the
enumerated site list now includes test-wsl-exposure.sh's wiring pins
and corrects the comparator citation to the full block (65–79), with
the observed note that presence-greps have no drift-discriminating
power. Bookkeeping only; snapshots stay immutable — the correction
lives here, review-b.md carries the finding.

### c W1 (LOW) — sweep sentence narrowed to what was swept

The b W2 evidence paragraph above said "the other extracted+eval'd
blocks in test-status.sh (capture, render) carry no `command -v`" —
literally false (review c, verified by independent sed-range
extraction): the adv extract (eval'd at test-status.sh:1438) carries
`command -v sudo` and `command -v timeout`, the capture extract
(eval'd at :1439) carries `command -v timeout`. Amended above to the
substantive claim that was actually swept: no other eval'd extract
carries a `command -v advisories_version_cmp` guard. The twin sentence
in c776ab2's commit message is immutable git history; this amendment
is the correction of record.

### c W2 (LOW) — wrapper mechanism corrected

The parenthetical "(it sources advisories.sh unconditionally)" was
false: the wrapper sources advisories.sh only when present
(`[ -f ]`, opencode-as-opencode:186). Amended above to the verified
mechanism — ADV_VERSION is assigned at exactly one site (:197), inside
that block, so a missing lib leaves it unset and the
`[ -n "${ADV_VERSION:-}" ]` guard at :347 short-circuits before the
unguarded comparator calls (:349–350). Conclusion ("no sibling site")
unchanged; the recorded reason is now the real one.

### c W3 (INFO) — wrapper env-inheritance edge (backlog)

Deliberately not done: the residual edge needs an exported
`ADV_VERSION=1.*/2.*` plus a kit already broken (advisories.sh
missing, loudly warned) — contrived preconditions on pre-existing
code (ccebffb3, 2026-10-03). Effect if it ever fires: empty
substitution satisfies `!= lt` → `_bridge_needed=0` → bridge warning
suppressed (unsafe side), stderr "command not found" the only tell.
If hardened later, the shape is status.sh's comparator-availability
guard. Same backlog family as review b's W2.

### c W4 (INFO) — wiring-pin ranges corrected

"115–117 on the wrapper, 137–139 on status.sh" → "116–117 / 138–139"
in the a W1 class-sweep paragraph above: the version-wiring checks are
exactly those line pairs; each old range included the preceding
unrelated check's continuation line (review c verified by reading the
cited lines).

### c W5 (INFO) — nocmp's `unset -f` stays

Deliberately not done (no change): `unset -f advisories_version_cmp`
in the nocmp pin is a defensive no-op today — the parent never
defines the function (sourcing is confined to w201_bridge's subshell)
— but `command -v` finds functions regardless of PATH, so it is the
only cover for a future harness that sources advisories.sh at top
level (0.0.46a F2 class). Removing it as dead code would weaken the
pin; `PATH=` remains the operative mechanism today.

### c W6 (INFO) — 3.x arm owed when 3.x ships

Deliberately not done: a version matching neither `1.*` nor `2.*`
falls through the bridge case (status.sh:993–996) and keeps the
carrier — the safe side, and no comment or pin claims that shape. A
`3.*)` arm becomes owed only when upstream ships an opencode 3.x with
its own opener story.
