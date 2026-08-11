# Container Tools (docker / ddev) — Opt-In Design Notes

> Status: **Implemented (2026-08-11).** This document is the historical design
> record behind the container-tools feature. The decisions below are in the
> code; the authoritative usage documentation lives in `docs/MANUAL.md` under
> "Container Tools (docker/ddev)". The unchecked "Still open" items in §7 have
> not been revisited since implementation.

## 1. The Problem

opencode runs as a dedicated Linux user (`opencode`) that is only a member of
the `www-data` group. It has **no** access to the Docker socket, so `docker`
and `ddev` commands fail with:

```
permission denied while trying to connect to the Docker daemon socket
```

Some developers, however, need opencode to run `docker` / `ddev` inside a
project (e.g. to execute `ddev start`, `ddev composer`, `ddev npm` while
working in the TUI). Today that is only possible in a second terminal, run by
the developer themselves.

Goal: let a project **opt in** to docker/ddev, ideally driven by the project's
own `opencode.jsonc`, while keeping the default ("no container access")
unchanged.

## 2. Two Independent Layers

Any access decision has two layers, and confusing them causes bugs:

| Layer | What it controls | Where it lives | Already per-project? |
|---|---|---|---|
| **Policy (soft)** | May the *agent* invoke the command at all? | `permission.bash` in `opencode.jsonc` (global + project) | Yes — project config overrides global |
| **Capability (hard)** | Does the OS let the `opencode` user actually run it? | group membership, sudoers, socket ACLs | **No** — the docker socket is system-wide |

**Decision (2026-08-11):** the global template will default docker/ddev to
**`deny`**. Currently it contains `"bash": { "*": "allow", ... }`, so a command
like `docker ps` only matches the catch-all and is policy-allowed. After the
change, projects must explicitly opt in with an allow rule in their own
`opencode.jsonc` — the hard layer (no docker group) stays the second gate.

Note: because the global deny and the project allow use the **same pattern key**
(`"docker *"`), the deep-merge replaces the value instead of ordering two
different keys — this specific case is robust against the cross-file ordering
problem (§3.2). Only *differently-shaped* patterns (e.g. global `"docker *"`,
project `"docker*"`) hit the fragile ordering.

## 3. How opencode Evaluates Permission Rules

### 3.1 Within one file (deterministic)

- opencode parses `permission.bash` as an **ordered** map
  (`propertyOrder: "original"` — key order is preserved).
- A command is matched against **every** rule; the **last matching rule wins**
  (`findLast`).
- Hence the kit's convention: broad rules first (`"*": "allow"`), specific
  rules later.

Example for `docker ps` with the current global template:
`"*": "allow"` matches → action `allow`. The `ddev ...` rules only match
specific subcommands (`DROP DATABASE`, `delete`, `import-db`, ...), not a
plain `ddev start`.

### 3.2 Across config sources (fragile — the "merge" trap)

- Config files are **deep-merged, not replaced**. Project rules override
  global rules only for *identical keys*; all other global rules survive.
- `permission.bash` is an object, so the rules of both files end up in one
  merged object.
