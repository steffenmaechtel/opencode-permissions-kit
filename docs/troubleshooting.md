# Troubleshooting

Known failure modes — each entry follows symptom → cause → fix. If your case
is missing, open an issue.

## The install refuses: "Ubuntu <version> is not supported by the kit"

**Cause:** the kit supports Ubuntu 22.04, Ubuntu 24.04 and Debian 12+ (see
the [support matrix](getting-started.md#supported-distros)). Ubuntu 26.04 is
blocked by known upstream errors (its default sudo freezes streamed
installs; its systemd sporadically refuses user managers).

**Fix:** use Ubuntu 24.04 — the only field-tested distro. If you know what
you are doing, re-run the installer with `--force-unsupported-distro`.
Existing installs on any distro keep updating normally via `opk update`.

## The install refuses: "The installer must run from your normal user account with sudo"

**Cause:** the installer was started from a root shell — typically
`wsl -u root` on Windows, `su -`, or a root ssh session. Those have no
`SUDO_USER`, so the installer would register `root` as the developer: the
shell hooks land in `/root/.bashrc` and the real developer account gets
nothing — a state no `opk update` can repair.

**Fix:** open a shell as your regular user and re-run the install command
there. If an earlier root-shell install already completed, run
`opk uninstall` from your regular user too (it refuses root shells), then
reinstall.

If your distro has no regular user yet (some minimal WSL images start as
root), create one first — `useradd -m -G sudo -s /bin/bash <name>` plus
`passwd <name>` — switch into it (from Windows:
`wsl -d <distro> -u <name>`) and run the install from there.

## ddev launch / mailpit / phpmyadmin fails with "WSL Interoperability is disabled" / "Permission denied"

**Cause:** the command ran as the `opencode` user (the `ddev()` function
routes everything there). Opening a browser on WSL2 needs Windows interop,
which the `opencode` user deliberately has not. The
`grep ... WSLInterop` line is cosmetic; the real blocker is the permission
denied.

**Fix:**

- in your terminal: update the kit and open a new terminal — the `ddev()`
  function routes browser commands (`launch`, `mailpit`, `phpmyadmin`,
  `adminer`, `xhgui`) through the split URL-computation-as-opencode +
  browser-open-as-developer. A project-specific browser command joins the
  class via one line in
  `/etc/opencode-permissions-kit/ddev-browser-cmds.conf`;
- in an agent session this stays blocked **by design**: the agent should
  not open windows on your Windows desktop. Ask it for the URL instead
  (`ddev describe`) and open it yourself.

## vendor script (runTests.sh) fails with "chmod .ddev/...: operation not permitted"

**Cause:** the script ran ddev as **you** (the developer), not as the
`opencode` user the kit uses. The kit's `ddev()` shell function reaches
bash child scripts (exported function + `BASH_ENV`, covering
`vendor/bin/runTests.sh` including its `#!/bin/sh` wrapper), but not pure
dash targets, cronjobs, IDE tasks, or shells that never loaded your RC
files.

**Fix:**

- update the kit and open a **new terminal** (both transports ship with the
  hook), then run the script again;
- force bash for pure `#!/bin/sh` vendor scripts:
  `bash vendor/bin/runTests.sh -s phpstan`;
- or run the inner ddev command directly (it works in your terminal):

  ```bash
  ddev exec vendor/bin/phpstan analyse -c vendor/somepath/phpstan/phpstan.neon \
    --verbose --no-progress --no-interaction --memory-limit 4G
  ```

## ddev fails with "all predefined address pools have been fully subnetted"

**Cause:** a stock Docker limit, not a kit one — Docker carves one subnet
per user-defined bridge network out of its default address pools (roughly
30 networks). ddev creates one network per project, and `ddev stop` keeps
it, so stopped-but-not-deleted projects keep consuming subnets.

**Fix:** reclaim abandoned networks — this prunes every network no
container uses anymore:

```bash
sudo -u opencode env HOME=/home/opencode \
  DOCKER_HOST=unix:///run/user/$(id -u opencode)/docker.sock \
  docker network prune -f
```

If you legitimately run that many projects in parallel, raise the pools
(only networks created after the restart come from the enlarged pools; the
`tee` below creates the file — an existing `daemon.json` is overwritten,
merge the key yourself before running it):

```bash
sudo mkdir -p /home/opencode/.config/docker
sudo tee /home/opencode/.config/docker/daemon.json >/dev/null <<'EOF'
{
  "default-address-pools": [
    { "base": "172.17.0.0/12", "size": 24 },
    { "base": "192.168.0.0/16", "size": 24 }
  ]
}
EOF
sudo chown -R opencode:opencode /home/opencode/.config/docker
sudo -u opencode XDG_RUNTIME_DIR=/run/user/$(id -u opencode) \
  systemctl --user restart docker.service
```

`size: 24` carves `/24` subnets instead: 4,000+ networks, each still
offering 254 container addresses.

## git: "detected dubious ownership in repository at ..."

**Cause:** git refuses repositories owned by another user. The kit sets
`safe.directory '*'` in the **opencode user's** global git config, so the
agent side is covered. You only hit this as the **developer** when you run
git in a repository the agent created (cloned as `opencode`, so it is
`opencode`-owned).

**Fix:** trust the agent's checkouts (developer side):

```bash
git config --global --add safe.directory '*'
```

or add single paths instead of the wildcard. If the agent side ever
regresses (e.g. a deleted `~opencode/.gitconfig`), re-run the kit's updater
— it re-applies the setting.

## git is below the tested version baseline

**Cause:** your distro ships a git older than the kit's tested floor of
2.30. Nothing breaks outright — the installer **warns but does not abort**;
agent-side git workflows on older versions are untested.

**Fix (WSL Ubuntu):** track the current git via the official git-core PPA
(the installer's pre-flight and `opk status` print the same hint):

```bash
sudo add-apt-repository ppa:git-core/ppa
sudo apt update
sudo apt install git
```

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
exports them before the `.ddev` handover: automatically in Standard mode,
on request in Advanced mode).

**Fix:** check what the install already exported:

```bash
ls /var/backups/opencode-permissions-kit/ddev-migration-*/
```

- Dumps there? Import them:
  `sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import`
  (or per project: `ddev start <name> && ddev import-db <name> --file=<dump>.sql.gz`).
- No dumps (export skipped/declined) and `.ddev` is **still yours**? Export
  now, before using ddev again:
  `sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate export <your-user> <project-roots>`
- `.ddev` already handed over to `opencode`? Temporarily give it back,
  export, hand it over again (replace `$USER` with your username):

  ```bash
  sudo find /var/www/vhosts -type d -name .ddev -prune -print0 \
    | xargs -0 -n1 -I{} sudo chown -R "$USER" {}
  sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate export "$USER" /var/www/vhosts
  sudo opk config refresh
  ```

**Only some of my databases were exported** — the install said
`N ok, 0 failed` with N smaller than your project count:

- Re-run the export — already-dumped projects are skipped, only the missing
  ones run:
  `sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate export "$USER" <project-roots>`
- See what the export would take today (read-only, as your user):
  `/usr/local/lib/opencode-permissions-kit/bin/ddev-migrate registry <your-user> <project-roots>`
  — projects listed as `outside:` fall outside the registered roots and
  are never exported.
- A project whose export **fails on every run** (for example its database
  was never pulled from staging) does not block the remaining projects — it
  is recorded as `FAIL` and the summary lists it. To mark a project as
  intentionally database-less, add `omit_containers: [db]` to its
  `.ddev/config.yaml`: the export then records a clean SKIP.
- Registry entries can also have grown after a (partial) export — `opk
  status` reports `db dumps INCOMPLETE` then. Fix: follow the `.ddev
  already handed over` runbook above once; only the missing projects run.

Details: [ddev integration](concepts/ddev-integration.md).

## The agent gets "Permission denied" on my project / ddev claims "a project cannot be created in the DDEV source code"

**Cause:** a project root under your home directory (for example
`/home/<you>/www/vhosts`) needs `+x` on EVERY path component above it — and
Ubuntu 24.04 ships home directories as `0750`. With a non-traversable home
the `opencode` user cannot resolve the path at all, and ddev misreports the
same EACCES as `a project cannot be created in the DDEV source code`.

**Fix:** the installer and `opk config refresh` grant traverse-only ACLs
(`g:<sharing-group>:--x` — no listing, no reading) on the blocking
ancestors automatically. To repair an older install:

```bash
sudo opk config refresh
# or manually (traverse-only, no read):
sudo setfacl -m g:opencode:X /home/<you> /home/<you>/www
```

`opk status` shows a warning per affected root.

## ddev start fails with "bind mounts can't be used with Docker Rootless"

**Cause:** ddev 1.25.0–1.25.2 cannot use bind mounts against a rootless
Docker daemon; upstream fixed that in v1.25.3.

**Fix:** the installer and the `opk config container-backend
docker-rootless` switch set ddev's global `no-bind-mounts` flag
automatically when they detect one of those versions — nothing to do. On an
affected existing install, run it once yourself (or upgrade ddev to
>= 1.25.3):

```bash
sudo -u opencode env HOME=/home/opencode ddev config global --no-bind-mounts
```

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

**Fix:** run the handover (fast — one project, no group baseline):

```bash
sudo opk config handover /var/www/vhosts/<project>
```

(or `update.sh` / `config.sh refresh` to re-run it over every registered
root). The `ddev` shell hook prints this exact command when it detects the
case before a `ddev start`. The handover table lives in
[ddev integration](concepts/ddev-integration.md).

**Tired of the ownership back-and-forth?** Switch the project to
[dev-owned](how-to/dev-owned-projects.md): `config ddev-settings on` makes
ddev never touch paths outside `.ddev/`, everything stays permanently yours,
and `git checkout` / `mv` / `rm` cannot hit ownership errors anymore.

## ddev warns "Unable to open hosts file ... permission denied"

**Cause:** ddev runs as `opencode` and can neither read the Windows hosts
file nor run Windows binaries — the agent must not reach the Windows
profile. ddev only **warns**; `ddev start` succeeds, but your Windows
browser cannot resolve custom-`project_tld` domains yet.

**Fix (developer side):** add the missing hostnames via the kit's bridge —
it runs ddev's own `ddev hostname` as your user and Windows shows its
permission dialog:

```bash
cd /var/www/vhosts/<project>
opk ddev-hosts-add
```

`ddev-hosts-check` lists what is missing (one ready-made
`ddev-hosts-add <hostname>` command each — that form works from anywhere);
`opk status` reports it per project root. Manual fallback: edit
`C:\Windows\System32\drivers\etc\hosts` in an elevated editor and add
`127.0.0.1 <project>.<tld>` per hostname. Hostnames
under the default `*.ddev.site` TLD never need an entry (ddev's wildcard
DNS). If WSL interop itself is broken (`cmd.exe` fails with "WSL
Interoperability is disabled"), re-register it:

```bash
sudo sh -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'
```

(persists until the next `wsl --shutdown` — and check `/etc/wsl.conf` has
no `[interop] enabled=false`).

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
`wsl --shutdown` and restart WSL. The kit never edits `/etc/wsl.conf`
itself — applying the snippet is yours. Details:
[security model](concepts/security-model.md).

## `opencode console login` / `opencode auth login` crashes with EACCES on powershell.exe

**Cause 1:** the device login opens its verification URL through the `open`
package bundled with opencode, which spawns the Windows powershell.exe. On
a restricted `/mnt/c` the `opencode` user may not execute it, and the login
dies on that spawn error. The kit's browser bridge redirects that lookup to
a harmless stand-in — the crash means the bridge is not in place (broken
deploy) or the login ran from a directory the `opencode` user cannot read
(typically your `$HOME`, mode 750) — the wrapper normally moves those
logins to a readable directory, so that variant means an old wrapper is
deployed.

**Fix:** run

```bash
sudo opk update
sudo opk wsl-add-opencode-1-fix
```

The block takes effect immediately (no `wsl --shutdown` needed). Without a
bridge, the login still works when you open the printed URL yourself: the
crash happens *after* URL and device code are displayed. Details:
[security model](concepts/security-model.md).

**Diagnose — expected vs. broken:** when the login runs with the agent
identity on a hardened mount, the stand-in prints
`auto-open unavailable for the agent — open the printed URL manually`
straight to your terminal and the login keeps polling. That line is the
*designed* state, not an error. Self-test as your own user — the browser
must open `https://opencode.ai`:

```bash
STANDIN=/usr/local/lib/opencode-permissions-kit/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
OPK_BROWSER_BRIDGE_DEBUG=1 "$STANDIN" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -EncodedCommand UwB0AGEAcgB0ACAAIgBoAHQAdABwAHMAOgAvAC8AbwBwAGUAbgBjAG8AZABlAC4AYQBpACIA
```

## `opencode auth login` (2.x, OpenCode Console account) dies with `Executable not found in $PATH: "xdg-open"`

**Cause:** opencode 1.18.33+/2.0.18+ open the verification URL through
`open` 11.x, which access-checks powershell.exe and falls back to
`xdg-open` — and WSL distros ship no xdg-open by default. On 2.x that
failed spawn escapes the CLI's error handling: the login dies right after
printing URL and device code.

**Fix:** update the kit (`sudo opk update`) — it deploys an xdg-open
fallback shim to `/usr/local/bin/xdg-open`, but only while no real
xdg-open exists (`sudo apt install xdg-utils` works too; the kit stands
back once a real one appears). The login then degrades gracefully: URL and
code stay on screen, open the URL in any browser. Self-test as your own
user — the browser must open `https://opencode.ai`:

```bash
OPK_BROWSER_BRIDGE_DEBUG=1 xdg-open https://opencode.ai
```

## Group membership (opencode group) not applied

**Cause:** group changes apply only to new login sessions.

**Fix:** open a fresh terminal (or re-login). Check with `id` — the
`opencode` group must appear.
