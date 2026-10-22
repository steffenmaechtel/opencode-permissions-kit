<!-- review-meta
ID: pr-00211
Snapshot: d
Subject: micro-wave review of the c-wave fixes (11 dispositions, 10 commits)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: snapshot-c commit ce7cbc5)
Diff: ce7cbc5..2350dbe
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 3x GLM-5.3-Flash reviewer subagents — P production hunks, T pins/tests, L ledger/bookkeeping (checkpoints under /tmp/opencode/pr-00211-review-d/checkpoints/, LAUNCH/RETURN 2026-10-21 22:56-23:05 UTC)
-->

# Micro-wave review — pr-00211 snapshot d — the c-wave fix diff

> Resolution: [resolution.md](resolution.md)

Wave-scope pass ("did the fixes break or lie?") over the c-wave: 10
commits `ce7cbc5..2350dbe`, +311/-27 across 14 files, dispositioning
all 11 findings of [review-c.md](review-c.md) (9 implemented, 2
deliberately not done). Three reviewer subagents ran axes P (production
hunks), T (pins/tests), L (ledger); the main agent re-verified every
reported finding against the code before it entered this snapshot —
all 3 survived, none retracted.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| W1 | MED | resolution.md:89 (c W6 row) | the c W6 row cites `bc56a17` — a b-wave commit OUTSIDE the range that never touched the Follow-ups wording; the correction actually landed in `0885c9f` — a ledger row pointing at the wrong history | L1 | yes (merge-base check + git show of both SHAs) |
| W2 | LOW | resolution.md (c W1 evidence, Follow-ups-after-c) | pre-fix line anchors and a stale sweep count: "userdel (:500)" is now :509, "audit rm (:615)" now :644, "closing log (:598)" now :605 (the in-code note shifted lines), and `grep -rn 'run_q' files/` counts 16 at HEAD, not the recorded 15 — the count was exact at the fix commit, then the note's own `run_q` mention moved it | L2 | yes (greps at HEAD + against 47e07f9) |
| W3 | INFO | tests/unit/test-uninstall.sh:714-728 | the audit-block drive stubs no run_q: on a REVERTED block (which calls run_q) the subshell prints "run_q: not found" noise instead of a controlled contract — the pin still goes red for the right reason (the false "removed" absence-assert); current-shape block never calls run_q | T1 | yes (both directions traced) |

Severity counts: **0 HIGH, 1 MED, 1 LOW, 1 INFO** (3 findings).

## Findings detail

### W1 (MED) — a ledger row pointing at the wrong history

The c W6 disposition row ("Follow-ups wording corrected") cites
`bc56a17` — the b-wave's ledger commit (b W16/W25/W29), an ancestor of
the wave base `ce7cbc5`: out of range, and its diff never touches the
Follow-ups paragraph. The wording fix rode `0885c9f` (the c-rows
commit, in range, diff carries the "stay unspaced" correction). This
is the exact class the C axis exists for: the row's claim was true,
its provenance was false. Provenance: wave-introduced (the c-wave's
own ledger). Direction: correct the SHA.

### W2 (LOW) — evidence anchors aged by the same wave

The c W1 evidence block and the Follow-ups-after-c section record
line positions from the fix commit (`47e07f9`), but the same wave's
later in-code note (`0885c9f`) shifted the uninstall.sh lines beneath
them (:500→:509, :615→:644, :598→:605) and pushed the run_q sweep
count 15→16 (the note itself mentions run_q). Every position was
correct when written; none is now — the claims-drift class in
miniature, fixed by dating the anchors ("at the fix commit") rather
than re-pinning them to HEAD (they would age again). Provenance:
wave-introduced.

### W3 (INFO) — revert-path stub noise, discrimination intact

The audit drive's subshell defines prompt_yn/sudo/log but no run_q. A
reverted (pre-c-W1) block calls `run_q sudo rm -rf …` → "run_q: not
found" — the drive still goes red at the load-bearing assert (the
false "Audit log removed." absence check), which is the exact lie the
pin exists to catch; only the failure transcript is noisier than the
userdel drive's (which carries a real-contract run_q stub). The
current-shape block never calls run_q, so the green path is exact. No
action required; recorded so the next pin author knows the asymmetry
is deliberate. Provenance: wave-introduced.

## Retracted / ghost findings

