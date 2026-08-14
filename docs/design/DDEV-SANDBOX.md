# PLAN-DDEV-SANDBOX: Run ddev as the `opencode` sandbox user

> Status: **IMPLEMENTED (opt-in, default off).** The transaction helper
> (`files/opencode-permissions-kit-lib/ddev-transaction.sh`), the shim mode
> switch (`DDEV_MODE=delegated|sandbox` in install.conf), the mutually
> exclusive sudoers rendering, `config.sh ddev-mode`, `status.sh` reporting,
> the protect-projects heal, and unit + e2e tests are in the code. Usage
> documentation lives in `docs/MANUAL.md` ("ddev sandbox mode"). The design
> rationale and residual-risk analysis below is the historical planning
> record; where wording differs, the code wins. Rollout §9 is still at step
> 1 (delegated stays the default; `config.sh ddev-mode sandbox` is the opt-in).

## 1. Why this plan exists (PROOF-3 H3)

Today every `ddev` the agent invokes is re-executed **as the developer** via
`sudo -u DEFAULT_USER DDEV_BIN` (`opencode ALL=(DEFAULT_USER) NOPASSWD: DDEV_BIN`
in the sudoers). ddev executes **host-side custom commands** from
`.ddev/commands/host/` — a tree the agent can write (group `www-data`, setgid,
umask `002`). Consequences:

- The agent plants a script in `.ddev/commands/host/`, runs `ddev <name>` →
  host execution **as the developer**, outside every ACL deny (the deny rules
  only target the `opencode` user).
- Even without custom commands, `ddev exec` / `ddev ssh` reach the container,
  and with the docker-group backend container root reads everything
  (PROOF-3 C3).
- "ddev enabled" currently equals "the agent inherits the developer's host
  identity" (see `DOCKER-ROOTLESS.md` §4.1: "ddev is not securable on the
  ACL layer").

**Goal of sandbox mode:** ddev (and everything it spawns — host commands,
mutagen, container processes) runs as the **`opencode` user**, so the kit's ACL
denies apply to all of it. No code path executes as the developer. H3's
privilege gain disappears: a planted host command can read exactly what the
agent itself can read — nothing more.

## 2. Why delegation exists (the collision inventory)

The original "ddev runs directly as opencode" approach failed in practice
(CONTAINER-TOOLS.md §4.3). `ddev start` rewrites host-side files, and every
write collided with the kit's own protections:

| Path ddev touches | Owner / protection today | Collision when ddev runs as `opencode` |
|---|---|---|
| `config/system/settings.php`, `additional.php` | developer-owned, hard ACL `u:opencode:---` | EPERM — the deny targets exactly the ddev-launching user |
| `config/system/` (dir) | developer-owned `755`, no www-data write | EPERM — cannot create/replace files inside |
| `config/system/.gitignore` | developer-owned | EPERM |
| `.ddev/.webimageBuild`, `.dbimageBuild` | developer-owned; ddev `chmod`s them | EPERM — non-owners cannot `chmod`, ACL rwx is not enough |
| `~/.ddev` (global config, project registry, mutagen state, `ddev auth ssh` key cache) | developer's home | Would move to `/home/opencode/.ddev` — empty registry, **no SSH keys** |
| Docker daemon | developer's (docker group) | opencode needs its own daemon → rootless backend (already implemented) |

A sandbox mode must solve **each row** deliberately, not by accident. That is
what the transaction wrapper (§4) does.

## 3. Hard prerequisites

1. **Rootless backend owned by `opencode`** — `docker-rootless` or
   `podman-rootless` (kit-implemented, incl. linger + socket reachability).
   Rationale: containers must run under the `opencode` host UID so
   `u:opencode:---` holds **inside** bind-mounted containers
   (`DOCKER-ROOTLESS.md` §9.1, e2e-proven). On `docker-group`, container root
   (CAP_DAC_OVERRIDE) voids every ACL (PROOF-3 C3) — sandbox ddev on
   docker-group would be security theater. **Sandbox mode is only offered when
   the backend is rootless; on `docker-group` the shim keeps delegating.**
2. **ddev ≥ 1.25** (rootless support). The kit already records `DDEV_VERSION`
   and warns below 1.25 (`status.sh`).
3. **Router ports** — rootless cannot bind <1024 → projects must use
   `8080/8443` (or `ddev config --router_http_port`). Already a documented
   rootless constraint.
4. Unprivileged user namespaces available (given — the rootless backends
   already require them).

