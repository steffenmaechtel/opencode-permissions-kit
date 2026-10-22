<!-- review-meta
ID: pr-00224
Snapshot: a
Subject: issue-197 e2e default flip to opencode 2.x, -1x lanes + v2 installer bootstrap (feature wave)
Scope: wave
Base: master @ 9f9fd32
Diff: 920919b..5640116
Date: 2026-10-22
Reviewer: GLM-5.3 (external /review session, single pass, no fan-out — wave scope)
-->

# Wave review — pr-00224 snapshot a — issue #197 e2e default flip to 2.x

> Resolution: [resolution.md](resolution.md)

Wave pass over the two PR commits (cea5da4 + 5640116; the master merge
7eeb33c excluded per the maintainer's scoping): the lane flip in both e2e
workflows, `npm_dist_latest` + reordered resolution in tests/e2e/lib.sh,
the install.sh bootstrap URL flip, the per-job lane pins in
test-workflows.sh, the new behavioral/structural pins (test-e2e-sources.sh,
test-install-args.sh), and the docs/record updates.

## Findings index

| ID | Sev | Location | One-line summary | Verified | Prov |
|---|---|---|---|---|---|
| W1 | LOW | tests/e2e/lib.sh:311-319 | offline fallback bypasses the new 2.x gate: with the npm registry unreachable and no 2.x binary in the cache, the default lane silently runs the newest *cached* version — on a pre-flip local cache that is 1.x, with only the generic WARNING, violating the lane's own "2.x or loud fail" contract (local `make e2e` only; CI fails at the resolve step before the fallback) | yes (code read, fallback reachability traced: only the unpinned default lane ever enters it) | wave-introduced |
| W2 | LOW | .github/workflows/test-e2e.yml, test-e2e-ddev.yml (rename) | the -2x→-1x rename changes required-check names: any branch-protection rule still requiring `e2e-2x` / `e2e-rootless-2x` / `e2e-ddev-2x` blocks every later PR ("Expected — waiting for status"); in-repo consumers are safe (scripts/release.sh gates on workflow-level run conclusions by head SHA, verified; remaining `e2e-2x` strings are the deliberately warm cache-key prefixes) | yes (release.sh read; GitHub-side config not visible from the repo — severity depends on it) | wave-introduced |
| W3 | INFO | tests/unit/test-e2e-sources.sh:131-132 | "workflows export the workflow token to the e2e steps" pin premise narrowed by the flip: the default e2e jobs are now tokenless (correct — they no longer call api.github.com), the file-level grep passes off the -1x lanes' tokens; label overstates, the real per-job auth contract is carried by the new lane pins in test-workflows.sh | yes (code read) | delta-introduced |
| W4 | INFO | tests/unit/test-e2e-sources.sh:2-6 | file header still claims lib.sh is "not unit-testable code" and the file holds only "structural greps" — the wave adds a behavioral fake-curl block to this same file | yes (code read) | wave-introduced |
| W5 | INFO | .github/workflows/test-e2e-ddev.yml:165-177 | default ddev Summary step prints the *step-resolved* `E2E_OC_VERSION` while the run step is deliberately unpinned — a dist-tag bump between step and run labels the summary with a version the suite did not test (display only) | yes (code read) | wave-introduced |
| W6 | INFO | tests/unit/test-e2e-sources.sh:71-72 | "a pin wins before any resolution" is presence-only: moving `OC_VERSION="$E2E_OC_VERSION"` below the resolve block escapes the pin while changing behavior (resolved value clobbered, gate applied to an ignored value) | yes (analysis) | wave-introduced |
| W7 | INFO | tests/e2e/lib.sh:249-261 | `npm_dist_latest` queries the suffixed per-target package name — on a non-AVX2 or musl host (`linux-x64-baseline`/`-musl`) this asks the registry for a suffixed npm package whose existence could not be verified; if absent: empty → offline fallback → loud FAIL on a fresh cache. Same naming contract e2e_fetch_opencode/update.sh already use, so kit-internal consistency holds; exotic-host, local-only, fails loud | analysis (upstream existence unverified — marked unverified) | wave-introduced |

Verified clean (main agent, this session):

- **Lane wiring**: all six job blocks read line-by-line against the per-job
  pins — default lanes resolve npm dist-tag latest with anchored `^2\.` gate,
  -1x twins resolve GitHub releases/latest authenticated (Bearer header) with
  anchored `^1\.` gate; step failures precede the cache step (C8 contract
  holds — an empty version can never reach a cache key).
- **Cache-key handover byte-identical** in all four mappings (default e2e ←
  former 2x keys, e2e-1x ← former v1-era default keys, ddev default ← former
  ddev-2x key, ddev-1x ← former ddev default key); restore-prefix bridging
  correct in both directions, no prefix shadowing between
  `opencode-e2e-old<OLD>-` and `opencode-e2e-2x-old<OLD>-`.
- **OPK_GH_TOKEN removal from the default e2e jobs is sound**:
  `gh_latest_tag`/api.github.com is called only by run-ddev.sh (ddev version
  resolution) — both ddev jobs keep the token; the OLD-binary fetch uses the
  release CDN, not the API.
- **npm_dist_latest matches update.sh's resolve_latest_opencode_version**
  (same packument, same dist-tags parsing via python3, empty-on-failure);
  empty-on-failure proven behaviorally (ok/junk/down pins); platform-target
  detection moved before resolution with no consumer in between; gate applies
  only to the unpinned default path — pins are never major-gated, as
  documented.
- **Upgrade-test claim verified**: run.sh 11c downgrades to 1.18.15 then
  upgrades via `--binary-path` to the version under test — on the default lane
  that is the production 1.x→2.x path; 11d is correctly 2.x-gated (skipped on
  the -1x lane).
- **install.sh bootstrap flip**: v2 URL in prompt + curl, pickup paths
  unchanged (`/root/.opencode/bin`, `$DEV_HOME/.opencode/bin`), repo-wide
  sweep leaves no v1 URL in shipped code (lib.sh's cached-installer v1 URL is
  deliberate and documented in both the code comment and the record).
- **Docs** (security-model.md, compatibility.md) and the record's new
  paragraphs match the code (lane names, cadence, cache swap, fallback
  behavior).
- **Gates**: `sh tests/unit/test-{e2e-sources,workflows,install-args}.sh`
  green; full `make test` green; shellcheck on the touched shell files — no
  new warning classes (the added SC3043 `local` matches the file-wide idiom).
- **Sabotage red→green ×3** (deletion, committed clean tree, restored after
  each): deleting the lib.sh 2.x gate reds exactly the two gate pins;
  reverting the install.sh URL to v1 reds exactly the two v2 pins; deleting
  the `E2E_OC_VERSION` env pin reds exactly the two 1x lane pins. Tree clean
  at `7eeb33c`, suites re-run green after restore.

## Retracted / ghost findings

None.

## Run provenance

- Tree: `7eeb33c` (clean), reviewed range `920919b..5640116` (PR commits
  cea5da4 + 5640116; the master merge excluded per the maintainer's scoping).
- Reviewer: GLM-5.3, single-pass external session (no subagent fan-out —
  wave scope); verification duty held in-session: every finding above
  re-verified by code read or traced execution; W7's upstream half marked
  unverified.
- Gates run: the three touched unit suites, full `make test` (all green),
  shellcheck on lib.sh + the three test files, three sabotage spot-checks
  with restore.
- Sabotage windows: before report output only; no parallel readers.

## Recommendation

**No merge blocker.** The flip is internally consistent, the warm-cache
handover is byte-exact, and the new pins discriminate (sabotage-verified).
W1 is the only code-level candidate — a two-line hardening (warn when the
offline fallback leaves the default lane's major, or gate the fallback value
on `2.*` with the same escape-hatch message); fine as an in-wave fix or a
follow-up. W2 is a maintainer checklist item at merge time: update
branch-protection required checks to the new `-1x` names (and drop the
`-2x` ones). W3–W7 are informational.
