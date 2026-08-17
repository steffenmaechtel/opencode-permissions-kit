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

See `docs/design/ux-improvement.md` (decisions): labeled lines
`info`/`success`/`warn`/`error` via `ui.sh`, slim banner, Unicode symbols
with `UI_ASCII=1` fallback, `NO_COLOR` and non-tty honored.

## Language

All shipped content (scripts, docs, prompts, messages) is English — see
`AGENTS.md`. American English spelling.
