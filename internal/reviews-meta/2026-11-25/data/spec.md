# M3 extraction spec — repeat-class baseline (issue #768)

Purpose: you are one of several parallel extraction agents. Together we
classify code-review findings from PR timelines of the opencode
permissions kit into error classes and decide, per finding, whether a
rule covering its defect shape already existed when it was reported
(the "repeat-class share" metric M3). A parent agent aggregates your
batch with the others.

**Read-only**: fetch PR data with `gh` (no mutations, no repo edits).
The ONLY file you write is your batch JSON. Do not touch the repository
working tree.

## How to read your assigned rounds

For each assigned round (PR number + wave letter + date):

```sh
gh -R steffenmaechtel/opencode-permissions-kit pr view <PR> --json comments --jq '.comments[].body'
```

The round you want is the comment titled `## Review <wave> — …` (wave
letter matches your assignment) carrying an HTML comment marker
`<!-- opk-review {"case":"pr-XXXXX","wave":"<letter>", …} -->` — the
marker JSON may wrap over several lines. IGNORE: other waves' comments,
closing summaries — dedicated closing comments in every era spelling
(`wave":"z"`, `wave":"closing"`, `wave":"close"`, or `state":"closed"`
— the same rule as data/normalize.py, #780 a B4) — and provenance
corrections. If you cannot find the round comment, record a
process_note and continue.

Inside the round comment: a findings table (`| ID | Sev | … |`) plus
per-finding detail paragraphs (`**A1 (LOW)** — …`). Extract EVERY
finding, including retracted ones (status field).

## Output JSON schema

Write ONE JSON object to your assigned output file:

```json
{
  "batch": "b1",
  "snapshots": [
    {
      "stem": "pr-00617a",
      "file": "pr-617/timeline",
      "date": "2026-11-18",
      "scope": "wave",
      "reviewer": "from the round comment (short)",
      "subject": "what the round reviewed, <= 15 words",
      "stop_rule": "met | not_met | n/a",
      "stated_counts": { "HIGH": 0, "MED": 0, "LOW": 0, "INFO": 0 },
      "findings": [
        {
          "id": "A1",
          "severity": "LOW",
          "severity_inferred": false,
          "class": "claim-drift",
          "secondary_class": null,
          "area": "tests-unit",
          "provenance": "wave-introduced | pre-existing | fix-induced | null",
          "summary": "<= 20 words, English",
          "cross_refs": ["pr-00568 c Z3"],
          "status": "reported | retracted | rejected | downgraded",
          "repeat": true,
          "repeat_basis": "cross-ref | pre-existing-rule | new-class"
        }
      ],
      "process_notes": ["optional short notes"]
    }
  ],
  "resolutions": []
}
```

Stem = `pr-` + zero-padded PR number (5 digits) + wave letter. Valid
JSON, UTF-8, no trailing commas. `stated_counts` from the round's
verdict line; findings array is your extraction.

## Error-class taxonomy (classify the DEFECT, not the artifact)

`race-toctou`, `silent-failure`, `shell-semantics`, `perm-model`,
`test-gap`, `test-vacuous`, `fix-regression`, `sibling-sweep`,
`claim-drift`, `wiring-gate`, `perf`, `deploy-shape`, `hardcoded-env`,
`ux-output`, `docs-policy`, `process`, `other`.

Decision rules: defect found in a test file about a weak pin =
`test-vacuous`; about a missing pin = `test-gap`. `fix-regression` and
`sibling-sweep` describe provenance of the defect — prefer them when
that is the essence. Severity: the review's own stated severity.

Areas: `install.sh`, `update.sh`, `config.sh`, `status.sh`,
`uninstall.sh`, `bin-opk`, `bin-wrappers`, `sh-lib`, `management`,
`templates`, `tests-unit`, `tests-e2e`, `tui`, `py`, `docs`,
`build-ci`, `internal`, `multiple`, `other`.

## repeat: did a rule already cover this defect shape?

`repeat: true` means: when this finding was reported, a documented
rule, learning (L1–L7), convention or meta already covered the defect
shape — the corpus failed to PREVENT a known class.

- The finding carries an explicit cross-reference to an earlier
  finding/class (e.g. "the #568 class", `(#176 a W1)`) ⇒ `repeat:
  true`, basis `cross-ref` (AND record the ref in cross_refs,
  normalized as `pr-00176 a W1` — no leading `#` for PR refs; real
  GitHub issues keep `#`).
- Otherwise judge by class: every taxonomy class above had standing
  rule coverage long before 2026-11-18 (learnings L1–L7 + agent/
  conventions) ⇒ `repeat: true`, basis `pre-existing-rule` — EXCEPT
  defect shapes from this recently-codified list; those count as
  `repeat: false` (basis `new-class`) when the finding's date is the
  codification date or earlier, `repeat: true` only after it:

| Defect shape | Rule codified |
|---|---|
| e2e git-writing arms: inline committer identity, no blanket `>/dev/null 2>&1` on observed git failures, recreate pruned dirs after `checkout -B`, staged-state constrains later merges | 2026-11-20 (#684/#686) |
| controlled-PATH enumeration completeness: stub-internal externals, fallback arms inside pinned blocks, set -u message variables | 2026-11-18 (#616) |
| referenced-path sandbox leg: existence asserts through symlinks to host paths, grep-needle inputs, comparison baselines | 2026-11-22 (#749) |
| case-split `case` grammar on one line; occurrence-counting (grep -o) vs line-counting (grep -c) for joined/single-line views; absence patterns probed against every separator | 2026-11-22 (#738/#739) |
| post-rebase `SHA256SUMS` own-commit-before-test shape | 2026-11-20 (#687) |
| docs-loop v2 mechanics (recurrence intake, AGENTS.md cap gate, metrics script) | 2026-11-23 (#755) |

- `other`-class findings: judge individually — covered by any
  pre-existing rule/learning/convention ⇒ `pre-existing-rule`.
- Cross refs in the round comment that tie a finding to an earlier
  incident are the strongest signal; when in doubt between
  `pre-existing-rule` and `new-class`, check whether the defect shape
  reads like "process/known-class violated" (repeat) or "first
  discovery of a new mechanism" (not repeat) and record a one-line
  rationale in the summary.
