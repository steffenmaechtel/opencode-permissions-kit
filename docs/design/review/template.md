# Code Review — opencode permissions kit <VERSION>[<variant>]

> Copy this file for a new review snapshot; delete this paragraph and every
> `<placeholder>`. Naming: `YYYY-MM-DD-v<VERSION>.md`; several snapshots on
> the same day/version get variant suffixes `-a`, `-b`, … (sorted: the first
> review has no suffix or `-a`). Add the `Resolution:` block only once a
> resolution file exists — the snapshot itself is never edited afterwards
> (see README.md rules).

- **Date:** YYYY-MM-DD
- **Version reviewed:** `X.Y.Z` (branch `<branch>`, working tree clean, commit `<sha>`)
- **Model used:** <model name and the agent/CLI that ran it>
- **Scope:** shipped code (`files/` incl. lib `sh/`, `management/`, `bin/`, `py/`, `tui/`, `templates/`), `scripts/`, `Makefile`, `.github/workflows/`; state explicitly what was read fully vs. targeted, and what was excluded.
- **Verification at review time:** <the suites that ran and their result, e.g. `make test`, `make lint`, `make check-version` — plus, explicitly, what did NOT run (e.g. the e2e suites).>

Method note: <how the review was produced — single-agent or parallel
subagents, independent of / compared against other snapshots of the same
version, and that every finding was re-verified against the code before
inclusion. Aborted runs: what was recovered and how.>

---

<!-- Finding ID scheme (IDs are stable and referenced from commits and the
     resolution — never renumber): S# = security, C# = correctness/bugs,
     D# = docs/consistency, Q# = quality (minor). Sections that have no
     findings are dropped.
     Reference rule (conventions.md): outside this snapshot, IDs always
     carry the review stem — `(0.0.39b C1)`, never bare `(C1)` — because
     every review restarts at S1/C1. In-code comments, commit messages,
     and the resolution use the qualified form.
     Table discipline: escape every literal `|` inside a cell as `\|`;
     cite file:line for every finding; severity in bold only for
     MEDIUM and above. -->

## Security

| # | Sev | File(s) | Finding |
|---|-----|---------|---------|
| S1 | **<SEVERITY>** | `path/to/file.sh:<lines>` | <What is wrong, why it matters, and a concrete fix.> |

**Verified clean (no findings):** <optional — security-relevant areas that
were checked and found solid; keeps later reviews from re-auditing blind.>

---

## Code quality — bugs & robustness

| # | Sev | File(s) | Finding |
|---|-----|---------|---------|
| C1 | <SEVERITY> | `path/to/file.sh:<lines>` | <Finding.> |

---

## Docs / consistency (drop when empty)

| # | Sev | File(s) | Finding |
|---|-----|---------|---------|
| D1 | <SEVERITY> | `path/to/file:<lines>` | <Finding.> |

---

## Quality (minor) (drop when empty)

| # | File(s) | Finding |
|---|---------|---------|
| Q1 | `path/to/file:<lines>` | <Finding.> |

---

## Priority fix order

1. **S1** — <why this first>.
2. **C1** — <…>.

---

## Retracted/ghost findings (only when applicable)

| # | Original suspicion | Why it was dropped |
|---|--------------------|--------------------|
| — | <what an earlier pass believed> | <what the code actually shows / why it was retracted.> |
