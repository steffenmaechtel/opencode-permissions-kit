# PROOF-3: Remaining Gaps in the opencode permissions kit

> **SUPERSEDED (DDEV-WORKING):** the hard ACL deny layer this document
> analyzes/proposes was **removed** — file permissions are now opencode's
> soft permission layer only. This document is kept as the historical
> analysis record; see `docs/design/ddev-working.md` for the current model
> and `docs/concepts/security-model.md` for the authoritative
> usage documentation. Where wording differs, the code and the docs win.
> A **Status addendum (2026-08-15)** at the bottom of this file maps every
> finding to its fate in the shipped design.

**Question under test.** Beyond the timing windows analyzed in PROOF-1 (git pull race,
object database, mtime cache) and PROOF-2 (no listener for developer-created files) —
what other gaps exist in the kit?

**Method.** Manual review of `repo/files/` (wrapper, protect-projects.sh,
jsonc-parser.py, hooks, sudoers template, ddev shim, opencode.jsonc template,
install.sh) with the threat model **"the sandboxed opencode agent is the adversary"**.
Findings are ranked Critical / High / Medium. Line numbers refer to the current state
of the repo.

---

## Critical

### C1. Root command injection via pattern `eval` in protect-projects.sh

**Chain: attacker-controlled config → unsanitized pattern → `eval` → root shell.**

1. Project trees are group `www-data`, setgid, umask `002` — and the `opencode` user
   is a member of `www-data` (`install.sh:343`). Therefore **opencode can create or
   edit `<project-root>/opencode.jsonc`**, which protect-projects.sh parses for deny
   patterns (`protect-projects.sh:304-318`).
2. The parser (`jsonc-parser.py:99-104`) prints pattern strings **verbatim, with no
   filtering**.
3. `build_find_args()` embeds each pattern into a double-quoted string
   (`protect-projects.sh:160-163`) which is later executed via
   `eval "find ... $find_args ..."` (`protect-projects.sh:191`, also `:197`, `:210`).
4. A pattern containing `$(...)` (or a closing `"`) executes **arbitrary commands as
   root** at eval time — command substitution inside double quotes fires before
   `find` even runs.
5. The trigger needs no social engineering: the sudoers template grants the opencode
   user the right to run protect-projects.sh as root itself
   (`sudoers.template:26`: `opencode ALL=(root) NOPASSWD: .../protect-projects.sh *`).
   Every git hook is an alternative trigger.

**PoC** (as the opencode user, inside any registered project root):

```json
// opencode.jsonc — written by the agent into the project root
{ "permission": { "read": { "$(touch /tmp/KIT-PWN)": "deny" } } }
```

```bash
sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force
# → /tmp/KIT-PWN now exists, owned by root
```

**Impact:** complete sandbox escape to root — the ACL model (and everything else)
is void.

**Fix (defense in depth, both recommended):**

- In `jsonc-parser.py`: validate patterns against a strict charset
  (e.g. `^[A-Za-z0-9._*/?*-]+$`) and refuse (exit non-zero) anything else.
- In `protect-projects.sh`: stop building eval strings. Loop over patterns and call
  `find "$root" -type f -name "$pattern"` per pattern (no eval), or use
  `find ... -print0 | xargs -0` composition. The `eval` exists only to combine `-o`
  predicates — not worth root RCE.
- Optionally: chown project-root `opencode.json[c]` to `DEFAULT_USER` and strip the
  group-write bit for the *file itself* (keep the tree writable), so the agent
  cannot author the config that root executes. Note this conflicts with teams that
  legitimately commit their own project config — then the parser/script fix is the
  real boundary.

### C2. Git hooks are suppressible by the agent — PROOF-1's "safe" chain is only safe against a *benign* agent

The PROOF-1 verdict for `git pull && cat .env` rests on the post-merge hook running.
But git offers the agent at least three ways to run a pull **without** the kit's
hooks:

- **Command-line config override:** `git -c core.hooksPath=/var/empty pull ...`
  (`-c` has the highest config precedence; core.hooksPath set this way disables all
  hooks for that invocation).
- **Repo-local config:** `.git/` is group-writable (setgid tree + umask 002), so the
  agent can persist `core.hooksPath` in `.git/config` once and every future git op
  in that repo silently skips the kit's hooks (repo-local overrides the global
  `core.hooksPath` the kit sets at `install.sh:634-635`).
- **Env injection:** `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath
  GIT_CONFIG_VALUE_0=/var/empty git pull ...`.