- **The relative order of merged rules across sources is not guaranteed.**
  opencode has known issues around exactly this (#16157, #14070): a project
  rule can end up *before* a global catch-all, which then wins. opencode v2
  fixes this with a layered-array `permission: [...]` syntax (PR #23214), but
  that is not what the kit currently ships.

**Consequence for the kit:** "Is docker *effectively* allowed in project X?"
cannot be answered robustly by replaying the full merge — the answer would be
version-dependent and would reproduce opencode bugs.

## 4. Proposed Design (Option B — session-scoped opt-in)

### 4.1 Trigger: evaluate the project config only

The wrapper reads **only the project's own** `opencode.jsonc` and answers:
"Does `permission.bash` broadly allow docker / ddev?"

- Project config is the override source — opencode *intends* it to win.
- Within a single file the rule order is deterministic, so `last-match-wins`
  can be replayed accurately.
- Shorthands are honored: `"permission.bash": "allow"` (string) and
  `"permission": "allow"` (top-level string) count as allowing everything.

Detection (new parser mode, e.g. `jsonc-parser.py --tools <project-config>`):

1. Load the project config's `permission.bash` rules in file order.
2. Test representative commands — `docker ps` and `ddev start`.
3. Glob-match each rule; keep the last match; its action is the decision.
4. Print `docker`, `ddev`, or nothing.

**Decision (2026-08-11):** only **broad** patterns count — `"docker *"` /
`"ddev *"` (and the bare `docker` / `ddev` without wildcard) with action
`allow`. Subcommand allows like `"ddev composer *"` do **not** trigger the
grant. Smaller attack surface, clearer to document.

### 4.3 ddev mechanics

**Decision (2026-08-11):** ddev runs **directly as the `opencode` user** with
its own `~/.ddev` (`/home/opencode/.ddev`), backed by the session docker grant
(§4.2). No sudoers delegation.

What `~/.ddev` is (for the record): ddev's *per-user home config directory*,
created on first run. Contains `global_config.yaml`, SSH keys cached by
`ddev auth ssh`, mutagen state, project registry. It is **not** a project
copy and not a ddev installation.

Implications:

- `ddev start/stop/restart/composer` over HTTP work out of the box.
- Anything needing private SSH keys (composer from private git repos,
  `ddev auth ssh`) **fails** unless keys are explicitly copied into
  `/home/opencode/.ddev/.ssh` — a deliberate security decision, documented in
  MANUAL.md.

### 4.2 Grant: per-session, not per-command

When the wrapper sees `docker` allowed:

```sh
exec /usr/bin/sudo -u opencode -g docker /usr/local/lib/opencode/bin/opencode "$@"
```

- `sudo -g docker` runs the process with the `docker` group as an
  **additional group for this process tree only**.
- The `opencode` user is **never** a member of `docker` in `/etc/group`; no
  permanent change to the account.
- The sudoers rule becomes `DEFAULT_USER ALL=(opencode:docker) NOPASSWD: ...`.
- `ddev` rides on the same docker access and runs directly as the `opencode`
  user with its own `~/.ddev` (first run creates it).
- The wrapper prints a clear notice at launch when container tools are granted
  for the project.

Edge cases to handle in the wrapper:

- `docker` group does not exist (no Docker installed) → fall back to no `-g`,
  print a warning.
- No docker group but the socket is reachable some other way → best-effort.

### 4.3 Scope semantics — be honest

- Scope is **per session** (the launch directory), **not per command**. Within
  one session the agent can run docker from any cwd, including directories
  outside the launch project. The wrapper already restricts *launching*
  opencode to registered project roots, but a running agent can `cd`
  anywhere.
- `agent.<name>.permission` overrides are **ignored** by the detector (it only
  reads top-level `permission.bash`). A developer who allows docker only for a
  specific agent gets no OS grant.

## 5. Security Analysis

### 5.1 The error direction is safe

The detector may be imprecise without creating a hole:

| Situation | Result |
|---|---|
| Capability granted, policy denies | opencode still blocks the command. No harm. |
| Capability missing, policy allows | `permission denied` — annoying, safe. |

So the detector should err on **granting more than strictly provable**, never
on being precise at the cost of missing a legitimately allowed project.

### 5.2 Inherent risks of container access

- **docker group ≈ root on the host.** Granting docker access (even
  session-scoped) is a deliberate act of trust. Anyone who can reach the
  docker socket can escalate to root.
- **`ddev exec` ignores host ACLs.** Container root reads files via
  bind-mounts regardless of `u:opencode:---` ACLs. `ddev exec cat .env` shows
  the file. Whoever enables `ddev`/`docker` accepts this gap.
- **Session leak.** The grant follows the process tree, so one enabled project
  "leaks" docker into the rest of the session.

## 6. Implementation Footprint

| File | Change |
|---|---|
| `files/opencode-lib/jsonc-parser.py` | new `--tools` mode (bash-rule evaluation) |
| `files/opencode-lib/wrapper` | detect tools, conditionally add `-g docker`, print notice |
| `files/sudoers.template` | extend RunAs to `(opencode:docker)` |
| `files/status.sh` | show which projects have container tools enabled |
| `files/opencode.jsonc` | docker/ddev (incl. `sudo` forms) denied in the global bash template |
| `docs/MANUAL.md` | usage documentation |
| `tests/` | parser + wrapper tests; e2e section |

No new files, no changes to `protect-projects.sh`, no docker group membership
for the `opencode` user.

## 7. Open Questions

**Decided (2026-08-11):**
- [x] Default policy: global template gets `"docker *": "deny"` / `"ddev *": "deny"`.
- [x] Broad-allow definition: only `docker *` / `ddev *` (incl. bare `docker` /
      `ddev`) with action `allow` trigger the grant; subcommand allows do not.
      `docker-compose *` (legacy hyphen binary) counts as docker; `docker
      compose *` and `sudo docker *` do **not** trigger.
- [x] ddev mechanics: ddev runs directly as the `opencode` user with its own
      `~/.ddev` (no sudoers delegation, no `~/.ddev` SSH keys by default).
- [x] Launch notice: the wrapper requires an **interactive confirm** at launch
      before granting container tools for the project (not just a warning).

**Still open / to verify at implement time:**
- [ ] Does Docker Desktop on WSL2 reliably create the `docker` group in the
      target distro? Verify `/var/run/docker.sock` ownership.
- [ ] `ddev ssh` — not granted (interactive shell, too powerful).
- [ ] No new files, so `update.sh` fetch list and CI `chmod +x` lists stay
      unchanged.
