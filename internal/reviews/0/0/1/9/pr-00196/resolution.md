# Resolution — pr-00196

Chain: birth-PR #196 (`feature/issue-192-root-default-user`).
Snapshot a: [review-a.md](review-a.md) — commit `86376ec`, wave review of
the issue-192 root-gate wave (0 HIGH · 2 MED · 2 LOW · 6 INFO).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a T1 (MED) | **implemented** | `3443d04` | 3 sweep pins flag slash-less form; sabotage red→green |
| a T2 (MED) | **implemented** | `3443d04` | 5 new pins execute every fallback arm; sabotage red→green |
| a T3 (LOW) | **implemented** | `3443d04` | troubleshooting names the user context for `opk uninstall` |
| a W1 (LOW) | **implemented differently** | `3443d04` | docs teach create-a-user; no override flag, by design |
| a S1 (INFO) | **implemented** | `3443d04` | trust-model comment at the gate (install.sh) |
| a S2 (INFO) | **deliberately not done** | — | pre-existing tee class, trusted dev side, fixed payload |
| a M1 (INFO) | **deliberately not done** | — | silent healing is the intent; a notice is taste |
| a T4 (INFO) | **deliberately not done** | — | comment accurate via "recorded"; precision nit |
| a T5 (INFO) | **deliberately not done** | — | canary sound (gate precedes provisioning); rootless 2a noted |
| a T6 (INFO) | **deliberately not done** | — | wording readable; taste-level |

## Evidence detail

### a T1 (MED) — sweep pins catch the slash-less form

All three same-shape sibling pins tightened (L2 sweep of the *pins*, not
just the finding's site — the class here is a too-narrow negative grep):

- `tests/unit/test-install-args.sh` (the status/update/uninstall loop),
- `tests/unit/test-uninstall.sh` (plugin-cleanup pin),
- `tests/unit/test-update-flags.sh` (DEFAULT_HOME pin).

New pattern (identical in all three suites): every
`/home/$DEFAULT_USER` occurrence is flagged, then comment lines and the
getent-failure fallback assignment are subtracted:

    grep '/home/\$DEFAULT_USER' <file> \
      | grep -v '^[[:space:]]*#' \
      | grep -v '|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$'

Sites checked (sweep evidence): 6 slash-less occurrences in `files/`
before the fix — update.sh:442 (comment), :447 (fallback),
status.sh:524 (comment), :532 (fallback), uninstall.sh:296 (fallback),
install.sh:612 (initializer overwritten by getent on the next line —
outside the three pinned files). 0 functional survivors after; the old
`[ -d "/home/$DEFAULT_USER" ]` shape now fails all three suites.
Sabotage: reintroduced that exact line into status.sh → all three suites
FAIL; restored → green (runs logged below).

### a T2 (MED) — probe fallback arms execute

Five pins added, each executing the failure path (L1) and asserting the
fallback VALUE where the value itself is the contract (L4 — a branch pin
cannot tell `|| echo 1` from `|| true`):

- `tests/unit/test-status.sh`: `_hk_run` id-stub now FAILS on an empty
  uid; composed arm (`hk-idfail`) proves sentinel uid 1 reads the hook
  and never raises the uid-0 defect row. Value pin extracts the
  `_st_dev_uid=` probe line and asserts `1` with `id` failing.
- `tests/unit/test-update-flags.sh`: same stub change + composed arm
  (`hku-idfail` fresh rc — hku-home is already hooked, a re-run would
  take the sed branch and stay silent) asserting hooks land and no
  "uid 0" skip. Value pin on the `_du_uid=` probe line asserts `1`.
- `DEFAULT_HOME` resolution (outside the hook block): both lines
  sed-extracted, executed with a stubbed getent — miss arm lands on
  `/home/<name>`, hit arm keeps `/relocated/home`.

Sabotage: `|| echo 1` → `|| true` in status.sh AND update.sh → the two
value pins FAIL (empty sentinel); fallback line deleted from update.sh →
both DEFAULT_HOME arms FAIL; restored → green.

### a T3 (LOW) — troubleshooting fix path

The Fix paragraph now says `opk uninstall` must run from the regular
user too and why (it refuses to start from a root shell) — the exact
friction a T3 named.

### a W1 (LOW) — implemented differently

The doc hint is implemented (create-a-user recipe for root-only distros,
same troubleshooting section). The override flag is deliberately NOT
added: a root developer is unrepairable by design (the issue-#192
framing) — an escape hatch would recreate the defect the wave closes.

### a S1 (INFO) — trust-model comment

Three comment lines above `_root_user_gate` name the
`sudo env SUDO_USER=...` self-override and why it is not defended.

## Sabotage runs (post-commit, tree restored after each)

| Mutation | Suite result |
|---|---|
| status.sh + `[ -d "/home/$DEFAULT_USER" ]` functional line | 3× FAIL (T1 pins) |
| status.sh `|| echo 1` → `|| true` | FAIL (status value pin) |
| update.sh `|| echo 1` → `|| true` | FAIL (update value pin) |
| update.sh fallback line deleted | FAIL (DEFAULT_HOME arms) |
| restored | all green |
