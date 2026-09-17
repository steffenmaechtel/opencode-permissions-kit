# opencode 2.x compatibility — design record

> Status: **CURRENT (work in progress).** What the kit does today to stay
> compatible with opencode 1.x **and** the upcoming 2.x line (tags
> `v2.0.x`, not yet on `releases/latest`), what was verified, and what is
> still open. Issue #80. The 2.x migration guide
> (<https://opencode.ai/v2/docs/migrate-v1/>) is the upstream reference;
> where wording differs from the code, the code wins.

## 1. What changed in opencode 2.x (kit-relevant)

| Area | 1.x (latest releases today) | 2.x (tags) | Kit impact |
|---|---|---|---|
| Process model | one binary per invocation | CLI is a **client**; commands ensure a shared background service (`opencode serve --service`, port `0xc0de`, password in `~/.config/opencode/service.json`, `0600`) or spawn a private `--standalone` server child | tools run **server-side** — env transport and lifecycle had to be re-anchored (§3) |
| Config files | `~/.config/opencode/opencode.json[c]` + project `opencode.json[c]` | same locations; v1 shapes normalize **in memory** (source files untouched) | **none** — the kit's global template and project opt-ins work unchanged |
| Permissions | `permission.bash` map, last match wins | same input, migrated to an ordered `permissions` array (`bash` action becomes `shell`) | detection semantics identical (§2) |
| `debug config` | one merged JSON object | **list of document entries** (lowest → highest priority), each with normalized `permissions` | parser extended (§2) |
| Service staleness | — | a running service answers with its **boot-time snapshot**; root-owned config edits (`sudo tee`, `sed -i`) need seconds to reload | probe stops the service again (§4) |
| Binary replace | — | the running service holds the binary (`ETXTBSY` on `cp`) | update stops the service first (§5) |
| Subcommands | `agent`, `plug`, `providers`, `account`, `github`, `pr`, `db`, `generate`, `web` … | `agents` (nested), `plugin`, `auth`, `api`, `service`, `pair`, `mini`, `update` (alias) | HEADLESS list is a union (§6) |
| `--version` output | bare (`1.18.31`) | `opencode v2.0.3` | `OPENCODE_MAJOR` stamp (§7), e2e normalization |
| serve output | `opencode server listening on …` | `server listening on …` | common substring checked in e2e |
| `OPENCODE_SERVER_PASSWORD` | primary | still honored (legacy fallback), primary is `OPENCODE_PASSWORD` | env_keep unchanged for now |
| TUI config | layered `tui.json(c)` | one global `~/.config/opencode/cli.json` (auto-migrated) | **open** (§9) |
| Plugins | v1 plugin API | **v1 plugins do not run** ("moving a file is not enough") | **open** (§9) |

## 2. Detection: same question, new answer shape

The wrapper's container-tool opt-in (issue #81) asks opencode itself via
`opencode debug config`, as the opencode user from the cwd. 1.x answers
with the merged config object; 2.x answers with the document-entry list.
`jsonc-parser.py --tools -` understands both: the v1 `permission.bash`
map (file order, last match wins) and the 2.x entries (documents in
priority order, `shell`/`bash` rules, concatenated in order, last match
wins). Rules with actions other than `shell`/`bash`/`*` never count.

Config files themselves stay in the v1 shape on both majors — 2.x
normalizes on load and never rewrites them (verified against the
migration guide and live probes).

## 3. Session servers: force `--standalone` on 2.x

The kit's env transport (`DOCKER_HOST`/`XDG_RUNTIME_DIR` exported before
the `sudo -u opencode` exec) assumes the exec'd process **is** the
session. On 2.x the default is the shared background service whose
environment comes from its own registration — a reused daemon never saw
this wrapper's exports, and the per-project container opt-in breaks.

Session starts (the TUI default — no args or flags-only — `run`, `mini`)
therefore get `--standalone` appended on 2.x: a private server as a child
of the exec'd process, full env inheritance, dies with the session. The
flag exists only in 2.x, so it is gated on `OPENCODE_MAJOR` (§7). An
explicit `--server`/`--standalone` in the user's args always wins — the
wrapper never adds the flag then. `serve` keeps its own foreground-server
path; query subcommands keep the service path (they run no tools).

## 4. Probe hygiene: no cross-start service state

A cold-starting service can answer `debug config` with an **error
object**; a long-lived one answers with a **stale snapshot** (root-owned
edits reload only after seconds). Both were observed in the e2e as
"banner missing" and "fresh global allow invisible". Two guards:

- **Shape validation**: piped probe output that is neither the 2.x entry
  list nor a dict carrying `permission`/`permissions` makes the parser
  exit 3 = "not trustworthy" → the wrapper falls back to the project-only
  scan instead of trusting "no tools".
- **Time bound**: the probe runs under `timeout 10` (best-effort, no
  timeout(1) → unbounded). 2.x assigns the background-service port per
  CHANNEL, not per user (`127.0.0.1:0xc0de`): a bare 2.x opencode run by
  the default user (the known bypass scenario — deny-all config
  mitigates permissions, not ports) blocks the opencode user's service,
  and `debug config` then retries forever. Without the bound even
  `opencode --version` hangs after the banner (observed on a real WSL).
  The service stop after the probe is time-bounded the same way.
