# ddev integration

How ddev runs as the `opencode` user, which paths are handed over, and the
trade-offs around ports, certificates, and SSH keys.

## One user, one daemon

ddev runs **always as `opencode`** — no delegation shim, no two owners for
`.ddev/`:

- **Agent (opencode session):** ddev runs natively as `opencode`.
- **Your terminal (default user):** the kit hooks a `ddev()` shell function
  into your `~/.bashrc` / `~/.zshrc` / `~/.profile`. It execs
  `/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode` via a
  passwordless sudoers rule, which re-sets the opencode environment
  (`HOME`, `XDG_RUNTIME_DIR`, `DOCKER_HOST` per backend) and runs the
  **real** ddev.

Both sides share one ddev home (`/home/opencode/.ddev`) and one rootless
daemon: `docker ps` in your terminal and in an agent session list the same
containers. A colleague's rootful docker daemon is a different world.

### Browser-opening commands

Commands that open a browser — `ddev launch` and its wrappers (`mailpit`,
the phpmyadmin/adminer add-ons, `xhgui`) — cannot open it as `opencode`:
that needs Windows interop, exactly what the agent must not have. The
`ddev()` function routes the whole class through a split:

1. The URL is read from **`ddev describe -j`** run **as `opencode`** via the
   sudoers helper (ddev maintains every URL in that document, even while the
   project is stopped). `launch` maps to `raw.primary_url` (with `launch`'s
   argument forms: path, `:<port>`, full URL), `mailpit` to
   `raw.mailpit_https_url`, `xhgui` to `raw.xhgui_https_url` (when enabled),
   add-on commands like `phpmyadmin` to `raw.services.<name>.https_url`.
   A stopped project is started first.
2. Commands whose URL describe does not carry (add-on not yet installed,
   custom project commands without a matching service) **plain-run as
   `opencode`**: output, prompts and exit code pass through; only the
   browser open is skipped.
3. The URL is printed and opened **as you** (`explorer.exe`, falling back to
   `xdg-open`) — your interop, your browser.

Project-specific browser commands can be added to
`/etc/opencode-permissions-kit/ddev-browser-cmds.conf` (one command name per
line, `#` comments): they open their browser when `ddev describe` carries a
service of the same name; otherwise they plain-run as `opencode`.

Agent-side, browser commands stay interop-blocked **by design** — the agent
should not pop windows on your Windows desktop. Ask it for the URL instead
(`ddev describe`) and open it yourself.

### Scripts: bash children inherit the function

The `ddev()` function lives in your shell RC files — shell functions exist
only in shells that loaded them. To cover **vendor scripts** like TYPO3's
`vendor/bin/runTests.sh`, the hook exports the function (bash children
import it) and sets `BASH_ENV` pointing at itself (non-interactive bash
startups source that file — it even survives `#!/bin/sh` wrapper scripts).
A user-set `BASH_ENV` is never overridden.

| Who calls `ddev`? | What happens |
|---|---|
| You, in a terminal | The function intercepts the call → runs via the sudoers helper as `opencode` ✔ |
| A bash script started from your terminal | Gets the function via `export -f` / `BASH_ENV` → runs as `opencode` ✔ |
| Outside your shell (dash script, cronjob, IDE task) | **Real ddev binary** as your user — function never applies ✘ |

Ways out for the last row:

1. Force bash for a dash script: `bash vendor/bin/runTests.sh -s phpstan`.
2. Call the helper explicitly:

   ```bash
   sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode start
   ```

### Unreadable working directories

`sudo` keeps your working directory, so ddev inherits whatever directory you
invoked it from — including ones the opencode user cannot read, like your
`$HOME`. The helper probes the inherited directory, prints a one-line note
when it is unreadable, and runs ddev from the opencode home instead:

```text
ddev-as-opencode: current directory is not accessible to the opencode user - continuing in /home/opencode
```

Commands addressing a project by name or walking the registry (`ddev
poweroff`, `ddev stop <project>`, `ddev list`) are unaffected. Commands
without a project name (`ddev start`, `ddev describe`) need the project
directory as their working directory — run them from inside the project or
pass the project name.

## ddev-managed paths (the EPERM fixes)

ddev chmods `.ddev/` and the app-type's **settings directories
unconditionally**, and `chmod` is owner-only on Linux — so these paths must
belong to `opencode:opencode` (with `g+w`). The kit hands them over, at
**any depth** under each registered root:

| App type (`.ddev/config.yaml` `type:`) | Handed-over directories |
|---|---|
| `typo3` | `config/system`, `<docroot>/typo3conf`, bare `typo3conf` (repo-root fallback) |
| `drupal*`, `backdrop` | `<docroot>/sites/default` |
| `magento*`, `maho` | `app/etc` |
| `modx` | `<docroot>/core/config` |

