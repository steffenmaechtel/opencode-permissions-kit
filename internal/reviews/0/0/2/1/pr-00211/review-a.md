<!-- review-meta
ID: pr-00211
Snapshot: a
Subject: release 0.0.55 full-scope review (pre-tag)
Scope: full
Base: v0.0.55 @ ad9467d
Diff: 4e56959..ad9467d (PR #211: VERSION bump 0.0.54 -> 0.0.55 only; full-scope pass per the release trigger — last full scope was the 0.0.49 legacy era, 360 files / +15555 / -1222 since)
Date: 2026-10-20
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 10x GLM-5.3-Flash reviewer subagents — 5 axes x 2 independent each (install/update, management surface, wrapper+bin+sh, security horizontal, tests+docs+CI); 3 subagents (A1/C1/E1) rate-limit-retried after burst launch
-->

# Full-scope review — pr-00211 snapshot a — release 0.0.55

> Resolution: [resolution.md](resolution.md)


Release full pass ("what rotted sideways?") over the whole tree at
ad9467d (VERSION 0.0.55). PR #211 itself is the one-line VERSION bump;
the reviewed object is the tree. Ten reviewer subagents ran five axes
(two independent agents each); the main agent re-verified every finding
against the code before it entered this snapshot. One reported finding
was retracted during verification (see "Retracted").

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| F1 | HIGH | sh/fs-baseline.sh:153-175 | Group-baseline recheck gates `[ -L ]` on the leaf only — a parent dir swapped to a symlink inside the minutes-wide scan->act window makes root chgrp/chmod g+rw act outside the tree (perm-model + race-toctou, the L5/0.0.39h F2 class) | D2 | yes (code read) |
| F2 | MED | management/config.sh:183-184,194,637-648 | Missing-lib fallbacks for the mutating baseline/handover helpers are silent noops (and `ddev_rootless_bindmounts` not stubbed at all) while sibling stubs fail loud and callers print success ("setgid, default-acl", "group baseline refreshed", "backend switched") | B1+B2 | yes (code read) |
| F3 | MED | bin/ddev-migrate:31 | `ddev-migrate list` exits 1 when dump directories exist, 0 when none — inverted rc on a shipped diagnostics command | C2+C1 | yes (code read) |
| F4 | LOW | install.sh:1816-1823 + management/update.sh:866-873 | Failed `safe.directory '*'` add is silent, and the audit log unconditionally records "ensured" | A1+A2 | yes (code read, both twins) |
| F5 | LOW | management/update.sh:629-633, 824-831 | "prefer the checkout copy" comment vs dual-source reality: both copies sourced, LIBDIR last -> deployed definitions win (last-wins, siblings use first-wins) | A1+A2 | yes (code read) |
| F6 | LOW | management/update.sh:706-719 | Missing `etc/umask.sh` skips the umask re-deploy with zero output/audit lines — the identical sudoers skip (697-702) was deliberately made loud (0.0.41f S2) | A1+A2 | yes (code read) |
| F7 | LOW | management/update.sh:672, 680-681 | `xdg_open_real_exists` called unstubbed/unguarded; a missing helper yields rc 127 -> the `!`-negated arm fails open (shim decisions without the never-shadow probe); sibling status.sh:1030 guards with `command -v` | A1+A2 | yes (code read; not reachable today) |
| F8 | LOW | management/status.sh:443 | Upstream advisory "live check unavailable" is a counted warn -> offline/python3-less hosts exit 2 forever, contradicting the file's own uncounted-unknown rule (0.0.48b W3, status.sh:1273-1278) | B1 | yes (code read) |
| F9 | LOW | management/status.sh:157-158 | `${DEFAULT_USER:-$USER}` under `set -u` aborts with rc 2 when both are unset (cron/timer env + conf without the stamp) — collides with the "2 = warnings-only" verdict contract | B2 | yes (read; dash abort empirically confirmed by B2) |
| F10 | LOW | management/config.sh:606-619, 562-583 | Backend switch drops a hand-configured `OPENCODE_PODMAN_SOCKET` from install.conf (grep-v removes all three keys; only the always-empty local is re-added); install.sh preserves the same key | B2 | yes (code read, both sides) |
| F11 | LOW | management/config.sh:129-146 | Unknown subcommand tokens fall into `TARGETS` and are silently ignored for non-project actions (rc 0) — three different usage contracts across opk's management surface | B1 | yes (code read) |
| F12 | LOW | sh/fs-baseline.sh:144-177 | `_fsb_pass` mktemp not registered with the caller's `_tmp_track` trap (convention: staged-write.sh:44-46) -> root-owned /tmp litter on mid-pass abort | C1 | yes (code read) |
| F13 | LOW | bin/setup-container-backend:153-159 | `loginctl enable-linger` failure swallowed by `|| true`; "Linger enabled" message + audit log print unconditionally | C1 | yes (code read) |
| F14 | LOW | sh/ddev-handover.sh:536-539, 606-609, 671-674 | Root-run `.ddev` handover pairs are `\|\| true`-silent with unconditional success echoes — unlike `opk handover`, which accumulates `_ho_rc` and fails loud | C1 | yes (code read) |
| F15 | LOW | bin/opk:23-29 | Single-hop `readlink` resolves only one symlink level: a chained user symlink makes every subcommand report "not found" with a misleading "is the kit installed?" error; siblings (ddev-migrate:13, xdg-open:47) use `readlink -f` | C1 | yes (code read) |
| F16 | LOW | bin/setup-container-backend:114-143 | `allocate_range` feeds raw /etc/subuid(subgid) fields into shell arithmetic: digit-leading junk aborts provisioning under `set -e` with a cryptic foreign error; leading zeros misparse as octal; alphabetic fields silently count as 0 | C2+C1 | yes (code read) |
| F17 | LOW | bin/opk:219-222 + management/update.sh:740-744 | OpenChamber `policy.json` writes are non-atomic (O_TRUNC `>` / `sudo tee`) — sibling-site gap of the 0.0.44a V10 atomic-write wave (sudoers/umask/lib all stage+mv) | D1 | yes (code read) |
| F18 | LOW | sh/wsl-browser-bridge.sh:128-158 | If the kit block's `-- end` marker was hand-destroyed, the stripper consumes foreign *comment* lines until the first non-comment line — "never eat foreign content" holds for code, not for comments | D1 | yes (code read) |
| F19 | LOW | docs/concepts/security-model.md:15 | Sudoers enumeration row omits the `cwd-check` rule the template grants (sudoers.template:48) | D2 | yes (doc read; template per D2 full read) |
| F20 | LOW | Makefile:74 vs .github/workflows/test-unit.yml:96,102 | `test-pages.sh` and `test-rules-index-parity.sh` run in CI only — no Makefile target, absent from `make test` (local green can hide a red suite) | E1 | yes (grep both sides) |
| F21 | LOW | Makefile:296 + .github/workflows/test-unit.yml:98 | German "Vorgang" in make/CI step names (English-only rule for shipped content) | E1+E2 | yes (grep) |
| F22 | LOW | docs/concepts/security-model.md:80-81 | Trust-model paragraph still says the one-liner streams from `master`; every user-facing one-liner now uses the Pages stable entry (pinned by test-pages.sh) | E1+E2 | yes (doc read) |
| F23 | LOW | docs/reference/cli.md:217-224 | install.sh flag table omits `--openchamber-policy` (parsed at install.sh:395-403); `-y` alias accepted by update/config/uninstall but unlisted | E1+E2 | yes (grep both sides) |
| F24 | INFO | management/config.sh:445-447 | Missing staged-write.sh makes `agent_home_sane` return 127 -> die() misattributes a broken kit to "a parent ... is a symlink" | B1 | yes (code read) |
| F25 | INFO | management/status.sh:718-722, 967-984 | Two unjudgeable probes render as counted verdicts instead of unknown rows: unreadable port_start -> counted `ui_kv_bad "(? > 80)"`; failed stat on /mnt/c -> counted `ui_kv_ok "restricted (mode ?)"` (narrow triggers, opposite directions) | B1 | yes (code read) |
| F26 | INFO | management/config.sh:850 vs 767-770 | `config.sh status` view narrower than the menu's "Current settings" (backend row missing) | B1 | yes (code read) |
| F27 | INFO | management/uninstall.sh:56, 335-339 | `browser_bridge_remove` noop stub + unconditional "WSL browser bridge removed" — claims a removal that never happened if the lib is missing (near-unreachable) | B2 | yes (code read) |
| F28 | INFO | management/uninstall.sh:404-407 | Substring group match (`grep -q "$OPENCODE_GROUP"`), run_q-silenced gpasswd, unconditional "Removed ... from group" | B2 | yes (code read) |
| F29 | INFO | bin/opencode-as-opencode:104, 648, 651 | `note()` is `printf '%b'` and interpolates paths — escape sequences in directory names garble the warning; the code's own :246 comment avoids exactly this class for the settings value | C1 | yes (code read) |
| F30 | INFO | sh/deploy-lib.sh:114,122,125,129 | Four sourced-only sh/ libs deployed 755 vs the 644-sourced-lib invariant; carried since 0.0.41d, test-pinned (test-bypass-guard), accepted by the 0.0.49 full review | C1 | per C1+C2 reads |
| F31 | INFO | bin/opk:14,189,361; bin/opencode-as-opencode:9; bin/setup-container-backend:32; bin/ddev-migrate:5; templates/sudoers.template:6,50; templates/opencode.jsonc:6; tui/kit-mode-2x.tsx:3 | Stale `docs/design/...` references in shipped code comments after the docs restructure (repo side swept to internal/records/, files/ side missed — partial class sweep) | D1 | yes (grep, 10 sites) |
| F32 | INFO | install.sh:930 vs management/config.sh:263 | `project_path_sane` exists as two maintained copies — drift hazard on the security gate that bounds the recursive group baseline | D1 | yes (grep, both definitions) |
| F33 | INFO | management/update.sh:1426-1450 | `opk update --refresh --only-binary` silently drops `--refresh` (section sits inside the not-only-binary block) | A1+A2 | yes (both agents; block placement) |
| F34 | INFO | management/update.sh:3-5 | Header enumerates the pre-0.0.29 flat file list; ~40 files deploy via the manifest today | A1 | yes (code read) |
| F35 | INFO | management/update.sh (fetch path) | Update trust anchor is TLS-only transport to a tracked branch ref — matches the documented streaming-install model, no change requested | D2 | note only |
| F36 | INFO | tests/unit/test-docs.sh | Docs flag tables have no automated pin against the actual parsers — claim-drift guarded by review only (F23 as the live example) | E1 | per E1 read |
| F37 | INFO | bin/ family | Partial `set` skeletons across bin/ (`set -e` xor `set -u`, never `set -euo pipefail`) — traced, no unguarded defect found; likely deliberate per-site | C2+C1 | per reads |

Severity counts: **1 HIGH, 2 MED, 20 LOW, 14 INFO** (37 findings).

## Key findings detail

### F1 (HIGH) — parent-symlink TOCTOU in the group baseline

`_fsb_pass` (fs-baseline.sh:134-189) writes the ENTIRE `find -print0`
result to a temp file first (:153), then replays it through an xargs
worker whose only gate is `[ -L "$_p" ] && continue` on the FINAL
component (:170). `-L` on the whole path tests the leaf's lstat — a
PARENT swapped to a symlink passes the gate. The scan->act window is
the full find runtime (the file's own issue-#14 note: "large trees can
take several minutes"), replay included.

Attack (within the kit's own threat model — the :125-133 comment names
the semi-trusted agent as the adversary this recheck loop exists for):
the agent pre-plants `root/x/y/shadow` as a regular file (so the
`-type f` / `! -type l` scan classifications stick), then during the
window runs `mv root/x/y root/x/y.d && ln -s /etc root/x/y`. The
replayed operand now resolves to `/etc/shadow`; the leaf is a regular
file, the gate passes, and pass 1 executes `chgrp <sharing-group>
/etc/shadow` and pass 3 `chmod g+rw /etc/shadow` — the sharing group
contains the agent user -> editable password hashes -> root escalation.

This is precisely house class L5 item 1 ("`[ -L ]` on every path
component — gates that check only the final component are bypassed via
parents, 0.0.39h F2"), applied to the one root-run recursive walker.
Provenance: pre-existing (recheck loop dates to 0.0.39e S1; file
unchanged in 0.0.49..HEAD). Direction: walk every component below the
baseline root in the worker (the chain-walker shape already exists as
`agent_home_sane`, staged-write.sh:94-126), or `realpath`-resolve and
refuse unless resolved == scanned inside the root.

### F2 (MED) — config.sh degrades silently where its siblings fail loud

config.sh stubs its conditionally-sourced helpers with two different
contracts: the write helpers fail loud (`staged_write` :206-207,
`sudoers_deploy` :218-219, `agent_config_render` :230-234 — "error: ...
unavailable ... missing" + return 1), but the two MUTATING helpers get
silent noops (`ddev_handover_root() { :; }` :183, `fs_baseline_root()
{ :; }` :194) and `ddev_rootless_bindmounts` (ddev-handover.sh:363) is
not stubbed at all. Consequences: `projects add` prints "added $p
(group=..., setgid, default-acl)" (:344) and `refresh` prints "group
baseline refreshed." (:672) over a no-op; the backend switch's `case $?`
handles only rc 2, so a 127 from the unstubbed bindmounts call leaves
the gate unevaluated while the switch reports success. Trigger: a
damaged/partially-deployed library (missing sh/fs-baseline.sh or
sh/ddev-handover.sh) after an interrupted update. Provenance:
pre-existing. This is the exact "silently-droppable lib guards" class
the #165/#199 waves retired for status.sh/update.sh — config.sh's
mutating helpers were not swept (sibling-sweep gap).

### F3 (MED) — `ddev-migrate list` inverted exit code

bin/ddev-migrate sets `set -u` only (no `-e`). The `list)` arm's last
command is `[ "$dm_found" = 0 ] && echo "no dump directories..."` (:31)
— with dumps present the test fails, the `&&` short-circuits, and that
rc 1 becomes the script's exit status; the empty case exits 0. Any
scripted use of the documented command reads success as failure and
vice versa. One-line fix (`if [ "$dm_found" = 0 ]; then echo ...; fi`).
Provenance: pre-existing.

## Retracted / ghost findings

- **B2-6** (config.sh menu grep without `2>/dev/null` at :793) —
  RETRACTED on verification: both config.sh sites (:411, :793) AND
  status.sh (:208) carry `2>/dev/null`. The finding does not exist at
  the cited location.

## Clean verdicts (axes' verified-clean areas, spot-checked)

- Fetch/deploy list discipline: install.sh fetch list == update.sh
  KIT_FILES == lib_deploy manifest == disk (mutation-canary-pinned by
  test-kit-files.sh) — both A agents independently.
- Channel pinning chain (install stamp -> update resolve/re-stamp ->
  status display -> docs) and strict version probes (empty = unknown,
  never a guess) — clean.
- Exit-code contract of `opk status` (0/1/2/64), UI counter semantics
  (no pipeline-subshell tally losses), y/n prompt conventions incl.
  issue-#187 trimming, git-config status/apply parity (issue #205) —
  clean.
- wsl.conf consent chain: sole writer `opk wsl-add-opencode-1-fix`,
  uninstall asks or `--yes`, install/update strip legacy-only, atomic
  stage+mv replace — compliant (F18 is an edge inside the stripper).
- Soft-only model: no deny ACLs / chmod-000-as-deny / chown-to-root
  hardening reintroduced anywhere; sudoers exact-path + `(opencode)`
  RunAs + visudo pre-validation — clean.
- Untrusted-input rules: no eval; sh -c bodies interpolation-free;
  anchored/negated-class allowlists; printf-format discipline — clean
  except F16 (unvalidated arithmetic input).
- Pins discriminate and gate before the summary in all 13 focus suites;
  sandbox policy conformance; exec-bit invariant (index modes) — zero
  mismatches; workflows carry no chmod lines.
- Wrapper hot-path fail-open contract intact at every probe site; no
  fail-open/fail-loud swaps found.

## Run provenance

- Tree: working tree at ad9467d (branch release/0.0.55, clean except
  untracked local build residue `py/__pycache__/jsonc-parser.cpython-312.pyc`
  — not part of any release artifact; ignored).
- Reviewer fan-out: 10 subagents (glm-5.3-flash), 5 axes x 2
  independent, checkpoint discipline per review-concept RM-0086/0092
  (side files under /tmp/opencode/pr-00211-review/checkpoints/, LAUNCH/
  RETURN timestamps 18:53-19:25 UTC window). Main agent (GLM-5.3)
  re-verified all 37 accepted findings by code read; 1 retraction.
- Gates run on this host (kit-managed checkout, agent user `opencode`,
  UID-separated): `make check-version` rc=0 (stamp 0.0.55, channel
  default master); `make test` (lint + 39 unit suites) rc=0;
  `make e2e-rootless` rc=0; `make e2e` first run rc=2 — root cause is
  ORCHESTRATION, not product: the suite resolves the opencode version
  dynamically as "current latest" (tests/e2e/lib.sh:240-247), the cache
  was cold for 1.19.3, and two suites launched concurrently downloaded
  into the same cache path (the exact precondition violation AGENTS.md
  documents). The surviving cache entry is a working 1.19.3 binary
  (`--version` verified); the sequential rerun came back green:
  **303 passed, rc=0** — all four gates at baseline on this host. No
  product finding.
- Provenance split (finding level): pre-existing 30, wave-introduced 3
  (F20, F21, F31), delta-introduced 2 (F19, F22), note/unstated 4
  (F33, F35, F36, F37 classification) — nothing fix-induced from the
  0.0.50..0.0.55 waves except the partial-sweep items above; the delta
  since 0.0.49 introduced no HIGH/MED of its own (F1/F2/F3 all
  pre-existing).

## Recommendation

**Ship-after-fixes for the release, with F1 as the gate.** The 0.0.55
delta itself is clean (VERSION bump only; no wave-introduced HIGH/MED).
F1 (HIGH, pre-existing) sits on the most HIGH-prone class in the corpus
(perm-model/race-toctou) and should block the tag or ride the release
fix wave with its own pin + e2e run; F2/F3 are small, high-confidence
MEDs; the LOW/INFO tail (docs drift F19/F22/F23, lint/CI hygiene F20/
F21, update.sh consistency F4-F7, F10-F18) fits one normal fix wave.
Release gate (RM-0091): both e2e suites and the unit suite are at
baseline on this host (see run provenance) — F1's disposition is the
only open release question.
