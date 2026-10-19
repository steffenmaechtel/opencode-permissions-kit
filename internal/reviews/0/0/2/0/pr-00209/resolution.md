# Resolution — pr-00209 (issue-201 direct --version capture)

Status: open — a-wave fixes touched test code (a W1); micro-wave
review b owed per the stop rule

Chain: [review-a.md](review-a.md) — wave review of the #201 wave
(`4f98611`). Base v0.0.53 @ f07f2fb.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `1dc553f` | 1.18.33/2.0.17 asserted per arm; M1–M3 sabotage red, green restored |
| a W2 (INFO) | **implemented** | `1dc553f` | typo "strenghtens" → "strengthens" |

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
`grep -rnE '1\.1[0-9]\.[0-9]+|2\.0\.[0-9]+' tests/unit/*.sh` — the only
sites are this pin and test-security-advisories.sh's comparator pins
(1.18.32 lt / 1.18.33 eq asserted at its lines 65–68); no sibling gap
left.

Gates after the fix: `sh tests/unit/test-status.sh` green (all
#201/#163/#166/#200 pins PASS), full unit suite green, `make lint`
green, `make check-version` green.

### a W2 (INFO) — typo fixed

`tests/unit/test-status.sh`: "strenghtens" → "strengthens" in the
comment above the bridge pin. Comment-only.
