# Resolution — pr-00198 (issue #164 openchamber probe authority gates)

Chain: review-a (snapshot `c771d71`, 0 HIGH / 3 MED / 3 LOW / 5 INFO) →
fix wave `bdcf9ed` (W1/W2/W3/W4/W5/W7) → review-b (snapshot `ebe4474`,
micro-wave review of the fix wave: 0 HIGH / 1 MED / 2 LOW / 1 INFO, no
behavior bug) → b-wave fix `fa938b8` (b B1), b B2/b B3/b B4 corrected
below. Loop closed at b (comment/ledger-only round — stop rule).
Snapshot findings are cited as `a <ID>` / `b <ID>`; the narratives live
in [review-a.md](review-a.md) (incl. the retracted Flash M4 / M-claim —
retracted findings carry no disposition row) and
[review-b.md](review-b.md).

Status: closed

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `bdcf9ed` | `sudo test -L` + `sudo readlink`; 3 pins; sabotage red→green |
| a W2 (MED) | **implemented** | `bdcf9ed` | reproducible 12-hit sweep account; anchors, no line numbers |
| a W3 (MED) | **implemented** | `bdcf9ed` | balanced `[ -f <path> ]` sabotage + uid-0 skip; `[: missing ]` gone |
| a W4 (LOW) | **implemented** | `bdcf9ed` | negative pin widened to bare shape; non-if re-plant → red |
| a W5 (LOW) | **implemented** | `bdcf9ed` | 20-line bound; fi-reindent sabotage → red at extract check |
| a W6 (LOW) | **deliberately not done** | — | order is no behavior claim; `&&` short-circuit + presence pair carry it |
| a W7 (INFO) | **implemented** | `bdcf9ed` | line-number cites → anchors (rode the a W2 rewrite) |
| a W8 (INFO) | **deliberately not done** | — | systemic sudo premise; failure stays loud, never silent-wrong |
| a W9 (INFO) | **deliberately not done** | — | verification record: all three rationales confirmed correct |
| a W10 (INFO) | **deliberately not done** | — | install twin static-only; behavioral coverage via update.sh harness |
| a W11 (INFO) | **deliberately not done** | — | fidelity note, recorded for the next harness touch |
| b B1 (MED) | **implemented** | `fa938b8` | sweep comment: 12th hit dispositioned (uninstall's [ -d /etc/opencode ]) |
| b B2 (LOW) | **implemented** | — | W1 roster completed cross-file in place below (this resolution commit) |
| b B3 (LOW) | **implemented** | — | true uid-0 consequence recorded in the a W3 evidence below (this commit) |
| b B4 (INFO) | **implemented** | — | `16+1` → 16 in the a W5 evidence below (this resolution commit) |

## Evidence detail

### a W1 (MED) — legacy sudoers gate at the rm's authority

`uninstall.sh` legacy gate now reads `if sudo test -L
/etc/sudoers.d/opencode` + `sudo readlink …` (comment cites `#198 a W1`,
same class note as the #164 gates). The removal path itself is unchanged
(marker-gated `case /etc/opencode/*`). Pins riding the fix:

1. dry-run allowlist extended for the two read-only probes
   (`sudo test -L /etc/sudoers.d/opencode`, `sudo readlink …`),
2. call-sequence pin: both probes must appear in the fake-sudo log of
   the real `--dry-run` invocation,
3. static marker-gate pin: `sudo test -L /etc/sudoers.d/opencode` added
   to the legacy-removal `_pin` list.

Sabotage (against commit `bdcf9ed`, construct deleted via sed, restored
after): plain `[ -L ]` re-planted → `FAIL legacy sudoers gate must
probe via sudo` + `FAIL legacy removal pinned: sudo test -L …` →
restore → green. Class sweep for THIS fix (pattern `\[\ -L\ ` + `readlink`
over uninstall.sh): two further same-shape sites — `/usr/local/sbin/
protect-projects.sh` (l.377) and `/usr/local/bin/xdg-open` (l.281), both
gate a `sudo rm` on plain `[ -L ]` + `readlink`. Both sit in
world-traversable standard-0755 dirs and both failure directions are a
benign leftover (dangling helper/shim symlink, no active grant) — left
plain per the same recorded rationale as `update.sh:618/:680` in the
wave's sweep account. The `/etc/sudoers.d` site was the class's one
live-relevant sibling (active grant × plausible 0750) — fixed.

Roster completed per `#198 b B2`: the class has a third
plain-gate→sudo-rm site outside uninstall.sh — update.sh:670-673
(`[ -L /usr/local/bin/xdg-open ]` + `readlink` marker gate →
`sudo rm -f`) — left plain per the same rationale (/usr/local/bin is
0755 by convention, so no developer-blind read; disagreement keeps a
stale shim; no grant rides it). install.sh:2072 (the never-shadow
twin) stays unclaimed as review-a W9 already recorded. Counting them,
the "one live-relevant sibling" disposition above still holds.

### a W2 (MED) — sweep account made reproducible

The test comment now states the literal pattern, its 12 base hits, the
per-site dispositions (fixed / deliberately plain, with reasons), the
two out-of-pattern class sites, and names the `-L` sibling closure
(`#198 a W1`). Line-number citations replaced by anchors (also closes
a W7). Corrected per `#198 b B1`: as shipped the comment dispositioned
only 11 of the 12 hits; the 12th — uninstall's
`[ -d /etc/opencode ]` legacy conf-dir gate — joined the
deliberately-plain list in `fa938b8` (/etc world-searchable, benign
leftover, no active grant). The PR-body text on GitHub still carries
the old 6-site list — maintainer to update the description (out of the
repo's reach).

### a W3 (MED) — balanced sabotage + environment marking

`sed 's|sudo test -f \([^ ]*\) |[ -f \1 ] |'` keeps the sabotaged
command a valid test invocation, so S3's write-branch outcome now flows
from the blind-probe mechanism (`[ -f … ]` false under mode 000 as
non-root), not from a broken-test rc-2 fallthrough. Observable: the
suite output no longer contains `[: missing ]` (present in every run
before the fix). uid 0 has no caller-blind state (CAP_DAC_OVERRIDE), so
S3 is skipped with a marked `SKIP` line when `id -u` = 0 (L4b
environment-marking; house form per test-browser-bridge.sh). S1/S2 stay
unguarded — both pass either way (stub flips the fixture dir open
around read-only probes).

Consequence corrected per `#198 b B3`: review-a's W3 guidance sentence
"without the guard the correction would break root-run suite hosts"
(immutable in the snapshot) is inverted — as root the balanced
`[ -f path ]` succeeds through mode 000, S2's leftover content equals
`_oc_expected`, so the else branch fires the write and S3 passes
VACUOUSLY, not red (same else-branch mechanism the M4 retraction
traced for the broken form). The guard's real effect: converting a
vacuous green into an honest, environment-marked SKIP. This ledger's
own a W3 wording above was already accurate; the note keeps the true
consequence on record so the snapshot's guidance is not re-imported.

### a W4 / a W5 (LOW) — pin hardening

W4: the negative static pin dropped its `if ` prefix — any plain
`[ -f /etc/openchamber/policy.json ]` in update.sh now fails the check
(no legitimate occurrence exists there; install.sh's deliberate opt-in
detection is a different file). Sabotage: probe re-planted in non-`if`
dress → red (the old if-anchored form stayed green — the exact W4 gap).
W5: the extracted block is bounded (≤ 20 lines; actual 16 — the
original `16+1` was off by one, corrected per `#198 b B4`) so a
drifted `^    fi$` anchor over-capturing to EOF fails the extraction
check itself. Sabotage: gate `fi` re-indented → `FAIL … not extractable
(anchor drift?)` → restore → green.

### Verification runs (this wave)

`sh tests/unit/test-update-flags.sh` (108 pass, incl. S1/S2/S3 green,
no `[: missing ]`), `sh tests/unit/test-uninstall.sh` (all pass incl.
the three new W1 pins), `make lint` clean,
`sh tests/unit/test-sandbox-policy.sh` clean. Sabotage matrix executed
against commit `bdcf9ed` (W1 plain-`[ -L ]`, W4 non-if re-plant, W5
anchor drift — each red, each restored, final green re-run). E2e: both
suites owed before merge (wave touches install.sh/update.sh/
uninstall.sh) — run recorded separately by the maintainer handoff.
