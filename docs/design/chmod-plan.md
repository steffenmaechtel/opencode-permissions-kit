# PLAN-CHMOD: Permanent group-writable projects via disable_settings_management

> Status: **DRAFT — planned, not implemented.** This plan replaces the
> per-path ownership juggling (`.ddev` / settings dirs / typo3 bootstrap
> root handovers) with a static, ddev-conflict-free permission model.
> Evidence: ddev source (github/ddev, v1.25.x) and the productive-WSL
> reports behind the handover fixes (local `Lokaler-Test.txt` and the
> `git checkout` EPERM follow-up).

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
`update` / the new `config handover`), and the typo3 bootstrap root must be
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

**Offer a per-project opt-in "dev-owned project" mode built on ddev's own
`disable_settings_management: true`.** With settings management off,
`CreateSettingsFile` returns **before** the chmod loop
(`pkg/ddevapp/apptypes.go:329`), ddev never touches settings paths or the
bootstrap root, and the kit's static baseline becomes the permanent state:

| Zone | Owner | Mode (permanent) |
|---|---|---|
| `.ddev/` | `opencode` | 2775 / files 664 |
| settings dirs, project root, everything else | **developer** | **2775 / 664** (group baseline) |

Consequences:

- **No settings-dir handover, no bootstrap-root handover, no handback.**
  `git checkout` / `mv` / `rm` always work for the developer.
- The group baseline (chgrp + setgid + g+rw + default ACLs, umask 002)
  remains the only recurring repair — it is idempotent and conflict-free
  (nothing fights it anymore).
- `.ddev/` stays opencode-owned: ddev's internal chmods are git-irrelevant
  (`.ddev` is committed only partially — `config.yaml`, commands — and
  those stay group-writable through the baseline).

The current handover model stays the **default** (zero-setup ddev
experience); dev-owned is the mode for developers who prefer permanent
permissions and are willing to own their settings file.

## 3. What ddev does NOT do anymore in this mode (the trade-off)

`disable_settings_management: true` (per project, `.ddev/config.yaml`;
there is no global switch) disables:

- writing/regenerating `AdditionalConfiguration.php` (TYPO3),
  `settings.ddev.php` (Drupal/Backdrop), `local.conf` (Magento), ...
- the per-start chmod of those paths,
- the typo3 bootstrap fallback that writes settings at the project root.

The developer writes the CMS settings file **once, themselves** (or keeps
a committed one). For TYPO3 (the kit's main audience) that is a small,
commit-safe `config/system/AdditionalConfiguration.php` with ddev's fixed
credentials — the kit ships a documented template (§5).

Things that keep working unchanged: `ddev start`, mutagen sync, router,
`ddev composer`, `ddev import-db`, exec, logs — none of them depend on
settings management.

## 4. Rule of thumb for support/troubleshooting

- ddev writes/chmods it and it is **inside `.ddev/`** → fine, opencode owns it.
- ddev would write/chmod it **outside `.ddev/`** → only with settings
  management enabled → handover model (default mode).
- dev-owned mode: ddev never writes outside `.ddev/` → static baseline.

## 5. Implementation sketch (for the implementing PR)

1. **Detection** — `ddev-handover.sh` grows
   `ddev_settings_management_disabled <project-dir>`:
   `yq`-free parse of `.ddev/config.yaml` for
   `disable_settings_management: true` (sed, like the `type:` parse).
2. **Handover functions gate on it** — `ddev_handover_project` and
   `ddev_handover_project_root` return early (no chown) when disabled;
   `ddev_handover_root` keeps handing over `.ddev/` only. A dev-owned
   project that was previously in handover mode needs a one-time
   **migration back**: new `config.sh handback <path...>` subcommand
   (root inode + settings dirs → developer, 2775; guarded by
   `project_path_sane`; refuses while typo3 is undetected AND settings
   management is still on — that would recreate the EPERM bootstrap).
3. **Installer/`projects add`** — when a project has the flag set, skip
   the settings/root handover from the start (same gate as 2).
4. **Docs** — new how-to `docs/how-to/dev-owned-projects.md`:
   - enable: `disable_settings_management: true` in `.ddev/config.yaml`
     (committed — affects teammates without the kit: safe, it is a
     standard ddev flag),
   - the TYPO3 `AdditionalConfiguration.php` template (db/db/db, host
     `db`, driver from `.ddev/config.yaml` `database:`; marker comment
     `# ddev-managed-by: developer`),
   - when to choose which mode (table §2),
   - migration instructions (flag + `config handback`).
   - update `docs/concepts/ddev-integration.md` (mode table + the
     rule-of-thumb §4) and `docs/troubleshooting.md` (EPERM entries get
     the dev-owned alternative).
5. **Tests** — unit: gate behavior (fixture trees with/without the flag),
   `handback` wiring + guards; e2e (`tests/e2e/run.sh`): plant a
   flagged project, verify `config.sh refresh` leaves settings dirs
   dev-owned, `git checkout` file replacement succeeds, `.ddev` still
   opencode-owned; extend the fake ddev if a start-path assertion needs
   it (the flag itself is ddev-side, the kit only stops chowning).
6. **Explicitly out of scope** — the kit never writes the flag into
   `.ddev/config.yaml` itself (team-shared file, deliberate developer
   decision), and there is no auto-handback of bootstrap roots in the
   default mode (superseded by this plan instead of the previously
   sketched hook-based handback).

## 6. Open questions (to resolve before implementing)

- **Q1:** Should `status.sh` surface the mode per project
  (handover vs dev-owned) in its projects list? (Leaning: yes, one
  line per project — it explains both EPERM symptoms at a glance.)
- **Q2:** Template support beyond TYPO3 first? Drupal's
  `settings.ddev.php` include chain is more intrusive to hand-write;
  start TYPO3-only and document the limitation?
- **Q3:** Does the leak-scan deny list need a dev-owned exception
  (settings file now contains DB creds but is committed anyway)?
- **Q4:** Naming: `dev-owned` vs `static-permissions` vs
  `no-handover` for docs/UI? (Leaning: keep it ddev-adjacent —
  "settings management disabled" — to avoid a third kit-specific term.)
