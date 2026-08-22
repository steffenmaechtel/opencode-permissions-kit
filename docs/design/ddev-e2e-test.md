# PLAN-DDEV-E2E: real-ddev e2e suite with a cached golden container

> Status: **PLANNED — not implemented.** Design record for a third e2e suite
> (`make e2e-ddev`) that runs the REAL ddev against the REAL docker-rootless
> daemon inside the systemd test container, answering the recurring burn-in
> problem: most ddev issues (#18, #20, #21, #25, the §10a TODOs in
> ddev-sandbox.md) only surfaced on productive WSL installs because both
> existing suites exercise ddev through the `fake-ddev` stub — kit plumbing
> only, never ddev itself. The core enabler is a **golden-image cache**: the
> provisioned rootless daemon + ddev + pulled images are snapshotted once via
> `docker commit`, so repeat runs skip the 3–4+ minute download/install phase.
> Where wording differs from the code, the code wins.

## 1. Problem & goal

| Today | Gap |
|---|---|
| `make e2e` (run.sh, 250 checks) | ddev is `tests/e2e/fake-ddev` — a logging stub. Nothing of ddev itself runs: no containers, no mutagen, no chmod behavior, no router. |
| `make e2e-rootless` (run-docker-rootless.sh, 54 checks) | REAL inner docker-rootless daemon (systemd container), but ddev is never installed — only raw `docker` probes (alpine). |

Every issue class from `ddev-as-user-issues.md` §1.1 — settings-dir chmod
(`#25`), the `ddev()` function transports (`#18`), describe-state mismatches,
mutagen, first-start behavior — needs real ddev to reproduce. Goal:

- `make e2e-ddev` boots the systemd container, provisions the inner
  docker-rootless daemon, installs real ddev, and drives a real project
  lifecycle as BOTH users (agent: opencode; developer: via the `ddev()`
  function and the sudoers helper).
- First run pays the full price (ddev download, image pulls, mutagen —
  realistically 5–12 min, dominated by GB-sized ddev images). The finished
  environment is committed as a local golden image; repeat runs start from
  it and take **~1–3 min**.
- Cache refresh is a non-event: automatic on ddev-version change, manual via
  `make e2e-ddev-fresh` (or `--fresh`), optional TTL.

## 2. Non-goals

- **Windows-side halves** stay untestable in a container: browser opening
  (`ddev launch` → `explorer.exe`), the Windows hosts file
  (`ddev-hostname.exe`), mkcert CA reuse from `/mnt/c`. The suite asserts
  only the container-side behavior (launch prints URL, interop-blocked as
  designed; hosts bridge prints the missing-hostnames report).
- **A broad CMS matrix** stays out — but ONE real, complete site is in scope
  as an **opt-in fixture tier** (§7.1): a real TYPO3 with the Camino theme,
  installed via composer and a DB dump, proving the full boot path
  (settings.php generation, `additional.php` `g+w`, site responds) that
  skeletons cannot reach. The default tier stays typo3-typed *skeletons*
  (no vendor/, no CMS runtime) because the file/ownership failure class
  ddev performs before any CMS code runs; the real-site tier is what the
  skeletons cannot see. Additional fixtures later = same recipe.
- **Performance testing** (mutagen sync speed at scale).
- Replacing the two existing suites — they stay the merge gate; e2e-ddev is
  the deep-dive suite (see §8).

## 3. Architecture: reuse the rootless scaffolding

The suite is `run-docker-rootless.sh` grown a ddev stage — same container,
same knobs:

- `tests/e2e/Dockerfile.rootless` unchanged (systemd PID 1, uidmap,
  slirp4netns, fuse-overlayfs, the nf_tables modules.builtin synthesis).
- `tests/e2e/lib.sh` unchanged: setuid guard + classic-builder self-heal,
  host-layout detection, opencode binary cache, `check`/`skip`/`E` helpers.
