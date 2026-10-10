# Statistics — error classes across the review corpus

> **As of the analysis run 2026-10-10.** Corpus: review snapshots
> 0.0.38–0.0.46 (54 snapshots, 9 resolutions, 2026-09-26 → 2026-10-09);
> extraction and classification method: [data/](data/README.md).
> Point-in-time measurement — see the
> [record README](README.md#re-running-this-analysis) for re-runs.

Population: **553 reported finding rows** (12 HIGH /
106 MED / 278 LOW / 157 INFO). Another 67 extracted rows were retracted or
rejected inside the review itself (see
[further-analyses.md](further-analyses.md#1-review-precision)).

## 1) Class ranking

n = reported rows; H/M/L/I = severity; "versions" = number of version groups
the class appears in (recurrence indicator for the learnings).

| # | Class | n | H / M / L / I | H+M | Versions | Spread |
|---|---|---|---|---|---|---|
| 1 | `claim-drift` (comments/docs/logs assert what code does not deliver) | **77** | 1/4/38/34 | 5 | 8 | 0.0.39–0.0.46 continuous |
| 2 | `silent-failure` (swallowed errors, silent aborts, lying success) | **62** | 1/12/32/17 | **13** | **9** | **all** |
| 3 | `other` (supply chain, API contracts, data formats, …) | 57 | 1/6/23/27 | 7 | 9 | all |
| 4 | `shell-semantics` (set -e/pipefail, quoting, glob, rc loss) | 46 | 0/14/24/8 | **14** | **9** | **all** |
| 5 | `sibling-sweep` (class closed at named site only, twins left) | 46 | 1/12/30/3 | **13** | 8 | 0.0.38–0.0.45 |
| 6 | `docs-policy` (docs missing/drifted vs same-PR rule) | 44 | 1/9/31/3 | 10 | 4 | 0.0.38/39/42/44 |
| 7 | `test-vacuous` (pin exists but does not discriminate) | 37 | 0/6/22/9 | 6 | 8 | 0.0.39–0.0.46 |
| 8 | `ux-output` (output style, wording) | 35 | 0/0/16/19 | 0 | 8 | — |
| 9 | `perm-model` (chown/chmod through symlinks, ACL principals, escalation) | 33 | **4**/12/10/7 | **16** | 7 | 0.0.38–0.0.45 |
| 10 | `wiring-gate` (make/lint/CI lists, ratchet, exec bits, fail-but-green) | 22 | 0/10/8/4 | 10 | 7 | 0.0.38–0.0.45 |
| 11 | `race-toctou` (scan-then-act, operand swap, chmod/chown order) | 20 | 1/6/5/8 | 7 | 7 | 0.0.38–0.0.46 |
| 12 | `test-gap` (new mechanism entirely unpinned) | 19 | 0/4/12/3 | 4 | 5 | — |
| 13 | `fix-regression` (fix introduces new defect / reopens class) | 19 | 1/10/6/2 | **11** | 6 | 0.0.39–0.0.46 |
| 14 | `hardcoded-env` (hardcoded users/paths, environment assumptions) | 14 | 1/0/8/5 | 1 | 7 | — |
| 15 | `process` (review-loop discipline itself) | 11 | 0/0/8/3 | 0 | 4 | 0.0.39–0.0.42 |
| 16 | `deploy-shape` (checkout vs deployed, manifests, fallbacks) | 7 | 0/1/4/2 | 1 | 4 | — |
| 17 | `perf` (unstamped walks, interactive-path cost) | 4 | 0/0/1/3 | 0 | 3 | — |

Severity-weighted top classes (H+M): `perm-model` 16 · `shell-semantics` 14 ·
`sibling-sweep` 13 · `silent-failure` 13 · `fix-regression` 11 ·
`docs-policy` 10 · `wiring-gate` 10 — the "real" defect ranking once LOW/INFO
noise is dropped.

## 2) Class × version group (reported rows)

| Class | 0.0.38 | 0.0.39 | 0.0.40 | 0.0.41 | 0.0.42 | 0.0.43 | 0.0.44 | 0.0.45 | 0.0.46 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| claim-drift | 0 | 25 | 7 | 3 | 16 | 1 | 9 | 11 | 5 |
| silent-failure | 7 | 16 | 1 | 4 | 2 | 5 | **12** | **12** | 3 |
| shell-semantics | 7 | 16 | 1 | 4 | 6 | 4 | 4 | 2 | 2 |
| sibling-sweep | 2 | 15 | 4 | 1 | 6 | 4 | 9 | 5 | **0** |
| docs-policy | 5 | 25 | 0 | 0 | 13 | 0 | 1 | 0 | 0 |
| test-vacuous | 0 | 12 | 3 | 3 | 7 | 1 | 6 | 3 | 2 |
| perm-model | 2 | 14 | 2 | 1 | 6 | 0 | 5 | 3 | 0 |
| wiring-gate | 4 | 6 | 1 | 2 | 6 | 0 | 2 | 1 | 0 |
| race-toctou | 1 | 6 | 0 | 0 | 2 | 1 | 3 | 5 | 2 |
| test-gap | 0 | 5 | 0 | 1 | 5 | 0 | 6 | 0 | 2 |
| fix-regression | 0 | 6 | 1 | 0 | 2 | 0 | **7** | 2 | 1 |

Reading: 0.0.39 was the monolith (192 rows, 16 snapshots). 0.0.40/0.0.41 are
nearly clean (dedup + micro waves, mostly LOW/INFO). With the new subsystems
from 0.0.42 on (git matrix, ddev export/migrate, security hardening),
`silent-failure`, `fix-regression` and `race-toctou` rise again — new feature,
new instance of a known class at a new site.

## 3) Severity distribution

12 HIGH · 106 MED · 278 LOW · 157 INFO — 88 % of rows are LOW/INFO. The 12
HIGHs by class: 4× `perm-model`, 1× each `silent-failure`, `sibling-sweep`,
`race-toctou`, `claim-drift`, `fix-regression`, `shell-semantics`, `other`,
and 1 `docs-policy`-HIGH (docs promised a backup the code did not make —
`0.0.39a D1`).

## 4) Provenance (reported rows, n = 553)

| Provenance | n | Share |
|---|--:|--:|
| pre-existing (found in the existing tree) | 245 | 44 % |
| **fix-induced (introduced by our own fix wave)** | **112** | **20 %** |
| wave-introduced (introduced by the feature wave) | 89 | 16 % |
| delta-introduced | 18 | 3 % |
| not stated in the snapshot | 89 | 16 % |

4 in 10 rows originate in our own waves — the fix wave is the dangerous one
(see [further-analyses.md](further-analyses.md#2-escape-and-provenance)).

## 5) Areas (top, reported rows)

tests-unit 92 · sh-lib 83 · docs 67 · install.sh 66 · multiple 63 · build-ci
27 · update.sh 27 · bin-wrappers 25 · bin-opk 17 · uninstall.sh 15 ·
status.sh 15. — `tests-unit` as #1 is itself a finding: its dominant classes
are `test-vacuous` + `test-gap` (56 rows).

## 6) Snapshot scope mix

wave 29 · full 12 · micro 9 · external-full 3 · other 1.

## 7) Notable single findings (cited by stem)

- **0.0.41f C1/S1 (HIGH, silent-failure):** skip rc leaked as status 1; `set -e`
  silently killed `opk update` after deploy — delta-introduced, e2e-invisible.
- **0.0.42e S1 (HIGH, perm-model):** uninstall chown follows agent-planted
  symlinks.
- **0.0.44b W1 (HIGH, fix-regression):** non-sticky 2770 dump dir falsified
  V3's class claim — agent renames root's 700 stage (zero-race root write-through).
- **0.0.45c S1/S2 (HIGH, perm-model):** `project_path_sane` accepted trailing
  `/.` roots (filesystem-wide group baseline); finalize chown dereferenced a
  planted manifest symlink (`/etc/shadow` class, introduced by the 0.0.44d
  F2 wave).
- **0.0.39h F1 (HIGH, sibling-sweep):** ungated chown/chmod/cp operands on
  agent-replaceable paths — "missed sibling despite full-class claim".
- **0.0.44c C1 (MED, test-vacuous):** four pin blocks placed after the
  summary gate — fail-but-green; mechanism reverts kept suites green.
