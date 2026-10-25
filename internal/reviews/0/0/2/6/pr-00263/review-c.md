<!-- review-meta
ID: pr-00263
Snapshot: c
Subject: external redundancy pass — GPT 6 Luna (high effort), release 0.0.57 full scope
Scope: full
Base: 0.0.57 @ 4eacabb
Diff: c979654..c38f9e5 (same material as snapshot a: tag 0.0.56..master, 101 files; reviewed tree release/0.0.57 @ 4eacabb)
Date: 2026-10-25
Reviewer: GPT 6 Luna (opencode/gpt-6-luna#high) — external pass on a bias-reduced sparse checkout (agent/, .agents/, internal/ excluded per internal/process/review.md "External review machines"), commissioned as a plain prompt WITHOUT opencode's /review template (accidental omission — see Commissioning); main review + 8 sub-agent passes, same model; ~15 min session; commissioned and handed over by the maintainer; per-finding verification by the GLM-5.3 house session (pr-00263)
Skills: none for the external pass (sparse checkout without house skills — the independence is the commissioning setup); the integrating house session ran opk-review-pass
-->

# External redundancy pass — pr-00263 snapshot c — GPT 6 Luna (high)


Third snapshot of the release review (a: house pass; b: external
GPT 6 Luna medium). Same bias-reduced setup as b — sparse checkout without
`agent/`, `.agents/`, `internal/`, no house skills — at the high effort
variant of the same model family. The report below is the external pass's
output verbatim; the house session (GLM-5.3) re-verified every finding on
the full tree. Verification marks, house severity mapping and provenance
dating are house-added.

**Post-hoc marking (maintainer decision, 2026-10-25): C7 is PROVEN BUT
FALSE** — the technical observation holds, but the defect claim is false:
issue #252 (the ticket behind the #256 shortening) and the PR #256 body
name this removal as deliberate ultra-legacy policy. Dispositioned
deliberately not done in the resolution (same basis as snapshot b's B1).

Session data (maintainer-provided where the model cannot know it): model
`opencode/gpt-6-luna#high` (high effort variant), main review plus 8
sub-agent passes on the same model, ~15 minutes, API cost **$0.31**
(maintainer-supplied figure). Host preflight passed; no test suites run
(as requested); no repository files modified.

## Findings index

| ID | Reported as | Sev (house) | Location | One-line summary | Verified |
|---|---|---|---|---|---|
| C1 | P2 | LOW | sh/fs-baseline.sh:177-197 | The tee's `except (BrokenPipeError, KeyboardInterrupt)` also catches a stderr-side EPIPE (progress sink died) — same exit-0 path as consumer death, but it aborts the data stream (stdout → /dev/null) instead of degrading progress only | yes (code read; stream-direction nuance in verification notes) |
| C2 | P2 | MED | bin/opk:321-332 | The settings-edit failure branch prints `ui_error` but never exits nonzero — the arm falls through to `ui_detail` and the command exits 0 while the settings pin remains | yes (code read; pre-existing since 0.0.48 — and a correction of house a's B-axis clean verdicts) |
| C3 | P2 | MED | docs/reference/cli.md:107-112 vs bin/opk:481-519, 585-605 | The handover guide claims "every path component is re-checked immediately before the iteration acts" — `opk handover` has policy/form/leaf gates but no component walk (that is the ddev-handover.sh scan loop's #234 gate) | yes (code read both sides; sentence is new in-range) |
| C4 | P2 | LOW | docs/reference/cli.md:105-112 (impl. comment opk:573-580) | The guide dropped the accepted-residual caveat (pre-arranged group/world-writable paths stay agent-writable in either pass order) while keeping the stronger "a planted link cannot steer them" | yes (0.0.56 cli.md:137-139 carried it) |
| C5 | P2 | MED | docs/concepts/security-model.md:74-80 vs install.sh:1964-1971 | The trust list lost the root-run `opencode.ai/v2/install` source (official installer, npm resolution) that 0.0.56's text still named | yes (0.0.56 security-model.md:87-89 had it) |
| C6 | P2 | MED | docs/getting-started.md:125-132 vs install.sh:1691-1714 | "their databases were exported" is now unconditional — the skip paths (--skip-ddev-migration, Advanced-mode decline, no configured roots, prior DDEV_EXPORTED stamp) lost their caveat | yes (0.0.56 getting-started.md:187-191 had the conditions) |
| C7 | P2 | ~~LOW~~ RETRACTED | docs/how-to/update.md:45-47 | ~~Update instructions omit the one-time pre-0.0.29 migration~~ — deliberate #252/#256 ultra-legacy removal (= snapshot b's B1) | retracted (deliberate #252 removal) |
| C8 | P3 | MED | docs/getting-started.md:9-11 vs install.sh:543-585, 731-737 | Prerequisite wording blurs the install gate vs the baseline fallback — identical defect to house snapshot a's F5, found independently; severity divergence recorded (external P3, house MED) | yes (= a F5) |
| C9 | P3 | LOW | docs/reference/files.md:76-79 vs bin/opk:211-217 | "a file with other content is admin-owned and never overwritten" reads absolute, but `opk openchamber-secure` announces and replaces divergent content — pages conflict under the absolute reading | yes (0.0.56 files.md carried no such sentence — delta) |
| C10 | P3 | LOW | docs/reference/cli.md:301-305 vs status.sh guards | "a missing kit library file" generalizes — status has explicit guards for the selected helper families only (the #165 five-site set), no generic deploy integrity check | yes (0.0.56 cli.md:389-401 enumerated the families; the enumeration was dropped) |
| C11 | P3 | LOW | docs/reference/cli.md:296-305 vs status.sh:92-108 | Exit-code docs omit the deliberate pre-install exception (full mode exits 0, --short exits 1 when the kit is not installed) | yes (status.sh:105-108 documents the exception in-code) |

Severity mapping (house): C2, C3, C5, C6, C8 → MED (C8 matching
snapshot a's F5 rating; the external P3 on it is recorded as a severity
divergence, not a downgrade); C1, C4, C7, C9, C10, C11 → LOW. Counts as
verified: **5 MED, 6 LOW**. Provenance: C1 delta-introduced (the tee is
the in-range #223/#244 wave); C2 pre-existing since 0.0.48 (fd93fbe,
openchamber-secure Tier 3 — the in-range #244 g-wave fixed the Python
side, not the shell exit code); C3–C7, C9–C11 delta-introduced (all but
C1/C2 are #256-shortening removals or rewrites).

## Findings (external output, verbatim)

### C1 — [P2] Progress tee can silently stop a baseline on a broken stderr pipe

`files/opencode-permissions-kit-lib/sh/fs-baseline.sh:177-197`

The `try` catches `BrokenPipeError` from both the path stream (`stdout`)
and progress output (`stderr`). If a progress write/flush to stderr gets
EPIPE, the shared handler redirects stdout to `/dev/null` and exits
normally with status 0. `xargs` then receives a truncated stream and can
also return 0, so `pipefail` and `_fsbp_rc` do not detect that the root
baseline only applied to part of the tree. Handle stdout EPIPE separately;
a failed progress sink or interrupt must not report a successful pass.

### C2 — [P2] OpenChamber settings-edit error still gives the command a success status

`files/opencode-permissions-kit-lib/bin/opk:321-332`

When the grep finds `"opencodeBinary"` as a JSON value rather than a key,
the new Python branch exits 1 and the CLI prints an error, but execution
continues to `ui_detail` and the command exits 0. The settings pin
remains, while automation sees success. Propagate a nonzero result from
this failure branch.

### C3 — [P2] The handover guide claims per-component checks that `opk handover` does not perform

`docs/reference/cli.md:107-112`; implementation:
`files/opencode-permissions-kit-lib/bin/opk:481-519,585-605`

The rewritten guide says every path component is re-checked immediately
before acting and that symlinked paths are refused. The CLI canonicalizes
the operand for its policy check, rejects certain slash/dot forms, and
rechecks only whether the final raw operand is a symlink; it does not
walk/check parent components. A path through a symlinked parent can
therefore pass the described guard and make recursive operations resolve
elsewhere. The new documentation guarantee is not implemented.

### C4 — [P2] The handover guide drops the documented writable-tree residual

`docs/reference/cli.md:105-112`; implementation comment:
`files/opencode-permissions-kit-lib/bin/opk:573-580`

The previous guide warned that pre-existing group- or world-writable paths
can remain agent-writable during a handover, regardless of operation
order. That accepted residual was removed while the shortened text
describes the ordered passes and says a planted link cannot steer them.
Restore the caveat so users do not mistake the ordering for an atomic or
complete write-access revocation.

### C5 — [P2] Security-model supply-chain summary omits a root-run installer source

`docs/concepts/security-model.md:74-80`; implementation:
`files/install.sh:1964-1971`

The revised trust list names GitHub, OpenCode releases, and
get.docker.com, but omits the optional official installer fetched from
`https://opencode.ai/v2/install` and piped to `bash` in the root install
context. That script also resolves the binary through npm. Add this source
to the stated trust assumptions.

### C6 — [P2] Getting-started guide overstates whether prior ddev databases were exported

`docs/getting-started.md:125-132`; implementation:
`files/install.sh:1691-1714,1751-1761`

The guide now says prior-project databases "were exported" without the
former opt-out/decline caveat. Export can be skipped with
`--skip-ddev-migration`, when there are no configured roots, or by
declining the Advanced-mode prompt; failed exports can also be accepted
under `--yes`. Those databases can remain reachable only through the old
daemon after handover. State the conditions and direct users to verify
dumps before proceeding.

### C7 — [P2] Update instructions omit the one-time pre-0.0.29 migration — **RETRACTED**

> Post-hoc marking (maintainer, 2026-10-25): deliberate #252/#256 removal.
> Dispositioned deliberately not done; see the resolution (= snapshot b's B1).

`docs/how-to/update.md:45-47`; implementation note:
`files/opencode-permissions-kit-lib/management/update.sh:116-120`

The guide says updates work from 0.0.14 onward and directs users to the
normal update path, but removes the one-time layout migration
instructions. An installed updater from 0.0.14–0.0.28 still uses the old
file list and fails with 404; users must stream the current updater once.
Restore that exception and command.

### C8 — [P3] Getting-started prerequisite wording blurs Python's install gate and baseline fallback

`docs/getting-started.md:9-11`; implementation:
`files/install.sh:543-585,731-737`

The prerequisite says the installer probes for missing/broken `python3`,
then says the baseline still applies without it. The baseline helper does
degrade without Python, but installation itself exits before applying it
when Python is absent or unhealthy. Clarify that distinction to avoid
implying an install can proceed without a working interpreter.

### C9 — [P3] Files reference overstates OpenChamber policy preservation

`docs/reference/files.md:76-79`; implementation:
`files/opencode-permissions-kit-lib/bin/opk:211-217`

The reference says a policy file with other content is "never
overwritten," although `opk openchamber-secure` announces and replaces
divergent content. `docs/reference/cli.md` describes the explicit
replacement, so the pages conflict. Scope the preservation statement to
install/update and repeat the explicit command's behavior.

### C10 — [P3] Status documentation implies every missing library file gets a warning row

`docs/reference/cli.md:301-305`; examples of the checks actually
implemented: `files/opencode-permissions-kit-lib/management/status.sh:373-376,839-847,996-1002`

The shortened wording generalizes from specific status checks to "a
missing kit library file." Status has explicit guards for selected
helpers, not a generic integrity check of the deployed library (for
example, it does not check `sh/fs-baseline.sh`). A damaged deploy can
therefore lack a row for a missing file. Scope the claim to the checked
helpers or add a generic check.

### C11 — [P3] Status exit-code documentation omits the pre-install full-report exception

`docs/reference/cli.md:296-305`; implementation:
`files/opencode-permissions-kit-lib/management/status.sh:92-108`

The guide says the full report uses the documented verdict codes but
omits that, before installation, full mode intentionally exits 0 while
`--short` exits 1. The direct checkout invocation is documented as working
before install, so scripts relying on the full-report status can mistake
absence for success. Restore the exception and recommend `--short` when
absence must fail.

## Verification notes (house session)

- **C1** — code-verified (fs-baseline.sh:167-200): the single
  `except (BrokenPipeError, KeyboardInterrupt)` covers both streams; a
  stderr EPIPE takes the consumer-death path (exit 0, stdout → devnull)
  and aborts the data passthrough. Two directions recorded for the fix:
  the common case fails LOUD (the tee stops reading, still-running find
  dies on SIGPIPE, pipefail fails the pass) — a broken progress sink
  kills the run; the false-green race (find already finished, buffered
  bytes lost, xargs EOF, all rc 0) needs that timing. The stdout-EPIPE
  direction is the documented deliberate-0 contract
  (fs-baseline.sh:186-195) and must be preserved by any fix — separate
  the streams, do not remove the handler. LOW (narrow trigger, mostly
  fail-loud).
- **C2** — code-verified (opk:321-333): the else branch prints two
  `ui_error` lines and sets no status; the arm continues to `ui_detail`
  (:332) and the subcommand's last command decides the exit code — 0.
  Dating: the shape originates with the openchamber-secure command
  (fd93fbe, first shipped 0.0.48); the in-range #244 g-wave fixed the
  Python-side false success (`sys.exit(1)`) but the shell side still
  swallows it. **This corrects house snapshot a**: both B-axis twins
  verified the branch as "fail-closed" — each checked the Python exit
  and the error message, neither checked the shell's exit code after the
  branch. MED: a shipped CLI command reports failure in prose and
  success in its exit status — the exact contract agent/conventions.md
  "Script output style" states ("report commands carry their verdict in
  the exit code").
- **C3** — verified on both sides: cli.md:110-112 asserts per-component
  re-checks "immediately before the iteration acts"; `opk handover`'s
  own gates (opk:479-520: realpath-canonicalized policy blocklist,
  raw-operand slash/dot form gate, existence check; :585-609: leaf
  `[ -L ]` + `find ! -type l` + `chown -R -h`) contain no component
  walk. The per-component walk is the #234 gate in ddev-handover.sh's
  `.ddev` scan loop — a different code path the sentence was
  transplanted onto. The 0.0.56 cli.md carries no "re-checked
  immediately" wording — the sentence is new in-range. MED
  (security-guarantee claim the command does not implement).
- **C4** — verified: 0.0.56 cli.md:137-139 carried the residual
  ("mode-based write paths the agent pre-arranged … stay agent-writable
  during the run in either order"); current cli.md:105-112 keeps the
  ordering claim without it, while opk:573-580 still documents the
  residual in-code. LOW (disclosure regression adjacent to C3).
- **C5** — verified: 0.0.56 security-model.md:87-89 explicitly named the
  fallback installer ("streams `https://opencode.ai/v2/install` (the
  official v2 installer, npm-registry resolution) — both as root"); the
  current trust list (:74-81) names GitHub, the opencode releases and
  get.docker.com only. A root-executed fetch source dropped from the
  trust-model reference. MED.
- **C6** — verified: current getting-started.md:125-127 states the
  export as fact; 0.0.56 :187-191 carried "(Standard mode exports
  automatically after you confirm the plan; Advanced mode asks first;
  `--skip-ddev-migration` opts out)"; install.sh:1691-1713 confirms all
  skip paths plus the prior-run stamp. MED (unconditional data-existence
  claim).
- **C7** — verified, identical to snapshot b's B1 (both external passes
  found it independently; see b's verification notes for the 0.0.56
  section proof). LOW (house mapping). [RETRACTED — deliberate #252/#256
  ultra-legacy removal (= snapshot b's B1); see the post-hoc marking in
  the intro.]
- **C8** — verified; this is house snapshot a's F5, found independently
  by a setup with zero shared context (convergence on existence).
  Severity divergence recorded: the external P3 ("wording blurs") vs
  the house MED (a Prerequisites entry that tells users without a
  healthy python3 that install degrades — while both probe arms
  `exit 1`). The house rating stands (a's F5); the divergence is
  calibration data, not a downgrade.
- **C9** — verified: opk:210-217 announces and replaces divergent
  policy.json ("this explicit command DOES replace divergent content
  (that is its job) — but never silently"); files.md:76-79's "never
  overwritten" reads absolute next to it. 0.0.56 files.md carried no
  such sentence — the ambiguity is delta-born. LOW.
- **C10** — verified: the status guards are the #165 five-site family
  (advisories, ddev-terminal hook, migration-gap, hosts, share-scan,
  plus the git floor) — no generic deployed-library check
  (`sh/fs-baseline.sh` missing produces no row). 0.0.56 cli.md:389-401
  ENUMERATED the covered families; the current sentence generalizes.
  LOW.
- **C11** — verified: status.sh:92-108 — full mode exits 0 pre-install
  by design ("status.sh is a diagnostic that must not 'fail' for
  reporting absence"), `--short` exits 1; cli.md:296-298 states the
  codes unconditionally. 0.0.56 cli.md:416-418 at least flagged
  "works before an install … reports 'NOT active'". LOW.
- One finding is RETRACTED: C7 (= snapshot b's B1) — the technical
  observation holds, but the defect claim is false (a deliberate #256
  ultra-legacy removal per issue #252; see the post-hoc marking in the
  intro). One house-verdict correction (C2), one severity divergence
  recorded (C8), one duplication across external snapshots (C7 = B1).

## Run provenance

- **Pass**: external machine, bias-reduced sparse checkout
  (`agent/`, `.agents/`, `internal/` excluded per
  internal/process/review.md). Model `opencode/gpt-6-luna#high`, high
  effort variant, main review plus 8 sub-agent passes on the same model;
  ~15 minutes; no repository files modified; host preflight passed; no
  test suites run (per the commissioning recipe).
- **Commissioning** (completed after the initial integration, when the
  maintainer verified the launch commands — recorded as the marked
  correction it is, not as if known from the start; the snapshot commit
  was amended pre-force-push for exactly this): started as a plain
  prompt WITHOUT opencode's built-in `/review` — the command prefix was
  accidentally omitted, so NO review template was loaded (a deviation
  from the process/review.md recipe; the independence axes — different
  model family, sparse checkout, no house skills — all held regardless).
  The prompt pinned the model (GPT 6 Luna high, sub-agents explicitly
  same model), instructed the pass to note model and session duration in
  its report, and set a ~15-minute budget: c's reported duration follows
  that instruction where b's was self-estimated — the two durations are
  not like-for-like.
- **Cost**: $0.31 (maintainer-provided billing figure).
- **Commissioning + hand-over**: maintainer, 2026-10-25, same recipe as
  snapshot b. Embedded verbatim and per-finding verified by the house
  session (GLM-5.3; opk-review-pass loaded for the integration
  choreography only) on the full tree at 4eacabb, porcelain-clean.
- **Provenance split (finding level)**: delta-introduced C1, C3, C4,
  C5, C6, C7, C8, C9, C10, C11 (nine of them #256-shortening
  regressions, one #223/#244 tee arm); pre-existing C2 (0.0.48,
  fd93fbe).

## Calibration (vs snapshots a and b)

- **What c found that a missed: ten** (C1–C7, C9–C11). Two are code
  findings over house false-cleans: C1 (the tee's stderr-EPIPE arm —
  house a's C-axis twins verified the documented rc-contract directions
  only) and, sharpest, **C2 — a correction of house a**: both B-axis
  twins called the settings-edit branch fail-closed; both verified the
  Python heredoc's `sys.exit(1)` and the printed error, neither the
  shell exit code. The external pass checked what automation observes:
  the command's status. That is the third house false-clean the
  external setup caught (after E1's getting-started sentence and E2's
  citation sweep, both recorded in snapshot a).
- **Convergence across independent setups**: C8 = a's F5 (house +
  external-high, zero shared context — the finding is real beyond
  doubt); C7 = b's B1 (external-medium + external-high). The two
  external passes otherwise found disjoint docs findings (b: daemon.json
  prose, WSL recovery entry, container-tools caveat, hosts mapping; c:
  handover claims, trust list, export caveat, files.md, status docs) —
  with the commissioning correction recorded above, the two passes
  differ in effort variant AND in template presence AND in time-budget
  instruction, so no single axis explains where each pass's yield sat.
- **Severity divergence**: C8 reported P3 (the external's minor tier),
  house-rated MED in snapshot a — the external read a wording blur, the
  house a prerequisites contradiction of a hard gate. Both descriptions
  are accurate; the difference is the release-gate framing the house
  scale carries.
- **Cost/yield datum — effort attribution withdrawn** (commissioning
  correction): the high-effort pass cost less ($0.31 vs $0.42), ran
  shorter (~15 vs ~28 min — though c's duration followed a commissioned
  budget while b's was self-estimated), used fewer agents (8 passes vs
  16) and yielded more findings (11 vs 6) than the medium-effort pass.
  The original version of this paragraph attributed that difference to
  the effort variant; with the commissioning facts completed above, the
  two passes also differ in template presence (the /review template was
  loaded for b, not for c) and in time-budget instruction — three axes
  varied together, one measurement each, so the difference cannot be
  attributed to effort alone. The raw numbers stand; only the
  attribution is withdrawn.
- **What a found that c missed: all 27** of a's findings (the five code
  MEDs, the sweep-gap classes, the L5 inventory, the citation/pin
  classes). The externals' yield concentrates on the user-facing
  surface; the house yield on code, security and process classes. The
  three snapshots are near-complementary: combined unique findings
  27 + 6 + 11 − 1 (C8=F5) − 1 (C7=B1) = **42**.
