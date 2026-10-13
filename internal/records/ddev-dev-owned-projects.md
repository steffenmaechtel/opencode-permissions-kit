# PLAN-DDEV-DEV-OWNED-PROJECTS: Permanent group-writable projects via disable_settings_management

> Status: **IMPLEMENTED (all sections).** Installer question + stamp
> (`DDEV_DEV_OWNED`), flag writer + scan branching in ddev-handover.sh,
> `config.sh ddev-settings on|off|status`, status.sh mode line, hook
> note, how-to + concept/troubleshooting/cli docs, unit + e2e coverage
> (`make e2e` green: 224 checks incl. section 4e). Where this plan
> conflicts with the code, the code wins.

## 1. Problem

The current model needs **three ownership handovers** to keep ddev (running
as the `opencode` user) working while the developer stays owner of their
working tree:

| Path | Owner | Why |
|---|---|---|
| `.ddev/` (any depth) | `opencode` | ddev chmods/rewrites inside it on every start (compose regen, `config.yaml` to 0666, `db_snapshots` to 0777, `.webimageBuild`, ...) |
| settings dirs (`config/system`, `typo3conf`, `sites/default`, `app/etc`) | `opencode` | ddev chmods `Dir(SiteSettingsPath)` to 0755 on every start, unconditionally |
| project root (typo3 bootstrap: no `vendor/` yet) | `opencode` | ddev's settings-path fallback writes `AdditionalConfiguration.php` AT the root and chmods the root to 0755 |

Each handover needs a trigger (install / `projects add` / `refresh` /
`update` / `config handover`), and the typo3 bootstrap root must be
handed **back** once `composer install` makes TYPO3 detectable — a moment
the kit cannot observe. Real-world consequences (both reported from a
productive WSL install):

1. **Fresh clone → `ddev start` EPERM** when the clone happened after the
   last handover scan (mitigated by the hook hint + `config handover`).
2. **`git checkout <branch>` EPERM** while the bootstrap root is still
   opencode-owned: replacing a top-level file needs **directory** write
   access, group has `r-x` only. Git leaves the working tree
   half-switched (`error: unable to unlink old 'AGENTS.md'`). The docs
   understated this as "creating new top-level files is limited" — every
   unlink/rename (`git checkout`, `mv`, `rm`, `git stash`) is affected.

Root cause (ddev source, verified):

- `util.Chmod` skips only when `Perm() == mode` **exactly**
  (`pkg/util/utils.go:442`) — no mode is simultaneously group-writable
  and `Perm() == 0755`.
- `CreateSettingsFile` chmods `Dir(SiteSettingsPath)` and the settings
  file on **every** start, for every app type, **before** the
  `#ddev-generated` signature check (`pkg/ddevapp/apptypes.go:341+`) —
  user-managed files are not spared.
- `chmod` is owner-only on Linux; ddev runs as `opencode`; hence every
  ddev-chmod target must be opencode-owned. That is the entire handover
  machinery.

## 2. Decision

**Ship a kit-level "dev-owned projects" mode. While on, the kit itself
writes `disable_settings_management: true` into every discovered
project's `.ddev/config.yaml` and hands settings dirs + typo3 bootstrap
root back to the developer.** With settings management off,
`CreateSettingsFile` returns **before** the chmod loop
(`pkg/ddevapp/apptypes.go:329`), ddev never touches paths outside
`.ddev/`, and the kit's static baseline becomes the permanent state:

| Zone | Owner | Mode (permanent) |
|---|---|---|
| `.ddev/` | `opencode` | 2775 / files 664 |
| settings dirs, project root, everything else | **developer** | **2775 / 664** (group baseline) |

Consequences:

- **No settings-dir handover, no bootstrap-root handover, no handback.**
  `git checkout` / `mv` / `rm` always work for the developer — including
  on a fresh clone, from the very first `ddev start`.
