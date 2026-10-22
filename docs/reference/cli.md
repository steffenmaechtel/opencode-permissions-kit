# CLI reference

This page lists the kit's commands and flags.

## openchamber-secure

Pin OpenChamber to the kit wrapper (sudo — the command elevates itself):

```bash
sudo opk openchamber-secure [--yes]
```

Writes the admin-owned policy `/etc/openchamber/policy.json`
(`opencodeBinary` → `/usr/local/bin/opencode`), which makes OpenChamber's
web UI, desktop app, and VS Code extension spawn the kit wrapper
regardless of their own settings pin — defusing a one-click bypass
retroactively. OpenChamber's self-update affordances stop working;
updates go through `opk upgrade-opencode` exclusively. The command also
removes leftover bypass binaries (`~/.opencode/bin/opencode`,
`opencode2`) and the `opencodeBinary` settings pin (asks first; `--yes`
skips the question) and records the opt-in so `opk update` re-applies
the pin. Idempotent. A pre-existing policy file with other content is
announced and replaced by this command; `opk update` and the install opt-in
never overwrite such a file — they skip it with a warning (admin-owned
content). `opk uninstall` removes the file only when it still pins the kit
wrapper (marker-gated).
Background and manual steps:
[the how-to](../how-to/openchamber.md#prevent-the-bypass-the-policy-pin).

## wsl-add-opencode-1-fix

Write the WSL browser-bridge carrier into `/etc/wsl.conf` (sudo — the
command elevates itself):

```bash
sudo opk wsl-add-opencode-1-fix
```

Keeps opencode device logins (`console login` / `auth login`) alive on a
hardened `/mnt/c` for versions bundling `open` 10.x — 1.x **< 1.18.33**
and 2.x **< 2.0.18**: the carrier is a comment block at the top of your
`wsl.conf` whose `root =` line wins the bundled `open` package's scan,
redirecting its powershell.exe lookup to the kit stand-in (forwards for
you, exits 0 for the agent). Takes effect immediately — no
`wsl --shutdown` needed, WSL only ever sees comments. Newer versions
access-check powershell and fall back to xdg-open (the kit ships an
xdg-open fallback shim for that path), so device logins survive without
the bridge — the kit does not warn for those versions.

This is the **only** kit command that writes `/etc/wsl.conf` — install
and update never touch the file; they only deploy the stand-in tree and
tell you about this command ([why](../../internal/records/wsl-conf-consent.md)). The
command is idempotent and also cleans up the broken kit-0.0.36 section if
one is present. `opk uninstall` asks before removing the block again
(`--yes` assumes yes).

## The `opk` command

After installation, one command manages everything (works from anywhere in
your WSL/Linux system):

```bash
opk status
opk config projects add /var/www/vhosts/new-project
opk update --binary
opk upgrade-opencode   # just the opencode binary
opk ddev-hosts-add     # in a ddev project dir
opk handover me .gotmp # mixed-owner tree -> yours again
opk ensure-shared      # re-assert group-write on ./.ddev (ddev share fix)
opk openchamber-secure # pin OpenChamber to the kit wrapper
opk wsl-add-opencode-1-fix   # opt in to the WSL browser-bridge carrier
opk uninstall
opk help        # commands + arguments overview
opk --version   # the deployed kit version
```

Everything after the subcommand goes to the underlying script unchanged,
so all flags below work with both forms. `config`, `update` and `handover`
elevate via sudo automatically; `ensure-shared` hops to the agent user
(`sudo -u opencode`) automatically; `status` needs no sudo; `uninstall` runs as
your user and asks for sudo itself; `ddev-hosts-*` run as your user (they
drive Windows-side elevation through ddev itself).

`opk --version` prints the deployed kit version in one line (`opk <x.y.z>`)
— the `VERSION` stamp from `install.conf`, the same value `opk status`
reports. Without an install (no `install.conf`) it answers `opk 0.0.0`
instead of failing.

The command is a symlink (`/usr/local/bin/opk`) into
the kit library — deployed since kit 0.0.14 as `opencode-permissions-kit`
and renamed to `opk` (issue #48). On older installs, run
[update](../how-to/update.md) once to switch to the new name — it creates
`opk` and removes the old long-name symlink. The direct script calls below
keep working everywhere.

## handover

Switch file ownership between the two kit users — you and the agent:

```bash
# You and the agent both ran builds in the same checkout; ddev's .gotmp
# cache now contains files of both users and every build complains
# ("chmod ... Operation not permitted"). Make the whole tree yours again:
cd /var/www/vhosts/ddev
opk handover me .gotmp

# Same idea the other way — give a folder to the agent user:
opk handover opencode /var/www/vhosts/some-project

# Not sure yet? Show what would happen, without sudo:
opk handover me .gotmp --dry-run
```

`me` and `opencode` resolve to your default user and the agent user from
the kit's install configuration — no usernames to remember, no root shell.
Plain `chown -R` would need both.

System roots and their subpaths (`/etc`, `/etc/apache2`, `/usr/local/...`)
and whole home directories are refused — hand over project trees, not
systems. `/tmp` subpaths are allowed (temp build trees are legitimate
handover targets). Symlinked paths are refused too: the kit never hands a
tree over through a link (`--dry-run` lists the refusals it would make).
Operands must be slash-, dot- and dotdot-free — `x/`, `x//`, `x/.`,
`x/./y`, `x/..` and mid-path `a/../b` are refused with a usage error: a
trailing slash, a `.` or a `..` component resolves through a link before
the symlink gate can see it, so both the gate and the recursive pair
would act on the resolved target (the link itself, or its parent). The
recursive pair cannot be steered through a planted link either, and its
order follows the direction: handing over **to the agent** runs the
group-write pass first, while every entry is still yours (the agent
cannot swap what it cannot write), and the ownership change rides
`chown -R -h` last (lchown on a planted operand re-owns the attacker's
own link, nothing outside). Handing over **back to you** (`me`) reverses
the order — `chown -R -h` runs first, so by the time group write is
granted no entry is agent-owned anymore and the chmod pass races no one
on trees the agent owned without group write. Trees that already carry
mode-based write paths the agent pre-arranged — group write from earlier
handovers, or world-writable entries the agent created while it owned the
tree — stay agent-writable during the run in either order; no ordering
closes that (an inherent, accepted residual).

The change is recursive and only flips the **owner** — the group stays the
kit's sharing group and group-write access is re-applied, so both sides
keep their group access to the tree (the same semantics as the ddev
handovers, see [ddev integration](../concepts/ddev-integration.md)).
System roots (`/`, `/usr`, `/var`, ...) and whole home directories are
refused — hand over trees, not systems. The command elevates via sudo
itself; `--dry-run` validates and prints the plan without sudo.

## ensure-shared

Re-assert group-write on a `.ddev` tree an agent-side ddev run left
without it — the short form of the fix `opk status` prints for its
`ddev share … group-write missing` line (issue #159):

```bash
opk ensure-shared                     # heals ./.ddev
opk ensure-shared /var/www/vhosts/some-project/.ddev
```

Runs the kit's heal helper as the agent user (`sudo -u opencode`,
passwordless through the kit's sudoers grant). The heal is an
**owner-only chmod**: it widens the mode of agent-owned entries to `g+w`
(what ddev's hardcoded `0755`/`0644` modes cap away) and never touches
ownership — dev-owned entries without group-write are your umask's
business and are deliberately left alone (`opk config handover
<project-root>` re-runs the full handover if a tree needs more).
Heavy generated subtrees (`db_snapshots`, import dumps) are pruned.
Idempotent and best-effort. Background:
[ddev integration](../concepts/ddev-integration.md#team-git-workflows-group-write-on-ddev-created-content-issue-94).

## ddev-hosts-add / ddev-hosts-check

Windows hosts bridge (WSL2): ddev runs as `opencode` and cannot manage
the Windows hosts file — your Windows browser cannot resolve custom-
`project_tld` domains. These commands stay on the developer side; the
agent never gets hosts-file access.

```bash
opk ddev-hosts-check   # what is missing?
opk ddev-hosts-add     # add it (Windows asks permission)
```

`ddev-hosts-add` runs `ddev hostname <name> 127.0.0.1` as your user for
every hostname missing from `C:\Windows\System32\drivers\etc\hosts`
(project name + TLD, `additional_hostnames`, non-wildcard
`additional_fqdns`); ddev elevates via `ddev-hostname.exe` and Windows
shows its confirmation dialog (needs working WSL interop). Both take an
optional project directory argument (default: the current directory).

Hostnames under the default `*.ddev.site` TLD are never reported or
added — ddev's public wildcard DNS already resolves them, no hosts
entry is needed (the per-hostname commands the status and the `ddev()`
hook print include the name, so you add exactly what was reported:

```bash
opk ddev-hosts-add my-fancy-project.local
```

works from anywhere). The status scan also skips `vendor/`,
`node_modules/`, and `testdata/`: composer/npm packages ship their own
`.ddev` dirs (package development checkouts) which are not your projects.

## install.sh

Installs the kit. Stream it from GitHub or run it from a checkout; when
streamed, it self-fetches its sibling files from the same ref. The docs
one-liner uses the GitHub Pages entry (a copy of the `stable` channel,
served at `steffenmaechtel.github.io/opencode-permissions-kit/`):

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh | sudo env KIT_BRANCH=stable bash
```

| Flag | Meaning |
|---|---|
| `--yes`, `-y` | Skip all prompts, assume Yes (Standard mode with defaults) |
| `--projects <path...>` | Pre-define project roots, skip interactive selection |
| `--container-backend <docker-rootless\|podman-rootless>` | Non-interactive backend choice |
| `--skip-ddev-migration` | Do not export the dev user's ddev databases (no `Step 4b` dumps) |
| `--openchamber-policy <yes\|no>` | Pre-decide the OpenChamber policy pin (non-interactive installs) |
| `--ddev-settings <dev-owned\|ddev>` | Pre-decide the settings mode: `dev-owned` (recommended) or `ddev` |
| `--secure-git-config` | Enable `.git/config` hardening up front |
| `--force-unsupported-distro` | Skip the Ubuntu version whitelist, install anyway — at your own risk |
| `--migrate-agents <move\|copy\|skip>` | Bring the developer's agent resources into `/home/opencode` |

Flags may appear in any order; unknown options abort the install.
`--projects` consumes every following non-flag argument.

Flag notes:

- `--ddev-settings dev-owned` writes
  `disable_settings_management: true`; `ddev` keeps ddev managing
  settings.
- `--force-unsupported-distro`: the whitelist covers Ubuntu 22.04/24.04;
  Debian and other distros are never version-gated — see the
  [support matrix](../getting-started.md#supported-distros). Ubuntu 26.04
  has known errors
  ([issue #145](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/145)).
- `--migrate-agents` moves `~/.agents` **whole** (opencode's own
  namespace) plus `~/.claude/skills` **skills/ only** — credentials like
  `~/.claude/.credentials.json` stay in your home. Values: `move`
  (recommended), `copy`, or `skip`; default: ask (`--yes` = move).

Environment: `KIT_BRANCH` (default `master`) selects the ref to fetch
siblings from — any branch or version tag works (`stable` release mirror,
`master` dev channel, `feature/...`, `0.0.29`; see
[update channels](../how-to/update.md#channels)). The value is stamped as
`KIT_CHANNEL` in `install.conf`, which later `opk update` runs follow.
Refs are limited to `A-Z a-z 0-9 . _ / -` (a git-ref charset) — anything
else is refused before anything runs.

## config.sh

Change settings on an installed kit.

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/config.sh <command>
```

Flags: `--yes` (alias `-y`) assumes yes where config.sh would ask;
the update/uninstall family documents the same shape.

| Command | Meaning |
|---|---|
| `status` | Quick overview: git-config state + configured project roots |
| `projects list` | Show configured project roots |
| `projects add <path...>` | Register roots + apply group baseline + ddev handover |
| `projects remove <path...>` | Remove the `projects.conf` lines (files untouched) |
| `git-config on\|off\|status` | Manage the `.git/config` deny ([hardening how-to](../how-to/secure-git-config.md)) |
| `container-backend docker-rootless\|podman-rootless` | Switch the rootless backend |
| `container-backend status` | Show the configured backend + socket state |
| `refresh` | Re-apply the group baseline (chgrp/setgid/default ACLs) |
| `handover <path...>` | Re-run the ddev handover for one project |
| `ddev-settings on\|off\|status` | Dev-owned projects: kit writes `disable_settings_management: true` |

Command notes:

- `container-backend`: see
  [switch the backend](../how-to/switch-container-backend.md).
- `handover` is the fresh-clone EPERM repair — see
  [ddev integration](../concepts/ddev-integration.md).
- `ddev-settings` details:
  [dev-owned projects](../how-to/dev-owned-projects.md).

## update.sh

Re-deploy the kit after an update; upgrades the opencode binary.

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh | sudo env KIT_BRANCH=stable bash
```

Without `KIT_BRANCH` set, the deployed `update.sh` follows the channel
stamped in `install.conf` (`KIT_CHANNEL`, shown by `opk status`). Switch
channels without editing `install.conf`:

```bash
sudo opk update --channel stable   # or master, a feature branch, or a tag
```

| Flag | Meaning |
|---|---|
| `--yes`, `-y` | Skip the confirmation prompt |
| `--refresh` | Also re-apply the group baseline |
| `--binary` | Also upgrade the opencode binary to the latest release **of the current major** |
| `--only-binary` | Skip every kit step, only upgrade the opencode binary |
| `--binary-path <file>` | Install a specific binary file instead |
| `--channel <ref>` | Switch the tracking ref for this and every future update (re-stamps `KIT_CHANNEL`) |
| `--major 1\|2` | Switch the opencode major (TUI registration flips with it) |
| `--version <ver>` | Upgrade to exactly this opencode version (channel by prefix: `2.*` from npm, `1.x` from GitHub) |

Upgrades never cross majors silently (issue #99): without `--major` /
`--version` the latest release **of the installed major** is used — 1.x
resolves through GitHub releases, 2.x through the npm dist-tag `latest`
(the channel the official v2 installer uses). `opk upgrade-opencode` is
the shorthand for `update --yes --only-binary` — extra flags (e.g.
`--binary-path`, `--major 2`, `--version 2.0.11`) pass through:

```bash
sudo opk upgrade-opencode                 # latest of the current major
sudo opk upgrade-opencode --major 2       # switch 1.x -> 2.x (latest 2.x)
sudo opk upgrade-opencode --major 1       # switch back to latest 1.x
sudo opk upgrade-opencode --version 2.0.11
```

Never touches `projects.conf` or the agent's `opencode.jsonc`. See
[update](../how-to/update.md).

## status.sh

Show the protection status: mode, backend + socket reachability, the
host git against the tested floor, project roots, ddev runtime readiness
(`~opencode/.ddev`, router ports, mkcert CA), migration state, the
security-advisory check (see
[security advisories](../how-to/update.md#security-advisories)), the WSL2
`/mnt/c` exposure (including the browser-bridge state), the
root-equivalent-access audit, and the leak scan — followed by management
hints (`opk update`, `opk config`, ...) and, as the very last line, the
one-line verdict (the **Summary** row: *All green* or the alert/warning
tally).

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/status.sh
```

| Flag | Meaning |
|---|---|
| `--short`, `-s` | Print only the verdict line; the exit code carries the verdict |

Exit codes: `0` all green, `1` alert(s), `2` warning(s) only, `64` usage
error. The full report uses the same exit codes (an installed-but-degraded kit
is visible to callers, not just to readers). The one exception: without
an install the full report stays `0` — status is a diagnostic and does
not "fail" for reporting absence — while `--short` reports that state as
`1`. Rows the caller cannot judge at their own privilege ("unknown —
needs root to check") and optional-feature rows (the mkcert CA) are
informational: they never count toward the verdict — `sudo opk status`
resolves the privilege unknowns. The opencode version is the deliberate
exception: it resolves at the caller's own privilege whenever the caller
can execute the managed binary (root and the sharing group, the agent
user included) — the report runs `--version` directly and the
security-advisory check answers on it, so a group member without sudo
rights gets the real verdict, and an affected version counts as an
alert at any privilege. A caller outside that audience keeps the
informational unknown with the sudo advice (privilege does resolve it),
and a `--version` output without a parsable version is informational
too (sudo would exec the same binary to the same answer).
A missing managed binary, a binary no mode bit lets anyone execute, or
a corrupt one is the exception: each is reported as a warning, because
no privilege can resolve it (a corrupt binary — present and executable
by mode bits, but failing to run, e.g. after an interrupted deploy — is
detected by exec'ing it directly at the caller's own privilege: the
kernel's verdict on a truncated or wrong-arch binary is the same for
every user). A binary that is executable by its audience (whoever
the mode bits grant x — for the deployed 750: root and the opencode
group) but not by the current caller is not a warning: the
"executable" verdict is read from the mode bits, not the caller's own
access, so it renders the same informational unknown — privilege does
resolve it (`sudo opk status` executes it). A missing
kit library file is the same exception: when a report section sources
its library from the deployed `sh/` tree — the advisories database,
the ddev terminal hook, the migration-gap detector, the Windows-hosts
check, the ddev-share resharde scan, the host git floor — and that
file is missing (a damaged or partially deployed tree), the check
family renders a warning row carrying the repair hint
(`fix: sudo opk update`; the row names the missing kit file — the
advisories row names the skipped security checks instead) and counts
toward the verdict instead of silently vanishing while it reads
"All green". The row appears where the family's own preconditions
hold — a stamped developer for the hook and migration rows, a
non-agent caller for the resharde scan, a WSL-ready host for the
hosts row (the checks themselves are gated the same way; an agent-uid
run or an unstamped install stays row-free for those families). The
deliberately optional pieces are exempt: the browser-bridge probe
degrades its own verdict to red on its own, and the audit-log line
stays best-effort.

`--short` is cron/timer friendly — alert yourself only when something is
off:

```bash
# daily check: one line when green, the verdict line + non-zero when not
opk status --short || echo "opk: protection degraded — run 'opk status'"
```

Runs from a checkout too (`sudo bash files/opencode-permissions-kit-lib/management/status.sh`) and works **before**
an install or after an uninstall — it reports "NOT active" when the kit is
not installed. Use it to check whether hardening is active from any machine.

## uninstall.sh

Remove everything the kit installed (see [uninstall](../how-to/uninstall.md)).

```bash
bash /usr/local/lib/opencode-permissions-kit/management/uninstall.sh
```

| Flag | Meaning |
|---|---|
| `--yes`, `-y` | Skip all prompts |
| `--dry-run` | Show what would be removed, change nothing |
| `--debug` | Trace execution (`set -x`) |
