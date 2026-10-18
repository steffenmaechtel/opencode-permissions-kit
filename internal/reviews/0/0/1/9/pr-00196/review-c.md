<!-- review-meta
ID: pr-00196
Snapshot: c
Subject: issue-192 b-wave fix (b B1/B2/B6/B7) micro-wave review
Scope: wave
Base: v0.0.51 @ d3e187d
Diff: d479622..8b944c2
Date: 2026-10-18
Reviewer: GLM-5.3 (house session, fresh — session-rotation pass D; main agent + 2 GLM-5.3-Flash axis subagents — mechanical, claims/docs; every finding main-agent-verified incl. a 5-mutation sabotage matrix)
-->

# Review — pr-00196 snapshot c — fix wave (b B1, b B2, b B6, b B7)

> Resolution: [resolution.md](resolution.md)

Wave under review: fix commit `8b944c2` (4 files, +44/−27) plus the
resolution bookkeeping `88f509b` (reviewed as a claims object): b B1 —
install.sh's own V14 pin joins the any-form sweep; b B2 — braced spelling
swept in all four registries, braced self-default fallback sanctioned;
b B6 — troubleshooting switch-user clause; b B7 — uninstall pin survivor
diagnostic. Question per review-concept: did the fixes break or lie?

**Bottom line: no behavior bug, nothing broke — all four registries
discriminate (proven for all four this pass, see C10), suites green.**
Four LOW findings, all claim/ledger drift of the exact class the wave
was closing: two survivor comments that the same commit's pipelines
contradict, the commit-message wording that overstates them, and a
dangling sabotage cite in the resolution. No MED/HIGH.

## Findings index

