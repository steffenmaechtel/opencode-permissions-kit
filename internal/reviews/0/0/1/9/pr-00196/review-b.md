<!-- review-meta
ID: pr-00196
Snapshot: b
Subject: issue-192 root-gate fix wave (a T1/T2/T3, a W1, a S1) micro-wave review
Scope: wave
Base: v0.0.51 @ d3e187d
Diff: 86376ec..3443d04
Date: 2026-10-18
Reviewer: GLM-5.3 (house session, fresh — session-rotation pass C; main agent + 2 GLM-5.3-Flash axis subagents — mechanical, claims/docs; every finding main-agent-verified incl. a 6-run sabotage matrix)
-->

# Review — pr-00196 snapshot b — fix wave (a T1, a T2, a T3, a W1, a S1)

> Resolution: [resolution.md](resolution.md)

Wave under review: fix commit `3443d04` (6 files, +158/−22): a T1 —
the three V14 sibling-sweep pins tightened to flag any
`/home/$DEFAULT_USER` form; a T2 — five pin blocks executing every new
probe fallback arm; a T3 + a W1 — troubleshooting sentences; a S1 —
trust-model comment at `_root_user_gate`. Question per review-concept:
did the fixes break or lie?

**Bottom line: no behavior bug, nothing broke — every new pin
discriminates and all suites are green.** One MED class-sweep gap: the
pin-tightening itself stopped one file short (install.sh's own V14 pin
keeps the exact too-narrow shape the wave's resolution claims was
swept), plus two LOW evidence/claim drifts in the resolution's own
sabotage record. All remaining findings are INFO-level.

## Findings index

