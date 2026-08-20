# Troubleshooting

This page lists known failure modes — each entry follows
symptom → cause → fix. If your case is missing, open an issue.

## vendor script (runTests.sh) fails with "chmod .ddev/...: operation not permitted"

**Symptom:** `vendor/bin/runTests.sh -s phpstan` (or similar vendor
tooling) reports port conflicts, then ddev dies with
`chmod .ddev/.webimageBuild: operation not permitted` — while the same
ddev command typed directly in the terminal works.

**Cause:** the script ran ddev as **you** (the developer), not as the
`opencode` user the kit uses. The kit's `ddev()` shell function is
exported to bash child scripts, but that does not reach
`#!/bin/sh` scripts, cronjobs, IDE tasks, or zsh-launched children —
there the real ddev binary runs as your user and collides with the
opencode-owned `.ddev/`.

**Fix:**

- update the kit and open a **new terminal** (the export ships with the
  hook), then run the script again — bash scripts like
  `vendor/bin/runTests.sh` are covered;
- force bash for `#!/bin/sh` vendor scripts:
  `bash vendor/bin/runTests.sh -s phpstan`;
- or run the inner ddev command directly (it works in your terminal):

  ```bash
  ddev exec vendor/bin/phpstan analyse -c vendor/somepath/phpstan/phpstan.neon --verbose --no-progress --no-interaction --memory-limit 4G
  ```

## git: "detected dubious ownership in repository at ..."

**Cause:** git refuses repositories owned by another user. The kit sets
`safe.directory '*'` in the **opencode user's** global git config (install
and update), so the agent side is covered. You only hit this as the
**developer** when you run git in a repository the agent created (cloned
as `opencode`, so it is `opencode`-owned).

**Fix:** trust the agent's checkouts (developer side):

```bash
git config --global --add safe.directory '*'
```

or add single paths instead of the wildcard. If the agent side ever
regresses (e.g. a deleted `~opencode/.gitconfig`), re-run the kit's
updater — it re-applies the setting.

## Wrapper prints a loud bypass warning on start

**Cause:** a real `~/.opencode/bin/opencode` exists — the official installer
or opencode's self-updater re-added it.

**Fix:** remove it and keep using the wrapper:

```bash
rm -rf ~/.opencode/bin
```

The kit has secured its own copy; the removal only drops the self-installed
bypass binary. Your deny-all lockout config
(`~/.config/opencode/opencode.jsonc`) protected you in the meantime — see
[the wrapper](concepts/wrapper.md).

## opencode still runs the old binary after install

**Cause:** bash caches command lookups (command hash) and the old
`~/.opencode/bin` directory may still be first in `$PATH` of running shells.

**Fix:** open a fresh terminal, or in the same shell:

```bash
hash -r
export PATH="/usr/local/bin:$PATH"
```

## The first `ddev start` takes forever

**Cause:** mutagen download and image pulls into the fresh rootless daemon.

**Fix:** none needed — wait once; every later start reuses the state. See
[ddev integration](concepts/ddev-integration.md).

## My databases are gone after the install

**Cause:** your old containers/volumes lived in your daemon; ddev now runs
as `opencode` against the kit's rootless daemon. Containers cannot move
between daemons — SQL dumps are the only portable copy (the installer
offers to create them before the `.ddev` handover).

**Fix:** check what the install already exported:

```bash
ls /var/backups/opencode-permissions-kit/ddev-migration-*/
```

- Dumps there? Import them:
  `sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh import`
  (or per project: `ddev start <name> && ddev import-db <name> --file=<dump>.sql.gz`).
- No dumps (export skipped/declined) and `.ddev` is **still yours**?
  Export now, before using ddev again:
  `sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh export <your-user> <project-roots>`
- `.ddev` already handed over to `opencode`? Temporarily give it back,
  export, hand it over again (replace `$USER` with your username):

  ```bash
  sudo find /var/www/vhosts -type d -name .ddev -prune -print0 \
    | xargs -0 -n1 -I{} sudo chown -R "$USER" {}
  sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh export "$USER" /var/www/vhosts
  sudo /usr/local/lib/opencode-permissions-kit/config.sh refresh
  ```

