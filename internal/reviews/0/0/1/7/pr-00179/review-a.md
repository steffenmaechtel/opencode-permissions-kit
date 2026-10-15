<!-- review-meta
ID: pr-00179
Snapshot: a
Subject: issue-173 docs reflow baseline (feature wave)
Scope: wave
Base: v0.0.50 @ ee54ca0
Diff: ee54ca0..6e87eed
Date: 2026-10-14
Reviewer: GLM-5.3 (external /review session)
-->

# Review — pr-00179 snapshot a — issue #173 docs reflow baseline

> Resolution: [resolution.md](resolution.md)

Wave under review: the whole branch `master..HEAD` (5 commits, 12 docs
files + `tests/unit/line-length-baseline.txt`, +226/−82): reflow of the
overlong lines in `docs/` and the matching line-length-baseline burn-down
(`docs/how-to/update.md` and `docs/reference/cli.md` entries shrunk, the
other ten docs files reflowed to zero and dropped from the baseline).

**Verdict: no HIGH/MED findings. 1 LOW, 2 INFO — stop rule met.**
Docs-only wave: every finding's plausible disposition stays in docs or
bookkeeping, which is not review-relevant code, so the loop closes with
this snapshot.

## Findings index

| ID | Severity | Provenance | Summary |
|---|---|---|---|
| W1 | LOW | wave-introduced | install.sh one-liners wrapped, the six update.sh streaming one-liners left overlong (the whole surviving baseline) — inconsistent treatment, no behavior impact |
| W2 | INFO | wave-introduced | three reworded cells lost specificity; each recovers from surrounding prose |
| W3 | INFO | wave-introduced | "(notes)" cell pointers inconsistent; some targets are unlabeled prose |

## Verification performed

1. **Baseline integrity.** `sh tests/unit/test-line-length.sh` passes.
   The surviving baseline entries (`docs/how-to/update.md 325 5`,
   `docs/reference/cli.md 62 1`) exactly match the six surviving
   overlong lines — all six are `update.sh` curl-streaming one-liners
   (5 in update.md lines 33/36/39/69/89, 1 in cli.md line 287). No
   stale entries, no growth, counts and sums recomputed by hand.
2. **Content fidelity.** Every shortened table cell was compared against
   `master`; dropped tokens were swept mechanically (normalized token
   diff per file, old-vs-new). Every detail moved out of a cell
   reappears in the notes/prose added below the table — `files.md`
   (install.conf keys, sudoers, `/usr/local` inventory),
   `security-model.md` (audit table), `cli.md` (flag and command
   notes), `compatibility.md` (OpenChamber/OpenHarness detail → the
   pre-existing Caveats section the shortened row now points to). Most
   "dropped" tokens were punctuation/case false positives; the real
   rewording losses are enumerated in W2 below.
3. **Gates.** Full unit sweep green (36 suites, incl. `test-docs.sh`
   link/anchor check — all anchors and relative links the reflow
   touched resolve). The `troubleshooting.md` self-test rewrite
   (`STANDIN` variable + quoted use replacing the long literal) is
   functionally equivalent for whole-block copy-paste. Working tree
   clean; e2e not owed (docs-only wave, no `files/` change).

## Findings

### W1 (LOW) — one-liner wrapping is inconsistent

The install.sh one-liners were wrapped with `\` continuations
(getting-started.md, cli.md install.sh block, update.md supported-upgrade
paths, secure-git-config.md), while the six `update.sh` streaming
one-liners stayed single-line — they are exactly the surviving baseline
entries. Both forms are copy-paste-safe (bash continues on
backslash-newline and on a trailing pipe), so this is a consistency
question, not a behavior one. If leaving URL lines unbroken was
deliberate, the baseline remainder documents it; otherwise the same
`\`-wrap would clear the last two baseline entries. Severity is LOW
because no reader or gate is affected either way.

### W2 (INFO) — small specificity losses in reworded cells

Three spots where a shortened cell carries less than the original, in
each case recoverable from prose that survives in the same page:

- `security-model.md` soft-layer row: "enforced by opencode's tools,
  **prompted** via bash tripwires" → "opencode's tools + bash
  tripwires". The enforce-vs-ask distinction is gone from the cell but
  survives in "Known residual gaps" ("only caught by the template's
  lexical ask-tripwires") and the intro prose.
- `security-model.md` audit row: "packet/log access can leak
  credentials" → "can leak credentials". The mechanism is now only
  implied by the group names `wireshark`/`adm`/`systemd-journal`.
- `update.md` channel table: "The default recommendation; installs and
  updates track it" → "The default recommendation".

Factual claims stay correct in all three; no behavior claim was
weakened below truth.

### W3 (INFO) — "(notes)" pointer wording inconsistent

Shortened cells point at their detail with "(notes)", but only some
files label the follow-up block accordingly ("Key notes", "Surface
notes", "Flag notes", "Command notes", "Deployment notes");
`sharing-group.md` and `container-tools.md` point "(notes)" at an
unlabeled prose paragraph, and `ddev-integration.md` uses "(legacy
fallback — notes)". Readers find the detail either way; a uniform label
pattern would help scanning.

## Provenance, gates, recommendation

- **Model:** GLM-5.3 (external /review session, single lead pass, no
  subagents — the diff is small and every finding was verified against
  full-file reads and live gate re-runs).
- **Tree:** `feature/issue-173-docs-reflow-baseline` @ `6e87eed`, clean;
  base `master` @ `ee54ca0` (v0.0.50).
- **Gates run:** full unit sweep (36 suites) green; line-length ratchet
  green at the burned-down baseline; docs link check green; e2e not owed
  (docs-only wave).
- **Recommendation:** merge-ready. Suggested dispositions: W1–W3
  deliberately not done (or docs-polish at maintainer taste — any such
  edit stays in docs and closes nothing further). No fix wave owed; the
  loop closes per the stop rule (docs/bookkeeping are not
  review-relevant code).