| ID | Sev | Site | Summary | Verified |
|----|-----|------|---------|----------|
| B1 | MED | tests/unit/test-install-args.sh:210–215 | fourth same-shape V14 pin (install.sh's own) still trailing-slash-only — the resolution's "L2 sweep of the pins" is one file short | yes (live + blame + matrix) |
| B2 | LOW | test-install-args.sh:229, test-uninstall.sh:502, test-update-flags.sh:603 | brace (`/home/${DEFAULT_USER}`) and mid-quote spellings escape the sweep grep — the "ANY form" claim is overstated | yes (probe) |
| B3 | LOW | resolution.md:47–48, 68–70, 94 | sabotage evidence drift: "all three suites FAIL / 3× FAIL (T1 pins)" is not what a status.sh-only mutation does; "both DEFAULT_HOME arms FAIL" — the arms never run on deletion | yes (S1/S4 measured) |
| B4 | INFO | the three sweep pipelines | a fallback line with a trailing comment would be flagged (EOL-anchored subtraction) — false-red, fail-loud only | yes (probe) |
| B5 | INFO | commit msg; resolution.md:52–66 | "five pins" counts blocks; 6 executed assertions ship — substance holds, granularity note | yes (counted) |
| B6 | INFO | docs/troubleshooting.md:48–52 | create-a-user recipe: correct for supported distros; no "how to switch into the account" step | yes |
| B7 | INFO | tests/unit/test-uninstall.sh:510 | tightened pin's fail message lacks the survivor diagnostic its two sibling sites got in the same commit | yes |
| B8 | INFO | resolution.md:44 | stale cite install.sh:612 → now :615 (shifted by the wave's own comment lines); classification still true | yes |
| B9 | INFO | DoD / review-a.md:231–233 | snapshot-a e2e evidence (19:12) predates the fix commit (19:56); this delta is comment-only — no e2e owed for it | yes |
| B10 | INFO | tests/unit/test-update-flags.sh:618–628 | DH pins eval shipped lines calling host `cut` un-stubbed — harness precedent, stub-fed input | yes |
| B11 | INFO | test-status.sh:1432–1442, test-update-flags.sh:581–592 | composed idfail pins pass under `|| echo 1`→`|| true` by design; the value pins carry the discrimination | yes (S2/S3) |

Counters: **0 HIGH · 1 MED · 2 LOW · 8 INFO.** No ghosts; three severity
adjustments during main-agent verification (axis LOW→INFO: trailing-
comment over-match, recipe completeness, fail-message diagnostic —
rationale in each block).

## Per-finding detail

### B1 (MED) — the pin-tightening class sweep stopped one file short

- **Mechanism:** the wave tightened the three V14 pins that guard the
  management scripts (test-install-args.sh sibling loop :229,
  test-uninstall.sh :502, test-update-flags.sh :603) but left the
  fourth same-shape pin — install.sh's own, 15 lines above the loop
  (test-install-args.sh:212) — on the old trailing-slash-only negation
  `! grep -q '/home/\$DEFAULT_USER/'`. A functional slash-less site
  reintroduced into install.sh — `[ -d "/home/$DEFAULT_USER" ]`, the
  old update.sh gate's exact form — passes that pin green while the
  identical shape fails all three sibling pins.
- **Claim at stake:** the resolution records "L2 sweep of the *pins*,
  not just the finding's site — the class here is a too-narrow negative
  grep" and "All three same-shape sibling pins tightened" — a fourth
  same-shape pin exists in the same suite and was not swept
  (`grep -rn '/home/\\\$DEFAULT_USER' tests/unit/` — four negative
  sweep sites, three tightened).
- **Live tree:** clean — install.sh's only slash-less occurrence is the
  initializer at :615 (sanctioned: positively pinned verbatim at :210,
  overwritten by getent on the next line); the exposure is
  future-regression detection, exactly like a T1's was.
- **Provenance:** pin shape pre-existing (0.0.44a, `f48b8eb`); the
  incomplete sweep and the closure claim ship with this wave.
- **Fix direction:** same subtraction trick, install-specific —
  subtract comments and the verbatim initializer line
  (`^\s*DEV_HOME="/home/\$DEFAULT_USER"$`), flag everything else.

### B2 (LOW) — the sweep grep misses brace/mid-quote spellings

Probe-verified: `X="/home/${DEFAULT_USER}/.config"` and
`Y="/home/"$DEFAULT_USER"/.config"` both pass the sweep pipeline green
(the literal pattern `/home/\$DEFAULT_USER` matches neither). The commit
message and the new code comments say the pins "flag ANY
/home/$DEFAULT_USER form" — true for every slash variant of the literal
spelling, not for shell-legal alternative spellings. No occurrence in
`files/` today; the historical bug form and the house style are the
unbraced spelling, so the realistic regression vector stays covered.
Fix direction: weaken the wording ("any form of the literal") or extend
the pattern (`\$\{?DEFAULT_USER\}?` catches braces). — pattern gap
pre-existing (the old trailing-slash pin had it too); the overstated
claim is wave-introduced.

### B3 (LOW) — the resolution's sabotage record misdescribes two runs

Measured on the real tree (matrix below):

- "reintroduced that exact line into status.sh → **all three suites
  FAIL**" / table row "**3× FAIL (T1 pins)**": a status.sh-only mutation
  trips exactly ONE T1 pin (test-install-args' status row) plus six
  *collateral execution* FAILs in test-status.sh (the inserted line runs
  inside the extracted hook block); test-uninstall and test-update-flags
  grep their own files and stay GREEN. Three FAILs per suite happen only
  with three per-file mutations.
- "fallback line deleted from update.sh → **both DEFAULT_HOME arms
  FAIL**": deletion makes the 2-line extraction count 1≠2, so the
  *precondition* pin ("resolution lines extractable") fails and the two
  arm assertions never run — one red, not two.

Red is red in both cases (the suites exit 1; discrimination itself is
real — verified), but the ledger the next review audits describes runs
that were not executed as recorded. Correction is bookkeeping-only
(resolution evidence wording), no code. — wave-introduced.

### B4 (INFO, axis LOW upheld→downgraded) — trailing-comment over-match

The subtraction `|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$` is
EOL-anchored; a future legit edit like
`… || DEFAULT_HOME="/home/$DEFAULT_USER"  # passwd-miss fallback` would
be flagged → suite red with the line printed. Fail-loud direction only
(no missed regression possible); triage cost ~minutes. Downgraded from
the axis LOW: no wrongness exists today and the failure self-explains.

### B5 (INFO) — "five pins" counts blocks, not assertions

The diff adds 5 pin blocks with 6 executed pass rows (status composed +
status value, update composed + update value, DEFAULT_HOME miss + hit)
plus 1 extraction precondition. Every claimed fallback arm is executed
and the two value pins discriminate (S2/S3 below) — the claim's
substance holds; granularity note only. Same for "the three V14
sibling-sweep pins" = 3 pin sites / 5 executed pins (loop ×3 + 2
standalone) — the resolution's three-file list matches the diff.

### B6 (INFO, axis LOW downgraded) — create-a-user recipe scope

`useradd -m -G sudo` presumes the Debian/Ubuntu sudoers group — correct
for every distro the kit's own distro gate supports (Ubuntu 24.04/22.04,
Debian 12; Arch/Alpine WSL images abort at that gate regardless, so the
recipe's portability cannot strand a supported install). Not named: how
to *enter* the new account (`wsl -d <distro> -u <name>`, `su - <name>`,
or the WSL default-user setting) — the reader's next root terminal
re-hits the gate message. Convenience gap, commands correct as written.

### B7 (INFO, axis LOW downgraded) — missing survivor diagnostic

test-install-args.sh:234 and test-update-flags.sh:610 append
`(${_bad:-no getent})` to their fail messages; test-uninstall.sh:510
does not — on a real regression the uninstall pin reports red without
the surviving line. Debuggability asymmetry introduced in one commit;
the pin still fails loud and names its subject.

### B8 (INFO) — stale line cite in the resolution

"install.sh:612 (initializer …)" — the wave's own +3 comment lines
shifted it to :615. Classification (getent-overwritten initializer,
outside the pinned files) still true at the new line.

### B9 (INFO) — e2e evidence vs this delta

Snapshot a's e2e logs (19:12, 303/303 + 47/47) cover the wave code but
predate the fix commit (19:56). This delta changes install.sh
comment-only plus tests/docs — no semantics, no e2e owed for it
(pr-00189 b precedent); the branch-level suites remain the merge gate
(maintainer).

### B10 (INFO) — eval calls host `cut`

The `_dh_arm` subshell stubs `getent` but not `cut`; the eval'd shipped
lines resolve `cut` from the host PATH. Stub-fed input, harness-wide
precedent, fail-loud if absent. No action.

### B11 (INFO) — division of labor is real and documented

Under `|| echo 1`→`|| true`, the composed idfail pins still pass (empty
uid ≠ "0" → the normal arm) — only the sentinel-value pins catch it.
That is exactly why both exist; the commit message says so ("composed +
sentinel-value pins, '|| true' fails on the empty value"). Recorded so
the next reviewer does not re-flag the composed pins as vacuous.

## Verified clean (all axes, main-agent-verified)

- **a T1 implementation:** the three tightened pipelines subtract
  exactly the three real fallback lines (status.sh:532, update.sh:447,
  uninstall.sh:296 — all `|| var="/home/$DEFAULT_USER"` at EOL) and the
  two comments; live pipelines yield zero survivors; the old gate shape
  fails each pin in its own file (S1/S5/S6 below, agents' /tmp probes).
- **a T2 implementation:** all six fallback assertions execute and pass;
  `id()` stubs differ from the old only for empty uid (rc 1, silent) and
  non-`-u` args — every pre-existing `_hk_run` call site enumerated
  (status: 0/1000×4; update: 0/1000×2), none changes meaning;
  `^ *_st_dev_uid=`/`^ *_du_uid=` match exactly one line each; the DH
  sed patterns match exactly the two live lines; `wc -l`=2 fails loud
  on 1, 0, or 3 matches.
- **L4:** every new pin block sits before its suite's summary gate; no
  new FAIL path exits 0.
- **L7:** the three `|| true` guards are required (last `grep -v` rc 1
  on empty) and present; all captures `_rc=0; _out=$(…) || _rc=$?`;
  `fail()` is echo-based — no format-string hazard from interpolated
  grep output.
- **Sandbox:** new writes only `mkdir -p`/`printf` into suite `WORK`
  (mktemp); sandbox-policy suite green.
- **a T3 / a W1 docs:** uninstall refusal chain verified (uninstall.sh
  whoami → root/opencode refusal before install.conf; bin/opk execs as
  invoker) — "refuses to start from a root shell" is exact; no
  contradictions with getting-started or security-model.
- **a S1 comment:** `sudo env SUDO_USER=…` override and
  "deliberately not defended" match the code
  (`${SUDO_USER:-$(whoami)}` read unsanitized); `(#196 a S1)` is the
  house citation form.
- **install.sh diff is comment-only;** extraction anchors
  (`^_root_user_gate() {`, grep-based order pin) unaffected — suites
  green.
- **Bookkeeping:** resolution rows ≤120 cols, three disposition verbs
  only, SHAs not branch names, 10/10 findings dispositioned; 83d3076's
  edit to review-a.md is exactly the 2-line Resolution pointer.

## Sabotage matrix (main agent, real tree @ 83d3076, restored green after each)

| Mutation | Result |
|---|---|
| status.sh + old-gate line | test-install-args FAIL (V14 status row, line quoted) + 6 collateral FAILs in test-status (line executes in the extracted block); uninstall/update suites GREEN |
| uninstall.sh + old-gate line | test-install-args + test-uninstall FAIL (both quote the line) |
| update.sh + old-gate line | test-install-args + test-update-flags FAIL (both quote the line) |
| status.sh `\|\| echo 1` → `\|\| true` | FAIL: status sentinel-value pin (out empty) — exactly one |
| update.sh `\|\| echo 1` → `\|\| true` | FAIL: update sentinel-value pin — exactly one |
| update.sh fallback line deleted | FAIL: "DEFAULT_HOME resolution lines extractable" (arms never run — B3(ii)) |
| restored | all four suites rc=0 |

## Run provenance, gates, environment

- **Agents:** 2 fresh-context GLM-5.3-Flash axis subagents (mechanical
  → MB1–MB4, claims/docs → CB1–CB9), ~8 min budget each, checkpointed
  to `/tmp/opencode/pr00196-review-b/{mechanical,claims}.md`; main agent
  (GLM-5.3) verified every finding (full-file reads, live greps, the
  sabotage matrix above, brace/trailing-comment probes) and applied the
  three severity adjustments noted. No fixing while verifying.
- **Gates run:** `make test` — all green (incl. the four touched suites,
  reviews lint + parity 15 cases, sandbox policy); `make lint` green;
  `make check-version` green (0.0.51).
- **e2e:** not run for this delta (comment-only install.sh change +
  tests/docs — not owed; B9). Branch-level e2e at merge is the
  maintainer's gate.
- **Environment:** WSL2 host; opencode 1.18.15 pinned reference;
  sabotage logs in `/tmp/opencode/pr00196-review-b/sab-*.log`.

## Recommendation

The fixes did what a T1/a T2/a T3/a W1/a S1 claim and broke nothing;
merge is blocked only by taste for how far the pin class should close.
Before merge (each a small test/docs-only change): **B1** — tighten the
fourth same-shape pin with the initializer subtraction; B2 may ride the
same edit (pattern or wording). **B3/B8** — correct the two sabotage
rows and the line cite in the resolution (bookkeeping, loop-neutral).
Stop rule: if B1 is fixed (test code), one more micro-wave pass (c) is
owed; if B1 is dispositioned deliberately-not-done, this round's
dispositions touch no review-relevant code and the chain closes at b.
