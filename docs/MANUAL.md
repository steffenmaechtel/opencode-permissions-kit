# opencode permissions kit — Manual

## What It Does

This kit secures [opencode](https://opencode.ai) by running it as a dedicated Linux user (`opencode`) with hard Linux-ACL denies on sensitive files (`.env`, `settings.php`, `auth.json`, SSH keys, etc.).

Once installed, a developer opens a terminal in a project directory and runs `opencode` — the wrapper validates the directory, refreshes ACLs, then starts opencode as the `opencode` user. Denied files are unreadable at the Linux level; not even `cat .env` works.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/0.0.8/files/install.sh | sudo bash
```

The script detects that it is being streamed, fetches its sibling files (config.sh, update.sh, uninstall.sh, status.sh, wrapper, hooks, templates) from the same release tag, and walks you through the setup. Follow the prompts to select project directories. After the install, `cd` into a project and run:

```bash
opencode
```

No npm package and no opencode plugin are involved — the kit is system-level only.

## Managing Project Directories

Project roots are stored in `/etc/opencode/projects.conf` (one absolute path per line). The wrapper only allows `opencode` to start inside one of these directories or their subdirectories.

### Adding More Projects

**Option A — Use `config.sh` (recommended after install):**

```bash
sudo bash /usr/local/lib/opencode/config.sh projects add /var/www/vhosts/new-project
```

You can pass multiple paths:

```bash
sudo bash /usr/local/lib/opencode/config.sh projects add /var/www/vhosts/site-a /var/www/vhosts/site-b
```

`config.sh` updates `projects.conf`, applies the base filesystem bits (group `www-data`, setgid, default ACL), and re-runs `protect-projects.sh --force` in one step. It is non-interactive when you pass `--yes`.

**Option B — Re-run `install.sh` (during initial setup):**
```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/0.0.8/files/install.sh | sudo bash -s -- --projects /var/www/vhosts/new-project
```
You can pass multiple paths:
```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/0.0.8/files/install.sh | sudo bash -s -- --projects /var/www/vhosts/site-a /var/www/vhosts/site-b
```
(Or re-run a local checkout with `sudo bash files/install.sh --projects ...`.)

**Option C — Edit the config directly:**
```bash
sudo nano /etc/opencode/projects.conf
```
Add one path per line, then apply ACLs to the new directory:
```bash
sudo /usr/local/lib/opencode/protect-projects.sh --force
```

### Listing Configured Directories

```bash
cat /etc/opencode/projects.conf
```

### Removing a Project Directory

**Option A — Use `config.sh`:**

```bash
sudo bash /usr/local/lib/opencode/config.sh projects remove /var/www/vhosts/old-project
```

Removes the line from `/etc/opencode/projects.conf`. ACL denies on that directory remain on disk until you clear them manually.

**Option B — Edit the config directly:**

Remove the line from `/etc/opencode/projects.conf`. ACLs on that directory remain in place but are no longer refreshed — use `getfacl` / `setfacl -x` to clean up manually or run `uninstall.sh`.

## How the Wrapper Works

Every `opencode` invocation goes through the wrapper at `/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a path listed in `/etc/opencode/projects.conf`. If not, an error is shown with the list of valid directories and opencode does not start.
2. **Refresh ACL denies** — runs `protect-projects.sh` to ensure sensitive files are blocked.
3. **Execute** — starts opencode as the `opencode` user.

## Customizing the Deny List

### Global Config

Edit the config file (as your default user, no `sudo` needed — the directory is group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add deny patterns under `permission.read.deny` and `permission.edit.deny`. Changes take effect on the next `opencode` start.

See `files/opencode.jsonc` for the default template.

### Project-Specific Config

Each project can have its own `opencode.jsonc` (or `opencode.json`) in its root directory. Project configs **extend** the global config — they add denies cumulatively, never weaken existing rules.

Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

How it works:

- **`permission.read.deny` / `permission.edit.deny`**: Merged with global denies. `protect-projects.sh` applies ACLs scoped to this project only.
- **`permission.read.allow` / `permission.edit.allow`**: Removes global ACL denies **for this project only**. In the wrapper you'll see a warning listing the overridden patterns.
- **`permission.bash`**: Project rules override global bash rules (opencode standard).

A project without its own config gets only the global protection.

See `tests/fixtures/project-opencode.jsonc` for a full example (TYPO3 project).

### `.git/config` Hardening (Optional)

`.git/config` can contain remote URLs with embedded credentials. When blocked, opencode **cannot execute any git commands** — no commit, push, pull, status, diff, or log. The developer must handle all git operations themselves.

**Enable during install:**

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/0.0.8/files/install.sh | sudo bash -s -- --secure-git-config
```

Or answer "Yes" when prompted during interactive install.

**Toggle later (without re-running install):**

```bash
sudo bash /usr/local/lib/opencode/config.sh git-config on     # block .git/config
sudo bash /usr/local/lib/opencode/config.sh git-config off    # allow git access again
sudo bash /usr/local/lib/opencode/config.sh git-config status # show current state
```

**Enable manually** (add to global or project config):

```jsonc
"permission": {
    "read": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    },
    "edit": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    }
}
```

When to enable:
- Remote URLs contain embedded tokens (e.g. `https://user:ghp_xxx@github.com/...`)
- You don't want opencode to run git at all

