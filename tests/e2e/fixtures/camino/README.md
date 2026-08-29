# Fixture: camino — real TYPO3 v14 site with the Camino theme

The real-site payload for the e2e-ddev suite (`docs/design/ddev-e2e-test.md`
§7.1, DD10/DD11) and the bare-origin generator (§7.2, DD12). Harvested
2026-08-22 from the manual burn-in install (`local/TEST-PROJECT-INSTALL.txt`).

## Layout

| Path | Content |
|---|---|
| `site/` | pristine fixture master — the tracked file set of the burn-in project (what a fresh clone contains) |
| `db.sql.gz` | DB dump of the installed site (`ddev export-db`), 85 KB — demo data only |
| `../make-bare-origin.sh` | builds the per-run bare git origin (main + 3 feature branches) from `site/` |

## Versions (pinned)

- TYPO3 `typo3/cms-base-distribution` **v14.3.0** (lock resolves CMS to v14.3.6)
- Theme `typo3/theme-camino` **v14.3.6**
- PHP 8.3, apache-fpm, docroot `public`, `project_tld local`, MariaDB 11.8
- ddev config carries `disable_settings_management: true` (dev-owned mode)

## Deliberate deviations from the burn-in repo

Three edits vs. the committed state of the burn-in project, made so the
master works as a cloneable fixture:

1. `.ddev/config.yaml`: the fixed `name: perm-kit-typo3-example` line is
   removed — ddev then derives the project name from the clone directory
   (e.g. `camino-e2e` → `camino-e2e.local`).
2. `public/index.php` is included although the TYPO3 `.gitignore` excludes
   `/public/*` — the fixture `.gitignore` adds a `!/public/index.php`
   exception, because without it a fresh clone cannot boot (the burn-in repo
   relied on `create-project` having run in-place first).
3. `backup.sql.gz` is renamed to the sidecar `db.sql.gz` and is NOT tracked
   inside the git origin — it is fixture payload, not project content.

Everything else is byte-identical to the burn-in commits, including
`config/system/settings.php` (`trustedHostsPattern: '.*'`, ddev-standard
db/db credentials) and the site config with its relative `base: /camino/`
(works under any hostname — the frontend marker route is **`/camino/`**).

## Demo credentials (throwaway, nothing real)

- TYPO3 backend user `admin` (system maintainer), password from the burn-in
  log — irrelevant for e2e (no backend login asserted).
- `settings.php` carries the demo install's `encryptionKey` and install-tool
  hash. Regenerate on `ddev typo3 setup` if that ever matters; this fixture
  is for file/ownership/boot assertions, not for holding secrets.

## Regenerating

```bash
# fresh empty dir, then (dev terminal, kit installed):
ddev config --php-version 8.3 --project-type=typo3 --docroot=public \
  --webserver-type=apache-fpm --project-tld local \
  --web-environment-add="TYPO3_CONTEXT=Development/ddev" --nodejs-version=14.18.1
sudo opk config handover "$PWD"
ddev start
ddev composer create-project "typo3/cms-base-distribution:^14"
ddev composer req typo3/theme-camino
ddev composer install          # retry on GitHub CDN 504s (burn-in finding)
ddev typo3 setup --server-type=other --driver=mysqli --host=db --port=3306 \
  --dbname=db --username=db --password=db --create-site <name>.local
# manual steps (see TEST-PROJECT-INSTALL.txt): trustedHostsPattern '.*' in
# config/system/settings.php; copy root-htaccess template to public/.htaccess
ddev launch /camino/           # verify frontend renders
ddev export-db -f=db.sql.gz
```

Then re-apply the three deviations above and refresh `site/`. Bump
`kit.e2e.format` in the e2e-ddev runner so cached golden images rebuild.