- **Service stop**: after a probe on 2.x the wrapper stops the background
  service again (graceful `service stop`). Every probe then reads fresh
  files, and no stale registration survives a wrapper crash. This matches
  the kit's per-invocation model; the next 2.x command re-ensures the
  service. Cost: a service boot (~2–4 s) per 2.x wrapper start — accepted
  for correctness while 2.x settles.

## 5. Binary upgrades: stop the service first

`opk upgrade-opencode` / `update.sh --binary-path` replace
`$LIBDIR/bin/opencode` — on 2.x a running service holds that file
(`Text file busy`). `install_binary()` stops the service first (graceful,
then a pkill fallback that catches a wedged daemon; both best-effort,
1.x ignores the unknown subcommand) and re-stamps `OPENCODE_MAJOR`.

## 6. Headless classification: subcommand union

The wrapper's HEADLESS list keeps every 1.x name (unknown to 2.x, which
errors on them anyway) and adds the 2.x additions `api`, `auth`,
`plugin`, `service`, `pair`, `update`. 2.x `mini` is an interactive UI
and stays bannered like `tui`/`attach`.

## 7. `OPENCODE_MAJOR` stamp

`install.sh` stamps the installed binary's major into `install.conf`
(`OPENCODE_MAJOR=1|2`, derived from `--version`: `opencode v…` → 2);
`update.sh` re-stamps on every binary replacement. The wrapper falls
back to runtime detection (one extra `--version` exec) for stamps from
older kit versions. All 2.x-only behavior hangs off this one variable.

## 8. Proving it: version-pinned e2e

2.x has no GitHub release assets yet (tags only), so the binary is built
from source (bun 1.4.2, `packages/cli/script/build.ts
--target=opencode-linux-x64`, `OPENCODE_VERSION` env pins the stamp) and
seeded into `tests/e2e/cache/opencode-<version>/` (gitignored).
`make e2e E2E_OC_VERSION=2.0.3` pins the whole suite to it — the default
(empty) still resolves `releases/latest`. Verified green: `e2e` +
`e2e-rootless` against 2.0.3 (256 + 46 checks) and against 1.x latest
(256 + 46). A CI job for the 2.x pin follows once upstream ships release
assets (the cache is not reproducible in CI from tags alone).

## 9. Open items

- **Service port collision**: 2.x binds the background service per channel
  (`0xc0de`), not per user — the default user running bare 2.x opencode
  blocks the opencode user's service (probe time-bounded, see §4, but the
  session itself would also suffer). Watch for an upstream fix or a kit
  side service-port config once 2.x ships release assets.
- **kit-mode.tsx port — DONE** (kept for context): `kit-mode-2x.tsx` is
  the v2 CLI-plugin port (same strings/contract, footer.status slots,
  theme tokens, `Plugin.define` entrypoint). Registered additively in
  both users' `~/.config/opencode/cli.json` via `py/tui-register.py`
  (OPENCODE_MAJOR-gated in install.sh/update.sh, unregistered by
  uninstall.sh; the auto-migrated v1 entry is dropped). Deployment and
  registration are e2e-verified; the actual TUI render needs a real
  terminal (manual verification on a real WSL).
- **cli.json management — DONE** (kept for context): see above — additive
  entry management only, user keys and entries survive, unparseable or
  wrong-shaped files are left untouched.
- **Service-mode ergonomics**: once 2.x is `releases/latest`, reconsider
  per-start service boots vs. keeping the service warm with a staleness
  guard (e.g. mtime probe of the config files).
- **`OPENCODE_PASSWORD` env_keep**: 2.x's primary name; add to sudoers
  env_keep when third-party UIs adopt it (legacy name still works).

## 10. Adoption plan (working notes)

How the compatibility work rolls out — decided 2026-09-16, session over
issues #80/#81:

1. **Now — branch stays open.** `feature/opencode-2x-compat` waits while
   the real-WSL install (kit from the branch, 2.0.3 built from source)
   gets manual observation. Holding is risk-free: every 2.x behavior is
   gated on `OPENCODE_MAJOR`, and both e2e suites are green against
   1.x latest (unchanged behavior) and 2.0.3.
2. **CI cannot run 2.x yet — deliberately.** No release assets exist for
   the v2 tags, so the e2e download path 404s. Building from source in
   CI (bun, ~8 min) or pulling upstream workflow-run artifacts (auth,
   90-day expiry, fragile) was considered and rejected as premature.
   The proof stays local: version-keyed cache in `tests/e2e/cache/`
   makes repeat runs cheap. The moment upstream ships release assets,
   `E2E_OC_VERSION` works in CI unchanged — add the job then.
3. **Merge as a normal PR** once manual validation satisfies. Everything
   is already in production shape; nothing in the PR depends on 2.x
   being released.
4. **Follow-ups, in order**: ~~`kit-mode-2x`~~ (done — see §9, ported on
   this branch), then the CI job, then the §9 ergonomics items.
5. **Urgency trigger**: when upstream flips `releases/latest` to 2.x,
   every fresh kit install pulls a 2.x binary — the merge becomes
   time-critical on that day. Monitor cheaply with
   `git ls-remote` / the releases API at session starts.
