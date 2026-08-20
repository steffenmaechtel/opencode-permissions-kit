# Security model

This page explains what the kit guarantees, what it deliberately does not,
and which residual gaps remain.

## The three hard guarantees

The kit's hard guarantees are UID-level — file permissions are opencode's
own **soft** layer (see below):

| Guarantee | Mechanism |
|---|---|
| Agent ≠ developer | wrapper execs `sudo -u opencode`; the developer's home is `750` and not group-shared |
| Containers ≠ root | rootless backend owned by `opencode` (per-user socket / daemonless podman) |
| No developer-RunAs | the sudoers carry only `(opencode)` rules for the kit binary, the socket probe, and the ddev-as-opencode helper |

Concretely:

- the agent's processes run as `opencode`, never as the developer — no
  credentials, SSH keys, or dotfiles in `/home/<developer>` are reachable,
- containers run under the `opencode` host UID via a rootless backend — the
  agent can never reach a root-equivalent docker socket,
- no code path executes as the developer (no RunAs-developer sudoers rule).

## The soft permission layer (trade-off, deliberate)

File denies (`.env`, keys, `settings.php`, …) live in `opencode.jsonc` and
gate **opencode's own read/edit tools** plus lexical bash tripwires. They
are the "ddev must work" decision:

> Processes spawned outside opencode's tools (ddev, its containers, `cat` in
> bash) can read every project file — including `settings.php`, which ddev's
> web container needs to boot.

The design record is `docs/design/ddev-working.md`.

| Guarantee | Mechanism |
|---|---|
| File denies (`.env`, keys, …) | `opencode.jsonc` soft rules — enforced by opencode's tools, prompted via bash tripwires |
| Developer ↔ agent file sharing | the `opencode` usergroup: setgid + default group ACLs + umask 002 |
| ddev runs as one user | the `ddev()` terminal function + the sudoers helper exec the real ddev as `opencode` (sole exception: `ddev launch` computes the URL as `opencode` and only the browser open runs as the developer — it needs the Windows interop the agent must not have, see [ddev integration](ddev-integration.md#exception-ddev-launch-issue-20)) |

## Known residual gaps

Documented rather than hidden:

- **Bash-spawned reads** (`cat .env`) are only caught by the template's
  lexical ask-tripwires, never by the OS.
- **Bind-mounted containers** read the mounted tree freely (they run as the
  opencode host UID).
- **Renamed copies** of secrets are invisible to the name-based
  [leak scan](../how-to/customize-deny-list.md).
- The kit protects **locations, not information flows** — once content
  leaves the project roots, no scan recaptures it.
- **Supply chain (trust assumption):** the one-liner streams `install.sh`
  from `master` over HTTPS, and `update.sh --binary` downloads the opencode
  release tarball without a checksum or signature — the "verification" is a
  liveness check (`opencode --version` runs). Installing means trusting
  GitHub, the opencode releases, and (for docker-rootless provisioning)
  get.docker.com at install time.

## WSL2: the /mnt/c exposure

`C:` is mounted through 9p/drvfs with the Windows session token — NTFS ACLs
do not distinguish WSL users, so with the default world-readable mount
**every WSL user (including the agent's) can read the whole Windows profile**
(`.ssh/`, `NTUSER.DAT`, browser data). The kit's UID separation only covers
the Linux side.

The kit surfaces this everywhere: `install.sh` warns and offers to restrict
the mount to your user (recommended; applies after `wsl --shutdown` from
Windows), `update.sh` prints a warning, `status.sh` reports the exposure,
and the **wrapper warns on every `opencode` start** until the restriction is
applied.

Manual fix via `/etc/wsl.conf`:

```ini
[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
```

> **After editing, restart WSL completely:** run `wsl --shutdown` from
> Windows, then reopen your WSL terminal — the mount options only take
> effect on a fresh WSL start.

`1000` is the default UID/GID of the first WSL user. Only if you deviate
from that default (created additional users, changed the default user)
adjust `uid`/`gid` to your default WSL user's values — the goal is always
the same: the agent user must end up as "other", with no bits.

Not sure what your values are? Check them with `id -u` / `id -g` in a fresh
WSL terminal (logged in as the default user).
