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
| GitHub advisory feed → `gh` argv/query | `scan_advisory_valid` — charset + vocabulary + anchored ranges | `scripts/security-scan.sh` |
| version resolution (GitHub/npm) | strict `case 1.*`/`2.*`, loud abort outside the shape | `management/update.sh` (`resolve_latest_opencode_version`) |
| version probes | strict `grep -oE` extract; empty means unknown, never a guess | wrapper, `management/status.sh` |
| exact id comparison | `grep -qxF` (fixed string, whole line) | `sh/advisories.sh` callers, scan dedup |

## Language

All shipped content (scripts, docs, prompts, messages) is English — see
`AGENTS.md`. American English spelling.
