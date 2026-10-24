<!-- review-meta
ID: pr-00243
Snapshot: f
Subject: micro-wave review of the e-wave's fix wave — OPENCODE_USER shape gate, anchored/discriminating pins, resolution corrections
Scope: wave
Base: 0.0.56 @ d8af4e0
Diff: d8af4e0..59e700a
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (axes S/X, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review f — micro-wave review of the e-wave's fix wave (pr-00243)

Round f over the diff d8af4e0..59e700a (2 commits: 2632c36 "fix(uninstall):
OPENCODE_USER shape gate, dot-gate screen(), per-spelling op-negative
anchors (#243 e X1 X2 S1 S2 S3 S4 S5 X3)" — the fix wave; 59e700a touches
resolution.md only, bookkeeping). Shipped material: uninstall.sh (18
changed lines: the `OPENCODE_USER` shape gate right after the `:-`
default — `case` refusing values outside `[A-Za-z0-9_.-]` with a WARN
and fallback to the canonical literal — plus its comment and the
refusal-comment extension), test-uninstall.sh (124: gate extraction +
standalone passthrough/fallback pins, the corrupted-conf chain arm on a
parameterized 7th driver parameter, the helper's dot gate with the
`/home/` and `/var//` static forms, `$`-anchored ts-loop negatives, the
end-anchored raw skip echo, the `.` chmod negative), and
docs/reference/files.md (2: the `OPENCODE_USER` row extension). All 8
implemented e-findings were audited as LANDED by the S axis (mechanism +
pin each) and spot-confirmed in verification; this snapshot's effective
findings are the residual charset-valid spellings the writer-parity gate
deliberately admits (X1 — LOW conditional, provenance corrected to
pre-existing residual), the stale line anchors in the resolution's e X1
paragraph (S1, independently found by both axes as X2), the screen()
comment's "IN FULL" breadth (S3), the unreachable `''` gate arm (X3) and
the raw-value WARN embed (X4); one reported finding retracted in
verification (S2 — its env-inheritance trigger cannot survive the
top-level literal).

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | INFO | resolution.md e X1 mechanism cites base-tree uninstall.sh line numbers, stale by +14/+16 at the diff endpoint | wave-introduced (bookkeeping text) |
| S2 | INFO — **retracted** | WARN blames `install.conf` even when the invalid value was environment-inherited on a conf-less machine — trigger unreachable: the top-level literal clobbers env before conf sourcing | wave-introduced (retracted in verification) |
| S3 | INFO | screen() comment claims gate-order parity "IN FULL" but the loop's absolute-path and agent-home gates are not mirrored (error direction is red, not silent green) | wave-introduced |
| X1 | LOW (conditional) | Charset-valid pathological spellings (`.` `..` `opencode.` `-x` `--`) pass the gate and re-target the lexical guards and user-section consumers | pre-existing residual (provenance corrected in verification) |
| X2 | INFO — duplicate of S1 | resolution.md e X1 row cites consumer line anchors in the pre-fix tree's numbering — all off by 14 lines vs the tree the row describes | fix wave (bookkeeping text) |
| X3 | INFO | Gate's `''` arm is unreachable in the shipped flow and unexercised by any pin | fix-introduced (dead defensive arm) |
| X4 | INFO | The WARN line embeds the raw corrupted value into a multi-line-capable stderr write | fix-introduced, consistent with sibling echoes |

Provenance split as reported: 7 findings (S: 3 INFO; X: 2 LOW + 2 INFO).
Verification retracts one (S2 — the claimed env-inheritance path is
unreachable), merges one cross-axis duplicate (X2 ≡ S1, found
independently by both axes; severity adjudicated INFO per S1's
rationale, see verification table) and corrects one provenance (X1:
both sub-hazards passed every prior version's compare too — the gate
narrowed the corruption class, it did not introduce the residual).
Effective after verification: **1 LOW + 4 INFO**.

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep + landing audit — fix wave 5 (e findings), diff `d8af4e0..59e700a`

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | INFO | resolution.md e X1 mechanism cites base-tree uninstall.sh line numbers, stale by +14/+16 at the diff endpoint | wave-introduced |
| S2 | INFO | Gate WARN blames `install.conf` even when the invalid value was environment-inherited on a conf-less machine | wave-introduced |
| S3 | INFO | screen() comment claims gate-order parity "IN FULL" but the loop's absolute-path and agent-home gates are not mirrored (error direction is red, not silent green) | wave-introduced |

No HIGH/MED findings. All 8 e-findings landed; every new pin verified discriminating; suite green.

## Landing audit (8/8 landed as claimed)

| Finding | Mechanism cite (verified) | Pin that reds on deletion |
|---|---|---|
| e X1 | unsh:220-225 — `case "$OPENCODE_USER" in ''\|*[!A-Za-z0-9_.-]*)` → WARN >&2 + `OPENCODE_USER=opencode`, placed after the `:-` default (:211), before all consumers (:228, :239-240, :340, :502, :595) | test:391-395 extraction pin (empty/red on gate deletion), test:402-424 standalone passthrough/fallback arms, test:934-951 chain arm — deletion red is via missing positive skip echoes, host-independent (the `[ ! -d ]` silent-continue cannot mask it) |
| e X2 | res, d Q1 block: bracketed **Correction (#243 e X2)** paragraph present; its install.sh anchors verified verbatim: :349 `OPENCODE_USER="opencode"`, :589-592 DEFAULT_USER charset gate, :1339 conf-heredoc line | n/a (text) |
| e S1 | test:815 `&& ! printf '%s' "$FOUT" \| grep -qF 'sudo chmod g-s .'` | self-red: deletion makes the arm's conjunction fail when the bare-dot op line exists; prefix-unique in the arm (`/var/.` has `/` after `g-s `, so no substring collision) |
| e S2 | test:918 `grep -q 'Skipping agent home (never a project root): /home/untest-agent$'`; chain arm born-anchored at test:937 | self-red: anchored form matches exactly the raw line; trailing-slash assertion stays `-qF` and is not satisfied by the raw line either — symmetric discrimination |
| e S3 | test:299 static list `/etc /home/ /var/ /var// …`; wired blocklist unsh:649-653 has bare `/home` with **no** `/home/*` sibling and bare `/var` with **no** `/var/*` (subdirs enumerated) | strip deletion → `/home/`/`/var/` match no arm → `screening rejects /home/`+`/var/` red (matches res spot-check 3); `/etc/` removal loses nothing (`/etc/` matched `/etc/*` with or without strip — belt only); `/etc` bare rep retained |
| e S4 | res, d Q4 block: **Correction (#233 e S4 → correctly #243 e S4)** paragraph scoping the invariant to non-agent-home arms | n/a (text) |
| e S5 | test:891-894, 901-902 — `grep -q "sudo setfacl -R -x g:60002 ${_un_ts%/}\$"` (+`/\$`, chmod pair, `/var//$` pair) | self-red per spelling; anchor premise verified: root is the LAST operand on the real op lines (unsh:708-709 `setfacl … "$root"`, :711 `chmod g-s "$root"`; find correctly keeps the ` !` anchor) |
| e X3 | test:282-284 helper dot gate `*..*\|/./\|*/./*\|./*\|*/.\|*//*` before the strip — arm set AND order identical to the loop's gate at unsh:613-615 (diffed literally); `/var//` fed at test:299 | dot-gate deletion → `/var//` strips to `/var/`, matches no arm, reports allowed → `screening rejects /var//` red (matches res spot-check 3) |

## Pin-discrimination audit (all clean)

- **S5 BRE metacharacters**: every new pattern (`…g:60002 /var$`, `…/var/$`, `…/var//$`, `/home` variants) carries only literals + the intended terminal `$` — no `.`, `*`, `[`, or mid-pattern `$`. Cross-matching checked: `/var$` ∉ {`/var/`, `/var//`} lines; `/var/$` ∉ `/var//` line (no EOL after the substring); `/var//$` ∉ `/var/` line. Each negative binds exactly one spelling; the old unanchored forms' same-arm misattribution is gone.
- **S2 end-anchor**: raw pattern is a strict prefix of the trailing-slash echo (verified textually); `$`-anchored BRE with `()` literal in BRE — matches only the raw line.
- **S1 prefix-uniqueness**: fed operands `//etc`, `/var/.`, `.`, `$WORK/fakeproj` — only `.` yields an op line with a bare `.` after `sudo chmod g-s `.
- **X3 parity**: arm-for-arm and order identical; dot gate before strip in both helper (test:282-285) and loop (unsh:613→:634).

## Sibling sweeps

- **Class-sweep claim ("no further gate owed") spot-verified**: argv consumers of conf-sourced names fail loudly — gpasswd rc-observed (unsh:471 `|| _grp_rc=$?`, WARN :477), userdel rc-observed (:548 `|| _udel_rc=$?`, WARN :554), chown via `un_rc_q` (partial list). `DEFAULT_USER`/`OPENCODE_GROUP` appear in no lexical `[ … = … ]` compare (grep walk over all occurrences) — the silent-lexical-defang hazard is indeed unique to `OPENCODE_USER`.
- **sed extraction** (test:391): start pattern unique (grep -c = 1); the gate's `esac` (:225) is the only column-0 `^esac$` in the whole file, so the range cannot over-run; a future nested column-0 esac truncates the eval → syntax error → all three X1 pins red (fail loud). Same extraction-by-text house pattern as `PROJECT_LOOP`/`UN_RC_Q` (test:372, :381).
- **Unanchored-negative re-sweep**: `//etc`, `/var/.`, `/home/untest-agent` negatives remain prefix-unique among their arms' fed operands; the new anchors did not change their subsumption story; the agent-home prefix pair remains deliberate per the e S4 correction.
- **Variable hygiene / pin placement**: `_ou_new`/`_ou_bad`/`_ou_canon`/`UN_OCU_GATE`/`_unlo_ocu` have no collisions (grep-confirmed, single-use clusters); defined before use; every new pin calls `fail()` (increments `failures`, test:25) and sits before the end-of-file summary gate (test:~1427). `_un_loop_out`'s 7th param is defaulted — no existing caller (≤6 args) changes behavior. `_ou_new`'s `2>` truncation ordering makes the shared `un-ouc-err.log` `[ ! -s ]` check staleness-proof and covers both the valid-name and canonical stderr (append at test:414).
- **Anti-pattern sweep over the diff hunks**: no new `|| true`; the new `2>`/`2>>` redirects each feed a pinned assertion; WARN channel pinned via stderr-file capture (a stdout regression reds test:419/:936). No conventions.md violation found.

## Finding details

**S1 (INFO) — stale line cites in the resolution's e X1 mechanism paragraph.**
res (e X1 block): "the LIVE_GROUP/id lookups (:214/:225-226), the agents-backup walk (:326/:332 …), and the later userdel" and "feeds the chown argv :664". At the diff endpoint these resolve to :228, :239-240, :340/:346, :680 (+14, and +16 past the second comment hunk). The same document's e X2 correction cites install.sh:349/:589-592/:1339, which I verified resolve exactly in the current tree — so the document's own convention is current-tree coordinates and the e X1 paragraph deviates. Why it matters: a future wave navigating by those numbers lands 14-16 lines off; the constructs are named unambiguously, so navigation recovers — bookkeeping accuracy only, no code effect.

**S2 (INFO) — WARN message names the wrong source on the env-inherited path.**
unsh:222: `echo "WARN: invalid OPENCODE_USER value in install.conf (…)" >&2`. The gate is unconditional and also fires when install.conf is absent and `OPENCODE_USER` arrives from the environment (the `:-` default at :211 can only produce the valid literal). Trigger: an operator or wrapper exports a malformed `OPENCODE_USER` and runs uninstall on a machine without `/etc/opencode-permissions-kit/install.conf` — the warning blames a file that was never read. Fallback behavior is correct either way; warning-path message precision only.

**S3 (INFO) — screen() comment overstates parity ("gate order IN FULL").**
test:276-281: "The helper mirrors the loop's gate order IN FULL (#243 c X1/d X4, dot gate #243 e X3)". The loop's gate chain also includes the agent-home refusal (unsh:595) and the absolute-path gate (unsh:605-611); the helper mirrors only dot gate → strip → blocklist. This is the same claim-scope class review e flagged (the comment previously claimed "strip parity only"). No silent-green path exists: the loop refuses a superset of what screen() refuses, so any helper-vs-loop divergence on a future static rep errors toward `screening rejects …` red — but a literal reading of the comment would let a maintainer trust screen() for a relative-path or agent-home-spelling rep where it does not parity the loop.

## Coverage

Covered: landing audit of all 8 rows (mechanism + red-on-deletion cite each); BRE-metacharacter and root-last-operand audit of every new `$`-anchored pattern; S2 end-anchor, S1 prefix-uniqueness, S3 bare-arm verification against the wired blocklist, X3 arm-set/order literal diff; sed-extraction uniqueness/fragility; unanchored-negative re-sweep; new-variable collision + summary-gate placement; diff-hunk anti-pattern sweep; class-sweep claim spot-check (gpasswd/userdel/chown rc paths, no lexical guards on `DEFAULT_USER`/`OPENCODE_GROUP`); suite run green (`sh tests/unit/test-uninstall.sh` → "All uninstall tests passed."). Deferred, recorded: `make lint`/`make test`/docs-test and both e2e suites not re-run (resolution records them green on the committed fix tree `2632c36`; budget scope was the uninstall suite); line-by-line audit of every `OPENCODE_USER` consumer beyond the grep walk (:228-246, :340-346, :481-561, :502, :595 all inspected). Unverified: none — every suspicion raised was resolved by one follow-up read.

---

## Axis X (security), verbatim

# Review — pr-00243 fix wave 5, axis: security (diff `d8af4e0..59e700a`)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| X1 | LOW | Charset-valid pathological spellings (`.` `..` `opencode.` `-x` `--`) pass the gate and re-target the lexical guards and user-section consumers | fix wave limit (gate is writer-parity; the residual class is inherent to the chosen charset) |
| X2 | LOW | resolution.md e X1 row cites consumer line anchors in the pre-fix tree's numbering — all off by 14 lines vs the tree the row describes | fix wave (bookkeeping text) |
| X3 | INFO | Gate's `''` arm is unreachable in the shipped flow and unexercised by any pin | fix-introduced (dead defensive arm) |
| X4 | INFO | The WARN line embeds the raw corrupted value into a multi-line-capable stderr write | fix-introduced, consistent with sibling echoes |

No HIGH/MED. The core gate is correctly placed, correctly ordered, fail-closed for the realistic corruption shapes, and its pins are real (I ran `sh tests/unit/test-uninstall.sh` myself: green, matching the Gates claim).

## Details

### X1 — LOW — charset-valid pathological spellings survive the gate

Probes (scratch, verbatim extracted gate): `opencode/`, `opencode//`, `opencode/.`, `''`, space, newline, tab, unicode, `opencode:x` → all WARN+fallback. `.`, `..`, `opencode.`, `-x`, `--` → **pass through untouched**.

Consumers affected when such a value is hand-set in install.conf:

- **Agent-home refusal** (unsh:595 `if [ "${root%/}" = "/home/$OPENCODE_USER" ]`): with `OPENCODE_USER=.`, `..`, or `opencode.`, the compare target becomes `/home/.`, `/home/..`, `/home/opencode.` and a projects.conf entry `/home/opencode` no longer matches — the root-run revert ops (find-chown/setfacl/chmod, unsh:699-712) then run over the real agent home. That is the exact X1 hazard, surviving for dot-legal spellings. Trigger: root hand-edit to one of these spellings **plus** the agent home listed in projects.conf. Realism is limited — the realistic typo shapes (trailing slash, space) are closed — so LOW/latent.
- **User-removal section** (unsh:481): `--` is the one spelling where `id --` **succeeds** (verified in scratch: rc0, prints the invoking user). With `OPENCODE_USER=--`, `OC_UID=$(id -u --)` (unsh:528) resolves the developer's own uid and `sudo systemctl stop user@$OC_UID.service` (unsh:530) stops the **developer's** systemd user manager; the subsequent ops (`sudo -u --`, `pkill -9 -u --`, `userdel -r --`) all fail loudly, and the prompt at unsh:482 names `--` before anything fires. Requires dev confirmation of a prompt — LOW.
- **Config-dir walker** (unsh:340): `/home/./.config/opencode` — bounded to the kit's own plugin path, no-op if absent.

Mitigation on record: the charset is byte-identical to the writer's own gate (install.sh:588-595, same `''|*[!A-Za-z0-9_.-]*)` arm), so this residual is writer-parity by design, not an oversight. Leading-hyphen option injection into `userdel` (unsh:548) is effectively blocked by the `id "$OPENCODE_USER"` precondition at unsh:481 — `id -x`-style values die at id's getopt.

### X2 — LOW — resolution.md e X1 row anchors are stale (pre-fix numbering)

res (~line 538): "the LIVE_GROUP/id lookups (:214/:225-226), the agents-backup walk (:326/:332 …)". Verified against `d8af4e0:files/.../uninstall.sh`: 214 = `id -gn`, 225-226 = `UN_OC_UID/GID`, 326/332 = the config-dirs walker — i.e. the row describing the fix anchors its consumers in the **pre-gate** tree. In the working tree (59e700a) these are 228, 239-240, 340/346. The behavior claims themselves all verified accurate (gate after the `:-` default at 211, before every consumer at 228/239/240/340/346/481-561/595/834; extraction pin anchored and unique — start line unsh:220 is the only `^case "$OPENCODE_USER" in$`, first `^esac$` after it is 225, the gate's own). Stale anchors mislead the next reviewer's spot-checks.

### X3 — INFO — `''` gate arm unreachable and unpinned

unsh:211 `OPENCODE_USER="${OPENCODE_USER:-opencode}"` replaces unset-or-empty before the gate, so the `''` arm (unsh:221) cannot execute in the shipped flow, and the suite never drives it (the standalone pins feed three non-empty values; the driver default is `untest-agent`). Fine as a defensive safety net (mirrors the writer's arm), but the empty-value failure path — the one failure path the gate claims — has no pin, against the house fail-loud-pins rule (agent/learnings.md).

### X4 — INFO — WARN echoes the raw corrupted value

unsh:222 embeds `$OPENCODE_USER` unfiltered into the stderr write; probe-verified with newline/tab/unicode values (multi-line WARN, arbitrary bytes reach the terminal/log of the session). The writer of the corrupt value is root itself, and sibling echoes print raw conf values too (unsh:596, 616, 655), so this is consistent house behavior — recorded as latent, not a violation.

## Coverage

Covered: gate placement/order and every `OPENCODE_USER` consumer walk (all post-gate; `OPENCODE_GROUP` corruption is structurally defended — live `id -gn` override at unsh:229-232 when the user exists, empty-gid loud skip at unsh:703-707 when not; `DEFAULT_USER` reaching the chown argv at unsh:699 is conf-sourced and ungated, but pre-existing and fails loudly per the e X1 sweep's own class criterion — swept, claim verified, not re-flagged); full spelling corpus probes; `id --` behavior probe; sed extraction uniqueness and over-capture shapes (today exact; a future CRLF conversion or an earlier duplicate start line would mis-capture, but the `falling back` marker grep keeps it fail-closed — noted, not flagged); driver eval ordering (gate before loop, mirroring shipped) and stub log shape (`$*` join — root is the LAST operand on unsh:709/710/712, so the new `$` anchors bind real leak shapes and cannot be spoofed by longer operands; both bare and trailing-slash negatives present for setfacl and chmod; find negatives correctly stay on the ` !` continuation shape); helper/loop classification agreement on `/home/`, `/var/`, `/var//` (identical dot-gate arms, strip-then-blocklist order; blocklist extracted from the shipped file, parity by construction); claims audit of e X1 row + Gates section (e2e/sabotage records taken as recorded, unit-suite green re-verified locally) and the docs row (accurate: uninstall-only, WARN+fallback, valid customs still pass). Deferred: e2e suites and sabotage spot-checks re-execution (recorded evidence, out of micro-scope budget); `sh tests/unit/test-docs.sh` (row verified by inspection); `--` chain into `pkill`/`sudo -u` argument consumption details (each ends in a loud failure by inspection; not probe-exhausted — marked unverified beyond the `id` probes).

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed — severity held at INFO** | Both sides byte-verified: `git show d8af4e0:…uninstall.sh` — :214 `LIVE_GROUP="$(id -gn …)"`, :225-226 `UN_OC_UID/GID`, :326/:332 the config-dirs walker, :664 the find-chown; in the tree the row describes (59e700a) these sit at :228, :239-240, :340/:346, :679 (+14/+15). Every behavior claim in the row is accurate and the constructs are named unambiguously — only coordinates drift, the "outcome right, stated anchor wrong" class (e S4 precedent = INFO). X2's LOW rationale (misleads the next reviewer's spot-checks) weighed and rejected: the next reviewer greps the construct name, not the bare number. |
| S2 | **RETRACTED — trigger unreachable** | The claimed path needs an env-exported `OPENCODE_USER` to survive to the gate on a conf-less machine. unsh:87 `OPENCODE_USER="opencode"` (top-level literal, verified in the tree) clobbers any environment value unconditionally, BEFORE install.conf sourcing (:209-212) — the only writer of the variable after :87 is install.conf itself. On a conf-less machine the gate sees the :87 literal and passes silently; with a conf, an invalid value came from exactly the file the WARN names. No reachable input produces the scenario; the WARN's `install.conf` attribution is accurate on every path that exists. |
| S3 | **confirmed — INFO** | Comment read in full (test:276-281): the colon-scoped expansion names exactly dot/empty-segment gate → strip → blocklist, which is the helper's entire content, in the loop's order (loop dot gate unsh:613-615, arm-for-arm identical to test:283; strip unsh:634-639; blocklist unsh:649+). The loop's agent-home (:595), `[ ! -d ]` (:601) and non-absolute (:605-611) gates are outside screen()'s stated contract (`0 = screened (system path, skipped)`) and no input classifies differently between helper and loop today; any future divergence reds (`screening rejects …` direction). Kept INFO as the claim-scope class (the phrase "IN FULL" literally claims the full loop chain); wording-breadth only, no behavioral gap. |
| X1 | **confirmed — LOW conditional; provenance corrected** | Probe corpus re-run by the main session (/tmp/opencode/pr-00243-f/verify): `opencode/`, `opencode//`, `opencode/.`, space, tab → FALLBACK; `.`, `..`, `opencode.`, `--`, `-x`, `opencode-x` → PASS. Sub-hazard (a) verified by compare logic: with `OPENCODE_USER=` `.`/`..`/`opencode.` the compare target `/home/…` never matches a projects.conf `/home/opencode` entry and no blocklist arm catches it (no `/home/*` sibling, unsh:649-653) → root-run ops over the agent home — but this spelling class passed the pre-d-wave dual compare and the pre-gate single compare identically (same interpolation), so it is a never-caught residual, not a wave regression: provenance **pre-existing residual** (the gate narrowed the corruption class from "any invalid shape" to "charset-valid pathological spellings"). Sub-hazard (b) verified: `id --` rc0 resolving the INVOKING user (probe: uid 1001), the section prompt names the literal (unsh:482) before `systemctl stop user@$OC_UID.service` — dev-confirmed prompt gates it. LOW stands: both sub-hazards need a root hand-edit of install.conf plus a second explicit action (agent home in projects.conf / "y" at a prompt naming the value). |
| X2 | **confirmed — merged into S1** | Same evidence as S1, discovered independently by both axes (the S axis's landing-audit cite walk and the X axis's consumer walk); one disposition, recorded once. Severity adjudicated with S1 (INFO). |
| X3 | **confirmed — INFO** | Reachability trace: unsh:87 literal → install.conf sourcing is the only other writer → a conf line `OPENCODE_USER=` (empty) is replaced by the `:-` default at :218 before the gate at :220 → the `''` arm (:221) is unreachable in the shipped flow; the pins feed non-empty values only (test:404-424; driver default test:446). Byte-parity with the writer's defensive arm verified (install.sh:589-592 — same `''\|*[!A-Za-z0-9_.-]*)` shape, likewise structurally defensive there). Record-only: dead defensive arm, no executable path claims a pin. |
| X4 | **confirmed — INFO latent** | unsh:222 verified: `echo` (no format-string surface) embedding raw `$OPENCODE_USER` into stderr. With S2 retracted, the value is conf-sourced only — root-authored input reaching a root-run script's terminal, the same trust level as the sibling raw echoes (unsh:596, :616, :618, :650 — all print raw values). Multi-line WARN verified as reachable only via newline-in-conf (root hand-edit). Record-only, house-consistent. |

Verification notes beyond the findings:

- **Landing-audit spot-checks:** the S axis's mechanism+pin cites for
  all 8 implemented e-findings re-checked against the shipped tree
  (gate block unsh:220-225 read directly; extraction pin test:391-395,
  standalone pins test:402-424, chain arm test:934-951, anchored raw
  echo test:918, `.` chmod negative test:815, static list test:299,
  `$`-anchors test:891-894/:901-902, helper dot gate test:282-284 all
  located in the diff hunks; the e X2 and e S4 correction paragraphs
  read at res:470-476 and :515-520).
- **Writer-parity claim byte-verified:** install.sh:349 literal
  `OPENCODE_USER="opencode"`, :589-592 the writer's charset gate with
  the identical `''|*[!A-Za-z0-9_.-]*)` arm, :1339 the conf heredoc
  stamping the variable — the gate's documented design anchor holds.
- **Root-last-operand premise (e S5 anchors):** the op tail read —
  `sudo setfacl -R -x/-d -x … "$root"` and `sudo chmod g-s "$root"`
  end in the root operand; the find op carries its ` ! -type l …`
  continuation and correctly keeps the ` !` anchor (d Q4 shape).
- **Bare-arm verification (e S3):** wired blocklist arms read at
  unsh:649-653 — `/home` bare with no `/home/*` sibling, `/var` bare
  with enumerated subdirs — `/home/` and `/var/` are discriminating
  trailing-slash forms; strip deletion reds on both.
- **Suite:** `sh tests/unit/test-uninstall.sh` green at baseline
  (main session, before fan-out) and in both reviewer runs.

## Retracted/ghost findings

- **S2 (INFO, retracted):** "WARN names the wrong source on the
  env-inherited path." Retracted in verification — the trigger is
  unreachable: the top-level literal `OPENCODE_USER="opencode"`
  (unsh:87) clobbers any environment value before install.conf
  sourcing, so an invalid value at the gate can only have come from
  install.conf, exactly what the WARN names. Recorded per RM-0075: the
  axis reported a message-precision hazard without tracing the
  variable's writers above the sourcing block; the main session's
  writer-trace (extending review e X1's own :88-literal observation to
  this wave's new gate) closed it. Calibration: unverified
  reachability claims about value flow need a full writer walk, not
  just the consumer-side read.

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Micro-Wave-Review
  f"). Sixth snapshot of the case; rotation normal (this fresh session
  authored neither the e-wave's fixes nor any prior snapshot of the
  chain).
- Tree: 59e700a (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty), re-verified clean after all
  reviewers returned (no mutations ran on the repo tree at any point —
  reviewer and main-session probes lived under /tmp/opencode/pr-00243-f/).
- Material: fix diff d8af4e0..59e700a; shipped files only in 2632c36:
  uninstall.sh 18 changed lines, test-uninstall.sh 124,
  docs/reference/files.md 2; 59e700a resolution.md bytes are bookkeeping
  (and became review material only as the S1/X2 finding target). Scope
  commissioned as **micro**; measured shipped diff is 144 changed lines
  (18 production-with-comments + 124 test pins + 2 docs) — above the
  ~50-line micro bound on raw count, dominated by pin blocks over a
  6-line production gate plus comments. Run at micro parameters per the
  commission: 2 axes (S sweep/landing-audit, X security), ~5-minute
  budgets, batched greps + targeted reads, no whole-file reads.
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T20:56:16Z; both reviewers returned by 21:07:07Z (host
  re-check; both subagent completions landed in the same tool batch).
  Checkpoint file stamps inside the host window after normalization:
  x.md 23:04, s.md 23:05 (sandbox local = UTC+2) — no skew anomaly.
- Reviewer subagents: 2 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-flash, fresh contexts, axis prompts built
  from `.agents/skills/opk-review-pass/axis-prompt.md`; the main
  session (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-f/checkpoints/{s,x}.md` (outside
  the reviewed tree), both with launch + per-section stamps. Reviewer
  probes under `/tmp/opencode/pr-00243-f/probe-x/`; main-session
  verification probes under `/tmp/opencode/pr-00243-f/verify/`.
- Sabotage/mutation windows: none — no tree mutations at any point
  (read-only reviewers; main-session verification by probes and code
  reads only). No screening in either direction required.
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green (baseline before
  fan-out; both reviewers ran it independently, green); `make lint`
  green (baseline); `make test` green; `sh tests/unit/test-line-length.sh`
  green (review-* snapshots exempt from the ratchet — verbatim over
  wrap); INDEX regenerated with this commit
  (`python3 scripts/gen-review-index.py`); `sh tests/unit/test-reviews-lint.sh`
  and `sh tests/unit/test-reviews-parity.sh` green before the commit
  carrying this file.
- e2e: no new debt — this snapshot changes no shipped code; the
  reviewed fix wave already ran both suites in-wave (resolution Gates:
  `make e2e` 309, `make e2e-rootless` 47 on `2632c36`; the shape gate
  is a no-op on the canonical conf the suites model, and the X1
  residual's corrupted-conf corners are outside e2e modeling — the
  disposition, not an e2e run, closes it).

## Recommendation

The e-wave's fixes all landed (8/8 mechanisms with pins, audited and
spot-confirmed): the agent-home refusal's load-bearing precondition is
now reader-enforced for every shape-invalid spelling, and the pins
discriminate per spelling, per form and per arm. The round's own
findings:

- **f X1 (LOW, conditional, pre-existing residual)** is the one with a
  decision to make: the writer-parity charset deliberately admits
  `.`, `..`, `opencode.`, `-x`, `--` — spellings that still defang the
  agent-home refusal (dot-legal) or reach the user-removal section with
  `id --` resolving the invoking user (`--`). Two disposition shapes
  close it: a deliberately-not-done row naming the triggers (root
  hand-edit + second explicit action) as accepted residual — the
  writer's own gate admits the same spellings by design — or a
  stricter reader-side charset (e.g. refusing leading dot/hyphen)
  which diverges from writer parity and owes its own micro round.
- **f S1 (≡X2, INFO)** is bookkeeping: the resolution's e X1 paragraph
  anchors its consumers in pre-gate coordinates — correct them in the
  f-wave's resolution bookkeeping (bracketed correction paragraph, the
  house pattern) or leave as named-construct history.
- **f S3/X3/X4 (INFO)** are record-only or ride-along: the screen()
  comment wording (S3) can ride the next test-touching wave; the dead
  `''` arm (X3) and the raw-value WARN embed (X4) need nothing.

Per the stop rule (RM-0064/RM-0067): a next round that only
dispositions X1 deliberately-not-done and corrects the resolution text
(S1) stays in bookkeeping and leaves review-relevant code untouched —
stop-rule eligible. A round that tightens the gate's charset touches
production code — review-relevant — and owes one more micro round. The
loop's state is the maintainer's call — this session records, it does
not close.