None — all 3 reported findings survived main-agent verification.

## Clean verdicts (axes' verified-clean areas, spot-checked)

- **c W1 production** (P): rc capture abort-proof on both blocks
  (plain assignment in `||` list, no set -e in the file regardless);
  arms byte-shaped like the gpasswd precedent; DRY arms match run_q's
  echo format; the deferred revert-loop note matches the resolution
  verbatim; no new unconditional success claim.
- **c W2 production** (P): `_fsbp_orig_root` captured on the shift
  line, consumed only at the refusal; normalization loop untouched.
- **c W3 production** (P): pure reorder — `_tmp_track` appends to the
  registry without an existence check, the trap's rm -f tolerates an
  absent path; the comment matches the new position.
- **c W7 production** (P): the one-liner gate catches redirect AND
  write failures; the no-second-fi rationale verified TRUE against the
  F17 pin's sed range (ends at the guard's fi); chown/chmod/mv below
  only reached on write success.
- **c W9/W10 production** (P): caps reachable only for digit-only
  ≤10-digit fields — no false rejects (0/65536/100000/4294967295
  boundary pass, 9999999999 rejected); comments match code; the
  fixture count discriminates both directions (T verified: 6 bad + 2
  good at HEAD).
- **Pins corpus** (T): extraction anchors unique and drift-stable
  (outer col-0 fi ends both uninstall extracts; truncation fails loud
  at the extractable gate); fail drives assert WARN + FAILED log +
  absence of the false claim; run_q stub carries the REAL contract;
  sudo stub per-command; W3's line-number compare fail-loud on
  multi-match; W7 pin not vacuous (gate deleted → rc 0 + residue 1 +
  no UIERR → red, reasoned through); W4 tripwire mirrors the W28
  sibling, suite has no set -e (assignment-abort impossible); W5
  `|| true` contains the substitution rc, state printed inside the
  subshell, no stale capture; sandbox clean throughout (scratch-only
  effects, `${F17:?}` guard intact); all pins before their summary
  gates.
- **Ledger** (L): exactly 11 c-rows, ≤120 cols, all other SHAs
  in-range and content-matching; `grep 'if run_q'` at HEAD = 0 (the
  corrected b W1 claim holds); review-c.md's only in-range edit is the
  Resolution pointer (+2); review-b.md untouched; INDEX regeneration
  idempotent (tree clean after the generator); status line matches the
  rows (9+2); every fix/test commit cites the right `#211 c W<n>`;
  not-done rationales consistent with review-c.md.

## Run provenance

- Tree: working tree at 2350dbe (branch release/0.0.55, clean); base
  of the reviewed wave ce7cbc5 (snapshot-c commit) over v0.0.55 @
  ad9467d.
- Reviewer fan-out: 3 subagents (glm-5.3-flash), axes P/T/L,
  checkpoint side files with LAUNCH/RETURN timestamps, window
  2026-10-21T22:56-23:05 UTC. Main agent (GLM-5.3) re-verified all 3
  findings (merge-base + git show for W1; HEAD greps + range greps for
  W2; both revert directions traced for W3); 0 retractions.
- Gates run on this host during this review: `make test` rc=0
  (incl. reviews parity after the INDEX regeneration), `make lint`
  rc=0, `make check-version` rc=0 (stamp 0.0.55). E2e: not re-run —
  `git diff aac8d67..HEAD -- files/` is non-empty since the c-wave
  (production fixes landed), so the b W18 evidence does NOT carry; the
  c-wave's production changes (uninstall arms, opk gate, backend
  validation caps, fs-baseline message, update.sh reorder) owe both
  e2e suites before the release gate per RM-0091 — the same debt
  snapshot c's W11 already names for its own reason.
- Finding provenance split: wave-introduced 3 (all), unstated 0.

## Recommendation

**Ledger-only fix round, then the loop closes.** No production or test
defect: every c-wave mechanism held up (P clean, T's single INFO needs
no code). What the wave broke is its own bookkeeping — one wrong SHA
(W1) and aged anchors/count (W2), both ledger text. Per the stop rule,
a round whose fixes stay in bookkeeping closes the loop: disposition
W1/W2 as ledger corrections and W3 as deliberately not done (no
action), run the unit suite, and the chain ends owing only the
standing e2e-before-release gate (RM-0091).
