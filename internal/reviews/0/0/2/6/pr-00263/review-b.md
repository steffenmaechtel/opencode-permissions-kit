<!-- review-meta
ID: pr-00263
Snapshot: b
Subject: external redundancy pass — GPT 6 Luna (medium effort), release 0.0.57 full scope
Scope: full
Base: 0.0.57 @ 4eacabb
Diff: c979654..c38f9e5 (same material as snapshot a: tag 0.0.56..master, 101 files; reviewed tree release/0.0.57 @ 4eacabb)
Date: 2026-10-25
Reviewer: GPT 6 Luna (opencode/gpt-6-luna#medium) — external pass on a bias-reduced sparse checkout (agent/, .agents/, internal/ excluded per internal/process/review.md "External review machines"), commissioned via opencode's built-in /review command (review template loaded, per the recipe); 16 sub-agents, same model; ~28 min session; commissioned and handed over by the maintainer; per-finding verification by the GLM-5.3 house session (pr-00263)
Skills: none for the external pass (sparse checkout without house skills — the independence is the commissioning setup); the integrating house session ran opk-review-pass
-->

# External redundancy pass — pr-00263 snapshot b — GPT 6 Luna (medium)


Second, independent snapshot of the release review (first: snapshot a, the
house pass). Setup per internal/process/review.md: a sparse checkout that
excludes `agent/`, `.agents/` and `internal/` (no house review memory), a
different model family (GPT 6 Luna), no house skills. The report below is
the external pass's output; the house session (GLM-5.3) re-verified every
finding against the code and docs of the full tree — verification marks and
the house severity mapping are house-added, the finding bodies are verbatim.

**Post-hoc marking (maintainer decision, 2026-10-25): B1 (001) and B4
(004) are RETRACTED** — the technical observations hold, but the
defect claims are false: issue #252 (the ticket behind the #256
shortening) and the PR #256 body name exactly these removals as
deliberate ultra-legacy policy ("how to update from 0.0.x to 0.0.y … we
can remove old legacy stuff"; "remove ultra-legacy update paths: the
one-time >= 0.0.29 layout migration section, the kit-0.0.36 wsl.conf
parse-error entry"). The sparse checkout could not see the recorded
intent; both are dispositioned deliberately not done in the resolution.

Session data (maintainer-provided where the model cannot know it):
model `opencode/gpt-6-luna#medium` (medium effort variant), 16 sub-agents
on the same model, ~28 minutes session duration, API cost **$0.42**
(maintainer-supplied figure — the reviewer model has no access to its own
billing). Host preflight passed; no test suites run (as requested); the
working tree stayed clean. The external pass compared candidate findings
against 0.0.56 and excluded pre-existing behavior where it determined so
(its README states this filter).

## Findings index

| ID | Reported as | Sev (house) | Location | One-line summary | Verified |
|---|---|---|---|---|---|
| B1 | P2 | ~~LOW~~ RETRACTED | docs/how-to/update.md:45-47 (0.0.56 had :63-78) | ~~The one-time 0.0.14–0.0.28 layout-migration section was removed~~ — deliberate #252/#256 ultra-legacy removal | retracted (deliberate #252 removal) |
| B2 | P2 | LOW | sh/fs-baseline.sh:157-159 | The python3-less `cat` passthrough ends in unconditional `return 0` — cat's rc is discarded, a read error truncates the operand stream with all pipeline members green | yes (code read; nuance: the 0 also mirrors the tee's deliberate consumer-EPIPE contract — see verification notes) |
| B3 | P2 | MED | docs/troubleshooting.md:95-104 | Prose says an existing daemon.json "gets the key merged in — do not overwrite the file" and the very next command is `sudo tee` over it — truncation by following the docs | yes (code read; pre-existing shape — 0.0.56 carried the same contradiction, reworded in-range) |
| B4 | P2 | ~~MED~~ RETRACTED | docs/troubleshooting.md (entry removed; 0.0.56 had it at :539-560) | ~~The recovery entry for the malformed 0.0.36 WSL section was deleted~~ — deliberate #252/#256 ultra-legacy removal | retracted (deliberate #252 removal) |
| B5 | P3 | LOW | docs/how-to/container-tools.md:18-22 (0.0.56 had the caveat at :22-25) | The guide dropped the condition that an unavailable `opencode debug config` probe makes the wrapper fall back to the project config only — a global-only allow is then not detected | yes (0.0.56 text + opencode-as-opencode:418-422, 467-478) |
| B6 | P3 | LOW | docs/troubleshooting.md:327-329 + docs/concepts/ddev-integration.md:253-259 | Both manual-fallback passages now say only "edit the hosts file" — the required `127.0.0.1 <project>.<tld>` mapping (present at 0.0.56, and what the bridge itself writes) is gone | yes (0.0.56 troubleshooting.md:427 + bridge behavior) |

