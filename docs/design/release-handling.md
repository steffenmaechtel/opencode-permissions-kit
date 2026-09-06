# Release handling after alpha — channels, tags, stability

> Status: **CURRENT (Phase 1 implemented).** Options and the decided
> model for how the kit ships stable versions after alpha. Phase 1
> (stable mirror branch + `KIT_CHANNEL` stamp + channel-aware updates)
> is implemented; Phases 2–3 are on-demand follow-ups. Tracked in
> [issue #38](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/38).

## 1. Problem

Every entry one-liner (README, docs, the `opk status` hint) streams
`files/install.sh` from `master`, and every `opk update` self-fetches
from `master` too. That was fine while `master` == alpha-latest, but
after alpha:

- A fresh install gets whatever `master` is *right now* — mid-development
  state, minutes after a merge, with only CI as a gate.
- `opk update` on a user's machine silently hops onto that same moving
  target (the deployed `update.sh` re-fetches with its in-code default).
- Version tags exist (`0.0.29`, bare, no `v` — matches the `VERSION`
  file) but are purely informational today.

Goals (from the issue):

1. **Stable by default** — installs and updates track a released,
   blessed state.
2. **Opt-in dev channel** — loading `master` or any `feature/*` branch
   for testing stays a documented, explicit path.
3. Keep the raw-GitHub streaming architecture (per-file `KIT_FILES`
   fetch). No npm package, no plugin store, no distribution platform —
   a deliberate non-goal today; Option D maps that door in detail,
   including the one variant (apt) that would technically fit.

## 2. What exists today

- `install.sh` / `update.sh` fetch every kit file from
  `KIT_BASE_URL = https://raw.githubusercontent.com/<repo>/$KIT_BRANCH`
  with `KIT_BRANCH` defaulting to `master` (files/install.sh:36,
  files/opencode-permissions-kit-lib/management/update.sh:38).
- `KIT_BRANCH` already accepts **any ref raw.githubusercontent
  understands** — branches, and also tags:
  `KIT_BRANCH=0.0.29` resolves `refs/tags/0.0.29`. Exact-version
  pinning therefore already works mechanically; it is just not
  documented as a channel.
- `make check-version` enforces the two in-code `KIT_BRANCH` defaults
  stay identical; `make version` stamps the `VERSION` file.
- `opk update` runs the **deployed** update.sh, whose self-fetch falls
  back to its in-code default. The installed kit has no memory of which
  channel it came from — `install.conf` carries no channel key.
- e2e suites are channel-agnostic: they pin `KIT_BASE_URL` per branch
  already.

**The bootstrap constraint** (it drives every option below): a streamed
script cannot know the ref it was fetched from. The channel must be
carried by the caller (env in the one-liner) or remembered on disk
(a stamp in `install.conf`) — the script itself cannot derive it.

## 3. Options

### Option A — trunk-based: `master` IS stable (status quo, hardened)

Releases stay tags on `master`; "stable" is enforced by merge discipline
only (green PRs, both e2e suites, no direct commits — all already rules).

- **Pros:** zero new machinery; docs, `check-version`, e2e, and the
  update flow stay exactly as they are.
- **Cons:** stability is a promise, not a mechanism. A bad merge on
  `master` is every fresh install within minutes; there is no way to
  test "next" on real user machines without releasing it; a revert is
  the only hotfix path and it re-triggers the same exposure.
- **Verdict:** acceptable for alpha (it is what we do now); too weak as
  the post-alpha default.

### Option B — `stable` mirror branch + explicit channel in the one-liners

A second long-lived branch `stable` that is a **byte-identical mirror**
of `master` at release points. The channel lives in the URL and the env,
never in the code:

- The in-code `KIT_BRANCH` default stays `master` **in both branches**
  — `git diff master stable` must be empty at every release. That keeps
  `make check-version` meaningful and merges conflict-free forever.
- The documented one-liners switch to
  `curl -fsSL .../stable/files/install.sh | sudo env KIT_BRANCH=stable bash`
  — channel = the ref in the URL, passed through the existing env
  override.
- `install.sh` stamps the actually-used channel into `install.conf`
  (`KIT_CHANNEL=stable`). The deployed `update.sh` resolves its
  self-fetch ref as: **explicit `KIT_BRANCH` env > `KIT_CHANNEL` stamp >
  `master`**. Result: users stay on the channel they installed from,
  `KIT_BRANCH=master` opts into dev, `KIT_BRANCH=feature/...` tests any
  branch, `KIT_BRANCH=0.0.30` pins an exact tag — one mechanism for all
  three.
- **Release procedure:** bump `VERSION` via PR on `master` (repo rule:
  never commit on master directly), then
  `make release VERSION=x.y.z` — the scripted release helper
  ([`scripts/release.sh`](../../scripts/release.sh)) verifies the
  preconditions, tags `x.y.z`, fast-forwards `stable` (aborting instead
  of force-pushing on divergence), and pushes. Optional later: a GitHub
  Action mirrors on tag push.
- **Hotfix policy:** fix on `master`, cut `x.y.(z+1)` normally. Never
  commit to `stable` directly (branch protection: merges only) — direct
  patches would break the byte-identical invariant.
- **Pros:** raw URLs only (no API calls), the streaming architecture is
  untouched, `KIT_BRANCH` machinery is reused as-is, e2e unaffected, a
  broken `master` can never reach a stable install, and the invariant is
  mechanically verifiable (`git diff master stable` empty).
- **Cons:** a second branch to protect and keep honest; the docs'
  one-liners must carry `env KIT_BRANCH=stable` (a user who strips the
  env var still installs from the `stable` *URL* but would update from
  `master` until the stamp exists — the stamp closes exactly this gap on
  first install); one manual mirror step per release (or one Action).

*Variant B1 (rejected):* rewrite the in-code default per branch
(`master` copy defaults `master`, `stable` copy defaults `stable`). Then
the branches differ permanently, every release merge conflicts on that
line, and `check-version` compares apples to oranges. B1 buys only
"one-liner without env var" — not worth a permanently diverging branch.

### Option C — resolve "latest release" via the GitHub API

`install.sh` asks
`https://api.github.com/repos/<repo>/releases/latest`, parses the tag,
then self-fetches at `refs/tags/<tag>`.

- **Pros:** tags are the single source of truth; no second branch;
  `releases/latest` skips prereleases for free (beta staging via
  `-beta.x` tag suffixes).
- **Cons:** an API dependency at the worst possible moment — the very
  first command a new user runs. Unauthenticated rate limit is 60
  requests/hour per IP (shared NATs, CI runners); a flaky or throttled
  API turns into "install.sh does not work" reports. More first-touch
  logic to keep robust, and the e2e suites would have to mock or pin the
  API answer.

*Variant C2 (rejected):* attach the kit as a release tarball and stream
`releases/latest/download/...`. That replaces the per-file `KIT_FILES`
fetch (and its per-file healing) with a single-artifact model — the
biggest possible change to `install.sh`/`update.sh`, for no user-visible
gain over B.

### Option D — distribution platforms (Homebrew, npm, apt, AUR, ...)

Today an explicit **non-goal**: the repo ships scripts streamed from raw
GitHub, deliberately without a package runtime (see AGENTS.md). This
section enumerates the variants anyway — what each could look like for
*this* kit, and where it breaks — so "no" stays an argued decision, not
an unexamined one.

Two properties of the kit collide with every package manager below:

- **The install mutates the system as root** (creates the `opencode`
  user, writes sudoers, deploys to `/usr/local/lib`). A channel that
  cannot run post-install steps as root cannot install the kit at all.
- **The kit self-updates** (`opk update` re-deploys files it does not
  own in the package-manager sense). Two owners for the same files —
  package database vs. `update.sh` — is a classic source of drift; any
  D variant would have to teach `opk update` to detect a package
  install and defer (`opk update` → "managed by apt, run apt upgrade").

#### D1 — Homebrew (Linuxbrew under WSL)

`brew install opencode-permissions-kit`, via a personal tap
(`brew tap steffenmaechtel/tap`) or homebrew-core (requires
notability/review).

- **Pros:** versioning and `brew upgrade` UX; wide developer mindshare;
  tap is low ceremony (one formula, no infra).
- **Cons:** **fatal fit problem** — Homebrew refuses to run as root, but
  the kit's post-install (useradd, sudoers, /usr/local/lib) is
  inherently root. A formula could only place the files and then ask
  the user to run the root part separately: two-step install, worst of
  both worlds. Also user-prefix install vs. the kit's FHS-style
  `/usr/local/lib` layout, and the brew-vs-`opk update` ownership
  conflict.

#### D2 — npm package / `npx opencode-permissions-kit`

- **Pros:** versioning, huge reach, `npx` one-shot runs; release
  automation (provenance, provenance attestations) is mature.
- **Cons:** needs a Node runtime on a shell-only kit; root installs from
  npm are exactly the `npm i -g` + sudo anti-pattern the security
  community warns about; postinstall scripts as root are npm's most
  abused feature (users rightly disable them). Explicitly ruled out in
  AGENTS.md ("no plugin, no npm package").

#### D3 — apt: `.deb` package + apt repository (or PPA)

A `.deb` with maintainer scripts (`postinst` does what `install.sh`
does: user, sudoers, deploy), hosted in an apt repo on GitHub Pages
(signed), or a Launchpad PPA (Ubuntu-only builds).

- **Pros:** the only variant whose model actually matches the kit —
  dpkg runs `postinst` as root by design, `install.conf` maps naturally
  to debconf/conffiles (interactive prompts at install, preserved on
  upgrade), GPG-signed artifacts beat raw-TLS streaming, and WSL2
  Ubuntu/Debian is precisely the target audience. Version pinning and
  stable repositories (`stable`, `-dev` suites) solve issue #38 natively.
- **Cons:** real infrastructure and process — repo hosting, GPG key
  rotation, reprepro/aptly (or Launchpad's build queue and slower
  iteration); a second packaging layer to maintain per release
  (changelog, version format `0.0.29-1`); the `opk update` ownership
  conflict must be resolved (dpkg database must win); e2e suites would
  need an apt-flavored install path. High fixed cost for a kit whose
  audience is one maintainer's user group.

#### D4 — AUR (Arch)

- **Pros:** zero infra (community-maintained PKGBUILD), versioned.
- **Cons:** wrong distro — the kit targets Ubuntu/Debian WSL2 (ddev's
  documented base); PKGBUILD runs as root from a community script,
  a trust surface this security-sensitive kit should not encourage.

#### D5 — git clone + `make install` (GitOps channel)

`git clone --branch x.y.z && sudo make install` — pin by tag or commit.

- **Pros:** offline-capable, exact pins, no curl-into-root; a checkout
  is already a supported install source (`files/install.sh` runs fine
  from a clone).
- **Cons:** no channel semantics at all (the user *is* the channel
  logic — this solves pinning, not stable-by-default); updates are
  `git pull && sudo make install`, i.e. manual; moves trust from "one
  reviewed script" to "run whatever the checkout contains". Fine as a
  documented power-user path (it half-exists via CONTRIBUTING), not as
  the answer to #38.

#### D6 — self-contained installer artifact (makeself / release tarball)

One signed, self-extracting bundle attached to GitHub releases; install
= download, verify checksum/signature, run.

- **Pros:** single artifact per release, offline installs, checksum and
  GPG verification fit the kit's security posture; `releases/latest`
  gives a stable "latest" URL without API parsing.
- **Cons:** replaces the per-file `KIT_FILES` streaming model (same
  objection as C2); updates still need a fetcher (so `update.sh`
  survives anyway, now with archive handling); artifact build/sign
  step per release. Interesting only if raw-GitHub streaming is ever
  rejected (e.g. for signing guarantees).

#### D verdict

| Variant | Root post-install possible | Update story | Effort | Fit |
|---|---|---|---|---|
| D1 brew | no (refuses root) | brew vs. `opk update` conflict | low-med | poor |
| D2 npm | as root (anti-pattern) | npm vs. `opk update` | med | rejected |
| D3 apt/.deb | yes (by design) | apt owns files, `opk update` defers | high | best of D, still costly |
| D4 AUR | yes | AUR helper | low | wrong distro |
| D5 git clone | yes (make as root) | manual | none | power-user path only |
| D6 makeself | yes | own fetcher needed | med | only if signing becomes a goal |

**Stays a non-goal** — but with the reasoning explicit: D1/D2/D4 fail
the kit's root-and-system-mutation model or its no-runtime philosophy,
D5/D6 do not answer the stable-channel question, and D3 (apt) — the
one that genuinely fits — costs repo infrastructure, signing, a second
packaging layer, and an e2e variant that a single-maintainer project
should not carry while B delivers stable-by-default with none of it.
The honest trigger to revisit D3: the kit gains users outside the
maintainer's circle who already manage their WSL distro with apt, or
signed artifacts become a requirement (then D6 first).

## 4. Comparison

| Criterion | A trunk | B stable mirror | C API resolve |
|---|---|---|---|
| Stable by default | by discipline | by mechanism (ref) | by mechanism (tag) |
| Test any branch / pin a tag | yes (`KIT_BRANCH`) | yes (`KIT_BRANCH`) | pin yes, branches outside the API path |
| Works with raw URLs only | yes | yes | no (API on first touch) |
| New machinery | none | branch + stamp + docs URLs | API parsing + e2e mocks |
| Broken `master` hits new installs | immediately | never (stable is behind) | never |
| Release effort | tag only | tag + mirror (or Action) | tag + release notes |
| e2e impact | none | none | mock/pin needed |

## 5. Recommendation

**Option B** (stable mirror branch with explicit channel in the
one-liners, channel stamp in `install.conf`, tags as documented pins).

It fits this kit because it changes *which ref the docs point at*, not
how the kit ships: per-file raw streaming, the `KIT_BRANCH` override,
`check-version`, and both e2e suites all survive unchanged, while
`master` gains a genuine staging area and users gain a stable default
plus one uniform opt-in mechanism (`KIT_BRANCH=master|feature/...|x.y.z`).
Of the platform routes (Option D), only apt/.deb would technically fit
the kit's root-mutation model — its infrastructure and packaging cost is
the reason it stays parked (see the D verdict for revisit triggers).
The phased order in which these ship: [§6 Adoption roadmap](#6-adoption-roadmap).

## 6. Adoption roadmap

Goal after alpha: make the kit usable for many end users — the first
milestone is **100+ developers** running it. The distribution decision
follows the adoption funnel, not the other way around: at that scale
users arrive through the ddev/opencode communities (Discord, issues,
blog posts) and convert on a working one-liner plus calm updates —
discovery and first-run reliability beat channel sophistication. The
phases:

### Phase 1 — now (alpha → beta): Option B

The stable-mirror branch is the whole job: stable-by-default installs
and updates, one uniform opt-in (`KIT_BRANCH=master|feature/...|x.y.z`),
distro-agnostic raw-GitHub streaming (works on every WSL2 distro the
audience runs — Ubuntu, Debian, Arch), no infrastructure, e2e untouched.
This is all 100 users need from distribution; the remaining work for the
milestone is community-facing (README, docs, announcements), not
packaging.

### Phase 2 — on demand (trust question / growth beyond 100): add D6

When users ask "is this verifiable?" or the audience grows past the
first circle, layer **signed release artifacts** (D6) on top of B — the
two coexist:

- One tarball (checksum + GPG signature) attached to each GitHub
  release; `releases/latest/download/...` becomes a stable latest URL
  without API parsing, and prerelease tags get correct semantics for
  free.
- Per-file streaming stays the dev path (feature branches have no
  releases) — `update.sh` grows a dual fetch mode: tarball for the
  stable channel, `KIT_FILES` streaming for branches/tags.
- Cost when it lands: release automation (build + sign + attach),
  key management, and an e2e variant for the tarball path. Deliberately
  not paid while nobody asks — a makeself artifact even breaks the
  `curl | sudo bash` one-liner (payload offset needs `$0` as a file →
  two-step install), which is a conversion loss at the most sensitive
  point of the funnel.

### Phase 3 — if the project outgrows single-maintainer: D3 (apt)

An apt repository (`.deb` with root `postinst`, GPG-signed repo) is the
only platform route whose model genuinely fits the kit (see the D
verdict). Its infrastructure and packaging cost is only justified once
there is a visible group of users who manage their WSL distro with apt
and ask for native packages. Not a milestone-100 move.

### What does not change

Homebrew (D1), npm (D2), and AUR (D4) stay rejected at every phase —
they fail the kit's root-and-system-mutation model or its
no-runtime philosophy regardless of scale.

## 7. Implementation outline (Phase 1 — implemented)

1. Create `stable` at current `master`; branch protection: merges from
   `master` only, no direct commits.
2. `install.sh`: stamp `KIT_CHANNEL=$KIT_BRANCH` into `install.conf`
   (and print it in the summary); document the key in
   `docs/reference/files.md`.
3. `update.sh`: self-fetch ref resolution becomes env `KIT_BRANCH` >
   `KIT_CHANNEL` stamp > `master`; `opk status` shows the channel next
   to the version.
4. Docs URL swap (README, `docs/getting-started.md`,
   `docs/reference/cli.md`, `docs/how-to/update.md`, the `opk status`
   hint in `status.sh`): one-liners point at `.../stable/...` with
   `env KIT_BRANCH=stable`; a short "channels" subsection documents
   stable / master / feature / tag pins (CONTRIBUTING keeps the
   branch-testing recipe).
5. `make version` hint text ("installs track master") updated;
   `make check-version` unchanged (in-code defaults stay `master`).
6. Optional: GitHub Action that fast-forwards `stable` on tag push and
   fails loudly if `git diff master stable` would not be empty.
7. e2e: no changes (suites already pin `KIT_BASE_URL` per branch).

## 8. Open questions

1. **Flip the in-code default to `stable` post-alpha?** Docs and stamp
   already carry the channel; a flipped default would additionally
   protect users who hand-strip the env var from the docs one-liner.
   Decide after the first stable release ships.
2. **GitHub default branch:** point the repo landing page at `stable`
   (visitors see installable code) or keep `master` (development is the
   visible face)? Leaning: keep `master` — the README one-liner is the
   install surface.
3. **Mirror automation from day one** (Action on tag push) or manual
   fast-forward while the release cadence is low? Leaning: manual first,
   automate when releases exceed ~monthly.
4. **Prerelease channel** (`0.1.0-beta.1` tag suffixes, hidden from
   `releases/latest`-style semantics)? Leaning: no — `master` is the
   prerelease channel; adding a third one is complexity without a user
   asking for it.
