# DDEV-URL-TRANSPORTS: how browser commands get their URL

> Status: **IMPLEMENTED (since 0.0.26, PR #50).** The kit reads browser-command
> URLs from `ddev describe -j`. This record documents that transport, the
> removed one it replaced, the upstream alternatives considered, and where
> each fact lives in the ddev source (pinned v1.25.3) so it can be
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

### `ddev launch --print-url` + `DDEV_LAUNCH_PRINT_URL` — our upstream PR

[ddev/ddev#8772](https://github.com/ddev/ddev/pull/8772) adds a
`--print-url` flag (and env var, so nested launch children of wrapper
commands inherit it) that prints the composed URL and exits 0. **Kept
open** after maintainer feedback: rfay would prefer this usage over the
`DDEV_DEBUG=true ddev launch` trick ddev uses in its own tests. If it
merges, it is attractive wherever the **composed** URL matters — ddev
itself would apply the `launch` argument handling we currently replicate
in shell. The kit does not depend on it (describe works on released
ddev); a later transport switch or combination is an open follow-up.

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

## 5. Upstream source map (pinned v1.25.3)

For re-verification when a new ddev release lands — paths refer to the
read-only checkout in the dev workspace (`github/ddev`, tag v1.25.3; not
shipped with the kit):

- `pkg/ddevapp/ddevapp.go` — `Describe()` (~line 223): the `raw` map.
  `primary_url`, `mailpit_https_url`/`mailpit_url`,
  `xhgui_https_url`/`xhgui_url` are config-derived (present when
  stopped); `services` is filled from running containers **and** from
  compose-defined stopped services (URLs built from their
  `HTTP(S)_EXPOSE` env; mailpit ports excluded).
- `pkg/ddevapp/ddevapp.go` (~line 2910) — the env block injected into
  host-command dispatch (`DDEV_PRIMARY_URL`, `DDEV_SCHEME`, mailpit and
  xhgui ports, …; no per-service variables).
- `pkg/ddevapp/global_dotddev_assets/commands/host/launch` — the launch
  script: auto-start when not running, the argument forms above, and the
  `FULLURL`-under-debug contract at the end.
- Same directory: built-in `mailpit` (just `ddev launch -m`) and built-in
  `phpmyadmin` (interactive add-on installer — the launcher is the
  add-on's own project-level command, which calls `ddev launch :<port>`;
  its Gitpod branch even uses the `DDEV_DEBUG`/`FULLURL` grep trick).
- `cmd/ddev/cmd/describe.go` — JSON emission:
  `output.UserOut.WithField("raw", desc)` through logrus' JSONFormatter:
  one line, `raw` nested at the top level.

## 6. Tests

- Unit: functional describe→URL mapping cases (fixtures mirroring the
  ddev field set) in `tests/test-ddev-as-opencode.sh` §3a.
- e2e: the fake ddev implements the describe contract, records callers,
  and models the stopped→running start flip; a planted `/mnt/c` hosts
  file + custom-tld fixture proves the hint parity — `tests/e2e/run.sh`
  section 4b.