With hooks suppressed, the merged `.env` is created by the agent's own git process —
**opencode-owned and readable** — and `cat .env` succeeds (see PROOF-1 §"ownership
gap"; the fix-up only runs inside the hook).

**Classification:** this is not a bug in a component but a broken assumption:
**git hooks are a convenience layer, not a security boundary against the sandboxed
agent.** The agent controls the git invocation, its config, and the environment.

**Mitigations (all partial):**

- Deny `git -c *` and `git *--config*`… in the bash permission rules (soft — glob
  matching on the literal command string is trivially evaded with quoting/spacing,
  and env-var injection isn't matched at all).
- Enable SECURE_GIT (deny `.git/config` read/edit — currently commented out in
  `files/opencode.jsonc:47-48`) so at least the *editor* path into repo config is
  closed; bash-level edits remain ask-gated only.
- **The real compensating control is event-based re-protection** (fanotify/inotify
  watcher or systemd path units re-running `protect-projects.sh --force`) plus
  `--force` at wrapper session start. Until such a mechanism exists, mid-session
  hook-less writes stay unprotected until the next manual/`--force` trigger.

**Amendment to PROOF-1:** conclusion 1 ("no timing window") holds only under the
assumption that hooks actually run. Against an adversarial agent they don't.

### C3. docker-group backend = root-equivalent (documented default, but it voids the ACL model)

- With the docker-group backend the wrapper execs
  `sudo -u opencode -g docker` (`wrapper:275`); membership in the `docker` group is
  host-root-equivalent (unauthenticated access to `/var/run/docker.sock`).
- Container root ignores the kit's ACL denies (`CAP_DAC_OVERRIDE`) — a bind-mounted
  project directory is **fully readable inside the container** regardless of
  `u:opencode:---`: `docker run -v "$PWD:/p" alpine cat /p/.env` returns the secret
  even on a "protected" file.
- install.sh itself labels it correctly (`install.sh:274,278`:
  "docker-group (default) gives root-equivalent host access") and the rootless
  backends preserve the ACL model because containers run under the opencode host UID
  (`docs/design/docker-rootless.md` §9.1, wrapper comment at `:281-285`).

**Gap:** for any project that enables docker tools with the docker-group backend,
every confidentiality guarantee of the kit is conditional on "the agent chooses not
to mount the project". Per-project opt-in + bash-level `docker *` deny in the stock
template reduce accidental use, but a prompt approval or a custom allow rule opens
the full break.

**Recommendation:** treat docker-group + project docker opt-in as a *trusted-container
mode* and say so explicitly in MANUAL.md; push rootless/podman as the default for new
installs (already possible via `--container-backend`).

### C4. TOCTOU symlink races: root-side `chown`/`chgrp`/`setfacl` follow symlinks over an agent-writable tree

protect-projects.sh runs as root and walks trees the opencode user can write.
Classic lstat→act races:

- `apply_acls`: `find ... -user opencode -exec chown DEFAULT_USER:www-data {} +`
  (`protect-projects.sh:197`) — `chown` **dereferences** symlinks. Swap a matched
  entry for a symlink between find's check and the exec → root chowns an arbitrary
  path (e.g. `chown developer /etc/passwd`).
- `fix_ddev_tree`: `chgrp www-data` via xargs (`:250`) and
  `setfacl -m g:www-data:rwx` (`:264`) — race-swapped symlinks let the agent get
  **arbitrary files group-readable/rwx by www-data**, and the opencode user is in
  www-data → read `/etc/shadow` etc.

The windows are tiny, but the attacker controls the directory and can retry on every
hook/sudo trigger (which it may fire itself, see C1).

**Fix:** use non-dereferencing operations — `chown -h`, `chgrp -h`, `setfacl -h`
(symlinks get skipped/error harmlessly), plus `find ! -type l` pre-filters where
possible; residual races shrink to near-zero. Long term, an O_NOFOLLOW-based walker
would be the clean solution but exceeds POSIX sh.

---

## High

### H1. Template bash-allowlist leaks file content: `git log *` / `git diff *`

`files/opencode.jsonc:102-103` allowlists `git status *`, `git diff *`, `git log *`
(prompt-free). These take path arguments that can target denied files:

- `git log -p --all -- .env` → prints the secret **from the object database** even
  with perfect worktree ACLs (compounds PROOF-1 §b; needs no race and no prompt).
- `git diff HEAD^ -- .env` → worktree read when the file is in an unprotected window
  (PROOF-2), or ODB read for committed content.

**Fix:** narrow the allows (`git log`, `git log --oneline` without `*`, or split
flag-only variants), or accept + document that anything git ever tracked is
agent-readable without a prompt.

**Status: MITIGATED (soft).** The template now mirrors the read/edit deny patterns
into `permission.bash` as `ask` rules placed after the allowlist (see
`files/opencode.jsonc`, "SENSITIVE FILE TRIPWIRE"). Literal-name commands like
`git log -p -- .env` drop from allow to ask — the developer decides false positive
vs. unwanted access. Residual: the tripwire is lexical (`F=.env; cat $F`, `cat .en?`,
`find -exec` evade it) and an approved ask still reads the file; the ODB read
remains possible after approval. Documented in MANUAL.md.

### H2. Copies/archives escape the protection scope permanently

Protection is scoped to `projects.conf` roots. Anything the agent copies out during
an unprotected window (PROOF-1 races, PROOF-2 window, C2) — `cp .env /tmp/x`,
`tar czf /tmp/proj.tgz .env`, `gzip -c .env > notes.txt.gz` — is outside every
future scan and stays readable forever. Note `*.sql.gz` is denied but a
`*.tar.gz`/`*.tgz` of the project is not matched by any pattern.

**Mitigation options:** none at ACL level (out-of-scope by design); rely on the
default-ask bash gate (tar/cp are ask — the residual risk is user approval), and
document the boundary. A tmpwarts-style /tmp cleaner is orthogonal.

**Status: PARTIALLY MITIGATED (visibility).** `status.sh` now ends with a
report-only **leak scan**: a name-based sweep of `/tmp`, `/var/tmp`, `/dev/shm`
(overridable via `LEAK_SCAN_DIRS`) for files matching the global deny patterns.
It catches lazy copies (`cp .env /tmp/backup`) for manual inspection, logs a
finding line to the audit log when run as root, and never modifies files outside
the project roots. Residual: renamed copies stay invisible (no content DLP),
unprivileged runs cannot see inside `0700` directories, and false positives are
expected. The boundary itself ("locations, not information flows") is now
documented in MANUAL.md, with a pointer to pre-commit secret scanning (gitleaks)
for the git side.

### H3. ddev delegation = arbitrary host command execution as the developer

The shim re-execs every `ddev` as `DEFAULT_USER` (`bin/ddev`, sudoers rule
`opencode ALL=(DEFAULT_USER) NOPASSWD: DDEV_BIN`). ddev executes **host-side custom
commands** from `.ddev/commands/host/` — a tree the agent can write (www-data). So:

1. agent writes `.ddev/commands/host/pwn` (a shell script),
2. agent runs `ddev pwn` → shim → `sudo -u developer ddev pwn` → **host execution
   as the developer**.

The stock template's `ddev *` bash deny (opencode.jsonc:132) is the only gate, and
AGENTS.md already notes subcommand gating is soft. In workspaces that allow ddev
(this dev workspace) the exec is one approval away.

**Mitigation:** subcommand allowlist inside the shim (start/stop/restart/status/
exec/launch only, reject unknown), or deny-by-default with per-project opt-in;
document `ddev ssh` and host-commands as the risk anchors either way.

**Status: MITIGATED (opt-in sandbox mode).** `config.sh ddev-mode sandbox`
(rootless backends only) now runs ddev — including `.ddev/commands/host/*` —
as the `opencode` user inside a root-side OPEN/RUN/CLOSE transaction, and the
RunAs-developer sudoers rule is removed in that mode (see
`docs/design/ddev-sandbox.md`, implemented). Delegated mode remains the default
and keeps this gap; the residual risks of the sandbox mode (temporary OPEN
window on the rewrite list, kill-the-transaction) are analyzed in the plan §7.

---

## Medium

### M1. Protected files are deletable/renamable (integrity/availability gap)

The deny ACL is per-inode and stops read/write, but the *directories* are
group-writable (by design — opencode must create files). No sticky bit → the agent
can `rm .env`, `mv .env .env.old`, or replace it with its own file (content unknown
to it, so this is vandalism/DoS, not disclosure). Worth stating in the threat model:
the kit protects **confidentiality** of sensitive files, not their existence.

### M2. `.git` is agent-writable in general

Beyond C2: `.git/config` (credentials, insteadOf URLs), `.git/objects` (PROOF-1 b),
`.git/index`. SECURE_GIT exists but ships commented-out
(`opencode.jsonc:47-48,80-81`). Recommendation: enable it by default in the template
or at least surface it in install.sh's summary; it costs little (agent rarely needs
to read .git/config via tools).

*Status update (issue #17):* the group baseline now covers `.git` (group-writable
for the agent, still developer-owned). That makes this mitigation-relevant again —
the soft `.git/config` deny/tripwire is the only guard, see the M2 row in the
summary table.

### M3. Supply chain: `curl | sudo bash` from `master`, unsigned

install.sh/update.sh self-fetch siblings from `KIT_BRANCH` (default `master`) via
raw GitHub URLs with **no checksums, no signatures, no pinning**. Any push to master
(often: any compromise of a maintainer account or the repo) is mass-RCE on every
developer machine at the next update. Mitigations: commit-hash pinning with a
checkpoint file, or at minimum a documented "review diff before update" workflow.

### M4. Audit-log injection

`log()` writes attacker-influenced strings (file paths, project roots, CWD) into the
audit log. An agent can craft names containing newlines/forge-looking prefixes to
plant fake event lines, polluting later forensics. Low severity (the log is for
humans), fix would be trivial sanitization in `log.sh` (strip control chars).

### M5. `OPENCODE_LAUNCH_CWD` is agent-influenceable

The var is exported by the wrapper but lives in the agent's environment and survives
sudo (`sudoers.template:12` env_keep) — the agent can set it arbitrarily when
invoking git/hooks directly. Alone it only selects *which* config governs
(read-only walk-up, `protect-projects.sh:105-118`), but it is the perfect delivery
vector for C1 (point resolution at the injected config). Harmless once C1 is fixed.

### M6. Recap of the known scan-model gaps (detail in PROOF-1/2)

- Wrapper startup scan runs **without `--force`** and is cache-skipped
  (`wrapper:265`, `protect-projects.sh:131-140`) — restart does not protect new
  files.
- No filesystem event watcher: IDE/cp/download-created sensitive files stay open
  until the next `--force` trigger.
- Git object database readable by design (agent performs fetches).
- Background-pull race (PROOF-1 a).

**Single most effective compensating control:** `--force` at wrapper session start +
an event-based (fanotify/systemd-path) re-scan for mid-session hook-less writes.

---

## Priority matrix

| ID | Finding | Severity | Effort | Recommended order |
|---|---|---|---|---|
| C1 | eval pattern injection → root RCE | Critical | Low (parser charset + no-eval rewrite) | **1 — now** |
| C2 | git hooks suppressible (`-c`, repo config, env) | Critical* | High (needs event-based re-protection) | 3 |
| C3 | docker-group backend voids ACLs | Critical* (documented) | Docs/default-change | 4 |
| C4 | TOCTOU chown/chgrp/setfacl symlink races | Critical | Low (`-h` flags) | 2 |
| H1 | `git log *` / `git diff *` allow leaks content | High | Low (rule narrowing) | 5 |
| H2 | Copies/archives escape scope | High | Leak scan (status.sh) + docs | 6 |
| H3 | ddev host-commands exec as developer | High | Medium (shim allowlist) | 7 |
| M1–M6 | integrity, .git, supply chain, log, env, scan model | Medium | mixed | 8+ |

\* C2/C3 are "critical only under an adversarial-agent threat model"; under the
kit's original benign-agent assumption they are known trade-offs. Decide and
document which threat model the kit officially claims — that decision drives how
much of this list is a bug report vs. a MANUAL.md paragraph.

## Verified assumptions

- opencode user is in `www-data` (`install.sh:343`) and trees are setgid+umask 002
  → agent can author project `opencode.jsonc`, `.git/config`, `.ddev/commands/host/`.
- Parser output is unfiltered (`jsonc-parser.py:99-104`); patterns reach `eval`
  (`protect-projects.sh:191,197,210`).
- opencode user may sudo protect-projects.sh as root (`sudoers.template:26`).
- docker-group is the default backend and is root-equivalent by the installer's own
  wording (`install.sh:274,278`).
- Not yet e2e-verified: the exact hook-firing behavior for `git pull --ff-only` /
  `--rebase` variants (post-merge vs post-checkout coverage) — add a case to
  `tests/e2e` when addressing C2.

---

## Status addendum (2026-08-15, soft-only model)

> Re-assessment of every finding below against the shipped DDEV-WORKING
> design (ddev always runs as the `opencode` user, rootless-only backends,
> no hard ACL layer, sharing group = opencode usergroup). The threat-model
> question from the footnote above was answered in the process: the kit
> now explicitly claims **"soft-only"** — file denies gate opencode's
> tools, UID separation carries the hard guarantees. That decision turns
> most of this document from a bug report into design record.

| ID | Finding | Status in the current design |
|---|---|---|
| C1 | eval pattern injection → root RCE | **Closed.** `protect-projects.sh`, the hooks, and the whole root-side parser path were removed; `migrate-denies.sh` sweeps the artifacts from legacy installs. No root code consumes agent-authored config anymore. |
| C2 | git hooks suppressible | **Closed.** The hook machinery is gone entirely; `update.sh` unsets `core.hooksPath` on legacy installs. |
| C3 | docker-group backend voids ACLs | **Closed.** Rootless-only: `install.sh` aborts without a rootless backend, `update.sh`/`migrate-denies.sh` refuse legacy docker-group installs with re-install instructions, the wrapper shows a loud warning on a stale conf value. |
| C4 | TOCTOU chown/chgrp/setfacl symlink races | **Mitigated, residual risk accepted.** Kit tree-walks now use `find -type d -name .ddev` (never follows symlinks) and plain `chown/chgrp/chmod -R`/`setfacl` are physical (non-symlink-following) for the recursive walk. Remaining window: a racing agent renaming/planting paths between the `find` and the per-path operation during install/update/refresh — a root-run batch job over a group-writable tree. Documented, not further hardened. |
| H1 | `git log *` / `git diff *` allow leaks content | **Mitigated in the template.** The sensitive-file tripwires (`*additional.php*`, `*.env*`, …) are deliberately ordered AFTER the allow rules — last match wins, so `git diff -- .env` becomes `ask`. Residual: the tripwire is lexical only (variables, globs, indirection evade it); documented in MANUAL.md as the last line of defense. |
| H2 | Copies/archives escape scope | **Accepted + visibility aid.** "The kit protects locations, not information flows" is the documented scope boundary; `status.sh` ends with a report-only name-based leak scan of the scratch dirs. |
| H3 | ddev host-commands exec as developer | **Closed by redesign.** ddev runs as `opencode` everywhere (terminal `ddev()` function + sudoers helper); the sudoers carry **zero** RunAs-developer rules. |
| M1 | protected files deletable/renamable | **Accepted** (soft-only: integrity/availability are not OS-enforced). |
| M2 | `.git` agent-writable | **Accepted, soft-mitigated.** Since the issue-#17 baseline change the `.git` tree is group-writable for the agent (deliberate: the agent's git must read the repository). `.git` stays excluded from the ddev handovers (never chowned to `opencode`), and `.git/config` remains guarded by the soft deny + bash tripwire — integrity of `.git` is not OS-enforced, consistent with the soft-only model. |
| M3 | supply chain: `curl \| sudo bash` from master, unsigned | **Open** (roadmap). Install tracks `master` by design during alpha; tagged/signed releases are the known follow-up (see the repo's planning notes). |
| M4 | audit-log injection | **Closed.** The log is root-owned 640 in the default user's group; the `opencode` user can neither read nor write it; entries are written by root-side kit scripts only. |
| M5 | `OPENCODE_LAUNCH_CWD` agent-influenceable | **Closed.** The variable no longer exists; the wrapper validates the CWD against `projects.conf` itself. |
| M6 | scan-model gaps (PROOF-1/2) | **Moot/accepted.** PROOF-1/2 analyzed the removed ACL layer; in the soft-only model their timing questions reduce to the documented tripwire limitations (H1 residual). |

**New known gaps of the current design (not in the original list):**

- `ddev auth ssh` / composer private keys live in `/home/opencode/.ddev` and are
  agent-readable — the accepted price of "ddev must read settings.php"
  (MANUAL.md, Security Model).
- The ddev handover hands `.ddev/` and the app-type settings dirs
  (`config/system`, `typo3conf`, `sites/default`, `app/etc`) to the agent user
  as **owner**. ddev requires ownership (unconditional chmod); protection of
  the contained files rests entirely on opencode's soft deny/ask rules.
- Bash tripwires are the last line of defense for bash-spawned reads — no
  OS backstop exists by design (soft-only).
- WSL2 only: the drvfs `/mnt/c` mount is world-readable by default and
  exposes the Windows profile to every WSL user incl. the agent — the kit
  reports it and offers a `wsl.conf` fix, but cannot enforce it (host-level).

**Net result:** of the actionable findings, C1–C3, H3, M4, M5 are closed by
the redesign; C4/H1 carry documented residuals; H2/M1/M6 are accepted scope
boundaries. The one open engineering item is M3 (signed/tagged releases).
