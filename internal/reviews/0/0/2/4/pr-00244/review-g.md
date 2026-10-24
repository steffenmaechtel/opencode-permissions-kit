<!-- review-meta
ID: pr-00244
Snapshot: g
Subject: issue-223 fix-wave 6 dispositions (micro-wave review of the f-round fixes, solo pass)
Scope: wave
Base: 0.0.56+71 @ d817f43 (VERSION 0.0.56)
Diff: d817f43..bb3c19d
Date: 2026-10-25
Reviewer: GLM-5.3 house session (opk-review-pass skill), SOLO — no reviewer subagents (the maintainer's commission for this round: single-session pass over the fix diff); session G of the maintainer's snapshot-letter counting (fix commits 97b55b9/bb3c19d authored by the closed F-session, closed before this pass)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review g — micro-wave review of the fix wave (pr-00244), solo pass

Round g over the f-round fix diff `d817f43..bb3c19d` (two commits:
`97b55b9` the dispositions — opk's openchamber-secure settings edit
moves its guard INSIDE the sudo context (`sudo -u "$_oc_duser"
sh -c 'command -v python3 … && exec python3 "$@"'`, one resolution
PATH for guard and execution, heredoc stdin passthrough, argv
byte-identical), the count grep `|| true`-guarded with the comment
trued to the mechanism, `_p3old` strips comment lines before
counting, the dup-pin span narrowed to `[^#]*`, the first-token-`+=`
double documented with both collateral catches, `TPSWERR` joins the
in-block `rm -rf`, ddev-terminal's rc-contract comment states the
true no-acting/set -e/fail-safe shape, cli.md names the three
diagnostic sites in report order, the count-pin labels say
assignment/append, and the wave-5 record corrections (Q1/Q2 markers);
`bb3c19d` bookkeeping — f-row SHA fills, wave-6 e2e discharge,
sabotage record, a disclosed ratchet near-miss). The wave answers
review-f's 12 unique findings: W1–W5, S1, Q1–Q4 implemented; S2/S3
deliberately not done (reasoned rows).

Commission shape: the maintainer commissioned this pass WITHOUT
reviewer subagents (solo main-session execution) at an 8-minute
window — micro-wave budget over the round's diff. The redundancy
axis is therefore collapsed to ONE context (this session); recorded
here per the skill's calibration disclosure. Rotation state: the
F-session is closed; this pass ran with fresh context over its fixes
(per the resolution's L6 entry and the maintainer's commission) — no
rotation deviation, RM-0110 recovery not applicable. Review-f left
no open findings beyond the dispositions this wave implements.

Tree `bb3c19d`, clean (`git status --porcelain` empty before and
after; no mutation window — no sabotage run this pass, the tree was
a read substrate throughout).

## Findings index

3 findings, all verified as reported; none retracted, none dropped.

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| W1 | LOW | new dup-span comment claims "no real double can carry # between its tokens" — false for a QUOTED `#` in the first value (`_py3_imports='a#b'; _py3_imports='c'` matches the old regex, not the new `[^#]*` span); the shape is collateral-caught (count 2 / lib-coverage reds via the module-name filter), not by the mechanism the comments document; the e-W4 residual list doesn't name it | wave-introduced |
| Q1 | INFO | kit-cli block-extraction pin's FAIL label says "block extractable" but its condition also hard-requires python3 — a python3-less host reds a pin asserting non-extractability (label/assertion mismatch, the f-Q4 class; bounded by check-host's make-test contract) | wave-introduced |
| S1 | INFO | opk openchamber-secure grep-then-edit false success: the grep needle can match `"opencodeBinary"` as a VALUE while the heredoc python deletes only the KEY and exits 0 → ui_success "settings pin removed" with the string still present — identical pre-wave, contrived trigger, backlog-style record (f-S2 precedent) | pre-existing |

Provenance split: 2 wave-introduced, 1 pre-existing. Severity: 1 LOW,
2 INFO — no MED/HIGH; the stop rule's severity bar is not tripped by
this snapshot. Loop state stays the next round's / maintainer's call.

---

## Solo review body (mechanical sweep + security + quality, one session)

# Solo review — wave diff `d817f43..bb3c19d` (fix wave 6, pr-00244 / issue #223)

## Details

### W1 — LOW: the W4 fix's `[^#]*` span is blind to quoted-`#` real doubles, and its comment overclaims

`tests/unit/test-install-args.sh` (dup pin + comment, tree `bb3c19d`):

