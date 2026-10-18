<!-- review-meta
ID: pr-00196
Snapshot: a
Subject: issue-192 root-shell install gate + getent developer homes (feature wave)
Scope: wave
Base: v0.0.51 @ d3e187d
Diff: d3e187d..a470bab
Date: 2026-10-18
Reviewer: GLM-5.3 (house session, fresh; main agent + 3 Flash axis subagents — mechanical, security, claims/tests; every finding main-agent-verified against full-file reads)
-->

# Review — pr-00196 snapshot a — issue #192 root-shell gate + getent developer homes

> Resolution: [resolution.md](resolution.md)

Wave scope: `git diff d3e187d..a470bab` (11 files, +396/−37). The wave
refuses root-shell installs up front (`_root_user_gate` in `install.sh`,
charset→root→distro gate order) and resolves developer homes via getent in
`status.sh` / `update.sh` / `uninstall.sh` instead of hardcoded
`/home/$DEFAULT_USER`; `update.sh` skips hook re-apply loudly for uid-0
developers and missing homes. Unit pins, e2e step 2a, and two docs pages
ride along.

**Bottom line: no behavior bug found.** The gate logic, wiring order,
`DEFAULT_USER`/`DEFAULT_HOME` derivation order, block-extraction ranges,
e2e modeling, and class sweep all verify clean. The two MED findings are
pin-hardening gaps (the class the house rules "pins discriminate" and
"every new probe gets a failure-path pin" cover), not shipped defects.

## Findings index

| ID | Sev | Site | Summary | Verified |
|----|-----|------|---------|----------|
| T1 | MED | tests/unit/test-install-args.sh:222–229 | V14 sibling-sweep pin requires a trailing slash — the old bug's exact slash-less form (`[ -d "/home/$DEFAULT_USER" ]`) would pass green | yes (live tree clean) |
| T2 | MED | status.sh:530, update.sh:764,446–447 | New `id -u … \|\| echo 1` probes' fallback arms never execute under any pin; update.sh's getent-miss `DEFAULT_HOME` fallback is shape-grepped only | yes |
| T3 | LOW | docs/troubleshooting.md:41–46 | Fix path's `opk uninstall` is refused when run from the root shell — the doc's stated context; works from the normal user | yes |
| W1 | LOW | files/install.sh:551–564 | No override flag for the root gate (distro gate has `--force-unsupported-distro`); the guidance assumes a regular user already exists | yes |
| S2 | INFO | update.sh:770–794 | `sudo tee -a` follows developer-owned rc symlinks — pre-existing class; this wave only widens the qualifying homes (downgraded from LOW in verification) | yes |
| S1 | INFO | files/install.sh:578,593 | Deliberate `sudo env SUDO_USER=x bash install.sh` self-override bypasses the gate — trust-model note, no attacker vector (installer already runs as root) | yes |
| M1 | INFO | uninstall.sh:291–313 | Uninstall now heals `/root/.config/opencode` on broken installs silently — no uid-0 notice, unlike status/update (trigger corrected in verification) | yes |
| T4 | INFO | uninstall.sh:292–294 | Comment rationale understates the mechanism: the root-home case is install.conf-mediated (whoami=root is refused at :97), "recorded" carries the meaning | yes |
| T5 | INFO | tests/e2e/run.sh:127–139 | 2a "provisioned nothing" rides a single canary (wrapper symlink); no rootless-suite 2a — acceptable, note for adding it | yes |
| T6 | INFO | docs/troubleshooting.md:39–41 | "the sharing group gets `root`" is ambiguous — root is added to the opencode-owned group | yes |

Counters: **0 HIGH · 2 MED · 2 LOW · 6 INFO**. No ghosts; three verification
adjustments (S2, T4 downgraded; M1 trigger corrected — see below).

## Per-finding detail

### T1 (MED) — the V14 sweep pin misses the slash-less form, which is the old bug's exact shape

- **Mechanism:** the sibling-sweep pin negates `grep -q '/home/\$DEFAULT_USER/'`
  — trailing slash required. A functional site written as
  `[ -d "/home/$DEFAULT_USER" ]` or `chown … "/home/$DEFAULT_USER"` (no
  trailing slash) reintroduces the hardcoded-home class with the pin green.
  The slash-less `[ -d "/home/$DEFAULT_USER" ]` is *exactly* the pre-diff
  update.sh gate form (verified: `git show d3e187d:…/update.sh` line 747),
  so a partial revert is the realistic regression.
- **Live tree:** clean — sweep over `files/` finds six slash-less hits, all
  legitimate: the three getent-failure fallbacks (update.sh:447,
  uninstall.sh:296, status.sh:532), two comments (update.sh:442,
  status.sh:524), and install.sh:612's initializer that the next line's
  getent overwrites.
- **Provenance:** wave-introduced (the pin ships in this diff).
- **Fix direction:** negate the slash-less pattern and subtract the three
  known fallback lines (or anchor the fallbacks verbatim).

### T2 (MED) — new probe fallback arms are dead under test