Severity mapping (house): the external P2/P3 scale maps per finding during
verification — B3/B4 carry realistic user harm on the docs surface (MED);
B1/B2/B5/B6 are narrow-trigger or remedy-adjacent (LOW). Counts as
verified: **2 MED, 4 LOW**. Provenance: B1, B4, B5, B6 delta-introduced
(the #256 shortening removed the material); B2 delta-introduced (the cat
arm is part of the in-range #223/#244 tee); B3 pre-existing (0.0.56
:141+:156-158 carried the same tee-vs-merge contradiction, reworded
in-range).

## Findings (external output, verbatim)

### B1 — [P2] Document the required one-time migration for 0.0.14–0.0.28 — **RETRACTED**

> Post-hoc marking (maintainer, 2026-10-25): deliberate #252/#256 removal
> ("ultra legacy, how to update from 0.0.x to 0.0.y … we can remove old
> legacy stuff"). Dispositioned deliberately not done; see the resolution.

**Location:** docs/how-to/update.md:45-47

For installs at kit versions **0.0.14–0.0.28**, the guide now says updates
are supported from 0.0.14 and directs users to run `opk update`. That path
is not sufficient for these versions: their installed updater uses the
pre-0.0.29 file layout and fails while fetching obsolete paths (404). They
must run the current updater as a streamed script once to migrate to the
reorganized layout; only then does ordinary `opk update` work.

As written, users in this version range are told their update path is
supported but are not told the required migration command, so following the
guide fails. Restore the one-time migration instructions (or otherwise
distinguish the 0.0.14–0.0.28 path) and direct users to the streamed update
entry point.

The current updater confirms this constraint in
`files/opencode-permissions-kit-lib/management/update.sh:116-120`.

### B2 — [P2] Preserve the passthrough command's failure status

**Location:** files/opencode-permissions-kit-lib/sh/fs-baseline.sh:157-159

When Python is missing or fails the health probe, `_fsb_count_tee` runs
`cat` to forward the NUL-delimited file list, then unconditionally returns
success. If `cat` encounters a read error and forwards only part of the
list, the downstream `xargs` can consume the truncated stream and exit
successfully. The function masks `cat`'s nonzero status, so even the
production pipeline's `pipefail` sees success; `_fsb_pass` does not
increment `_FSB_ERRORS` and callers can report the group baseline as
applied although part of the tree was skipped.

Return `cat`'s status (or explicitly propagate a failed passthrough) so the
pass is marked incomplete. The Python-free fallback must preserve the
stream *and* its failure signal.

### B3 — [P2] Do not truncate the existing Docker daemon configuration

**Location:** docs/troubleshooting.md:95-100

The prose says an existing `daemon.json` should be merged and not
overwritten, but the prescribed `sudo tee .../daemon.json` truncates the
file before writing the example object. A user with existing daemon
settings (for example, a storage driver, registry configuration, DNS, or
proxy settings) loses them by following this command; restarting Docker may
then change behavior or fail.

Change the instructions to perform an actual key merge, or explicitly tell
users to merge the JSON manually and make the `tee` example safe only for a
file that does not already exist.

### B4 — [P2] Retain the recovery steps for the malformed 0.0.36 WSL section — **RETRACTED**

> Post-hoc marking (maintainer, 2026-10-25): deliberate #252/#256 removal
> (PR #256 body names "the kit-0.0.36 wsl.conf parse-error entry" under
> "remove ultra-legacy update paths"; #252: "remove historical infos").
> Dispositioned deliberately not done; see the resolution.

**Location:** docs/troubleshooting.md:425 — the section immediately before
this heading was removed.

This change deletes the troubleshooting entry for `wsl: Expected ']' in
/etc/wsl.conf` after kit 0.0.36. The shipped updater still strips that
legacy kit-owned section, but it does not restart WSL. On affected WSL
versions (up to 2.9.12), the malformed section can cause parsing to stop,
leaving settings below it unapplied; after the update removes the section,
users still need to run `wsl --shutdown` and reopen the distro for settings
such as `systemd=true` and the `/mnt/c` restriction to take effect. Without
the deleted recovery steps, users with this known failure lose the
instructions that restore their rootless backend and mount restriction.

Restore a concise troubleshooting entry that directs affected users to
update, then run `wsl --shutdown` from Windows and reopen the distro (and
retains the explicit opt-in instruction for older opencode versions if
still relevant).

### B5 — [P3] Retain the global-config fallback limitation in the container-tools guide

**Location:** docs/how-to/container-tools.md:18-22

The guide now says a broad allow counts "no matter which file declares it"
and can live in the opencode user's global config, but removes the prior
caveat for an unusable `opencode debug config` probe. In that case the
wrapper deliberately falls back to scanning only the project config
(`bin/opencode-as-opencode:418-422, 467-477`). A global-only allow is then
not detected and the rootless container backend is not attached, despite
the procedure in this section.

Restore the fallback condition and explain that users in this case need a
project-level rule (or a working merged-config probe) for detection.

### B6 — [P3] Give the actual hosts-file mapping in the manual fallback

**Locations:** docs/troubleshooting.md:327-329;
docs/concepts/ddev-integration.md:253-259

Both pages now say the manual fallback is to edit the Windows hosts file,
but omit the mapping users must add. When the kit's bridge cannot add a
hostname, merely opening/editing the file does not make the custom project
hostname resolve. The deleted troubleshooting text gave the needed
`127.0.0.1 <project>.<tld>` form, and the shipped bridge calls
`ddev hostname <name> 127.0.0.1`.

Restore the explicit mapping (and point users at the hostname list from
`ddev-hosts-check`) in both pages so the fallback can be completed without
guessing.

## Verification notes (house session)

- **B1** — verified both directions: the 0.0.56 guide carried
  "## Migrating to ≥ 0.0.29 (one-time, layout change)" (update.md:63-78 at
  0.0.56) with the streamed-updater command and the "From 0.0.29 onwards,
  `opk update` works again" note; the current file has no migration section
  (only the 0.0.29 pin examples). update.sh:116-120 states the breaking
  constraint verbatim. House severity LOW (not the external P2): the
  affected cohort is old and the docs' general remedy for failed updates —
  re-run the installer — does re-deploy the new layout; the harm is a
  confusing dead end, not data loss or a security gap.
  [RETRACTED — deliberate #252/#256 ultra-legacy removal; see the
  post-hoc marking in the intro.]
- **B2** — code-verified: `cat` then `return 0` (fs-baseline.sh:157-159).
  Verification nuance the fix must respect: the unconditional 0 also
  mirrors the python tee's deliberate consumer-EPIPE exit-0 contract
  (fs-baseline.sh:186-195) — a bare `return $?` would make a consumer that
  closes early fail the pass, diverging from the tee. The correct fix
  distinguishes the directions or accepts the consumer-death 0 while
  propagating read errors. Trigger is narrow (python3-absent host AND a cat
  read error), hence LOW.
- **B3** — verified; provenance corrected to pre-existing: 0.0.56's
  troubleshooting carried the same `sudo tee` example (:141) with a
  post-block "Merge the `default-address-pools` key in — do not overwrite
  the file" note (:156-158) — the contradiction is older than this range;
  the #256 shortening reworded it into the pre-block sentence but kept both
  halves. MED stands: following the printed command destroys existing host
  docker configuration while the adjacent prose forbids exactly that.
- **B4** — verified: current troubleshooting.md has no "Expected ']'"
  entry (grep empty); the 0.0.56 entry (read in full) carried cause, the
  `opk update ≥ 0.0.38` strip, the `opk wsl-add-opencode-1-fix` opt-in for
  opencode < 1.18.33, and the `wsl --shutdown` + reopen step. The kit
  still ships the strip logic (wsl-browser-bridge.sh) and cannot restart
  WSL itself, so the recovery step is load-bearing for the affected cohort.
  [RETRACTED — deliberate #252/#256 ultra-legacy removal; see the
  post-hoc marking in the intro.]
- **B5** — verified: 0.0.56 container-tools.md:22-25 carried the caveat
  ("If the probe is unavailable (opencode too old for `debug config`, sudo
  denied), it falls back to scanning the project config only"); current
  :18-22 states the unconditional "no matter which file declares it". The
  wrapper code confirms the fallback (opencode-as-opencode:418-422 comment,
  :467-478 the project-only else branch).
- **B6** — verified: 0.0.56 troubleshooting.md:427 named
  `127.0.0.1 <project>.<tld>`; both current passages end at "edit the
  hosts file in an elevated editor" without the mapping. The bridge's own
  command (`ddev hostname <name> 127.0.0.1`) confirms the required form.
- Two of the six findings are RETRACTED: B1 and B4 — the technical
  observations hold, but the defect claims are false (issue #252 and
  the PR #256 body name exactly these removals as deliberate
  ultra-legacy policy; see the post-hoc marking above). The factual
  verifications above stand as recorded; the defect judgments for
  B1/B4 do not. One provenance correction recorded above (B3
  pre-existing, not delta).

## Run provenance

- **Pass**: external machine, bias-reduced sparse checkout
  (`git sparse-checkout` excluding `agent/`, `.agents/`, `internal/` per
  internal/process/review.md — links into them dangle by design; their
  absence is not a finding). Model `opencode/gpt-6-luna#medium`, medium
  effort variant, 16 sub-agents all on the same model; ~28 minutes
  (estimated from its own artifact timestamps); working tree clean at
  4eacabb throughout; required host preflight passed; no test suites run
  (per the commissioning recipe — the house side runs them).
- **Commissioning** (completed after the initial integration, when the
  maintainer verified the launch commands — recorded as the marked
  correction it is, not as if known from the start; the snapshot commit
  was amended pre-force-push for exactly this): started via opencode's
  built-in `/review` command — the review template WAS loaded, matching
  the process/review.md recipe; the prompt pinned the model (GPT 6 Luna
  medium, sub-agents explicitly same model) but contained NO time budget
  and no reporting instruction — the ~28 min duration is the pass's own
  estimate from its artifact timestamps. The commissioned report dir was
  `/tmp/opencode/review-full-project-pre-0.0.57/` (no suffix); the
  maintainer handed it over under the `-b` name.
- **Cost**: $0.42 (maintainer-provided billing figure; the reviewer model
  has no access to its own accounting).
- **Commissioning + hand-over**: maintainer, 2026-10-25, per the
  "External review machines" recipe (internal/process/review.md). The pass
  wrote its report outside the repo; the house session (GLM-5.3, with the
  opk-review-pass skill loaded for the integration choreography only)
  embedded it here verbatim and verified every finding on the full tree.
- **Verification environment**: full checkout at 4eacabb
  (release/0.0.57), porcelain-clean; verification by targeted reads and
  `git show 0.0.56:` comparisons; no mutation windows.
- **Provenance split (finding level)**: delta-introduced B1, B2, B4, B5,
  B6 (four of them #256-shortening removals, one #223/#244 tee arm);
  pre-existing B3.

## Calibration (vs snapshot a — the house pass)

- **What b found that a missed: all six.** Five are docs regressions of
  the #256 shortening pass (B1, B4, B5, B6 and — as rewording — B3); the
  house E-axis twins verified the changed pages' flag tables, channel
  tables and the #244 python3 sentences, but explicitly deferred
  line-by-line prose review of the heavily shortened pages to the three
  in-repo #256 review rounds (snapshot a's E1 coverage records the
  deferral). The external pass, lacking that in-tree context, judged the
  pages on their own words — and the shortened pages lost load-bearing
  qualifiers. This is exactly the bias axis the redundancy setup exists
  to check: the house knew the shortening was a deliberate,
  already-reviewed change; the external saw only the result.
- **B2 is a code miss with a house false-clean adjacent to it**: house
  snapshot a's C-axis twins verified the tee's documented rc contract
  (consumer EPIPE, SIGINT, tool probe) and called the cat fallback clean —
  the undocumented directions (cat rc mask; the stderr-EPIPE arm that
  snapshot c's C1 flags) were not covered by the in-code contract the
  twins verified against.
- **What a found that b missed: all 27 of a's findings** — including the
  five code MEDs (ddev-migrate dump operand, the #243/#234 sweep gaps, the
  uninstall rc-blind sites, the getting-started python3 contradiction) and
  the whole L5/security inventory. Consistent with the setup: the external
  pass had no house memory and ran no suites; its yield concentrated on
  the user-facing docs surface, the house yield on code and process
  classes.
- **No overlap at all between a and b** — 0 of 6 shared. The combined
  unique count across a+b is 33.
