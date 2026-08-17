# Customize the deny list

This guide shows how to change which files the agent may read and edit —
globally and per project.

All read/edit rules are **soft**: they gate opencode's own tools, not the OS.
See the [security model](../concepts/security-model.md) for what that means.

## Edit the global config

Open the config as your default user (no `sudo` — the directory is
group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add or remove deny patterns under `permission.read` / `permission.edit`.
Changes take effect on the next `opencode` start.

The bundled template additionally:

- runs `permission.bash` as **ask-by-default** (`"*": "ask"`) with a small
  allowlist of harmless read-only commands,
- hard-denies system-destructive and container commands,
- mirrors the read/edit deny patterns as **ask tripwires** with trailing `*`
  in bash — so `cat settings.php | grep DB` still prompts. The tripwire is
  lexical: variables (`F=.env; cat $F`), globs, and indirection evade it.

## Add a per-project config

Each project can have its own `opencode.jsonc` in its root. Project configs
**extend** the global config (opencode merges them; last matching rule
wins).

Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

A project without its own config gets only the global protection.

## Know the scope boundary

The kit protects **locations, not information flows**. Once content leaves
the project roots (`cp .env /tmp/backup`), no scan recaptures it. As a
visibility aid, `status.sh` ends with a **leak scan**: a name-based,
report-only sweep of the scratch directories (`/tmp`, `/var/tmp`,
`/dev/shm`, overridable via `LEAK_SCAN_DIRS`) listing files matching the
deny patterns. Renamed copies stay invisible; false positives are expected.

On the git side, prevent secrets from entering history in the first place
(pre-commit secret scanning, e.g. gitleaks).
