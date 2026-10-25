<!-- review-meta
ID: pr-00263
Snapshot: f
Subject: micro-wave review of the pr-00263 e-round fixes (run() removal, harness label, ledger wording)
Scope: wave
Base: 0.0.57 @ 6f9826e (snapshot e; the reviewed range ends at 4959c4b)
Diff: 6f9826e..4959c4b (3 commits; uninstall.sh + resolution.md, 2 test suites, +51/-22)
Date: 2026-10-25
Reviewer: GLM-5.3 (house session, verification duty held in-session) + 2x GLM-5.3-Flash reviewer subagents (W mechanical sweep / Q quality)
Skills: opk-review-pass
-->

# Micro-wave review — pr-00263 snapshot f — the e-round fixes

> Resolution: [resolution.md](resolution.md)

Micro pass ("did the e fixes break or lie?") over the round that
dispositioned all 4 snapshot-e findings: two fix commits (tests
`1abc8d6` — e W2 production-shaped label; uninstall `163da3a` — e W3
run() removal + comment sweeps + def-count pin) plus the e-round
resolution bookkeeping (`4959c4b`). Two reviewer subagents ran two
axes (mechanical sweep, quality) on the provider's fast tier; the main
session re-verified every finding against the code and executed one
sabotage spot-check (pre-fan-out, window a) against the round's only
new pin.

Severity counts: **1 MED, 4 LOW, 2 INFO** (7 findings; W1 and Q1 are
one construct found independently by both axes, counted once) — no
HIGH. The e fixes' core behavior claims hold: the run() removal is
behavior-neutral (zero statement-position callers at the parent tree
AND at HEAD, first-hand), the e W2 label is production-shaped with a
verified-inert assignment, and the ledger rows/evidence block are
mostly accurate. The one MED: the round's new def-count pin greps
`'^run ()'` (space) while the removed def was `run() {` (no space) —
a byte-exact resurrection passes green, and the "fails loud" claim in
the pin comment, commit 163da3a, and resolution row e W3 is false for
that scenario (proven by sabotage, not by pattern argument). The
remaining findings are comment/ledger precision: two unswept sibling
comments and one stale header bullet in test-uninstall.sh, a
corrected-then-still-wrong evidence sentence (2 of 3 log lines, not
all three), a commit-message byte-count drift, and bookkeeping state.

## Findings index

