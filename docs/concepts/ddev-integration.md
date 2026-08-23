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

### Browser-opening commands (issue #20)

Commands that open a browser — `ddev launch` itself and every wrapper
whose internals spawn `ddev launch ...` (`mailpit` → `launch -m`, the
phpmyadmin/adminer add-ons and custom project host commands →
`launch :<port>`, `xhgui` bare) — cannot run as `opencode`: opening the
browser on WSL2 needs `explorer.exe` / `xdg-open` → `wslview`, i.e.
**Windows interop**, exactly what the `opencode` user must not have (an
`.exe` would run as your Windows user, outside every soft rule). The
`ddev()` function routes the whole class through a split:

1. The command runs **as `opencode`** with `DDEV_DEBUG=true`: whatever
   internal `ddev launch` child it spawns (bash host command or Go exec)
   inherits the flag, prints `FULLURL <url>` and exits instead of opening
   anything. Running as `opencode` is what makes this correct — as
   *you*, ddev cannot see the rootless daemon, would decide "not
   running" and run its internal `ddev start` on **every** call; the
   https/mkcert detection needs the `opencode`-owned CAROOT. A stopped
   project is started by that same run.
2. The URL is opened **as you** (`explorer.exe`, falling back to
   `xdg-open`) — your interop, your browser.

Project-specific browser commands can be added to
`/etc/opencode-permissions-kit/ddev-browser-cmds.conf` (one command name
per line, `#` comments) — any ddev host command that internally calls
`ddev launch` fits the same mechanism.

Net effect: browser commands in your terminal open the browser without a
restart detour; agent-side they still fail interop-blocked (by design —
the agent should not pop windows on your Windows desktop; it can hand
you the URL from `ddev describe` instead).

### Scripts: bash children inherit the function

