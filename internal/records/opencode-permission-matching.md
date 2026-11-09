# opencode-permission-matching.md — how opencode matches permission rules

> Status: **CURRENT** — living reference for how opencode v1.18.x and
> v2.x evaluate `permission` rules (bash/shell focus), verified for
> issue #391 (the dead redirect-deny shapes). Where this record and the
> opencode sources disagree, the sources win. Anchors: opencode v1.18.15
> (`packages/opencode/src/util/wildcard.ts`, `permission/index.ts`,
> `tool/shell.ts`) and v2.2.6 (`packages/core/src/util/wildcard.ts`,
> `permission.ts`, `shell/scan.ts`, `config/normalize.ts`,
> `config/plugin/agent.ts`), both pinned under `github/` in this
> workspace, plus the maintainer's live tests in issue #391.

## 1. Why this exists

The template's redirect denies (`"> /dev/sd*"`, `">> /dev/sd*"`,
`"> /etc/*"`, `">> /etc/*"`, `"dd of=/dev/sd*"`) shipped for months
without matching a single realistic command: a bash rule is matched
against the whole command text, and no command text starts with `>`.
Two review rounds (#378 stray colon, #390 append forms) fixed spelling
variants of the same dead shape; issue #391's live tests proved the
whole class dead and drove the corrected shapes plus the verification
layers below.

## 2. The matching pipeline

Rule sources, in evaluation order (last match wins):

1. **v1 format** (`permission: { bash: { "<pattern>": "action" } }` in
   `opencode.jsonc`): `fromConfig` turns the object into rules in FILE
   ORDER (object key order). v2 migrates the same section verbatim —
   `ConfigMigrateV1.normalizeAction` renames the action key
   `bash` → `shell`, the pattern (resource) is unchanged — so one
   template serves both versions.
2. **v2 agent merge**: a config document's top-level `permissions` are
   pushed onto EVERY agent (`config/plugin/agent.ts`:
   `agent.permissions.push(...permissions)`). A session evaluates
   `merge(agent.permissions, session.permissions)` — global template
   rules first, project/session rules last (they win).
3. **Saved approvals** append AFTER the configured rules (both
   versions). Semantic difference: **v2 runs the deny check over the
   configured rules only** (`denied()` before saved rules join), so a
   saved "always allow" can never lift a configured deny. **v1.18.15
   evaluates findLast over configured + approved together** — a
   per-session prefix approval (`cmd *`) that matches a deny-command
   does override the deny there. The template's ask-by-default design
   keeps approvals rare and prefix-shaped; residual accepted for 1.x.

The matcher itself (both versions, identical semantics):

- anchored: the pattern must match the **whole** resource string
  (`^…$`)
- `*` → `.*` (any run, dot-all), `?` → `.` (**exactly one** character —
  an optional character is NOT expressible; there is no way to produce
  a regex quantifier from the pattern)
- regex specials escaped first; case-sensitive on Linux
- a trailing `" *"` is treated as optional (lets `ls *` match bare `ls`)
- **last matching rule wins**; no match at all → `ask`

## 3. The bash/shell resource construction

opencode does NOT match the rule against "the command" as one blob of
argv — the shell tool parses the command (tree-sitter) and derives one
**resource string per command**, and the resource INCLUDES redirects:

- v1.18.15 `tool/shell.ts`: `source(node)` returns the parent
  `redirected_statement` text — `echo x > /dev/sda` is ONE resource
  `echo x > /dev/sda`. Commandless redirects (`> /etc/passwd` alone)
  produce **no command node, hence no resource, hence no permission
  question at all** — a 1.x upstream gap no config rule can close.
- v2 `shell/scan.ts`: same per-command model, but commandless redirects
  DO produce resources (`>/dev/null` as its own head), and the redirect
  operator list (`BASH_REDIRECTS`) covers `>`, `>>`, `>|`, `&>`, `&>>`,
  fd-prefixed (`2>`) and `<>` forms.

Any resource hitting a deny blocks the whole tool call (v1 evaluates
per-pattern with an immediate deny return; v2 `denied()` = some()).

## 4. Consequences for rule shapes

- A rule with a **leading literal** only matches commands whose text
  starts with it — `sudo`, `time`, wrappers evade (`sudo mkfs…` matches
  no `mkfs*`). `docker *`/`sudo docker *` pairs in the template exist
  for exactly this reason.
- The operator-agnostic redirect shape `*>*/dev/<fam>` works because
  the inner `*` swallows operator token AND spacing: it matches
  `>`, `>>`, `>|`, `&>`, `&>>`, `2>`, `<>` — spaced, glued
  (`>/dev/sda`) and commandless (`> /etc/passwd`, v2) — every form
  where a `>` appears before a `/dev/<fam>` path in the same command.
- dd writes: `*dd*of=/dev/<fam>` catches `sudo dd …`, any argument
  order, any spacing.
- `/dev/*` must NOT be denied broadly: `> /dev/null` (incl. glued
  `>/dev/null 2>&1`, `2>/dev/null`) is an everyday sink — enumerate
  device families instead (sd, nvme, mmcblk, vd, xvd, hd).
- Later rules shadow earlier ones, so the template's ask tripwires
  (which sit AFTER the denies) can convert a deny into an ask when both
  match (`cat settings.php > /dev/sda` → ask, not deny). An ask still
  gates; accepted lexical shadow.

## 5. Verification layers (which layer proves what)

1. **Maintainer live tests** (issue #391 comments): real sessions,
   real agent, deployed config — proved the shape class dead and the
   corrected shapes firing.
2. **`tests/unit/test-template-bash-rules.sh`**: a matcher replica
   (anchored to the upstream sources and the live tests via a
   selftest pin) evaluates the REAL template over an attack/benign
   matrix — catches template regressions on every CI run.
3. **`tests/e2e/run.sh` section 3b**: the real binary with the
   deployed agent config — the `session.permission.create` HTTP route
   returns the evaluated effect, no LLM, no TUI. Closes replica drift:
   the real evaluator must agree with the replica.

The no-LLM seam is that HTTP route, **not** a CLI flag: the
`--validate-command` / `conversation --dry-run` commands floated in
issue #391's research comment are hallucinated — they exist in neither
v1.18.15 nor v2.2.6 (verified against both pinned sources; the
maintainer marked them in the issue accordingly). Probe mechanics: the
server always runs with a password (random unless `OPENCODE_PASSWORD`
is set — Basic auth, username `opencode`); the probe pins it via env
and pins the port; the route exists from v2.2.6 (older version pins
skip the probe).

**Warm-up race (measured on 2.2.6):** the HTTP listener answers ~1s
before the agent registry finishes mounting the config rules. A
permission ask in that window evaluates against the default agent's
allow-all and returns `allow` — for deny-shaped resources too. The
e2e probe therefore waits SEMANTICALLY: it polls a neutral warmup
resource (`echo x > /tmp/e2e-warmup`) until it evaluates `ask` — the
template's `"*": "ask"` catch-all being live in evaluation proves the
registry settled, without pre-asserting any deny shape the checks own.
(`GET /api/agent` showing the full rule set is NOT sufficient — it
settles ~1s before evaluation does.)

E2E probe result on the corrected template (opencode 2.2.6,
2026-11-09): all 7 probes green — spaced/glued/family redirects
denied, sudo dd denied, /etc denied, `> /dev/null` stays ask,
allowlisted `ls -la` stays allow. Full suite: 342 checks passed.

## 6. Accepted residuals

- v1.18.15 commandless redirects bypass the permission layer entirely
  (no resource is produced — upstream gap, config-side unfixable).
- Write tools are not redirects: `tee /dev/sda`, `cp x /dev/sda`,
  `mv x /dev/sda` match none of the redirect denies (same as before
  #391; a follow-up rule set would need per-family `*tee /dev/<fam>*`
  shapes with a `/dev/null` carve-out for `tee`).
- Device families not enumerated: `loop*`, `md*`, `sr*` (raw writes
  there are root-gated in practice; the whole block is defense in
  depth on top of Unix device permissions).
- Lexical-only matching (the template's own tripwire caveat applies):
  variables (`F=/dev/sda; echo x > $F`), indirection, and
  same-command false positives in the safe direction (a quoted string
  containing `> /dev/sd…`).
