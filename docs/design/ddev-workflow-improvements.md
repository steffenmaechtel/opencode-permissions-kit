# DDEV-WORKFLOW-IMPROVEMENTS: the issue #149 workflow replay — findings and resolutions

> Status: **IMPLEMENTED (findings 1, 2, 4, 5 on `feature/issue-149-ddev-workflow`; finding 3 subsumed by finding 1).** This record documents the workflow audit behind the changes and keeps the evidence for future reviews. Where this record conflicts with the code, the code wins.

## 1. Context and method

Workflow replay for [issue #149](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/149)
(kit `0.0.46`, ddev `1.25.4`, docker-rootless, dev-owned mode ON,
`DEFAULT_USER` acting as developer, the agent session acting as
`opencode`):

1. new project via `ddev config` + `git` (developer and agent side),
2. checkout of an existing repo (a) without and (b) with the committed
   `disable_settings_management: true` flag,
3. one project per ddev app type on an empty dir (22 agent-side runs;
   `drupal6`–`drupal12` share the `drupal` handler) to inventory which
   types ddev actually writes or chmods outside `.ddev/`.

Key ddev source fact (v1.25.x, `pkg/ddevapp/apptypes.go`
`CreateSettingsFile`): for **every** type carrying a `SiteSettingsPath`,
ddev chmods `Dir(SiteSettingsPath)` to `0755` and the ddev settings
include to `0644` **before** any `#ddev-generated` signature check — and
aborts the start when the chmod fails. With
`disable_settings_management: true` it returns early and touches nothing
outside `.ddev/`. `chmod` is owner-only and ddev runs as `opencode`:
that asymmetry is the entire handover machinery's cause.

## 2. What the replay confirmed (green)

- Developer, new project: `ddev config` → `.ddev/` opencode-owned with
  g+w (hook heal, issue #94), start and git green.
- Clone without flag, dev-owned `.ddev/`: `ddev start` succeeds without
  any handover — ddev never chmods the `.ddev` top dir or the committed
  `config.yaml`; everything else inside `.ddev/` is ddev-created as
  opencode.
- Clone with flag: the project root stays `2775` — verified both ways
  (without the flag ddev caps a root-file/bootstrap root to `0755`).
- Agent-side ddev in general works (opencode owns what it creates).

## 3. Findings and resolutions

### Finding 1 — the dev-owned flag was never written for new projects

`ddev config` wrote no flag and the stamp-skipped routine `opk update`
rescan never picked new projects up. typo3 had a (painful) path via the
bootstrap EPERM hint; drupal/backdrop/magento/others had none — live
evidence: drupal's `ddev config` alone creates `sites/default/`
opencode-owned, capped, dev-readonly, no error, no flag.

**Resolution:** the `ddev()` hook writes the flag right after
`ddev config` — `bin/ddev-as-opencode --opk-devowned-flag <dir>` (new
helper mode, sources the sibling `sh/ddev-handover.sh`, runs as opencode
behind the existing uid guard, no new privilege), gated on the mode and
on "not already flagged"; prints the commit-it note. e2e DD13 asserts
flag + note right after config; the first-start EPERM tripwire is
preserved by explicitly stripping the flag first.

### Finding 2 — agent-side ddev runs leave `.ddev/` without group-write

ddev's explicit `0755`/`0644` cap the inherited ACL mask below g+w
(`getfacl`: `group::rwx #effective:r--`); the #94 heal only ever ran
from the developer's hook. Agent-only projects could stay capped
indefinitely (stamp-skipped updates heal nothing) and the developer's
`git pull` failed without explanation.

**Resolution (visibility):** `ddev_reshare_needed <.ddev-dir> <user>` in
`sh/ddev-handover.sh` (owner-filtered, prunes identical to the heal) +
a `ddev share … group-write missing` warn line per affected project in
`opk status`, naming the cause and the one-command fix. e2e DD13 proves
the full circle: agent start caps → status reports → dev-side ddev
command heals → status clean. The agent *could* always self-heal (it is
the opencode user); automatic agent-side healing stays a documented
behavior rule, not machinery.

### Finding 3 — typo3 bootstrap as agent locks the developer out of the root

Agent-created fresh typo3 projects got the root chmod'd to `0755` until
a root-run scan handed it back. **Subsumed by finding 1** for the
standard flow: with the flag present from birth ddev never chmods the
root. Residual: a `ddev config` run *by the agent* still writes no flag
(the hook is developer-side) — the agent may run the helper mode itself;
documented residual, no machinery.

### Finding 4 — committed `name:` key vs multiple checkouts

Committing `name:` is fine (stable identity) until the same repo is
checked out twice on one host (git worktrees): the second `ddev start`
fails with "a project … already exists". Documented in
[concepts/ddev-integration.md](../concepts/ddev-integration.md)
(multiple checkouts section): drop `name:` and ddev derives per-checkout
identity from the directory.

### Finding 5 — five settings-managed types were missing from the kit map

The map knew typo3, drupal*, backdrop, magento*; ddev's generic settings
chmod fires for more types (all live-verified):

| Class | Types | ddev chmod target | Kit handling now |
|---|---|---|---|
| dir types | `magento*`, `maho` | `app/etc` | handed over like magento |
| dir types | `modx` | `<docroot>/core/config` | handed over |
| root-file types | `codeigniter`, `shopware6`, `symfony` | **project root** (`.env`/`.env.local`) | permanent root-inode handover (`2755`) while unflagged; handed back with the flag |
| root-file type | `wordpress` | **project root** (`wp-config.php`) | deliberate documented exclusion |
| benign | `php`, `generic`, `joomla`, `laravel`, `cakephp`, `asterios`, `silverstripe`, `wp-bedrock`, `craftcms` (inside `.ddev/`) | nothing outside `.ddev/` | none needed |

**Resolution:** type map + `ddev_handover_project_root` root-file branch
+ the generalized `_opk_bootstrap_hint` (type-specific wording, typo3
text unchanged). e2e DD16 proves both classes end to end (EPERM
tripwire → hint → handover → flag → EPERM-free rerun).

## 4. Coverage

Unit: `tests/unit/test-ddev-as-opencode.sh` sections 2c (helper mode),
7d-2 (hook wiring), 7d-3 (reshare detection), 7c-2 (type map, root-file
handover/handback). e2e: `tests/e2e/run-ddev.sh` DD13 (flag at config,
status detect/heal circle) and DD16 (unmapped-type clones).
