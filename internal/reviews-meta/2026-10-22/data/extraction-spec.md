# Meta-review extraction spec — run 2026-10-22

Purpose: you are one of several parallel extraction agents. Together we
analyze all code-review snapshots under `internal/reviews/` of the
opencode permissions kit. Your job: read your assigned review files
COMPLETELY and convert every *defect finding* they contain into
structured JSON. A parent agent will aggregate your batch with the
others into error-class statistics and recurrence analysis.

**Read only your assigned files** (plus this spec). Do not explore the
repo code — the findings are self-contained. Do not modify anything
except writing your batch JSON file.

## Background (1 paragraph)

The repo is a shell-based kit ("opencode permissions kit") that runs
opencode as its own Linux user against a rootless container backend.
Each review snapshot is either a *full-scope* review of a version tip or
a *wave/micro review* of a fix or feature wave. The corpus spans two
citation eras: legacy stems (`0.0.47a` … `0.0.49d`, house format, files
under the birth-PR case folders pr-00156/pr-00160/pr-00171) and
PR-keyed cases since the 2026-10 restructure (`pr-00179` … `pr-00222`,
each snapshot a `review-<letter>.md` with a `review-meta` header).
Snapshot finding IDs use several schemes over time (`S#/C#/D#/Q#`, later
`F#/W#/V#/E#/G#`); severities are HIGH / MED(IUM) / LOW / INFO (plus Q =
question). Resolutions disposition every finding (implemented /
implemented differently / deliberately not done). Reviews frequently
cross-reference earlier findings as recurring "classes" (e.g. "the
0.0.42d class", "the L5/0.0.39h F2 class", `(#176 a W1)`) — capture
those references, they are the core input for the recurrence analysis.

## Batch assignments (this run)

| Batch | Case folders (under `internal/reviews/`) | Era / snapshots |
|---|---|---|
| b1 | `0/0/1/5/pr-00156` (stem 0.0.47), `0/0/1/6/pr-00160` (stem 0.0.48) | legacy, a–c and a–e |
| b2 | `0/0/1/7/pr-00171` (stem 0.0.49), `0/0/1/7/pr-00179` | legacy a–d; new-era a |
| b3 | `0/0/1/8/pr-00189`, `0/0/1/9/pr-00196` | new-era, a–c each |
| b4 | `0/0/1/9/pr-00198`, `0/0/1/9/pr-00199` | new-era, a–b each |
| b5 | `0/0/2/0/pr-00200`, `0/0/2/0/pr-00202` | new-era, a–b and a–e |
| b6 | `0/0/2/0/pr-00208`, `0/0/2/0/pr-00209` | new-era, a–c each |
| b7 | `0/0/2/1/pr-00211` | new-era, a–g, full-scope (99 findings) |
| b8 | `0/0/2/2/pr-00221`, `0/0/2/2/pr-00222` | new-era, a–c each |

Each folder holds `review-a.md`, `review-b.md`, … and exactly one
`resolution.md`. Extract every snapshot AND the resolution of each of
your assigned cases.

## Stem conventions (the `stem` field)

- Legacy era (pr-00156/160/171): `<version><letter>` as the snapshot
  itself titles it — `0.0.47a`, `0.0.47b`, `0.0.48c`, `0.0.49d` …
  The letter is the snapshot position in the folder (a=first).
- PR-keyed era (all other cases): `<case-key><letter>` — `pr-00189a`,
  `pr-00211g` … The case key is the `ID:` line of the `review-meta`
  header (equals the folder name); the letter is the `Snapshot:` line.

## What to extract

For every **snapshot** file: metadata + every finding (including
retracted, rejected, or downgraded ones — mark their status). New-era
snapshots open with a `review-meta` HTML comment (ID, Snapshot, Subject,
Scope, Base, Diff, Date, Reviewer) — transcribe it directly; their
"Findings index" table (columns vary: ID/Sev/Location/Provenance/Summary
or subsets) plus the body prose are the finding sources. Verified-OK
prose, method sections, gate results, and per-commit "sound and
effective" verdicts are NOT findings; skip them (but note the
gates/verdict flavor in process_notes if remarkable).

For every **resolution** file: only a compact summary — disposition
counts, recorded follow-ups/regressions, notable not-done rationales.
Use the resolution's own numbers where it states them (e.g. "37 a-, 30
b-, 11 c- findings dispositioned"); count only if not stated.

## Error-class taxonomy (classify the DEFECT the finding describes, not the artifact)

## Error-class taxonomy (classify the DEFECT the finding describes, not the artifact)

- `race-toctou` — TOCTOU / scan-then-act / check-then-use windows, symlink
  operand swaps, chmod/chown walk-order races
- `silent-failure` — swallowed errors, silent aborts, invisible failure
  modes, lying success messages (says OK when it failed)
- `shell-semantics` — set -e / pipefail / glob / quoting / rc-propagation /
  subshell / untrusted-input shell pitfalls
- `perm-model` — violation of the permission/security model: chown/chmod
  through symlinks, agent-plantable operands, ACL principal mismatch,
  privilege escalation, secret disclosure
- `test-gap` — a (new) mechanism has no pin/test coverage at all
- `test-vacuous` — a pin exists but does not discriminate (green when
  broken), unpinned claims, fail-but-green gates
