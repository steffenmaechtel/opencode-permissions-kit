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

Non-interactive scripts calling `ddev` are not intercepted — either run
them in a terminal or call the helper directly:
`sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode <args>`.

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