## 4. Architecture: a transactional ddev wrapper

The core idea: the file-write collisions are **temporary ACL/ownership states**,
so wrap ddev in an open→run→close **transaction** executed by a small root
helper — never by the agent directly.

```
agent: ddev start
  └─ /usr/local/bin/ddev (kit shim, new behavior in sandbox mode)
      └─ sudo /usr/local/lib/opencode-permissions-kit/ddev-transaction.sh \
               /var/www/vhosts/project start            # root, fixed argv
          ├─ OPEN:   chown -R opencode:www-data .ddev
          │          setfacl -m u:opencode:rwx  config/system        (dir)
          │          setfacl -m u:opencode:rw-  <rewritable files>   (deny strip)
          ├─ RUN:    runuser -u opencode -- env HOME=/home/opencode \
          │              DOCKER_HOST=unix:///run/user/<uid>/docker.sock \
          │              DDEV_BIN start                          # waits
          └─ CLOSE:  protect-projects.sh --force --cwd <project>    (self-heal)
                     chown -R DEFAULT_USER:www-data .ddev
                     setfacl -x u:opencode config/system ...
```

Key properties:

- **The agent cannot open without closing.** There is no sudoers entry for
  "open"; the only sudoable command is the whole transaction, and CLOSE runs
  in every exit path (`trap … EXIT INT TERM` inside the root helper).
- **A killed transaction self-heals.** If the agent SIGKILLs the wrapper to
  hold the window open, the state is merely "ACLs missing" — exactly the state
  every existing `--force` trigger repairs (git hooks, wrapper start,
  `config.sh` refresh). The kit's scan model is the safety net. A stale
  `.ddev` ownership also heals: the next developer-terminal ddev run goes
  through the same shim (pass-through path) … see limitation L3.
- **Read-only subcommands skip the transaction entirely.** `describe`, `exec`,
  `ssh`, `composer`, `logs`, `list`, `status` do not rewrite host files → the
  shim runs them directly as `opencode` (via `runuser`, no sudo, no open
  phase) → **no ACL window during the common long-running usage**. Only
  mutating subcommands open the transaction: `start`, `restart`, `config`,
  `stop`, `pull`, `push`, `snapshot`, `restore-snapshot`, `import-db`,
  `import-files`, `delete`, `debug rebuild` (list to be finalized against the
  ddev docs; default-deny: unknown subcommands are treated as mutating).
- **Host commands run confined.** `.ddev/commands/host/*` execute as
  `opencode` under the full ACL deny set — H3's privilege gain is gone. Same
  for mutagen and everything else ddev spawns.
- **The developer's own ddev is untouched.** Outside opencode the shim still
  passes through to the real ddev as before.

## 5. OPEN/CLOSE specification

Per project root (the root known to `projects.conf`):

| Action (OPEN) | Action (CLOSE) |
|---|---|
| `chown -R opencode:www-data .ddev` (build dirs need owner-`chmod`) | `chown -R DEFAULT_USER:www-data .ddev`; `fix_ddev_tree` semantics (group + mask repair) |
| `setfacl -m u:opencode:rwx config/system` (dir, TYPO3 layout) | `setfacl -x u:opencode config/system` |
| `setfacl -m u:opencode:rw-` on the type-specific rewrite list (below) | `protect-projects.sh --force --cwd <root>` re-applies `u:opencode:---` **and** chowns opencode-owned deny-matched files back to `DEFAULT_USER` (existing `apply_acls` behavior) |
| Stamp `/run/opencode-permissions-kit/ddev-txn/<hash>.open` (state marker for status/diagnostics) | Remove stamp |

The **rewrite list** is the only project-type-specific input:

- **TYPO3** (initial scope): `config/system/settings.php`,
  `config/system/additional.php`, `config/system/.gitignore`.
- Derived, not hardcoded: read from a per-project config
  `opencode.jsonc` key or a kit config file
  (`/etc/opencode-permissions-kit/ddev-rewrites.conf`), one glob per line.
  Projects with non-TYPO3 layouts extend it themselves.
- **Laravel is explicitly out of initial scope** — ddev manages `.env` there,
  and OPEN-ing `.env` (the most sensitive pattern) is exactly what this plan
  must not do silently. Documented as limitation L1.

CLOSE must be idempotent and safe to run twice (it mostly *is*
`protect-projects.sh --force` plus symmetric chown/ACL removal).

## 6. Component changes