The `ddev()` function lives in your shell RC files — and shell functions
exist only in shells that loaded those files. To cover **vendor scripts**
like TYPO3's `vendor/bin/runTests.sh`, which call `ddev` in a child bash
process (issue #18), the hook uses two transports: it **exports** the
function (bash children import it directly), and it sets **`BASH_ENV`**
pointing at itself (non-interactive bash startups source that file — a
plain variable, so it even survives `#!/bin/sh` wrapper scripts and
Makefile/zsh spawn paths in between). A user-set `BASH_ENV` is never
overridden.

| Who calls `ddev`? | What happens |
|---|---|
| You, in a terminal | The function intercepts the call → runs via the sudoers helper as `opencode` ✔ |
| A bash script started from your terminal (e.g. `vendor/bin/runTests.sh`, also behind its `#!/bin/sh` wrapper) | Gets the function via `export -f` / `BASH_ENV` → runs as `opencode` ✔ |
| A pure `#!/bin/sh` (dash) target script, cronjob, IDE task — anything outside your shell environment | Calls the **real ddev binary** as your user — the function never applies ✘ |

In the last case ddev runs as your user instead of `opencode` — two
owners for `.ddev/`, a different daemon: exactly the state the kit
prevents. Ways out for those scripts:

1. Force bash for a dash script: `bash vendor/bin/runTests.sh -s phpstan`.
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

**The project root during bootstrap.** A freshly cloned `typo3` project
has no `vendor/` yet — ddev cannot detect the installation and falls back
to writing its settings file at the **project root**, chmod-ing the root
directory to `0755` on every start. Since `chmod` is owner-only, the kit
hands the root *directory inode* (never its contents) to `opencode` with
mode `2755`: the exact `0755` base bits make ddev's chmod a no-op, so
`ddev start` and `ddev composer install` work from the first run. While
the root is handed over, creating new top-level files is limited (editing
existing files is not — they stay group-writable). Once TYPO3 is
installed (`vendor/` or `<docroot>/typo3` present, the same markers
ddev's detection uses), ddev targets `config/system` instead and the kit
hands the root **back to you** (`2775`, group-writable) on the next
install/`projects add`/`refresh`/`update --refresh`.

The handover runs on install, on `config.sh projects add`, on
`config.sh refresh`, on `config.sh handover <path>` (one project, no
group baseline — the fast repair after cloning a new project), and
unconditionally on every `update.sh`. The `ddev` shell hook covers the
gap between cloning and the next handover run: before `ddev start` /
`ddev restart` it detects the bootstrap case (fresh `typo3` clone whose
root still belongs to you) and prints the ready-made
`config handover` command instead of leaving you with ddev's cryptic
`operation not permitted`. The scan never descends into `vendor/`,
`node_modules/` or `testdata/` trees — a `.ddev` directory found there
is a shipped test fixture, not a project (a checkout of ddev's own
repository carries dozens, issue #29). Your
`.git/` stays yours (ownership untouched; the group baseline makes it
group-accessible — see [the sharing group](sharing-group.md)).

## Dev-owned projects (the alternative to handovers)

The handover model exists because ddev chmods settings paths outside
`.ddev/` on every start. **Dev-owned mode removes that cause**: the kit
writes `disable_settings_management: true` into each project's committed
`.ddev/config.yaml` (installer default; `config.sh ddev-settings
on|off|status`) — inserted directly below the head of the file (after
`corepack_enable:`, `type:` as fallback), never appended at the end
where ddev's default template hides it behind a wall of commented
examples (issue #28). Fixture `.ddev` dirs under `vendor/`,
`node_modules/` and `testdata/` are never flagged. ddev then never
writes or chmods anything outside
`.ddev/`. Settings dirs and project roots stay developer-owned
permanently (2775/664 via the group baseline) — no handover, no
handback, `git checkout` always free, fresh clones work from the first
`ddev start`. The trade-off: your repo owns the CMS settings file (for
TYPO3 a small committed `AdditionalConfiguration.php` — see the
[how-to](../how-to/dev-owned-projects.md)). A project carrying the
committed flag is dev-owned regardless of the kit mode; the mode only
decides whether the kit writes the flag.

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

## Hostnames and the Windows hosts file

On WSL2, stock ddev manages the **Windows** hosts file (running
`ddev-hostname.exe` via WSL interop). For the kit's ddev user that path
is closed — `/mnt/c` is restricted to the developer, and interop is
additionally broken on many WSL2+systemd hosts. ddev then only **warns**
and continues (`ddev start` succeeds), but your Windows **browser**
cannot resolve custom-`project_tld` domains until the hostnames are in
the Windows hosts file.

The kit deliberately gives the agent **no** hosts-file access. Instead
the developer gets a one-command bridge that uses **ddev's own
elevation path** (`ddev hostname <name> 127.0.0.1` as your user →
`ddev-hostname.exe` → the Windows permission dialog):

```bash
opencode-permissions-kit ddev-hosts-add          # in the project dir
```

It adds every hostname missing from
`C:\Windows\System32\drivers\etc\hosts` — the project name + TLD,
`additional_hostnames`, and non-wildcard `additional_fqdns`. Hostnames
under the default `*.ddev.site` TLD are never touched: ddev's public
wildcard DNS already resolves them, no hosts entry is needed. After
`ddev start`/`restart` the kit's `ddev()` shell function prints the
missing hostnames with one ready-made command each —
`opencode-permissions-kit ddev-hosts-add <hostname>` also works
standalone from anywhere, so you add exactly what was reported;
`ddev-hosts-check` lists them on demand, and
`opencode-permissions-kit status` reports them per project root (its
scan skips `vendor/`, `node_modules/` and `testdata/` — packages and
test fixtures ship their own `.ddev` dirs that are not your projects).

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

A project that no longer **starts** (old production leftovers) does not
block the others: the export continues, then the installer lists the
failed projects and asks whether to continue anyway (their databases
would become unreachable) or abort so you can fix them first — the
`.ddev` handover has not happened yet at that point, so your side still
works and a re-run retries cleanly. `--yes` installs print the list and
continue.

Re-running the installer after an abort **resumes** instead of repeating:
projects whose dumps already exist are skipped, only missing or
previously-failed ones are exported (into the same dump directory).