When to leave open:
- You use SSH keys (no token in remote URL)
- You use a credential helper (Git Credential Manager)
- You want opencode to commit/push on your behalf

## Git Hooks

Global git hooks re-apply ACL denies automatically after:

- `git checkout` / `git switch` / `git pull` (fast-forward)
- `git merge`
- `git commit`

The hooks run `protect-projects.sh --force --cwd "$(pwd)"` from the worktree root, so the project-level `opencode.jsonc` of the repository you are working in is applied too — not just the global denies.

No per-repo setup required — `core.hooksPath` is set globally for both users.

## Verification

Run the test suite to confirm everything is working:

```bash
./tests/verify.sh
```

It checks users, groups, wrapper, hooks, sudoers, and that `opencode` truly cannot read sensitive files like `.env` and `settings.php`.

### Development Tests

These tests run without system dependencies and verify logic in isolation:

```bash
./tests/test-wrapper-validation.sh   # 17 tests: directory validation
./tests/test-project-config.sh       # 29 tests: project config parsing & matching
```

## Management Scripts

The kit is system-level only — no opencode plugin, no npm package. Everything is managed from a regular terminal (the `sudo` password prompt needs a real TTY, not opencode):

```bash
sudo bash /usr/local/lib/opencode/status.sh       # show protection status
sudo bash /usr/local/lib/opencode/config.sh       # change settings (projects, .git/config, ACL refresh)
sudo bash /usr/local/lib/opencode/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode/uninstall.sh         # remove everything (no sudo prefix)
```

All of these scripts are deployed to `/usr/local/lib/opencode/` by the installer, so there is nothing to fetch or configure afterwards.

`status.sh` shows the current protection state:

```
opencode permissions kit  v0.0.8
=============================================

Mode:       hardened (opencode runs as its own user)
User:       opencode exists
Wrapper:    /usr/local/bin/opencode -> /usr/local/lib/opencode/wrapper
Library:    /usr/local/lib/opencode
Config:     /home/opencode/.config/opencode/opencode.jsonc
Default user: info  group: www-data

Project roots (1):
  - /var/www/vhosts

.git/config hardening: OFF

Management (run in a terminal):
    sudo /usr/local/lib/opencode/config.sh                 change settings
    sudo /usr/local/lib/opencode/update.sh                 re-deploy kit after an update
    bash /usr/local/lib/opencode/uninstall.sh              remove the kit
```

Before the kit is installed, `status.sh` still works and reports that hardening is **NOT active** — handy for checking any machine.

## Updating the Kit

After `git pull` (or a new release) you can re-deploy the kit **without** re-answering the install-time questions:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/0.0.8/files/update.sh | sudo bash
```

Or run the deployed copy directly:

```bash
sudo bash /usr/local/lib/opencode/update.sh
```

`update.sh` fetches the matching release files (wrapper, hooks, `protect-projects.sh`, `jsonc-parser.py`, `sudoers` template, `umask` profile, `config.sh`, `uninstall.sh`, `status.sh`) and refreshes the `install.conf` version stamp. It does **not** touch:

- `/etc/opencode/projects.conf`
- `/etc/opencode/install.conf` (except the `VERSION=` line)
- `/home/opencode/.config/opencode/opencode.jsonc`
- the opencode binary at `/usr/local/lib/opencode/bin/opencode`
- any ACLs or filesystem metadata

Add `--refresh` to also re-run `protect-projects.sh --force` after the deploy:

```bash
sudo bash /usr/local/lib/opencode/update.sh --refresh
```

## Uninstalling

```bash
bash /usr/local/lib/opencode/uninstall.sh
```

Run it as your normal user (no `sudo` prefix — the script handles sudo itself). Options: `--yes`, `--dry-run`, `--debug`.

Removes the `opencode` user, all installed files, ACLs, hooks, and sudoers rules. Project files are untouched.

## File Overview

| Path | Purpose |
|---|---|
| `/usr/local/bin/opencode` | Wrapper (symlink to `/usr/local/lib/opencode/wrapper`) |
| `/usr/local/lib/opencode/wrapper` | Validates directory, refreshes ACLs, execs opencode |
| `/usr/local/lib/opencode/protect-projects.sh` | Applies ACL denies to sensitive files |
| `/usr/local/lib/opencode/config.sh` | Change settings post-install (projects, git-config, refresh) |
| `/usr/local/lib/opencode/update.sh` | Re-deploy the kit after an update, no prompts |
| `/usr/local/lib/opencode/uninstall.sh` | Uninstall script |
| `/usr/local/lib/opencode/status.sh` | Show protection status (works even before install) |
| `/usr/local/lib/opencode/bin/opencode` | The actual opencode binary |
| `/etc/opencode/projects.conf` | Project roots (one per line) |
| `/etc/opencode/install.conf` | `DEFAULT_USER`, `OPENCODE_USER`, `WWW_GROUP`, `VERSION` |
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with deny patterns |
| `/etc/sudoers.d/opencode` | Sudo rules for wrapper and protect-projects.sh |
| `/usr/local/lib/opencode/hooks/` | Global git hooks (post-checkout, post-merge, post-commit) |
