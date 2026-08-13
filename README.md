# opencode permissions kit

> ⚠️ **ALPHA — not for production use.** This kit is still in active development and has not been audited. The ACL rules, wrapper, and sudoers configuration may change in breaking ways between releases. Run it on a throwaway WSL2/dev box, not on a production server.

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One step:**

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

After that, `opencode` runs as a dedicated user with hard filesystem denies. No npm package, no plugin, no extra install steps.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit, including the project-level `opencode.jsonc` of the current worktree (not just the global denies)
- **Project-specific configs** — add or override deny rules per project
- **No plugin** — the kit is system-level only: one install script, four management scripts in `/usr/local/lib/opencode-permissions-kit/`

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## The Three Runtime Modes

The kit runs opencode in one of three modes, depending on (a) whether the
project's `opencode.jsonc` enables docker/ddev and (b) the configured container
backend (`CONTAINER_BACKEND` in `install.conf`). The mode decides what the
`opencode` user can reach — and whether the kit's hard ACL denies hold.

| | **Mode 1 — no containers** | **Mode 2 — rootless** | **Mode 3 — classic docker** |
|---|---|---|---|
| Enabled by | project config allows no docker/ddev | project allows docker/ddev + backend `docker-rootless` / `podman-rootless` | project allows docker/ddev + backend `docker-group` |
| opencode runs as | own user `opencode`, no docker group | own user `opencode`, `DOCKER_HOST` → `opencode`'s rootless socket | own user `opencode` **with** the docker group (`sudo -u opencode -g docker`) |
| Deny-listed files (`.env`, `settings.php`, `README.md`, keys, …) | **hard-denied** (`u:opencode:---`) | **hard-denied — including inside bind-mounted containers** (containers run as the `opencode` host UID) | **bypassable**: container root reads everything, the ACLs do not apply |
| ddev | not available | delegated to the developer via the shim → **soft protection only** | delegated to the developer via the shim |
| Root-equivalence | none | **none** (confined to the `opencode` UID) | **yes** — the docker socket is root on the host |
| Security posture | full | strong | as unsafe as running without the kit |

Example configs for the modes — global (deny default) and the project override
that opts in — are in [docs/MANUAL.md](docs/MANUAL.md#the-three-runtime-modes).

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

The script fetches its sibling files from the same `master` branch, so the one-liner is always a complete, self-consistent install. It asks interactively; add `--yes` and `--projects /var/www/vhosts` to skip prompts.

After the install completes, restart opencode:

```bash
opencode
```

## Managing the Kit

All management happens in a regular terminal (they need `sudo` anyway — no opencode commands required):

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh       # show protection status
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh       # change settings (projects, .git/config, ACL refresh)
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh         # remove everything (no sudo prefix)
```

`status.sh` also works before the kit is installed, so you can check whether hardening is active from any machine.

Every kit script writes an audit trail to `/var/log/opencode-permissions-kit/opencode-permissions-kit.log` (self-rotating, readable by the default user — the `opencode` user cannot read it).

## Updating

Fetch `update.sh` from `master` and pipe it through sudo — it deploys the matching branch files and leaves `projects.conf`, `install.conf`, and `opencode.jsonc` untouched:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

`opencode upgrade` and opencode's auto-updater cannot work behind the wrapper (the binary is root-owned, opencode runs as an unprivileged user), so the bundled config sets `autoupdate: false` and `update.sh` is the upgrade entry point:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary                  # upgrade opencode to the latest release
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary-path ./opencode  # install a specific binary
```

Binary upgrades are best-effort: a failure leaves the current binary in place, the previous one is kept in `/tmp/opencode-upgrade-backup-*`.

## Uninstall

```bash
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh
```

Removes the `opencode` user, the kit library, ACLs, hooks, and sudoers rules. Project files are untouched. Shell RC hook lines (`~/.bashrc` / `~/.zshrc` / `~/.profile`, tagged `# opencode permissions kit`) and the default-user `~/.config/opencode/opencode.jsonc` are left in place — harmless after uninstall; the script prints a notice with manual cleanup steps. See [docs/MANUAL.md](docs/MANUAL.md#uninstalling) for details.

## Documentation

See [docs/MANUAL.md](docs/MANUAL.md) for:
- The three runtime modes (no containers / rootless / classic docker)
- Managing project directories
- Customizing the deny list (global + per-project)
- Project-level allow/deny overrides
- `.git/config` hardening
- Wrapper behavior

## Requirements

- WSL2 (or any Linux with ACL support)
- `sudo` access
- `curl`

## License

MIT
