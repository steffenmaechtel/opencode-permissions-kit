# Use dev-owned projects

Switch from the handover model (ddev owns what it chmods) to **dev-owned
projects**: everything outside `.ddev/` stays yours, permanently
group-writable — no ownership juggling, `git checkout` / `mv` / `rm` always
work, even on a fresh clone.

Background: [ddev integration](../concepts/ddev-integration.md)

## What it does

With **ddev-settings on** (the installer's recommended default), the kit
writes one line into each project's `.ddev/config.yaml`:

```yaml
disable_settings_management: true
```

The line is inserted below the head of the file (after `corepack_enable:`,
after `type:` as fallback) so it never disappears below the comment block
ddev's default template carries. Already-flagged configs are left
untouched. Only real projects are flagged: `.ddev` dirs inside `vendor/`,
`node_modules/` and `testdata/` trees are test fixtures and are skipped.

With that flag ddev stops managing CMS settings files completely — it never
writes or chmods anything outside `.ddev/`:

| Path | Owner | Mode |
|---|---|---|
| `.ddev/` | `opencode` | 2775 / 664 (ddev's internal churn stays contained) |
| settings dirs, project root, everything else | **you** | 2775 / 664 (group baseline, permanent) |

The trade-off: **your repo owns the CMS settings file.** ddev no longer
generates `AdditionalConfiguration.php` (TYPO3) or `settings.ddev.php`
(Drupal). For repos that commit their settings anyway — the common TYPO3
setup — nothing changes. `ddev start`, mutagen, router, `ddev composer`,
`ddev import-db` all keep working.

## Enable it

Fresh installs already have it on (recommended default). On an existing
install:

```bash
sudo opk config ddev-settings on
sudo opk config refresh   # flags existing projects + hands back
```

Per project (faster, no full baseline):

```bash
sudo opk config handover /var/www/vhosts/<project>
```

**New projects are flagged the moment they are created:** after
`ddev config`, your `ddev` shell function writes the flag into the fresh
`.ddev/config.yaml`. Projects configured while the mode is off (or by
teammates without the kit) stay unflagged until one of the commands above
runs.

**Commit the added `disable_settings_management: true` line** — it is
regular repo content. Teammates without the kit get it via the repo; their
ddev also stops touching settings (a standard ddev flag, safe to commit).

## The TYPO3 settings file

With settings management off, provide the DB connection yourself. A
commit-safe `config/system/AdditionalConfiguration.php`:

```php
<?php
// Managed by the project, not by ddev (disable_settings_management: true).
// Credentials are ddev's fixed container defaults.
$GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] = array_merge(
    $GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'] ?? [],
    [
        'dbname'   => 'db',
        'host'     => 'db',
        'user'     => 'db',
        'password' => 'db',
        'port'     => '3306',
        'driver'   => 'mysqli',
    ]
);
```

Drupal/Backdrop need a `settings.ddev.php` include chain instead — keep those
projects on the handover model or hand-write the include.

## Disable it

```bash
sudo opk config ddev-settings off
```

Stops future flag writes. Already-committed flags stay (repo content) —
those projects remain dev-owned. To give settings back to ddev in a repo,
remove the `disable_settings_management` key from its `.ddev/config.yaml`,
then run `config refresh`.

## Fresh clones

- Repo **with** the committed flag: clone → `ddev start` — nothing else to
  do.
- External repo **without** it: the `ddev` shell hook detects the case
  before `ddev start` and prints the one-command fix
  (`config handover <path>`), which also writes the flag — run it once,
  commit the line.