```sh
    # The dup span [^#]* cannot cross a comment start (#244 f W4): a
    # trailing comment naming the token after a legitimate assignment
    # stays green, and no real double can carry # between its tokens.
    _p3dup="$(grep -nE "^[[:space:]]*_py3_imports=[^#]*_py3_imports(\+=|=)" "$INSTALL" || true)"
```

Probe (this pass, /tmp/opencode/pr-00244-g/probe/w4.sh): the shape
`_py3_imports='a#b'; _py3_imports='c'` — a real same-line double
whose first value contains a QUOTED `#` — matches the OLD regex
(`.*` span: 1) but NOT the new `[^#]*` span (0); the count pin sees
1. A quoted `#` is data, not a comment start, so the comment's
universal "no real double can carry # between its tokens" is false;
the W4 fix traded a trailing-comment false-red for a quoted-`#`
false-green on exactly the pin whose job is same-line doubles.

Why LOW, not higher: the shape cannot sail silently. Next to the
real assignment the count pin reds (found 2); as the sole line the
extraction yields `a#b`, which fails the module-name filter
(`grep -E '^[A-Za-z_][A-Za-z0-9_.]*$'`) upstream of the lib-coverage
comparison, so the coverage pin reds on every shipped import missing
from the gate list. But the catching mechanism is neither the dup
pin nor the "starves the extraction" path the W3 sentence documents
(the extraction SUCCEEDS on this shape) — and the e-W4 residual
enumeration a few lines below names only backslash-continuation and
eval-built shapes. Value domain today: install.sh:573 carries a
python import list, where a quoted `#` is contrived — the defect is
the comment's false universal plus the unnamed residual, the same
class f rated LOW for W3/W4.

### Q1 — INFO: block-extraction pin label vs condition

`tests/unit/test-kit-cli.sh` (the asymmetry-arms guard):

```sh
if [ -n "$OCW2_BLOCK" ] && command -v python3 >/dev/null 2>&1; then
    …
else
    echo "  ${RED}FAIL${NC}  settings-edit block extractable for asymmetry arms (#244 f W2)"
```

A host without python3 reds a pin whose label asserts the block is
not extractable — the label describes one conjunct, the condition
checks two (the f-Q4 class: label and assertion describe different
things, here inverted). Bounded: check-host makes python3 a make-test
precondition, the L4 record names the hard-require, and the failure
is loud. INFO for the record.

### S1 — INFO: grep-then-edit false success (pre-existing)

`files/opencode-permissions-kit-lib/bin/opk:298-323`: the outer
`grep -q '"opencodeBinary"' "$_oc_settings"` can match the quoted
literal as a JSON VALUE (`{"note": "opencodeBinary"}`), while the
heredoc python deletes only the top-level KEY (`isinstance(d, dict)
and "opencodeBinary" in d`) and still exits 0 → the then-branch
prints `ui_success "settings pin removed from $_oc_settings"` with
the string still in the file. Identical in the pre-wave shape (the
wave moved the guard, not this contract); trigger contrived (opencode
itself writes the pin as a key, and the e2e run.sh settings-pin-gone
assert covers the real flow). Recorded backlog-style per the f-S2
precedent — the site the wave just rewrote is the right place to
have it on file.

## Verified clean (no finding)

- **f W2 headline change (opk:299-322)**: script string fully
  single-quoted — nothing expanded inside it; operands pass as argv
  (`$@`, not `$*`) so the inner `exec python3 "$@"` yields a
  byte-identical python3 argv to the pre-wave `python3 -
  "$_oc_settings"` (`$0=opk-settings-edit` cosmetic); the `<<'PYEOF'`
  heredoc attaches to the sudo command and sh passes stdin through
  the exec, so the `-` operand still reads the script (arm B's
  fixture edit through the REAL interpreter proves the whole path).
  rc contract: inner guard fail → `&&` chain rc 1 → sh/sudo rc 1 →
  the same two-line ui_error else the pre-wave arm A reached, now
  without sudo's not-found noise; arm B runs the edit instead of
  falling to the hand-edit instruction. Pattern sanctioned:
  install.sh:768 (guard-inside-sudo'd-sh precedent), tui-plugin.sh:80
  (the wave-5 sibling), opk:368 (0.0.38 C23), fs-baseline.sh:276
  (xargs) — no new `sh -c` class member. Root context unchanged
  (opk root-runs; `-u` drops to the dev user; no sudoers boundary
  crossed — f's S-axis analysis carries, the wave only moved the
  guard into the same sudo argv).
- **The four kit-cli pins**: extraction `/^            fi$/` ends at
  the REAL fi (opk:322; comment start :299 is the file's only
  `#244 f W2` line; no earlier 12-space `fi` — python body indents
  0-8); block = 24 lines ≤ 32 (anchor-drift bound); static pair
  verified against my own read (the `sh -c ` + guard literals
  present; no `^ +if command -v python3` caller-side line); the
  functional arms' mechanics traced — PATH-fixing sudo shims strip
  `-u`, arm A's noisy python3 exists ONLY in the caller PATH (a
  caller-side guard revert runs it or leaks "not found" — either
  reds), arm B's farm carries the real interpreter and asserts
  `W2:success` + opencodeBinary gone + `"port": 3000` preserved
  (`json.dumps(indent=2)` keeps that exact rendering); fresh
  fixture per run (no cross-arm contamination); farms/shims under
  suite scratch; pins sit before the tally. All four passed in this
  pass's gates run (make test, test-kit-cli included). The recorded
  sabotage (guard revert → 4 pins red with the designed mechanisms)
  is post-commit record — deferred, text-consistent with the diff
  and the pin shapes read here.
