# Troubleshooting

This page lists known failure modes — each entry follows
symptom → cause → fix. If your case is missing, open an issue.

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
