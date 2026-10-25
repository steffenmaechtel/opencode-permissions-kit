<!-- review-meta
ID: pr-00244
Snapshot: d
Subject: issue-223 fix-wave 3 dispositions (wave review of the c-round fixes)
Scope: wave
Base: 0.0.56+62 @ d47fffe (VERSION 0.0.56)
Diff: d47fffe..28c6664
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session D of the maintainer's snapshot-letter counting (fix commits 58c2019/28c6664 authored by session C, closed before this pass)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review d — wave review of the fix wave (pr-00244)

Round d over the c-round fix diff `d47fffe..28c6664` (two commits:
`58c2019` the dispositions — interpreter-stderr passthrough at the six
sibling sites (status probe/advisory/leak-scan, update resolve,
ddev `_opk_json_get`, fs-baseline probe rerun), CPython-real noisy
wording via scanner-safe variable indirection, the drift-pin
restructure (`_p3collect` via find over the whole lib root,
`_p3split` with `tr ',;'`, fixture self-test, assignment-count pin),
the .pth residual in all three shipped comments, integer sleep poll,
dead `_p3f`/`_p3d` removal; `28c6664` bookkeeping — c-row SHA fills,
wave-3 e2e discharge, sabotage record, session-naming clarification).
The wave answers review-c's 14 IDs (11 unique); all implemented,
none deliberately not done.

Rotation state (per the commission): the b-round and c-round sessions
are both closed; this pass ran with fresh context over fixes authored
by the closed c-session — no rotation deviation, RM-0110 recovery not
applicable. Review-c left no open findings.

Tree `28c6664`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

