# Conventions

> Status: **BINDING** — this is the living style guide for shipped code, not
> a historical design record. Change it via PR when a convention evolves;
> update the affected code in the same PR.

## Interactive prompts (y/n)

Every yes/no question in shipped scripts follows one pattern:

```
[?] Proceed with uninstall? [y/N]
                        ^^^^ default = capital letter
```

- **Format:** `[?] <question> [Y/n]` or `[?] <question> [y/N]` — square
  brackets, the **default as the capital letter**.
- **Enter accepts the default** (empty answer = default).
- Accepted input: `y`, `yes`, `n`, `no` — case-insensitive. Unknown input
  falls back to the default.
- **Default choice:** `n` for anything that changes the system (remove,
  provision, proceed with destructive steps), `y` only where "no" is the
  surprising/riskier answer (e.g. the recommended audit-log deletion during
  uninstall).
- Don't invent alternatives (`(yes/no)`, `Y/N`, `[yes|no]` …). If a choice
  needs more than yes/no, use a numbered/keyed menu (`ui_menu`).

Implementation:

| Context | Helper |
|---|---|
| Scripts that source `ui.sh` | `ui_confirm "Question?" <y\|n>` |
| install.sh menus | `ui_menu` (keys like `1`/`C`/`A`/`X`, default highlighted) |
| uninstall.sh (standalone, no ui.sh) | local `prompt_yn` (same display rules) |
| wrapper (standalone POSIX sh) | inline `case` on the lowercased answer |

Free-text questions (`ui_ask`) show `[default] >` — different shape on
purpose, they are not confirmations.

## Script output style

See `docs/_archive/design/ux-improvement.md` (decisions, archived):
labeled lines `info`/`success`/`warn`/`error` via `ui.sh`, slim banner,
Unicode symbols with `UI_ASCII=1` fallback, `NO_COLOR` and non-tty
honored.

File lists in code (fetch/deploy lists such as `KIT_FILES`, install.sh's
fetch list, and the `lib_deploy` manifest): **one file per line**,
backslash-continued. Packed multi-name lines make diffs unreadable;
consumers and tests compare word-wise, so the layout is pure
convention — keep it when adding entries.

## Shell security (untrusted input)

External data — HTTP feeds, files someone else wrote, anything parsed
from outside the script — is untrusted. It may influence shell *data*,
never shell *structure*:

1. **Quoting.** Every expansion of external data is double-quoted. No
   `eval`, no `sh -c` with interpolated values, no unquoted `$var`
   (word splitting and globbing are injection surfaces).