- **f W1**: probe (probe/w1.sh) — guarded: `survived asn=0` and the
  FAIL path records "found 0, want 1"; unguarded (pre-fix shape):
  abort rc 1. Comment trued to the mechanism it previously
  overclaimed ("Both greps are guarded" → now states the abort
  mechanics). Zero-path sabotage record matches the probe.
- **f W4 + sibling sweep**: `_p3old` comment-strip probe — clean
  tree 1 (both shapes), commented gate: NEW 0 / OLD 1 — the
  commented-sabotage survivor trap closed exactly as recorded; the
  recorded isolation probe (old 1 / new 0 / clean 1) matches mine.
  Trailing-comment false-red closed (probe: old 1 / new 0), true
  same-line doubles still red (with and without trailing comment).
  The `:827` URL-grep disposition (commented-URL two-step false-green
  bounded and named, not fixed) read back — reasoning holds.
- **f W3**: the documented blind shape re-probed (first-token-`+=`
  double: new 0 / old 0 / count 1) with both collateral catches
  named at the site — comment matches behavior.
- **f W5**: `rm -rf "$TPSW" "$TPSWERR"` in-block; merged trap
  backstop unchanged. Class sweep (L2 record) read: every block
  removes what it creates; the new ocw2 block removes its farm dir.
- **f S1**: ddev-terminal comment now states the defensible contract
  (plain `$()` assignments DO carry the rc, but only under `set -e`,
  which the interactive rc-file context does not run; no caller
  ACTS on it; the file never exits the parent shell; 127→0 is the
  fail-safe direction) — each clause matches f's verified caller
  enumeration (:99-103, :122, :148, :172) and the e-round's S2
  nuance.
- **f Q3**: cli.md now enumerates the three sites in report order
  (advisory feed, first scan, leak scan); status.sh untouched by
  this wave, so f's order verification (:542 < :827 < :1341) carries
  — spot-checked myself (`_st_py_checked` cache at :214-215 inside
  `_st_ddev_scan`, `advisories_ids` consumer at :553).
- **f Q4 / Q1 / Q2**: labels say "assignment/append line" (regex
  `\+?=` semantics); correction markers in place and accurate —
  resolution :734 (Q2: 12 is the CLASS count; 15 executing lines /
  13 site units) and :750 (Q1: the "stays green" held only for the
  isolation probe; composition reds by design).
- **S2/S3 not-done rows**: reasoned and recorded (uninstall:316
  backlog precedent; exact-name basename exclusion is the correctly
  scoped build, and the new kit-cli farm comments document purpose).