**Root-file types (`codeigniter`, `shopware6`, `symfony`).** Their settings
file lives at the project root (`.env`, `.env.local`) and ddev chmods the
**root directory** on every run. The kit hands the root *inode* to
`opencode` with mode `2755` (ddev's `0755` chmod becomes a no-op); with the
dev-owned flag the root is handed back to you permanently.

**The project root during bootstrap.** A freshly cloned `typo3` project has
no `vendor/` yet — ddev cannot detect the installation, writes its settings
file at the project root and chmods the root directory on every start. The
kit hands the root *directory inode* (never its contents) to `opencode` with
mode `2755`, so `ddev start` and `ddev composer install` work from the first
run. Creating new top-level files is limited while the root is handed over
(editing existing files is not). Once TYPO3 is installed (`vendor/` or
`<docroot>/typo3` present), the kit hands the root **back to you** (`2775`)
on the next install/`projects add`/`refresh`/`update --refresh`.

The handover runs on install, `config.sh projects add`, `config.sh refresh`,
`config.sh handover <path>` (one project, no group baseline — the fast
repair after cloning), and on `update.sh`. The routine update skips the
rescan when nothing changed (a stamp under
`/etc/opencode-permissions-kit/handover/` records the last completed pass
per root); `opk update --refresh` always re-scans.

The `ddev` shell hook covers the gap between cloning and the next handover
run: before `ddev start` / `ddev restart` it detects the cases that would
fail with ddev's cryptic `operation not permitted` — the typo3 bootstrap and
dev-owned settings dirs of `maho`/`modx` and the root-file types — and
prints the ready-made `config handover` command instead. The scan never
descends into `vendor/`, `node_modules/`, `testdata/` or `.git/` trees: a
`.ddev` directory there is a shipped test fixture, not a project. Your
`.git/` stays yours (ownership untouched — see
[the sharing group](sharing-group.md)).

### Team git workflows: group-write on ddev-created content

ddev hardcodes explicit `0755`/`0644` modes for everything it creates —
explicit modes bypass the umask and cap the inherited default ACL down to
`r-x` for the group. Content ddev writes as `opencode` (a `ddev config` in a
freshly cloned project, regenerated webserver configs on `ddev start`)
therefore starts out **without group write**, and `git pull` fails with
*permission denied* the moment a teammate delivers a new or modified file
under `.ddev/`.

The kit heals this at the source: after **every** `ddev` command your `ddev`
shell function re-asserts group-write on the project's `.ddev` through the
sudoers helper — an owner-only chmod as `opencode`, no new privilege. Heavy
generated subtrees (`db_snapshots`, import dumps) are pruned. Trees that
arrived via git never need the heal.

That the heal runs after *every* command (not just the tree-creating
`config`/`get`/`start`/`restart`) is deliberate: ddev re-caps group-write
on **every invocation** — during its startup it walks the project's
`.ddev/commands/` and chmods every command file to `0755`, from any
subcommand (`ddev describe`, `ddev --version` and the describe-polls IDE
integrations run in the background all qualify). A tree healed once does
not stay healed: the next describe re-breaks it seconds later (issue #279).
The kit's own ddev invocations — version probes and the handover/migrate
runners — run ddev outside the project context, so no kit command re-breaks
the project you stand in.

After `ddev config` the same hook also writes the dev-owned flag into the
fresh `.ddev/config.yaml` when dev-owned mode is on — new projects are
dev-owned from birth. When the write fails (a clone whose config arrived
without group write), the hook prints a WARNING naming the retry commands;
the `ddev` command itself still succeeds.

Edge case: content written by the *agent's* ddev session (running as
`opencode` directly) lacks the automatic heal — run any `ddev` command in
the project yourself, use `opk update --refresh`, or fix it directly:

```bash
opk ensure-shared <project>/.ddev
```

`opk status` detects the state per project (a `ddev share … group-write
missing` line) so a failing `git pull` on `.ddev/` content does not stay
unexplained.

### Multiple checkouts of one repo (git worktrees)

`ddev config` writes a `name:` key into `.ddev/config.yaml`. If you commit
it, ddev derives the same project name for **every** checkout of the repo —
starting a second checkout fails with *"a project (web container) in running
state already exists for …"*. Remove the `name:` key from the committed
config and ddev derives the project name from the directory instead: every
checkout becomes its own project with its own containers and database.

## Dev-owned projects (the alternative to handovers)

The handover model exists because ddev chmods settings paths outside
`.ddev/` on every start. **Dev-owned mode removes that cause**: the kit
writes `disable_settings_management: true` into each project's committed
`.ddev/config.yaml` (installer default; `opk config ddev-settings
on|off|status`). ddev then never writes or chmods anything outside `.ddev/`:

| Path | Owner | Mode |
|---|---|---|
| `.ddev/` | `opencode` | 2775 / 664 (ddev's internal churn stays contained) |
| settings dirs, project root, everything else | **you** | 2775 / 664 (group baseline, permanent) |

No handover, no handback, `git checkout` always free, fresh clones work from
the first `ddev start`. The trade-off: **your repo owns the CMS settings
file** (for TYPO3 a small committed `AdditionalConfiguration.php` — see the
[how-to](../how-to/dev-owned-projects.md)). A project carrying the committed
flag is dev-owned regardless of the kit mode.

One handover remains: `.ddev/` itself stays with `opencode` — inside it,
ddev keeps writing and chmod-ing on every run, so handing it to the
developer would break every `ddev start`.

Notes:

- ddev resets a settings directory's mode to `0755` on each start — you keep
  editing the **files** (group-writable); `update.sh`/`refresh` re-applies
  `g+w` to the directory.
- **wordpress** manages `wp-config.php`, a *file* at the project root — keep
  it user-managed (remove the `#ddev-generated` marker) or set
  `disable_settings_management: true`.
- Unknown app types (`php`, `generic`, `joomla`, `laravel`, `silverstripe`,
  `wp-bedrock`, …) manage no settings outside `.ddev/` and are skipped.

## Provisioned by the kit

- `/home/opencode/.ddev` — the opencode user's global ddev home (project
  registry, mutagen binaries, `ddev auth ssh` key cache).
- **Router ports** — rootless containers cannot bind <1024; either the
  sysctl (`ip_unprivileged_port_start=80`, offered at install) or higher
  ports:

  ```bash
  sudo -u opencode ddev config global --router-http-port 8080 --router-https-port 8443
  ```

- **mkcert CA** — reused from the Windows user or the developer's CAROOT so
  browsers keep trusting ddev's HTTPS certs; a new CA is generated only as a
  last resort (created as the `opencode` user — the install prints the
  import command for you to run yourself). A symlink anywhere in the chain
  to the agent's CAROOT is never followed — CA provisioning is skipped with
  a warning until you remove the link. The copy includes the CA **private
  key** (see the [security model](security-model.md#known-residual-gaps)).

## Hostnames and the Windows hosts file

On WSL2, ddev cannot manage the **Windows** hosts file for the kit's ddev
user — `/mnt/c` is restricted to the developer. ddev only **warns** and
`ddev start` succeeds, but your Windows **browser** cannot resolve
custom-`project_tld` domains until the hostnames are in the Windows hosts
file. The kit deliberately gives the agent **no** hosts-file access; the
developer gets a one-command bridge that uses ddev's own elevation path:

```bash
opk ddev-hosts-check   # what is missing?
opk ddev-hosts-add     # add it (Windows asks permission)
```

`ddev-hosts-add` adds every hostname missing from
`C:\Windows\System32\drivers\etc\hosts` — project name + TLD,
`additional_hostnames`, non-wildcard `additional_fqdns`. After
`ddev start`/`restart` the `ddev()` shell function prints the missing
hostnames with one ready-made command each. Hostnames under the default
`*.ddev.site` TLD never need an entry (ddev's public wildcard DNS). Manual
fallback: edit the hosts file in an elevated editor and add
`127.0.0.1 <project>.<tld>` per hostname.

## The SSH-key trade-off

`ddev auth ssh` / composer private keys live in `/home/opencode/.ddev` and
are **agent-readable** — ddev runs as one user, so there is no safer place
the import could put them: once a key is imported, every opencode session
can read it from disk.

The template denies the import command (`ddev auth ssh*`, incl. `sudo`) so
the decision stays with you — run it in your terminal if you accept the
trade-off. A project that broadly allows `ddev *` must re-add the specific
deny **after** its allow (see [allow docker/ddev](../how-to/container-tools.md)).
Prefer dedicated, rotatable deploy keys — and rotate them if the machine is
not trusted.

## First start is slow

The **first** `ddev start` as `opencode` downloads mutagen and pulls images
into the rootless daemon; everything afterwards reuses that state.

## Database migration from your old daemon

Before the kit, ddev ran as **you** against your daemon. At install time the
kit exports every registered project's database while your side still works
(one project at a time), then powers the old daemon off (volumes are kept).
The dumps land in
`/var/backups/opencode-permissions-kit/ddev-migration-<timestamp>/`; the kit
never deletes them. Projects without a database
(`omit_containers: [db]`) are skipped automatically.

The **import is deliberately your call**, not part of the install:

```bash
# all at once:
sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import
# or per project (the ddev() function already runs as opencode):
ddev start <project> && ddev import-db <project> --file=<dump>.sql.gz
```

`opk status` lists dumps still waiting for import. Only each project's
**default** database is exported; extra named databases need a manual
`ddev export-db --database=<name>` on the old side — do that **before** the
`.ddev` handover (see [troubleshooting](../troubleshooting.md)).

A project that no longer **starts** does not block the others: the installer
lists the failed projects and asks whether to continue anyway or abort so
you can fix them first. Re-running the installer after an abort **resumes**
instead of repeating — projects whose dumps already exist are skipped.