2. **`printf '%s'` style.** External values are arguments to a fixed
   format string, never the format itself — `printf "$EXT"` interprets
   `%` and `\` sequences from the data.
3. **Free text flows through files, not argv.** Long untrusted content
   (issue bodies, messages) goes via a temp file (`--body-file`), never
   through argv, where a crafted value could steer a flag or a query.
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
     metacharacter interpretation, no query steering
5. **Fail loud vs. fail open.** Maintainer automation skips malformed
   data with a warning and exits non-zero (a red CI run is the
   visibility). The wrapper's hot path fails open instead — an
   unavailable check must never keep a session from starting.
6. **Prove it in tests.** Payload attempts (command substitution,
   qualifier smuggling, column shifts) are unit-tested, with a
   marker-file proof that nothing ever executed.

Patterns already in this repo:

| Context | Pattern | Code |
|---|---|---|
| GitHub advisory feed → `gh` argv/query | `scan_advisory_valid` — charset + vocabulary + anchored ranges | `scripts/advisory-watch.sh` |
| version resolution (GitHub/npm) | strict `case 1.*`/`2.*`, loud abort outside the shape | `management/update.sh` (`resolve_latest_opencode_version`) |
| version probes | strict `grep -oE` extract; empty means unknown, never a guess | wrapper, `management/status.sh` |
| exact id comparison | `grep -qxF` (fixed string, whole line) | `sh/advisories.sh` callers, scan dedup |

## Test sandbox (unit suites)

Unit suites run on contributor and CI hosts, not in containers — they
must never create, delete or re-permission anything outside their own
scratch space, and never carry real-tree path literals at all. Rules
(finding history: 0.0.42e C1, executed as a live incident on an external
review host):

- Operate only on the suite's scratch (`$WORK`, `mktemp`) and the
  sanctioned temp prefixes `/tmp`, `/var/tmp` (plus `/dev/null`).
- Never touch real project or system trees — `/var/www/vhosts`, `/home`,
  `/srv`, `/etc`, ... — **not in setup, not in teardown**: a cleanup
  `rm -rf` on a fixed host path deletes real data wherever the path
  happens to exist.
- Fixture data is written **sandboxed at the source** (heredocs,
  registries, configs carry `/var/tmp/...` paths directly). Inert
  real-tree literals behind a later rewrite are forbidden too — they are
  one broken rewrite away from live (the migrate fixtures carried them
  for months behind a `sed` that a wave then dropped; maintainer
  directive 2026-10-04).
- An `rm` — any flag form (`rm`, `rm -f`, `rm -r`, `rm -rf`, `rm -fr`,
  …), any operand position — on a variable **with a literal suffix**
  (`rm -rf "$WORK/sub"`, `rm -f "$WORK/mark"`, `rm -rf "${WORK}/sub"`,
  `rm -rf "$WORK"/sub`, `rm -rf $WORK/sub` — every spelling degenerates
  the same way on an empty variable) must guard the variable with `:?`
  (`rm -rf "${WORK:?}/sub"`): an empty or unset variable degenerates the
  operand to a fixed absolute path (`/sub`) instead of the harmless
  empty-operand no-op of the pure-variable form (audit follow-up to
  0.0.42e C1, maintainer directive 2026-10-06; all suffix spellings
  enforced since 0.0.45c C3).
  Pure-variable operands (`rm -f "$CONF"`) are deliberately exempt.
  Destructive permission verbs (`chmod`/`chown`/... with `"$VAR/suffix"`)
  stay unguarded by design: fixture setup uses them heavily, they are
  not deletion, and a degenerate target fails on permissions for the
  non-root suite user.

Enforced by `tests/unit/test-sandbox-policy.sh`, three checks over every
unit suite (backslash-continued commands are joined first; full-comment
lines are skipped):

1. **Mutation check** — a mutating verb (`rm`, `mkdir`, `chown`,
   `setfacl`, ...) whose operand is a literal absolute path outside the
   sanctioned prefixes fails. Source-to-destination verbs (`cp`, `mv`,
   `ln`, ...) flag only the destination; `sed` only with `-i`.
   Variables are exempt — what they hold is the review's job.
2. **Real-tree ratchet** — any path-shaped literal starting with a
   real-tree prefix (`/var/www/vhosts`, `/srv/other/outside`) fails,
   quoted or not, in fixture strings as much as in commands
   (0.0.42g C2). Policy-INPUT classes — values handed to
   screening/parsing functions or parse-only argument fixtures, never
   executed as paths — are allowlisted in the suite with reasons.
   Unit-suite-scoped: e2e scripts legitimately name container paths
   (/var/www/vhosts fixtures), so they are not in this check's scope.
3. **rm suffix guard** — any `rm` invocation (flag order and operand
   position aware, statement-scoped) on a variable with a literal suffix
   must carry the `:?` empty-variable guard — quoted unbraced
   (`"$V/x"`), quoted braced (`"${V}/x"`), slash-outside-the-quotes
   (`"$V"/x`) and unquoted (`$V/x`) spellings alike (2026-10-06;
   all spellings enforced since 0.0.45c C3); pure-variable operands are
   exempt (an empty operand is a verified rm no-op — the dangerous
   shape is the suffix). Scope since 0.0.45d (0.0.45b C1): the unit
   suites AND the e2e helper scripts (`tests/e2e/**/*.sh` — the three
   host-side sites that carried no guard are swept with this change).
   The same `:?` standard applies to shipped code's `rm` var+suffix
   sites, root context included (0.0.45b C2): the shipped tree is
   swept clean with this change, and new sites must not regress it
   (convention, enforced by review — the unit guard's scan deliberately
   stops at tests/).

The suite self-probes all three checks (continuation-split `rm`, inert
and quoted and redirect-glued literals, the unguarded suffix shapes —
flag orders, bare `rm`, multi-operand — vs the guarded ones, a clean
sandboxed control) so the guard itself cannot rot silently.

## Referencing review findings

Every review restarts its finding IDs at S1/C1, so a bare ID is ambiguous
across reviews (v0.0.38 and 0.0.39a both have an `S1`). In-code comments,
commit messages, and resolutions therefore always qualify the ID with the
review stem (the snapshot's file-name stem without the date):

- `(0.0.38 S1)` — v0.0.38 review, security finding 1
- `(0.0.39a C1)` / `(0.0.39b S1)` — same-day variant snapshots

Grep-able by design: `grep -rn "0.0.38 S1"`. The
[review index](review/README.md#index) maps stems to snapshots, ID ranges,
and resolutions; the snapshot-format rule (external verbatim embedding
since 0.0.45d) lives in the [review README](review/README.md).

## Language

All shipped content (scripts, docs, prompts, messages) is English — see
`AGENTS.md`. American English spelling.
