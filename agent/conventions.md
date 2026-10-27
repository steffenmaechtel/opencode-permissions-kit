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

## Source-counting pins (unit suites)

Any unit-test pin that COUNTS a literal in a shipped or repo-internal
source file (`grep -c … "$INSTALL"`, counts over extracted blocks or
`grep -n` extraction legs) counts behind a comment-strip rider —
`sed 's/^[[:space:]]*#.*$//' "$FILE" | grep -c … || true` — so a
commented-out construct stops counting (the survivor trap, #261/#244 g
W1). Full-line strip only (#244 h W6 residual: trailing comments after
live lines still count). Piped shapes (`grep -c … | grep -q "^[N-M]$"`)
carry the rider but no `|| true`: the rc must come from the final
`grep -q` so the check can fail. Precedent: `test-install-args.sh` (v2
URL), `test-git-config.sh` (safe.directory), the #261 rider pin in
`test-project-paths.sh`.

## Test sandbox (unit suites)

Unit suites run on contributor and CI hosts, not in containers — they
must never create, delete or re-permission anything outside their own
scratch space, and never carry real-tree path literals at all. Rules
(finding history: 0.0.42e C1, executed as a live incident on an external
review host):

- Operate only on the suite's scratch (`$WORK`, `mktemp`) and the
  sanctioned temp prefixes `/tmp`, `/var/tmp` (plus `/dev/null`). (RM-0014)
- Never touch real project or system trees — `/var/www/vhosts`, `/home`,
  `/srv`, `/etc`, ... — **not in setup, not in teardown**: a cleanup
  `rm -rf` on a fixed host path deletes real data wherever the path
  happens to exist. (RM-0015)
- Fixture data is written **sandboxed at the source** (heredocs,
  registries, configs carry `/var/tmp/...` paths directly). Inert
  real-tree literals behind a later rewrite are forbidden too — they are
  one broken rewrite away from live (the migrate fixtures carried them
  for months behind a `sed` that a wave then dropped; maintainer
  directive 2026-10-04). (RM-0016)
- An `rm` — any flag form (`rm`, `rm -f`, `rm -r`, `rm -rf`, `rm -fr`,
  …), any operand position — on a variable **with a literal suffix**
  (`rm -rf "$WORK/sub"`, `rm -f "$WORK/mark"`, `rm -rf "${WORK}/sub"`,
  `rm -rf "$WORK"/sub`, `rm -rf $WORK/sub` — every spelling degenerates
  the same way on an empty variable) must guard the variable with `:?`
  (`rm -rf "${WORK:?}/sub"`): an empty or unset variable degenerates the
  operand to a fixed absolute path (`/sub`) instead of the harmless
  empty-operand no-op of the pure-variable form.
  Pure-variable operands (`rm -f "$CONF"`) are deliberately exempt.
  Destructive permission verbs (`chmod`/`chown`/... with `"$VAR/suffix"`)
  stay unguarded by design: fixture setup uses them heavily, they are
  not deletion, and a degenerate target fails on permissions for the
  non-root suite user. (RM-0003)
- Code extracted from shipped scripts and eval'd or run by a test
  executes under a **controlled PATH**, never the inherited host PATH:
  any `command -v` inside the extracted block must not see tools that
  merely happen to be installed on the contributor's machine. The
  0.0.48 release blocker: the status verdict matrix evals a block whose
  `command -v openchamber` found the maintainer's nvm-installed
  OpenChamber, flipping the "without OpenChamber" cases red on local
  `make release` while CI (no OpenChamber) stayed green — the
  0.0.46a F2 environment-dependence class. Build a scratch bin with
  symlinks to the block's few externals instead of rewriting the probe
  lines away — the real probe keeps executing (0.0.47c C1 direction). (RM-0017)

Enforced by `tests/unit/test-sandbox-policy.sh`, three checks over every
unit suite (backslash-continued commands are joined first; full-comment
lines are skipped):

1. **Mutation check** — a mutating verb (`rm`, `mkdir`, `chown`,
   `setfacl`, ...) whose operand is a literal absolute path outside the
   sanctioned prefixes fails. Source-to-destination verbs (`cp`, `mv`,
   `ln`, ...) flag only the destination; `sed` only with `-i`.
   Variables are exempt — what they hold is the review's job. (RM-0042)
2. **Real-tree ratchet** — any path-shaped literal starting with a
   real-tree prefix (`/var/www/vhosts`, `/srv/other/outside`) fails,
   quoted or not, in fixture strings as much as in commands.
   Policy-INPUT classes — values handed to
   screening/parsing functions or parse-only argument fixtures, never
   executed as paths — are allowlisted in the suite with reasons.
   Unit-suite-scoped: e2e scripts legitimately name container paths
   (/var/www/vhosts fixtures), so they are not in this check's scope.
   (RM-0043)
3. **rm suffix guard** — any `rm` invocation (flag order and operand
   position aware, statement-scoped) on a variable with a literal suffix
   must carry the `:?` empty-variable guard — quoted unbraced
   (`"$V/x"`), quoted braced (`"${V}/x"`), slash-outside-the-quotes
   (`"$V"/x`) and unquoted (`$V/x`) spellings alike; pure-variable
   operands are exempt (an empty operand is a verified rm no-op — the
   dangerous shape is the suffix). Scope: the unit suites AND the e2e
   helper scripts (`tests/e2e/**/*.sh`). The same `:?` standard
   applies to shipped code's `rm` var+suffix sites, root context
   included: new sites must not regress it (convention, enforced by
   review — the unit guard's scan deliberately stops at tests/). (RM-0044)

The suite self-probes all three checks (continuation-split `rm`, inert
and quoted and redirect-glued literals, the unguarded suffix shapes —
flag orders, bare `rm`, multi-operand — vs the guarded ones, a clean
sandboxed control) so the guard itself cannot rot silently.

## Referencing review findings

Every review restarts its finding IDs at S1/C1, so a bare ID is ambiguous
across cases. Always qualify the ID — two citation eras:

- **New cases (birth-PR key, since the 2026-10 restructure):**
  `(#176 a W1)` — PR number, snapshot letter, finding ID. The PR number
  is allocated by GitHub when the maintainer opens the birth-PR, so
  parallel features can never collide. (RM-0018)
- **Legacy corpus (stems 0.0.38–0.0.49):** `(0.0.38 S1)`,
  `(0.0.39a C1)` — the stem stays the qualifier. Resolve via
  [legacy-index.md](../internal/reviews/legacy-index.md) or grep. (RM-0019)

Grep-able by design: `grep -rn "#176 a W1"`, `grep -rn "0.0.38 S1"`.
The case map is the generated
[INDEX](../internal/reviews/INDEX.md); naming, formats, and the
mechanics live in the [review README](../internal/reviews/README.md).

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
  generated review indexes and the frozen reviews corpus sit outside
  the count; living files under `internal/reviews/` —
  `internal/reviews/README.md` and its living peers — do not.
  (RM-0116)

## Language

All shipped content (scripts, docs, prompts, messages) is English — see
`AGENTS.md`. American English spelling.
