# Code Review — opencode permissions kit — 0.0.49, snapshot-d micro wave review (0.0.49c fix wave: F2 mode pins + F3 count pins + F4 §6 umask)

> Resolution: [resolution.md](resolution.md)

- **Date:** 2026-10-13 (wave and chain of 2026-10-12; the pass ran in the
  session that started on the 12th, snapshot committed after midnight)
- **Reviewer:** GLM-5.3 (OpenCode v2 agent), run in the repo session at the
  maintainer's request (provenance: this session produced none of the
  reviewed waves — all three commits under review are the maintainer's).
  Single lead pass, no subagents — the wave diff is +82/−12 across 5 files
  (2 test files, +30/−5; 3 docs-only commits), every claim was verified
  against full-file reads and every recorded sabotage was independently
  re-derived on a scratch clone.
- **Tree reviewed:** `feature/issue-163-corrupt-binary-status` @ `5ff63ee`
  (VERSION 0.0.49), working tree clean. **Wave under review:** the 0.0.49c
  fix wave, `5678cf7..5ff63ee` — `9de1dae` (F2: both wiring pins carry the
  mode via `&& grep -Fq "opencode-permissions-kit-umask.sh 644"`; F3:
  `-eq 1` call-site count pins per script; F4: `umask 022` at the top of
  test-secure-binary.sh §6), `f4ee345` (resolution stem-c rows F1–F4, the
  rule-2 pointer line, README index tail) and `5ff63ee` (L2 sweep evidence
  appended to the F2 row).
- **Result:** **0 new findings — no MED/HIGH, no LOW, no INFO. Stop rule
  met; the 0.0.49 a→b→c→d chain converges.** All four stem-c dispositions
  verified implemented and effective; every recorded sabotage reproduced
  with its exact count (mode 2 / decoy 1 / wiring reverts 3+3 / helper
  in-place 4 / rm-legs 2 / chmod-after 1), the umask-027 before/after pair
  re-derived on both trees, and the recorded session follow-up (the
  `5678cf7` test-docs red) verified true with its exact FAIL line.

## Method

- Full read of the wave diff, both touched suites whole
  (test-bypass-guard.sh: the six umask-deploy pins now four mode/count
  pairs across both scripts; test-secure-binary.sh §6: the `umask 022`
  line at :184 with all pins downstream of it), and the pinned production
  code in context (`install.sh` :128/:285–286/:1799–1804 incl. the
  call-site continuation lines, `update.sh` :393/:699–711, the
  `copy_file_atomic` body in `sh/secure-binary.sh` :99–116).
- Count-pin anchoring re-derived by hand: the quote-carrying pattern
  `copy_file_atomic "` matches exactly ONE line per script — the call
  site. The `command -v` wiring line (`>` follows the name), the fallback
  definition (`(` follows the name) and its echo string
  (`copy_file_atomic unavailable` — space + `u`) all miss it; the mode
  string `opencode-permissions-kit-umask.sh 644` likewise occurs exactly
  once per script (the call-site line :1802/:706 — the log lines carry
  the path without the mode, the old in-place chmod ordered 644 before
  the path).
- Sabotage re-derivations on a scratch clone (branch @ `5ff63ee`,
  baseline test-bypass-guard 33/0 + test-secure-binary 31/0, tree
  restored and re-run green after each): `644→600` at both call sites →
  exactly **2** FAILs (one mode pin per script); decoy third call site
  (mode 600) in install.sh → exactly **1** (the count pin); install.sh
  wiring reverted to the pre-`cb33e98` in-place shape → exactly **3**
  (call+mode, count, no-in-place); update.sh wiring reverted → exactly
  **3**; helper body reverted to in-place cp+chmod → exactly **4**
  (killed-cp bytes, failing-mv rc, failing-mv bytes, mode-at-mv); rm-legs
  deleted → exactly **2** (both temp-litter pins); chmod moved after the
  mv (retargeted at the dst — the realistic cp-then-chmod-after shape) →
  exactly **1** (the mode-ordering pin). All match the resolution F2/F3
  rows' recorded counts, including the updated "3 pins each" for the
  wiring reverts.
- F4 before/after pair re-derived on both trees with the chmod-after-mv
  sabotage: pre-fix `5678cf7` under an outer umask 027 → **0** FAILs (the
  ordering pin blind, exactly the F4 mechanism); fix tip `5ff63ee` under
  027 → exactly **1** FAIL; clean baselines green under 022 **and** 027
  (the script's own `umask 022` overrides the caller's shell).
- The recorded session follow-up verified: `test-docs.sh` at `5678cf7` →
  rc 1 with exactly `FAIL 2026-10-12-v0.0.49-c: index lists a resolution
  but the snapshot has 0 pointer line(s) (README rule 2)`; at `5ff63ee`
  green. The snapshot file's only edit across the wave is the pointer
  line (rule 2's allowed edit); `5ff63ee` touches the resolution only.
- L2 sweep re-run per the F2 row's claim: `grep -rnE 'chmod [0-9]|install
  -m [0-9]' files/` — every executed/sourced-content mode site accounted
  for (secure_binary 750, the lib_deploy manifest modes, the sudoers
  stage 440, the WSL stand-in `install -m 755`, the two umask 644 call
  sites); the row's cited pins verified present (test-sudoers-deploy:84
  "happy path: mode 440"; test-deploy-lib:63–67 per-manifest-entry mode
  checks incl. the 440; test-browser-bridge §4 stand-in deployed;
  test-secure-binary §1 behavioral 750); the remaining grep hits
  re-classified — temps staged for a later mv
  (config.sh `_ucb_tmp`/`_udd_tmp` → install.conf,
  wsl-browser-bridge `_bb_stage` → wsl.conf, update.sh `_fk_tmp`/
  `_elf_tmp`), directory modes (2775/2750/700/750), audit-log data
  (log.sh 640) and the openchamber/jsonc/theme data writes — all data
  modes or non-content deploys, out of the class per the 0.0.49b C1
  boundary the row cites. "The two umask 644 sites were the class's only
  unpinned members" holds.