| Component | Change |
|---|---|
| `files/opencode-permissions-kit-lib/bin/ddev` (shim) | Mode switch: `delegated` (today's behavior, default) vs `sandbox` (transaction for mutating subcommands, direct `runuser` for read-only ones). Mode read from `install.conf` (`DDEV_MODE=`), set only when backend is rootless. Pass-through for non-opencode users unchanged. |
| **new** `files/opencode-permissions-kit-lib/ddev-transaction.sh` | Root helper: validate argv (project root must be in `projects.conf`; subcommand must be on the mutating list), OPEN → `runuser` ddev as `opencode` with `HOME=/home/opencode`, rootless `DOCKER_HOST`/podman env → CLOSE via trap. ~150 lines POSIX sh. |
| `files/sudoers.template` | Add `opencode ALL=(root) NOPASSWD: /usr/local/lib/opencode-permissions-kit/ddev-transaction.sh *` (rendered only when `DDEV_MODE=sandbox`). The delegation rule (`opencode ALL=(DEFAULT_USER) … DDEV_BIN`) is rendered **only** for `delegated` mode — the two modes are mutually exclusive in sudoers. |
| `install.sh` / `update.sh` | Provision `/home/opencode/.ddev` (mode 755, `opencode:www-data`); write `DDEV_MODE`; render the mode-correct sudoers block; refuse `sandbox` unless backend ∈ {docker-rootless, podman-rootless} and ddev ≥ 1.25. |
| `config.sh` | `ddev-mode [delegated|sandbox]` subcommand mirroring `container-backend` (incl. validation + migration of the sudoers block). |
| `status.sh` | Report `ddev mode: sandbox (transactional)` or `delegated`, plus any stale `.open` stamps from killed transactions. |
| `protect-projects.sh` | No behavioral change needed — CLOSE reuses it. Optional: also heal a stale `.ddev` ownership (chown back to `DEFAULT_USER`) during `--force`, making the self-healing complete even without a CLOSE. |
| `files/opencode.jsonc` | **Unchanged.** Policy layer stays as-is: `ddev *` deny globally, project opts in with allow. Sandbox mode changes only *who executes* it, not *whether* the agent may. |
| `docs/MANUAL.md` | New section "ddev modes", incl. the SSH-key and port consequences. |

## 7. Security analysis

**What improves:**
- H3 closed for sandbox projects: `.ddev/commands/host/*` and all ddev
  children run as `opencode` under the ACL denies — planting a host command
  gains nothing over the agent's own bash.
- Combined with a rootless backend, `ddev exec cat settings.php` is now
  **denied in-container** (bind mount under opencode UID, §9.1 proof) — today
  it reads everything (docker-group + container root).
- The sudo surface shrinks conceptually: no RunAs-`(DEFAULT_USER)` rule in
  sandbox mode → the agent can never spawn a process as the developer.

**Residual risks (accepted / documented):**
- **R1 — the OPEN window.** While a mutating `ddev start` runs (potentially
  minutes), the rewrite-list files are readable by `opencode`. A malicious
  agent can run `cat config/system/settings.php` concurrently in a second
  shell. Assessment: same class as PROOF-1(a); confined to declared
  non-secret config files, only during mutating runs, and ddev must be
  explicitly allowed by the project anyway (a trust decision that today
  grants *far* more — the whole developer identity). Narrower than the status
  quo in every dimension.
- **R2 — SIGKILL'd transaction.** Agent kills the wrapper to hold R1 open.
  Mitigated: every `--force` trigger heals the ACLs (git hooks fire on the
  agent's own next git op; wrapper start heals on next session);
  `status.sh` surfaces stale stamps. Worst case equals PROOF-2's window.
- **R3 — root helper argv.** `ddev-transaction.sh` runs as root with an
  agent-controlled argv. Mitigations: root must be in `projects.conf`
  (exact string match, no globs), subcommand validated against a fixed list,
  **no `eval`, no pattern interpolation from project files** (the PROOF-3 C1
  lesson — the rewrite list is read from a **root-owned** kit config file,
  never from the writable project tree), `chown -R` targets bounded by
  `<root>/.ddev` via a hardened path join. Code review gate: this file gets
  the same scrutiny as protect-projects.sh post-C1.
- **R4 — sudo env.** ddev as opencode gets `DOCKER_HOST` etc. from the
  transaction, not from the agent's inherited env (root helper constructs the
  env explicitly — no `env_keep` reliance for the child).

**What does not change:** raw `docker` (already rootless-as-opencode), the
policy layer, the ACL scan model, PROOF-1/2 timing gaps.

## 8. Testing plan

Unit tests (no Docker, mirroring `test-ddev-shim.sh` style):
- Mode switch logic: sandbox requires rootless backend + ddev ≥ 1.25;
  docker-group falls back to delegated with a warning.
- Subcommand classification: mutating vs read-only; unknown = mutating.
- Transaction helper: OPEN actually strips denies only on the rewrite list;
  CLOSE restores (`getfacl` assertions); CLOSE runs on non-zero ddev exit and
  on SIGTERM; argv validation rejects roots not in `projects.conf`.
- Rewrite-list loading only from the root-owned kit config.

E2E (extend `tests/e2e/run.sh` / the rootless suites with the ddev stub):
- Stub records the invoking user: in sandbox mode it is **opencode**, never
  `dev` (inverse of today's 12h delegation check).
- Fake "ddev start" (stub) that tries to read `.env` as opencode → EPERM
  during the transaction (proves the window excludes secrets).
- After the stubbed mutating run: ACLs on `settings.php` restored,
  `.ddev` ownership back to `dev`, no stale stamp.
- SIGKILL the transaction → run any git hook → ACLs healed (self-heal proof).
- Sudoers: `(DEFAULT_USER)` ddev rule absent in sandbox mode.

## 9. Rollout

1. Implement behind `DDEV_MODE=delegated` default — zero behavior change for
   existing installs (`update.sh` preserves the mode).
2. `config.sh ddev-mode sandbox` as the opt-in path; validate prerequisites.
3. This dev workspace flips first (rootless backend already present), runs the
   real TYPO3 workflow (`ddev start` on a fixture project) for a burn-in.
4. Only after burn-in: consider making `sandbox` the default for new rootless
   installs. `delegated` stays available and documented.

## 10. Limitations & non-goals

- **L1 — Laravel `.env`:** out of scope; projects where ddev manages a deny
  pattern file must stay `delegated` (or extend the rewrite list consciously,
  accepting R1 on that file).
- **L2 — no private composer repos / `ddev auth ssh`:** sandbox ddev has no
   SSH keys (deliberate — handing the agent the developer's keys would be a
   far bigger hole than H3). Composer from private repos stays a
   developer-terminal task.
- **L3 — two ddev drivers:** developer (terminal, their daemon) and agent
   (rootless daemon) must not drive the same project simultaneously — router
   port and `.ddev` ownership conflicts. Documented "one driver at a time";
   optional later: a lockfile in `.ddev`.
- **L4 — mutagen performance** under a UID-shared rootless daemon is untested
   at scale; burn-in will tell.
- Non-goal: sandbox ddev on the `docker-group` backend (see §3.1).

## 10a. Open TODOs (burn-in findings, 2026-08-14)

- **TODO: TYPO3 project does not boot via the sandbox path.** The container
  reaches the site, but PHP cannot read the settings file it itself
  generated during the transaction:
  `Warning: require(/var/www/html/config/system/settings.php): Failed to
  open stream: Permission denied in
  /var/www/html/vendor/typo3/cms-core/Classes/Configuration/ConfigurationManager.php
  on line 121` — reported at https://pc-database-v2.local/
  The agent-side `ddev start` (open) now completes without the chmod error,
  but the web container's PHP process is denied read access to
  `config/system/settings.php`. Working theory: the file is written as
  `opencode` (the sandbox user) during OPEN but stays opencode-owned/unreadable
  for the container's `www-data`; or the rewrite-list CLOSE re-asserted
  `u:opencode:---` / ownership too early. Next steps: inspect the file's
  owner/mode/ACL right after `ddev start` (open vs. after close), and check
  whether the container mounts the project with a UID-mapped root that does
  not share the `opencode` UID. Untested hypothesis (see L4): UID-shared
  rootless daemon + mutagen.

## 11. Effort estimate

| Phase | Content | Estimate |
|---|---|---|
| 1 | Transaction helper + shim mode switch + sudoers/config plumbing | 1–2 days |
| 2 | config.sh/status.sh/install/update integration + rewrite-list config | 1 day |
| 3 | Unit + e2e tests (incl. self-heal and kill cases) | 1–2 days |
| 4 | Real-world burn-in (this workspace, TYPO3 fixture), docs | 1 day |

Blocking dependency: PROOF-3 **C1 must be fixed first** — the transaction
helper is root code in the same trust domain as protect-projects.sh, and the
rewrite list must never become a second eval-injection vector.