- **Mechanism:** status.sh:530 and update.sh:764 add
  `id -u "$DEFAULT_USER" 2>/dev/null || echo 1`. Every pin that reaches
  these lines stubs `id()` to always succeed, so the `|| echo 1` arm never
  executes. Regression it guards: changed to `|| true`, an unresolvable
  developer yields empty ≠ "0" and the uid-0 loud-skip rows silently
  disarm — all pins stay green. Same gap for update.sh:446–447: the
  getent-miss `DEFAULT_HOME` fallback sits *outside* the sed-extracted
  hook block (the range starts at the section comment) and is covered
  only by the shape grep at tests/unit/test-update-flags.sh:568–571.
  Contrast: status.sh's getent miss *is* execution-pinned
  (`_hk_run rug-nouser-x ""`), and uninstall's is honestly declared
  shape-only.
- **Standing rule:** "every new `|| true`, stderr redirect, or probe pipe
  gets a pin that executes the failure path" (agent/conventions.md,
  learnings L2 class) — the wave ships three probes without one.
- **Provenance:** wave-introduced.
- **Fix direction:** one arm per probe — stub `id` to fail (assert the row
  is *not* the uid-0 defect) and run update's hook block with a getent miss
  (assert the loud missing-home skip).

### T3 (LOW) — the doc's uninstall step bounces in the doc's own context

