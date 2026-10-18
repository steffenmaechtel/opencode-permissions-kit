# Resolution — pr-00199

Case: issue #165 feature wave (birth PR #199). Snapshot a: wave review of
`28c2e0e`. This resolution records the a-wave dispositions; the fix wave
lands as one commit (`696e3a3`) and owes snapshot b (fresh session per
the rotation rule — the fixing session does not review its own fixes).
Snapshot b (`8ece3e5`) reviewed that fix wave (0 HIGH, 0 MED, 3 LOW,
3 INFO); its dispositions are the `b` rows below — comment/docs/
bookkeeping-only, so the chain closes with this round per the stop rule
(no review-relevant code touched).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `696e3a3` | handover elif row; 3 arms (devrun/agent-uid/control); S1 red |
| a W2 (MED) | **implemented differently** | `696e3a3` | uid condition executed (carved, #196 pattern); S3b/S4b red |
| a W3 (LOW) | **implemented** | `696e3a3` | git fallback row + noop stub retired; 2 arms; S2 red |
| a W4 (LOW) | **implemented** | `696e3a3` | docs: six families, honest row-naming claim |
| a W5 (LOW) | **implemented** | `696e3a3` | class-set ratchet pin; S5 red |
| a W6 (INFO) | **deliberately not done** | — | anchors fail loud by design; brittleness documented in snapshot |
| a W7 (INFO) | **deliberately not done** | — | benign evaluation-order delta; no observable behavior change |
| a W8 (INFO) | **deliberately not done** | — | pre-existing loud-crash class; #165 scopes "missing" only |
| a W9 (INFO) | **deliberately not done** | — | record-only finding; sibling scripts clean |
| b F1 (LOW) | **implemented** | `47c83dd` | 0b comment states the counted-row contract, points to g2 |
| b F2 (LOW) | **implemented** | `561efc1` | errata block: re-measured counts, mutation shapes, 13 pass lines |
| b F3 (LOW) | **implemented** | `47c83dd` | docs qualifier names the family preconditions; comment widened |
| b F4 (INFO) | **deliberately not done** | — | wording-scoped ratchet; boundary documented in the pin comment |
| b F5 (INFO) | **deliberately not done** | — | contrived override shape; real drift classes pinned by d3 |
| b F6 (INFO) | **deliberately not done** | — | no defect; double-id record only |

## Evidence detail

### a W1 (MED) — ddev-handover row

Mechanism: the guard keeps its compound shape
(`[ -f "$_st_dhl" ] && [ uid != agent-uid ]`) and gains the sibling
`elif` on the uid condition alone — developer-uid run + missing lib
renders `ui_kv_warn "ddev share" "not checked — kit file
sh/ddev-handover.sh missing (fix: sudo opk update)"`; agent-uid runs
stay row-free (the scan is developer-only anyway). Checkout-first is
untouched: a checkout run with its own `sh/ddev-handover.sh` still uses
it and renders no row.

Pins (`tests/unit/test-status.sh`, section g): extraction of the whole
block from `^_st_dhl=` (the harness runs from `tests/`, so the
checkout-first candidate never exists and the LIBDIR fixture decides),
missing-lib arm (row fires), agent-uid arm (empty output), control
(fixture lib + `ddev_reshare_needed` stub + project root with `.ddev`
renders the real group-write row, no "not checked"). Sabotage S1
(delete the row): 6 FAILs including the class-set pin.

### a W2 (MED) — readiness semantics pinned by execution

Deviation from the snapshot's suggested shape (hence "implemented
differently"): driving the full chain to `true` is impossible
host-independently — the two `/mnt/c` file tests are host-fixed false on
CI and cannot be stubbed (dash rejects `[` as a function name: "Bad
function name", verified). Implemented instead:

- the REAL uid condition is carved out of the real readiness line by sed
  (greedy capture anchored on `; then$` — the `]; then` form eats the
  closing bracket, learned the hard way) and EXECUTED with `id` stubs
  (the #196 `_st_dev_uid` sentinel-pin pattern): agent-uid → unready,
  developer-uid → ready, unresolvable agent user → sentinel 1 → ready;
- the extraction itself is pinned (`grep -qF` of the exact condition,
  which includes `!=` and `|| echo 1`), so wording/semantics drift in
  the source line fails before the arms even run;
- a full-chain execution smoke evals the real readiness block on any
  host and asserts it still yields a boolean under `set -u` (the value
  stays host-dependent by design — the two file tests answer whatever
  this host answers).

Sabotage: S3b (`!=` → `=` on the hosts line): 4 FAILs (extraction pin +
all three arms). S4b (sentinel dropped): extraction pin fails. First
S3/S4 attempt mutated the wrong site — the handover guard carries the
identical condition text (a W1's own elif); re-run with the
`${DEFAULT_USER:-}` prefix as anchor.

### a W3 (LOW) — git-floor row

Mechanism: the `git_status_row() { :; }` noop stub is retired; the Core
call site runs `if command -v git_status_row …; then git_status_row;
else ui_kv_warn "git" "not checked — kit file sh/git-check.sh missing
or outdated (fix: sudo opk update)"; fi`. `command -v` (not the old
file-existence guard) is the truthful signal — it also covers a
deployed lib too old to define the helper ("missing or outdated"). The
stale fail-soft comment at the resolution block is rewritten to the
broken-kit ruling. Maintainer decision (2026-10-18): row over note, to
close the class with no odd-one-out.

Pins (section g2): extraction (`sed` address with escaped `/` — the
`>/dev/null` slashes terminate an unescaped address regex, learned the
hard way), undefined-helper arm (row fires), defined-helper control
(row renders, no fallback). Sabotage S2: 5 FAILs including the set pin.

### a W4 (LOW) — docs alignment

`docs/reference/cli.md`: the family enumeration grows to six (advisories,
terminal hook, migration-gap, Windows-hosts, ddev-share resharde scan,
host git floor); the row-naming claim now says the row names the missing
kit file "— the advisories row names the skipped security checks
instead". The advisories row text itself stays as the issue #165 spec
prescribed it.

### a W5 (LOW) — class-set ratchet

The keep-as-is pin greps the class marker
`kit file sh/<name>.sh missing` over status.sh and compares the sorted
unique set against the exact five-site expectation (handover, hosts,
migrate, terminal, git-check). Any over-sweep in this wording — any
file — fails with the actual set printed; a deliberate sixth site is a
ratchet edit (`_k165_want`). Sabotage S5 (bogus bridge over-sweep row):
6 FAILs (the advisories anchor moved too, and the set pin fired).

### b F2 (LOW, snapshot b) — evidence-count errata (re-measured)

Snapshot b's main agent re-executed the sabotage matrix above against
the committed tree with MINIMAL mutation shapes (delete exactly the
named line; flip/drop on the readiness line :853; insert one bogus
row). Measured vs recorded:

| Mutation (minimal shape) | Measured in snapshot b | Recorded above |
|---|---|---|
| S1 handover row line deleted | 5 FAILs (extraction, 3 arms, set pin) | "6 FAILs" |
| S2 git fallback row line deleted | 4 FAILs (extraction, 2 arms, set pin) | "5 FAILs" |
| S3b `!=` → `=` on :853 | 4 FAILs | 4 ✓ |
| S4b sentinel dropped on :853 | 1 FAIL (extraction pin) | 1 ✓ |
| S5 bogus bridge row inserted | shape-dependent: 1 at an inert insertion point, 3 in the claims-axis /tmp copy, 6 here (the advisories anchor moved in this run) | "6 FAILs" |

All five red, all restores green — the pins discriminate; the deltas
come from mutation shape (the a-wave runs deleted larger constructs /
hit a moved anchor), which the entries above did not spell out.
Pass lines: the fix wave adds 13 `pass "` lines (d3:5, g:4, g2:3, f:1),
not 10 — 10 is right only when the three extraction pins are excluded;
32 pins carry the `165:` label, 131 pass lines total in the suite.

### Class sweep of the fix wave (L2)

Pattern `kit file sh/[a-z0-9-]*\.sh missing` over `files/`: exactly the
five intended rows in `management/status.sh`, none elsewhere. Full
guard inventory of status.sh after the wave: ui.sh loud-exit; git-check
row (W3, this wave); advisories/terminal/migrate/hosts rows (feature
wave `28c2e0e`); handover row (W1, this wave); wsl-browser-bridge
red-by-design; log.sh silent-by-design. No undefended same-shape site
remains — the class is closed, and the set pin holds it closed.

### Gates

`sh tests/unit/test-status.sh` green (all 165 pins incl. the 10 new
pass lines); `make test` green (full unit suite + sandbox policy);
`make lint` green; `make check-version` green. Sabotage matrix 5/5 red
(S1, S2, S3b, S4b, S5), restore green, tree clean against `696e3a3`.
e2e not owed (status.sh is not in AGENTS.md's e2e list; no healthy
install gains a row).
