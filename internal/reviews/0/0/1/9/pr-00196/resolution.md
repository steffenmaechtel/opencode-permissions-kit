# Resolution — pr-00196

Chain: birth-PR #196 (`feature/issue-192-root-default-user`).
Snapshot a: [review-a.md](review-a.md) — commit `86376ec`, wave review of
the issue-192 root-gate wave (0 HIGH · 2 MED · 2 LOW · 6 INFO).
Snapshot b: [review-b.md](review-b.md) — commit `d479622`, micro-wave
review of the fix wave `3443d04` (0 HIGH · 1 MED · 2 LOW · 8 INFO);
fix wave `8b944c2` (b B1/B2/B6/B7), b B3/b B8 corrected below.
Snapshot c: [review-c.md](review-c.md) — commit `f3620e0`, micro-wave
review of the b-wave fix (0 HIGH · 0 MED · 4 LOW · 6 INFO); fix wave
`4d318b9` (c C1/C2/C6), c C3/C4/C5/C7/C10 dispositioned below, c C8/C9
deliberately not done. Loop closed at c (comment/docs/ledger-only
round — stop rule).

Status: closed

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
| b B1 (MED) | **implemented** | `8b944c2` | install.sh V14 pin swept any-form; old-gate mutation red |
| b B2 (LOW) | **implemented** | `8b944c2` | braced swept ×4; self-default fallback sanctioned; braced mutations red |
| b B3 (LOW) | **implemented** | — | both a-wave sabotage rows corrected in place below (this resolution commit) |
| b B4 (INFO) | **deliberately not done** | — | fail-loud over-match only; the subtraction's strictness is intended |
| b B5 (INFO) | **deliberately not done** | — | counting note (5 blocks / 6 assertions); no claim is false |
| b B6 (INFO) | **implemented** | `8b944c2` | troubleshooting names `wsl -d <distro> -u <name>` / `su - <name>` |
| b B7 (INFO) | **implemented** | `8b944c2` | uninstall fail message carries the survivor diagnostic |
| b B8 (INFO) | **implemented** | — | a-wave cite :612 → :615 corrected below (this resolution commit) |
| b B9 (INFO) | **deliberately not done** | — | comment-only delta owes no e2e; merge-time suites stay the gate |
| b B10 (INFO) | **deliberately not done** | — | harness precedent; stub-fed input; fail-loud if `cut` is absent |
| b B11 (INFO) | **deliberately not done** | — | division of labor documented; recorded so c does not re-flag it |
| c C1 (LOW) | **implemented** | `4d318b9` | survivor comment lists all three classes the pipeline subtracts |
| c C2 (LOW) | **implemented** | `4d318b9` | same completion for the `_up_bad` comment |
| c C3 (LOW) | **implemented** | `4d318b9` | substance via c C1/c C2; commit-msg claim marked superseded below |
| c C4 (LOW) | **implemented** | — | S-label cites replaced by mutation names (this ledger update) |
| c C5 (INFO) | **implemented** | — | superseded-pointer on the a-wave pattern block (this ledger update) |
| c C6 (INFO) | **implemented** | `4d318b9` | doc: from-Windows vs from-inside-root-shell switch paths |
| c C7 (INFO) | **deliberately not done** | — | commit messages immutable; residual scoped below with c C3 |
| c C8 (INFO) | **deliberately not done** | — | no detection gap; anchoring adds false-reds; shared subtraction design |
| c C9 (INFO) | **deliberately not done** | — | vacuous green unreachable (positive anchors fail first); pre-existing |
| c C10 (INFO) | **implemented** | — | cites the #196 c matrix rows instead of re-running (this ledger update) |

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

