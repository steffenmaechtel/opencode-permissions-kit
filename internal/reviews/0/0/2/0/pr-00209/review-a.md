<!-- review-meta
ID: pr-00209
Snapshot: a
Subject: issue-201 fix wave — status.sh direct --version capture ends the sudo-advice dead end
Scope: wave
Base: v0.0.53 @ f07f2fb
Diff: f07f2fb..4f98611 (single commit: status.sh capture block + render re-arms, test-status.sh pins, docs/reference/cli.md)
Date: 2026-10-20
Reviewer: GLM-5.3 (external /review session — single-pass main agent, no subagents; verification duty held in-session)
-->

# Wave review — pr-00209 snapshot a — issue-201 direct-capture wave

Wave question: did the fixes break or lie? Wave = `4f98611`
(`f07f2fb..4f98611`, 3 files): the #163 direct probe now CAPTURES the
`--version` stdout it used to discard and feeds it through the same
strict extract as the sudo path, so the advisory verdict and every
`ADV_VER` consumer answer at the caller's own privilege; the render
chain gains a residual informational arm (rc 0, no parsable version)
and the dead-end "sudo opk status" advice shrinks to the #166 cell.

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | new bridge pin claims "1.18.33+ unneeded" but never asserts the 1.x eq boundary (1.18.33 itself) — a `!= lt` → `= gt` mutation in the 1.x arm stays green (verified); 2.x lt boundary (2.0.17) likewise unasserted | wave-introduced |
| W2 | INFO | typo "strenghtens" in the new test comment (tests/unit/test-status.sh:1361) | wave-introduced |

No MED/HIGH findings.

## W1 (LOW) — bridge pin does not discriminate the 1.18.33 boundary it names

The new pin's pass message claims `1.18.33+/2.0.18+ unneeded`, but the
assertions exercise `1.19.0` (gt), `2.0.18` (eq, 2.x arm), `1.18.32`
(lt) and `""`. The 1.x arm's eq case — `1.18.33` itself — is never
asserted, and no other suite pins the status-side arm
(test-security-advisories.sh pins only the comparator's `eq` semantics,
not this arm's use of it).

Verified by mutation (tree committed at `4f98611`, restored after):
changing status.sh's 1.x arm `!= lt` → `= gt` (line 994) leaves the
entire suite green. Production effect of that undetected regression: an
exactly-1.18.33 install falls through to the carrier checks instead of
the "not needed" row — a mislabeled row, not a broken login, hence LOW
(the test-vacuous/L4 class, not a shipped bug). The same gap lets the
boundary constants drift (1.18.33→1.18.34 and 2.0.18→2.0.17 both stay
green on the current assertion set).

Suggested fix, one line inside the existing `if`:

```sh
… && [ "$(w201_bridge 1.18.33)" = 1 ] \
&& [ "$(w201_bridge 2.0.17)" = 0 ] && …
```

(`2.0.17` closes the symmetric 2.x lt/boundary-constant gap; `1.18.33`
is the load-bearing addition.)

## W2 (INFO) — typo in new test comment

`tests/unit/test-status.sh:1361`: "strenghtens" → "strengthens".
Comment-only, no behavioral weight.

## Verified clean (commit-vs-claim audit)

- **Render chain, all shapes re-derived:** capture runs only when
  `[ -z "$ADV_VER" ] && [ -x … ]`; rc≠0 → counted broken-warn
  (unchanged #163 semantics), rc=0+parsable → real verdict, rc=0+
  unparsable/empty → informational without sudo advice, `[ -x ]`-denied
  → #166 row keeps the advice (sudo genuinely resolves that shape). No
  arm is reachable that shouldn't be; ordering of the elif chain is
  sound under `set -u`.
- **Class sweep claim holds:** `run: sudo opk status` in `files/` =
  4 sites; socket twins (540/564, `/run/user/<uid>` mode 700) and
  mkcert CA (750) are privilege-real. The version row is the only
  dead-end removed.
- **Docs claims match code** (cli.md 355–364); no other doc carries the
  old wording (`probe failed` absent from `docs/`). Same-PR docs rule
  satisfied.
- **L1 fail-loud:** every new fail-soft construct (`|| ADV_DIRECT_RC=$?`,
  extract `|| true`, `2>/dev/null`, probe pipe) has a failure-path pin
  that executes and observes the production row.
- **L4 sabotage (3 mutations):** discard-stdout → headline pin FAILs
  (caught); residual row regains advice → 2 pins FAIL (caught); the W1
  mutation survives (the finding above).
- **Pins sit before the summary gate**; exec bits unchanged (755 both
  files); `make lint`, `make check-version`, full unit suite (all
  `tests/unit/test-*.sh`) green; e2e correctly not owed (status.sh
  rendering is outside the install/update/wrapper/backend DoD set).
- **Comment claims:** 750 root:group deployment confirmed (install.sh
  :1104, update.sh:909); "sudo -n collapses refused/password-required
  into rc 1" matches the code (sudo rc stays unread).

## Provenance, gates, recommendation

- **Finding provenance:** W1, W2 — `wave-introduced` (both sites are
  new in this diff).
- **Gates run:** check-host, `test-status.sh` (all #201/#163/#166/#200
  pins PASS), full unit suite, `make lint`, `make check-version`;
  3 sabotage mutations with restore.
- **Recommendation:** fix wave may start — address W1 (one-line
  assertion) and W2; neither blocks. Per the stop rule, a W1 test-only
  fix still owes a micro-wave review (b).