- **Class sweeps (this pass's own)**: `grep -rn "command -v python3"
  files/` — exactly the 10 recorded sites; tui-plugin:80 + opk:305
  the sh -c pattern, the other 8 single-context, uninstall:316
  unguarded (S2) — no caller-guard/different-context site remains.
  `sh -c` sites in files/: 5, all sanctioned (listed above).
- **Bookkeeping bb3c19d**: resolution-only (+45/−11); SHA fills (11
  references to 97b55b9); e2e tails re-read by this pass —
  ../logs/e2e-20261025-000326.log "Passed: 309",
  ../logs/e2e-rootless-20261025-000326.log "Passed: 47" (the
  lone-first-run cache confirmation matches the parallel-run
  precondition in AGENTS/CONTRIBUTING); the `_p3old` sabotage
  eval-confound record (mutation red via the wrong mechanism, pin
  discrimination probe-verified in isolation) is internally
  consistent and matches this pass's probe numbers; the ratchet
  near-miss (rc masked by a `| tail`, caught and amended pre-push)
  is disclosed in the record — process debt discharged by the
  amended gate-green HEAD.

## Coverage

Covered: the full wave diff (7 files) — opk's rewritten compound in
full-context read with quoting/argv/stdin/rc-contract analysis and
the pattern-class sweep; all four new kit-cli pins traced (extraction
bound, discrimination directions, farm/shim mechanics, sandbox
scope) plus their green run in this pass's gates; the three
install-args pin edits probed empirically (w1, w4 matrix, p3old) —
six shapes for the dup regex alone; tui-mode's W5 line; both claim
fixes (ddev-terminal comment, cli.md sentence) clause-checked
against f's verified enumerations with fresh spot-checks of the
status.sh anchors; the two record corrections read back; both
not-done rows; both L2 sweep records re-derived (patterns run,
sites counted); the bookkeeping commit's fills, e2e tails, sabotage
record, and near-miss disclosure. Deferred, recorded: the wave-6
sabotage runs (guard revert, assignment delete, commented gate) are
post-commit actions on the closed F-session's tree — not
re-executable from this tree, checked for text-consistency with the
pins and probes read here (my own probe numbers match the recorded
ones exactly); runtime behavior of the opk compound under a REAL
sudo/-u boundary is covered by the e2e record (tails re-read), not
re-run in this pass — the unit arms drive it through shims.

## Retracted/ghost findings

None this round. All 3 findings verified as reported; nothing
dropped, nothing newly marked `unverified`.

## Run provenance

- Commission: maintainer, in-session — wave review g over
  `d817f43..bb3c19d`, WITHOUT reviewer subagents (solo main-session
  execution), 8-minute window, micro-wave shape. The standard
  axis fan-out (review-concept "Parallel reviewer agents") was
  collapsed into this single session BY THE COMMISSION — the
  redundancy axis (independent contexts) is collapsed to one and is
  disclosed here per the skill's calibration rule.
- Host timestamps (UTC): pass start 2026-10-24T22:15:22Z, end
  2026-10-24T22:30:49Z (single window, no fan-out staging). The
  commission's 8-minute ceiling was exceeded (~15.5 min host time,
  gates and snapshot writing included) — disclosed rather than
  trimmed; the section budget (11 dispositions + sweeps +
  bookkeeping) governed, per "agents spend sections".
  Checkpoint side file /tmp/opencode/pr-00244-g/checkpoints/main.md
  (launch, gates rc, per-work-section lines, findings count);
  probes under /tmp/opencode/pr-00244-g/probe/ (w1.sh, w4.sh,
  p3old.sh — all against scratch copies, never the tree).
- Main session: GLM-5.3 (zai-coding-plan), strong tier, solo —
  sweep/security/quality sections executed in one context;
  verification duty over the full fix diff; 3 of 3 findings
  confirmed (all three probe- or read-verified twice: once in the
  work section, once before writing).
- Gates run by this session on tree `bb3c19d` (clean, before the
  snapshot): `make lint && make test` rc 0 — full suite, all suites
  passed, rules index parity OK (118 index rows); reviews lint,
  reviews parity, and the line-length ratchet re-run green on the
  commit that carries this snapshot.
- E2E: owed and discharged by the f-round wave ITSELF on tree
  `97b55b9` (309 + 47 passed, TS 20261025-000326) — log tails
  re-read by this pass (see Verified clean). This round's snapshot
  changes no code — no new e2e debt.
- Mutation windows: none — no sabotage spot-checks this pass; the
  tree stayed clean and read-only throughout (`git status
  --porcelain` empty before and after); probes touched only session
  scratch outside the tree. RM-0112 check: this pass's verdicts on
  the wave's constructs rest on the F-session's recorded sabotage
  (4 kit-cli pins red, W1 zero path, _p3old isolation probe) plus
  this pass's own executed probes (w1/w4/p3old) — no
  reasoning-only verdict on a construct lacking a representative
  execution.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary at
  /usr/local/bin/opencode this session (recorded per RM-0078).
- Rotation: the F-session (fix author) was closed before this pass;
  this fresh session (G in the maintainer's snapshot-letter
  counting) reviewed its fixes — no deviation, RM-0110 recovery not
  applicable.
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