(Pattern as of the a-wave `3443d04`; superseded by the b-wave form —
four registries, the braced `-e`, the third subtraction — see the
b-wave evidence below. #196 c C5.)

Sites checked (sweep evidence): 6 slash-less occurrences in `files/`
before the fix — update.sh:442 (comment), :447 (fallback),
status.sh:524 (comment), :532 (fallback), uninstall.sh:296 (fallback),
install.sh:612 (initializer overwritten by getent on the next line —
outside the three pinned files; line cite corrected to :615 per
#196 b B8 — the a S1 comment lines shifted it). 0 functional survivors
after; the old `[ -d "/home/$DEFAULT_USER" ]` shape now fails all three
suites' pins when present in their file. Sabotage: reintroduced that
exact line into status.sh → test-install-args FAILs (the status row)
plus 6 collateral execution FAILs in test-status (the line runs inside
the extracted hook block); test-uninstall/test-update-flags stay green
— their pins grep their own files. Corrected per #196 b B3: the
original wording "all three suites FAIL" described runs that were not
executed; review-b's matrix rows for the uninstall.sh and update.sh
old-gate mutations show each per-file mutation fails the matching
suite's own pin (#196 c C4: cite de-labeled — the former "S5/S6"
existed only in the b session's /tmp logs). Restored → green.

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
the extraction precondition FAILs (count 1≠2 — the two arm assertions
never run; corrected per #196 b B3: the original "both DEFAULT_HOME
arms FAIL" misnamed the failing pin — red is red, the suite exits 1);
restored → green.

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
| status.sh + old-gate functional line | 1 T1 pin FAIL + 6 collateral (#196 b B3 corrected) |
| status.sh `|| echo 1` → `|| true` | FAIL (status value pin) |
| update.sh `|| echo 1` → `|| true` | FAIL (update value pin) |
| update.sh fallback line deleted | FAIL (extractable precondition; arms never run — #196 b B3) |
| restored | all green |

## b-wave evidence (fix `8b944c2`, sabotages post-commit)

### b B1 (MED) — install.sh's own V14 pin joins the any-form sweep

The pin at tests/unit/test-install-args.sh keeps its two positive anchors
(the verbatim initializer and the getent line) and replaces the
trailing-slash-only negation with the sweep pipeline: flag every
literal/braced occurrence, subtract comments and the verbatim
initializer line. Sabotage (old gate shape dropped into install.sh):
the pin FAILs quoting the line; restored → green.

### b B2 (LOW) — braced spelling swept; one sanctioned survivor added

All four registries (install pin, sibling loop, `_un_bad`, `_up_bad`)
now also match `/home/\${DEFAULT_USER`. Implementation follow-up
(README rule 6, expected reading for c): the first green run FAILED —
the brace pattern caught status.sh:155
`_oc_home="${_oc_home:-/home/${DEFAULT_USER:-$USER}}"`, the openchamber
getent-failure fallback (positively pinned by the 0.0.47c C1 rows) —
a sanctioned site in braced spelling. Added subtraction: the braced
self-default fallback shape (exact, EOL-anchored) in the three
management-file sweeps; the install pin keeps its minimal survivor set.
Live tree: exactly one brace occurrence in `files/` (status.sh:155,
subtracted); zero functional survivors anywhere. Sabotage (a braced
functional line in install.sh) and (a braced functional line in
status.sh) both FAIL red, proving the subtraction does not
blanket-whitelist braces; restored → green. Comments reworded to claim
exactly what the patterns deliver
(literal + braced spelling, every slash form; mid-quote remains
unenumerated residual, b B2 detail).
The other two registries' braced discrimination (uninstall.sh,
update.sh mutations) is proven by the #196 c matrix rows (c C10) —
the b-wave matrix above covered install and status only. The
"comments reworded" claim itself held for test-install-args.sh's
blocks only; the uninstall/update comments caught up with `4d318b9`
(#196 c C1/c C2/c C3).

### b B6 / b B7 (INFO) — doc clause, fail-message diagnostic

troubleshooting now names how to switch into the created account
(`wsl -d <distro> -u <name>` / `su - <name>`); the uninstall sweep
pin's fail message carries `(${_un_bad:-no getent})` like its siblings.

### b-wave sabotage matrix (`8b944c2`, tree restored after each)

| Mutation | Suite result |
|---|---|
| install.sh + `[ -d "/home/$DEFAULT_USER" ]` | FAIL (b B1 pin, line quoted) |
| install.sh + braced functional line | FAIL (b B1/B2 pin) |
| status.sh + braced functional line | FAIL (sibling-loop status row) |
| restored | all four suites green |

Extended by the #196 c pass (c C10): uninstall.sh and update.sh braced
mutations each FAIL their own suite's pin — all four registries
discriminate (matrix in [review-c.md](review-c.md)).

## c-wave evidence (fix `4d318b9` + this ledger update)

### c C1 / c C2 / c C6 — comments and doc clause

The two management-sweep comments now enumerate all three survivor
classes their pipelines subtract (mirroring the install-args wording);
the troubleshooting switch clause names the from-Windows and
from-inside-the-root-shell paths. Comments/docs only — the two suites,
`make lint` and the full `make test` are green on `4d318b9`; no pin,
pipeline or behavior change, so no new sabotage owed (L1/L4).

### c C3 + c C7 — commit-message wording (in-ledger correction)

Commit messages are immutable history, so the correction lives here:
"comments reworded to claim exactly what the patterns deliver"
(`8b944c2`) held for test-install-args.sh's blocks only — the other
two sites said "only"/"nothing else" until `4d318b9` (c C1/c C2);
"close the pin-class sweep" is scoped by the recorded mid-quote
residual (b B2 detail above — no occurrence in `files/`, house style
unbraced).

### c C4 — S-label cites de-labeled

The former "S1 red→green"/"S2/S3 red" (dispositions rows), "the
b-wave matrix (S5/S6)" (a T1 correction) and "Sabotage S1/S2/S3"
(b-wave evidence) referenced labels that exist in no committed matrix —
review-b.md's S1–S6 point at its session's /tmp logs, and the b-wave
section reused S1–S3 for different mutations. All cites now name their
mutations; every sabotage reference is resolvable from the repo
(review-b/review-c matrices plus this file).

### c C5 — a-wave pattern block marked historical

The a T1 pattern block keeps its historical text plus a
superseded-pointer to the b-wave form (four registries, braced `-e`,
third subtraction).

### c C8 / c C9 — deliberately not done

C8: every line exempted by the third subtraction ends in the exact
sanctioned self-default assignment (probed, #196 c C8) — no in-scope
regression can hide there, while anchoring would false-red legitimate
prefixed forms (`export X=…`, `cmd && X=…`); the pipe-var fallback
subtraction shares the left-unanchored shape by design. C9: the
vacuous-green scenario is unreachable — a missing swept file fails the
positive anchors first (probed); pre-existing pipeline shape.

### Stop rule

This round's dispositions touched test-file comments, docs and
resolution bookkeeping only — no review-relevant code
(review-concept.md "The loop and the stop rule", 0.0.45f precedent).
The chain closes at c: snapshots a–c, 31 findings dispositioned,
zero MED/HIGH open.
