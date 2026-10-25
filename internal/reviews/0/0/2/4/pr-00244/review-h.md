<!-- review-meta
ID: pr-00244
Snapshot: h
Subject: issue-223 fix-wave 7 dispositions (wave review of the g-round fixes, 3-axis fan-out)
Scope: wave
Base: 0.0.56+74 @ a32884b (VERSION 0.0.56)
Diff: a32884b..ce90367
Date: 2026-10-25
Reviewer: GLM-5.3 house session (opk-review-pass skill), 3-axis fast-tier fan-out (GLM-5.3-Flash reviewers: W mechanical sweep, S security, Q quality; verification duty in the main session, strong tier); session H of the maintainer's snapshot-letter counting (fix commits 5fc14c6/5ffefc2/ce90367 authored by the closed G-session, closed before this pass)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review h — wave review of the fix wave (pr-00244), 3-axis fan-out

Round h over the g-round fix diff `a32884b..ce90367` (three commits:
`5fc14c6` the dispositions — the `_py3_imports` count/dup regex pair
is RETIRED for an executed-value semantic pin (collected assignment
lines executed under install.sh's own interpreter, executed final
value must equal the extracted list), the v2-URL `grep -c` joins the
comment-strip rider class, kit-cli extraction-vs-python3 FAIL labels
split, and opk's settings-edit heredoc exits 1 when no
"opencodeBinary" key was removed (g S1) with two behavioral pins;
`5ffefc2` self-check hardening — the semantic pin's FAIL message
prints the diverging values, export/readonly/local-prefixed
assignments join the collection; `ce90367` bookkeeping — g-row SHA
fills, wave-7 e2e discharge (309+47 on `5fc14c6`), sabotage record,
the post-push-amend no-force resolution). The wave answers review-g's
3 findings: W1, Q1, S1 all implemented.

Commission shape: the standard wave fan-out (review-concept,
"Parallel reviewer agents") — 3 axis reviewers on the provider's fast
tier (GLM-5.3-Flash), ~8-minute section budgets each, staged launch
(3 of the 5-seat cap), checkpoints outside the tree; every finding
re-verified by this main session (strong tier) before entering this
snapshot. Rotation state: the G-session (fix author) is closed; this
pass ran with fresh context over its fixes — no rotation deviation,
RM-0110 recovery not applicable. Review-g left no open findings
beyond the dispositions this wave implements.

Tree `ce90367`, clean (`git status --porcelain` empty before and
after; no mutation window — no sabotage ran while reviewers read;
every probe in this pass ran against scratch copies under
`/tmp/opencode/pr-00244-h/probe*/` outside the tree).

## Findings index

15 IDs, 14 unique after 1 cross-axis duplicate pair (W3 ≡ Q1: the
union-vs-FIRST extraction claim, found independently by the sweep and
quality axes). All 15 verified as reported by the main session —
reads plus scratch-copy probes; every probe number in the verbatim
bodies below reproduces (union extraction, continuation-steal false
green with loud production failure, declare-shape green-today, abort
one-liner). None retracted, none dropped, none `unverified`.

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| W1 | MED | wave-7 L2 sweep record names 3 sibling `grep -c` sites; ≥9 further source-counting sites exist unnamed, and ddev-as-opencode :1336/:1358 count shipped source — the record's blanket "fixture OUTPUT" classification of that file is false | wave-introduced (record; sites pre-existing) |
| W2 | MED | test-project-paths.sh:181 bare unguarded `$(grep -c '_PP_NORM' "$INSTALL")` under `set -e` — the f-W1 abort class: zero matches aborts the suite before the FAIL records | pre-existing |
| W3 | LOW | new pin comment says the extraction "reads the FIRST single-quoted list"; the `_p3gate` sed `/p` unions EVERY list (probe: two assignments → both printed) | wave-introduced |
| W4 | LOW | test-ddev-as-opencode.sh:1491 bare `grep -c` under `set -e` on generated output — abort-instead-of-FAIL shape on the warn-wording accident it guards | pre-existing |
| W5 | INFO | collection regex over-collects token-suffixed shapes (`_py3_imports-foo=x` — `-` satisfies `[^_[:alnum:]]`); no such line ships, failure direction is loud | wave-introduced |
| W6 | INFO | comment-strip rider covers full-line comments only; a trailing comment carrying the v2 URL would still count (today both sites are live code) | wave-introduced |
| S1 | LOW | semantic pin false-green on the continuation-steal shape — backslash on the line ABOVE the assignment keeps the line out of `_p3cont`'s scan, the pin executes it standalone and PASSES while production dies at the use site (probe: `parameter not set` rc 2); contradicts "Every accident shape reds by construction", absent from the residual list | wave-introduced |
| S2 | LOW | TOCTOU: settings rewritten between the outer grep (opk:298) and python's read → the new else-exit lands the user in ui_error "remove by hand" for a key already gone (fail-closed, ms window, old code was worse: false success) | wave-introduced |
| S3 | INFO | production cannot distinguish the new else-exit rc 1 from unparseable JSON / missing python3 / write failure — one generic ui_error for four causes (unit pin separates via empty-stderr; production does not) | wave-introduced (conflation pre-existing) |
| S4 | INFO | pin executes under the shebang interpreter (`#!/bin/sh` → dash) while production pipes install.sh to bash — model divergence degrades to false-reds only (bash-isms error loudly under dash) | delta-introduced |
| Q1 | MED | "FIRST list" false model repeated in three places: the pin comment (test-install-args.sh:974-975), the resolution record (:1042/:1044), and commit `5fc14c6`'s message — the sed unions every list; behavior is safe on every probed double (union ≠ executed-last reds) | wave-introduced |
| Q2 | LOW | the combined guard's FAIL label "assignment present, no continuation" also serves the empty-extraction arm, where the assignment is NOT present (lines=0 prints, so the values discriminate) | wave-introduced |
| Q3 | LOW | "Every accident shape reds by construction" — a `declare`/`typeset`-prefixed second assignment is not collected (probe: green; dash errors loudly on bare `declare` today, so no silent drift unless the shebang becomes bash) | wave-introduced |
| Q4 | MED | probe-matrix record claims "9 accident shapes red" but enumerates 8; the L1 entry's shape indices (7/8, 3/6) map to neither ordering; "with the diverging values in the FAIL text" is wrong for 3 shapes (+= reds rc 127, commented-sole/deleted red via the other arm printing lines/cont only) | wave-introduced |
| Q5 | INFO | the new loud-failure branch (value-shaped hit → ui_error hand-edit instead of false ui_success) is documented nowhere; no existing docs statement became false (openchamber.md:66 already covers the hand-edit) | wave-introduced |

