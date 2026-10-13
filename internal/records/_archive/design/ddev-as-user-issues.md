# IDEA-DDEV-AS-USER: run ddev as the developer again — security inventory

> Status: **PLANNING RECORD (brainstorming, 2026-08).** No code change. This
> document answers two questions: which security disadvantages arise if ddev
> runs as the developer user again (agent-delegated or developer-only), and
> whether the known `.ddev/commands/host/` gap is the only one — and whether
> it can be closed. Verdict in §6: **not viable**; the host-command gap is one
> instance of a structural class that cannot be sealed without re-introducing
> the hard-deny model the kit deliberately removed. Where wording differs from
> the code, the code wins.

## 1. Motivation (why the idea keeps coming back)

ddev-as-opencode (ddev-working.md §11) has real operational cost, all of it
caused by "ddev must run as one user, and that user is not the one who owns
the files ddev touches":

- the `.ddev/` + settings-dir **handover machinery** (chmod is owner-only),
  incl. the bootstrap-root handover/handback dance for fresh TYPO3 clones,
- the **browser-command split** (issue #20: `launch`/`mailpit`/… need Windows
  interop the opencode user must not have),
- the **hosts-file bridge** (`ddev-hosts-add`, because the opencode user
  cannot run `ddev-hostname.exe`; its scans need vendor/node_modules
  exclusions, issue #21),
- the `ddev()` shell function + `export -f` / `BASH_ENV` transports for vendor
  scripts (issue #18: `vendor/bin/runTests.sh` fell through to the real ddev
  as the developer → chmod EPERM on the opencode-owned `.ddev/`) — dash
  scripts, cronjobs and IDE tasks still fall through,
- mode-repair friction on settings files (issue #25: ddev resets
  `config/system` to `0755` on every start, stripping `g+w` from
  `additional.php` until the next `refresh`),
- the **SSH-key trade-off** (`/home/opencode/.ddev` is agent-readable),
- slow first start (mutagen + image pulls into the rootless daemon) and the
  install-time **database migration** from the developer's old daemon
  (issue #15: the export/import dance around the handover).

Running ddev as the developer again would delete most of that machinery —
stock ddev is designed to run as the developer on the developer's machine.
The question is only what it costs.

### 1.1 The documented evidence: closed `ddev`-labeled GitHub issues

The kit's issue tracker is the burn-in log of this model. All six closed
`ddev` issues
([#15](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/15),
[#17](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/17),
[#18](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/18),
[#20](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/20),
[#21](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/21),
[#25](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/25))
map to pain classes, and the mapping matters for the assessment — because
**not every ddev issue is a ddev-*user* issue**:

| Issue | Symptom | Pain class | Would ddev-as-developer fix it? |
|---|---|---|---|
| #25 | `ddev start` strips `g+w` from `config/system/additional.php` (chmod `0755` on the settings dir) | handover/chmod (two owners) | yes — one owner, chmod is a no-op for the developer. **Already fixed inside the model** by dev-owned projects (`disable_settings_management`) + `refresh` re-applying `g+w` |
| #21 | `ddev-hosts-add` reported hostnames from `.ddev` dirs inside `vendor/` | hosts bridge scan bug | moot — with ddev as the developer the whole hosts bridge would not exist (stock `ddev-hostname.exe` interop works). Kit bug itself is fixed (vendor/node_modules skip) |
| #20 | `ddev launch` failed: WSL interop/wslview denied for the ddev user | browser/interop split | yes — the developer has interop; the split machinery would not exist |
| #18 | `vendor/bin/runTests.sh` (dash) called the real ddev as the developer → chmod EPERM on opencode-owned `.ddev/.webimageBuild` | function-transport gap (two owners, two ddevs) | yes — no function/transports needed, ddev is ddev. Fixed via `export -f`/`BASH_ENV`; residual gaps (cronjobs, IDE tasks, `#!/bin/sh` without bash parent) documented |
| #17 | agent's `git log`: "dubious ownership" on developer-owned `.git` | **UID separation itself**, not ddev | **no** — `.git` stays developer-owned and the agent stays a different UID regardless of who runs ddev; only `safe.directory` handling (kit `git-config`) addresses it |
| #15 | after install, all project databases unreachable on the old daemon | daemon/user migration | yes — containers would stay on the developer's daemon; no export/import. Fixed by the install-time export + `ddev-migrate.sh` import |

Reading of the table: four of six issues (#25, #20, #18, #15 — plus #21's
whole feature category) are *structural* consequences of "ddev runs as
opencode" and would vanish with ddev-as-developer; one (#17) is a
consequence of UID separation that no ddev-user switch can touch. The
operational case for the switch is therefore real and documented — which is
exactly why §4–§6 weigh it against the security cost instead of dismissing
it. Note also what #18 demonstrates about the current model's failure mode:
when the developer's native ddev meets opencode-owned trees, it fails with
hard EPERM — annoying, but fail-closed. The reverse combination (agent-side
ddev on developer-owned trees) is the one that motivated the handover
machinery in the first place.

## 2. What the change would mean concretely

Two variants are usually meant:

- **A — delegation (the old `delegated` mode):** the agent's `ddev` calls are
  re-executed as the developer via a RunAs-developer sudoers rule; the
  developer's terminal runs ddev natively. `.ddev/` becomes developer-owned
  again; the developer's daemon/context serves the containers.
- **B — developer-only:** the agent loses ddev access entirely; only the
  developer runs ddev, natively as themselves.

Both variants put ddev's *executing* user back to the developer. The
inventory below applies to both; §4.1 explains why even B does not close the
class.

## 3. The known gap: custom host commands (H3)

The scenario from the brainstorming, verified against the ddev source:

1. The agent writes `.ddev/commands/host/evil-cmd` — a tree it can write
   (group sharing, setgid, umask 002).
2. `ddev evil-cmd` — **no `ddev restart` needed**: command discovery happens
   on every invocation, and ddev even `chmod 0755`s the file for the agent
   (`cmd/ddev/cmd/commands.go`, `addCustomCommandsFromDir`).
3. ddev executes the script **directly on the host, as the invoking user**
   (`makeHostCmd` → `exec.RunInteractiveCommand(fullPath, …)`). No container
   is involved (`cmd/ddev/cmd/commands.go:447-488`).

With variant A that is arbitrary code execution **as the developer**, outside
every soft rule — this is exactly finding H3 from `docs/security/proof-3.md`
and §1 of `docs/design/ddev-sandbox.md`, the reason sandbox mode (and later
the as-opencode model) exists.

## 4. Is it the only gap? No.

The host-command gap is merely the most visible carrier of one structural
problem: **ddev executes agent-authored configuration and scripts with the
authority of the invoking user.** Move that user to the developer and every
carrier becomes a developer-privilege channel.

### 4.1 The four carriers (same class as H3)

All verified in the ddev source; all read from files the agent can write:

| # | Carrier | Mechanism (ddev source) | Trigger |
|---|---|---|---|
| 1 | Custom host commands | `.ddev/commands/host/*` executed on the host (`commands.go:447-488`) | `ddev <name>` — by the agent (A) **or the developer** |
| 2 | `exec-host` hooks | `.ddev/config.yaml` `hooks:` accept `exec-host: <shell>` tasks run on the host (`pkg/ddevapp/task.go:34-115`; valid tasks `exec`/`exec-host`/`composer`, `config.go:1881-1885`); lifecycle events include pre/post-`start`/`stop`/`restart`/`exec`/`pull`/`push`/… | **automatic** on the next `ddev start`/`restart`/… — by anyone |
| 3 | Add-on actions | `ddev get <owner/repo \| URL \| local path>` executes `pre_install_actions` / `post_install_actions` / `removal_actions` shell actions (`pkg/ddevapp/addons.go:79-91, 1330-1344`) | `ddev get` / add-on remove — argv, or **from inside a planted hook (2)** |
| 4 | Compose overrides / bind mounts | `.ddev/docker-compose.*.yaml` (and `config.yaml` mounts) are agent-writable; `ddev start` mounts anything the daemon user can read into containers | `ddev start` — by anyone |

Carrier 2 is the crucial one for the "can we close it" question, for two
reasons:

- **No invocation needed at fire time.** A planted `exec-host` hook fires on
  the *developer's own* next `ddev start` — there is no agent session, no
  sudo, no ddev call by the agent involved when it goes off. Variant B (§2)
  therefore does **not** close the class: the agent only needs write access
  to `.ddev/` — which the group-collaboration baseline grants by design —
  and patience. The payload runs as the developer either way.
- **It defeats argv allowlists.** Even a delegation helper that only permits
  `ddev start/stop/restart/…` (the H3 "mitigation" sketched in proof-3)
  executes the planted hook, the custom command discovery chmod, and the
  compose overrides. The payload lives in files, not in argv.

### 4.2 Consequences beyond the carrier class (variant A)

- **Developer-UID containers.** The containers serve from the developer's
  daemon. On the developer's rootless daemon every container (and its
  "root") maps to the developer's host UID: combined with carrier 4, the
  whole developer-readable namespace (`~/.ssh`, `.gitconfig`, `.aws`,
  browser profiles — `/home/<developer>` is `750`, but the container *is*
  the developer's UID) becomes readable from `ddev exec` / `ddev ssh`.
- **Root-equivalent socket.** If the developer runs rootful docker (docker
  group — the stock setup), agent-driven ddev reaches a root-equivalent
  socket: mount `/` into a container → full host compromise. The kit cannot
  force the developer's *own* environment to be rootless.
- **Windows interop as the Windows user.** Host commands and `exec-host`
  hooks run as the developer and can invoke `powershell.exe` /
  `explorer.exe` / any `.exe` via WSL interop — execution on the Windows
  side, outside every Linux rule. This is exactly the capability the
  browser-command split (issue #20) exists to keep from the agent.
- **`ddev auth ssh` with the real keys.** Delegation gives the agent a path
  to import the developer's *actual* SSH keys into the ssh-agent container
  (the template's `ddev auth ssh*` deny is soft and re-allowable per
  project).
- **A RunAs-developer sudoers rule returns.** The delegation helper *is* an
  `opencode ALL=(developer)` rule — the class of rule the current
  security-model.md lists as a hard guarantee ("no code path executes as
  the developer").

### 4.3 Which guarantees survive? None of the three.

| Guarantee (security-model.md) | ddev as developer |
|---|---|
| Agent ≠ developer | void — every ddev run (A), or the developer's own run over agent-planted files (A+B), executes with developer authority |
| Containers ≠ root | void — developer's daemon; root-equivalent if rootful docker |
| No developer-RunAs | void in A (the delegation rule) |

## 5. Could the gaps be closed while ddev runs as the developer?

| Vector | Closing attempt | Why it fails |
|---|---|---|
| Host commands (4.1.1) | make `.ddev/commands/host` developer-owned, agent read-only; argv allowlist in a delegation helper | agent can plant fresh `.ddev` trees in any writable root (new projects); carrier 2 makes even `ddev start` sufficient; allowlists cannot see file payloads |
| `exec-host` hooks (4.1.2) | deny agent writes to `.ddev/config.yaml` | re-introduces hard OS denies over `.ddev/` — the ACL model ddev-working.md removed after it broke ddev and the agent workflow; still scan-based/racy (the PROOF-1/2 gaps); compose overrides are separate files anyway |
| Add-ons (4.1.3) | deny `ddev get` in the allowlist | a planted hook (4.1.2) can run `ddev get` itself; remote payloads (URL/GitHub) bypass local file checks |
| Bind mounts (4.1.4) | seal `.ddev/*.yaml` | same as 4.1.2; sealing ddev's whole extension surface means the agent can no longer do its job (configuring projects *is* agent work) |
| Developer-UID / rootful daemon (4.2) | enforce rootless for the developer | not the kit's environment to control |
| Windows interop (4.2) | — | the developer's normal capability; only reachable because execution happens as the developer |

**Hybrid idea, considered and rejected:** ddev as the developer *against the
opencode-owned rootless daemon* (keeps containers opencode-UID, fixes the
chmod pain). It leaves every host-side carrier (4.1) and the interop path
open and adds cross-user socket plumbing (XDG runtime dir is `0700`).
Security theater: the biggest class stays wide open while the model gets
more complex.

**The only theoretical full closure** is an OS-level hard deny on agent
writes to every `.ddev/`, settings dir, and config/compose file *everywhere
the agent can write*, enforced continuously. That is the pre-ddev-working
model — removed because it broke `ddev start` (chmod is owner-only), needed
per-collision carve-outs, and its own proofs showed the scan model leaks.
Re-introducing it contradicts the kit's soft-only decision
(docs/design/ddev-working.md, docs/concepts/security-model.md) and would not
even restore the guarantees: it would just move the breakage back.

## 6. Assessment

**Recommendation: no — do not run ddev as the developer, in neither variant.**

- The `evil-cmd` scenario is **not** the only gap. It is one of four file
  carriers of the same class ("agent-authored ddev input executed with the
  invoking user's authority"), and the class additionally drags in
  developer-UID containers, a possibly root-equivalent socket, Windows
  interop, and real-key exfil.
- The class **cannot be closed** while ddev executes as the developer: the
  decisive vector (`exec-host` hooks) fires on the developer's own runs,
  defeats argv allowlisting, and sealing it means re-introducing the hard
  ACL layer the kit just removed — knowing it broke ddev then.
- The pain that motivates the idea is real, and **documented** — §1.1 shows
  four of the six closed `ddev` issues would vanish structurally. But the
  same table shows the switch is not even a complete pain relief: #17 (git
  dubious ownership) is UID-separation pain that no ddev-user change
  touches. The pain is *operational*, not structural. The existing answer
  inside the as-opencode model is the
  **dev-owned projects mode** (`disable_settings_management`,
  docs/design/ddev-dev-owned-projects.md): it removes the handover cause —
  ddev stops writing/chmodding outside `.ddev/` — without moving the trust
  boundary. Remaining friction (browser split, hosts bridge, BASH_ENV
  transports) is cosmetic-to-moderate tooling cost, not a security
  regression.

If the operational pain grows further, the direction to explore is reducing
the handover surface and the context gaps (§1) within the one-user model —
not moving ddev's executing user back to the developer.
