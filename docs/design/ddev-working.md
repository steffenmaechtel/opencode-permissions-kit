# PLAN-DDEV-WORKING: Drop the hard ACL deny layer, keep ddev working

> Status: **IMPLEMENTED (all phases done).** Soft-only model shipped:
> wrapper/sudoers/install/update/config/status/uninstall rewritten, hard-deny
> migration (`migrate-denies.sh` + `HARD_DENY_REMOVED` stamp) in place,
> parser `--allow` removed (default deny mode kept — status.sh's leak scan
> consumes it), dead files deleted, CI/Makefile/e2e updated (`make e2e`
> green: 183 checks), docs rewritten. Where this plan conflicts with the
> code, the code wins. This is the design record for the epic change
> sketched in the (internal) `local/MAJOR_CHANGE.md`.

## 1. Problem

The kit's second job — mirroring `opencode.jsonc` `read`/`edit` deny rules
into hard Linux ACL entries (`u:opencode:---`) via `protect-projects.sh` —
breaks ddev when ddev runs **as the opencode user** (the only secure ddev
mode). The inner project must read files the kit hard-denies:

- `config/system/settings.php` (TYPO3) — `*settings.php: deny` → hard ACL →
  web container cannot boot.
- `.ddev/commands/<svc>/README.txt` — already relaxed to `"ask"` for exactly
  this reason (see template comment); every further collision would need
  another carve-out.

The transaction helper (`ddev-transaction.sh`, OPEN/RUN/CLOSE) exists to
juggle exactly this conflict. It is complex, root-powered, and only needed
because of the hard denies.

## 2. Decision

**Remove the file read/edit hard-deny layer completely.** File protection is
opencode's own SOFT permission layer (`opencode.jsonc`), nothing more. The
kit's remaining purpose:

1. Create the dedicated `opencode` user (WSL2, also native Linux).
2. Run containers rootless (docker-rootless or podman-rootless) as that user.
3. Run ddev as that user (no delegation, no transaction).
4. Keep the group-collaboration baseline (setgid, default group ACLs,
   umask 002) so developer and agent can share files — now on the
   **`opencode` user's own private group** instead of `www-data`.

**Removed modes:** `docker-group` backend, `DDEV_MODE=delegated|sandbox`
(there is only one ddev mode now: as-opencode), the ddev delegation shim,
the git hooks, the ACL deny machinery, the transaction helper.

### 2.2 Sharing group: reuse the `opencode` usergroup (no `www-data`)

