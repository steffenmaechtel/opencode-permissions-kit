# CLI reference

The kit's commands and flags.

## openchamber-secure

Pin OpenChamber to the kit wrapper (sudo — the command elevates itself):

```bash
sudo opk openchamber-secure [--yes]
```

Writes the admin-owned policy `/etc/openchamber/policy.json`
(`opencodeBinary` → `/usr/local/bin/opencode`), which makes OpenChamber's
web UI, desktop app, and VS Code extension spawn the kit wrapper regardless
of their own settings pin — defusing a one-click bypass retroactively.
OpenChamber's self-update affordances stop working; updates go through
`opk upgrade-opencode` exclusively. The command also removes leftover bypass
binaries (`~/.opencode/bin/opencode`, `opencode2`) and the `opencodeBinary`
settings pin (asks first; `--yes` skips the question) and records the opt-in
so `opk update` re-applies the pin. Idempotent. A pre-existing policy file
with other content is announced and replaced by this command; `opk update`
and the install opt-in never overwrite such a file. `opk uninstall` removes
the file only when it still pins the kit wrapper.
Manual steps: [the how-to](../how-to/openchamber.md#prevent-the-bypass-the-policy-pin).

## wsl-add-opencode-1-fix

Write the WSL browser-bridge carrier into `/etc/wsl.conf` (sudo — the
command elevates itself):

```bash
sudo opk wsl-add-opencode-1-fix
```

Keeps opencode device logins (`console login` / `auth login`) alive on a
hardened `/mnt/c`: the carrier redirects the login's powershell.exe lookup
to the kit stand-in (forwards for you, exits 0 for the agent). Takes effect
immediately — no `wsl --shutdown` needed. Relevant for opencode
1.x **< 1.18.33** and 2.x **< 2.0.18**; newer versions fall back to
`xdg-open` on their own (the kit ships a fallback shim for that path).

This is the **only** kit command that writes `/etc/wsl.conf` — install and
update never touch the file. The command is idempotent. `opk uninstall`
asks before removing the block again (`--yes` assumes yes).

## The `opk` command

After installation, one command manages everything (works from anywhere):

```bash
opk status
opk config projects add /var/www/vhosts/new-project
opk doctor            # in a project dir: ownership diagnosis (read-only)
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

Everything after the subcommand goes to the underlying script unchanged, so
all flags below work with both forms. `config`, `update` and `handover`
elevate via sudo automatically; `ensure-shared` hops to the agent user
automatically; `status` and `doctor` need no sudo; `uninstall` runs as your
user and asks for sudo itself; `ddev-hosts-*` run as your user (they drive
Windows-side elevation through ddev itself).

`opk --version` prints the deployed kit version in one line (`opk <x.y.z>`)
— the same value `opk status` reports. Without an install it answers
`opk 0.0.0` instead of failing.

## doctor

Per-project deep diagnosis for the rootless ownership failure class
(read-only, no sudo — run it in the project root):

```bash
opk doctor                       # the current directory
opk doctor /var/www/vhosts/<project>
```

Classifies every entry in the **container trees** the project declares in
its `opk.json` (format below) as **mapped-safe** or **at-risk**: under the
kit's rootless backend a container process can write file *contents*
through the sharing group, but setting *metadata* — timestamps
(`futime`/`utimensat`), `chmod`, `chown` — only works for owners mapped
into the daemon's user namespace, and your own uid is not. At-risk files
are exactly where container builds die with
`EPERM: operation not permitted, futime` after writing the output
correctly (the "container build fails with EPERM ... futime" entry in
[Troubleshooting](../troubleshooting.md)). Every finding carries its
fix command (`sudo opk handover opencode <tree>`); doctor itself never
changes anything.

The mapped-uid set is resolved from the **live user namespaces**: every
process carries its `uid_map` in `/proc`, world-readable, so no docker
socket access is involved. `/etc/subuid` is deliberately not consulted —
it can be empty even when the mapping demonstrably exists. When no user
namespace of the daemon user is found (backend down), doctor falls back
to matching the daemon uid only and says so in a warning — re-run it
with the containers up before trusting a clean verdict.

Exit codes like `opk status`: `0` all declared trees healthy, `1`
at-risk finding(s) or a rejected `opk.json`, `2` warning(s) only, `64`
usage error.

### opk.json — the project's container-tree policy

```json
{
    "version": 1,
    "containerTrees": [
        {
            "path": "packages/ext/<ext>/Resources/Public",
            "note": "frontend build tree — inputs and outputs share one owner"
        }
    ]
}
```

- **Committed to the project's git**: every developer with the kit gets
  the policy on clone — nothing is configured per machine. Dev-only like
  `.ddev/`: add it to your deployment excludes.
- **Strict JSON** (no comments — documentation lives in `note` fields),
  pretty-printed with one entry per line so diffs stay readable, and
  readable by `jq` and other tooling.
- `version` is reserved for future format migrations (only `1` exists);
  unknown keys are ignored.
- Each entry declares a tree the container **writes** (build outputs,
  the `node_modules` it installs into), not one it only reads —
  ownership follows the writer. Declare the smallest tree that contains
  both the build's inputs and its outputs, otherwise outputs drift to
  odd subuid owners (the troubleshooting entry above explains why).
- Paths are relative to the project root: no absolute paths, no `..`,
  no globs, and no shell-significant characters (`'` `"` `` ` `` `$` `;`)
  — the fix hints interpolate paths into copy-paste commands, so the
  policy gate keeps them out entirely. A bare string entry
  (`"some/path"`) works too when a tree needs no note.

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

`me` and `opencode` resolve to your default user and the agent user from the
kit's install configuration — no usernames to remember, no root shell.

The change is recursive and only flips the **owner** — the group stays the
kit's sharing group and group-write access is re-applied, so both sides keep
their group access to the tree (the same semantics as the ddev handovers,
see [ddev integration](../concepts/ddev-integration.md)). The command
elevates via sudo itself; `--dry-run` validates and prints the plan without
sudo.

Guardrails: system roots and their subpaths (`/etc`, `/usr/local/...`) and
whole home directories are refused — hand over project trees, not systems
(`/tmp` subpaths are allowed). Symlinked paths and operands carrying `/`,
`.` or `..` components are refused too: the kit never hands a tree over
through a link (`--dry-run` lists the refusals it would make). The
chown/chmod passes are ordered per direction so a planted link cannot steer
them; pre-arranged group/world-writable paths survive the passes in either
order.

Direction — **ownership follows the writer**: `handover me` is for trees
*you* write (source code you take back, your checkouts);
`handover opencode` is for trees *container processes or the agent* write
into — ddev caches, build output trees, generated assets. The group never
changes, so either direction keeps full data-write access on both sides;
only metadata rights (explicit timestamps, `chmod`, `chown`) move with the
owner — hand a source tree over and it is *your* `chmod` and exec-bit
`git checkout` on it that fail next. Under the
rootless container backend that direction matters for
builds: container tooling that restores file metadata (gulp/vinyl-fs
`dest`, `rsync -t`, `cp -p`, `tar -xpf`) needs the owner to be the agent
user and aborts with `EPERM: ... futime`/`chmod` on developer-owned
outputs — after the data write already went through. If a container build
fails that way, hand its tree over:

```bash
opk handover opencode /var/www/vhosts/some-project/packages/ext/<ext>/Resources/Public
```

Careful with `opk handover me <whole project>` on projects with
container-written output trees: it re-owns those outputs to you, and the
next container build that restores their metadata fails with EPERM again —
expect a clean rebuild of container-written outputs afterwards. The
sibling command `opk config handover <project-root>` covers ddev's own
settings directories (a different writer); both failure modes live in
[troubleshooting](../troubleshooting.md).

## ensure-shared

Re-assert group-write on a `.ddev` tree a ddev run left without it (every
ddev invocation re-caps the modes, and agent sessions run without the
healing hook) — the short form of the fix `opk status` prints for its
`ddev share … group-write missing` line:

```bash
opk ensure-shared                     # heals ./.ddev
opk ensure-shared /var/www/vhosts/some-project/.ddev
```

Runs the kit's heal helper as the agent user (passwordless through the
kit's sudoers grant). The heal is an **owner-only chmod**: it widens the
mode of agent-owned entries to `g+w` and never touches ownership —
dev-owned entries without group-write are deliberately left alone
(`opk config handover <project-root>` re-runs the full handover if a tree
needs more). Heavy generated subtrees (`db_snapshots`, import dumps) are
pruned. Idempotent and best-effort. Background:
[ddev integration](../concepts/ddev-integration.md#team-git-workflows-group-write-on-ddev-created-content).

## ddev-hosts-add / ddev-hosts-check

Windows hosts bridge (WSL2): ddev runs as `opencode` and cannot manage the
Windows hosts file — your Windows browser cannot resolve custom-
`project_tld` domains. These commands stay on the developer side; the agent
never gets hosts-file access.

```bash
opk ddev-hosts-check   # what is missing?
opk ddev-hosts-add     # add it (Windows asks permission)
```

`ddev-hosts-add` runs `ddev hostname <name> 127.0.0.1` as your user for
every hostname missing from `C:\Windows\System32\drivers\etc\hosts` (project
name + TLD, `additional_hostnames`, non-wildcard `additional_fqdns`); ddev
elevates via `ddev-hostname.exe` and Windows shows its confirmation dialog
(needs working WSL interop). Both take an optional project directory
argument (default: the current directory); a hostname argument works from
anywhere:

```bash
opk ddev-hosts-add my-fancy-project.local
```

Hostnames under the default `*.ddev.site` TLD are never reported or added —
ddev's public wildcard DNS already resolves them. The status scan skips
`vendor/`, `node_modules/`, and `testdata/`: composer/npm packages ship
their own `.ddev` dirs which are not your projects.

## install.sh

Installs the kit. Stream it from GitHub or run it from a checkout; when
streamed, it self-fetches its sibling files from the same ref. The docs
one-liner uses the GitHub Pages entry:

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
  [support matrix](../getting-started.md#supported-distros).
- `--migrate-agents` moves `~/.agents` **whole** (opencode's own
  namespace) plus `~/.claude/skills` **skills/ only** — credentials like
  `~/.claude/.credentials.json` stay in your home. Values: `move`
  (recommended), `copy`, or `skip`; default: ask (`--yes` = move).

Environment: `KIT_BRANCH` (default `master`) selects the ref to fetch
siblings from — any branch or version tag works (`stable` release mirror,
`master` dev channel, `feature/...`, `0.0.29`; see
[update channels](../how-to/update.md#channels)). The value is stamped as
`KIT_CHANNEL` in `install.conf`, which later `opk update` runs follow. Refs
are limited to `A-Z a-z 0-9 . _ / -` — anything else is refused before
anything runs.

## config.sh

Change settings on an installed kit.

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/config.sh <command>
```

Flags: `--yes` (alias `-y`) assumes yes where config.sh would ask.

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

Command notes: `container-backend` — see
[switch the backend](../how-to/switch-container-backend.md); `handover` is
the fresh-clone EPERM repair — see
[ddev integration](../concepts/ddev-integration.md); `ddev-settings` — see
[dev-owned projects](../how-to/dev-owned-projects.md).

## update.sh

Re-deploy the kit after an update; upgrades the opencode binary.

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh | sudo env KIT_BRANCH=stable bash
```

Without `KIT_BRANCH` set, the deployed `update.sh` follows the channel
stamped in `install.conf`. Switch channels without editing it:

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
| `--version <ver>` | Upgrade to exactly this opencode version |

Upgrades never cross majors silently: without `--major` / `--version` the
latest release **of the installed major** is used (1.x resolves through
GitHub releases, 2.x through npm). `opk upgrade-opencode` is the shorthand
for `update --yes --only-binary` — extra flags pass through:

```bash
sudo opk upgrade-opencode                 # latest of the current major
sudo opk upgrade-opencode --major 2       # switch 1.x -> 2.x (latest 2.x)
sudo opk upgrade-opencode --major 1       # switch back to latest 1.x
sudo opk upgrade-opencode --version 2.0.11
```

Never touches `projects.conf` or the agent's `opencode.jsonc`. See
[update](../how-to/update.md).

## status.sh

Show the protection status: mode, backend + socket reachability, project
roots, ddev runtime readiness, migration state, the security-advisory check,
the WSL2 `/mnt/c` exposure (including the browser-bridge state), the
root-equivalent-access audit, and the leak scan — followed by management
hints and the one-line verdict (the **Summary** row: *All green* or the
alert/warning tally).

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/status.sh
```

| Flag | Meaning |
|---|---|
| `--short`, `-s` | Print only the verdict line; the exit code carries the verdict |

Exit codes: `0` all green, `1` alert(s), `2` warning(s) only, `64` for a
usage error — the full report uses the same codes, so scripts can judge an
installed-but-degraded kit (pre-install exception: full mode exits 0,
`--short` exits 1 — use `--short` when absence must fail). Rows the caller cannot judge at their own
privilege ("unknown — needs root to check") and optional-feature rows never
count toward the verdict: `sudo opk status` resolves the privilege
unknowns. Two exceptions always count: a managed binary that is missing,
unexecutable or corrupt (no privilege can fix that), and a missing kit
library file from the checked helper families (a damaged deploy — the row
names the missing kit file and
the repair hint `fix: sudo opk update`; the advisories row names the
skipped security checks instead).

On a terminal, the two project-root scans (the ddev-share group-write check
and the Windows-hosts check) show a live progress line while they walk your
project roots. The line is transient: it never appears in piped output, log
files, cron mail or `--short` mode. The scans run identically without
`python3` (losing only the progress display); a broken `python3` names
itself at each python-backed step — a missing one stays silent.

`--short` is cron/timer friendly — alert yourself only when something is
off:

```bash
# daily check: one line when green, the verdict line + non-zero when not
opk status --short || echo "opk: protection degraded — run 'opk status'"
```

Runs from a checkout too
(`sudo bash files/opencode-permissions-kit-lib/management/status.sh`) and
works **before** an install or after an uninstall — it reports "NOT active"
when the kit is not installed. Use it to check whether hardening is active
from any machine.

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
