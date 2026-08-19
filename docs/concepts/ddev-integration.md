# ddev integration

This page explains how ddev runs as the `opencode` user, which paths are
handed over (and why), and the trade-offs around ports, certificates, and
SSH keys.

## One user, one daemon

ddev runs **always as `opencode`** — no delegation shim, no transaction, and
no two owners for `.ddev/`:

- **Agent (opencode session):** ddev runs natively as `opencode`.
- **Your terminal (default user):** the kit hooks a `ddev()` shell function
  into your `~/.bashrc` / `~/.zshrc` / `~/.profile`. It execs
  `/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode` via a
  passwordless sudoers rule, which re-sets the opencode environment
  (`HOME`, `XDG_RUNTIME_DIR`, `DOCKER_HOST` per backend) and runs the
  **real** ddev.

Both sides share one ddev home (`/home/opencode/.ddev`) and one rootless
daemon. Consequence: `docker ps` in your own terminal and in an agent
session list the same containers — but a colleague's rootful docker daemon
is a different world entirely.

### Why scripts must take the detour

The `ddev()` function lives in your shell RC files — and shell functions
exist only in shells that loaded those files, i.e. your interactive
terminal sessions:

| Who calls `ddev`? | What happens |
|---|---|
| You, in a terminal | The function intercepts the call → runs via the sudoers helper as `opencode` ✔ |
| A script (cronjob, Makefile, deploy script) | Calls the **real ddev binary** as your user — the function never applies ✘ |

In the second case ddev runs as your user instead of `opencode` — two
owners for `.ddev/`, a different daemon: exactly the state the kit
prevents. Two ways out for scripts:

1. Run the script from a normal terminal (it inherits the function).
2. Call the helper explicitly — this is exactly what the `ddev()` function
   does internally, minus the shell function in between:

   ```bash
   sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode start
   ```

## ddev-managed paths (the EPERM fixes)

ddev chmods `.ddev/` and the app-type's **settings directories
unconditionally**, and `chmod` is owner-only on Linux — so these paths must
belong to `opencode:opencode` (with `g+w`). The kit hands them over, at
**any depth** under each registered root (a root is usually a parent folder
like `/var/www/vhosts` holding several projects):

| App type (`.ddev/config.yaml` `type:`) | Handed-over directories |
|---|---|
| `typo3` | `config/system`, `<docroot>/typo3conf` (composer v12+, legacy v12 `system/`, v11−) |
| `drupal*`, `backdrop` | `<docroot>/sites/default` |
| `magento*` | `app/etc` |

The handover runs on install, on `config.sh projects add`, on
`config.sh refresh`, and unconditionally on every `update.sh`. Your
`.git/` stays yours (mode 700, untouched).

Notes:

- ddev resets a settings directory's mode to `0755` on each start — you
  keep editing the **files** (group-writable), and `update.sh`/`refresh`
  re-applies `g+w` to the directory.
- **wordpress** manages `wp-config.php`, a *file* at the project root — the
  kit does not hand the project root over. Keep the file user-managed
  (remove the `#ddev-generated` marker) or set
  `disable_settings_management: true` in `.ddev/config.yaml`.
- Unknown app types (e.g. `php`) are skipped.

## Provisioned by the kit

- `/home/opencode/.ddev` — the opencode user's global ddev home (project
  registry, mutagen binaries, `ddev auth ssh` key cache).
- **Router ports** — rootless containers cannot bind <1024; either the
  sysctl (`ip_unprivileged_port_start=80`, asked at install) or higher
  ports:

  ```bash
  sudo -u opencode ddev config global --router-http-port 8080 --router-https-port 8443
  ```

- **mkcert CA** — reused from the Windows user (WSL2: scanned from
  `/mnt/c/Users/*/AppData/Local/mkcert`) or the developer's CAROOT so
  browsers keep trusting ddev's HTTPS certs; a new CA is generated only as
  a last resort.

## The SSH-key trade-off

`ddev auth ssh` / composer private keys live in `/home/opencode/.ddev` and
are **agent-readable** — ddev runs as one user, including in your terminal,
so there is no safer place the import could put them: once a key is
imported (by you or by an approved agent command), every opencode session
can read it from disk.

The template denies the import command (`ddev auth ssh*`, incl. `sudo`) so
the decision stays with you — run it in your terminal if you accept the
trade-off. The read/edit denies (`*id_rsa*`, `*.pem`, …) and the bash
tripwires keep gating opencode's tools. A project that broadly allows
`ddev *` must re-add the specific deny **after** its allow (see
[allow docker/ddev](../how-to/container-tools.md)). Prefer dedicated,
rotatable deploy keys and rotate them if the machine is not trusted.

## First start is slow

The **first** `ddev start` as `opencode` downloads mutagen and pulls images
into the rootless daemon; everything afterwards reuses that state.

## Database migration from your old daemon

Before the kit, ddev ran as **you** against your daemon. At install time
the kit exports every registered project's database while your side still
works — one project at a time (`ddev start` → `ddev export-db` →
`ddev stop`, so dozens of projects never run simultaneously), then powers
the old daemon off (volumes are kept). The dumps land in
`/var/backups/opencode-permissions-kit/ddev-migration-<timestamp>/`;
the kit never deletes them. Projects without a database
(`omit_containers: [db]`) are skipped automatically.

The **import is deliberately your call**, not part of the install (the
first opencode-side start pulls images and takes a while). After the
install:

```bash
# all at once:
sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh import
# or per project (the ddev() function already runs as opencode):
ddev start <project> && ddev import-db <project> --file=<dump>.sql.gz
```

`opencode-permissions-kit status` lists dumps still waiting for import.
Only each project's **default** database is exported; extra named
databases need a manual `ddev export-db --database=<name>` on the old
side — do that **before** the `.ddev` handover made your side
inoperable (see [troubleshooting](../troubleshooting.md)).