| ID | Sev | Location | One-line summary | Verified |
|---|---|---|---|---|
| W1 (≡ Q1) | MED | test-uninstall.sh:1511-1516 vs the removed def (6f9826e uninstall.sh:164) | def-count pin `grep -c '^run ()'` (spaced) cannot match the historical `run() {` (no space): a byte-exact resurrection (git revert 163da3a, copy-paste from history, house-style redefinition) passes green; "a resurrected def without callers must fail loud" (pin comment, commit message, resolution row e W3) is false for every realistic resurrection shape | yes — sabotage (window a): def resurrected byte-exact → suite GREEN, pin false-PASSES; spaced `run () {` → pin red; Q measured `grep -c '^run()'` = 1 at 163da3a~1 (the pattern that discriminates) |
| W2 | LOW | test-uninstall.sh:816-817, 1099-1100 | class sweep incomplete: two sibling "run/run_q convention" comments (the `_un_loop_out` / `_un_cfg_out` dry-run drivers) left unreworded — present-tense about a convention whose `run` half no longer exists; 163da3a swept the four uninstall.sh sites but not these two test siblings | yes (both contexts read; repo-wide `run/run_q` grep: only these two outside frozen ledger prose) |
| W3 | LOW | test-uninstall.sh:3 | header bullet claims the suite tests "the run() wrapper echoes in dry-run mode instead of executing" — present-tense, and no backing test exists at HEAD (all other `run()` hits are prose or `_f27_run()`-style differently-named helpers); the referent was deleted by 163da3a | yes (suite grepped; bullet's last content-touch predates the range — the claim was already unsubstantiated, the removal makes it permanently dangling) |
| Q2 | LOW | resolution.md:188-191 vs install.sh:2001, 2482, 2503-2505 | the corrected e W1 evidence sentence still overclaims in the same breath: "all three log lines now read 'backup attempt: … — <verdict>'" is true for 2 of 3 — branch-b's log is the parenthetical `log "binary copied: … ($_ocb_bk)"` → `(Backup saved.)`, no "backup attempt:" literal at all | yes (all three log lines read at HEAD; severity screened MED→LOW — prose-only, same sentence/class as e W1 LOW; the repeat-in-the-correction aggravation is named in the detail) |
| Q3 | LOW | 163da3a commit message vs resolution.md:77 | message says the e W3 resolution row was "shortened to 114"; the committed row measures 110 bytes (at 163da3a and unchanged at HEAD) — both under the 120 bound, no gate was affected; immutable history, ledger-note class (d Q3 precedent) | yes (measured at both trees with awk length = bytes) |
| W4 | INFO | test-uninstall.sh:370-371 | driver comment says the project loop runs "with a logging run() stub" — the driver stubs `sudo()` (:532) and `log()` (:547) and evals the real `un_rc_q`; no run() stub exists at HEAD or at 6f9826e — pre-existing inaccuracy, now permanently dangling | yes (driver stub defs enumerated) |
| Q4 | INFO | resolution.md:75-77 (+ Follow-ups) | three `<SHA>` placeholders open at HEAD — e W1→4959c4b, e W2→1abc8d6, e W3→163da3a per the README fill rule; the e W1 row sits at 119 bytes and the +2 fill tips it to 121 (the issue #237 shape, live c3fcb7b scenario); the rewritten Follow-ups did not name the fill debt | yes (rows measured; README:181-189 read; the fills + shortening land in THIS snapshot's commit as the chain's next commit) |

Provenance: W1/Q1 fix-induced (163da3a's own new pin); W2/W3
fix-induced staleness completed by 163da3a's removal (W3's bullet
predates the range); Q2 delta-introduced (4959c4b, the e W1 fix
itself); Q3 wave-introduced ledger recount drift; W4 pre-existing;
Q4 wave-introduced bookkeeping state.

## Findings (reviewer output, verbatim)

### Axis W — mechanical sweep (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner |
|----|----------|-----------|
| W1 | MED | The new def-count pin `grep -c '^run ()'` cannot match the removed def's exact historical shape `run() {` (no space) — a byte-exact resurrection (e.g. `git revert 163da3a`) passes green |
| W2 | LOW | Class sweep incomplete: two sibling "run/run_q convention" comments in test-uninstall.sh (:817, :1100) left unreworded — present-tense about a convention whose `run` half no longer exists |
| W3 | LOW | test-uninstall.sh:3 header bullet claims the suite tests "the run() wrapper echoes in dry-run mode" — present-tense about the removed wrapper, and no backing test exists |
| W4 | INFO | test-uninstall.sh:371 says the loop driver runs "with a logging run() stub" — the driver has no run() stub (it stubs `sudo()` and evals the real `un_rc_q`); pre-existing, now permanently dangling |

## Detail

### W1 — MED — Pin pattern blind to the exact historical def shape (wave-introduced: 163da3a)

Evidence — the removed def's exact bytes (`git show 6f9826e:files/opencode-permissions-kit-lib/management/uninstall.sh`, former line 164, `cat -A`):

```
run() {$
```

The pin (tests/unit/test-uninstall.sh:1514):

```sh
[ "$(grep -c '^run ()' "$UNINSTALL")" = 0 ] \
```

BRE `^run ()` = literal `run ()` **with a space** between `run` and `(`. Variant enumeration, each piped through `grep -c '^run ()'`:

| Variant | grep -c | Pin counts it? |
|---|---|---|
| `run() {` — **the exact historical shape** | 0 | **NO — blind** |
| `run () {` (spaced) | 1 | yes |
| `  run() {` (indented; valid sh def) | 0 | no — blind |
| `function run {` | 0 | no — but not realistic: `function` is not a POSIX keyword, this does not define a function under the script's `sh` interpreter at all |

Why it matters: the pin's stated purpose ("a resurrected def without callers must fail loud" — commit message 163da3a; resolution row "def-count pin = 0") is unmet for the most likely resurrection: `git revert 163da3a` (or cherry-pick of the pre-removal code) restores `run() {` byte-exactly with zero callers — the callers died in the earlier d-round commits — and the pin stays green. This is the fail-loud-pin discrimination class (agent/learnings.md). MED, test-only: no shipped-code impact, and even a missed resurrection is dead code until someone calls it — but the pin exists solely to catch that resurrection and misses its primary form. Note the commit-message claim "a resurrected def without callers fails loud" is false for the byte-exact form.

### W2 — LOW — "run/run_q convention" siblings not swept (wave-introduced: 163da3a)

Evidence — tests/unit/test-uninstall.sh:816-817:

```
# Dry run: [DRY] echoes and the success lines despite failing ops —
# the run/run_q convention since #211 b W1 (dry reports the intended
```

and :1099-1100:

```
# Dry run: [DRY] echoes and the success lines despite the failing
# stub — the run/run_q convention (#211 b W1). The guard probes
```

Both are present-tense descriptions of the **current** dry-run arms (the `_un_loop_out` / `_un_cfg_out` drivers exercise today's extracted code, which goes through `un_rc_q`/inline arms — no `run` involved). Commit 163da3a reworded the four uninstall.sh sites (:549/:626/:831/:885, now "run_q convention" — verified, no fifth site in uninstall.sh) but not these two test siblings. Repo-wide `grep 'run/run_q'` finds only these two plus internal/reviews ledger rows (frozen history / accurate-historical disposition prose — not findings). Class sweep incomplete per the AGENTS.md memory aid; comment-only impact.

### W3 — LOW — Suite header names the removed wrapper as a current test subject (staleness completed by 163da3a; bullet's backing test already long gone — provenance: pre-existing sloppiness + fix-induced)

Evidence — tests/unit/test-uninstall.sh:3:

```
#   - the run() wrapper echoes in dry-run mode instead of executing
```

Present-tense header bullet. At HEAD the suite contains **no** test exercising a `run()` wrapper: the only other `wrapper` hits in the file are path mentions (:170, :1158) and a historical list (:1488); the dry-run arms (:1333, :1398, :1439) drive today's extracted sections, and the loop driver evals the real `un_rc_q`. The bullet predates this wave (last content-touch: 255642d, the tests/unit/ move) — it was already unsubstantiated, but `run()` at least existed until 163da3a deleted it; now the referent is gone entirely. Same shape, borderline: :91 ("deliberately OUTSIDE run() so they see the file at the rm's authority") — dangling comparator, but its rationale clause (probes run as direct sudo reads) still holds, so I do not raise it separately.

### W4 — INFO — Driver comment misdescribes the harness mechanism (pre-existing)

Evidence — tests/unit/test-uninstall.sh:370-371:

```
# the conf path, so it is fed a fake root via stdin) and run with a
# logging run() stub; the captured uid 60000 and the DISTINCT gids
```

The driver (:505-552) defines a logging `sudo()` stub and `log()`, evals the extracted real `un_rc_q` (:385 extraction, eval'd in the subshell), then evals `$PROJECT_LOOP` — there is no `run()` stub, at HEAD **and** at 6f9826e (the file's only diff in this range is the new pin at :1511-1516). Pre-existing inaccuracy; the removal makes the dangling name permanent. INFO.

## Verified clean (no findings)

- **Removal completeness**: invocation-anchored grep (`(^|[;&|(]|&&|\|\|)[[:space:]]*run[[:space:]]`, excluding `run_q`) over files/, tests/, scripts/ — zero statement-position `run` callers at HEAD **and** at 6f9826e (run on the `git show` blob): the removal is behavior-neutral; no path ever entered `run()` at either tree.
- **No sourcing/eval of uninstall.sh**: nothing sources or evals the file; harnesses sed-extract named sections (`un_rc_q()`, loops, case blocks — test-uninstall.sh:376/:385/:395 etc.) and none of those ranges ever captured the `run()` def.
- **Separate namespace**: scripts/release.sh:68 defines its own `run()` with callers :234/:238/:269 inside release.sh only — noted, not conflated.
- **Pin placement**: the new pin (:1511-1516) sits before the summary gate (:1547-1552) as the commit claims.
- **1abc8d6 (DEFAULT_USER=opencode)**: assignment is inert outside the extract-eval block — no `DEFAULT_USER` consumers after :1139; earlier suite uses (:237-245) are literal grep patterns, not value reads. Production claims verified: files/install.sh:630 `DEFAULT_USER="${SUDO_USER:-$(whoami)}"`, :723 `_bk_fail "gitconfig-$DEFAULT_USER"` — the harness label `gitconfig-opencode` is production-shaped as stated.
- **uninstall.sh in-file historical mentions**: :164-165 (new removal note), :396-399 ("both ops **were** claim-less `run` … Through un_rc_q now"), :826-828 ("the **former** `run` ops") — all past-tense, accurate; the commit-message claim "the historical mentions of former run ops stay — they describe past sites, accurately" holds for uninstall.sh.
- **docs/**: zero mentions of `run`/`run_q`/the wrapper — nothing stale.
- **Unintentional behavior changes**: none found — uninstall.sh hunks are def removal + comments only; the other two hunks are test-only.

## Coverage

Covered: all 3 commits' hunks read in context; repo-wide caller/sourcing sweep; byte-level pin-vs-historical-shape comparison with variant enumeration (executed against piped input in /tmp — the repo tree was never touched); stale-anchor sweep over uninstall.sh, test-uninstall.sh (every `\brun\b` line classified), docs/, and the rewording-class sweep; DEFAULT_USER blast radius; resolution.md diff read. Deferred: blame-tracing exactly when the wrapper-echo test body was deleted (only the header bullet's last content-touch, 255642d, was checked — enough for W3's classification, not for a precise staleness birthday); no e2e/lint runs (reader role, tree must stay byte-identical). No unverified suspicions remain open.

### Axis Q — quality (GLM-5.3-Flash)

## Findings index

| ID | Severity | Summary | Provenance |
|----|----------|---------|------------|
| Q1 | MED | e W3 def-count pin greps `'^run ()'` (space) but the removed def was `run() {` — the pin cannot fail on a verbatim resurrection; its comment and the commit message claim "fails loud" falsely | fix-induced (163da3a) |
| Q2 | MED | Corrected e W1 evidence sentence still overclaims: "all three log lines now read 'backup attempt: … — <verdict>'" — true for only 2 of 3 sites (branch-b log is a parenthetical) | delta-introduced (4959c4b, the e W1 fix itself) |
| Q3 | LOW | 163da3a commit message claims the e W3 resolution row was "shortened to 114"; the committed row is 110 bytes | wave-introduced (ledger recount drift) |
| Q4 | INFO | Three `<SHA>` placeholders open at HEAD (e W1→4959c4b, e W2→1abc8d6, e W3→163da3a) — sanctioned state, but the e W1 row at 119 bytes will tip to 121 on fill; Follow-ups does not name the fill debt | wave-introduced (bookkeeping state) |

## Details

**Q1 — MED — the e W3 pin is blind to the def shape it exists to catch.**
`tests/unit/test-uninstall.sh:1511-1516`:
```
# resurrected def without callers must fail loud here.
[ "$(grep -c '^run ()' "$UNINSTALL")" = 0 ] \
```
The removed helper was defined without a space — `git show 163da3a~1:files/opencode-permissions-kit-lib/management/uninstall.sh` line 164 is `run() {` — and every def in the house style is `name() {` (`run_q() {` :167, `un_rc_q() {` :190, `do_plan_phase() {`, `_bk_fail() {`). Measured directly at the parent tree: `grep -c '^run ()'` = **0**, `grep -c '^run()'` = **1**. So the pin returns 0 even against the pre-removal file: a resurrection in the only shape git history holds (revert, copy-paste of the removed block) passes green. The in-tree comment "a resurrected def without callers must fail loud here" and the 163da3a message claim "a resurrected def without callers fails loud" are both false for that scenario. Severity is MED conditional on the consequence being dead-code-only (the original e W3 was INFO): the pin itself never discriminates, which is exactly the fail-loud-pin class the house learnings call out; it should have been `'^run()'` or `'^run *()'`. No red-path run of this pin could ever have caught it.

**Q2 — MED — the e W1 "correction" replaces one overclaim with another in the same sentence.**
`internal/reviews/0/0/2/6/pr-00263/resolution.md:188-191`:
```
reorders to
"Copied to X. Backup saved.", the existing-config arm turns the
parenthetical into a trailing sentence) and all three log lines now
read "backup attempt: … — <verdict>" — corrected per snapshot e W1.
```
At HEAD the three d W1/W2 site log lines are: `files/install.sh:2001` `log "binary copied: $loc -> $SYSTEM_BIN ($_ocb_bk)"` (branch b — parenthetical verdict, no "backup attempt:", no "—"), `:2482` `log "opencode config replaced (backup attempt: … — $_occ_bk)"` ✓, `:2503-2505` `log "opencode config re-rendered … backup attempt: … — $_occ_bk)"` ✓. Two of three, not three of three — the branch-b log keeps the pre-d parenthetical shape (5171eb3:1993 was `(backup saved)`; HEAD is `($_ocb_bk)`, same shape, only literal→variable). The two restructure clauses in the same sentence are accurate (verified against 5171eb3:1992 `echo "Backup saved. Copied to $SYSTEM_BIN."` → HEAD:2000; 5171eb3:2464 `(opencode.jsonc — backup saved)` → HEAD:2480 trailing `$_occ_bk`). Why it matters: this sentence's second consecutive inaccuracy in the exact ledger sentence e W1 existed to make accurate; an auditor verifying the ledger by grepping `backup attempt:` at the binary site finds nothing and concludes the code drifted from the doc. The e W1 row's own summary ("2/3 sites reworded, logs reshaped", :75) is fine — the drift is in the detail block.

**Q3 — LOW — 163da3a recount drift on the shortened row length.**
Commit 163da3a: "shortened to 114, chain rerun whole". The e W3 row as committed at 163da3a and unchanged at HEAD (`resolution.md:77`) measures **110** bytes (`| e W3 (INFO) | **implemented** | \`<SHA>\` | run() removed; run_q doc + 4 comments updated; def-count pin = 0 |`). Both values sit under the 120 bound, so no gate was affected; the immutable message simply misdescribes the committed artifact by 4 bytes. Ledger note only.

**Q4 — INFO — open `<SHA>` placeholders: who owes what, and one fill will trip the ratchet.**
`resolution.md:75-77` — three rows carry `` `<SHA>` ``: **e W1** owes **4959c4b** (the evidence-sentence fix rode 4959c4b itself), **e W2** owes **1abc8d6**, **e W3** owes **163da3a**. This is the sanctioned state per `internal/reviews/README.md:181-186` ("the Commit column carries `<SHA>` … and the chain's next commit replaces it with the real short SHA") — no violation at HEAD, since 4959c4b is HEAD and cannot know its own SHA. Two things the ledger should be aware of: (a) the e W1 row is at **119** bytes; the fill adds +2 (`<SHA>`→`` `1abc8d6` ``-shaped, README:185-187), tipping it to 121 — the next bookkeeping commit must shorten that row before/while filling, exactly the live c3fcb7b scenario; (b) the rewritten Follow-ups (`resolution.md:259-266`) does not name the `<SHA>`-fill debt among the owed items. I found nothing else owed-but-unnamed: the micro-wave-review-of-e-fixes line covers the snapshot-f debt substantively, and e2e-not-owed for e W3 is correct — the removal is provably behavior-neutral (zero statement-position `run` callers at the parent, verified by word-boundary grep: def + prose only) and the AGENTS semantics rule exempts comment-shape-only changes to root-run scripts.

## Verified clean (no finding)

- **e W2 anchors exact:** `files/install.sh:630` `DEFAULT_USER="${SUDO_USER:-$(whoami)}"` and `:723` `|| _bk_fail "gitconfig-$DEFAULT_USER"` — both line-accurate; "never an empty string" is enforced by the charset guard at :633-639.
- **DEFAULT_USER sweep after :1133:** only :1137 (drive) and :1139 (assertion) expand it — both intended and self-consistent; no later assertion or message changes meaning. Assignment is before the `_BKDEF` extract (:1135); not exported (plain assignment, :1133); suite has `set -e` but no `set -u` (:30), and the drive subshell sits in an if-condition where set -e is suspended. The e W2 commit's claims all hold.
- **W2 safety claim:** extracted `_bk_fail` body (`install.sh:714-719`) is pure `_BK_FAIL` accumulation + `echo >&2` + `log` (undefined in the harness → "command not found" → swallowed by the subshell-level `2>/dev/null` at `test-install-args.sh:1141`). No sudo/filesystem reach — claim true.
- **W3 recounts at HEAD:** `run_q` keeps 4 live statement-position call sites (:612, :613, :615, :620) in the executed user-removal path; zero statement-position `run` callers at parent and HEAD; exactly 4 `run_q convention` comments (:549, :626, :831, :885), zero `run/run_q` remain; pin sits before the summary gate (`test-uninstall.sh:1547-1550`); historical `run` mentions (:397, :826-827) accurately describe past sites; the doc comment's "last two callers went to un_rc_q (#246 site 7)" matches `un_rc_q "plugins rm"`/`"tui unregister"` (:402-403).
- **Gates claims:** INDEX carries 33 case rows (34 `^| ` hits minus the header) — "reviews lint 33, parity 33" consistent.
- **No stray `run()` references** in tests/ or docs/ (all hits are unrelated `*_run()` helpers in test-status.sh).

## Coverage

Covered: all four diff hunks read in full; both install.sh anchors verified by line and content; full `$DEFAULT_USER` expansion sweep of test-install-args.sh; the extract-eval block read end-to-end (:1119-1165); run/run_q/un_rc_q caller census at parent and HEAD via word-boundary grep; pin position vs. summary gate; e W1 claims diffed against pre-d 5171eb3 shapes at all three sites; all four e-row lengths measured at each introducing commit; README `<SHA>` rule read; INDEX count checked. Deferred: running any suite or the reviews lint/parity gates (reader-only mandate — gate-green claims checked statically only); the historical ratchet-catch counts ("caught at 121/126 pre-commit") are unverifiable from the committed trees and were accepted as process narration, with only the committed final states recounted (→ Q3).

## Verification notes (house, GLM-5.3)

Every finding was re-verified against the code at 4959c4b (tree
porcelain-clean before, during and after the pass — the one mutation
window is the sabotage below, closed before fan-out):

- **W1/Q1 verified by execution, not pattern argument** (sabotage
  spot-check, window a — BEFORE fan-out, no readers running, tree
  committed-clean at 4959c4b): the historical def block was
  re-inserted byte-exact at its old location (`run() {` … `}`, from
  `git show 6f9826e`) → `sh tests/unit/test-uninstall.sh` **rc 0,
  "All uninstall tests passed"**, and the e W3 pin itself PASSed
  ("run() helper gone, no orphaned runner") over the resurrected def
  — a false PASS on exactly the scenario the pin exists to catch.
  Flipping only the def spelling to the spaced `run () {` → the pin
  FAILed red ("run() def present without callers"), rc 1. `git
  restore` → porcelain-clean, suite green again. Q's parent-tree
  measurements re-checked: `grep -c '^run ()'` = 0 and `grep -c
  '^run()'` = 1 at 163da3a~1 — the committed pattern never
  discriminated at any tree, past or present. Severity MED confirmed
  (test-only impact named in the same breath: a missed resurrection
  is dead code until called — but the pin's sole deliverable is
  unmet and claimed delivered in three places: pin comment :1511,
  commit 163da3a, resolution row e W3).
- **W2 verified**: test-uninstall.sh:816-817 and :1099-1100 read in
  context — both describe TODAY's dry-run drivers with the compound
  "run/run_q convention" name; the four uninstall.sh rewordings
  (:549/:626/:831/:885 → "run_q convention") confirmed, no fifth
  site; repo-wide `run/run_q` grep leaves only these two test sites
  plus frozen ledger prose. LOW — class sweep incomplete
  (AGENTS.md memory aid), comment-only.
- **W3 verified**: test-uninstall.sh:3 quoted verbatim; every `run()`
  hit in the file enumerated (:3, :91, :371 prose; :1263/:1300/:1363/
  :1407/:1450 differently-named `_*_run()` helpers; :1511-1516 the new
  pin) — no test exercises a run() wrapper. The bullet was already
  unsubstantiated before the range; 163da3a deleted the referent.
  LOW — the fix for the header bullet is one comment line.
- **Q2 verified, severity screened MED → LOW**: all three log lines
  read at HEAD — `install.sh:2001` `log "binary copied: $loc ->
  $SYSTEM_BIN ($_ocb_bk)"` with `_ocb_bk` = "Backup saved." /
  "binary backup FAILED — see Backup summary" (:1990/:1993) — a
  parenthetical verdict with NO "backup attempt:" literal; :2482 and
  :2503-2505 do read "backup attempt: $BACKUP_DIR/… — $_occ_bk".
  2 of 3, not 3 of 3: the corrected sentence is wrong again, in the
  same sentence e W1 was filed over. Downgraded from the reviewer's
  MED: prose-only ledger drift, zero behavior — the identical class
  scored LOW as e W1 in this very case; the aggravation (second
  consecutive inaccuracy in the sentence that was itself a
  correction) is recorded here and in the recommendation, not
  inflated into a severity the class has never carried.
  Correction of record against frozen history: snapshot e's
  verification note ("ALL THREE sites' log lines change shape …
  'backup: $DIR' → 'backup attempt: $DIR — <verdict>'") carried the
  same conflation — branch-b's log never read "backup: $DIR" and
  does not now read "backup attempt:"; the e W1 FINDING (all three
  log lines changed shape at all) remains true — literal→variable +
  case change at branch-b.
- **Q3 verified**: `awk length` (bytes) on the e W3 row = 110 at
  163da3a and at HEAD; commit message says 114. Both under 120, no
  gate impact, immutable history — ledger-note class (d Q3
  precedent). LOW.
- **W4 verified**: stub definitions enumerated (:532 `sudo()`, :547
  `log()`, :1042/:1053 second driver, :1266/:1270 per-case) — no
  `run()` stub anywhere at HEAD or 6f9826e. Pre-existing; the
  removal makes the dangling name permanent. INFO.
- **Q4 verified**: rows measured at HEAD — e W1 119, e W2 110, e W3
  110, e Q1 116 bytes; README:181-189 fill rule read; the chain's
  next commit is THIS snapshot's commit → the three fills
  (`4959c4b`, `1abc8d6`, `163da3a`) and the e W1 row shortening
  (119 + 2 = 121 → shortened to 116) land in it, check-then-commit.
- **Clean-verdict spot re-checks (first-hand)**: `run_q` live
  callers :612/:613/:615/:620; four `run_q convention` comments;
  pin-before-gate placement; `$DEFAULT_USER` after :1133 consumed
  only at :1137/:1139; uninstall.sh:396-399/:826-828 past-tense
  framing; both reviewers' checkpoint files present under
  /tmp/opencode/pr-00263-f/checkpoints/ — all confirmed as reported.

No finding retracted. One severity change (Q2 MED→LOW, disclosed
above with the precedent). One cross-axis duplicate merged (W1 ≡ Q1,
independent convergence — both reports embedded verbatim, counted
once). No reviewer `unverified` residue remains.

## Retracted / ghost findings

None — all 7 reported findings verified (W1/Q1 as one construct).
The one borderline the W reviewer itself declined to raise
(test-uninstall.sh:91 "deliberately OUTSIDE run()" — dangling
comparator whose rationale clause still holds) is recorded in W3's
detail as declined, not retracted.

## Calibration

Micro scope — two axes, one fast-tier agent each, no per-axis
redundancy (the micro budget; wave/full shapes get more). The two
axes converged independently on the pass's one MED (the def-count
pin's spaced pattern vs the no-space def — W via variant
enumeration, Q via parent-tree measurement; the house sabotage then
proved it executively) — convergence on a construct both were pointed
at by the blind-spot line ("a count/absence pin must be tested
against the exact historical shape of the construct it guards") is
shared strictness, disclosed here: the axes did NOT independently
discover the pin from an open field, and the MED rests on the
sabotage execution, not on the 2-vote count. Yield otherwise:
comment-sweep residuals (W2/W3), ledger precision in the corrected
sentence itself (Q2), recount drift (Q3), pre-existing dangling
prose (W4), bookkeeping state (Q4). Severity discipline: one
reviewer MED downgraded to LOW with the in-case precedent named
(Q2 ≡ e W1 class); the merged MED kept test-only impact in the same
breath as the severity. The stop rule (MED/HIGH reads) has exactly
one thing to read: f W1 — the pin fix is a one-character-class
pattern change (`'^run()'` or `'^run *()'`) plus the three "fails
loud" claims it falsifies; the dispositions are the maintainer's
call, this round changes no review-relevant code beyond ledger
bookkeeping (the <SHA> fills). No second snapshot owed (micro).

## Run provenance

- Host window (UTC): pre-launch stamp **2026-10-25T22:53:55Z**
  (chain read + material measurement; sabotage window a closed
  before it), reviewer launches **2026-10-25T22:56:41Z**; W returned
  first, Q second (both in the 23:0xZ hour); post-return host stamp
  **2026-10-25T23:04:44Z**, screening/verification 23:04–23:06:30Z.
  Sandbox clocks ran +0100; reviewer self-stamps in the checkpoints
  were normalized to UTC.
- Reviewer agents: 2x `zai-coding-plan/glm-5.3-flash` (explore
  reader agents, read-only): W mechanical sweep
  (ses_e8ab83658ffephCIly7iO90798), Q quality
  (ses_e8ab83656ffe99he1mnfVF4tR). Checkpoints:
  `/tmp/opencode/pr-00263-f/checkpoints/{W-sweep,Q-quality}.md`
  (session scratch outside the reviewed tree; absorbed here).
- Sabotage spot-check (window a — BEFORE fan-out, no readers
  running, tree committed-clean at 4959c4b): historical `run() {`
  def re-inserted byte-exact → suite green, e W3 pin false-PASSed
  over the resurrected def (rc 0); spaced `run () {` → pin red
  (rc 1); `git checkout -- <file>` → porcelain-clean, suite green
  (rc 0). Logs: `/tmp/opencode/pr-00263-f/sab-{A-nospace,B-space,
  C-restored}.log`. One earlier failed redirect (log dir not yet
  created) left the insertion unobserved for one shell line — the
  dir was then created and the A-run executed properly; no reviewer
  overlapped any mutation (first launch followed the closed window).
- Tree under review: `release/0.0.57 @ 4959c4b`, porcelain-clean
  before and after the pass; the reviewed range 6f9826e..4959c4b is
  exactly the commissioned `6f9826e..` (no out-of-range commits this
  time).
- Resolution edits riding THIS snapshot's commit (the chain's next
  commit per the README fill rule and the snapshot-e precedent):
  e W1/e W2/e W3 `<SHA>` fills (`4959c4b`/`1abc8d6`/`163da3a`), the
  e W1 row shortened 119→116 for the +2 fill (the issue #237 shape,
  caught check-then-commit this time), the chain line extended with
  snapshot f, and the Follow-ups rewrite recording that the owed
  micro-wave ran as THIS snapshot — dispositions owed, closure NOT
  declared (RM-0106/RM-0107/RM-0115).
- Gates run before this snapshot's commit (one unbroken `&&` chain,
  output to a log file): `sh tests/unit/test-reviews-lint.sh`,
  `sh tests/unit/test-reviews-parity.sh`,
  `sh tests/unit/test-line-length.sh`, INDEX regenerated via
  `python3 scripts/gen-review-index.py` (check-then-commit; the
  snapshot body is immutable frozen history per the ratchet's scope
  — the in-scope resolution edits stay ≤ 120).
- e2e: not owed by this round — the range touches no shipped
  semantics (uninstall.sh hunks are a dead-def removal + comments;
  both axes verified zero statement-position `run` callers at the
  parent tree and HEAD, so no statement path changed), and the
  snapshot itself is ledger-only (AGENTS Testing semantics rule).
- Environment: opencode kit checkout at
  `/var/www/vhosts/opencode-permissions-kit/repo` (kit-managed
  install, agent user `opencode`); main session GLM-5.3.

## Recommendation

The e fixes' behavior claims hold — the run() removal is provably
behavior-neutral at both trees, the e W2 label fix does exactly what
its row says, and the e W1 row summary is accurate. But the round's
only new pin does not work and is claimed to work in three places —
**f W1 (MED)**: fix the pattern to `'^run()'` or `'^run *()'`,
sabotage-verify the fixed pin (delete-not-comment discipline is N/A
here — the failure path is resurrection; re-run this pass's
shape-A/shape-B sabotage), and correct the "fails loud" wording in
the pin comment and the e W3 row's ledger echo. Dispositions owed
(maintainer's call): **W2/W3** (one-line comment sweeps — the two
`run/run_q` siblings and the stale header bullet; consider :91/:371
(W4) in the same sweep), **Q2** (one-sentence ledger fix — "two of
the three log lines"; this is the second correction of that
sentence, so diff-check it against install.sh:2001/:2482/:2503-2505
before committing), **Q3** (record-only correction of note),
**Q4** (discharged by this commit's fills — verify the shortened e W1
row still reads true). The stop rule has one MED read: with f W1
open, the loop cannot close this round — closure stays the
maintainer's or the next round's call (RM-0106/RM-0107, RM-0115).