- New: `tests/e2e/run-ddev.sh` (runner), golden-image helpers (§4), and the
  same container-internal adaptations the rootless suite applies (RL2 prep:
  fuse-overlayfs daemon.json pin; nested-userns subuid seed when the OUTER
  daemon is rootless — the dev-workspace case).

What the inner environment looks like after warm-up:

```
systemd (PID 1, --privileged, --cgroupns=private)
└─ user@<uid>.service (linger)          # opencode user manager
   └─ docker.service (rootless)         # fuse-overlayfs storage:
      │                                 #   /home/opencode/.local/share/docker
      ├─ ddev-router                    # images pre-pulled (golden):
      ├─ ddev-<proj>-web                #   ddev-webserver, ddev-dbserver,
      └─ ddev-<proj>-db                 #   ddev-router, ddev-utilities
/usr/local/bin/ddev                     # real ddev binary
/home/opencode/.ddev                    # global config + mutagen binary
```

## 4. The cache: one golden image via `docker commit`

Yes to the brainstorming question — a finished "rootless docker + ddev"
environment can be cached, and the natural vehicle is the container itself:
everything expensive lives **inside the container filesystem**, so a commit
captures all of it in one artifact.

### 4.1 What is cached — and what deliberately is not

| State | Location | Cached? | Why |
|---|---|---|---|
| docker-ce-rootless-extras (inner daemon) | `/usr/lib/...`, system dirs | yes | ~100 MB download via get.docker.com |
| ddev binary | `/usr/local/bin/ddev` | yes | ~50 MB download |
| inner daemon images (webserver/db/router/utilities) | `/home/opencode/.local/share/docker` | yes | **the big one** — GBs of pulls, the 3–4 min the user sees |
| mutagen binary + global ddev config | `/home/opencode/.ddev` | yes | downloaded on first `ddev start` |
| composer package cache (real-site tier) | `~opencode/.composer/cache` (or ddev's composer cache volume) | yes | `ddev composer install` on warm-up fills it → repeat runs resolve offline |
| real-site fixture master, pristine (§7.1) | `/opt/e2e/fixtures/<name>` inside the image | yes | tests run against a per-run `cp -a` copy; baking the master into the golden image keeps repeat runs offline and fast |
| `opencode` user, subuid/subgid, linger, `systemctl --user enable docker` | system state | yes | makes the daemon auto-start on every cached boot |
| the kit (`/usr/local/lib/opencode-permissions-kit`, sudoers, install.conf) | system state | **no** | the thing under test — freshly installed from the repo bind mount every run |
| project `.ddev/` + project files | bind-mounted host tmp dir | **no** | fresh `e2e_prepare_project` fixture every run (both-owners scenarios need a clean tree) |
| `/run` (sockets, user runtime dirs) | tmpfs | **no** (impossible) | recreated by systemd on boot — this is why nothing needs manual re-animation |

### 4.2 Build flow (first run / cache miss)

```
1. build Dockerfile.rootless (lib.sh, setuid guard applies)
2. start systemd container
3. create opencode user + subuid seed + fuse-overlayfs daemon.json   (RL2 prep)
4. provision inner daemon: setup-container-backend.sh path
   (or dockerd-rootless-setuptool.sh directly — see §6 R5)
5. install ddev (official install script, pinned version §5)
6. warm up:  ddev config --project-type=typo3 --auto  +  ddev start
   on a throwaway project → pulls all images + mutagen, creates none kept
7. teardown warm-up project:  ddev delete -Oy  +  docker system prune -f
   (keeps images, drops warm-up containers/volumes/networks)
8. quiesce:  sudo -u opencode systemctl --user stop docker.service
   (commit must not snapshot a mid-write storage)
9. docker commit --label kit.e2e.ddev.version=<V> --label kit.e2e.format=<F>
                --label kit.e2e.built=<epoch>   <container> opencode-e2e-ddev:cached
```

### 4.3 Run flow (cache hit)

```
1. docker run -d ... opencode-e2e-ddev:cached /sbin/init
2. systemd boots → linger starts user@<uid> → enabled docker.service starts
   → socket reappears in /run/user/<uid> (no manual steps)
3. DD0 gate: daemon active, `docker images` non-empty, `ddev version` = <V>,
   sudo setuid intact (§6 R2)
4. install the KIT from the repo bind mount (existing-opencode-user path)
5. run the DD catalog (§7) against a fresh project fixture
```

First `ddev start` on the cached image only creates the project's containers
from local images — seconds, not minutes.

## 5. Cache key & invalidation

Same idioms as `e2e_resolve_cache` (lib.sh): resolve, compare, fall back.

- **Key = three labels** on the golden image:
  `kit.e2e.ddev.version` (e.g. `v1.25.3`), `kit.e2e.format` (bump when the
  warm-up recipe changes — the manual escape hatch), `kit.e2e.built` (epoch).
- **Desired version:** env `DDEV_VERSION` (pins win — "test the new release
  that just broke things": `make e2e-ddev DDEV_VERSION=v1.26.0`), else
  latest from the ddev GitHub release API (tiny request). API unreachable →
  reuse the cached image with its label version (offline dev runs work).
- **Rebuild triggers:** label missing (no image) · version mismatch ·
  `kit.e2e.format` bump · `--fresh` flag / `make e2e-ddev-fresh` · optional
  TTL (`kit.e2e.built` older than `E2E_DDEV_TTL` days, default **14** — the
  "every few weeks" refresh from the brainstorming, automated; `0` disables).
- **Wipe:** `make e2e-ddev-fresh` is enough; `docker rmi
  opencode-e2e-ddev:cached` for the paranoid. The golden image is a local
  docker artifact — NOT `tests/e2e/cache/` (that gitignored dir stays
  opencode-binaries-only, so CI's existing cache key is untouched).

## 6. Risks & mitigations

| # | Risk | Assessment / mitigation |
|---|---|---|
| R1 | committed storage inconsistent (daemon writing during commit) | mandatory quiesce step (§4.2.8); DD0 fails loudly with "restore images" hint if the storage were corrupt — worst case is a `--fresh` rebuild |
| R2 | outer daemon strips setuid (this workspace's rootless daemon + BuildKit) | base build already self-heals via lib.sh's classic-builder guard; `docker commit` does not re-unpack layers, it reuses them + adds the container diff as-is, so setuid survives. DD0 still asserts `-u /usr/bin/sudo` on every cached boot; a surprising loss self-heals container-internally (`chmod u+s`) with a loud note |
| R3 | fuse-overlayfs on-disk format not portable across daemon restarts | it is plain directories/files under the container FS — the daemon re-opens its own storage on boot; DD1 (`docker images` non-empty) is exactly this regression's canary |
| R4 | golden image grows unboundedly (layered diffs, leftover volumes) | prune before commit (§4.2.7); TTL rebuild bounds drift; size printed after commit |
| R5 | warm-up uses kit code to provision → kit bugs poison the cache | acceptable and even desirable (the kit's provisioning IS production path); `kit.e2e.format` is the reset button. Alternative (raw setuptool) kept as fallback if kit provisioning gains checks that assume a fresh machine |
| R6 | CI: golden image is GBs; `actions/cache` caps at 10 GB/repo | CI does NOT commit/save per run. Strategy (§8): weekly scheduled run rebuilds warm (no image cache in CI at all — runner disk is ephemeral anyway), plus `workflow_dispatch` for on-demand deep dives. If per-PR e2e-ddev is ever wanted: `docker save | gzip` ≈ 1.5–2.5 GB into a dedicated actions/cache key (`ddev-e2e-image-<V>-<F>`, restore-keyed) — feasible but only worth it once the suite is stable |
| R7 | router ports <1024 under rootless | suite pins the documented rootless answer — `ddev config global --router-http-port 8080 --router-https-port 8443` — instead of the host-wide sysctl; the sysctl question stays covered by unit tests |
| R8 | ddev update checks / instrumentation phone home and add flakiness | warm-up sets `DDEV_NO_INSTRUMENTATION=true` + update-check off in `~opencode/.ddev/global_config.yaml`; offline repeat runs stay green |

## 7. Test catalog (DD sections)

Mapped to the documented issue classes (ddev-as-user-issues.md §1.1) — each
row is the regression net for a real burn-in finding:

| Section | Checks | Issue class |
|---|---|---|
| DD0 | systemd PID 1; inner rootless daemon active; `docker images` non-empty (R3 canary); `ddev version` = label; sudo setuid intact | cache integrity |
| DD1 | kit install from repo bind mount on the warm image (existing `opencode` user path — the upgrade-style install, complementing run.sh's fresh-user path); wrapper + sudoers + `ddev()` shell hook wired for `dev` | install on real state |
| DD2 | agent-side bootstrap: fresh `typo3`-typed project (no vendor/), `sudo -u opencode ddev start` — the bootstrap-root handover: root inode opencode-owned `2755`, start completes without `operation not permitted` (the ddev-working.md §11 chmod error, now with REAL ddev) | #18/#25 EPERM class |
| DD3 | ownership/modes around `ddev start`: `.ddev/` opencode-owned; settings dir chmod'd `0755` by ddev (real behavior); `config.sh refresh` restores `g+w` on settings files | #25 |
| DD4 | dev-owned mode: `ddev-settings on` → start → settings dirs stay dev-owned `2775`, no write outside `.ddev/` | #25 in-model fix |
| DD5 | developer side: `sudo -u dev bash -ic 'ddev ...'` through the `ddev()` function + sudoers helper; `BASH_ENV` transport: nested `bash -c` script calling ddev runs as opencode (uid assert, not just exit code) | #18 |
| DD6 | container identity with REAL ddev containers: `ddev exec` works; web container uid_map maps container root → opencode host UID (§9.1 proof, ddev edition); container reads settings file via bind mount (soft-only goal) | security-model |
| DD7 | lifecycle: `ddev restart`, `ddev stop`, `ddev delete -Oy`, mutagen flush; full-output grep for `operation not permitted` / `EPERM` — zero tolerance across the whole suite log | all chmod classes |
| DD8 | `ddev describe` / `ddev list` report the SAME project state from agent and developer context (the ddev-sandbox §10a mismatch, finally assertable) | §10a TODO |
| DD9 (opt.) | db round-trip: tiny `import-db` → `export-db`; snapshot + restore | db migration (#15 adjacency) |
| DD10–11 (opt-in) | real-site tier, §7.1 below | full boot path |
| DD12 (opt-in) | git flow against a local bare origin, §7.2 below | checkout EPERM class |
| DD13 | `ddev config` on a fresh empty dir (new-project creation), §7.3 below | new-project gap (2026-08-22 burn-in) |
| DD14 | `ddev composer create-project` on the handed-over bootstrap project, §7.3 below | create-project exit 23 (2026-08-22 burn-in) |

Out of scope per §2: launch/hosts/mkcert Windows halves — asserted only as
"prints URL / reports missing hostnames / interop-blocked as designed".

### 7.1 Real-site tier: a complete TYPO3 (e.g. Camino) — DD10/DD11

Opt-in via `E2E_DDEV_SITE=camino` (empty default → skeleton tier only). A
real site proves what skeletons cannot: TYPO3 actually boots, the
frontend renders, and ddev's TYPO3 settings management behaves on real
files.

**DD10 — install & boot (agent side):**

1. `cp -a /opt/e2e/fixtures/camino /var/www/vhosts/camino-e2e` (pristine
   master from the golden image; handover would corrupt the master),
   then kit-side handover (`config.sh projects add` / handover helper).
2. `ddev start` → `ddev composer install` (composer cache is warm — §4.1)
   → `ddev import-db --src=db.sql.gz` → `ddev exec vendor/bin/typo3
   cache:flush` (or equivalent).
3. Assert `curl -f http://camino-e2e.ddev.site:8080/` returns **200** and
   contains a fixture marker string — the first end-to-end "the site
   really works" assertion the kit has ever had.
4. Assert the REAL `config/system/settings.php` exists, is
   `#ddev-generated`-managed, and `additional.php` is group-writable after
   `config.sh refresh` (issue #25 on the real file, not a fixture stub).

**DD11 — two-owner reality on a live site:** developer-side `ddev restart`
through the `ddev()` function while the site runs; edit of
`additional.php` as `dev` (group write — #25 regression); site still 200
afterwards; `ddev exec` uid assertions from DD6 repeated on the real
project.

#### Fixture spec (what gets prepared, where it lives)

| File | Content | Rules |
|---|---|---|
| `composer.json` (+ ideally `composer.lock`) | TYPO3 CMS + Camino theme, versions **pinned** | lock preferred = deterministic warm-up; the theme itself is fetched from packagist at warm-up, so **no theme code is redistributed** in this repo — only the two fixture files |
| `db.sql.gz` | gzip'd dump of the installed site (ddev `export-db` output) | **must not** contain real customer data, credentials, or secrets — a throwaway demo install; keep it small (target < 10 MB gz, hard cap 20 MB); homepage must contain a stable marker string the assertions grep for |
| optional `assets/` | fileadmin/user_upload content, if the theme needs it to render | same size/secrecy rules; referenced paths must exist after import |
| `README.md` | how to regenerate (install steps + `ddev export-db`) | reproducibility — anyone can rebuild the fixture |

Concrete recipe proven out in the 2026-08-22 burn-in (§7.3): TYPO3
v14.3.6 + `typo3/theme-camino` v14.3.6, PHP 8.3, `--project-tld local`,
dump via `ddev export-db -f=backup.sql.gz` came out at **85 KB** (budget
is a non-issue), frontend marker route `/camino/` (the site config's
`base:` is relative — works under any hostname). The burn-in's manual
post-install steps (below) are **baked into the fixture master**, never
re-done per run: `trustedHostsPattern` in `config/system/settings.php`,
`public/.htaccess` copied from
`vendor/typo3/cms-install/Resources/Private/FolderStructureTemplateFiles/root-htaccess`.

**Status: fixture harvested (2026-08-22)** at
`tests/e2e/fixtures/camino/` — `site/` (pristine master, byte-identical
to the burn-in commits except three documented deviations: `name:` line
dropped from `.ddev/config.yaml`, `!/public/index.php` gitignore
exception so clones boot, dump as sidecar `db.sql.gz`) plus the fixture
README with the regeneration recipe. Phase 2b fixture intake is done;
the golden-image warm-up integration remains.

Location: `tests/e2e/fixtures/camino/` in the repo (shipped — installs
stream from the same repo, and CI needs the files). If the dump ever
breaches the size budget: move `db.sql.gz` out of git, keep a README +
download/mount hint, and let the golden image warm-up fetch it from a
local path (`E2E_DDEV_FIXTURE_DIR`). Fixture changes bump
`kit.e2e.format` → golden rebuild re-runs `composer install` + a
freshness check that the installed vendor tree matches the lock file.

Warm-up integration: after §4.2.6, the warm-up also clones the fixture
master into `/opt/e2e/fixtures/`, runs `ddev composer install` + the DB
import once, verifies the 200/marker, `ddev delete -Oy` + prune, then
commits — so the golden image contains warm composer cache + the
pristine master (vendor/ included; page-cached `cp -a` makes per-run
copies cheap).

### 7.2 Git-flow tier: local bare origin — DD12

`git checkout` colliding with ddev ownership is a documented burn-in class
(ddev-dev-owned-projects.md §1: fresh-clone `ddev start` EPERM;
`git checkout <branch>` EPERM while the bootstrap root is opencode-owned —
"error: unable to unlink old 'AGENTS.md'", half-switched working tree). None
of it is e2e-tested today: run.sh's git checks use plain directories, never
clone/branch-switch flows. A **local bare repo as origin** makes the real
flow testable offline and deterministically — no GitHub, no network flake.

**Fixture: `tests/e2e/fixtures/make-bare-origin.sh`** builds the bare repo
per run from the pristine fixture master into the tmp project dir (a bare
repo without vendor/ is tiny; generating it fresh every run avoids yet
another baked artifact and keeps branch content in reviewable script form —
the maintainer's real project bare repo is the template for what the
branches must contain). **Status: generator implemented and verified**
(2026-08-22; ShellCheck-clean, clone + all branch switches tested against
the harvested camino fixture) — reconciled with the real burn-in bare repo:
the tracked set there is `.ddev/config.yaml` + the composer/TYPO3 tree
(11 files, no AGENTS.md), so `feature/top-level` works on README.md/LICENSE
instead. Branch layout:

| Branch | Differs from `main` in | Exercises |
|---|---|---|
| `main` | — (the installed state, DB-dump-matching) | clone baseline |
| `feature/top-level` | modifies/deletes a top-level tracked file (e.g. `AGENTS.md`) | bootstrap-root unlink — THE checkout EPERM |
| `feature/settings` | modifies tracked files under `config/system/` | settings-dir ownership on file replacement |
| `feature/ddev-tree` | adds/removes a tracked `.ddev/commands/host/` file | opencode-owned `.ddev/` vs git unlink/rename |

**DD12 checks** (per run: `git clone /tmp/…/origin.git camino-e2e` as dev,
then kit handover, then):

1. **clone → start (handover mode):** fresh clone, `ddev start` via the
   agent — either boots (handover already ran) or prints the ready-made
   `config handover` hint (ddev-integration.md's hook promise, finally
   asserted).
2. **checkout EPERM, handover mode (documented pain):** with the bootstrap
   root opencode-owned, dev-side `git checkout feature/top-level` must fail
   with `unable to unlink` — asserting *current* behavior as a regression
   tripwire: if this ever changes silently (kit or ddev), DD12 notices.
3. **checkout free, dev-owned mode (the promise):** `ddev-settings on`,
   branch-switch through ALL three feature branches as dev — zero EPERM,
   working tree fully switched (`git status` clean). This is the
   ddev-dev-owned-projects.md §2 guarantee, end-to-end.
4. **agent-side git:** clone + `git pull` as opencode (safe.directory /
   dubious ownership, #17 class; kit `git-config on` path) and branch
   switch as opencode on developer-owned tracked files (group baseline).
5. **pull-while-running:** `ddev restart` after a checkout that replaced
   `.ddev/commands/host/` content — ddev must survive git's file
   replacement inside its own tree.

Runs with the site tier (`E2E_DDEV_SITE=camino` gates it — realistic
tracked-file set) but is generator-driven, so a skeleton variant is one
flag away if the site fixture lags. The 2026-08-22 burn-in validated the
bare-repo mechanics manually (empty bare repo → `mv .git` into the
working tree → add/commit/push; `.git` stays dev-owned as the model
promises) — and confirmed `.ddev/config.yaml` IS a tracked file in a real
project, so the `feature/ddev-tree` branch must include it (already in
the layout above).

### 7.3 Burn-in findings (2026-08-22) → DD13/DD14

A first real new-project install (empty dir → `ddev config` → `ddev
start` → `ddev composer create-project` → `ddev typo3 setup` → Camino
site running, db dumped, bare origin pushed) surfaced two kit-relevant
gaps and validated the designed flows. Both become checks; one is a kit
fix candidate.

**Finding 1 — `ddev config` on a fresh dir creates `.ddev/` without
`g+w`, and no hint fires (kit gap, fix candidate):** ddev creates
`.ddev/` (and the docroot) opencode-owned with its own modes — group
gets `r-x` only, so the developer **cannot edit `.ddev/config.yaml`**
(hotfix was `sudo chmod 775 -R .ddev/`). The `ddev()` hook's bootstrap
hint cannot fire for `ddev config`: it hooks `start|restart` only and
requires `.ddev/config.yaml` to already exist — chicken-and-egg on
project creation. The settings-file warning ddev prints (`Could not
write settings file … chmod … operation not permitted`) is the bootstrap
EPERM in warning form; config still completes. Fix candidate (own issue
+ PR, not part of this plan): post-`config` hook arm that suggests
`config handover` / `projects add` once `.ddev/` exists.

**DD13 checks** (asserting today's behavior as tripwires until the fix
lands, then flipped):

1. fresh empty dir + `ddev config --project-type=typo3 …` (exact burn-in
   flags) via the `ddev()` function completes with "Configuration
   complete." even with the settings warning;
2. `.ddev/` exists, opencode-owned; `config.yaml` NOT group-writable
   (documents the gap — flips to `g+w`-or-hint when fixed);
3. dev-side edit of `.ddev/config.yaml` fails EACCES pre-`refresh`,
   works after `config.sh refresh` (the existing repair path);
4. the follow-up `ddev start` prints the bootstrap hint (hook works —
   `.ddev/config.yaml` exists by then) and fails EPERM until handover,
   then succeeds — the full designed first-start flow of the burn-in.

**Finding 2 — `ddev composer create-project` exits 23 ("Moving install
to Composer root", partial result):** files landed (composer.json,
packages/, …) but the move was incomplete and the command errored;
recovery via `ddev composer req`/`install` worked. **Root cause
diagnosed (2026-08-22, in-suite):** the move is an `rsync -rltgopD`
inside the web container (`cmd/ddev/cmd/composer-create-project.go`);
`-o/-g` chowns the composer root, which only succeeds when the ddev user
OWNS it. In dev-owned mode (kit default) the root belongs to the
developer, so as opencode rsync dies with `chown "/var/www/html/."
failed: Operation not permitted` → exit 23 — the exact burn-in symptom.
With an opencode-owned (handover-mode) root create-project succeeds.
Consequence: **dev-owned mode × `create-project` are incompatible until
a fix** (kit-side: document the temporary `config handover` workaround
or special-case it; upstream: ddev could drop `-o/-g` when running as
non-root on a foreign-owned root). DD14 asserts both sides as the
regression pair. Reference checkouts for follow-up analysis:
`github/ddev` (tag v1.25.3), `github/composer` (tag 2.10.2) in this
workspace.

**DD14 checks:** dev-owned root → create-project must FAIL with exit 23
(tripwire, Finding 2); after switching to handover mode (root
opencode-owned) create-project must exit 0 and land composer.lock +
public/index.php completely.

**Validated as working (no new checks needed beyond existing DD rows):**
the pre-start hint + handover + green start flow (DD2/DD4), hosts-hint +
`ddev-hosts-add` bridge (DD section §7 out-of-scope note), `ddev typo3
setup` / `ddev export-db` inside the container (DD9/DD10), and the whole
bare-origin flow (DD12).

## 8. Integration

- **Makefile:** `e2e-ddev` (`sh ./tests/e2e/run-ddev.sh $(ARGS)`),
  `e2e-ddev-fresh` (`--fresh`), help entries. NOT added to `e2e-all` —
  `e2e-all` stays the merge gate; e2e-ddev downloads GBs and must not gate
  every PR.
- **CI (phase 3):** `.github/workflows/e2e-ddev.yml` — live since
  2026-08-22 as **manual-only** (`workflow_dispatch` with `site_tier` and
  `ddev_version` inputs; the maintainer validates runner runtime first).
  Weekly `schedule` is the planned follow-up once duration is known; no
  image caching between runs (R6). The chmod-list rule now covers all
  THREE workflow files (`tests/test-workflows.sh` enforces it, including
  the runner `tests/e2e/run-ddev.sh`).
- **Docs:** this record + a MANUAL.md "troubleshooting with e2e-ddev" note +
  README testing mention in the same PR as the runner (repo rule: docs move
  with code).

## 9. Rollout & effort

| Phase | Content | Estimate |
|---|---|---|
| 1 | runner skeleton + golden-image build/quiesce/commit/boot (§4) + DD0–DD2 | 1–2 d |
| 2 | full catalog DD3–DD9 + `--fresh`/TTL knobs | 1 d |
| 2b | real-site tier: fixture intake (**done 2026-08-22** — `tests/e2e/fixtures/camino/` harvested), remaining: warm-up integration + DD10–DD11 | 1 d |
| 2c | git-flow tier: `make-bare-origin.sh` generator (**done 2026-08-22**, verified) + DD12 | 0.5 d |
| 2d | burn-in findings §7.3: DD13 (config-on-empty-dir tripwires) + DD14 (create-project) — DD13/DD14 need no site fixture, only ddev + composer | 0.5 d |
| 3 | Makefile/CI workflow + test-workflows + docs | 0.5–1 d |
| 4 | burn-in on this workspace (rootful + rootless outer layouts), matrix knob `DDEV_VERSION` for new ddev releases | 0.5 d |

Expected wall times (workspace, rootless outer daemon): first build 5–12 min
(image pulls dominate; real-site warm-up adds `composer install` + import,
a few more minutes), cached runs 1–3 min (real-site tier: +1–2 min for
copy/import/boot), `--fresh` = first-build cost again.

## 10. Open questions

- Warm-up provisioning via the kit vs. raw `dockerd-rootless-setuptool.sh`
  (R5) — start kit-path, keep fallback.
- TTL default 14 d vs. manual-only refresh — plan says 14 d; decide after
  seeing how often label-rebuilds hit mid-week.
- DD9 depth (db round-trip worth its runtime?) — optional flag initially.
- Should DD2 use a second, `drupal`-typed skeleton for the
  `sites/default` handover row, or is typo3 enough for v1? Plan: typo3 only,
  drupal behind the same flag as DD9.
- Fixture versioning policy (real-site tier): follow Camino/TYPO3 releases
  on fixture refresh, or pin a known-good snapshot and only bump
  deliberately? Plan: pin deliberately (a fixture bump is a conscious act +
  golden rebuild), track upstream in the fixture README.
- Does the Camino theme license permit its use in fixture context (fetch
  via packagist, demo dump in a public repo)? Plan: assume yes for
  packagist usage; verify before committing the dump, keep the dump free of
  anything beyond theme demo content.
- Bare-origin branch set (§7.2): are the four branches enough, or does the
  maintainer's real project bare repo show additional collision files
  (e.g. tracked `.ddev/config.yaml` churn, `public/fileadmin` content)?
  **Resolved (2026-08-22):** reconciled against the real repo — tracked
  set is 11 files incl. `.ddev/config.yaml`; generator covers it
  (`feature/ddev-tree` includes config.yaml churn). `fileadmin` is
  gitignored in the real project, correctly absent from the fixture.
- DD12.2 asserts today's EPERM as a tripwire — flip it to "must succeed"
  the day handover mode is retired in favor of dev-owned-everywhere (then
  the check becomes the promise, not the pain).
- DD13's `ddev config` gap (§7.3 Finding 1): fix inside the kit first
  (post-`config` hint arm in `ddev-as-opencode.sh`) or ship the e2e
  tripwire first and fix later? Plan: file the issue now, ship both —
  the tripwire documents current behavior, the fix PR flips it.
- DD14's exit-23 cause is undiagnosed — investigate during phase 1
  burn-in (may be a ddev bug worth reporting upstream, in which case the
  check pins ddev's behavior with a version note instead of ours).
  **Resolved (2026-08-22):** rsync `-o/-g` chown on the dev-owned
  composer root — dev-owned × create-project incompatible until fixed;
  DD14 asserts the pair (fail in dev-owned, succeed in handover).
  Remaining decision: kit-side workaround (hint/`config handover`
  detour) vs. upstream report — tracked as the Finding-2 issue.
