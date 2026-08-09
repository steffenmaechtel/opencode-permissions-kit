# opencode permissions kit

> ⚠️ **ALPHA — not for production use.** This kit is still in active development and has not been audited. The ACL rules, wrapper, and sudoers configuration may change in breaking ways between releases. Run it on a throwaway WSL2/dev box, not on a production server.

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One step:**

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/main/files/install.sh | sudo bash
```

After that, `opencode` runs as a dedicated user with hard filesystem denies. No npm package, no plugin, no extra install steps.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit, including the project-level `opencode.jsonc` of the current worktree (not just the global denies)
- **Project-specific configs** — add or override deny rules per project
- **No plugin** — the kit is system-level only: one install script, four management scripts in `/usr/local/lib/opencode/`

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/main/files/install.sh | sudo bash
```

The script fetches its sibling files from the same `main` branch, so the one-liner is always a complete, self-consistent install. It asks interactively; add `--yes` and `--projects /var/www/vhosts` to skip prompts.

After the install completes, restart opencode:

```bash
opencode
```

## Managing the Kit

All management happens in a regular terminal (they need `sudo` anyway — no opencode commands required):

```bash
sudo bash /usr/local/lib/opencode/status.sh       # show protection status
sudo bash /usr/local/lib/opencode/config.sh       # change settings (projects, .git/config, ACL refresh)
sudo bash /usr/local/lib/opencode/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode/uninstall.sh         # remove everything (no sudo prefix)
```

`status.sh` also works before the kit is installed, so you can check whether hardening is active from any machine.

## Updating

Fetch `update.sh` from `main` and pipe it through sudo — it deploys the matching branch files and leaves `projects.conf`, `install.conf`, `opencode.jsonc`, and the opencode binary untouched:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/main/files/update.sh | sudo bash
```

## Uninstall

```bash
bash /usr/local/lib/opencode/uninstall.sh
```

Removes the `opencode` user, all files, ACLs, hooks, and sudoers rules. Project files are untouched.

## Documentation

See [docs/MANUAL.md](docs/MANUAL.md) for:
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
