# DDEV-URL-TRANSPORTS: how browser commands get their URL

> Status: **IMPLEMENTED (since 0.0.26, PR #50).** The kit reads browser-command
> URLs from `ddev describe -j`. This record documents that transport, the
> removed one it replaced, the upstream alternatives considered, and where
> each fact lives in the ddev source (pinned v1.25.4) so it can be
> re-verified on ddev updates. Where this record conflicts with the code,
> the code wins.

## 1. Problem

ddev browser commands — `launch` itself and the wrappers (`mailpit`, the
phpmyadmin/adminer add-ons, `xhgui`) — cannot open a browser as the
`opencode` user: the browser open needs WSL interop (`explorer.exe` /
`xdg-open` → `wslview`), which `opencode` deliberately has not. The URL
must be computed **as opencode** (only that side sees the rootless daemon
— as the developer, ddev would decide "not running" and internally
`ddev start` on every call) and then opened **as the developer**. The
`ddev()` shell function routes the whole class through
`_opk_ddev_browser` (ddev-as-opencode.sh); the user-facing story is in
[ddev integration](../concepts/ddev-integration.md).

## 2. Current transport: `ddev describe -j` (issue #20 rework)

Upstream-recommended scripting interface
([ddev/ddev#8771](https://github.com/ddev/ddev/issues/8771)). The arm runs
`ddev describe -j` as opencode via the sudoers helper and maps the command
to a field:

| Command | Field(s) |
|---|---|
| `launch` | `raw.primary_url` + argument forms (below) |
| `mailpit` | `raw.mailpit_https_url` / `raw.mailpit_url` (scheme matched to `primary_url`) |
| `xhgui` | `raw.xhgui_https_url` / `raw.xhgui_url`, only when `raw.xhgui_status` = `enabled` |
| `phpmyadmin`, `adminer`, conf-registered | `raw.services.<name>.https_url` / `.http_url` |

Properties that made it the choice:

- **Works while stopped.** All mapped fields are config-derived; ddev even
  lists compose-defined-but-stopped services with their URLs (from the
  compose `HTTP(S)_EXPOSE` env). No ddev invocation side effects needed
  before the URL is known.
- **Stable contract.** The JSON is a single line (logrus
  `{"raw":{...},"msg":...}`) — parsed with python3, already a kit
  prerequisite.
- **No logging side effects** — unlike the debug transport it replaced.

`launch` argument handling mirrors ddev's launch script: `-m`/`--mailpit`/
`--mailhog` switch to the Mailpit URL, `-p`/`--phpmyadmin` declines to a
plain run (ddev prints its add-on hint there), `--` ends flags; one
positional then applies — full URL as-is, `:<port>` replaces the primary
URL's port (keeping its scheme — the launch script additionally probes
describe for the scheme; both agree in standard setups), anything else is
appended as a path (`${base%/}/${1#/}`).

Behavior parity kept by the arm:

- A stopped project is **started first** (like the launch script), with
  the same hints a direct `ddev start` prints: `_opk_bootstrap_hint`
  before, `_opk_hosts_hint` (the `opk ddev-hosts-add` bridge) after.
- Commands whose URL describe does not carry — the built-in phpmyadmin
  installer prompt (add-on not yet installed), custom commands without a
  matching service, invocations outside a project — **plain-run as
  opencode**: output, prompts and exit code pass through; only the
  browser open is skipped.
- The URL is printed on stdout and opened as the developer
  (`explorer.exe`, fallback `xdg-open`).

## 3. Removed transport: `DDEV_DEBUG` / `FULLURL` (0.0.19 – 0.0.25)

The launch script prints `FULLURL <url>` and exits 0 instead of opening a
browser when `DDEV_DEBUG=true`/`DDEV_VERBOSE=true`. The old arm ran the
browser command as opencode under `DDEV_DEBUG`, captured the `FULLURL`
lines, filtered them from the visible output and opened the last one.
Removed because debug logging is global to the whole invocation: on a
stopped project the launch script's internal `ddev start` produced a wall
of timestamped debug output before the URL appeared (the original
complaint in ddev/ddev#8771). Also dropped: `DDEV_DEBUG` from the sudoers
`env_keep` it needed to survive `sudo -u opencode`.

## 4. Alternatives considered (deferred / upstream)

### `ddev launch --print-url` + `DDEV_LAUNCH_PRINT_URL` — merged, released, not adopted

[ddev/ddev#8772](https://github.com/ddev/ddev/pull/8772) added a
`--print-url` flag (and the `DDEV_LAUNCH_PRINT_URL` env var, so nested
launch children of wrapper commands inherit it) that prints the composed
URL — no prefix, exit 0 — instead of opening a browser. **Merged and
released in ddev v1.25.4** (issue #61). It is attractive wherever the
**composed** URL matters: ddev itself would apply the `launch` argument
handling the kit currently replicates in shell.

**Decision: the kit stays on `ddev describe -j`** (issue #61):

- **Version floor.** The flag exists only in ddev ≥ 1.25.4; the kit
  supports ≥ 1.25.0. On older ddev the launch script's unknown-option
  branch *ignores* `--print-url` and falls through to the browser open —
  as opencode, without interop, the exact failure this arm exists to
  prevent. A switch would need a version probe plus a second code path;
  "one interface, one code path" was the deciding principle in 0.0.26.
- **Service URLs.** `--print-url` composes only the primary/Mailpit URL
  (plus argument forms). The phpMyAdmin/adminer/xhgui URLs come from
  describe's `raw.services.*` (with the add-ons' custom ports) —
  describe stays the uniform source either way.
- **Stopped-project output.** The v1.25.4 launch script still
  auto-starts a stopped project (`ddev start` output first, URL as the
  last stdout line). The kit's arm runs that start itself so the
  bootstrap/hosts hints keep their place around it; delegating would
  bury them and require last-line scraping.
- **Side-effect-free probe.** Describe fields are config-derived: the
  URL is known before anything starts; starting stays the arm's own
  explicit decision.

Revisit when the kit raises its minimum ddev to ≥ 1.25.4 **and** ddev
can print service URLs (or the add-on wrappers compose them) — then
`DDEV_LAUNCH_PRINT_URL=true` could replace both the shell argument
replication and the describe mapping for launch/mailpit in one code
path again.

### Global host-command env — rfay's suggestion

Host commands can be global (`~/.ddev/commands/host/<name>` — ddev's own
`launch`/`mailpit`/`phpmyadmin` ship exactly there; for the kit:
`/home/opencode/.ddev/commands/host/`, inside the ddev home we already
provision). Dispatching one injects `DDEV_PRIMARY_URL`,
`DDEV_PRIMARY_URL_PORT`/`_WITHOUT_PORT`, `DDEV_SCHEME`,
`DDEV_MAILPIT_*`, `DDEV_XHGUI_HTTP(S)_PORT`, … — enough to compute the
primary, Mailpit and xhgui URLs without JSON parsing (and without the
python3 dependency). Deferred because:

- **No per-service env.** The phpMyAdmin add-on's URL exists only in
  describe (`raw.services.phpmyadmin.https_url`); the add-on hardcodes
  its ports (8036/8037) inside its own command — hardcoding them kit-side
  breaks on custom ports.
- Still one ddev invocation from the wrapper (the dispatch); "no `ddev`
  invocation" only means the command itself would not call ddev
  internally, replacing the `describe` call.
- A kit-shipped global command appears in every project's `ddev --help`
  and is another file the kit must deploy/update.

Combining both (env for the built-ins, describe for services) was
considered and rejected for now: one interface, one code path.

## 5. Upstream source map (pinned v1.25.4)

For re-verification when a new ddev release lands — paths refer to the
read-only checkout in the dev workspace (`github/ddev`, tag v1.25.4; not
shipped with the kit). Re-verified for v1.25.4 at issue #61; unchanged
in substance from the v1.25.3 map.

- `pkg/ddevapp/ddevapp.go` — `Describe()` (line 232): the `raw` map.
  `primary_url` (line 258), `mailpit_https_url`/`mailpit_url`
  (lines 253–254), `xhgui_https_url`/`xhgui_url` are config-derived
  (present when stopped); `services` is filled from running containers
  **and** from compose-defined stopped services (URLs built from their
  `HTTP(S)_EXPOSE` env; mailpit ports excluded).
- `pkg/ddevapp/ddevapp.go` (~line 3006) — the env block injected into
  host-command dispatch (`DDEV_PRIMARY_URL`, `DDEV_SCHEME`, mailpit and
  xhgui ports, …; no per-service variables).
- `pkg/ddevapp/global_dotddev_assets/commands/host/launch` — the launch
  script: auto-start when not running, the argument forms above, the
  `FULLURL`-under-debug contract, and since v1.25.4 the
  `--print-url`/`DDEV_LAUNCH_PRINT_URL` branch (print the bare URL,
  exit 0) *before* the debug and browser branches. Unknown options are
  warned about and ignored — older ddev silently degrades
  `--print-url` into a browser open (see §4). The `:port` argument
  handling shells out to `docker run ddev/ddev-utilities` helpers and
  re-consults `ddev describe -j` for the scheme.
- Same directory: built-in `mailpit` (just `ddev launch -m`) and built-in
  `phpmyadmin` (interactive add-on installer — the launcher is the
  add-on's own project-level command, which calls `ddev launch :<port>`;
  its Gitpod branch even uses the `DDEV_DEBUG`/`FULLURL` grep trick).
- `cmd/ddev/cmd/describe.go` — JSON emission (line 72):
  `output.UserOut.WithField("raw", desc)` through logrus' JSONFormatter:
  one line, `raw` nested at the top level.

## 6. Tests

- Unit: functional describe→URL mapping cases (fixtures mirroring the
  ddev field set) in `tests/test-ddev-as-opencode.sh` §3a.
- e2e: the fake ddev implements the describe contract, records callers,
  and models the stopped→running start flip; a planted `/mnt/c` hosts
  file + custom-tld fixture proves the hint parity — `tests/e2e/run.sh`
  section 4b.