Severity as reported: 4 MED (W1, W2, Q1, Q4), 6 LOW (W3, W4, S1,
S2, Q2, Q3), 5 INFO (W5, W6, S3, S4, Q5). The stop rule's severity
bar (MED/HIGH) is tripped as reported.

Verification calibration notes (main session; severities stay AS
REPORTED — the verbatim bodies below are untouched, and the
disposition authority is the resolution's):

- **W1, Q4** are record-completeness/accuracy corrections inside
  resolution.md (bookkeeping, not review-relevant code per RM-0065);
  house precedent for the class is LOW (c W4, d W4, f Q1/Q2). The
  MED ratings are noted, not contested — W1 also carried the
  discovery of W2, which stands at MED on its own.
- **Q1**'s defect class is the g-W1 shape: a comment's false
  universal over a mechanism whose BEHAVIOR is safe in every probed
  shape (any double assignment reds — union ≠ executed-last, probe
  below). House precedent rates the class LOW; Q1 adds only that the
  false model is repeated in the record and commit message.
- **Q2**'s label states both conjuncts of its assertion and prints
  both observed values (`lines=` and `cont=`) — under the house
  label convention (labels state the assertion; the retired count
  pin's "(found N, want 1)" is the same shape) this is weaker than
  the g-Q1 missing-conjunct defect; INFO-calibration noted.
- **W2** stands at MED un-contested: the f-W1 abort class in a live
  suite, this time pre-existing and missed by the wave's own sweep —
  probe below (rc 1, diagnostic never reached).

---

## Axis W — mechanical sweep (verbatim, GLM-5.3-Flash)

# Mechanical sweep — wave diff `a32884b..ce90367` (pr-00244, fix wave 7)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | MED | L2 class-sweep record names 3 sibling sites; ≥9 further source-counting `grep -c` sites exist unnamed | wave-introduced (record text in ce90367; sites pre-existing) |
| W2 | MED | `test-project-paths.sh:181` unguarded `$(grep -c …)` under `set -e` — the f-W1 abort class, missed by the sweep, on the same case-chain that fixed it in wave 6 | pre-existing |
| W3 | LOW | New pin comment claims extraction "reads the FIRST single-quoted list"; the `_p3gate` sed unions **all** matches | wave-introduced |
| W4 | LOW | `test-ddev-as-opencode.sh:1491` bare `$(grep -c …)` under `set -e` on generated output — abort-instead-of-FAIL shape | pre-existing |
| W5 | INFO | Collection regex over-collects token-suffixed shapes (`_py3_imports-foo=x` collected, probe-verified) | wave-introduced |
| W6 | INFO | Comment-strip rider covers full-line comments only; a trailing comment carrying the v2 URL would still count | wave-introduced (residual inherited from class) |

## Details

### W1 (MED) — L2 sweep record under-reports the sibling-site list
`internal/reviews/0/0/2/4/pr-00244/resolution.md:1097-1105` claims the sweep of `grep -rn 'grep -c' tests/unit/*.sh` and names as same-class out-of-diff sites only `test-bypass-guard :125/:152/:180` (those three verified accurate against this tree — they are exactly `sh -c '[ "$(grep -cF …)" -eq N ]'` over `$INSTALL`/`$UPDATE`). But the same sweep surfaces further **source-counting** sites the record neither names nor classifies:
- `tests/unit/test-kit-cli.sh:166` `[ "$(grep -c 'oc_bypass_bin' "$KIT")" -ge 4 ]` and `:173` (same shape, `$KIT` = shipped `bin/opk`, `test-kit-cli.sh:14`)
- `tests/unit/test-project-paths.sh:181` `_norm_sites=$(grep -c '_PP_NORM' "$INSTALL")` (install.sh source; see W2)
- `tests/unit/test-e2e-sources.sh:171,200` `_git_build_args=$(grep -c -- '--build-arg GIT_CHANNEL' "$LIB")` (counts `tests/e2e/lib.sh` source, no `|| true`, no strip)
- `tests/unit/test-ddev-as-opencode.sh:1358` counts `ddev settings management? (dev-owned projects)` in `"$INSTALL"` where `INSTALL="$FILES/install.sh"` (`:28`) — this contradicts the record's blanket claim (`resolution.md:1104-1105`) that "Sites counting fixture OUTPUT (container-backend, ddev-as-opencode) are a different class"
- `tests/unit/test-ddev-as-opencode.sh:1336` counts `ddev_handover_stamp_write` in `"$CONFIG"` = shipped `management/config.sh` (`:30`)
- `tests/unit/test-ddev-migrate.sh:396` `_grep_n=$(grep -c 'chmod 3770 …' "$MIG" || true)`, `MIG="$FILES/…/sh/ddev-migrate.sh"` (`:26`) — shipped source
- `tests/unit/test-staged-write.sh:486,524,529`, `tests/unit/test-status.sh:1210,1357`, `tests/unit/test-update-flags.sh:141,285,421,422`, `tests/unit/test-workflows.sh:279,280` — all count shipped-script source without a comment-strip rider.

Why it matters: `agent/learnings.md` L2 makes the recorded pattern+sites list the authoritative input for follow-up scoping; the next wave starts from 3 sites instead of ~12. Mitigating: the record explicitly defers the named sites, and one compliant precedent exists that the record also fails to cite — `tests/unit/test-git-config.sh:133-138` already joins backslash continuations AND drops comment lines before counting (`_opk_install_j=$(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$INSTALL" | grep -v '^[[:space:]]*#' || true)`).

### W2 (MED) — unguarded source-count grep -c under set -e (f-W1 abort class)
`tests/unit/test-project-paths.sh:181`:
```sh
_norm_sites=$(grep -c '_PP_NORM' "$INSTALL")
```
under `set -e` (`:11`, no `set +e` anywhere in the file). If `_PP_NORM` drops to zero occurrences in install.sh — exactly the accident the `-ge 4` pin guards (`:182`) — `grep -c` prints `0` and exits 1, the assignment fails, and the suite **aborts before recording the FAIL**. This is verbatim the f-W1 class this case-chain fixed in wave 6 (`resolution.md:70`: "count grep `|| true`-guarded: zero-match FAIL observable, no abort"). The line is also survivor-prone: no comment strip, so a commented-out `_PP_NORM` site still counts toward `-ge 4`. Same shape as f W1's house LOW rating; rated MED only because it is a same-shape sibling the wave's L2 sweep missed on the very class the chain owns — severity in isolation is LOW.

### W3 (LOW) — comment misstates the extraction mechanism
`tests/unit/test-install-args.sh:972-975` (new comment): "the extraction above reads the FIRST single-quoted list". The extraction at `:964`:
```sh
_p3gate="$(sed -n "s/^[[:space:]]*_py3_imports='\([^']*\)'.*$/\1/p" "$INSTALL")"
```
`sed -n … p` prints **every** match — it unions all single-quoted lists, as the retired (accurate) comment said ("the gate-list extraction unions every match"). Safety is unaffected — with two assignments the extracted union differs from the executed last value and the pin reds — but the comment's mechanism claim is false, and it replaced wording that was true (L3: comment claims carry their pins).

### W4 (LOW) — abort shape on generated-output count
`tests/unit/test-ddev-as-opencode.sh:1491`:
```sh
_n_w9=$(grep -c 'warn: project-root hand\(back\|over\) incomplete' "$HANDOVER")
```
`set -e` is active here (`:16`, last `set +e`/`set -e` pair at `:168/:171`). `$HANDOVER` is generated output; if the warn wording changes so zero lines match — the exact accident the `-ge 3` pin at `:1492` guards — the suite aborts instead of printing the intended FAIL. Output-counting, so outside the wave's comment-blind class (the L2 record's classification is right for this one), but the same rc-reading shape the blind-spot list names. Pre-existing.

### W5 (INFO) — collection regex collects token-suffixed names
Probe (on a copy under `/tmp/opencode/pr-00244-h/probe-sweep/`): the literal collection regex matches `_py3_imports-foo=x` — `-` satisfies `[^_[:alnum:]]`. Such a line would execute as command-not-found under the pin's `set -e` scratch → false RED. No such line exists in `files/install.sh` (only `:573` assignment, `:578/:583` use sites — probe-verified: the real file collects exactly one line, the `:573` assignment), and the failure direction is loud, so this is a boundary note, not a defect. The intended exclusions all hold: use sites (`if ! python3 …`, `python3 -I -c …`) are not line-start-matched, `export`/`readonly`/`local` prefixes are matched as designed.

### W6 (INFO) — trailing-comment residual on the URL rider
`tests/unit/test-install-args.sh:830` strips full-line comments only (`sed 's/^[[:space:]]*#.*$//'`). A trailing comment carrying the URL (`curl … | bash # disabled, see …`) would still count toward the `-ge 2` pin. Today both occurrences in `files/install.sh:1964-1965` are live code lines with no trailing comments, so nothing triggers it; the rider's comment (`:826-828`) accurately scopes its claim to "comment lines". Same residual applies to `_p3old` (`:939-940`).

## Verified clean

- **Retired constructs**: `_p3asn`/`_p3dup` absent from `tests/`, `files/`, `docs/` (grep rc=1); remaining `_p3*` hits are unrelated (`test-line-length.sh:175` probe var, `_p3old` rider, `_p3collect`/`_p3split` machinery, `_p3diag` fixture).
- **Line-number cite**: the wave's `:578/:583` use-site claim measures true at this tree (`grep -n '_py3_imports' files/install.sh` → 573/578/583 only).
- **Shebang resolver**: `sed -n '1{s/^#!//p;q;}'` → `/bin/sh` → `case` maps to `sh`; a `#!/usr/bin/env bash` shebang contains `bash` → maps to `bash` as the comment claims.
- **L2 bypass-guard claim**: `:125/:152/:180` match the record's description exactly (`grep -cF` literals in `$INSTALL`/`$UPDATE` inside `[ "$(…)" -eq N ]`).
- **Extraction-vs-runtime siblings**: none — the heredoc-extraction sites (`test-security-advisories.sh:353-354`, `test-status.sh:2517-2518`, kit-cli `OCW2_BLOCK`/`OPYSCR`) execute the extracted artifact against fixtures (behavioral eval), they do not compare extracted vs runtime-computed values.
- **OPYSCR anchors**: `opk-settings-edit` occurs exactly once in `bin/opk` — the axis's "$0 cosmetic" concern is void because the cosmetic sits on the *same* line `:306` as the heredoc start; `^PYEOF$` matches only the `:320` terminator (column 0, exact for a non-`<<-` heredoc). Extraction probe yields the exact python program; S1 value-shaped fixture → rc=1, silent, file byte-identical.
- **OCW2_BLOCK anchors**: `#244 f W2` unique (`:299`); the first `^            fi$` after it is the intended inner `fi`; no shell `fi` inside the heredoc body; the ≤32-line bound (`test-kit-cli.sh:894`) guards anchor drift.
- **CRLF**: none at the checked lines (`cat -A` clean).

## Coverage / deferrals

Covered: wave diff; retired-remnant grep; full `grep -c` classification over `tests/unit/*.sh` (per-site); extraction-vs-runtime sibling sweep; collection regex vs install.sh ground truth + shebang resolver (probes on copies under `/tmp/opencode/pr-00244-h/probe-sweep/`); sed-range anchor checks for OPYSCR, OCW2_BLOCK, plus a probe run of the S1 value arm. Deferred: behavioral re-run of the full 9-shape sabotage matrix (wave gates ran green; I re-verified extraction mechanics and one arm); the ddev-migrate/ddev-as-opencode output-count sites were classified by definition+context, not each individually read; `test-ddev-migrate.sh` output-count sites (:317/:363-367/:743-747/:828-833) left unclassified beyond "output class by shape" — none is source-counting by construction.

## Axis S — security (verbatim, GLM-5.3-Flash)

# Security review — wave `a32884b..ce90367` (pr-00244 fix wave 7)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | Semantic pin false-green for the continuation-steal shape (backslash on the line *above* the assignment); contradicts the pin's own "reds by construction" claim | wave-introduced |
| S2 | LOW | TOCTOU: settings file changed between outer grep and python read lands the user in the hand-edit error branch for a key that is already gone | wave-introduced |
| S3 | INFO | Production cannot distinguish the new else-exit rc 1 from unparseable JSON / missing python3 / write failure — one generic ui_error for four causes | wave-introduced (conflation pre-existing) |
| S4 | INFO | Pin resolves "install.sh's own interpreter" from the shebang (dash) while production pipes install.sh to bash — model divergence, no realistic false-pass constructed | delta-introduced |

## Details

### S1 — LOW — continuation-steal false-green in the executed-value pin

Evidence (tests/unit/test-install-args.sh:999-1003 — collection and detector):
```sh
_p3lines="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL" \
    | grep -E '^[[:space:]]*(export[[:space:]]+|…)?_py3_imports[^_[:alnum:]]' || true)"
_p3cont="$(printf '%s\n' "$_p3lines" | grep -n '\\$' || true)"
```
and the claim it fails to support (test-install-args.sh:979-980):
```
    # value == extracted list. Every accident shape reds by
    # construction — separate-line seconds, appends, same-line
```

`_p3cont` only scans **collected** lines. A backslash ending the line *before* the assignment is on an uncollected line, so the physical assignment line is collected standalone, executed out of context, and matches the extraction (which reads the same physical line). Probe against a mutated copy under `/tmp/opencode/pr-00244-h/probe-sec/`:

```
    ui_detail "stolen" \
    _py3_imports='import fnmatch, …'
```
→ pin: `PASS: gate: executed _py3_imports equals the extracted list` (and sanity run on the unmutated copy: green, so the harness is sound). In that file the assignment is an argument to `ui_detail`, the runtime variable is never set, and install.sh dies at the use site — probe under `set -u` (install.sh:46): `_py3_imports: parameter not set`, rc 2.

Why it matters: the pin's stated job is to make the spot stop re-opening; this accident shape ships green and only surfaces as a loud install failure on user machines. Mitigations keeping it LOW: production fails loudly (not silently), the shape is rarer than the already-detected trailing-backslash form, and it belongs in the documented-residuals list (test-install-args.sh:1020-1027), which currently omits it — so the claim at :979-980 is overstated as written.

### S2 — LOW — TOCTOU between outer grep and python read

Evidence (files/opencode-permissions-kit-lib/bin/opk:298 and :307-319):
```sh
if grep -q '"opencodeBinary"' "$_oc_settings" 2>/dev/null; then
```
The flow explicitly tolerates a **running** OpenChamber — the restart instruction comes after the edit (opk:328: "restart OpenChamber if it is running"). If the daemon rewrites settings.json between the grep at :298 and python's `p.read_text()`, the key is gone at python time, the new else fires, and the user gets (opk:324-325):
```
ui_error "could not update $_oc_settings — remove the \"opencodeBinary\""
ui_error "line by hand (docs/how-to/openchamber.md)"
```
for a line that no longer exists. Window is milliseconds (fork/exec, no interactive gap before the read — the `ui_confirm` at :286-292 sits before the final grep), trigger requires the daemon to persist config exactly then. Benign direction overall: the old code printed `ui_success` over an unchanged/pinless file in the same race. Fail-closed elsewhere: every shape the grep can hit but python can't act on (value-shaped literal, non-dict top-level JSON, key removed concurrently) now exits 1 into ui_error — no write, no success. The byte-identical failure path is mechanically pinned (test-kit-cli.sh:1024-1029, `cmp -s`).

### S3 — INFO — rc-1 conflation in the production error branch

Evidence (opk:305-306, :309-312, :316-319, :323-326): four distinct causes reach the same `else` with rc 1 and no discriminator — the new value-shape `sys.exit(1)`, the pre-existing unparseable-JSON `sys.exit(1)` (except-ValueError branch, untouched by the diff), python3 missing (`sh -c 'command -v … && exec …'` short-circuit), and write/OSError via traceback. The ui_error text ("remove the line by hand") is literally accurate for only the first cause. Users *do* see a behavior change — value-shaped grep hits previously got `ui_success` (opk:322) and now get an error; that is the intended fix. The conflation itself is a support-diagnosis ambiguity, not a fail-open: every branch fails closed. Blind-spot answer: the unit pin separates else-exit from traceback via the empty-stderr assertion (test-kit-cli.sh:1028 `[ -z "$_s1out" ]`); production does not.

### S4 — INFO — interpreter model: shebang vs production invocation

Evidence (test-install-args.sh:994-998):
```sh
_p3she="$(sed -n '1{s/^#!//p;q;}' "$INSTALL")"
case "$_p3she" in
    *bash*) _p3bin=bash ;;
    *) _p3bin=sh ;;
esac
```
install.sh's shebang is `#!/bin/sh`, so the pin executes under dash — but production runs install.sh via `curl … | sudo env KIT_BRANCH=stable bash` (AGENTS.md install command), i.e. bash. "Executed == extracted under install.sh's own interpreter" models dash, not the production interpreter. I could not construct a realistic false-pass: bash-only assignment constructs (`+=`, arrays) error loudly under dash → red, and plain assignments are POSIX-identical — so the divergence degrades to false-reds, not false-greens. The missing-shebang fallback (`_p3bin=sh`) is the correct fallback for today's sh script and same fail direction.

## Clean (verified, no finding)

- **Else-exit write path**: `sys.exit(1)` only — no `write_text` on the failure path; pinned byte-identical (test-kit-cli.sh:1024-1029).
- **rc propagation**: python `exec` replaces the inner sh → sudo rc passthrough → compound else (opk:305-326). The sudo leg is verified by reading and standard sudo semantics only — *unverified mechanically* (no `sudo -u` target in this environment) and not e2e-exercised (the e2e run covered the success path); the unit pins bypass sudo by design.
- **Heredoc quoting**: `<<'PYEOF'` — no `$` anywhere in the python body (opk:307-319); nothing needs or receives expansion. The test-side extraction (`sed -n '/opk-settings-edit/,/^PYEOF$/p'` + `1d;$d`, test-kit-cli.sh:1012) yields exactly the python body; `opk-settings-edit` occurs once in opk.
- **Unparseable-JSON contract**: except-ValueError branch untouched by the diff — contract unchanged.
- **Fail-open conjuncts**: empty extraction fails closed twice (`[ -z "$_p3lines" ]` :1004, `[ -n "$_p3gate" ]` :1013); `_p3cont` false-positives red (fail-closed); line-start filter verified against the use sites (install.sh:577/:583 don't match); `printf '%s\n' "$_p3lines"` keeps content out of the format string; rc capture `|| _p3rc=$?` correct under the suite's `set -e`.
- **Executed-line threat model**: no capability beyond existing suite practice (the suites already eval extracted blocks — RM-0017's origin) and production (`curl | bash`); RM-0017's controlled-PATH rule is not triggered — the collected lines carry no `command -v` today.
- **Root-op class (L5)**: verified from the diff — opk gains `sys.exit(1)` + comment only; no path operands, no chmod/chown, no `[ -L ]` walks touched. The blind-spot path-operand forms (`x/`, `x//`, `x/.`) are absent from the wave entirely.
- **Sandbox/deletion**: new `rm -f "$_p3tmp"` (test-install-args.sh:1012) and `rm -rf "$OCW2S1"` (test-kit-cli.sh:1048) are pure-variable operands — exempt per agent/conventions.md "Pure-variable operands … deliberately exempt"; quoted; all scratch under `$WORK`/`mktemp`; fixtures sandboxed at source. `sh tests/unit/test-sandbox-policy.sh` run green, including the rm-guard self-probes.

## Coverage

Covered: full wave diff; opk settings-edit compound with surrounding function (opk:255-339); rc/TOCTOU/stderr analysis incl. the except-ValueError pre-existing branch; executed-value pin threat model with mechanical probes on copies (sanity + continuation-steal sabotage + dash runtime probe); S1 test block in situ (test-kit-cli.sh:995-1049); root-op-class and sandbox verification including a green `test-sandbox-policy.sh` run. Deferred: mechanical sudo rc-passthrough probe (no `sudo -u` target available; recorded as unverified-mechanically under S3's clean item), and an exhaustive bash-vs-dash assignment-semantics sweep (S4 bounded by loud-red argument). Checkpoints at /tmp/opencode/pr-00244-h/checkpoints/security.md; probes confined to /tmp/opencode/pr-00244-h/probe-sec/; repo untouched.

## Axis Q — quality (verbatim, GLM-5.3-Flash)

# Quality axis — wave diff `a32884b..ce90367` (fix wave 7, pr-00244)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | MED | Comment, resolution record, and commit message claim the extraction reads the FIRST single-quoted list — the sed actually unions EVERY list | wave-introduced |
| Q2 | LOW | Presence-arm FAIL label says "assignment present" but fires on the empty-extraction case where it is not | wave-introduced |
| Q3 | LOW | Blanket "Every accident shape reds by construction" — a `declare`/`typeset`-prefixed second assignment is not collected (probe: green) | wave-introduced |
| Q4 | MED | Probe-matrix record claims "9 accident shapes red" but enumerates 8; L1's shape indices (7/8, 3/6) map to neither order | wave-introduced |
| Q5 | INFO | No doc lies after the opk else-exit, but the new loud-failure branch is documented nowhere; how-to/openchamber.md already covers the hand-edit it points at | wave-introduced |

## Details

### Q1 — MED — "FIRST list" claim vs union extraction
`tests/unit/test-install-args.sh:974-975`: "the extraction above reads the FIRST / single-quoted list (the coverage pin below audits that list)" — but `:964` is `_p3gate="$(sed -n "s/^[[:space:]]*_py3_imports='\([^']*\)'.*$/\1/p" "$INSTALL")"`, whose `/p` flag prints **every** matching line. Re-probed on a scratch copy (`/tmp/opencode/pr-00244-h/probe-qual/`): two plain assignment lines → `_p3gate` = both lists joined by newline, not the first. The removed predecessor comment had it right ("the gate-list extraction unions every match"). The false model is repeated in `internal/reviews/0/0/2/4/pr-00244/resolution.md:1042` ("executed final value == the extracted first list") and `:1044` ("the coverage pin audits the FIRST list"), and in commit message `5fc14c6` ("the extracted first list"). Why it matters: for the most plausible copy-paste accident — an **identical** duplicate second line (first `X`, second `X`) — the stated model predicts green while the pin actually reds (union `X\nX` ≠ executed `X`). The pin's behavior is safe in every probed shape; the documented invariant is not the one the code enforces, and any future fix reasoned from this comment starts from a false premise.

### Q2 — LOW — FAIL label contradicts its own condition
`tests/unit/test-install-args.sh:1005`: `fail "gate: _py3_imports assignment present, no continuation (lines=$_p3n cont=[$_p3cont])"` also serves the `[ -z "$_p3lines" ]` arm — the commented-out/deleted sole-assignment case the comment at `:981-983` says must red. There the assignment is *not* present and the message contradicts its own `lines=0`. Realistic trigger: someone comments the sole assignment and gets a diagnostic claiming it is present. The arm reds correctly; diagnostic-only.

### Q3 — LOW — blanket claim vs uncollected prefixes
Comment `:979-980`: "Every accident shape reds by construction"; the collection regex at `:1000-1002` alternates exactly `export|readonly|local`. Probe: a second line `declare _py3_imports='import sys'` → collected n=1, executed == extracted, **GREEN**. Mitigating condition named: under the resolved interpreter (shebang `#!/bin/sh` → dash) a bare `declare` line errors instead of reassigning, so no silent runtime drift escapes *today*; the shape becomes a real miss only if the shebang changes to bash (then `_p3bin=bash` would execute the declare while the collection still never sees it). The blanket sentence overstates the pin's guarantee.

### Q4 — MED — record's own enumeration contradicts its count
`resolution.md:1050`: "9 accident shapes red with the diverging values in the FAIL text, 2 comment shapes green" — then enumerates **8** red shapes (second assignment, append, same-line double, quoted-# double, `+=` double, commented sole, deleted, trailing continuation). `resolution.md:1116` (L1): "empty collection → recorded FAIL, shapes 7/8; interpreter failure → captured rc, shapes 3/6" — in the enumerated order, empty collection is items 6–7 and interpreter failure is item 5; neither index pair maps. Additionally "with the diverging values in the FAIL text" is wrong for three shapes: `+=` reds with rc=127 (probe-confirmed: dash `_py3_imports+=x: not found`), commented-sole/deleted red via the `:1005` arm printing lines/cont only. The count is repeated in commit message `5fc14c6` ("probe matrix 9 red / 2 green"). Note the sabotage record itself (5 constructs) **is** consistent: each quoted evidence string is printable — the quoted-# same-line double probe reproduces exactly `executed=[{c}] extracted=[{a#b}]`.

### Q5 — INFO — docs state after the S1 behavior change
The earlier waves' sentences are still true: `docs/concepts/sharing-group.md:76-77` and `docs/reference/cli.md:359` describe the python3 health-gate diagnostic, untouched by S1. `docs/how-to/openchamber.md:58-66` already documents the manual "Remove the `opencodeBinary` line" step, and the new `ui_error`'s cited path `docs/how-to/openchamber.md` (opk:325-328) exists. No page promises opk's removal always succeeds, so no statement became false — RM-0100 is not violated as "docs that lie." The new failure branch (value-shaped hit → ui_error hand-edit instead of false ui_success) is itself not mentioned on any docs page; a sentence in how-to/openchamber.md would have satisfied RM-0100's letter more fully. Judgment call, recorded as INFO.

## Coverage

**Covered:** full wave diff; claim audit of the executed-value pin block with 7 scratch probes on copies under `/tmp/opencode/pr-00244-h/probe-qual/` (export-prefixed second → RED with values ✓ matches record; `+=` double → rc 127 under dash ✓ matches record; quoted-# two-line → union demonstrated; `declare` → GREEN; quoted-# same-line → exact record values reproduced; trailing-comment shapes → GREEN, f-W4 property preserved; continuation detector fires ✓); label-vs-condition on both kit-cli splits (all four labels accurate); OPYSCR anchor condition vs opk:306-317 body ✓; S1 header style matches its f-W2 sibling (`) --`, test-kit-cli.sh:887/:1006); escaped `\"` renders correctly (shell strips before echo); sibling `command -v python3` sweep — no unsplit compound left; `_p3asn`/`_p3dup` fully gone (grep rc=1), no dead vars (`_p3n`/`_p3cont`/`_p3she`/`_p3bin` all used); resolution record vs git — no `<SHA>` placeholders, g rows cite real `5fc14c6` whose stat matches (opk +4, both test files, resolution), `5ffefc2` is test-install-args.sh-only and `ce90367` resolution.md-only, so "post-e2e deltas test-only" is true; both e2e log tails read at the given paths — `Passed: 309` / `Passed: 47` exact; rootless-alone note corroborated by shapes (root log ends 01:19:50, rootless 01:21:56 ≈ 2m06s solo run, same TS, cache `opencode-1.18.15` warm + 00:03 sibling log exists); settings-pin e2e flow exercised green (e2e log:1691-1699); opk else-exit intentional and lands in the pre-existing ui_error compound ✓; `:578/:583` cites exact at ce90367 (both `python3 -I -c "$_py3_imports"`, install.sh untouched by the wave); "every grep guarded" true (`_p3lines`/`_p3n`/`_p3cont` all `|| true`); shebang→sh claim true.

**Deferred:** `/tmp/opencode/pr-00244-g/wave7-gates.log` (gate evidence in the g session's tmp — outside repo/logs scope); the "parity 118 rows" figure (no cheap verification); the exact e2e assert name "run.sh settings-pin-gone" (substance verified via log:1691-1699 instead); the root cause of the 9-vs-8 mismatch (what the 9th shape was — unrecoverable from the record). OPYSCR vs `OCW2_*` naming is a suggestion only — no house rule forbids it, so per the axis rules it is not a finding.

## Retracted/ghost findings

None this round. All 15 reported findings verified as reported by the
main session; nothing dropped, nothing newly marked `unverified`.
The S-axis's one mechanically-unverified clean verdict (sudo
rc-passthrough leg, no `sudo -u` target in this environment) is
disclosed in the verbatim body above; the e2e record covers the
runtime path (success leg) and the unit pins cover the compound.

## Run provenance

- Commission: maintainer, in-session — wave review h over
  `a32884b..ce90367`, standard wave shape (3 axes, fast tier,
  ~8-minute section budgets, 5-seat cap respected: 3 launched, no
  backfill needed). Redundancy: three independent reviewer contexts;
  no second snapshot (wave scope — none owed).
- Host timestamps (UTC): fan-out start 2026-10-24T23:51:33Z, all
  reviewers returned by 2026-10-25T00:05:28Z (~14 min wall for the
  fan-out window). Verification, probes, gates, and snapshot writing
  ran after the fan-out window in the main session. Sandbox clocks
  run ~+02:00 against host; the recorded launch lines normalize
  (security launch 2026-10-25T01:52:48+02:00 = 23:52:48Z, ~1 min
  after the host fan-out stamp; quality sections 01:55:09–02:02:45
  local = 23:55:09–00:02:45Z). Per-agent checkpoint files:
  /tmp/opencode/pr-00244-h/checkpoints/{sweep,security,quality}.md
  (launch/section/return lines; absorbed here — the S-axis's
  section-by-section record and the W/Q section lines match the
  returned reports).
- Reviewers: GLM-5.3-Flash (zai-coding-plan), fast tier, one per
  axis (W mechanical sweep, S security, Q quality), fresh contexts,
  axis prompts built from the skill's axis-prompt.md. Main session:
  GLM-5.3 (zai-coding-plan), strong tier — verification duty over
  all 15 findings; every finding read-verified, the substantive ones
  probe-verified on scratch copies (union extraction; S1
  continuation-steal: pin false-green + production `parameter not
  set` rc 2; Q3 declare: green today, `declare: not found` rc 127
  under dash; W2 abort one-liner rc 1).
- Gates run by this session on tree `ce90367` (clean, before the
  snapshot): `make lint && make test` rc 0 — all suites passed,
  rules index parity OK (118 rows); log
  /tmp/opencode/pr-00244-h/gates.log on the session host. Reviews
  lint, reviews parity, and the line-length ratchet (snapshots
  exempt as immutable history — this file is written wrapped in the
  house sections regardless) re-run green on the commit that carries
  this snapshot.
- E2E: owed and discharged by the g-round wave ITSELF on tree
  `5fc14c6` (309 + 47 passed, TS 20261025-011708) — log tails
  re-read and confirmed by this pass (one `Passed: 309` in
  ../logs/e2e-20261025-011708.log, one `Passed: 47` in
  ../logs/e2e-rootless-20261025-011708.log); the post-e2e deltas
  (`5ffefc2` test-only, `ce90367` bookkeeping-only) verified by
  `git show --stat`. This round's snapshot changes no code — no new
  e2e debt.
- Mutation windows: none — no sabotage spot-checks ran while the
  reviewers read; the tree stayed clean and read-only throughout
  (`git status --porcelain` empty before and after); every probe
  (reviewers' and the main session's) touched only scratch copies
  under /tmp/opencode/pr-00244-h/probe*/ outside the tree.
  RM-0112 check: this pass's verdicts rest on the wave's recorded
  sabotage (5 constructs red, Follow-ups) plus this pass's own
  executed probes — no reasoning-only verdict on a construct
  lacking a representative execution (the S-axis's sudo-leg clean
  verdict is disclosed as unverified-mechanically, not load-bearing
  for any finding).
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary at
  /usr/local/bin/opencode this session (recorded per RM-0078).
- Rotation: the G-session (fix author) was closed before this pass;
  this fresh session (H in the maintainer's snapshot-letter
  counting) reviewed its fixes — no deviation, RM-0110 recovery not
  applicable.
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only as
  the next fix wave lands.