- The flag lives in the **committed** `.ddev/config.yaml`: teammates get
  it via the repo, with or without the kit. Their ddev also stops
  managing settings — for repos that ship their own settings file (the
  maintainer's standard) that is the intended end state, nothing changes
  for them.
- `.ddev/` stays opencode-owned: ddev's internal chmods are git-irrelevant
  (`.ddev` is committed only partially — `config.yaml`, commands — and
  those stay group-writable through the baseline).
- The group baseline (chgrp + setgid + g+rw + default ACLs, umask 002)
  remains the only recurring repair — it is idempotent and conflict-free
  (nothing fights it anymore).

**Separation of policy and behavior (important):**

- The **flag** in `.ddev/config.yaml` is the per-project source of truth:
  flagged projects are dev-owned, unflagged projects get today's
  handover treatment — regardless of the mode.
- The **mode** only decides whether the kit *writes* the flag into
  projects that lack it. Mode off = the kit never edits `.ddev/config.yaml`
  (today's behavior, for public users who want ddev's auto-settings).

Mode default: **on** (installer question, recommended; `--yes` takes the
default). Declining at install — or `config.sh ddev-settings off` later —
keeps the handover model.

## 3. What ddev does NOT do anymore in this mode (the trade-off)

`disable_settings_management: true` (per project, `.ddev/config.yaml`;
there is no global switch) disables:

- writing/regenerating `AdditionalConfiguration.php` (TYPO3),
  `settings.ddev.php` (Drupal/Backdrop), `local.conf` (Magento), ...
- the per-start chmod of those paths,
- the typo3 bootstrap fallback that writes settings at the project root.

The settings file becomes the **repo's responsibility** — committed, owned
by the team, not by ddev. For the maintainer's TYPO3 repos that is already
the norm; the how-to ships a commit-safe template (`config/system/AdditionalConfiguration.php`
with ddev's fixed credentials or, better, env-var driven) for repos that
still rely on ddev's generated file. The kit deliberately does NOT
generate or modify CMS settings files — only the ddev flag.

Things that keep working unchanged: `ddev start`, mutagen sync, router,
`ddev composer`, `ddev import-db`, exec, logs — none of them depend on
settings management.

## 4. Rule of thumb for support/troubleshooting

- ddev writes/chmods it and it is **inside `.ddev/`** → fine, opencode owns it.
- Flagged project (dev-owned): ddev never writes outside `.ddev/` → static
  baseline, no handover questions.
- Unflagged project: ddev chmods outside `.ddev/` → handover model
  (default mode for unflagged projects).

## 5. Implementation sketch (for the implementing PR)

1. **Installer + config.sh**
   - install.sh asks (recommended default yes; `--yes` takes it; a flag
     like `--ddev-settings=auto|ddev` for scripts) and stamps
     `DDEV_DEV_OWNED=true|false` into install.conf.
   - `config.sh ddev-settings on|off|status` toggles; `off` also stops
     future flag writes (committed flags stay — repo content).
   - status.sh reports the mode and, per project, whether it is flagged.
2. **Flag writer** — `ddev-handover.sh` grows
   `ddev_devowned_flag <project-dir>`: adds the top-level key
   `disable_settings_management: true` to `.ddev/config.yaml` **iff**
   the file exists and the key is not already present (grep check, then
   a single insert; no other edit, no backup churn — one line,
   idempotent). Inserted below the head of the file (after
   `corepack_enable:`, `type:` as fallback, top as last resort), not
   appended — ddev's default template would hide an appended flag
   behind its comment block (issue #28). Never runs inside pruned trees
   (vendor/node_modules/testdata `.ddev` fixtures, issues #21/#29).
3. **Scan behavior** — `ddev_handover_root` and its callers
   (install, `projects add`, `refresh`, `update`, `handover`):
   - `.ddev/` handover: unchanged (always opencode).
   - per project: if mode on → `ddev_devowned_flag` first; then, if the
     project is flagged (mode-written or repo-committed), hand settings
     dirs + project root **back** to the developer (2775, g+w) instead of
     handing them over; unflagged projects keep today's handover logic
     verbatim (incl. the typo3 bootstrap root rules).
4. **Fresh clone flow**
   - Repo with the committed flag (their norm): nothing to do — clone is
     dev-owned 2775 from the umask/setgid parent, `ddev start` just works.
   - External repo without the flag: the existing `ddev()` hook bootstrap
     hint fires; with the mode on, the hint's fix (`config handover
     <path>`) also writes the flag — one command, once per repo, then
     commit it.
5. **Docs** — new how-to `docs/how-to/dev-owned-projects.md`: mode
   on/off, what the kit writes into `.ddev/config.yaml` (team-visible!),
   the committed-settings-file pattern for TYPO3 (credentials + env-var
   variant), team implications (colleagues without the kit), migration
   (= enable mode, run `refresh` once, commit). Update
   `docs/concepts/ddev-integration.md` (mode table + §4 rule of thumb)
   and `docs/troubleshooting.md` (EPERM entries get the dev-owned
   alternative).
6. **Tests**
   - Unit: flag writer (inserts iff absent, no-op when present, skips
     missing config.yaml), scan hands back flagged projects / hands over
     unflagged ones, mode off → no writes, config.sh toggle wiring,
     install.sh question + stamp, status reporting.
   - e2e (`tests/e2e/run.sh`): extend section 4 — a mode-on run flags a
     planted project, settings dirs + root stay dev-owned 2775,
     `git checkout` file replacement succeeds, `.ddev` still
     opencode-owned; existing 4c/4d checks keep a mode-off run (or get
     mode-specific expectations).
7. **Explicitly out of scope** — the kit never writes or edits CMS
   settings files (`AdditionalConfiguration.php` etc.); it only manages
   the ddev flag. Auto-handback in the unflagged (handover) model stays
   unsolved by design — that model is superseded by this mode.

## 6. Open questions (to resolve before implementing)

- **Q1 (resolved):** status.sh surfaces the mode + per-project flag state
  — yes, one line per project (explains both EPERM symptoms at a glance).
- **Q2 (resolved):** settings-file template is TYPO3-only for now —
  Drupal's `settings.ddev.php` include chain is more intrusive to
  hand-write; documented as a limitation, extendable later.
- **Q3 (resolved):** leak-scan deny list unchanged — committed settings
  files are the repo's choice, the scan stays name-based either way.
- **Q4 (resolved):** naming: "dev-owned projects" in docs,
  `ddev-settings` as the config.sh action.