- **Mechanism:** troubleshooting's Fix section explains the root-shell
  install defect, then says "uninstall it first (`opk uninstall`)". But
  `opk uninstall` execs as the invoking user (bin/opk:305) and
  uninstall.sh:97–101 refuses `root` — *before* install.conf is sourced at
  :181 — so from the root shell (the section's context) the command
  bounces with "Do not run as root or opencode". From the normal user the
  flow works end-to-end (install.conf's recorded `DEFAULT_USER=root`
  overrides at :181 → getent → `/root` → the sudo-wrapped cleanup now
  reaches it — the wave's healing intent, verified).
- **Severity rationale:** the refusal message self-explains and the reader
  recovers; the Fix's opening sentence already says "open a shell as your
  regular user". One explicit sentence closes it.
- **Provenance:** wave-introduced (the doc section ships in this diff).

### W1 (LOW) — no override for the root gate; guidance assumes a regular user exists

- **Mechanism:** unlike the distro gate (`--force-unsupported-distro`), the
  root gate has no escape hatch. On a root-only system (a minimal WSL
  distro whose default user is root, a dedicated VM) no install is
  possible without first creating a normal user — and the gate's guidance
  ("Open a shell as your regular user") presupposes one exists; neither
  the error nor the docs say to create one.
- **Severity rationale:** fail-closed is defensible (the issue's framing:
  such installs are unrepairable by design), so this is a design-acceptance
  question plus a doc hint, not a defect.
- **Provenance:** wave-introduced.

### S2 (INFO, downgraded from LOW in verification) — rc-file appends follow symlinks; reach widened

- **Mechanism:** `sudo tee -a "$cf"` (update.sh:780,794) follows a
  developer-owned rc symlink — pre-existing (the identical `tee -a` under
  the old `[ -d "/home/$DEFAULT_USER" ]` gate, verified at d3e187d). The
  wave widens the qualifying homes to getent-resolved ones, so relocated
  homes that previously skipped now receive appends.
- **Why INFO:** the payload is a fixed kit line, the developer side is
  trusted by the kit's model, and the developer already holds sudo — no
  new capability. The wave also moves the /root case in the *safe*
  direction: the uid-0 branch refuses loudly before any write where the
  old code silently skipped.
- **Provenance:** pre-existing class, delta-introduced reach.

### S1 (INFO) — deliberate SUDO_USER self-override

- **Mechanism:** `sudo env SUDO_USER=x bash install.sh` overrides SUDO_USER
  *inside* the sudo'd process, so the gate reads a chosen developer. What
  holds: line 578 resolves unconditionally (`${SUDO_USER:-$(whoami)}` — no
  preloadable env-default chain), the charset gate runs first, the arms
  fail closed, and `sudo -E` cannot inject (sudo re-sets SUDO_USER).
- **Why INFO:** the only trigger is the operator typing the override into
  an installer that already runs as root — self-deception, not attack.
- **Provenance:** pre-existing trust model, made load-bearing by the wave.

### M1 (INFO, trigger corrected in verification) — uninstall heals /root silently

- **Mechanism:** on a root-shell-broken install, `opk uninstall` from the
  *normal* user loads install.conf's `DEFAULT_USER=root`, getent resolves
  `/root`, and the plugin cleanup now really removes the registration
  there (old code looked at the nonexistent `/home/root`). Chain-gated by
  `agent_home_sane`; `tui-register.py` tolerates a missing cli.json.
- **Correction:** the axis agent's original trigger ("from a root shell")
  is wrong — whoami=root is refused at :97 before install.conf loads. The
  behavior itself is the wave's intent; the only gap is symmetry: status
  and update print an explicit uid-0 notice, uninstall just cleans.
- **Provenance:** wave-introduced.

### T4 (INFO) — uninstall comment mechanism understated

The comment's root-home scenario operates via install.conf (whoami=root
never reaches line 295); "recorded" carries that meaning correctly, so
this is precision only. No action required. — wave-introduced.

### T5 (INFO) — e2e 2a coverage notes

The refusal pin (rc≠0 + both message fragments + issue anchor at
install.sh:562) is sound; "provisioned nothing" rides the wrapper-symlink
canary alone — sound because the gate precedes all provisioning (verified
by line order), though install.conf/opencode-user canaries would be
stronger. No rootless-suite 2a — acceptable: the gate is
backend-independent and unit-pinned; note for whoever adds one: `E()` pins
`-u dev` in *both* suites (lib.sh:421), so a rootless 2a needs `-u 0`
too. — wave-introduced.

### T6 (INFO) — doc wording

"the sharing group gets `root`" (troubleshooting) — root is *added to* the
opencode-owned group; readable but imprecise. — wave-introduced.

## Verified clean (all axes, main-agent-verified)

- **Gate logic/arms:** pass = name≠root ∧ uid≠0, both arms independent and
  pinned with stubbed `id`; empty/missing user cannot reach the gate
  (charset case rejects `''` at install.sh:582–589); `|| true` and
  `${_rug_uid:-unknown}` are set-e/pipefail-safe.
- **Order:** charset (583–588) → root gate (593) → distro gate (626) →
  backup dir (656) → first prompt (636 menu comes after the gate; 486/497
  are function bodies). "Aborts before the first prompt" claim holds.
- **update.sh derivation order:** install.conf sourced at :435–436 →
  fallback at :439 → `DEFAULT_HOME` at :446–447; `DEFAULT_USER` has no
  later re-assignment, so `DEFAULT_HOME` cannot go stale; update.sh:427
  resets the var first, so exported env cannot preload it.
- **Block extraction:** all three sed ranges capture the intended blocks
  (start markers unique; inner `fi`s indented; first column-0 `fi` closes
  the outer block only) — status.sh 523→552, update.sh 757→803,
  install.sh 551→564.
- **Restructured hook section:** `bash -n` clean; the four `\`-continuations
  carry byte-identical sed/echo payloads (re-indentation only).
- **e2e modeling:** `E()` is `docker exec -u dev` — every pre-existing
  install invocation runs via `sudo` (SUDO_USER=dev) and is unaffected;
  2a's `docker exec -u 0` models the root shell in both images
  (Dockerfile:45 `USER dev`; Dockerfile.rootless has no USER).
- **Namespaces/anchors:** `_rug_*`/`_st_*`/`_du_*`/`_un_*` collision-free;
  the order pin's anchors ("Invalid user name", `^    _root_user_gate `,
  `^    _distro_gate `) match exactly once each.
- **Interpolation:** DEFAULT_USER reaches no sed script or command operand
  unvalidated in the management scripts; the sudoers re-deploy path
  re-validates via sudoers-deploy.sh (charset + `ALL` reject + visudo);
  install.conf is root-owned and *sourced* (code-exec precedes
  interpolation — no new boundary).
- **Gate exit path:** `log()` is best-effort (`log_init || return 0`,
  `printf … || true`) — cannot trip set -e; ui_error/ui_detail flush before it.
- **Docs-vs-code:** troubleshooting symptom quote matches install.sh:557–558
  verbatim modulo the `error  ` label; getting-started's SUDO_USER claim
  matches :578.
- **Sandbox policy:** new test writes live under suite scratch
  (`mktemp -d` WORK) only.
- **OPENCODE_USER twin:** the 27+ `/home/$OPENCODE_USER` sites are backed by
  an install-time invariant (install.sh:1146–1153 reuse guard refuses a
  deviating opencode home) — not an unswept sibling of this class.

## Run provenance, gates, environment

- **Agents:** 3 fresh-context GLM-5.3-Flash axis subagents (mechanical,
  security, claims/tests), ~8 min budget each, checkpointed to
  `/tmp/opencode/pr00196-review/{mechanical,security,tests}.md`; main agent
  (GLM-5.3) verified every finding against full-file reads, git history
  (`git show d3e187d:…`), and live file state. No fixing while verifying.
- **Gates run (main agent):** `make test` — all green (includes
  test-install-args/test-status/test-uninstall/test-update-flags with the
  new pins, reviews lint + parity, sandbox policy); `make lint` green.
- **e2e evidence (maintainer-run logs, this tree):**
  `logs/e2e-20261018-191212.log` — 303/303 passed incl. both new 2a checks;
  `logs/e2e-rootless-20261018-191212.log` — 47/47 passed.
- **Environment:** opencode 1.18.15 (e2e cache), WSL2 host, rootful outer
  docker, noble-based suite images.

## Recommendation

Ship-worthy: no behavior bug; the wave does what its PR claims and the
healing paths verify end-to-end. Before merge (or as an immediate fix
wave owed a micro-wave review per the stop rule): T1 + T2 pin hardening
(small test-only additions), T3/W1 doc sentences, S1 one-line comment
beside the gate. Everything else is taste-level.
