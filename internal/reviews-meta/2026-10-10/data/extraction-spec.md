# Meta-review extraction spec

Purpose: you are one of several parallel extraction agents. Together we analyze all
code-review snapshots under `docs/design/review/` of the opencode permissions kit.
Your job: read your assigned review files COMPLETELY and convert every *defect
finding* they contain into structured JSON. A parent agent will aggregate your batch
with the others into error-class statistics and recurrence analysis.

**Read only your assigned files** (plus this spec). Do not explore the repo code —
the findings are self-contained. Do not modify anything except writing your batch
JSON file.

## Background (1 paragraph)

The repo is a shell-based kit ("opencode permissions kit") that runs opencode as its
own Linux user against a rootless container backend. Each review snapshot is either a
*full-scope* review of a version tip or a *wave/micro review* of a fix or feature
wave. Snapshots use different ID schemes over time (`S#/C#/D#/Q#` house format,
later `F#`, `W#`, `V#`, `E#`, `G#`, `C#`), severities are HIGH / MED(IUM) / LOW /
INFO (plus Q = question). Resolutions disposition every finding (implemented /
implemented differently / deliberately not done). Reviews frequently cross-reference
earlier findings as recurring "classes" (e.g. "the 0.0.42d class") — capture those
references, they are the core input for the recurrence analysis.

## What to extract

For every **snapshot** file: metadata + every finding (including retracted,
rejected, or downgraded ones — mark their status). Verified-OK prose, method
sections, gate results, and per-commit "sound and effective" verdicts are NOT
findings; skip them (but note the gates/verdict flavor in process_notes if
remarkable).

For every **resolution** file (`*-resolution.md`): only a compact summary —
disposition counts, recorded follow-ups/regressions, notable not-done rationales.

## Error-class taxonomy (classify the DEFECT the finding describes, not the artifact)

| Code | Meaning |
|---|---|
| `race-toctou` | TOCTOU / scan-then-act / check-then-use windows, symlink operand swaps, chmod/chown walk-order races |
| `silent-failure` | swallowed errors, silent aborts, invisible failure modes, lying success messages (says OK when it failed) |
| `shell-semantics` | set -e / pipefail / glob / quoting / rc-propagation / subshell / untrusted-input shell pitfalls |
| `perm-model` | violation of the permission/security model: chown/chmod through symlinks, agent-plantable operands, ACL principal mismatch, privilege escalation, secret disclosure |
| `test-gap` | a (new) mechanism has no pin/test coverage at all |
| `test-vacuous` | a pin exists but does not discriminate (green when broken), unpinned claims, fail-but-green gates |
| `fix-regression` | a fix introduced a new defect, reopened or reintroduced a previously-fixed class |
| `sibling-sweep` | a class was closed at the named site(s) but same-shape siblings elsewhere were left unswept (incomplete class closure) |
| `claim-drift` | comments/docs/log-lines/messages overstate or misdescribe actual behavior (incl. lying log lines, stale comments, docs overpromising) |
| `wiring-gate` | build/test/lint wiring and gates: make target lists, ratchet violations, exec-bit policy, suite not run by CI, gate runs after summary |
| `perf` | repeated/unstamped filesystem scans, O(large) cost on interactive paths |
| `deploy-shape` | checkout vs deployed-kit fallbacks, KIT_FILES manifest consistency, install/update parity, versioning stamps |
| `hardcoded-env` | hardcoded users/paths, environment assumptions (umask, missing /etc/os-release, CRLF, distro-specific, GNU-only tools) |
| `ux-output` | user-facing output style/wording problems (honesty-neutral UX, prompt conventions) |
| `docs-policy` | docs missing or outdated where the repo rules demand same-PR updates; index/structure drift |
| `process` | review-loop discipline itself: snapshot ordering, resolution timing, provenance gaps |
| `other` | anything else (always add a descriptive summary) |

Decision rules:
- Primary class only in `class`; if a finding genuinely spans two, set `secondary_class`.
- A defect *found in a test file* about a weak pin is `test-vacuous`; about a missing pin is `test-gap`.
- `fix-regression` and `sibling-sweep` describe *provenance of the defect* (introduced by a fix / missed siblings); prefer them over generic classes when that is the essence of the finding, and use `secondary_class` for the underlying technical shape.
- Severity: use the review's own stated severity. Map synonyms (MAJOR→MED, MINOR/NIT→LOW, QUESTION→INFO-Q). If only implied, infer and set `"severity_inferred": true`.

## Areas (pick the closest)

`install.sh`, `update.sh`, `config.sh`, `status.sh`, `uninstall.sh`, `bin-opk`,
`bin-wrappers` (ddev-as-opencode, ddev-terminal, …), `sh-lib` (sh/*.sh), `management`,
`templates`, `tests-unit`, `tests-e2e`, `tui`, `py`, `docs`, `build-ci` (Makefile, workflows), `multiple`, `other`

## Output JSON schema

Write one JSON object:

```json
{
  "batch": "b1",
  "snapshots": [
    {
      "stem": "0.0.39a",
      "file": "docs/design/review/2026-09-27-v0.0.39-a.md",
      "date": "2026-09-27",
      "scope": "full | wave | micro | external-full | other",
      "reviewer": "GLM-5.3 lead + 2 subagents | GPT-6 Luna | ... (short)",
      "subject": "what was reviewed (issue/feature/fix wave), <= 15 words",
      "stop_rule": "met | not_met | n/a",
      "stated_counts": { "HIGH": 0, "MED": 0, "LOW": 0, "INFO": 0 },
      "findings": [
        {
          "id": "S1",
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
      "stem": "0.0.39",
      "file": "docs/design/review/2026-09-28-v0.0.39-resolution.md",
      "dispositions": { "implemented": 0, "implemented_differently": 0, "not_done": 0 },
      "follow_ups_recorded": 0,
      "notes": "<= 40 words: notable not-done rationales, regressions recorded"
    }
  ]
}
```

Rules: valid JSON, UTF-8, no trailing commas. `stated_counts` = counts as the
snapshot itself states them (its Result line / index row); the findings array is your
extraction — small deviations are fine. `cross_refs`: every explicit reference the
finding makes to an EARLIER finding/class (stems like `0.0.39g S2`, `#112 class`,
`V22`, `0.0.42d class`). Include F#/W#/V#/E#/G# letters exactly as written.