| ID | Sev | Site | Summary | Verified |
|----|-----|------|---------|----------|
| C1 | LOW | tests/unit/test-uninstall.sh:502–503 | comment: survivors are comments + fallback "only" — the same commit's `_un_bad` subtracts a third (braced self-default) the comment doesn't list | yes (diff + live pipeline) |
| C2 | LOW | tests/unit/test-update-flags.sh:602–603 | same drift: "…fallback assignment, nothing else" vs the third subtraction in `_up_bad` | yes (diff) |
| C3 | LOW | 8b944c2 commit msg | "comments reworded to claim exactly what the patterns deliver" — holds only for test-install-args.sh's two blocks; C1/C2 contradict it at the other two sites | yes |
| C4 | LOW | resolution.md:68 | "(S5/S6)" cite dangles — neither the resolution's nor review-b.md's matrix carries S labels (they point at the b session's /tmp logs), and the b-wave section reuses S1/S2/S3 for different mutations than review-b.md's S references | yes (grep both docs) |
| C5 | INFO | resolution.md:47–53 | a-T1 pattern block ("identical in all three suites") is stale vs the tree (4 registries, braced `-e`, third subtraction) — historical section, present-tense wording, neighbor sentences were corrected in place | yes |
| C6 | INFO | docs/troubleshooting.md:48–52 | `su - <name>` "elsewhere" — su also works inside WSL (and is the direct path from the root shell the reader is in); the `wsl -d … -u …` form assumes Windows side/interop; both commands syntactically correct, scoping suboptimal | partial (syntax + platform knowledge) |
| C7 | INFO | 8b944c2 commit msg headline | "close the pin-class sweep" is broader than the resolution's own scoping (mid-quote `/home/"$DEFAULT_USER` stays unmatched, documented as unenumerated residual) | yes |
| C8 | INFO | third `grep -v` (all management sweeps) | left-unanchored: `export X=…`, `cmd && X=…` prefixed forms of the sanctioned shape are exempt — the exempt class is the sanctioned idiom itself, and the softness mirrors the pre-existing `\|\| var=` subtraction design | yes (probe) |
| C9 | INFO | all four sweep pipelines | first-grep rc 2 masked by `2>/dev/null` + `\|\| true` → hypothetical vacuous pass; unreachable in practice (missing file fails the positive anchors → pin FAILs); pre-existing shape | yes (probe) |
| C10 | INFO | resolution b-wave matrix | proves 2 of 4 braced registries (install pin, status row) — uninstall/update braced discrimination claimed ("swept ×4") but unproven there; verified red by this pass (S4/S5 below) | yes (S4/S5) |

Counters: **0 HIGH · 0 MED · 4 LOW · 6 INFO.** No ghosts; two severity
adjustments during main-agent verification (axis LOW→INFO: the
left-unanchored subtraction C8 — exempt class analysis; the doc scoping
C6 — no incorrect command, both options listed; rationale in each
block).

## Per-finding detail

### C1 / C2 (LOW) — survivor comments contradict their own pipelines

The b B2 rewrite added the braced self-default subtraction
(`var="${var:-/home/${DEFAULT_USER:-$USER}}"`, EOL-anchored) to `_un_bad`
and `_up_bad`, but the reworded comments above them still say survivors
are "comment lines and the getent-failure fallback assignment only"
(test-uninstall) / "…nothing else" (test-update-flags). test-install-args'
sibling-loop comment — the fourth registry — enumerates all three
survivors correctly. Direction of the drift: the comments claim
strictness the code does not deliver; a future sanctioned-shape line in
uninstall.sh/update.sh passes silently while a reader auditing the pin
believes "only" two classes are allowed. Dead subtraction today (no such
line in either file — status.sh:155 is the only braced occurrence in
`files/`), so this is documentation accuracy, not a detection gap.
Provenance: wave-introduced (comments and pipelines both shipped by
8b944c2). Fix: one comment line each, mirroring the install-args
wording.

### C3 (LOW) — the commit-message claim is true for two of four sites

"comments reworded to claim exactly what the patterns deliver" — the
patterns deliver three survivor classes at all four registries (minus
the install pin's initializer-for-fallbacks difference); the comments
deliver that list at one file and the old two-class list at the other
two (C1/C2). Same claim-vs-delivery shape as b B2, smaller blast
radius. Nothing to change in history — the correction belongs in the
resolution (the ledger is live; commit messages are not).

### C4 (LOW) — dangling "(S5/S6)" cite and S-label collision

resolution.md:68 (the b B3 correction inside the a T1 row) justifies
the corrected sabotage wording with "the b-wave matrix (S5/S6)". Neither
matrix carries S labels: the resolution's b-wave table is unlabeled, and
review-b.md's matrix is too — its S1–S6 labels exist only in prose
references to the b session's `/tmp` logs. Worse, the b-wave evidence
section (resolution.md:132, 147–148) defines "Sabotage S1/S2/S3" for
different mutations (install old-gate / install braced / status braced)
than the S references review-b.md uses for its own runs — one chain, two
S-numberings. The next review cannot audit the cite from the repo.
Provenance: wave-introduced (the cite arrived with 88f509b's b B3
correction). Fix: name the mutations, not the labels (e.g. "the
review-b matrix rows for uninstall.sh/update.sh old-gate"), or label
the matrix rows.

### C5 (INFO) — a-wave pattern block gone stale

The resolution's a T1 evidence still shows the a-wave three-stage
literal-only pipeline as "New pattern (identical in all three suites)".
After 8b944c2 the tree has four registries, the braced `-e`, and the
third subtraction. The section is a historical record of the a-wave and
the b-wave section documents its own delta — but b B3/B8 corrected
neighboring sentences in this same section to present-tense reality,
leaving the block the only stale spot. Bookkeeping; suggest a one-line
"(superseded by the b-wave pattern below)" pointer rather than a
rewrite. Provenance: delta-introduced.

### C6 (INFO, axis LOW upheld→downgraded) — switch-user clause scoping

Both commands are syntactically correct and both are listed, so no
reader is instructed wrong; `wsl -d <distro> -u <name>` naturally runs
from Windows (or inside WSL via interop, typically on for the
developer), and `su - <name>` works from inside WSL — which is the
reader's exact situation — and everywhere else. The "on WSL /
elsewhere" split assigns su to non-WSL only, a suboptimal scoping, not
an error. Downgraded from axis LOW: no failure mode, seconds of
recovery, and b B6 asked for exactly these two commands. Fix (taste):
"(from Windows: `wsl -d <distro> -u <name>`; from inside the root
shell: `su - <name>`)".

### C7 (INFO) — headline vs documented residual

"close the pin-class sweep" reads as class-complete; the resolution
itself records the mid-quote spelling as an unenumerated residual (no
occurrence in `files/`, house style is unbraced). Rhetoric granularity,
recorded so the next reviewer does not re-litigate it as a claim gap.

### C8 (INFO, axis LOW downgraded) — third subtraction left-unanchored

Probed: `export FOO="${FOO:-/home/${DEFAULT_USER:-$USER}}"` and
`log "x" && _oc_home="${_oc_home:-…}"` are subtracted (the pattern
requires only `name="…"` at EOL). Every exempt line's home usage IS the
sanctioned self-default idiom — the prefix cannot smuggle a different
home expression past the sweep (any other shape — plain
`foo="/home/${DEFAULT_USER:-$USER}"`, usage inside `mkdir -p "${…}"`,
trailing text — stays flagged, probed). The pre-existing `|| var=`
subtraction has the identical left-unanchored softness by design
(0.0.44a era). Anchoring `^[[:space:]]*` would be strictly tighter;
optional hardening, not a detection gap. Provenance: wave-introduced
subtraction, pre-existing class softness.

### C9 (INFO) — rc-2 masking is unreachable-vacuous

If the swept file is missing, the sweep grep dies rc 2 behind
`2>/dev/null || true` (empty `_bad`), but the pin's positive anchors
fail on the same missing file → FAIL branch, not a vacuous pass
(probed: anchor rc 2 → condition false). A vacuous green would need the
file present, anchors passing, and the sweep grep erroring anyway — no
realistic shape. Pre-existing pipeline form; the wave only added a valid
`-e`.

### C10 (INFO) — matrix proved two of four braced registries

The b-wave resolution matrix runs three mutations (install old-gate,
install braced, status braced); the "swept at all four sites" claim
implies `_un_bad` and `_up_bad` discriminate on braced lines too, which
the ledger never showed. This pass ran them (S4/S5 below): both FAIL
red, quoting the line. The claim was true; the evidence was one matrix
short of it. Evidence now on record here — the resolution may cite this
snapshot instead of re-running.

## Verified clean (all axes, main-agent-verified)

- **b B1 implementation:** the install pin's sweep yields zero
  survivors on the live tree; the initializer subtraction matches the
  indented `    DEV_HOME="/home/$DEFAULT_USER"` at install.sh:615; both
  positive anchors (verbatim initializer, getent line) intact; S1
  sabotage FAILs quoting the offending line — the exact exposure b B1
  named (old gate shape back in green) is closed.
- **b B2 implementation:** the braced `-e` is present in all four
  registries; the sanctioned survivor (status.sh:155) is subtracted
  byte-exact; the subtraction is tight — a functional braced gate
  `[ -d "${X:-/home/${DEFAULT_USER:-$USER}}" ]` is NOT subtracted
  (probed); the mid-quote residual is documented (b B2 detail) and the
  reworded install-args comments no longer claim it; the sanctioned
  site stays positively pinned (test-status.sh openchamber rows,
  0.0.47b W2/0.0.47c C1).
- **b B7 implementation:** diagnostic parity delivered — S4's FAIL
  message carries `(_x_probe="/home/${DEFAULT_USER}/.config")`, matching
  the siblings' shape.
- **b B6 implementation:** commands syntactically correct, section
  reads correctly (see C6 for the scoping nit).
- **Live tree:** verbatim pipeline runs → zero functional survivors in
  install.sh, status.sh, update.sh, uninstall.sh; raw matches are
  exactly the sanctioned sites (initializer, three `|| var=` fallbacks,
  status.sh:155, comments).
- **L4:** all changed pin blocks sit before their suite's summary
  exit gate (uninstall pin :504 < gate :517; install and update
  analogous); every sabotage produced rc=1 — FAILs fail the suite.
- **L7:** `|| true` guards present and required on all four capture
  pipes (final `grep -v` rc 1 on empty); no new unquoted expansion or
  set -e hazard.
- **Sandbox:** no new writes at all — the wave adds pure greps; the
  sandbox-policy suite is green.
- **Conventions:** English throughout; docs changed with the code in
  the same commit; `#196 b B1`-style citations in the new comments;
  resolution rows ≤120 cols, three disposition verbs only, 21/21
  findings dispositioned (a: 10, b: 11).
- **Resolution accuracy:** the b B3 corrections to the a-wave rows
  match the measured reality of review-b's matrix; the b B8 cite :615
  is correct; the "first green run FAILED on status.sh:155" narrative
  is mechanically consistent (the pre-b B2 intermediate state
  reproduces exactly that failure).
- **Gates at HEAD 88f509b:** `make test` green (all suites incl.
  reviews lint + parity), `make lint` green, `make check-version` green
  (0.0.51).

## Sabotage matrix (main agent, real tree @ 88f509b, restored green after each)

| Mutation | Result |
|---|---|
| install.sh + old-gate line `[ -d "/home/$DEFAULT_USER" ]` | test-install-args FAIL (V14 pin, line quoted) — 1 FAIL total, rc=1 |
| install.sh + braced functional line | test-install-args FAIL (V14 pin, line quoted) |
| status.sh + braced functional line | test-install-args FAIL (sibling status row, line quoted); test-status rc=0 (no collateral) |
| uninstall.sh + braced functional line | test-uninstall FAIL (pin + b B7 diagnostic quotes the line) — C10/S4 |
| update.sh + braced functional line | test-update-flags FAIL (pin quotes the line) — C10/S5 |
| restored | all four suites rc=0 |

Every mutation produced exactly one targeted FAIL — no collateral, a
cleaner matrix than either predecessor snapshot's.

## Run provenance, gates, environment

- **Agents:** 2 fresh-context GLM-5.3-Flash axis subagents (mechanical
  → M1–M2, claims/docs → C1–C7 in the agents' own scheme), ~5–8 min
  budget each, checkpointed to
  `/tmp/opencode/pr00196-review-c/{mechanical,claims}.md`; main agent
  (GLM-5.3, fresh session — rotation pass D) re-verified every finding
  (verbatim pipeline replication, BRE probes incl. escaped-brace
  control, the 5-mutation matrix, doc cross-reads), applied the two
  severity adjustments, and renumbered to the house scheme C1–C10. No
  fixing while verifying.
- **Gates run:** `make test` — all green; `make lint` green;
  `make check-version` green (0.0.51); four touched/nearby suites
  re-run green after the matrix restore.
- **e2e:** not run for this delta (tests + docs only, no `files/`
  change — b B9 precedent); branch-level e2e at merge is the
  maintainer's gate.
- **Environment:** WSL2 kit-managed host (agent runs as the `opencode`
  user); opencode 1.18.15 pinned reference; logs, probes and
  checkpoints in `/tmp/opencode/pr00196-review-c/`.

## Recommendation

The b-wave fixes did what b B1/b B2/b B6/b B7 claim and broke nothing;
nothing here blocks merge. All ten findings are comment/docs/ledger
touch-ups or optional hardening — no behavior, no pins lost. Stop rule:
if the c-dispositions stay in comments, docs and resolution bookkeeping
(C1–C7, C10 — the 0.0.45f comment-only precedent) and C8/C9 go
deliberately not done, no review-relevant code changes and the chain
closes at c. Taking C8's anchoring would touch test code and owe a
final micro-wave pass (d).
