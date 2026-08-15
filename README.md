# opencode permissions kit

> ⚠️ **ALPHA — not for production use.** This kit is still in active development and has not been audited. The scripts and sudoers configuration may change in breaking ways between releases. Run it on a throwaway WSL2/dev box, not on a production server.

Runs [opencode](https://opencode.ai) as its own Linux user against a **rootless container backend**, so the agent is UID-separated and ddev keeps working. File permissions are opencode's own **soft** permission layer (`opencode.jsonc`).

**One step:**

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

After that, `opencode` runs as the dedicated `opencode` user. No npm package, no plugin, no extra install steps.

## How It Works

- **Dedicated user** — the wrapper at `/usr/local/bin/opencode` validates the project directory, then execs opencode as `opencode` (never as you)
- **Rootless containers only** — docker-rootless or podman-rootless, owned by the `opencode` user; no root-equivalent docker socket is ever granted (mandatory: provisioning failure aborts the install)
- **ddev as the sandbox user** — `/home/opencode/.ddev`, router ports, and a reused mkcert CA are provisioned; no delegation shim, no transactions
- **Soft file permissions** — deny rules in `opencode.jsonc` (`.env*`, `settings.php`, keys, ...) gate opencode's tools and trip bash commands with an `ask`; they are not OS-level ACLs (that is the "ddev must read settings.php" trade-off, see [docs/MANUAL.md](docs/MANUAL.md#security-model-soft-only))
- **Sharing group** — the `opencode` usergroup + setgid + default ACLs + umask 002, so you and the agent can edit the same files
- **No plugin** — the kit is system-level only: one install script, management scripts in `/usr/local/lib/opencode-permissions-kit/`

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
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh       # change settings (projects, .git/config, backend)
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh         # remove everything (no sudo prefix)
```

`status.sh` also works before the kit is installed, so you can check whether hardening is active from any machine.

Every kit script writes an audit trail to `/var/log/opencode-permissions-kit/opencode-permissions-kit.log` (self-rotating, readable by the default user — the `opencode` user cannot read it).

## Updating

Fetch `update.sh` from `master` and pipe it through sudo — it deploys the matching branch files and leaves `projects.conf` and `opencode.jsonc` untouched:

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

Removes the `opencode` user (and its usergroup), the kit library, ACLs, and sudoers rules. Project files are untouched. Shell RC hook lines (`~/.bashrc` / `~/.zshrc` / `~/.profile`, tagged `# opencode permissions kit`) and the default-user `~/.config/opencode/opencode.jsonc` are left in place — harmless after uninstall; the script prints a notice with manual cleanup steps. See [docs/MANUAL.md](docs/MANUAL.md#uninstalling) for details.

## Documentation

See [docs/MANUAL.md](docs/MANUAL.md) for:
- The security model (soft-only) and its trade-offs
- Container backends and ddev as the sandbox user
- Managing project directories
- Customizing the deny list (global + per-project)
- `.git/config` hardening
- Migration from a hard-ACL install
- Wrapper behavior

## Requirements

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- `sudo` access
- `curl`
- ddev ≥ 1.25 (when ddev is installed)

## License

MIT