Details: [ddev integration](concepts/ddev-integration.md).

## ddev complains it cannot bind port 80/443

**Cause:** rootless containers cannot bind ports < 1024.

**Fix:** either the sysctl the installer offered:

```bash
sudo sysctl net.ipv4.ip_unprivileged_port_start=80
```

(make persistent — the installer's `ip_unprivileged_port_start` sysctl file
under `/etc/sysctl.d/` does this for you), or use higher router ports:

```bash
sudo -u opencode ddev config global --router-http-port 8080 --router-https-port 8443
```

## ddev reports EPERM/permission errors on settings directories

**Cause:** a settings directory (e.g. `config/system`, `sites/default`)
belongs to the developer — ddev chmods it unconditionally, and `chmod` is
owner-only on Linux.

**Fix:** run the handover:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh
```

(or `config.sh refresh`). The handover table lives in
[ddev integration](concepts/ddev-integration.md).

**EPERM on the project root itself** (`chmod /var/www/vhosts/<project>:
operation not permitted` during `ddev start` on a fresh clone): same
mechanism, different target — without `vendor/` ddev writes its settings
file at the project root and chmods the root directory. The handover
covers this bootstrap case (root inode → `opencode`, mode `2755`) and
hands the root back to you once TYPO3 is detected; see the bootstrap
paragraph in [ddev integration](concepts/ddev-integration.md).

## ddev warns "Unable to open hosts file ... permission denied"

**Cause:** two layers, and the second one is deliberate:

1. The kit's `/mnt/c` restriction: ddev runs as `opencode` and can
   neither read the Windows hosts file nor run Windows binaries — the
   agent must not reach the Windows profile. ddev only **warns**;
   `ddev start` succeeds, but your Windows browser cannot resolve
   custom-`project_tld` domains yet.
2. (Only for the fix below) WSL interop must work as your user. On many
   WSL2+systemd hosts the `WSLInterop` binfmt entry disappears — even
   `cmd.exe` fails ("WSL Interoperability is disabled"). Re-register:

   ```bash
   sudo sh -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'
   ```

   (verify with `cmd.exe /c echo hi`; persists until the next
   `wsl --shutdown` — and check `/etc/wsl.conf` has no
   `[interop] enabled=false`).

**Fix (developer side):** add the missing hostnames via the kit's
bridge — it runs ddev's own `ddev hostname` as your user and Windows
shows its permission dialog:

```bash
cd /var/www/vhosts/<project>
opencode-permissions-kit ddev-hosts-add
```

`ddev-hosts-check` lists what is missing; `opencode-permissions-kit
status` reports it per project root. Manual fallback: edit
`C:\Windows\System32\drivers\etc\hosts` in an elevated editor and add
`127.0.0.1 <project>.<tld>`. Projects on the default `ddev.site` TLD
with internet access need no hosts entry at all.

## `docker ps` in the agent session lists "wrong" containers

**Cause:** expected behavior — the session talks to the **opencode user's**
rootless daemon. Containers you started with a different user/daemon are a
different world.

**Fix:** none. Run ddev from your terminal (the kit's `ddev()` function
routes it to the same daemon) so both sides share one daemon. See
[ddev integration](concepts/ddev-integration.md).

## Wrapper warns about world-readable /mnt/c on every start

**Cause:** the WSL2 `C:` mount is world-readable by default; NTFS ACLs do
not distinguish WSL users, so the agent could read your whole Windows
profile. The kit keeps warning until the restriction is applied.

**Fix:** restrict the mount to your user via `/etc/wsl.conf`:

```ini
[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
```

(replace `uid`/`gid` with your default WSL user's), then from Windows run
`wsl --shutdown` and restart WSL. Details: [security model](concepts/security-model.md).

## Group membership (opencode group) not applied

**Cause:** group changes apply only to new login sessions.

**Fix:** open a fresh terminal (or re-login). Check with `id` — the
`opencode` group must appear.