9 reported IDs, 9 unique findings (no cross-axis duplicate pairs this
round). All 9 verified as reported; none retracted, none dropped.

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | INFO | Broken-interpreter diagnostic repeats per `_opk_json_get` call (up to ~5× per ddev-terminal run) — designed passthrough, stdout contract unaffected | wave-introduced (designed) |
| S2 | INFO | fs-baseline probe rerun emits interpreter stderr unguarded on non-tty/cron paths (unlike the tty-gated status.sh probe) — consistent with the pre-existing unguarded warn on the same branch | wave-introduced (designed) |
| W1 | LOW | Wave-3 S3 class-sweep enumeration is incomplete: `tui-plugin.sh:68` swallows interpreter stderr and is absent from the record's re-classified site list | site pre-existing; enumeration gap wave-introduced |
| W2 | LOW | The W3 assignment-count pin is bypassed by a semicolon-joined same-line second `_py3_imports=` assignment (probe-verified: pin green, runtime last-wins reduced list) | wave-introduced (bypass exists since the pin's birth) |
| W3 | INFO | Record cites stale pre-wave line number for the residual fractional sleep: says `test-status.sh:2621`, actual position in the reviewed tree is 2690 | wave-introduced (record line) |
| W4 | INFO | Record's residual-`2>/dev/null` bullet mis-describes its own grep's hits: the gate-probe discards it lists don't match `2>/dev/null`, and the one real python3-line hit (oao:444) is classified only in an adjacent bullet | wave-introduced (record line) |
| Q1 | LOW | S3 passthrough at update.sh resolve and ddev `_opk_json_get` has no absent-python3 guard — shell "not found" noise now surfaces on paths the ledger says carry "only interpreter-level stderr" | wave-introduced |
| Q2 | INFO | update-flags line-shape needle `' 2>/dev/null || true)` is file-wide, not site-scoped — a future unrelated redirect of that shape reds the pin with a misleading "resolve:" message | wave-introduced |
| Q3 | INFO | S3 changes user-visible stderr behavior on four shipped paths; no docs page updated and the new diagnostic is undocumented — but no existing docs sentence is made false | wave-introduced |

Provenance split: 7 wave-introduced (two of them marked designed),
1 split (W1 — pre-existing site, wave-introduced record gap),
1 pin-birth (W2). No HIGH, no MED: the stop rule reads MED/HIGH for
severity, and any dispositioning round that touches review-relevant
code owes one more wave review regardless of severity — the loop state
is the next round's call, not this snapshot's.

---

## Axis S (security), verbatim

# Security review — wave diff `d47fffe..28c6664` (pr-00244, fix wave 3)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | INFO | Broken-interpreter diagnostic repeats per `_opk_json_get` call (up to ~5× per `ddev-terminal` invocation) — designed passthrough, stdout contract unaffected | wave-introduced (designed) |
| S2 | INFO | fs-baseline probe rerun emits interpreter stderr unguarded on non-tty/cron paths (unlike the tty-gated status.sh probe) — consistent with the pre-existing unguarded warn on the same branch | wave-introduced (designed) |

No HIGH/MED/LOW findings. Every behavioral claim in the wave checked out under execution, not just reading.

## Details

**S1 — INFO — `_opk_json_get` diagnostic repetition.** `files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:83` now lets interpreter stderr pass; the function is called up to ~5 times per `ddev-terminal` run (`:91`, `:92-96`, `:115`, `:119`, `:137`, `:141-142`, `:149`, `:165`). Trigger: a present-but-broken python3 during a `ddev` terminal/launch flow → the shim's diagnostic prints once per call. All callers capture stdout only (`$( … )`), so no URL or parsed value can be corrupted; expected misses stay silent (`except: pass`, ddev-terminal.sh:83-84). Only fires on an already-broken interpreter — cosmetic noise, recorded so the snapshot has the repetition noted.

**S2 — INFO — rerun not tty-gated.** `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:135-136` reruns `python3 -I -c 'import os, sys' >/dev/null` with stderr passing whenever the probe failed — no `[ -t 2 ]` guard (fs-baseline.sh has none; grep confirms), unlike status.sh:214 which gates on `[ -t 2 ]`. In cron/non-tty runs a broken interpreter now mails its diagnostic alongside the warn. The warn on the next line (fs-baseline.sh:138) was already unconditional pre-wave, so the rerun is consistent with the branch's existing output contract, and S3 explicitly wants the cause named. Deliberate; noted because the asymmetry with status.sh is real.

## Verified clean (evidence per axis surface)

1. **Six passthrough sites — no capture corruption, no rc-contract change.** stderr never enters a captured stream: status.sh:216 probe is stdout-`>/dev/null` under `[ -t 2 ]` (stderr is a tty by the guard's own test); status.sh:549 advisory `ADV_IDS=$( … | python3 … )` captures stdout only, expected-failure path (`json.load` exception → `sys.exit(1)`) emits nothing; status.sh:1337 `scan_patterns=$( … )` — the parser prints all errors to stderr (py/jsonc-parser.py:130,133,146,230) and patterns to stdout (:166), rc semantics unchanged; update.sh:1164 `$_rlov_ver` gets only python stdout, and python prints solely on success (`print(dist["latest"])`) — the diagnostic can never enter the variable, `|| true` and the `case 2.*)` return-1 contract kept, caller update.sh:1272 captures stdout only; ddev-terminal.sh:83 stdout contract intact. `bin/opk:161-162` exec's status.sh with no stderr aggregation — no upstream consumer parses these scripts' stderr.
2. **fs-baseline rerun** — read-only (imports `os, sys` only, stdout discarded), absence-guarded (`command -v` first), verdict-neutral (`_fsb_py_ok` untouched, rc discarded by `|| true`), `-I` carried, fires once per run inside the `_fsb_py_checked` cache; same root trust surface as the first probe. Probe-count pin honestly updated 1→2 with the cache rationale (8 without).
3. **Fixture shims** — every shim is a per-command PATH prefix (`PATH="$X:$PATH" cmd`) or a subshell-internal replacement (`_py3case` sets `PATH="$_p3p"` inside `( )`, test-install-args.sh:879-889); no `export PATH` of a shim dir (the suite's `export PATH` sites — test-status.sh:91/302/323/368, test-update-flags.sh:297 — are pre-existing `run_case` subshell patterns); 11f removes its shim (`rm -rf "$W23NZ"`); no cross-assertion or host leak.
4. **New-test untrusted input** — `eval "$SCAN_HELPERS"` content is sed-extracted shipped status.sh function bodies (test-status.sh:83) and is exported before the new block (:2416); `script -qec` and heredoc expansions are suite scratch paths (`$WORK`, `$T210`), quoted at point of use in the generated script; `python3 -c "$C244ADVPGM"` executes repo content with fail-loud empty extraction; all `sh -c ". '$FUNC' && …"` compositions single-quote the path variable; `_p3collect`/`_p3split` are read-only over the lib root.
5. **Scanner claim (c S1) — empirically replayed with the real check-3 ERE** (test-sandbox-policy.sh:288-290) in `/tmp/opencode/pr-00244-d/s-probe/replay.sh`: definition line `X='platform independent libraries'` → **clean**; post-fix consuming greps (`grep -qF "$VAR" …`) → **clean**; the pre-fix **hyphenated** inline grep (`'platform-independent libraries' … "$_py3w/err"`) → **clean** (it never matched — `rm` inside "platform" is glued to `-independent`, and every chain alternative demands a leading space); the **unhyphenated** inline grep + `"$VAR/"` operand → **MATCH**. The mechanism is real exactly for the shapes the wave now ships: the indirection is load-bearing because the wording simultaneously moved to CPython's real unhyphenated message. The real `sfx_scan` over the current `tests/unit` + `tests/e2e` trees returns **0 violations**.

**Behavior-change sweep:** install.sh hunk is comment-only; the SIGINT-block changes are wording plus the integer-sleep poll (same 10 s bound: 40×0.25 s → 10×1 s, Q3-motivated, test-only); every stderr change matches its stated S3 intent; no accidental behavior deltas found.

## Coverage

Covered: all six passthrough sites with caller walks to the `opk` wrapper; fs-baseline rerun (read-only/guard/verdict/`-I`/frequency); shim scoping and cleanup across all five suites; the eval/`script -qec`/heredoc/`sh -c`/`python3 -c` expansion surface; empirical check-3 replay (definition vs consuming-grep vs fixture shapes, plus pre-fix verbatim lines from `d47fffe` and a full live `sfx_scan` run). Deferred: e2e-suite internals (out of diff scope; unit pins only reviewed where the diff touches them); hostile-site-packages `.pth` execution at `-I` startup — documented residual (c S2), unchanged by this wave, not re-analyzed. Nothing marked `unverified` — every suspicion raised during review was resolved by one follow-up read or probe.

---

## Axis W (mechanical sweep), verbatim

# W-sweep report — mechanical sweep axis, diff `d47fffe..28c6664`

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Wave-3 S3 class-sweep enumeration is incomplete: `tui-plugin.sh:68` swallows interpreter stderr and is absent from the record's re-classified site list | site pre-existing; enumeration gap wave-introduced |
| W2 | LOW | The W3 assignment-count pin is bypassed by a semicolon-joined same-line second `_py3_imports=` assignment (probe-verified: pin green, runtime last-wins reduced list) | wave-introduced (bypass exists since the pin's birth) |
| W3 | INFO | Record cites stale pre-wave line number for the residual fractional sleep: says `test-status.sh:2621`, actual position in the reviewed tree is 2690 | wave-introduced (record line) |
| W4 | INFO | Record's residual-`2>/dev/null` bullet mis-describes its own grep's hits: the gate-probe discards it lists don't match `2>/dev/null`, and the one real python3-line hit (oao:444) is classified only in an adjacent bullet | wave-introduced (record line) |

## Details

### W1 — LOW: S3 sweep enumeration misses `tui-plugin.sh:68`

Evidence — `files/opencode-permissions-kit-lib/sh/tui-plugin.sh:68-69`:
```sh
_tp_sudo python3 "$_tp_libdir/py/tui-register.py" "$_tp_user_dir/cli.json" unregister \
    "$_tp_libdir/tui/kit-mode-2x.tsx" --drop "$_tp_libdir/tui/kit-mode.tsx" >/dev/null 2>&1 || true
```
The wave-3 record (`internal/reviews/0/0/2/4/pr-00244/resolution.md:465-470`) claims "`grep -rn "python3" files/` re-classified against stderr redirects" and lists 10 sites (6 fixed + opk:300 + oao:444 + fsb-tee + update-1.x-sed). My independent enumeration (grep: `grep -rn python3 files/ -I --exclude-dir=__pycache__`, including extensionless `bin/` scripts) found **13 execution sites**; the wave-3 list omits three, of which `tui-plugin.sh:68` is the only live swallow. The earlier b-wave sweep line ("uninstall/tui (best-effort, labeled)", resolution.md:154) is the only coverage, and it predates the wave-3 re-classification claim. `uninstall.sh:316` and `install.sh:574-584` are also unlisted but transparent (no redirect / b-S2 discard+rerun shape).

Why it matters: the site does exactly what the wave's S3 rationale targets — a present-but-broken python3 is swallowed identically to an expected miss, with no rerun/drop shape, while the record presents the class as fully enumerated. Impact is small (best-effort cleanup of inert pre-0.0.35 entries; the plugin-dir `rm -rf` above still runs), hence LOW.

Verified-true record claims (no finding): opk:299-300 transparent (heredoc runs with no stderr redirect; loud `ui_error` else) ✓; status:145 and fs-baseline:161 tees silent by the pinned except-clause contract ✓; update.sh 1.x branch sed-based ✓; oao:444 residual is recorded as deliberate (resolution.md:416, 467) — not missed, not misclassified.

### W2 — LOW: assignment-count pin bypassed by same-line semicolon join

Evidence — `tests/unit/test-install-args.sh:945-948`:
```sh
_p3asn="$(grep -c "^[[:space:]]*_py3_imports=" "$INSTALL")"
if [ "$_p3asn" -eq 1 ]; then
```
Probe (in `/tmp/opencode/pr-00244-d/w-probe/one.sh`), a single line:
```
_py3_imports='import aa, bb'; _py3_imports='import aa'
```
- `grep -c "^[[:space:]]*_py3_imports="` → **1** (counts lines; the pin passes)
- the pin's extraction sed (`tests/unit/test-install-args.sh:937`) → `import aa, bb` (the `.*` eats the second statement)
- runtime (`. ./one.sh; echo "$_py3_imports"`) → `import aa` (last statement wins)

So the exact divergence the pin exists to close — "a second … assignment would keep this pin green while the probe silently stops exercising the first list's modules" (comment at test-install-args.sh:941-944) — is realizable on one line: pin green, extraction reads the full list, runtime executes the reduced list, modules in the first list silently unexercised. Separate-line second assignments are caught (count 2 → red; probe-verified). A second statement joined by `;` sails through. Trigger realism is the honest caveat: a contributor must write two assignments semicolon-joined on one line — the same low-likelihood editing accident the pin's own threat model already assumes. The heredoc/string false-positive direction is loud (count inflates → red), not a bypass; a `+=` append line bypasses the count but only widens the runtime gate, so no coverage gap.

### W3 — INFO: stale line number in the fractional-sleep record

Evidence — `internal/reviews/0/0/2/4/pr-00244/resolution.md:471-472`: "test-status.sh:2621 `sleep 0.05` is pre-existing". Verified: `grep -rnE "sleep[[:space:]]+['\"]?0" tests/unit/` → exactly one hit, `tests/unit/test-status.sh:2690` (in the §11e sender-fixture poll). The 2621 position is the pre-wave tree (`git show d47fffe` → 2621; `git show 58c2019` and the reviewed tree → 2690). The substantive claim (pre-existing, sole residual, deliberately not done) verifies true; only the citation number is stale — the record commit (28c6664) is the tree where the number is already wrong. Unambiguous (single hit in the file), hence INFO.

### W4 — INFO: residual-redirect bullet doesn't match its own grep's output

Evidence — `internal/reviews/0/0/2/4/pr-00244/resolution.md:473-475`: "`grep -rn "2>/dev/null" files/` on python3 lines — residual hits are the fixed-gate probes themselves (presence/probe rc still discarded by design …) and curl noise guards". My rerun filtered to python3/curl lines found: `update.sh:230`, `update.sh:1157`, `setup-container-backend:283` (curl guards ✓) and **one** python3-line literal hit, `bin/opencode-as-opencode:444`. The gate-probe discards the bullet names are `>/dev/null 2>&1` shapes (`install.sh:578`, `fs-baseline.sh:127`) which do not match the literal `2>/dev/null` pattern at all. So the bullet's enumeration is wrong in both directions: it claims hits its grep cannot produce and omits the one python3-line hit its grep does produce (oao:444 is classified as deliberate in the adjacent S3 bullet, resolution.md:467, so the disposition exists — the residual bullet is just inaccurate as stated). INFO: classification exists elsewhere; no behavior gap beyond the recorded one.

## Coverage

**Covered (all 7 sections):** full python3-site enumeration over all of `files/` incl. extensionless `bin/` (13 sites classified, grep pattern recorded above); fractional-sleep sweep over `files/`, `tests/unit/`, `tests/ux/`, `tests/e2e/*.sh` + record verification at 3 commits; residual `2>/dev/null` sweep over `files/` filtered to python3/curl, all 4 hits classified; drift-pin replay of the exact `_p3collect`/`_p3split` bodies (extracted from the test file, unmodified) over the shipped lib — extracted set equals the 11-module gate set in both `comm` directions — plus 8 empirical edge-shape probes in `w-probe/fx/` (CRLF survives via the `[[:space:]]` trim; spaced filename survives `IFS= read -r`; heredoc line-start imports collected; late-single-quote one-liner keeps its import; double-quoted `-c`, `as` aliases, and dynamic `importlib`/`__import__` confirmed as the documented residuals — the test comment's claims are all empirically true, no shipped shape dropped); assignment-count pin probed for comment/heredoc inflation (loud), `+=` (no coverage gap), and the W2 semicolon bypass; scanner-indirection grep (5 definition lines + 5 variable-consuming greps, zero inline-quoted consumers, hyphenated variant gone from tests/+files/); pin placement and FAIL arms in all 5 suites; happy-path noise check on the dropped parser redirect (`jsonc-parser.py` writes stderr only on error paths, lines 130/133/146/230/292); deliberate behavior changes (probe-count 1→2, 40×0.25s→10×1s same 10 s bound, c-W5 pipe-buffer wording now accurate) confirmed intentional and commented.

**Deferred / out of scope:** full read of `resolution.md` (only the wave-3-relevant ranges read); e2e suites not run (reader role; discharge recorded separately in the bookkeeping commit); the `ddev-images-*.tar` binary grep hits (cached image, not code); test-side `python3 … 2>/dev/null` in `test-browser-bridge.sh:55,84,104`, `test-git-config.sh:50`, `test-fs-baseline.sh:711` (test infrastructure discarding its own fixture's stderr — outside the S3 shipped-code class, pre-existing, untouched by this diff); untracked `files/…/py/__pycache__/*.pyc` residue (not in git, cannot ship via the ref-streamed install — housekeeping note only); newline-in-filename extraction shapes (pathological, no realistic trigger).

---

## Axis Q (quality), verbatim

# Quality review — pr-00244 fix wave 3 (`d47fffe..28c6664`)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | LOW | S3 passthrough at update.sh resolve and ddev `_opk_json_get` has no absent-python3 guard — shell "not found" noise now surfaces on paths the ledger says carry "only interpreter-level stderr" | wave-introduced |
| Q2 | INFO | update-flags line-shape needle `' 2>/dev/null || true)` is file-wide, not site-scoped — a future unrelated redirect of that shape reds the pin with a misleading "resolve:" message | wave-introduced |
| Q3 | INFO | S3 changes user-visible stderr behavior on four shipped paths; no docs page updated and the new diagnostic is undocumented — but no existing docs sentence is made false | wave-introduced |

No HIGH/MED findings. Both commit messages reconcile against their diffs; the resolution's wave-3 claims reconcile against the code.

## Details

### Q1 — LOW — absent-interpreter noise asymmetry; ledger sentence imprecise

The wave treats interpreter *absence* asymmetrically across the six S3 sites. fs-baseline guards it and says so:

- `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:133-134`: `command -v python3 >/dev/null 2>&1 && python3 -I -c 'import os, sys' >/dev/null || true` with the comment "An absent one is guarded off — no not-found noise for a legitimate absence" (comment verified true).

But two sibling sites dropped `2>/dev/null` with no `command -v` guard:

- `files/opencode-permissions-kit-lib/management/update.sh:1160-1164` — `curl ... | python3 -c '...' || true)`; if python3 is absent, the shell now prints "python3: command not found" above the resolve warn (pre-wave: silent).
- `files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:78-83` — `printf '%s' "$_opk_gj" | python3 -c '... pass' "$@"`; absent python3 is noisy at *every* call, and `_opk_scheme_url` (ddev-terminal.sh:93-99) calls `_opk_json_get` up to 4×, so up to 4 not-found lines per describe lookup.

Trigger: python3 removed from PATH mid-lifecycle (the kit verifies python3 at install time only) — realistic for cron/systemd contexts with stripped PATH. Why it matters: `internal/reviews/0/0/2/4/pr-00244/resolution.md:417-419` claims "Every expected-failure path stays SILENT … the passthrough only carries interpreter-level stderr" — the shell's not-found message is neither, and it passes at exactly the two unguarded sites. The direction is fail-loud and the comment scopes python3 as "a kit prerequisite", so LOW; but the ledger sentence overstates the silence contract, and the absence facet of the behavior change is dispositioned nowhere (fs-baseline dispositions it, the siblings don't).

### Q2 — INFO — over-broad line-shape needle

`tests/unit/test-update-flags.sh:420`: `grep -qF "' 2>/dev/null || true)" "$UPDATE"` matches any line in update.sh ending in a close-quote + `2>/dev/null || true)`, not just the resolve pipe. Verified non-vacuous: the forbidden shape is currently absent (0 hits) and the live shape `' || true)` exists at update.sh:1164. Risk is only a future false red with a misleading message. The three test-status needles are site-exact and discriminate correctly (`status.sh` forbidden shapes: 0 hits; live shapes: present).

### Q3 — INFO — S3 tty diagnostic undocumented (RM-0100 judgment, no lie)

58c2019 changes user-facing behavior (broken-interpreter diagnostics now visible on the tty path of status, and on update/ddev/fs-baseline failure paths) without touching `docs/`. Sweep result: no sentence is made false. Near misses verified true as written: `docs/reference/cli.md:356-359` ("never appears in piped output, log files, cron mail or `--short`" — probe is tty-gated, still true; "without `python3`" is absence-scoped, and absence is still silent at status) and `docs/concepts/sharing-group.md:73-75` ("one warning says so" — still exactly one kit warning; the diagnostic is interpreter output, not a second warning). Whether the new terminal diagnostic deserves a sentence on the sharing-group/cli pages is a maintainer call; nothing in docs now lies.

## Verified-clean claim audit (no findings)

- **58c2019 message vs diff**: every ID maps to a hunk — S1 (unhyphenated CPython literal via variable in 5 suites), S2 (all three comments name the .pth/site-packages route: install.sh:553-555, fs-baseline.sh:109-112, fs-baseline.sh:151-154), S3 (6 sites + rerun), S4 (shapes + residual, test-install-args.sh:938-945), W1 (`tr ',;'`, whitespace-requiring second strip — the importlib.util bug is genuinely unreachable, fixture self-test), W3 (assignment-count pin), W4/Q2 + W5/Q4 (both ledger corrections in place at resolution.md:304 and :267-272; correction content verified true — test-ui.sh has 20 setsid refs and a hard require at :36), Q3 (10×1 s = same 10 s bound), Q5 (`_p3f`/`_p3d` gone, word-boundary greps 0). No hunk omitted from the trailer.
- **28c6664 message vs diff**: fills are the 11 `<SHA>` placeholder rows (deletions confirm) + 1 e2e-bullet mention = 12 occurrences; the message claims no row count (the brief's "14" is the 14-ID count with 3 dup pairs merged into rows — internally consistent, not a commit error). Sabotage record names all 4 constructs with their observed reds and the 3 accidental pre-commit reds. Session-naming paragraph matches review-b.md:9 and review-c.md:9 verbatim ("session C of the rotation" vs snapshot-letter counting).
- **S3 pin count**: row's "pins in 4 suites" is accurate — new S3 pins in test-fs-baseline (§11f), test-status (5b), test-ddev-as-opencode (2b), test-update-flags (2c-2); test-install-args only swaps the needle on the pre-existing b-S2 pin. The commit message's "5 suites" counts suites touched by wave pins overall — different scope, both true.
- **Probe-count arithmetic**: 4 passes confirmed (fs-baseline.sh:371-374); uncached 4×(probe+rerun)=8, cached 1+1=2 — the pin's comment is arithmetically correct.
- **Reference-identical claim**: `t210-ref.txt` is an independent find-derived oracle (test-status.sh:2358-2360), reused by 6 pre-existing pins — stronger than a healthy-run reference; the c-wave pty pin cmp's against it.
- **Class sweep spot-checks**: opk:300 heredoc python has no stderr redirect; opencode-as-opencode:444 keeps `2>/dev/null` exactly as the "deliberately not changed" record states.
- **Hygiene**: fixture temp cleanup complete (`_p3fx` rm -rf, five mktemp files, W23NZ, `$WORK` trap at test-status.sh:27); no pin-id collisions (§11f, 5b unique).

## Coverage

Covered: both commit messages against full diffs; all 15 c-finding IDs hunk-by-hunk; resolution wave-3 section claim-by-claim incl. pin-count and probe arithmetic; all four line-shape needles by live grep; all six new/edited comment blocks against code; docs sweep over `docs/` for silence claims; dead-code/naming/cleanup sweep; class-sweep spot-checks (opk:300, opencode-as-opencode:444). Deferred/unverified: the e2e log files (`../logs/e2e*-20261024-212945.log`) and the `make test` log live outside `repo/`, which my brief restricts me to — the 309+47 counts and gate numbers are **unverified**; only the commit-timestamp timeline (21:26:46 < 21:29:45 < 21:34:14) was checked and is consistent with "runs on the committed tree". Runtime pin behavior was not executed (static review); the sabotage-record reds were taken as recorded, with each claimed red mechanism statically confirmed plausible (pin asserts exactly what the sabotage deletes).

---

## Retracted/ghost findings

None this round. All 9 reported IDs survived main-session verification
unchanged (no retraction, no drop, nothing newly marked `unverified`;
the Q reviewer's own two unverified items — the e2e/make-test counts —
were re-verified by the main session, see below).

## Verification (main session)

Every finding re-verified against tree `28c6664` before entering this
snapshot (9 of 9 IDs confirmed as reported):

- **S1**: `_opk_json_get` call sites enumerated independently —
  ddev-terminal.sh:91, 92, 93, 95, 96 (inside `_opk_scheme_url`: the
  case head + one arm + two fallbacks), 115, 141, 165; every caller
  wraps the call in `$( )` (stdout captured only, stderr passes to the
  terminal). Repetition on a broken interpreter is real; the stdout
  contract is untouched. Confirmed INFO.
- **S2**: the rerun block (fs-baseline.sh:131-138) carries no tty
  guard; `grep -n '\[ -t 2 \]'` over fs-baseline.sh returns nothing
  while status.sh gates its probe at :214; `git show d47fffe` confirms
  the degradation warn was already unconditional pre-wave. Confirmed
  INFO (consistent with the branch's existing contract).
- **W1**: tui-plugin.sh:68-69 quoted verbatim from the tree; the
  wave-3 record (resolution.md:465-470) names 6 fixed sites + opk:300
  + oao:444 + fsb-tee + update-1.x-sed — tui-plugin.sh:68 is absent.
  My own enumeration seconded the reviewer's: uninstall.sh:316 runs
  `sudo python3 … tui-register.py` with NO redirect (already
  transparent, also unlisted), install.sh:574+ is the wave-2 gate
  (b-S2 shape), tui-plugin.sh:68 is the one live `>/dev/null 2>&1`
  swallow outside the record's list. The a-wave line "uninstall/tui
  (best-effort, labeled)" (resolution.md:154) predates the wave-3
  re-classification standard. Confirmed LOW.
- **W2**: empirical replay in /tmp/opencode/pr-00244-d/verify/ —
  joined line `_py3_imports='import aa, bb'; _py3_imports='import aa'`:
  `grep -c` → **1**, extraction sed → `import aa, bb`, runtime →
  `import aa`. The pin/runtime divergence reproduces exactly as
  reported. Confirmed LOW.
- **W3**: `grep -n 'sleep 0\.' tests/unit/test-status.sh` → :2690;
  `git show d47fffe:tests/unit/test-status.sh | grep -n` → :2621.
  Sole hit in tests/unit either way. Confirmed INFO.
- **W4**: my rerun of the literal grep over files/ filtered to
  python3/curl lines: update.sh:230 + :1157 (curl), bin-side
  setup-container-backend:283 (curl), opencode-as-opencode:444 (the
  one python3-line hit). The gate probes the bullet names
  (install.sh:574, fs-baseline.sh:127) are `>/dev/null 2>&1` shapes
  that cannot match a literal `2>/dev/null` grep. Confirmed INFO.
- **Q1**: shell behavior reproduced empirically —
  `sh -c 'no-such-cmd 2>/dev/null'` → silent rc 127; the same call
  without the redirect → `sh: 1: no-such-cmd-x: not found` on stderr.
  update.sh:1158 (pipe into python3, no guard) and ddev-terminal.sh:74
  (no guard) confirmed; guards confirmed at fs-baseline.sh:133,
  status.sh:215, opk:299 (`command -v python3 && …`). The ledger
  sentence at resolution.md:417-419 quoted verbatim. Trigger realism
  corroborated by the kit's own docs: cli.md ("the scans run
  identically without `python3`") and sharing-group.md ("A missing or
  broken `python3` never blocks the baseline") — absence is a
  supported operating state. Confirmed LOW.
- **Q2**: needle at test-update-flags.sh:166 (file-wide grep over
  $UPDATE); 0 current hits (non-vacuous); live shape `' || true)`
  present 2×. Confirmed INFO.
- **Q3**: docs quotes re-read at docs/reference/cli.md:354-360 and
  docs/concepts/sharing-group.md:70-77 — both true as written for the
  post-wave behavior (probe tty-gated; absence still silent at
  status; exactly one kit warning). No docs sentence made false.
  Confirmed INFO (RM-0100 judgment call named for the maintainer).
- **Q's unverified items discharged**: the e2e log tails were re-read
  by the main session — "Passed: 309" (logs/e2e-20261024-212945.log)
  and "Passed: 47" (logs/e2e-rootless-20261024-212945.log);
  /tmp/opencode/maketest-pr244d.log exists, ends "All shell tests
  passed." + "rules index parity: OK (118 index rows)". The counts the
  Q reviewer could not reach are green.
- **Independent corroboration (c S1 two-shapes narrative)**: the main
  session replayed the real check-3 ERE (test-sandbox-policy.sh:288)
  against seven shape lines in /tmp/opencode/pr-00244-d/verify/ —
  definition line, variable-consuming grep, and BOTH fixture-printf
  wordings: clean; the unhyphenated inline-consuming grep + quoted
  `$VAR/` operand: MATCH; the hyphenated consuming grep: clean. The
  wave-3 c-S1 record's mechanism story reproduces in full, and the
  shipped indirection is load-bearing for exactly the shape it
  indirections.

Cross-axis duplicates: none — all 9 IDs are distinct underlying
sites/claims (S1 repetition vs Q1 absence-noise; W1 missed site vs
Q1 unguarded sites — different defects).

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T19:38:39Z, all
  reviewers returned by 2026-10-24T19:50:17Z. Checkpoint files
  (sandbox clocks): s-security.md 7 lines, w-sweep.md 29 lines,
  q-quality.md 8 lines — all three reviewers appended per section
  (launch + per-section + return lines); no checkpoint deviation to
  disclose this round.
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); 3 concurrent
  seats (cap 5, staged single wave). Checkpoint side files
  /tmp/opencode/pr-00244-d/checkpoints/{s-security,w-sweep,
  q-quality}.md (absorbed into this provenance); reviewer probes
  under /tmp/opencode/pr-00244-d/{s,w,q}-probe/, main-session
  verification probes under /tmp/opencode/pr-00244-d/verify/.
- Main session: GLM-5.3 (zai-coding-plan), verification duty over
  the full fix diff; 9 of 9 findings confirmed, none retracted,
  none dropped, none newly marked `unverified` (the Q reviewer's
  two out-of-tree unverified counts were discharged by the main
  session, above).
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round; all probes touched
  only session scratch outside the tree). No sabotage-artifact
  screening owed.
- Gates run by the main session on tree `28c6664` (before fan-out):
  `make lint` green (ShellCheck); `sh tests/unit/test-fs-baseline.sh`
  82/82 green; `sh tests/unit/test-install-args.sh` green;
  `sh tests/unit/test-status.sh` green; `sh
  tests/unit/test-ddev-as-opencode.sh` green; `sh
  tests/unit/test-update-flags.sh` 133 passed, green.
- E2E: owed and discharged by the c-round ITSELF on tree `58c2019`
  (make e2e 309 passed, make e2e-rootless 47 passed, TS
  20261024-212945 — log tails re-read this pass). Snapshot d's round
  changes no code — no new e2e debt.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary at
  /usr/local/bin/opencode this session (recorded per RM-0078).
- Rotation: b- and c-round sessions closed before this pass; this
  fresh session (D in the maintainer's snapshot-letter counting)
  reviewed the closed c-session's fixes — no deviation, RM-0110
  recovery not applicable; review-c's CLEAN verdicts were not
  mandatorily re-verifiable, but the c-S1 scanner-shape clean claims
  were re-anchored empirically anyway (Verification section).
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