`useradd -m opencode` already creates a private group named `opencode`
(the user's primary group). The kit reuses it as the sharing group:

- No new group to create or remove — the group lives and dies with the
  user (`userdel` cleans it up once the developer is no longer a member).
- No name-collision trap: creating a group named `opencode` **before**
  `useradd` would make `useradd` fail (group exists). Reuse sidesteps it;
  the ordering (user first, then `usermod -aG opencode $DEFAULT_USER`) is
  the only thing install.sh must get right.
- `www-data` is vestigial on WSL2+DDEV: the web server runs in the
  container; the host group's only job is developer↔agent sharing, which
  any shared group + setgid + umask 002 does identically. Rootless
  containers run as the opencode UID, so owner bits (not the group) govern
  container access anyway.
- Host-side Apache/Nginx consumers of `www-data` lose group access. If a
  developer serves files with a host webserver, they must add its user to
  the `opencode` group (or chgrp the docroot) — documented in MANUAL.md,
  not a kit question. Consequence: the "Group 'www-data' already exists?"
  install prompt disappears entirely.
- `WWW_GROUP` stays a variable read from `install.conf` (now
  `WWW_GROUP=opencode`); all scripts are already group-agnostic.
  `protect-projects.sh` dies anyway, so its `chown :$WWW_GROUP` usage goes
  with it.

### 2.1 Security story (rewrite, do not just delete)

The old justification for rootless was "ACL denies hold inside containers"
(PROOF-3). That argument dies with the deny layer. The new rationale:

- **UID separation**: agent processes run as `opencode`, not as the
  developer. No developer credentials, SSH keys, or dotfiles are reachable
  (they live in `/home/<developer>`, mode 750).
- **No root-equivalent socket**: rootless backend only — the agent can never
  reach the host docker socket that grants container-root.
- **No RunAs-developer channel**: the delegated ddev sudoers rule is gone;
  no code path executes as the developer.

**Trade-offs that must be documented openly (MANUAL.md, PROOF docs):**

- SOFT rules are enforced by the opencode process itself. Inside a container
  with bind mounts, file reads are unrestricted — that is inherent to the
  "ddev must work" goal, not an accident.
- SECURE_GIT becomes soft-only: `cat .git/config` via bash is no longer
  blocked by the OS. The template keeps the read/edit deny (opencode tools
  respect it); a bash tripwire entry (`*.git/config*": "ask"`) should be
  added to the template as partial compensation.
- `"docker *": "deny"` + project opt-in (`--tools` detection in the wrapper)
  remains the gate for container access and must stay strict.

## 3. File-by-file impact

### Deleted

| File | Reason |
|---|---|
| `files/opencode-permissions-kit-lib/protect-projects.sh` | the deny layer |
| `files/opencode-permissions-kit-lib/ddev-transaction.sh` | nothing to transact |
| `files/opencode-permissions-kit-lib/hooks/post-checkout` | deny refresh trigger |
| `files/opencode-permissions-kit-lib/hooks/post-merge` | ditto |
| `files/opencode-permissions-kit-lib/hooks/post-commit` | ditto |
| `files/opencode-permissions-kit-lib/bin/ddev` | delegation shim; ddev now runs natively as opencode |
| `tests/test-hooks.sh` | hooks gone |
| `tests/test-ddev-shim.sh` | shim gone |
| `tests/test-ddev-sandbox.sh` | transaction gone |
| `tests/test-project-config.sh` | tested protect-projects pattern→ACL logic |

### Kept unchanged (or nearly)

| File | Notes |
|---|---|
| `files/umask.sh` | group-collab baseline |
| `files/opencode-deny-all.jsonc` | default-user bypass guard still valid |
| `files/opencode-permissions-kit-lib/log.sh` | audit log stays |
| `files/opencode-permissions-kit-lib/shell-warn.sh` | bypass warning stays |
| `files/opencode-permissions-kit-lib/setup-container-backend.sh` | rootless provisioning; docker-group teardown path removed |
| `files/opencode-permissions-kit-lib/bin/socket-check.sh` | wrapper socket probe stays |
| `tests/test-jsonc-parser.sh`, `test-git-config.sh`, `test-bypass-guard.sh` | parser `--tools` mode still used; `test-git-config.sh` moves off the parser's default mode in Phase 6 (grep-based) |
| `tests/test-container-backend.sh` | rootless cases only |

### Rewritten

| File | Changes |
|---|---|
| `files/opencode-permissions-kit-lib/wrapper` | drop the `protect-projects.sh --cwd` call; drop `-g/--gid docker` parsing and the docker-group backend case; drop the `--allow` override warning; keep project-dir validation, `--tools` opt-in, sock probe, DOCKER_HOST/XDG export, `sudo -u opencode` exec; stop exporting `OPENCODE_LAUNCH_CWD` |
| `files/sudoers.template` | keep: base `(opencode)` RunAs for the binary, socket-check rule, `env_keep += "DOCKER_HOST XDG_RUNTIME_DIR"`; drop: `OPENCODE_LAUNCH_CWD` env_keep, both protect-projects rules, docker-group block, ddev-delegated block, ddev-sandbox block |
| `files/opencode.jsonc` | comments rewritten ("OS ACL remains the hard boundary" is now false); read/edit denies stay as SOFT rules; `*README.txt` goes back to `deny` (the old `ask` existed only because the hard ACL broke ddev's start-time read of `.ddev/commands/<svc>/README.txt` — a soft deny never touches the ddev process); add `*.git/config*": "ask"` and `*README.txt*": "ask"` bash tripwires; keep `docker *`/`ddev *` denies + SECURE_GIT markers |
| `files/install.sh` | backend prompt becomes docker-rootless (default) \| podman-rootless, **mandatory** — abort when provisioning fails (no docker-group fallback); ddev >= 1.25 becomes a **hard** requirement; absorb sandbox provisioning: `/home/opencode/.ddev`, router-port sysctl question, mkcert CA reuse (moved here from `config.sh ddev-mode sandbox`); drop Step 7 (initial protection run), git hooks setup, hooks deploy; drop `--container-backend docker-group`; **group switch (§2.2)**: drop the `www-data` groupadd/existence prompt, `usermod -aG opencode $DEFAULT_USER` instead, all `:$WWW_GROUP` chowns become `:opencode`, default ACLs `g:opencode:rwx` |
| `files/update.sh` | shrink `KIT_FILES`; drop hooks/protect-projects/transaction/shim deploy + `core.hooksPath` re-assert + ddev shim re-link; add the **one-time deny-removal + group migration** (§4); keep `--binary`/`--binary-path`; `--refresh` becomes the migration trigger alias (or is removed) |
| `files/config.sh` | drop `ddev-mode` subcommand + all sandbox provisioning code (moved to install); `container-backend` accepts only rootless values + `status`; `git-config on/off` stays (soft-only, message updated); `refresh` subcommand removed or re-purposed to re-apply the group baseline (now `g:opencode:rwx`) |
| `files/status.sh` | drop ACL-protection and ddev-mode sections; add: leftover `u:opencode` deny scan (warns "run update.sh"), rootless socket state, `/home/opencode/.ddev` presence, migration stamp state; group display switches to the `opencode` usergroup |
| `files/uninstall.sh` | drop hooksPath unset, shim/sudoers remnants already handled; keep `setfacl -R -b/-k` sweep (now the only ACL cleanup) + removal of migration artifacts (`ddev-rewrites.conf`, `/run/opencode-permissions-kit/`); **group note**: `gpasswd -d $DEFAULT_USER opencode` (best-effort) before `userdel -r` so the private group is cleaned up automatically |
| `files/opencode-permissions-kit-lib/jsonc-parser.py` | keep `--tools`; remove `--allow`/default deny-extraction modes (dead code). **Timing: Phase 6** — until then `test-project-config.sh` (default + `--allow`), `test-git-config.sh` (default mode) and the not-yet-rewritten wrapper (`--allow`) still consume them; trimming earlier would break the green-tests-per-phase rule. Phase 6 also rewrites `test-git-config.sh` to assert SECURE_GIT on/off via grep instead of the parser |

## 4. Migration of existing installs (update.sh)

`update.sh` runs a **one-time** migration, gated by a stamp
(`HARD_DENY_REMOVED=1` written to `install.conf`), so repeat updates are
no-ops:

1. **Remove hard denies** from every root in `projects.conf` — same parser
   trick `clear_stale_acls()` uses today:

   ```sh
   getfacl -R -p "$root" 2>/dev/null | awk '
       /^# file: / { path = substr($0, 9); has = 0; next }
       /^user:opencode:/ { has = 1; next }
       /^$/ { if (path != "" && has) print path; path = ""; has = 0 }
   ' | xargs -d '\n' setfacl -x u:opencode
   ```

2. **Unset `core.hooksPath`** for both `opencode` and `$DEFAULT_USER`
   (best-effort, `|| true`) — the hooks dir is about to disappear.
3. **Remove the ddev shim** only when `/usr/local/bin/ddev` is our symlink
   (`readlink` matches `$LIBDIR/bin/ddev`) — never touch a real ddev.
4. **Remove transaction artifacts**: `/etc/opencode-permissions-kit/ddev-rewrites.conf`,
   `/run/opencode-permissions-kit/ddev-txn/`, `$LIBDIR/hooks/`,
   `$LIBDIR/ddev-transaction.sh`, `$LIBDIR/bin/ddev`,
   `/usr/local/sbin/protect-projects.sh`.
5. **Backend migration**: existing `CONTAINER_BACKEND=docker-group` installs
   must be re-provisioned. update.sh cannot ask questions — so it **aborts
   with instructions** ("run `install.sh --container-backend docker-rootless|podman-rootless`")
   instead of silently downgrading security. Rootless installs pass through.
6. **Group migration (§2.2)**: `chgrp -R opencode` + re-apply default ACLs
   (`setfacl -R -d -m g:opencode:rwx`) on every project root and
   `/home/opencode` (config files: `chown opencode:opencode`); then
   `usermod -aG opencode $DEFAULT_USER`. Touches every inode — same class
   of recursive change install.sh already performs; the pre-migration
   `getfacl -R` backup already exists in install.sh and moves to §4.
   Membership change needs a fresh login/newgrp for the developer — print
   that hint.
7. **Provision ddev-as-opencode** (absorbed from sandbox mode, idempotent):
   `/home/opencode/.ddev`, mkcert CA reuse, router-port sysctl — sysctl is
   host-wide; update.sh applies it only when already present in
   `/etc/sysctl.d/99-ddev-rootless.conf`, otherwise prints the manual
   command (update.sh must stay prompt-free).
8. Re-render sudoers from the new template (existing render code, backend
   and ddev-mode conditionals deleted).
9. Write `HARD_DENY_REMOVED=1`; log every step to the audit log.

Ownership note: files created by the agent stay `opencode`-owned after the
sweep; group `opencode` + setgid + umask 002 keeps them developer-editable.
No chown sweep (ddev needs to chmod its own files as opencode anyway).

## 5. install.conf key changes

| Key | Before | After |
|---|---|---|
| `CONTAINER_BACKEND` | docker-group \| docker-rootless \| podman-rootless \| (none) | docker-rootless \| podman-rootless only |
| `DDEV_MODE` | delegated \| sandbox | **removed** |
| `WWW_GROUP` | www-data (or custom) | fixed `opencode` (the user's private group, §2.2) — later renamed to `OPENCODE_GROUP` (readers keep a `WWW_GROUP` fallback for pre-rename confs, `update.sh` renames the key away) |
| `OPENCODE_DOCKER_HOST` / `OPENCODE_PODMAN_SOCKET` | kept | kept |
| `HARD_DENY_REMOVED` | — | new migration stamp |
| `DDEV_BIN` | needed by the shim | **removed** (shim gone; ddev resolved via PATH inside the opencode session) |

All readers (`status.sh`, `config.sh`, `update.sh`, `uninstall.sh`) treat a
missing key with the new defaults; unknown legacy values are ignored, not
inherited.

## 6. Install-time questions (final list)

1. **Project folders** (`/var/www/vhosts` etc.) — unchanged.
2. **Allow git commands** — yes (default) / no (soft-only `.git/config`
   deny via SECURE_GIT) — unchanged, wording updated ("soft-only").
3. **Rootless container tool** — docker-rootless (default) / podman-rootless.
4. **Router ports** — lower `ip_unprivileged_port_start` to 80?
   (host-wide sysctl, moved here from `config.sh ddev-mode sandbox`).

The **user-group question is gone**: the sharing group is always the
`opencode` usergroup (§2.2) — no `www-data` prompt, no groupadd.

Conditional prompts that cannot go away: existing `opencode` user, existing
default-user opencode config, opencode binary found/install, filesystem
baseline (group+setgid+default ACLs — this is the group-collab half, it
stays). `DEFAULT_USER` stays auto-detected (`SUDO_USER`), never asked.

## 7. Tests / CI

- **Unit** (`sh tests/test-*.sh` per AGENTS.md — never rely on mode bits):
  delete `test-hooks.sh`, `test-ddev-shim.sh`, `test-ddev-sandbox.sh`,
  `test-project-config.sh`; extend `test-wrapper-validation.sh` (no `-g`,
  backend normalization rootless-only), `test-container-backend.sh`
  (rootless-only), `test-jsonc-parser.sh` (drop `--allow` cases).
- **New**: `test-migration.sh` — fixture tree with planted
  `u:opencode:---` entries + stamp logic: run migration, assert denies
  gone, group switched to `opencode` (default ACLs `g:opencode:rwx`), group
  bits intact, idempotent on second run, docker-group install
  aborts with instructions.
- **Makefile**: update the test list; `make check-version` unchanged.
- **CI**: update the `chmod +x` lists and test script lists in **both**
  `.github/workflows/test.yml` and `.github/workflows/e2e.yml` (AGENTS.md
  rule).
- **e2e** (`tests/e2e/run.sh`): drop hook/ACL/deny assertions and the ddev
  shim + delegated/sandbox sections; the "README.txt readable (ddev
  compat)" OS check and the stale-ACL heal check around it go too
  (soft-only world); keep/extend 12g log assertions minus
  the ACL event lines; new section: install old-shape kit fixture → run
  update.sh → assert `getfacl` shows no `u:opencode` deny and ddev start
  succeeds reading `settings.php`. Section 12i (rootless runtime teardown)
  stays. NOTE: e2e is only expected green again **after Phase 6** —
  intermediate phases change repo files that the e2e container installs,
  so the unit suite is the per-phase gate.

## 8. Documentation

- `docs/MANUAL.md`: remove ACL/hooks/ddev-mode/shim chapters; new "Security
  model (soft-only)" section with the trade-offs from §2.1; updated install
  question walkthrough; migration instructions.
- `README.md`: trim feature list to the four goals in §2.
- `docs/design/docker-rootless.md`: rationale section rewritten (UID
  separation, not ACL-holding).
- `docs/design/ddev-sandbox.md` + `docs/security/PROOF-1/2/3.md`: add a
  status banner "superseded by ddev-working.md (hard deny layer removed)";
  keep as historical records.
- `AGENTS.md`: ddev-shim section, self-block section, and audit-log wording
  ("documents the restrictions applied against it") all become obsolete —
  rewrite after implementation lands.
- Workspace `opencode.jsonc` (dev workspace root): the README.md allow
  override becomes unnecessary once denies are soft-only; keep until
  migration removes the hard denies here too.

## 9. Rollout order (each phase leaves `sh tests/test-*.sh` green)

1. **Phase 1 — template + tests** (DONE): rewrite `opencode.jsonc`
   comments/rules (README.txt → deny, new bash tripwires
   `*README.txt*` + `*.git/config*`, soft-only wording), adjust
   `test-jsonc-parser.sh`. Parser trim deferred to Phase 6 (green-tests
   constraint, see §3 parser row).
2. **Phase 2 — wrapper + sudoers.template** (DONE): soft-only wrapper, new
   sudoers shape; `test-wrapper-validation.sh` extended.
3. **Phase 3 — install.sh** (DONE): rootless-only flow, absorbed
   provisioning, new question list.
4. **Phase 4 — update.sh migration** (DONE, §4) + `test-migration.sh`.
5. **Phase 5 — config.sh / status.sh / uninstall.sh** (DONE) cleanup.
6. **Phase 6 — delete dead files**, Makefile + both CI workflows, e2e
   updates (DONE) — `make e2e` green (183 checks) run from this workspace.
7. **Phase 7 — docs + AGENTS.md** (DONE): MANUAL/README rewritten,
   superseded banners on DDEV-SANDBOX/PROOF-1/2/3, rationale updated on
   DOCKER-ROOTLESS, AGENTS.md rewritten.

VERSION bump: per AGENTS.md, only when the developer asks — the backend
abort in §4.5 effectively requires users to re-run install.sh, so the
version jump is the natural marker.

## 10. Open questions

- Keep the parser's `--allow` mode for a "this project overrides global
  rules" informational warning in the wrapper? (Cheap, no ACL coupling.)
  Current plan: drop it.
- `OPENCODE_PODMAN_SOCKET` (docker-CLI-over-podman compat): keep or let
  podman users call `podman` directly? Current plan: keep, unchanged.
- Should `config.sh refresh` re-apply the group baseline (chgrp/setgid/
  default ACLs) as its new meaning? Current plan: yes.
- e2e depth for the migration path (full old→new container dance vs.
  fixture-level only). Current plan: fixture-level in e2e, real
  old-install container only if cheap.

## 11. Addendum — ddev always runs as the opencode user

**Burn-in finding (2026-08):** the soft-only model still breaks `ddev start`
in a real two-owner project:

```
Failed to start pc-database-v2: chmod /var/www/vhosts/pc-database-v2/.ddev/.webimageBuild: operation not permitted
```

`.ddev/` is owned by the developer, but the agent's ddev runs as `opencode`;
Linux `chmod` requires ownership (or root), so the group-shared `.ddev`
metadata cannot be written. The wrapper's `sudo -u opencode` has no
passwordless root path. This was the collision inventory in
ddev-sandbox.md:56, now realized in the soft-only world.

**Decision: one owner for ddev, everywhere.** ddev runs as `opencode` in
EVERY context — the agent natively, and the developer's terminal through a
shell function + a sudoers helper:

- `files/opencode-permissions-kit-lib/bin/ddev-as-opencode` — sudoers
  target, deployed 755. Reads `install.conf` (legacy fallback chain),
  refuses any non-opencode caller (exit 1), resolves the REAL ddev
  (`command -v ddev` → `/usr/local/bin/ddev` → `/usr/bin/ddev`; exit 127
  with a hint when missing), re-sets `HOME`/`XDG_RUNTIME_DIR`/`DOCKER_HOST`
  (sudo env_reset drops them), `umask 002`, `exec`s the real ddev. Never
  references the removed shim.
- `files/opencode-permissions-kit-lib/ddev-as-opencode.sh` — sourced
  `ddev()` function, appended to the DEFAULT user's rc files (idempotent
  grep, `[ -f ]` guard like shell-warn.sh). Already opencode → `command
  ddev` (no recursion); otherwise `exec sudo -u opencode <helper> "$@"`.
  Never installed for the opencode user.
- sudoers: `DEFAULT_USER ALL=(opencode) NOPASSWD:
  /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode *`
  (fixed kit path — `DDEV_BIN` stays dead).
- **`.ddev/` + settings-dir handover** — every project's `.ddev` and the
  app-type's settings directories are handed over to `opencode:opencode`
  with `g+w`: install.sh Step 5, config.sh
  projects-add, migrate-denies.sh step 3, AND an unconditional block in
  update.sh (so already-migrated installs are healed — the migration path
  alone would miss them). Searched at any depth under each registered root
  via the shared helper `ddev-handover.sh`. Rationale: ddev chmods these
  directories **unconditionally** (e.g. `writeTypo3SettingsFile` does
  `util.Chmod(dir, 0755)` before writing), and chmod is owner-only — group
  write can never suffice, ownership is required. Covered types: typo3
  (`config/system`, `<docroot>/typo3conf`), drupal*/backdrop
  (`<docroot>/sites/default`), magento (`app/etc`); wordpress (root file)
  is documented as user-managed. `.git/` stays developer-owned (mode 700).

**Trade-off (accepted, documented in MANUAL.md):** `ddev auth ssh` /
composer private keys now live in `/home/opencode/.ddev` and are
agent-readable. No OS backstop — the price of "ddev must read settings.php"
extended to "ddev must run as one user".

**Tests:** `tests/test-ddev-as-opencode.sh` (functional guard + function
branches + wiring incl. CI chmod lists); e2e §4b (helper/hook/sudoers,
127-without-ddev), §4c (`.ddev` handover via `config.sh refresh`), §11e
(migration handover), §12 (projects-add handover).
