# Resolution — pr-00263 (release 0.0.57 full-scope review)

Chain: a (house full pass) -> b, c (external redundancy passes, GPT 6 Luna
medium/high) — 42 unique findings across the three snapshots. This is the
second fix-wave attempt: attempt 1 (backed up at
`backup/pr-00263-fix-wave-1`, never pushed) was superseded when the
maintainer surfaced issue #252 — the ticket behind the #256 docs
shortening — whose ultra-legacy policy deliberately removed two of the
externals' findings' subjects; those are dispositioned deliberately not
done and marked in the snapshots. Deferred to backlog issues: #264-#267
new, #245/#246/#247 existing.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a F5 + c C8 (MED) | **implemented** | `07ae002` | prerequisite states the abort; claim-drift pin in test-docs.sh |
| b B1 + c C7 (LOW) | **deliberately not done** | — | #252 names 0.0.x→0.0.y update paths as removable legacy |
| b B4 (MED) | **deliberately not done** | — | #252/PR #256 name the 0.0.36 entry removal as policy |

## Evidence detail

### a F5 + c C8 (MED) — getting-started python3 prerequisite

The bullet claimed "the installer probes `python3` missing or broken; the
baseline still applies without it" while both `_py3_health_probe` arms
exit 1 (install.sh:574-586 — missing → "required but not installed",
broken → "present but broken"). Fixed to state the hard gate; the component
degrade (baseline without live counters) stays, correctly scoped to an
installed kit. Pin (test-docs.sh, before the summary gate): the abort
claim must be present, the survival claim must be absent, and both
installer abort messages serve as code-side anchors. Found independently
by the house pass (a F5, E2 axis) and the external high pass (c C8, P3);
the severity divergence (house MED vs external P3) is recorded in
snapshot c's calibration.

### b B1 + c C7 / b B4 — deliberately not done: deliberate removals per #252

Issue #252 and the PR #256 body name both removals as intended
ultra-legacy cleanup ("how to update from 0.0.x to 0.0.y … we can remove
old legacy stuff"; PR body: "remove ultra-legacy update paths: the
one-time >= 0.0.29 layout migration section, the kit-0.0.36 wsl.conf
parse-error entry"). Both findings are marked RETRACTED in
review-b.md / review-c.md (post-hoc, maintainer decision 2026-10-25 —
the sparse external setup could not see the recorded intent, and the
house verification initially restored them; attempt 1 is backed up at
`backup/pr-00263-fix-wave-1`, never pushed). The current-accuracy fixes
are unaffected: #252 wants brevity, not false claims.
