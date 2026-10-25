<!-- review-meta
ID: pr-00244
Snapshot: c
Subject: issue-223 fix-wave 2 dispositions (wave review of the b-round fixes)
Scope: wave
Base: 0.0.56+59 @ 69acb28 (VERSION 0.0.56)
Diff: 69acb28..ff2876c
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session D of the rotation (fix commits 25f96f1/ff2876c authored by session C)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review c — wave review of the fix wave (pr-00244)

Round c over the b-round fix diff `69acb28..ff2876c` (two commits:
`25f96f1` the dispositions — `_py3_imports` measured import union with
the drift pin, the noisy-case diagnostic passthrough pin, `-I` comment
rescoping, the root-exec sentence, §11e setsid guard + drain-marker
arm proof, `_p3d` removal, the README trailer rule; `ff2876c`
bookkeeping — b-row SHA fills, wave-2 e2e discharge, sabotage record,
issue refs #248-#251). The wave answers review-b's 9 IDs (8 unique);
all implemented, none deliberately not done.

Tree `ff2876c`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

14 reported IDs, 11 unique findings (three cross-axis duplicate pairs:
W2=Q1 — kept verbatim per axis with a severity split LOW/MED,
dispositioned once; W4=Q2; Q4 duplicates the verified clause of W5).

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | The noisy-shim fixture's recorded scanner false-positive mechanism does not reproduce against the shipped check-3 regex; the hyphenation fix is harmless but its justification is an unverified claim, and the marker now silently deviates from CPython's real diagnostic wording | wave-introduced |
| S2 | LOW | Shipped `-I` concession comments name only loader+binary residuals and omit the system site-packages/`.pth` startup-execution route that the b-S1 finding and resolution.md both name — conceding less than the truth | fix-induced |
| S3 | LOW | The stderr-transparency class (b S2) is fixed at the installer gate only; five same-shape sibling consumers still swallow interpreter stderr and the wave's L2 class-sweep record does not name this class as swept or deferred | sites pre-existing; record gap wave-introduced |
| S4 | INFO | The drift pin's extraction covers only documented import shapes; the test's promise ("a new consumer … goes red here") is unbounded but the enforcement is shape-scoped — a bypass is silent, reintroducing the a-W1 hole without a red pin | wave-introduced |
| W1 | LOW | Drift pin silently drops inline `-c 'import X; …'` semicolon one-liners — the most common `-c` idiom bypasses the "enforced sweep" with no red | wave-introduced |
| W2 | LOW | Extraction globs cover 4 of the lib's 6 subdirs (`tui/`, `templates/` missed; single-level only) while resolution.md claims "a new consumer anywhere in the lib goes red" (dup of Q1) | wave-introduced |
| W3 | LOW | No count pin on `_py3_imports`: a second assignment unions the pin's gate list but only the LAST assignment runs at runtime — silent pin/runtime divergence | wave-introduced |
| W4 | LOW | resolution.md class-sweep record says "§11e is the only setsid user" — test-ui.sh uses setsid ~25 times (differently guarded); the record misstates its own cited grep (dup of Q2) | wave-introduced |
| W5 | INFO | §11e arm-proof comment overstates the marker: write() returning proves all but up to one pipe buffer (~64 KiB tail) consumed; marker also fires if the writer python died — SECOND CLAUSE RETRACTED in verification, see Retracted/ghost (dup superset of Q4) | wave-introduced |
| Q1 | MED | Drift-pin sweep record claims "a new consumer anywhere in the lib goes red" — the glob covers only 4 of the lib's 6 shipped subdirs (`templates/`, `tui/` are outside) (dup of W2) | wave-introduced (25f96f1/ff2876c) |
| Q2 | LOW | Class-sweep record states "`grep -rn 'setsid' tests/unit/` — §11e is the only setsid user"; false — test-ui.sh has 5+ setsid call sites (dup of W4) | wave-introduced (ff2876c) |
| Q3 | LOW | New §11e poll uses unguarded fractional `sleep 0.25` under the suite's `set -e` — in the very block that was portability-guarded for `setsid` | wave-introduced (25f96f1) |
| Q4 | INFO | "the tee has consumed the whole stream and sits blocked in read" — a 1 MiB fifo write returns with up to ~64 KiB (pipe capacity) still unconsumed (dup of W5's verified clause) | wave-introduced (25f96f1) |
| Q5 | INFO | `_p3f=""` pre-declaration is dead code — no `set -u`, and the for-loop assigns before any read | wave-introduced (25f96f1) |

Provenance split: 11 wave-introduced (the reviewed fix wave's own
output), 1 fix-induced (S2 — the b-S1 fix's own comment text), 1
pre-existing-sites/record-gap split (S3). No HIGH; one MED (Q1, dup
pair with W2 at LOW) — the stop rule reads MED/HIGH, so dispositions
that touch review-relevant code extend the loop.

---

## Axis S (security), verbatim

# Security review — pr-00244 b-wave diff `69acb28..ff2876c` (axis: security)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | The noisy-shim fixture's recorded scanner false-positive mechanism does not reproduce against the shipped check-3 regex; the hyphenation fix is harmless but its justification is an unverified claim, and the marker now silently deviates from CPython's real diagnostic wording | wave-introduced |
| S2 | LOW | Shipped `-I` concession comments name only loader+binary residuals and omit the system site-packages/`.pth` startup-execution route that the b-S1 finding and resolution.md both name — conceding less than the truth | fix-induced |
| S3 | LOW | The stderr-transparency class (b S2) is fixed at the installer gate only; five same-shape sibling consumers still swallow interpreter stderr and the wave's L2 class-sweep record does not name this class as swept or deferred | sites pre-existing; record gap wave-introduced |
| S4 | INFO | The drift pin's extraction covers only documented import shapes; the test's promise ("a new consumer … goes red here") is unbounded but the enforcement is shape-scoped — a bypass is silent, reintroducing the a-W1 hole without a red pin | wave-introduced |

## Detail

### S1 · LOW · Recorded scanner false-positive mechanism does not reproduce; marker deviates from real CPython wording

Evidence — `tests/unit/test-install-args.sh:857-861`:

```sh
    # (Hyphenated marker wording:
    # the sandbox scanner greps raw lines quote-blind — "platform
    # independent" + a "$VAR/" operand on one line chains into a false
    # rm-suffix match.)
    printf '#!/bin/sh\necho "Could not find platform-independent libraries" >&2\nexit 9\n' > "$_py3w/noisy/python3"
```

and `internal/reviews/0/0/2/4/pr-00244/resolution.md:281` (class-sweep record): `one scanner false positive ("platform independent" chains into the raw-line rm-suffix grep) was fixed at the source by hyphenating the marker`.

I replayed check 3's exact regex (`tests/unit/test-sandbox-policy.sh:287`) against both the unhyphenated and hyphenated fixture lines in `/tmp/opencode/pr-00244-c/s-probe/`: **neither matches (rc=1 both)**. The only `rm` substring in the line is inside "platfo**rm**", but the chain dies at the embedded double-quote run (`libraries"`), and the check-1/check-2 views are identical for both wordings (quote-blanked to `printf X > X`; no real-tree token). Checks 1/2/3 are all clean on the unhyphenated shape. So the hyphenation was not required by the shipped scanner, and the recorded mechanism ("chains into a raw-line rm-suffix grep") is unverified — an L3 claim-audit miss (`agent/learnings.md`) inside the very record that certifies the sweep.

Axis question answered with evidence: the hyphenation **cannot hide a real rm violation** — the marker text participates in no structural `rm`/path pattern and no allowlist entry (`test-sandbox-policy.sh:55-70`) keys on it. Fidelity note: real CPython prints `Could not find platform independent libraries` (unhyphenated), so the fixture no longer reproduces the real-world diagnostic text it claims to model, and the S2 pin greps the shim's own wording — mechanism, not real text.

### S2 · LOW · Shipped `-I` residual concession is under-inclusive vs the finding it disposes

Evidence — `files/install.sh:550-552`:

```
# (#244 a S1) — the -I scope is those env vars, not the whole
# environment: the loader route (LD_PRELOAD/LD_LIBRARY_PATH) and the
# PATH-resolved binary itself stay outside any python flag (#244 b
```

`files/opencode-permissions-kit-lib/sh/fs-baseline.sh:140-141`: `# S1; the -I scope is exactly those env vars, #244 b S1).`

But the b-S1 finding it implements (`review-b.md:36`) names **three** routes: "the loader route (LD_PRELOAD), the PATH-resolved binary, **and system dist-packages/.pth execution**", and the resolution's own S1 correction (`resolution.md`, Evidence detail b S1) concedes all three. `-I` implies `-E -s -P`, not `-S`: system site-packages are still processed, so a `.pth` file there executes at interpreter startup even under `-I`. The shipped comment — the durable rationale a future maintainer reads, which is exactly what b-S1 said matters — enumerates "not the whole environment: A and B", a colon-list that reads as exhaustive, and omits the third route. Related imprecision: fs-baseline's tee comment "the -I scope is **exactly** those env vars" understates in the conservative direction (`-s`/`-P` are additional real protections — they close the user-site `.pth` route), so the three shipped surfaces state the residual three different ways. Severity is LOW because every version errs or omits in the non-overclaiming direction; no isolation is claimed that `-I` does not provide.

### S3 · LOW · Interpreter-stderr transparency fixed at one site; sibling class unswept and unrecorded

Evidence — the consumers still swallowing interpreter stderr on failure:
- `files/opencode-permissions-kit-lib/management/status.sh:216`: `&& python3 -c 'import sys, threading, time' >/dev/null 2>&1 \`
- `files/opencode-permissions-kit-lib/management/status.sh:540`: `python3 -c 'import json,sys` (failure → "unavailable", stderr discarded)
- `files/opencode-permissions-kit-lib/management/update.sh:1154-1162`: `| python3 -c 'import json,sys …' 2>/dev/null || true` (resolve → "could not resolve")
- `files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:73`: `import json, sys` (empty-on-failure contract)
- `files/opencode-permissions-kit-lib/bin/opk:301`: `sudo -u "$_oc_duser" python3 - …` (runs as the opencode user, not root — lower stakes)

The wave's L2 record (`resolution.md:270`, "Class sweep record (L2, fix wave 2)") lists the import-union pin and the setsid/rm greps — the stderr-swallowing class is absent, and the filed follow-ups name different classes: #248 (update.sh timeout presence probes) and #249 (kit-wide `-I` env scope). Per `agent/learnings.md` L2, a class fix counts only after the same-shape sibling sweep is recorded. The installed kit still degrades attributelessly on exactly the interpreter-failure class the installer gate now names — a stated inconsistency would cost one sentence; instead it is implicit at best. All siblings degrade by design (warn/passthrough/return 1), so this is a record/consistency gap, not a runtime defect.

### S4 · INFO · Drift pin's "goes red here" promise is shape-scoped

Evidence — `tests/unit/test-install-args.sh:939-945`: extraction covers "line-start imports in .py files and python blocks embedded in sh/bin scripts (comment lines stripped), plus inline `-c 'import ...'` probes"; the promise at :936-938 is unbounded: "a new consumer adding an import without extending the gate goes red here". A future consumer using a double-quoted `-c "import x"` probe, mid-line imports, or `importlib`/`__import__` bypasses the extractor silently. I replayed the extraction over the shipped lib: it collects exactly the 11 gate modules — faithful for every shape shipped today, so the b-Q1 "union" claim is currently true. Flagged because the failure mode of the promise (silent bypass, gate passes while the consumer fails attributelessly) is the precise a-W1 hole this pin exists to prevent.

## Explicitly clean (verified, no finding)

- **Injection/word-splitting on `_py3_imports`**: single-quoted static literal (`install.sh:571`), expanded double-quoted into a single `-c` argv element (`:576`, `:581`) — no surface. The test-side `eval` extraction (`test-install-args.sh:848-849`) operates on repo-controlled `$INSTALL` (`:37`); the range `/^_py3_health_probe() {/,/^}/p` matches the intact function (body has no early `^}`); a broken range fails loud at eval, not silently green. Pre-existing `_distro_gate` pattern.
- **New `|| true` instances**: the diagnostic rerun guard (`install.sh:581`) is load-bearing under `set -eu` (`install.sh:46`) and pinned by an executing failure path — the suite runs `set -e` (`test-install-args.sh:30`), so without the guard the noisy case's subshell would die rc 9 before `ui_error` and the rc-1 + both-greps assertions (`:910-912`) would go red. The drift-pin greps' `|| true` are pinned by the non-empty surface check (`[ -s "$_p3mods" ]`). No unpinned fail-open found.
- **Guarded rm operands / slash forms**: `rm -f "${_py3w:?}/err"` (`:877`) — the `:?` colon correctly exempts it from check 3's suffix group; `rm -rf "$_py3w"`, `rm -f "$_p3raw" "$_p3mods" "$_p3g"`, `rm -rf "$W23KI"` are pure-variable operands (mktemp-derived, non-empty by `set -e` before the rm) — exempt per the policy's own rationale. `x/`, `x//`, `x/.` operand shapes: check 3's pattern flags all unguarded suffix forms regardless of trailing shape; none appear in this diff.
- **W23KI restructure**: all references inside the setsid branch (`test-fs-baseline.sh:690-756`); no orphaned cleanup; the arm-proof logic is sound (fifo write returns only after the tee drained ⇒ interpreter startup and KI handler installation are guaranteed; never-armed fails red at `:730-734`; poll = 40×0.25 s as commented). The setsid skip branch is unpinnable on hosts that require setsid — recorded pattern, not a gap.
- **Unintentional behavior changes**: the `ui_error` wording change is deliberate (b S2); no doc or e2e pin the old installer text (the `tests/e2e/run.sh:1281/1288` "present but broken" hits are opk status's own surface). fs-baseline.sh hunks are comment-only; no behavior change.

## Coverage

Covered: install.sh gate hunk + pre-flight caller and shell-option posture; fs-baseline.sh hunks (comment-only verified) + `-I` mechanics check; test-install-args matrix (extraction, shims, noisy case, rm guards), the drift pin (replayed end-to-end against the shipped lib), test-sandbox-policy scanner mechanics (check-3 regex probed empirically, both wordings, in `/tmp/opencode/pr-00244-c/s-probe/`), W23KI branch structure and arm-proof logic; sibling stderr-swallower sweep classified against the resolution's L2 record; every new `|| true` in the diff traced to a pin.

Deferred: full audit of install.sh beyond the gate/pre-flight (~2000 lines; diff-scoped axis, budget); the intermediate fixture shape that produced the original "false positive" report is undiffable from `69acb28..ff2876c` and could not be reconstructed — S1 records what could not be verified rather than asserting it; opk status's own health message (different surface, untouched by the diff).

---

## Axis W (mechanical sweep), verbatim

# Review pr-00244, wave `69acb28..ff2876c` — axis W (mechanical sweep)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Drift pin silently drops inline `-c 'import X; …'` semicolon one-liners — the most common `-c` idiom bypasses the "enforced sweep" with no red | wave-introduced |
| W2 | LOW | Extraction globs cover 4 of the lib's 6 subdirs (`tui/`, `templates/` missed; single-level only) while resolution.md claims "a new consumer anywhere in the lib goes red" | wave-introduced |
| W3 | LOW | No count pin on `_py3_imports`: a second assignment unions the pin's gate list but only the LAST assignment runs at runtime — silent pin/runtime divergence | wave-introduced |
| W4 | LOW | resolution.md class-sweep record says "§11e is the only setsid user" — test-ui.sh uses setsid ~25 times (differently guarded); the record misstates its own cited grep | wave-introduced |
| W5 | INFO | §11e arm-proof comment overstates the marker: write() returning proves all but up to one pipe buffer (~64 KiB tail) consumed; marker also fires if the writer python died | wave-introduced |

No HIGH/MED findings. The pin is empirically green today with an exact 11=11 module match (probe below).

## Details

**W1 — LOW — semicolon `-c` one-liners silently dropped by the drift pin's module regex.**
`tests/unit/test-install-args.sh:968-970` collects inline probes (`grep -oE -- "-c[[:space:]]+'import[^']*"` → `sed "s/.*'//"`), then the pipeline at :972-975 strips `import `, splits on commas, and filters with `^[A-Za-z_][A-Za-z0-9_.]*$`. For `python3 -c 'import znewmod; znewmod.run()'` the extracted token is `znewmod; znewmod.run()` — one comma-free token that the regex rejects, so `znewmod` never reaches `$_p3mods`. Verified empirically in `/tmp/opencode/pr-00244-c/w-probe/`: the shipped pipeline run against a fixture one-liner yields an empty module set. Related fragility in the same grep: `sed "s/.*'//"` (:970) strips through the LAST quote on the line, so a one-liner containing a later `'` (e.g. the suite's own §11e writer line `import sys; sys.stdout.buffer.write(b"e\0" * …)`) extracts to nothing. Why it matters: resolution.md ("Class sweep record (L2, fix wave 2)") calls this pin "the enforced sweep for the import-union class", and a future consumer written as a semicolon one-liner gets gate coverage nowhere and red nowhere. All 6 current lib `-c` sites are comma-pure or newline-led (line-start route catches those), so the pin is green today — the gap is silent future-drift only. LOW, not MED: no shipped behavior affected, and the line-start route independently covers heredoc/multiline programs.

**W2 — LOW — glob coverage vs the "anywhere in the lib" claim.**
`ls files/opencode-permissions-kit-lib/` shows six subdirs: `bin`, `management`, `py`, `sh`, `templates`, `tui`. The pin globs only four (:958-961). Currently zero import surface in `tui/` (`.tsx`/`.json` — and TSX `import fs from "node:fs"` shapes would be regex-rejected anyway) or `templates/` (jsonc/json/sudoers), so nothing is missed today. But resolution.md claims "its extraction runs over py/, sh/, management/ and bin/ (glob), so a new consumer anywhere in the lib goes red without touching the pin" — false for `tui/`, `templates/`, a loose lib-root file, or any subdirectory of a globbed dir (`py/vendor/x.py`, `bin/tool.d/helper`). LOW: future-drift gap plus an inaccurate bookkeeping claim; the test's own comment block (:940-945) honestly documents only the four globs.

**W3 — LOW — `_py3_imports` has no assignment-count pin.**
`tests/unit/test-install-args.sh:946` extracts EVERY line matching `_py3_imports='…'`; the pipeline at :948-951 unions all extracted values via `sort -u`, while the runtime gate (`files/install.sh:576,581`) executes `python3 -I -c "$_py3_imports"` — i.e. only the LAST assignment wins in shell semantics. No `grep -c`-style pin exists for the assignment (grep shows the sed and a comment only). Scenario: a future edit adds a second `_py3_imports=` line; modules present only in the first assignment keep the pin green while the runtime probe stops exercising them. Today exactly one assignment exists (`files/install.sh:571`). LOW: silent mechanism, no current instance.

**W4 — LOW — sweep-record sentence contradicted by test-ui.sh.**
resolution.md: "`grep -rn 'setsid' tests/unit/` — §11e is the only setsid user". test-ui.sh:36-39 hard-requires setsid (`command -v setsid … || { echo "test-ui: setsid (util-linux) is required for hermetic runs" >&2; exit 1 }`) and uses it at :44 and ~25 further sites. The substantive sweep conclusion holds — every setsid use in tests/unit is guarded (§11e skip-with-note; test-ui hard-require) — but the record misstates its own grep result; anyone re-running the cited command hits test-ui.sh first. LOW: bookkeeping accuracy only, no behavior.

**W5 — INFO — marker semantics overstated in the §11e comment.**
`tests/unit/test-fs-baseline.sh:698-700` claims the marker "appears only once the tee consumed the whole stream (a fifo write blocks until read)"; :705 writes it after the 512 KiB write. A blocking `write()` returns when the last byte is accepted INTO the pipe buffer (default 64 KiB), so consumption at marker time is ≥ ~448 KiB, not necessarily the tail. The load-bearing property — interpreter initialized, tee live and blocked in read at signal time — holds regardless, and the asserted surfaces (no Traceback, no completion line) are unaffected. Second clause: the marker line is `;`-separated after the writer python (:703-705), so a writer killed by EPIPE (tee died first) still writes the marker and the arm pin passes green in exactly the broken-tee scenario — the content greps (:746-755) then own detection for loud deaths; silent deaths are undetectable by the surface's contract, as the resolution itself argues. INFO: comment precision, no assertion weakened in a way the pins miss.

## Verified clean (checks executed)

- **Probe**: shipped pin pipeline reproduced in `/tmp/opencode/pr-00244-c/w-probe/` — gate list and shipped-surface list both exactly `fnmatch, importlib.util, json, os, pathlib, re, stat, sys, tempfile, threading, time`; `comm -23` empty. Green today.
- **Pattern shapes**: no `-c "import` (double-quoted) anywhere in `files/`; no `import a as b`; no relative `from .` imports; trailing comments handled (full-line comment strip + `[^#]*` grep stop); prose `from the Windows hosts file` (`bin/opk:126`) correctly not captured; `from X import (…)` collecting `X` is correct gate semantics (interpreter health, not submodule preflight — residual documented in resolution.md a-S1). `ddev-terminal.sh:73` (the "ddev describe" source), the tee's newline-led `-c '` program (`fs-baseline.sh:149`), `status.sh:146` heredoc, `opk:301` heredoc — all captured via the line-start route; gate comment's source enumeration is complete.
- **Matrix**: `_p3d` zero refs; all 5 `_py3case` call sites 2-arg (:886-910); noisy case has all three discriminations (:910-913); ui_error stubbed to stderr (:882) matching the comment's claim; hyphenated-marker comment at :855-859 matches the resolution's scanner story; healthy-case silence assertion `[ ! -s "$_py3w/err" ]` intact.
- **§11e**: `W23KI` refs all inside the guard except the harmless assignment at :690; `rm -rf "$W23KI"` at :756 inside the guard (nothing created on setsid-less hosts); skip-note shape matches the §11c bash-rider (:649 vs :758); `W23KIWAIT` 40×0.25 s = 10 s as commented; `fail()` does not exit (cleanup runs even on the red path); `sleep 0.25` follows existing suite practice (`test-status.sh:2621` uses `sleep 0.05`).
- **Count pins**: presence-only gate grep count = 1 (inside `_py3_health_probe`); empty-collection caught by the `[ -s "$_p3mods" ] && [ -s "$_p3g" ]` pair (:977); `comm -23` inputs both `sort -u` in one locale — no residue path to false-green.
- **rm-operand convention** (`agent/conventions.md:142-150`): new path-shaped operand guarded (`rm -f "${_py3w:?}/err"`, :877); `rm -f "$_p3raw" "$_p3mods" "$_p3g"` (:988) is pure-variable → deliberately exempt. Compliant.
- **Bookkeeping**: `ff2876c` touches only resolution.md; all 8 b-rows filled with `25f96f1`; rows match review-b.md (9 findings, 8 unique after the Q1≡W1 dup, 1 MED + 4 LOW + 3 INFO); trailer of 25f96f1 enumerates all 9 IDs and qualifies "all implemented, none not done" — true against the rows and conforming to the new README step-5 rule it introduces; ff2876c enumerates no finding IDs (rule N/A); wave-2 e2e discharge recorded on the correct tree (25f96f1, 309+47, parallel); issue refs #248-#251 explained in Follow-ups.

## Coverage

Covered: all five budgeted sections over the wave diff, plus an empirical replay of the drift-pin pipeline and the semicolon-gap probe (read-only; artifacts under `/tmp/opencode/pr-00244-c/w-probe/`). Deferred: running any suite or make target (role-forbidden); reading the e2e logs and the archived §11e log referenced by host paths in resolution.md (outside the tree and outside this role — their contents are taken from the resolution, not independently verified). No unverified suspicions remain flagged.

---

## Axis Q (quality), verbatim

# Quality review — pr-00244 b-wave (`69acb28..ff2876c`)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | MED | Drift-pin sweep record claims "a new consumer anywhere in the lib goes red" — the glob covers only 4 of the lib's 6 shipped subdirs (`templates/`, `tui/` are outside) | wave-introduced (25f96f1/ff2876c) |
| Q2 | LOW | Class-sweep record states "`grep -rn 'setsid' tests/unit/` — §11e is the only setsid user"; false — test-ui.sh has 5+ setsid call sites | wave-introduced (ff2876c) |
| Q3 | LOW | New §11e poll uses unguarded fractional `sleep 0.25` under the suite's `set -e` — in the very block that was portability-guarded for `setsid` | wave-introduced (25f96f1) |
| Q4 | INFO | "the tee has consumed the whole stream and sits blocked in read" — a 1 MiB fifo write returns with up to ~64 KiB (pipe capacity) still unconsumed | wave-introduced (25f96f1) |
| Q5 | INFO | `_p3f=""` pre-declaration is dead code — no `set -u`, and the for-loop assigns before any read | wave-introduced (25f96f1) |

## Details

**Q1 — MED — "anywhere in the lib" overclaims the drift pin's coverage.**
Evidence: `internal/reviews/0/0/2/4/pr-00244/resolution.md:272-275` — "The drift pin IS the enforced sweep for the import-union class — its extraction runs over py/, sh/, management/ and bin/ (glob), so a new consumer anywhere in the lib goes red without touching the pin". The glob at `tests/unit/test-install-args.sh:958-961` covers exactly `py/*.py`, `sh/*.sh`, `management/*.sh`, `bin/*`. The lib's shipped tree (`find files/opencode-permissions-kit-lib -type d`) is **six** subdirs: `bin/`, `management/`, `py/`, `sh/`, `templates/`, `tui/` (plus lib root). `templates/` and `tui/` are outside the glob. Why it matters: the recorded enforcement guarantee — the whole point of the b Q1 fix — is false as written. Realistic trigger: a future python consumer placed under `tui/` (a dir that already ships registerable assets) or `templates/`, or at lib root, adding an import without extending `_py3_imports` does **not** go red — silently reintroducing the exact b Q1 gap. Today's claim "every shipped python import appears there" (install.sh:569-570 comment) is true only because all current consumers happen to sit in the four globbed dirs. Condition for materialization: new consumer outside the four dirs — unlikely but exactly the drift scenario the pin was built for.

**Q2 — LOW — sweep record misstates its own grep.**
Evidence: `resolution.md:276-277` — "`grep -rn 'setsid' tests/unit/` — §11e is the only setsid user". Tree: `tests/unit/test-ui.sh:44,130,133,139` (and more) call `setsid`; `tests/unit/test-uninstall.sh:474` references it. The substantive conclusion survives — test-ui.sh hard-requires setsid at startup (`test-ui.sh:36-37`, loud, not vacuous), so no sibling shares §11e's b W2 flaw — but the recorded evidence sentence is false on the grep's own terms, and the L2 discipline (agent/learnings.md: record grep pattern and sites checked) exists so the record can be trusted without re-running it.

**Q3 — LOW — unguarded fractional sleep beside a carefully-guarded setsid.**
Evidence: `tests/unit/test-fs-baseline.sh:726-728` — `while [ ! -e "$W23KI/ready" ] && [ "$W23KIWAIT" -lt 40 ]; do sleep 0.25; …` with `set -e` at `test-fs-baseline.sh:16`; the same block guards `setsid` presence (`:691`) because the suite may run where it's absent. POSIX `sleep` takes only integers; on a host whose sleep rejects `0.25`, every iteration fails and `set -e` aborts the entire suite mid-block — not even reaching the "never armed" red or the skip note. Conditions: non-GNU/non-busybox sleep only (supported WSL2 Ubuntu/Debian ship coreutils, where this works — hence LOW). Note the failure mode is loud either way; no vacuous pass.

**Q4 — INFO — "consumed the whole stream" is off by a pipe buffer.**
Evidence: `tests/unit/test-fs-baseline.sh:701-702` — "the marker appears only once the tee has consumed the whole stream and sits blocked in read"; `resolution.md:248-249` — "the marker proves the tee consumed the stream and sits blocked in read". A 1 MiB `write()` to a fifo unblocks once the reader has consumed ≥ 1 MiB − pipe capacity (~64 KiB); at marker time up to 64 KiB can remain in flight, and the tee's `read(1 << 20)` loop (`fs-baseline.sh:150`) consumes it microseconds later. The load-bearing proof (interpreter initialized, KI handler installed, read loop live) is unaffected — that is why this is INFO, not a correctness flag — but it is precisely the "false comment claim" genre this chain caught twice ("union", "entirely").

**Q5 — INFO — dead pre-declaration.**
Evidence: `tests/unit/test-install-args.sh:957` — `_p3f=""` immediately before `for _p3f in …` (`:958`). The suite sets only `set -e` (`:30`), no `set -u`; the loop always assigns before any read; unmatched globs expand to literal patterns (filtered by `[ -f … ] || continue`), never an empty list. Nothing reads `_p3f` before the loop. Harmless.

## Verified clean (claims checked and held)

- **Measured union**: `_py3_imports` (install.sh:571) exactly equals the shipped surface — fnmatch/json/re/sys (jsonc-parser.py:19-22), importlib.util/json/os/stat/sys/tempfile (tui-register.py:26-31), os/sys (fs-baseline.sh:124,149), json/sys (update.sh:1154, status.sh:540, ddev-terminal.sh:73), sys/threading/time (status.sh:146,216), json/sys/pathlib (bin/opk:301). 11 modules, exact match.
- **"Corrected in place"**: both a-W1 and a-S1 sections carry explicit `(Correction, #244 b …)` parentheticals — the claim is true.
- **Gates**: `/tmp/opencode/maketest-pr244c.log` readable — ends rc 0, "Passed: 81" (line 257) matches the 80+1 new §11e pin arithmetic, line-length ratchet OK, reviews lint OK. E2E logs readable: "Passed: 309" / "Passed: 47" (the two `FAIL` strings in the e2e log are fixture content and a PASS asserting them).
- **Commit-vs-claim**: 25f96f1's trailer "all implemented, none not done" matches all 8 b rows (none marked not-done); every message clause maps to a diff hunk. ff2876c's four enumerated claims each map to its diff (8 SHA fills, e2e bullet, sabotage record, #248–#251 refs). Timeline consistent: 25f96f1 20:27:47 → e2e logs 20:30/20:31 → ff2876c 20:32:24 ("runs on the committed tree, bookkeeping after" holds).
- **§11e guard shape** matches §11c verbatim pattern (test-fs-baseline.sh:640 vs :758); poll replaces `sleep 1` ✓; 40 × 0.25 s ≈ 10 s ✓; never-armed fails red ✓; noisy case asserts rc 1 + diagnostic + 'present but broken' ✓; all new pins sit before their suites' summary gates ✓; temp-file cleanup unconditional ✓; pass ids unique ✓.
- **Docs drift**: clean — `docs/getting-started.md:15-18` ("the installer probes for it, missing or broken") remains true; the third failure class falls under "broken"; no docs page quotes gate messages or import lists, so RM-0100 is not triggered.
- **Wait-rc rejection rationale**: reasoned sound (default SIGINT disposition survives execv → sh dies by the group signal, rc 130, indistinguishable); not executed, accepted on mechanism.

## Coverage

Covered: resolution fix-wave-2 sections + Follow-ups claim-by-claim against the tree and logs; both commit messages vs their diffs; every new/changed comment sentence in the four shipped/test hunks; docs grep (python3/pre-flight/probes across docs/); lib dir enumeration for the "anywhere" claim; hygiene pass over `_p3*`/`W23KI*` variables, mktemp lifecycles, section placement, id uniqueness, §11e restructure for accidental behavior change (none found — the skip is the intended b W2 disposition). Deferred: executing the wait-rc rationale or the sabotage (read-only brief; recorded as reasoned-not-executed); the class-sweep's "rides the guarded `:?` scratch pattern" sentence is loose (`rm -rf "$_py3w"` is unguarded, pre-existing) but has no realistic trigger (`_py3w` is always a mktemp -d result) — not flagged; non-finding suggestion: `_py3_imports` is not declared `local` in `_py3_health_probe` while the sibling `_distro_gate` uses `local` (install.sh:102) — no house rule in agent/conventions.md mandates `local`, so it stays a suggestion. Unverified: none beyond the two noted reasoned-not-executed items.

---

## Retracted/ghost findings

**W5, second clause — RETRACTED during main-session verification.**
The clause "marker also fires if the writer python died" (writer killed
by EPIPE still writes the marker → arm pin green in the broken-tee
scenario) does not survive execution. Empirical probe
(`/tmp/opencode/pr-00244-c/verify/`): a subshell under `set -e` (the
suite's own posture, `test-fs-baseline.sh:16`) whose writer python
exits non-zero **aborts before the marker line** —
`( set -e; python3 -c 'import sys; sys.exit(1)' 2>/dev/null; : >
marker.txt; sleep 5 )` → subshell rc 1, `MARKER-ABSENT`. So a dying
writer python writes NO marker and the arm pin goes RED ("tee never
armed") — the loud, correct behavior, the opposite of the reported
green-in-broken-tee outcome. The clause is retracted; W5's first
clause (write() unblocks with up to ~one pipe buffer unconsumed; the
comment's "consumed the whole stream" overstates) is verified and
stands, and Q4 duplicates exactly that clause. Recorded here — not
edited out of the verbatim axis report — per the retraction-visibility
rule.

## Verification (main session)

Every finding re-verified against tree `ff2876c` before entering this
snapshot (13 of 14 IDs confirmed as reported; 1 sub-clause retracted):

- **W2/Q1**: `ls files/opencode-permissions-kit-lib/` = bin,
  management, py, sh, templates, tui (6); pin globs four
  (test-install-args.sh:958-961); `tui/` ships tsx/json/theme files,
  `templates/` jsonc/sudoers — zero python import surface today
  (grep-verified), so the pin is green and honest TODAY; the
  resolution claim "a new consumer anywhere in the lib goes red"
  (resolution.md:274) is false as written. Severity split kept per
  axis (Q1 MED / W2 LOW), dispositioned once.
- **W4/Q2**: test-ui.sh carries 20 setsid occurrences (hard-require
  at :36-38, first use :44), test-uninstall.sh:474 references it;
  resolution.md:276 quoted verbatim — the record misstates its grep.
  Substantive conclusion (every tests/unit setsid use guarded) holds.
- **W1**: empirical replay of the shipped extraction pipeline over
  `python3 -c 'import znewmod; znewmod.run()'` → **0 modules
  extracted** (`/tmp/opencode/pr-00244-c/verify/semicolon.txt`).
  Confirmed as reported.
- **S1**: the real `sfx_scan` ERE (test-sandbox-policy.sh:287-288)
  replayed by the main session against both wordings of the exact
  fixture line → rc 1 both, non-matching — the recorded
  false-positive mechanism does not reproduce against the shipped
  scanner. CPython's real diagnostic wording is unhyphenated
  ("platform independent libraries"); the fixture and its pin grep
  the hyphenated form. Confirmed.
- **S2**: install.sh:549-552 and fs-baseline.sh:138-141 quote only
  loader route + PATH-resolved binary; grep over both shipped files
  finds no site-packages/.pth mention; review-b.md:36 names three
  routes. Confirmed.
- **S3**: sibling sites verified (status.sh:216/540,
  update.sh:1154-1162, ddev-terminal.sh:73, opk:301); the wave-2 L2
  record (resolution.md:270-283) lists drift-pin/setsid/rm greps
  only — no stderr-class sweep. Confirmed as a record/consistency
  gap (all siblings degrade loud-by-design).
- **S4/W3**: test promise text at test-install-args.sh:936-938;
  `grep -c '_py3_imports=' files/install.sh` = **1**; extraction
  (:946-951) unions all matches via sort -u while runtime
  (install.sh:576,581) executes the last assignment only; no count
  pin exists. Both confirmed.
- **Q3**: set -e at test-fs-baseline.sh:16; `sleep 0.25` at :727;
  precedent `sleep 0.05` at test-status.sh:2621 (fractional sleep
  pre-exists suite-wide — the class is not new, the unguarded
  placement inside a portability-guarded block is). Confirmed.
- **Q5**: `_p3f=""` at :957, first read is the loop assignment —
  dead. Confirmed.
- **Q's clean claims re-checked**: e2e log tails "Passed: 309"
  (logs/e2e-20261024-202817.log) and "Passed: 47"
  (logs/e2e-rootless-20261024-202817.log) — both re-read by the main
  session; `/tmp/opencode/maketest-pr244c.log` exists, ends "All
  shell tests passed." + "rules index parity: OK (118 index rows)".
- **Independent corroboration**: the S and W reviewers each replayed
  the drift-pin extraction over the shipped lib independently — both
  got the exact 11-module match, green today.

Cross-axis duplicates (W2=Q1, W4=Q2, Q4⊂W5) verified as the same
underlying sites — each dispositioned once.

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T18:37:01Z, all
  reviewers returned by 2026-10-24T18:52:39Z. Checkpoint files
  (sandbox clocks): s-security.md 27 lines (per-section appends),
  q-quality.md 7 lines, w-sweep.md 2 lines — the W reviewer wrote
  launch and return lines only, batching its per-section findings
  into the final report (all five sections present in the report;
  deviation from the after-every-section rule, disclosed here).
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); 3 concurrent
  seats (cap 5, staged single wave). Checkpoint side files
  /tmp/opencode/pr-00244-c/checkpoints/{s-security,w-sweep,
  q-quality}.md (absorbed into this provenance); reviewer probes
  under /tmp/opencode/pr-00244-c/{s,w,q}-probe/, main-session
  verification probes under /tmp/opencode/pr-00244-c/verify/.
- Main session: GLM-5.3 (zai-coding-plan), verification duty over
  the full fix diff; one reviewer sub-claim retracted (W5 second
  clause), none dropped, none newly marked `unverified` beyond the
  reviewers' own recorded notes (S1's intermediate-fixture-shape
  caveat is recorded inside the finding).
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round; all probes touched
  only session scratch outside the tree). No sabotage-artifact
  screening owed.
- Gates run by the main session on tree `ff2876c` (before fan-out):
  `make lint` green (ShellCheck); `sh tests/unit/test-fs-baseline.sh`
  81/81 green; `sh tests/unit/test-install-args.sh` green.
- E2E: owed and discharged by the b-round ITSELF on tree `25f96f1`
  (make e2e 309 passed, make e2e-rootless 47 passed, log tails
  re-verified this pass). Snapshot c's round changes no code — no
  new e2e debt.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary not on the
  agent PATH this session (recorded per RM-0078).
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