- `fix-regression` — a fix introduced a new defect, reopened or
  reintroduced a previously-fixed class
- `sibling-sweep` — a class was closed at the named site(s) but same-shape
  siblings elsewhere were left unswept (incomplete class closure)
- `claim-drift` — comments/docs/log-lines/messages overstate or
  misdescribe actual behavior (incl. lying log lines, stale comments,
  docs overpromising)
- `wiring-gate` — build/test/lint wiring and gates: make target lists,
  ratchet violations, exec-bit policy, suite not run by CI, gate runs
  after summary
- `perf` — repeated/unstamped filesystem scans, O(large) cost on
  interactive paths
- `deploy-shape` — checkout vs deployed-kit fallbacks, KIT_FILES manifest
  consistency, install/update parity, versioning stamps
- `hardcoded-env` — hardcoded users/paths, environment assumptions
  (umask, missing /etc/os-release, CRLF, distro-specific, GNU-only tools)
- `ux-output` — user-facing output style/wording problems
  (honesty-neutral UX, prompt conventions)
- `docs-policy` — docs missing or outdated where the repo rules demand
  same-PR updates; index/structure drift
- `process` — review-loop discipline itself: snapshot ordering,
  resolution timing, provenance gaps
- `other` — anything else (always add a descriptive summary)

Decision rules:
- Primary class only in `class`; if a finding genuinely spans two, set
  `secondary_class`.
- A defect *found in a test file* about a weak pin is `test-vacuous`;
  about a missing pin is `test-gap`.
- `fix-regression` and `sibling-sweep` describe *provenance of the
  defect* (introduced by a fix / missed siblings); prefer them over
  generic classes when that is the essence of the finding, and use
  `secondary_class` for the underlying technical shape.
- Severity: use the review's own stated severity. Map synonyms
  (MAJOR→MED, MINOR/NIT→LOW, QUESTION→INFO-Q). If only implied, infer
  and set `"severity_inferred": true`.

## Areas (pick the closest)

`install.sh`, `update.sh`, `config.sh`, `status.sh`, `uninstall.sh`,
`bin-opk`, `bin-wrappers` (ddev-as-opencode, ddev-terminal, …), `sh-lib`
(sh/*.sh), `management`, `templates`, `tests-unit`, `tests-e2e`, `tui`,
`py`, `docs`, `build-ci` (Makefile, workflows), `internal` (reviews,
records, rules-meta), `multiple`, `other`

## Output JSON schema

Write one JSON object to your batch file:

```json
{
  "batch": "b1",
  "snapshots": [
    {
      "stem": "0.0.47a",
      "file": "internal/reviews/0/0/1/5/pr-00156/review-a.md",
      "date": "2026-10-10",
      "scope": "full | wave | micro | external-full | other",
      "reviewer": "GLM-5.3 lead + 2 subagents | GPT-6 Luna | ... (short)",
      "subject": "what was reviewed (issue/feature/fix wave), <= 15 words",
      "stop_rule": "met | not_met | n/a",
      "stated_counts": { "HIGH": 0, "MED": 0, "LOW": 0, "INFO": 0 },
      "findings": [
        {
          "id": "F1",
          "severity": "MED",
          "severity_inferred": false,
          "class": "silent-failure",
          "secondary_class": null,
          "area": "install.sh",
          "provenance": "wave-introduced | pre-existing | fix-induced | delta-introduced | null (unstated)",
          "summary": "<= 20 words, English",
          "cross_refs": ["0.0.39b C2"],
          "status": "reported | retracted | rejected | downgraded"
        }
      ],
      "process_notes": ["optional short notes: verification method, anomalies"]
    }
  ],
  "resolutions": [
    {
      "stem": "0.0.47",
      "file": "internal/reviews/0/0/1/5/pr-00156/resolution.md",
      "dispositions": { "implemented": 0, "implemented_differently": 0, "not_done": 0 },
      "follow_ups_recorded": 0,
      "notes": "<= 40 words: notable not-done rationales, regressions recorded"
    }
  ]
}
```

Rules: valid JSON, UTF-8, no trailing commas. `stated_counts` = counts
as the snapshot itself states them (its Result/Verdict line); the
findings array is your extraction — small deviations are fine.
`provenance` = the finding's own provenance claim where it makes one
(fix waves reviewing fixes often state it); else null.

### cross_refs normalization (IMPORTANT for this run)

Every explicit reference the finding makes to an EARLIER finding/class:

- Legacy-style refs verbatim: `0.0.39g S2`, `0.0.41f S2`, `#112 class`,
  `0.0.42d class`, `V22` (bare IDs keep their letter exactly as
  written).
- PR-keyed refs WITHOUT the leading `#`: `(#176 a W1)` becomes
  `pr-00176 a W1` (pad to 5 digits); `(#211 g W2)` becomes
  `pr-00211 g W2`. Same-case refs (`a W1` inside case pr-00211) become
  `pr-00211 a W1`.
- Real GitHub issues keep the `#`: `#187`, `#112 class`.
- Class-word refs like "the L5 class" or "the 0.0.39h F2 class" are
  refs too: `L5`, `0.0.39h F2`.
