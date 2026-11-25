# Conventions

> Status: **BINDING** — this is the living style guide for shipped code, not
> a historical design record. Change it via PR when a convention evolves;
> update the affected code in the same PR.

## Interactive prompts (y/n)

Every yes/no question in shipped scripts follows one pattern:

```
  Proceed with uninstall? [y/N]
                        ^^^^ default = capital letter
```

- **Format:** `<question> [Y/n]` or `<question> [y/N]` — square
  brackets, the **default as the capital letter**; the line carries
  the two-space indent of the standard output style and no extra
  marker. (RM-0004)
- **Enter accepts the default** (empty answer = default). (RM-0005)
- Accepted input: `y`, `yes`, `n`, `no` — case-insensitive;
  leading/trailing whitespace is trimmed before matching (a padded
  ` y` is an explicit answer, #189 a W2). Unknown input falls back
  to the default. (RM-0006)
- **Default choice:** `n` for anything that changes the system (remove,
  provision, proceed with destructive steps), `y` only where "no" is the
  surprising/riskier answer (e.g. the recommended audit-log deletion during
  uninstall). (RM-0002)
- Don't invent alternatives (`(yes/no)`, `Y/N`, `[yes|no]` …). If a choice
  needs more than yes/no, use a numbered/keyed menu (`ui_menu`). (RM-0007)

Implementation:

| Context | Helper |
|---|---|
| Scripts that source `ui.sh` | `ui_confirm "Question?" <y\|n>` |
| install.sh menus | `ui_menu` (keys like `1`/`C`/`A`/`X`, default highlighted) |
| uninstall.sh (standalone, no ui.sh) | local `prompt_yn` (same display rules) |
| opk with a damaged library | fallback `ui_confirm` in `bin/opk` (same display rules) |

- Free-text questions (`ui_ask`) show `[default] >` — different shape on
  purpose, they are not confirmations. (RM-0036)

## Script output style

See `internal/records/_archive/design/ux-improvement.md` (decisions, archived):
labeled lines `info`/`success`/`warn`/`error` via `ui.sh`, slim banner,
Unicode symbols with `UI_ASCII=1` fallback, `NO_COLOR` and non-tty
honored.

- Severity rows are **semantic, not colorized `ui_kv` calls** (issue
  #158): verdict rows use `ui_kv_ok` / `ui_kv_warn` / `ui_kv_bad` (and the
  checklist helpers `ui_have` / `ui_atten` / `ui_miss`), which render the
  same output but also bump the counters `UI_ROWS_OK/WARN/BAD` — a summary
  (`status.sh`'s verdict line) can tally findings by call site, where
  counting color bytes would fail (they are empty under `NO_COLOR`/piping).
  Two consequences for report scripts follow. (RM-0037)
- Rows printed inside a pipeline (`cmd | while ...; ui_kv_warn ...; done`)
  count in the pipe's subshell and the tally loses them — feed such
  loops from a temp file and read it via redirect (`while ... done < "$f"`). (RM-0008)
- `UI_SILENT=1` mutes every non-interactive print helper while the
  counters keep running — the base for one-line report modes
  (`opk status --short`). The question helpers (`ui_ask`/`ui_confirm`/
  `ui_menu`) are deliberately not muted: a muted report mode must not
  fall through to an invisible prompt. (RM-0009)

Additional script output style rules:

- Report commands carry their verdict in the exit code (`opk status`:
  `0` all green, `1` alert(s), `2` warning(s) only, `64` usage error) so
  cron/timers can react without parsing output. (RM-0038)
- File lists in code (fetch/deploy lists such as `KIT_FILES`, install.sh's
  fetch list, and the `lib_deploy` manifest): **one file per line**,
  backslash-continued. Packed multi-name lines make diffs unreadable;
  consumers and tests compare word-wise, so the layout is pure
  convention — keep it when adding entries. (RM-0039)

## Formatting (shfmt)

All kit shell is formatted canonically by **shfmt** (issue #255
stage 0a) — the style authority for `files/`, `scripts/` and the
kit's own test scripts. Style is not a review topic: the gate
(`make lint`) rejects anything `shfmt -l` lists.

- Settings: `-ln dash -i 4 -ci` (mirror: `.editorconfig`, pinned
  equivalent by `tests/unit/test-format-gate.sh`). Deliberately NOT
  set: `simplify`, `keep_padding`, `space_redirects`,
  `binary_next_line`, `func_next_line`.
- The version pin is **exact** (`SHFMT_VERSION` in the Makefile,
  today v3.14.1): formatting output drifts between shfmt versions
  (3.7.0/3.12.0 reformat lines 3.14.1 leaves alone), and the dash
  variant needs 3.14.x. Install via `make install-shfmt`.
- Run `make fmt` between edit and first suite run — a green suite
  followed by a shfmt red-list forces a full re-verify cycle after
  `shfmt -w` (two files red-listed mid-#519-wave); hand-formatting
  against the canon does not stick.
- Wrapping a long line is a measured decision, not a guess: under the
  pinned shfmt the **dq splice** (frag2's opener at EOL, the
  backslash-newline INSIDE the double quotes — the form shfmt itself
  produces from a classic wrap) is the only byte-identical AND
  fmt-stable shape. A single-quoted literal has none: the classic wrap
  at column 0 is joined back into the long line; the indented classic
  is normalized to spaced fragments — separate WORDS, so `echo`
  inserts seam spaces and a split sed script becomes two arguments —
  and an sq "splice" is no continuation at all (backslash-newline is
  literal inside single quotes). Wrapping an sq literal therefore
  converts it to dq first, after checking for `$`, backtick and `"`
  hazards — and the wrap's byte-identity is proven by EXECUTING old
  vs new and comparing the output: the ratchet and the join guard
  stay green on every broken sq form, and fmt red-lists only the two
  classic spellings — its canonical output for the indented classic
  IS the broken spaced-words shape, and the sq splice never trips
  fmt at all; post-fmt, only execution discriminates (#300 tier 1,
  sharpened by review #331 a a-2, measured 2026-10-31).
- A pin greping a message that the house continuation idiom wraps
  matches the WRAP, not the contiguous phrase: wrapping changes the
  source bytes, so a `live_src` pin on the contiguous phrase reds on
  a purely cosmetic wrap. Grep both fragments separately (`grep -q
  'retry anytime' && grep -qF 'already-imported…'`) — the
  test-ddev-migrate D3 retry-hint pin, pr-00568 wave a.
- That pin rule has a sweep-side inverse: an inventory or class sweep
  over shipped shell joins backslash continuations BEFORE grepping
  (or greps the payload fragment standalone) before claiming site
  completeness — the house dq-splice idiom puts the variable on the
  SECOND physical line, invisible to any single-line `echo.*$var`
  pattern (PR #642 round b S1: the round-a sweep found 5 of 7 warn
  arms in ddev-migrate.sh, the continuation-joined re-sweep all 7;
  any mechanical join is fine — the round-b/c form folded
  backslash-newlines with python before grep).
- A structural pin greps the CANONICAL spelling — the bytes `make
  fmt` leaves, not the bytes typed: shfmt reformats `! ( : </dev/tty
  )` to `! (: </dev/tty)`, and a pin written against the pre-fmt
  spelling reds after the next format run (test-git-config 8a,
  pr-00568 wave a). Run `make fmt` before writing the pin.
- Still human rules, NOT shfmt's business: the 120-column ratchet
  (`tests/unit/test-line-length.sh` — shfmt never wraps lines), the
  string-continuation join guard (`test-string-continuations.sh`,
  aware of both the classic and the shfmt splice wrap shape), and
  the one-file-per-line file-list rule earlier in this section.

## Shell security (untrusted input)

External data — HTTP feeds, files someone else wrote, anything parsed
from outside the script — is untrusted. It may influence shell *data*,
never shell *structure*:

1. **Quoting.** Every expansion of external data is double-quoted. No
   `eval`, no `sh -c` with interpolated values, no unquoted `$var`
   (word splitting and globbing are injection surfaces). (RM-0010)
2. **`printf '%s'` style.** External values are arguments to a fixed
   format string, never the format itself — `printf "$EXT"` interprets
   `%` and `\` sequences from the data. (RM-0011)
3. **Free text flows through files, not argv.** Long untrusted content
   (issue bodies, messages) goes via a temp file (`--body-file`), never
   through argv, where a crafted value could steer a flag or a query. (RM-0012)
4. **Allowlist before argv/query.** Any field that leaves the script as
   an argument or inside a query string (`gh --search ...`) is
   shape-validated first:
   - charset allowlists via a **negated class**:
     `case "$x" in *[!A-Za-z0-9-]*) reject ;; esac` — a prefix glob
     (`GHSA-*`) swallows payloads behind the prefix, only the negated
     class rejects every foreign character
   - **anchored** regexes for structured values (both ends:
     `grep -qE '^[0-9]+(\.[0-9]+)*$'`)
   - vocabulary `case` for enums (severity, channel, backend)
   - fixed-string exact matches (`grep -qxF`) for ids — no regex
     metacharacter interpretation, no query steering (RM-0013)
5. **Fail loud vs. fail open.** Maintainer automation skips malformed
   data with a warning and exits non-zero (a red CI run is the
   visibility). The wrapper's hot path fails open instead — an
   unavailable check must never keep a session from starting. (RM-0040)
6. **Prove it in tests.** Payload attempts (command substitution,
   qualifier smuggling, column shifts) are unit-tested, with a
   marker-file proof that nothing ever executed. (RM-0041)

Patterns already in this repo:

| Context | Pattern | Code |
|---|---|---|
| GitHub advisory feed → `gh` argv/query | `scan_advisory_valid` — charset + vocabulary + anchored ranges | `scripts/advisory-watch.sh` |
| version resolution (GitHub/npm) | strict `case 1.*`/`2.*`, loud abort outside the shape | `management/update.sh` (`resolve_latest_opencode_version`) |
| version probes | strict `grep -oE` extract; empty means unknown, never a guess | wrapper, `management/status.sh` |
| exact id comparison | `grep -qxF` (fixed string, whole line) | `sh/advisories.sh` callers, scan dedup |

## Shell semantics (dash and POSIX sh)

The kit targets exactly two shells (dash and bash-as-sh — the SC3043
exclusion in the Makefile's ShellCheck pin), and their differences
have bitten shipped code and tests more than once. The rules below
are the distilled incidents:

- A special builtin's failed redirection is FATAL under dash — `:
  </dev/tty` with an unopenable target kills the script outright,
  where bash continues with a non-zero rc. Probe such a redirection
  inside a subshell — `( : </dev/tty ) 2>/dev/null` — so the fatality
  becomes a plain non-zero rc the caller can branch on (the config.sh
  M1 guard shape, pr-00568 wave a). (RM-0163)
- Comment text inside a single-quoted `sh -c` worker string (xargs
  workers) stays apostrophe-free — an apostrophe terminates the
  string and the remainder becomes garbage. Neither `sh -n` nor a
  clean run is the discriminator: an UNBALANCED apostrophe fails
  `sh -n` outright, but a balanced pair mangles the worker into a
  silent no-op that `sh -n` AND a clean execution both pass (probe,
  pr-00586 round a A2). The check is the grep — worker-string
  comments carry no apostrophe at all (the pr-00568 wave broke
  ddev-handover.sh twice on `abort's` before that rule existed).
  (RM-0164)
- A `case` pattern list split across lines is not parseable shell:
  POSIX case grammar takes one arm's alternatives on one physical
  line — a list ending in `|` with the further alternatives on the
  next line dies at `sh -n` with "word unexpected" and reddens
  ShellCheck (SC1073/SC1009; probed in scratch, one red lint cycle
  paid — issue #738, PR #729 fix wave a). When a new form-arm class
  would push a shared pattern line past the 120-column ratchet, give
  the class its OWN `case` statement after the shared one — the
  handover declared-tree belt's three-case shape, whose own comment
  names the reason ("a separate case keeps the structural list
  inside the ratchet", sh/handover-core.sh). (RM-0203)
- A presence check on a shell function proves the function exists,
  never WHERE its definition came from — `command -v func` is
  satisfied by a stub from an earlier invocation of the same shell,
  an `export -f` import (bash) and a sourced vintage alike. A
  stub-or-real distinction built on presence needs an
  invocation-scoped `unset -f func` reset at entry (every invocation
  re-derives the probe from its own sourcing) or a definition-site
  marker the sourced file sets itself — the never-shadow fail-safe's
  marker precondition was satisfied by the very rc-0 stub it existed
  to prevent (PR #746 round b D1 over round a's B1 marker, fix
  53364ca9; probed in dash). (RM-0209)

## Python3 pipeline tees (health probe, fork cache, degrade)

Shipped progress tees (`find … | tee-with-counter | …`) run python3
inline on DATA paths. The pattern's sites as of #710 — status-core's
`_st_progress_tee`, fs-baseline's `_fsb_count_tee`, git-heal-core's
`_ghc_progress_tee` — predate this section, and PR #710 spent three
review rounds re-deriving knowledge that lived in code comments 200
lines apart (#714); this section is the one findable home. The two
mechanism claims below were re-probed in scratch 2026-11-21 before
codifying (fork cache; broken-shim health probe).

- The python3 check is a HEALTH probe, not `command -v` presence: a
  findable-but-broken interpreter (pyenv shim to a removed version,
  poisoned PYTHONHOME/PYTHONPATH) passes presence and dies at
  pipeline startup — on a data path it hands the consumer loop an
  EMPTY scan list, a silent false-green (#221 a W3). The probe runs
  the SAME invocation shape as the tee it gates (`python3 -I -c
  '<exactly the tee's imports>'`): presence checks a different fact
  than the execution about to stream. (RM-0194)
- Probe once per run, from the MAIN shell: the verdict caches in a
  `<pfx>_py_checked`/`<pfx>_py_ok` pair, and a pipeline member is a
  FORK — a cache first written inside a pipeline dies with the fork
  (every call site re-probes and re-warns, PR #710 b D2), while a
  main-shell cache is inherited by every pipeline member. Call the
  probe from the main shell before the pipeline; a tee-side call is
  the same no-op once the cache is set (fs-baseline and git-heal-core
  spell it that way, status-core probes in its consumer).
  (RM-0195)
- On probe failure the path DEGRADES — the stream loses its live
  counter, never its data — in two sanctioned spellings: the
  tee-side plain `cat` passthrough with one warn line naming the
  degradation (fs-baseline, git-heal-core), or the consumer-side
  skip that never starts the tee (status-core — silent by design:
  the probe's own unswallowed stderr is the signal, #244 c S3). A
  diagnostic rerun that swallows stderr (`2>&1` into the void)
  discards exactly the cause it exists to show (PR #710 b D1).
  (RM-0196)

Reference implementations with their pin suites: `sh/status-core.sh`
(#221 a W3; `tests/unit/test-status.sh` — the #244 c S3
health-probe pins — and `tests/unit/test-status-core.sh`),
`sh/fs-baseline.sh` (`tests/unit/test-fs-baseline.sh`),
`sh/git-heal-core.sh` (`tests/unit/test-git-heal-core.sh`; born PR
#710 rounds a–c — the pattern's cost record).

## Lib pairing and cross-lib guards (entries that source libs)

An entry script and the libs it sources are pinned surfaces — version
skew between them must refuse loud (or count the degradation visibly),
never proceed silently. Two tiers with DIFFERENT pinning sets
(design record: [internal/records/cross-lib-pairing-guards.md]
(../internal/records/cross-lib-pairing-guards.md), issues #413/#452/#456):

- **Paired core:** the entry's pairing guard list equals the core's
  DEFINITIONS, both directions, enforced by test riders — entry and
  core are same-vintage by construction, and helper-level skew is the
  #452 finding.
- **Cross-lib (other sourced libs, ui.sh included):** pin the USED set
  — every function entry AND core call. A lib's full definition set is
  deliberately NOT pinned here: legitimately older deployed libs may
  lack functions the run never calls. ui.sh consumers carry a used-set
  guard right after their resolver (refuse before the first
  section/phase); other cross-lib functions ride entry stub arms with
  named semantics (loud for actions, no-op for advisories/stamps,
  fail-closed for policy gates, never-shadow for probes).
- **The discriminator is missing-FILE vs present-but-skewed:** a
  missing lib keeps the entry's documented legacy contract (compat
  stubs or a loud abort); a present-but-skewed one is a broken kit and
  refuses loud. Fail-soft report surfaces (status) degrade into a
  COUNTED warn row (`ui_kv_warn ... not checked — ... (fix: sudo opk
  update)`), never a silently dropped row.
- **Riders** for these surfaces: comment-stripped both sides,
  boundary-anchored, emptiness-probed, and their token extraction keeps
  line separation (`tr -d '[:space:]()'` concatenates definitions into
  one token and the rider goes vacuous — the #456 sabotage cycle);
  lib iteration covers what the run SOURCES, never a whole-dir glob
  (wrapper-side shell hooks like `ddev()` live in the same directory).

## Source-counting pins (unit suites)

The decision rule for a PRESENCE grep over a live source file: go
through `check_live` / `live_src` — never a direct `check` + `grep`
pair over a registered source variable (rider-lint rule 2 reddens
exactly that shape, #524 §2). The section's sanctioned raw shapes —
markdown docs pins, absence pins, behavioral probes, captured-output
pins — stay raw by design (below).

Any unit-test pin that COUNTS a literal in a shipped or repo-internal
source file to assert its PRESENCE or a count floor (`grep -c …
"$INSTALL"`, counts over extracted blocks or `grep -n` extraction
legs) counts through `live_src` (#460, `tests/unit/lib/harness.sh`)
— the canonical comment-strip rider — so a commented-out construct
stops counting (the survivor trap, #261/#244 g W1). The shapes:
`live_src "$FILE" | grep …` for pipes, counts and extraction legs;
`check_live "desc" "$FILE" -qF 'literal'` for the single-file
presence check; `live_src "$A" "$B" | grep …` for the multi-file
presence (a concatenation sums per-file counts). Stripping an
extracted BLOCK (extract_func output, a printf-fed variable) keeps
the INLINE `sed 's/^[[:space:]]*#.*$//'` — live_src is files-only;
that stdin shape is sanctioned, not a finding. What IS a finding: a
raw inline rider over a FILE operand in a NEW pin — gated by the
rider lint (tests/unit/test-rider-lint.sh, rule 1), which matches
the three historical byte forms with a same-line operand; exotic
re-spellings (tab after the expression, `sed -e`, a `g` suffix, a
continuation-line operand) escape the detector and stay the
reviewer's call. The strict `check "desc" grep … "$SRCVAR"`
single-file presence shape is GATED (rule 2, converted by the #460
census wave: 85 sites to check_live, one to the inversion below -- 86
total):
registration derives from the suite's assignments — a variable whose
value references the repo/shipped tree (`$REPO/`, `$FILES/`,
`$SCRIPT_DIR/../../`, `$SCRIPT_DIR/../sh/`, `../e2e/`, `.github/`)
directly or through another registered variable. Slash-comment
sources (values ending `.jsonc/.json/.ts/.tsx`) register but stay
EXEMPT pending the deferred JSONC `//` decision. Markdown sources
(values ending `.md`) stay EXEMPT too, but DECIDED, not deferred
(#472): a `#`-initial line is a heading there, so the strip rider
deletes live content — a docs reorg that leaves the pinned literal
only in heading lines false-alarms a ridden pin, and extraction legs
over markdown (a `sed -n '/^## …/,/^## /p'` span) use headings as
their anchors, which riding would delete. The canonical docs-pin
shape is therefore the raw un-ridden grep (`check "desc" grep -qF --
'literal' "$MD"` — the `--` guards dash-leading flag literals, the
common docs-pin class; if-form pipes likewise); a docs-presence sugar
(`check_raw`/`raw_src`) enters the harness at the third
strict-shape site per the rule of three — one exists today
(test-update-flags.sh's cli.md `--only-binary` pin, un-ridden by
#472).

A docs pin's literal is chosen against the doc's WRAP, not the
phrase's prose: `grep -qF` is line-based, house docs wrap at ~72-80
columns, and a natural multi-word phrase spanning a hard line break
misses while the disclosure is fully intact — pin the shortest
distinctive single-line fragment, and know the count before the
gate run: `grep -cF`
gives it (1 for a distinctive fragment; recurring flags legitimately
count higher — the `--only-binary` pin counts 2 in cli.md). When
a disclosure pin reds after a doc edit, check the
line-break split FIRST before suspecting content loss — the red
message names the disclosure as missing and invites restoring text
that was never lost (probed 2026-11-20: the drafted phrase "complete
closure remains a separate agent clone" missed across a wrap between
"agent" and "clone" — and the doc's `*emphasis*` markers are a
second single-line miss-maker the same fragment check catches; the
surviving single-line fragment holds —
#690, PR #689; the multi-word #483 literals share the latent shape,
the single-token `OPENCODE_PODMAN_SOCKET` cannot split). The
shell-side sibling — a pin over house-wrapped shell matches the
WRAP, not the contiguous phrase — lives in "Formatting (shfmt)"
above.

When the JSONC `//` decision eventually lands it follows the
same boundary as the markdown exemption above (#472) — its own primitive or semantics, never the `#` strip
pointed at non-`#` syntax. The `sh -c`
indirection of the same shape (`sh -c 'grep … "$1"' _ "$SRCVAR"`) is
GATED too since the #470 wave (rule 3; was a down-only ratchet until
then, 304 residual sites converted): single-leg presence greps go to
`check_live`, multi-leg and extraction pipelines (awk ranges,
`grep -A/-B` context, `sed -n` spans, `head`/`tr`/`cut` consumers) to
parent-if + `live_src` pipes (the strip substitutes empty lines, so
NR bookkeeping stays true) — the gate covers the detector's grammar
(single positional file, presence-only, var-bound); sibling spellings
(multi-operand payloads, literal-path bindings, indirect
`$(cd "$(dirname "$0")/…")`-spelling bindings the registration regex
cannot see, `;`-statement payloads, numeric-gate second operands
lifting the positional count, if-form shapes)
escape it and convert on sight like the counted shape did. Shapes
where `live_src` would change the semantics unwrap RAW instead,
un-ridden: behavioral probes (`. "$1"` sourcing, `sh "$1"` execution,
`make -n` dry-runs, numeric gate checks — a commented-out construct
changes the probe's behavior, so the survivor trap does not apply)
and pins over CAPTURED OUTPUT (`sh -c` output captures, printf-stdin
payloads — what the process printed carries no comment-line
structure; the detector's transitive registration over-approximates
these). This exemption does NOT cover SOURCE-TEXT captures: an
unstripped `sed -n` span or extract_func block carries comment lines
verbatim, so a raw pin over one still matches a commented-out
construct — ride `live_src`, or strip the block at capture (the
inline block-strip sanction above).
The `|| true` rule keeps its per-shape semantics: rc-observed shapes
omit it (the consumer's rc must be able to fail the check); piped
shapes (`grep -c … | grep -q "^[N-M]$"`) and extraction-leg pipelines
ending in a consumer (`cut -d: -f1`) ride `live_src` but no
`|| true` — the final consumer takes the rc and the empty case is
guarded downstream. Absence pins stay un-ridden in BOTH spellings —
the negated leg (`! grep`) and if-found-then-fail (`if grep …; then
fail`): a commented-out forbidden line SHOULD keep counting there
(bare grep, no `live_src`) — and so are deliberate bare control arms
(the #261 pin's own un-ridden leg). The strict single-target
check-form of that class is `check_absent` (#469,
`tests/unit/lib/harness.sh`) — the RAW fail-on-found sugar carrying
a loud rc >= 2 arm the raw shapes lack: `! grep` and the former
suite-local `grep_absent` (test-container-backend, removed at
adoption) invert grep's error rc to 0 and PASS VACUOUSLY on a
missing operand file, counting it as absent; `check_absent` fails
loud there (a missing file or bad pattern never passes as absent —
the mirror of check_live's missing-file loudness). Adoption wave
#469: 27 sites converted (12 grep_absent call rows -- the removed
definition was the suite's 13th grep_absent line, not a site -- plus
15 single-target `sh -c '! grep …'` negations); the rider lint gates
the strict shape by NAME (rule 4, born gated: the registration-bound
single-positional single-leg sh -c absence form must be
`check_absent` — the payload is split quote-aware and compound
payloads stay out; quote-CONCATENATED payloads (sq-dq-sq, sq-sq, the
dq-opening spelling) are PARSED THROUGH since the #488 shlex port of
the detector (tests/unit/lib/rider_detect.py): shlex assembles the
payload token by construction, so a concat spelling no longer hides
the payload's real legs — a spliced STRICT absence flags (the escape
class the hand-rolled first-segment parser had is closed), a spliced
compound still stays out); multi-file conjunctions,
compound legs, in-payload pipes, literal-path/log/fixture binds and
if-form spellings stay the documented raw shapes and convert on
sight like the counted shape did). A `-r` directory target rides
the same shape (the file operand is the grep target, one operand). A presence pin whose pinned
literal is itself a full-line comment is the recorded INVERSION of
this rule: the strip would delete the pinned bytes and make the pin
unmatchable — such a site (the documented-disposition marker pin
`'#428 disposition'` in `test-install-core.sh`) carries an in-place
annotation naming the inversion instead of the rider (#459 a B3);
the rider lint's rule 2 honors the `# rider-inversion` marker as
that exemption. New inversion sites are a registered exception, not a
free pass: the rider lint asserts the exact marker-mention count
across the suites (lines carrying the marker anywhere; the inversion
tripwire, review a X3 + b B1) -- a new marker fails the lint until the
diff documents the site here.
Full-line strip only (#244 h W6 residual: trailing comments after
live lines still count). Precedent: `test-install-args.sh` (v2 URL,
the canonical shape) and the #261 rider pin in `test-project-paths.sh`;
`test-git-config.sh`'s safe.directory counts strip by a DIFFERENT
idiom (backslash-continuation join + `grep -v` drop): the join is
deliberate hardening so a wrapped call cannot escape the check (both
pinned literals sit on single lines today), the drop keeps commented
examples from counting; for a NEW pin whose literal spans a wrap, join
continuations before stripping — otherwise do not copy the idiom, and
do not refactor the site into the canonical shape.

Line counting versus occurrence counting is a per-pin DECISION, made
explicitly and checked against the constructs that can share a
physical line: `grep -c` counts LINES, so a rogue token glued onto
the sanctioned line, a comma-joined sudoers Defaults list, or a CLI
printing its whole JSON payload on one line (gh's run list: two
completed runs, `grep -c '"status":"completed"'` answers 1 forever)
all defeat it — probed shapes, not hypotheses. Class or absence pins
over joined/normalized views count OCCURRENCES on at least one leg
(`grep -o … | wc -l`) against the sanctioned-line count — a rogue
keep glued onto the sanctioned line then reds 2-vs-1 (PR #733's
env_keep class pin, sabotage-verified) — and counts over single-line
tool output go through `grep -o | wc -l` or a structured query
(`jq 'length'`), never `grep -c` (the pr-00729 CI watcher polled a
threshold `grep -c` could never reach). Absence patterns over such
views are probed against every separator character that can appear
between the anchor and the construct: `^Defaults[^!]*` cannot cross
a `!`, so the merged-negation shape `Defaults !setenv,env_keep += …`
escaped the pin (PR #733 round a B2+C1). Issues #738 and #739 land
this paragraph together — one principle, two incident arms.

## Quoting-aware test machinery (detectors and byte-exact fixtures)

Test machinery that must UNDERSTAND shell quoting — a lint detector
over suite source, a fixture row carrying byte-exact shell payload
bytes — does not hand-roll quote tracking: first-index anchors,
escape folding and splice-segment walks were each their own finding
in the #487 loop (a X1, a X2, b B1, c C2; evidence and the library
pilot order live in #488). The rider-lint detector itself took the
library option (#488's shlex pilot, adopted): rules 2–4's quote
tracking lives in `tests/unit/lib/rider_detect.py` — POSIX
`shlex(punctuation_chars=True)` tokenizes legs and payloads correctly
by construction, the splice/concat escape class closed structurally,
and the suite's arms (plus the spliced-strict row) pin the port. The
sandbox-policy trap-arm analyzer followed (#498, the #496 playbook):
its hand-rolled quote walk — four #287 defect rounds of this class —
is now `tests/unit/lib/trap_detect.py` (rider_detect's two-pass
tokenize with the commenter pass first, arms read as the tokens after
the action word; the receiver regex and the own-call view stayed
faithful ports — the shlex option does not fit them, they feed
structural line views, not token walks); the adoption differential
(old awk vs the port over tests/unit + the probe corpus: byte-identical
rows on the whole corpus, the delta shapes measured on scratch torture
files, none live — review a B3, #516) is the
equivalence record, the suite's probe arms pin the four defect-round
shapes. For
any new parser need, evaluate the library option first (python3
`shlex` — python3 is a required suite
dependency); if awk stays, every quote-handling conjunct gets a
discrimination arm BEFORE the tree sweep runs — the sweep alone
passes vacuously at zero. NEW fixture rows with escaped payload
bytes (`\"\$1\"`) are written single-quoted-with-splices: a
double-quoted printf folds `\$` to `$`, the detector then sees
neither positional spelling and the row flags nowhere — the c C2
follow-up pin was VACUOUSLY green with and without the guard it
pinned. The scope is NEW rows only: the #460/#487 fixture block in
`test-rider-lint.sh` (double-quoted printf rows with per-row
`\\\$`/`\$` escape discipline, every row armed with a 1-hit check)
is a REGISTERED EXCEPTION — do not copy its idiom into new rows.
Every `test … = 0` expectation pin gets its red path EXECUTED once (delete
the guard or the planted row in a sabotage run and observe the red)
— count pins alone stayed green through three rounds' sabotage
candidates.

A PATH stub that must reach the real binary bakes the binary's
ABSOLUTE path at write time: UNQUOTED heredoc delimiter, every `$` in
the stub body escaped (`\$1`, `\$2`, `\$@`), and the real path
expanded into the exec line — the stat-stub idiom in
`tests/unit/test-status.sh`. A QUOTED heredoc leaves the variable
literal: the stub runs as its own `#!/bin/sh` process, the unexported
variable arrives empty, `exec ""` dies rc 126 on the first
reach-through, and a pin asserting a downstream rc can pass from the
WRONG arm — pr-00621 round b B1's markers asserted rc 2 and went green
off the helper's first-probe arm while the `%G` guard they claimed to
pin was never exercised (issue #626; fixed in 3966d1c5 by mirroring
the working idiom). Corollary: inside a quoted heredoc nothing expands
at all — never pre-escape backticks or fences there (issue #624's
body was posted with literal escape sequences this way).

The arm-discrimination duty: a stub-capture restructure ships only
when a
sabotage cycle proves the pin discriminates through the INTENDED arm —
red-on-delete is not enough when an earlier arm can manufacture the
rc; trace which arm produces the rc, or make the marker arm-unique
(#626, the B1 follow-up).

## Fail-loud detector sweeps

The fail-loud detector-sweep pattern — a scan/producer function whose
death must fail the suite, and the pins proving it — exists across
waves (#496 a B1, #498, #519: `_rule2_batch`, `_rule1_batch`,
`trap_scan`, `_docs_collect`, `p10b_scan`, `p10_lane_c_hits`,
`scan`/`sfx_scan`) and lived only in round comments until this section
(issue #523 §1).

- The producer function dies loud: nonzero rc on death, guard message
  on **stderr** — stdout is the data channel. (RM-0146)
- Call sites consume the rc with `if ! producer …; then` (fail/exit) —
  never `|| true`. (RM-0147)
- The death arm is EXECUTED, not inferred: `( producer <dying input> )
  2>&1 >/dev/null` captured, asserting rc ≠ 0 AND the guard message —
  an arm that pins the message only stays green through an rc
  regression (#496 b D3), and the redirection ORDER is load-bearing
  (swap it and the arm goes vacuous, #523 §1). Sabotage cycles follow
  agent/gates.md (secured tree, content-verified restore). (RM-0148)
- The empty-scan-set leg fails loud too: zero scanned files is not a
  clean verdict — `trap_detect`'s "no files given" rc 1 is the
  reference shape. (RM-0149)
- Detector rc semantics are per-tool, and rc diagnostics capture with
  `cmd || rc=$?` BEFORE branching — never read `$?` inside an `if !`
  branch: dash's negation clobbers it (#520 a A1, a death diagnostic
  that always said rc=0). The same rule's assignment shape: a fixture
  run inside a command substitution assigned to a variable returns
  the subshell's rc from the ASSIGNMENT — under a suite's `set -e` a
  failing fixture aborts the suite right there, before the pass/fail
  branch renders any row (every green-side gate blind to it; the
  sabotage cycle's log simply ended, #676; PR #675 round a) — so the
  capture is `_rc=0; _out="$( … )" || _rc=$?`. `grep` rc 1 = no
  match (normal) vs rc ≥ 2 = death; awk rc ≠ 0 = death. (RM-0150)
- An absence assertion over captured output pipes the capture to
  grep's stdin (`printf '%s' "$cap" | grep -q …`), never as a file
  operand: a captured multiline string is an unopenable "filename" —
  grep exits rc 2 and the `!` inverts it into a pass, so the absence
  leg goes green regardless of what the producer printed (PR #670 a
  M3; probed under dash — rc 2 inverted into the vacuous pass, the
  stdin shape discriminates both directions, #672). Channel
  discipline on the same captures: an absence leg observes the
  channel the producer renders on — a combined stdout+stderr capture
  can carry raw operand bytes from TOOL diagnostics (grep's
  "No such file" error echoes the operand), not from the rows under
  test; capture stderr separately when a leg asserts byte
  cleanliness. (RM-0187)
- The channel is a property of the OBSERVED emitter, not of the
  capture convention: shipped runners' diagnostics go to stderr (the
  capture shape above), but `tests/e2e/lib.sh`'s FAIL and WARNING
  lines are console progress lines — plain `echo`, stdout — so a
  drive asserting one captures stdout and greps there; an empty
  capture file with rc and file state already green is the tell of
  the wrong channel (the #601 chmod-failure drive asserted its FAIL
  line from an empty stderr capture, PR #628, #631). (RM-0181)

## Named-cause failure guards (shipped runners)

Shipped code runs where `$TMPDIR` can be unset, read-only or full — a
bare `$(mktemp)` death aborts with the shell's generic message and the
user cannot tell what stopped. Every shipped fetcher already guards
its mktemp with a named cause (the `#364` class): the SHA256SUMS
fetches in `files/install.sh` and `management/update.sh`, and the
get.docker.com fetch in `bin/setup-container-backend`. This section
prescribes the standard for new and touched shipped code; the tree
does not hold it universally yet — existing unguarded receivers (the
`sh/ddev-migrate.sh` bare `|| return 1` shape) are the class debt
named in the rule below.

- A `mktemp` receiver in shipped code carries a named-cause guard:
  `tmp=$(mktemp) || { echo "… mktemp failed (is \$TMPDIR writable?) —
  <what cannot proceed now>" >&2; return 1; }` — the message names the
  consequence for the user, never the bare call. The scope boundary
  rides the same rule: e2e/test scaffolding keeps its lighter sibling
  shape (PR #532 round a S1, disposition deliberately-not-done —
  sanctioned in writing here; the shipped-code class work stays with
  issues #431/#376). (RM-0155)

## Unit-suite path variables (entry scripts and their phase libs)

Suites that reference a management entry script together with its
sourced phase lib (the #346 waves: `status.sh`/`status-core.sh`,
`update.sh`/`update-core.sh`, `install.sh`/`install-core.sh`,
`uninstall.sh`/`uninstall-core.sh`)
name the two path variables after the entry script:
`STATUS`/`STATUS_CORE`, `UPDATE`/`UPDATE_CORE`, `INSTALL`/`INSTALL_CORE`,
`UNINSTALL`/`UNINSTALL_CORE`. No bare `CORE`
and no per-suite abbreviations (`SCORE`, `UCORE`): suites grow second
and third lib references over time, and a grep for one lib's pins must
find every referencing suite under one variable name. (The shipped
resolver variables follow the same shape — `UPDATE_CORE` in
management/update.sh, `STATUS_CORE` in management/status.sh.) A suite
whose own subject IS the lib keeps the plain `LIB` idiom
(test-status-core.sh, test-update-core.sh).

## Pin-cost budget (unit suites)

A pin whose fixture would exceed ~30 lines for a LOW/INFO-severity
behavior is NOT shipped: the behavior is dispositioned **deliberately
not done (accepted residual)** in the round comment's dispositions
table instead, with the budget breach named. Adopted from issue #303;
origin: #262 P4 / §11e (the PR #244 retrospective). §11e is the
canonical breach: ~80 lines of FIFO + setsid + drain-marker +
SIGINT-disposition-across-exec engineering to pin one cosmetic
except-arm of a progress counter — whose own comments record that the
pin initially "could not fire AT ALL" and that a dash-vs-bash `kill`
difference broke it silently. In that PR the fixture choreography for
LOW-severity behavior was ~450 of 955 net-new test lines at a
lines-per-assertion ratio of ~21, where historical baseline pins in
the same suite are one-liners — pin hardening had become its own
defect surface, reviewed by waves f/g over the PR's own pins.

- Scope: severities LOW and INFO only. MED/HIGH findings are never
  budget-exempted — their pins cost what the defect deserves.
- The budget declines the PIN, not the finding: the finding is still
  reported and dispositioned; only the fixture is declined.
- The bound applies wherever pins are proposed — feature waves and
  reviewer rounds alike: a reviewer proposing an over-budget LOW/INFO
  pin gets the accepted-residual disposition with this rule cited,
  not the fixture.
- An issue or fix shape that explicitly prescribes the fixture class
  overrides the bound for that pin: the prescription names its model,
  and the breach is disclosed in the wave's records (issue #511's
  F30-class pins — a ~50-line fake-curl fixture after its ~70-line
  model — rode PR #532 on exactly this override).

## Test sandbox (unit suites)

Moved to [tests/AGENTS.md](../tests/AGENTS.md) (issue #768): the
section auto-loads when an agent reads or lists files under `tests/`,
so the policy rides the path trigger instead of this always-on page —
same text, no compression. The enforcing suite stays
`tests/unit/test-sandbox-policy.sh`; the rule metas moved with the
section (their `rule:` back-refs point at the new home).


## Never-write pins (unit suites)

A pin proving a staged run never wrote a real-tree file (the INDEX
parity leg's kill-window residual, #572 T2) — both rules born in that
suite's own wave and review round (issue #616):

- A never-write pin asserts mtime, not bytes: a staged regeneration of
  identical content is byte-invisible, so `cmp` stays green over the
  exact violation it exists to catch. Copy the target to a marker
  before the run and arm the red with `[ "$TARGET" -nt "$MARKER" ]` —
  the copy stamps the marker, and `-nt` detects the in-place write
  under bash and dash alike, sub-second (probed 2026-11-18, #616).
  (RM-0177)
- The pin's red path never repairs the real tree: a failure handler
  that restores incoming bytes (`cp "$TMP.in" "$INDEX"`) re-opens the
  write window the pin guards. Fail with the drift visible — the suite
  exits 1 either way, and the tree keeps the evidence for the
  operator. (RM-0178)

## E2E arm authoring (git-writing arms)

An e2e arm's default vocabulary is checkout/add/reset — git commands
that create no commits and need no committer identity (the arms'
whole vocabulary before the #678 wave). Arms that build diverged
topologies, conflict states or merges WRITE git history, and the e2e
container users carry no global git identity by design. Four authoring
traps from the #678 fix wave — three of them reddening two full e2e
runs before a container repro isolated the causes, none of them
heal-behavior bugs (#686, PR #684):

- Any e2e arm whose git command CREATES COMMITS (`git commit`,
  `merge`, `cherry-pick`, `rebase` conclude, `am`) passes the
  committer identity inline — `git -c user.email=… -c user.name=…
  <cmd>` — because the container users carry no global identity (a
  repo-local `git config` identity satisfies commits too —
  tests/e2e/fixtures/make-bare-origin.sh — but inline `-c` keeps
  an arm self-contained): the refusal is rc 128
  ("Committer identity unknown") with a stderr a blanket
  `>/dev/null 2>&1` eats, and the arm then fails downstream with
  zero evidence in the log (probed 2026-11-20; #686 item 1,
  PR #684). (RM-0190)
- Never silence a git command whose FAILURE MODE the arm observes
  beyond the expected rc: redirect to a log file or scope the
  `|| true` to the expected conflict rc — a blanket
  `>/dev/null 2>&1` written to swallow an expected conflict also
  swallows any unexpected death, leaving three red arms and no
  stderr to diagnose (#686 item 1, PR #684). (RM-0191)
- Recreate pruned directories after every `checkout -B` in topology
  construction — `mkdir -p <dir>` immediately after the switch: git
  removes a worktree directory that only holds the OTHER branch's
  tracked files, and the arm's next write into it dies "Directory
  nonexistent" (probed 2026-11-20; hit twice in one wave —
  measurement harness and e2e arms; #686 item 2, PR #684). (RM-0192)
- Fixture state constrains every later git-writing arm in the same
  repo: an arm that leaves files STAGED makes a later merge refuse
  ("would be overwritten by merge") wherever the merge touches the
  same path — end staging arms with the unstaging reset
  (`git reset`) or plan the cleanup explicitly; the refusal needs
  path overlap (a staged NEW file unrelated to the merge target
  passes — probed 2026-11-20; #686 item 3, PR #684). (RM-0193)

## Referencing review findings

Every review restarts its finding IDs at S1/C1 (per case), so a bare
ID is ambiguous across cases. Always qualify the ID — two citation
eras, one resolution rule per era:

- **Live cases (PR-native process, since 2026-10-26):** `(#291 a S1)`
  — PR number, round letter, finding ID. The PR timeline is the
  record: the citation resolves to the round comment on the birth-PR
  (comment permalink, or `gh api repos/<org>/<repo>/issues/<PR>/comments`
  — the `opk-review` markers make the rounds grep-able). Fix commits
  qualify their citations the same way. (RM-0018)
- **Legacy corpus (stems 0.0.38–0.0.49):** `(0.0.38 S1)`,
  `(0.0.39a C1)` — the stem stays the qualifier. Resolve via
  [legacy-index.md](../internal/reviews/legacy-index.md), then read
  the file at the tag. (RM-0019)

Grep-able by design. Corpus-era citations of both shapes (new-key
`(#176 a W1)` from the 2026-10 restructure era included) resolve
against the tag `review-corpus` (issue #290):
`git grep "#176 a W1" review-corpus -- internal/reviews/`,
`git grep "0.0.38 S1" review-corpus -- internal/reviews/`. The case
map is the INDEX at the tag
(`git show review-corpus:internal/reviews/INDEX.md`); naming,
formats, and the archive mechanics live in the
[review README](../internal/reviews/README.md).

## Referencing house rules (RM keys)

Citations in new text name the file and section, never the bare ID:

- Every RM key appears at exactly three sites in the audit's closed
  world: as the trailing `(RM-NNNN)` of its rule unit, as the `id:`
  line of its meta file, and as its generated row in the rule-meta
  INDEX — new text (files, skills, comments, cross-references)
  cites a rule by file and section, never by its ID, because any
  fourth site breaks the rules audit's invariant that searching an ID
  only ever hits genuine sites. The closed world is what the no-fake
  findings pin measures (tests/unit/test-rules-meta.sh, pin 10): the
  frozen reviews corpus (archived at tag `review-corpus`) and its
  generated indexes sit outside the count; of the living files under
  `internal/reviews/`, the README is covered while the
  machine-generated legacy-index is exempt. (RM-0116)
- Citation-FIXING waves are the prime fourth-site authors: rewording a
  comment that cites a rule invites writing the bare ID into the new
  text (a #606 a Q5 fix did exactly that; the rules-meta pin caught it
  at gate time, one cycle paid). Grep the ID tree-wide before
  committing to the reword, and cite by file + section + item in the
  replacement text. (RM-0180)

## Referencing reflection topics

Reflection topics live in a second tracker since the docs-loop cutover
(the implementation PR of issue #755):
`steffenmaechtel/opk-agent-feedback`. Issue numbers are per repository,
so a number alone no longer says which tracker it means.

- A feedback issue is cited by its repository-qualified short form,
  `opk-agent-feedback#N`, never a bare `#N`: a bare number resolves
  inside THIS repository and silently points at an unrelated issue
  here, and GitHub autolinks nothing inside repository files — the
  form is a grep key, not a link. Text written before the cutover
  keeps its bare numbers: they mean this repository's own reflection
  archive. (RM-0217)

## Referencing, not restating

Content (a contract, question, label list, command shape) should
live in exactly ONE owning document; every other site should name it
— skill ID, file path, section link — and stop there. Copying
content into a second document turns a future change into an N-place
update, and each missed place is a silent contradiction. A pointer
sentence ("what the skill does lives in the skill alone") stays true
while the referenced content is freely editable with no co-moves.
This applies to newly written and edited content; existing
duplication is retired in passing when a site is touched anyway —
no mass pass. (Maintainer directive 2026-11-15, the opk-improve-docs
wave — its first draft restated one skill's contract in four
documents.)

A page that references a skill checks its OPENING paragraph against
the skill's own file before committing — first drafts drift toward
restating the contract (2 instances, 2026-11-15: the review-concept
meta log's first draft restated the skill's question and contract;
docs-loop.md's opening copied the opk-improve-docs contract facts
until round a B2, fixed in 6e13493b).

## Standing prose: history, not rosters

- Standing text (agent/, docs/, skills) that names the members of a
  GROWING set enumerates them as history — "the first three were
  #541–#543" — never as an exhaustive roster, and carries no unscoped
  count of the set: the next member silently falsifies both. A
  roster's job belongs to a query mechanism (a label, a search); the
  prose POINTS at the mechanism instead of duplicating its current
  result. (RM-0157)
- A capability claim over a set — "every reader/consumer/script does
  X" — is a roster claim even with no list in parens: it duplicates
  the current result of a query over a growing set, and the next
  member silently falsifies it (a docs sentence claiming `#` lines
  are "ignored by every reader" while a reader the wave never
  touched still printed them — the wrapper's refusal list, PR #670 a
  L1). Grep the whole set before writing the sentence — and again at
  review — or scope the claim to what the wave verified ("the
  readers the wave touched skip …"); the mechanism-pointer form above
  (name the query, not the result) applies verbatim. (RM-0188)

## Wave-record claims: classes, not counts

- An exhaustive claim in a wave record — a PR body's "the two sites",
  "the only point where", "every probe of X around the copy", or a
  shipped comment's count over sites — either enumerates by OPEN
  CLASS over the code's real taxonomy or cites the grep that derives
  it; a bare count or an "only/every + narrow scope" phrasing is
  review debt that the next round's finer scope refutes — every
  count-based and scope-narrowed rewording of one loop's claims fell
  this way, while the class-scoped enumeration survived every round
  (the update path's root-exec comment, unchanged since: every probe
  of the opencode binary enumerated by trust class — the run's fresh
  candidate, the freshly deployed binary, the OLD deployed binary,
  install-side; sh/update-core.sh, PR #680 rounds a–c, #683).
  Standing prose carries the same discipline under "Standing prose:
  history, not rosters" above; tracker-state claims in PR bodies are
  the round-comment contract's own rule (review-concept.md). (RM-0189)

## Docs code blocks (paste-safe commands)

- A docs code block whose prose promises gating (check-then-run
  recipes) is ONE compound command — a trailing `&&` per line, the
  operator itself the continuation — never sequential plain lines:
  pasted lines run in an interactive shell without `set -e`, so a
  FAILED check prints its error and the next line executes anyway;
  the check was a diagnosis, not a gate. "Executable as printed"
  verified the happy path only — three review axes passed the plain
  3-liner, the maintainer caught it (fixed 0f68f4d1, issue #604).
  (RM-0171)
- A load-bearing line shape a wave shares across docs AND script AND
  pins AND fixtures (the echo-hash install line) records the grep
  that enumerates the sites: the pins guard partial drift by design,
  and a future shape change is a coordinated move over that list, not
  a per-site rediscovery (pr-00600 A8/D1). (RM-0174)

## Rule-file markdown structure

- Markdown structure inside rule bullets — an indented fence, an
  indented table — is invisible to the rules-audit unit parser (its
  fence regex anchors at column 0). Indented-fence pairing has a
  structural gate since #542 (tests/unit/test-docs.sh — the #526
  deleted-opening shape reds); damage that gate cannot see —
  indented tables, fence content, deeper fence-shape drift — still
  owes a manual render/balance check in the diff review. (RM-0152)

## Language

All shipped content (scripts, docs, prompts, messages) is English — see
`AGENTS.md`. American English spelling.