- L1–L7 checklist: L1 no new fail-soft spots (test-only wave); L2 sweep
  above; L3 every wave claim audited true (the two new comment blocks,
  all four resolution rows, both commit messages, the README tail —
  including the old-shape claim, verified against `cb33e98^` live);
  L4 every new pin sits before its suite's summary gate
  (test-bypass-guard checks :128–170 vs summary :186–194; §6 umask :184
  vs summary :280) and discriminates (sabotages above); L5 no root-op
  delta in the wave; L6 the wave is itself pins, and this pass is its
  owed micro review; L7 no new scripts (test edits follow the house
  `check`/`sh -c` shapes).
- Gates re-run by this review: `sh tests/check-host.sh` OK, **all 34 unit
  suites** green (touched: test-bypass-guard 33/0 — 31 plus the two new
  count pins; test-secure-binary 31/0), `make lint` green,
  `make check-version` green (0.0.49). **E2e not owed** (AGENTS owes the
  suites for install.sh/update.sh/wrapper/backend changes — the wave
  touches test code and docs only); the last same-day workspace pair
  (23:29:12) started before the wave (`9de1dae` landed 23:50:07) and
  corroborates nothing here — recorded rather than cited.

## Per-commit verdicts

| Commit | Claim | Verdict |
|---|---|---|
| `9de1dae` | pin the umask-deploy mode 644, copy_file_atomic call-site count and §6 umask (0.0.49c F2, F3, F4) | Implemented and effective — exactly the shapes 0.0.49c prescribed (mode-carrying wiring pins; W6's `-eq` count shape; the house `umask 022` pattern); all seven sabotages reproduce with the recorded counts, the F4 pair discriminates under 027 |
| `f4ee345` | resolution stem-c rows F1–F4, rule-2 pointer, README tail | Rows match the code and the sabotages (incl. the honestly-updated "3 pins each"); the F1 correction accurately states the old shape's set -eu abort; the pointer line is the snapshot's only edit (rule 2); the session follow-up discloses the `5678cf7` red accurately |
| `5ff63ee` | L2 sweep evidence in the F2 row | Sweep re-run matches the row's inventory; every cited pin exists; the boundary sites land on data files as recorded |

## Findings index

None — the pass records no findings.

## Verified clean (no finding)

- **F2 mechanics:** the mode string is carried at both call sites
  (continuation line `…/opencode-permissions-kit-umask.sh 644 \`), occurs
  nowhere else in either script, and cannot be satisfied by the old
  in-place shape (chmod-before-path) — live-verified at exactly 3 FAILs
  per wiring revert. Combined with §6's behavioral mode pins (explicit
  640 exact, ordering at the mv), the deployed 644 is transitively pinned
  end-to-end: the string at the real sites plus the helper honoring its
  mode argument. The two greps of a pin are line-independent — a
  bystander line would have to carry the exact path-then-mode string;
  none exists today, and the count pin plus §6 keep the chain closed.
- **F3 mechanics:** `-eq` (not `-ge`) makes both a removed and an added
  call site fail loudly — decoy → 1 FAIL, revert → count 0 → FAIL; the
  quote-carrying pattern excludes the wiring line, the fallback
  definition and its echo string (verified by grep and by sabotage).
- **F4 mechanics:** `umask 022` sits at §6's top with only the summary
  downstream — no earlier section is affected (sequential execution) and
  no later one exists to drift; §6's expectations are umask-stable
  (source explicitly `chmod 644`, temps asserted only for absence); the
  pre-fix blindness and the post-fix discrimination both re-derived.
- **Boundary:** e2e's umask checks remain existence + content
  (run.sh:583–614, untouched) — F2's row records the e2e `stat`
  alternative as deliberately not taken because the unit pins fail on
  the same commit; consistent, and the e2e option stays available for a
  future wave without owing one now.
- **Docs/process:** the 0.0.49-c snapshot gained only the rule-2 pointer;
  the README row tails stay one-line summaries; IDs carry their stems in
  every new check description; no VERSION delta; no user-facing behavior
  changed (no docs-page duty).

## Gates

- Re-run by this review: `sh tests/check-host.sh`; **all 34 unit suites**
  green (test-bypass-guard 33/0, test-secure-binary 31/0); `make lint`
  green; `make check-version` green (0.0.49); `sh tests/unit/test-docs.sh`
  green on the committed tree (the rule-2 red of `5678cf7` verified
  repaired).
- E2e not owed — test-only wave (no install.sh/update.sh/wrapper/backend
  delta); no same-day post-wave run exists to cite.

## Recommendation

No MED/HIGH/LOW/INFO — the stop rule is met and the 0.0.49 chain
(a→b→c→d) converges. The stem-c fixes did exactly what the snapshot
prescribed, at the pinned level, with every sabotage independently
reproduced. No fix wave follows from this review; the branch is
PR-ready on the maintainer's call. The resolution's chain state is
updated to stems a–d with this snapshot.
