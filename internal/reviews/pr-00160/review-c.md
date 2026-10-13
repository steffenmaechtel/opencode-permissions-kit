# Code Review — opencode permissions kit — 0.0.48, snapshot-c micro wave review (the 0.0.48b fix waves, issue #158)

> Resolution: [resolution.md](resolution.md)

- **Date:** 2026-10-11
- **Reviewer:** GLM-5.3 (OpenCode v2 agent, repo session — continuing the
  0.0.48b chain at the maintainer's request). Two axis subagents on
  GLM-5.3-Flash (security + quality). **Provenance deviation, recorded:**
  the subagents ran in THIS session (which also produced 0.0.48b and the
  fix waves), not in a fresh external session — the maintainer directed
  it this way for this pass ("mach das jetzt dann weiter erstmal so");
  a potential -d pass will run in a new session per the maintainer.
  Every sub-agent finding was re-verified by the lead before entering
  this snapshot; the quality agent could not write its side file
  (read-only role) and delivered in-band — recorded here by the lead.
- **Tree reviewed:** `feature/issue-158-status-messages` @ `9daeccb`
  (VERSION 0.0.48), working tree clean. **Wave under review:** the
  0.0.48b fix waves — `8148784` (W1: DD13 decoupling + 4 exit-contract
  e2e pins), `f4adae7` (W2: fail-loud mktemp + behavioral failure-path
  pins), `777bbb9` (W3–W7: unknown/optional rows uncounted, --short
  guard pins, three wording fixes); the docs commits `3229b31`/`d693cee`/
  `9daeccb` read as riders (resolution rows audited claim-by-claim).
- **Result:** **1 MED, 2 LOW, 4 INFO. Stop rule NOT met — C1 MED owes a
  small fix wave (fix wave 2) before the PR; the follow-up micro pass
  (-d) is reserved for a fresh session per the maintainer.** C1: the W3
  conversion made a *missing/unexecutable managed binary* invisible to
  the verdict — the advisory check is dead, the row falls into the
  uncounted "unknown" class, and `sudo opk status` cannot resolve it
  (same `[ -x ]` gate), contradicting cli.md's "sudo resolves the
  unknowns". Everything else verified: the W1/W2 mechanisms hold exactly
  as claimed, the W3 L2 sweep found no missed conversion candidate, the
  W4 harness is behaviorally faithful, and every new pin discriminates.

## Method

- Full read of the three fix commits' diffs and the touched regions in
  context; the resolution rows for W1–W11 audited claim-by-claim by the
  quality agent (all behavior claims TRUE; two wording imprecisions
  became C3/C5; the host-empirical records — sabotage FAIL counts and
  gate totals — are lead-attested from this session's logs, not
  re-runnable by the read-only agent).
- **C1 traced statically by the lead against the code:** the `installed`
  gate (`status.sh:82–85`) checks `bin/opencode-as-opencode` + the
  `/usr/local/bin/opencode` symlink but NOT the managed binary
  `bin/opencode`; the advisory probe is gated on `[ -x
  "$LIBDIR/bin/opencode" ]` (`:241–249`), so a missing/unexecutable
  binary leaves `ADV_VER` empty and renders the — since W3 uncounted —
  "unknown — probe failed (run: sudo opk status)" row. A sudo re-run
  hits the same gate: the state is a broken install reported "All
  green"/exit 0 even for root, with the security-advisory check dead
  (and the wrapper's runtime exec target gone). Pre-W3 this shape was a
  counted warn (exit 2).
- Unit suite re-run green on this host by both agents independently;
  gates for the fix tips were run by the lead (see resolution): 34
  suites + lint + check-version green, e2e 298/298 + rootless 47/47 +
  ddev 86/86 on both `f4adae7` and `777bbb9`, parallel, zero skips.
- Learnings applied: L2 (the W3 conversion class sweep — every counted
  warn row in status.sh judged individually, no missed candidate), L3
  (commit-message + resolution claim audit — C3/C5 are its findings),
  L4 (pin discrimination re-derived by the agents from the constructs,
  not from the recorded sabotages), L1/L5 (the C1 fix shape below keeps
  the failure loud and adds no root operand).

## Findings index

| ID | Severity | Site | Summary |
|---|---|---|---|
| C1 | **MED** | `management/status.sh:241–271` + `docs/reference/cli.md` | Missing/unexecutable managed binary (`bin/opencode`) falls into W3's uncounted "unknown" class — dead advisory check + broken kit report "All green"/exit 0 even under sudo; cli.md's "sudo opk status resolves the unknowns" overclaims for this shape |
| C2 | LOW | `tests/e2e/run-ddev.sh:864–866` | The healed-side DD13 check (`; ! grep -q …`) can pass vacuously if the second status run truncates the log and dies (negated grep over missing evidence); mitigated by the sibling positive pin, pre-fix shape strictly worse |
| C3 | LOW | resolution W3 row + `777bbb9` message | "the five privilege-unknown rows" — the enumeration lists FOUR unknown rows (+1 optional = five conversions total); the code and pin are right, the resolution wording (fixable) and the immutable commit message carry the miscount |
| C4 | INFO | resolution W2 row | "a control run" exists for the share site only — the row's phrasing can be misread as per-site (hosts/gap are failure-path-only; extraction drift still fails closed) |
| C5 | INFO | resolution W4 row | "presets UI_SILENT exactly like the arg parser" — production full mode leaves UI_SILENT unset, the harness sets 0; behaviorally identical (every guard reads `${UI_SILENT:-0}` at call time), "exactly" overstates |
| C6 | INFO | resolution W3 row | the named "real states" are examples, not the ~20-site census; the 0.0.48c L2 sweep checked every counted warn site and found no missed conversion candidate — the row should say so instead of implying exhaustiveness by example |
| C7 | INFO | `tests/unit/test-status.sh` class-sweep pin | the `=\/dev/null` sweep is var-name-scoped (`_(share_list|hosts_list|gap_roots)`); a future differently-named `$(mktemp) || var=/dev/null` elsewhere would pass it (repo-wide sweep today: no other fallback exists) |

## Findings detail

### C1 (MED) — a broken install can render the dead advisory check "All green"

W3's rule ("the verdict counts findings, not unknowns") is right for the
privilege-unknown shape, but the converted version-probe row also
swallows a shape that is a *finding*: `$LIBDIR/bin/opencode` missing or
not executable. In that state `ADV_VER` is empty without the probe ever
running; the row prints "unknown — probe failed (run: sudo opk status)"
— advice that cannot work (sudo hits the same `[ -x ]` gate) — and since
W3 the row no longer counts. The `installed` gate never checks this
binary, so the report can end "All green"/exit 0 (full and `--short`)
over a kit whose advisory check is dead and whose wrapper would fail at
the first agent session. **Scenario:** interrupted `opk update` or a
manually deleted managed binary on an otherwise healthy install; any
caller, including root, gets green. Fix shape (fix wave 2): split the
gate — missing/unexecutable binary → a COUNTED warn row naming the real
fix (`sudo opk update`); only the binary-present-but-probe-failed shape
stays the uncounted privilege-unknown. Scope cli.md's "sudo resolves
the unknowns" to the privilege shape. Behavioral pin: the extracted
gate block against a fixture LIBDIR without `bin/opencode` must warn
and must not print the "unknown — probe failed" row; control with a
fake binary asserts neither row fires.

### C2 (LOW) — healed-side DD13 check passes vacuously on an empty log

`; ! grep -q "group-write missing" /tmp/dd13-status2.log` succeeds when
the log is missing or empty (a crashed/truncated second status run).
Fail-closed hardening is one `test -s` before the negated grep; the
sibling status1 check pins detection positively, so today's risk is
bounded — recorded LOW, fixed as a rider of fix wave 2.

### C3–C7 (LOW/INFO)

C3: arithmetic correction in the resolution's W3 row ("four
privilege-unknown rows + the optional row — five conversions"); the
commit message of `777bbb9` is immutable history, the correction is
noted in the resolution. C4/C5/C6: resolution wording precision (C4:
name the share site as the control; C5: state the unset-vs-0
equivalence instead of "exactly"; C6: replace the example list with the
sweep statement). C7: accepted residual — recorded; widening the sweep
pattern to any `$(mktemp)`-adjacent `/dev/null` assignment is a
candidate for the next conventions/test pass, not this wave.

## Verified clean (both agents, lead-checked)

- **W1 mechanism and pins:** `&&`-death on rc 2 traced end-to-end
  (count-before-guard, warns→2, check takes the last rc); the `;` fix
  and the run.sh:1150 precedent; all four e2e exit pins discriminate
  (exit-mapping inversion fails both 12k rc checks; verdict-print
  suppression fails both line-count pins); no quoting/precedence trap in
  the single-quoted `test $?` shapes.
- **W2 fail-loudness:** all four mktemp outcome shapes (path+rc0,
  path+rc≠0, empty+rc0, empty+rc≠0) land in scan-or-counted-skip; the
  skip rows count in every shape incl. `--short` (exit 2); no new root
  operand; `continue` scope exact (skips find+report+rm for that root
  only); gap-site else branch verbatim-identical to the pre-wave flow.
- **W3 L2 sweep:** every counted warn row judged — real states and
  dead-scan markers counted, no remaining privilege-unknown/optional
  candidate (the `:376` "mode unreadable" judgment call correctly stays
  counted: the stat failure IS the finding for that caller); socket
  twins traced exactly (agent-user crons get definitive verdicts — the
  agent owns `/run/user/<uid>`); mkcert never counting is documented
  optional-feature semantics.
- **W4 harness fidelity:** every UI_SILENT consumer reads
  `${UI_SILENT:-0}` at call time; source-order and unset-vs-0
  differences are invisible; the pre-existing one-line pin is what
  makes the recorded restore-sabotage credible.
- **W5/W6/W7:** docs/code order, scoped claim, and checkout-first header
  all match the code; conventions.md and ui.sh carry identical W6
  wording; line lengths within file norms; cli.md consistent with the
  flag table.

## Retracted / corrected during verification

- Security agent's socket-twin concern ("masks a down daemon for
  unprivileged callers") — traced to the documented contract: the agent
  user owns the runtime dir and gets a definitive counted verdict; only
  dev-type callers can see green-over-unknown, which is exactly the
  documented privilege-unknown shape with an in-row sudo hint. Downgraded
  to verified-clean with the trace recorded.
- Quality agent's side file: could not be written (read-only role) —
  findings integrated in-band by the lead; noted as a process
  observation, not a finding.

## Recommendation

Fix wave 2 (small): C1 gate split + cli.md scoping + behavioral pin;
C2 `test -s` hardening; C3–C6 resolution wording corrections; C7
record-only. Gates: unit + all three e2e suites (status.sh and
run-ddev.sh change). Then the -d micro pass **in a new session** (the
maintainer starts it) closes the chain per the stop rule.
