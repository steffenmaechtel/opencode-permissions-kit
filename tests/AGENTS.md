# AGENTS — tests/

Auto-loads on read/list under `tests/` (path-triggered, not
shell-triggered): the test-tree invariants, moved verbatim from
agent/conventions.md (issue #768). Rationale: the metas; wave
mechanics: ../agent/gates.md.

## Test sandbox (unit suites)

Unit suites run on contributor and CI hosts, not in containers — they
must never create, delete or re-permission anything outside their own
scratch space, and never carry real-tree path literals at all. Rules
(finding history: 0.0.42e C1, executed as a live incident on an external
review host):

- Operate only on the suite's scratch (`$WORK`, `mktemp`) and the
  sanctioned temp prefixes `/tmp`, `/var/tmp` (plus `/dev/null`). (RM-0014)
- Never touch real project or system trees — `/var/www/vhosts`, `/home`,
  `/srv`, `/etc`, ... — **not in setup, not in teardown**: a cleanup
  `rm -rf` on a fixed host path deletes real data wherever the path
  happens to exist. (RM-0015)
- Fixture data is written **sandboxed at the source** (heredocs,
  registries, configs carry `/var/tmp/...` paths directly). Inert
  real-tree literals behind a later rewrite are forbidden too — they are
  one broken rewrite away from live (the migrate fixtures carried them
  for months behind a `sed` that a wave then dropped; maintainer
  directive 2026-10-04). (RM-0016)
- Every path a fixture REFERENCES — not just executes — is
  scratch-owned: a symlink's target, a grep needle's input file, a
  comparison baseline. An existence assert through the reference
  resolves the HOST path (`test -e`/`-x` through a link follows to
  the target), so the pin greens wherever the host happens to carry
  the path and reds where it does not — a foreign-symlink fixture
  linked `/etc/sudoers.d/README`, green locally and CI-red on the
  runner (PR #746 round b D5, unit lane red on ef5be2da; issue #749
  incident 2). (RM-0208)
- An `rm` — any flag form (`rm`, `rm -f`, `rm -r`, `rm -rf`, `rm -fr`,
  …), any operand position — on a variable **with a literal suffix**
  (`rm -rf "$WORK/sub"`, `rm -f "$WORK/mark"`, `rm -rf "${WORK}/sub"`,
  `rm -rf "$WORK"/sub`, `rm -rf $WORK/sub` — every spelling degenerates
  the same way on an empty variable) must guard the variable with `:?`
  (`rm -rf "${WORK:?}/sub"`): an empty or unset variable degenerates the
  operand to a fixed absolute path (`/sub`) instead of the harmless
  empty-operand no-op of the pure-variable form.
  Pure-variable operands (`rm -f "$CONF"`) are deliberately exempt.
  Destructive permission verbs (`chmod`/`chown`/... with `"$VAR/suffix"`)
  stay unguarded by design: fixture setup uses them heavily, they are
  not deletion, and a degenerate target fails on permissions for the
  non-root suite user. (RM-0003)
- Scratch receivers in harness-sourcing suites register with the
  **work registry** (`WORK="$(work_new)"`,
  `F="$(work_new_file)"`, `work_register "$P"`,
  `work_register_var NAME` — issue #395): the central EXIT INT TERM
  trap in `tests/unit/lib/harness.sh` collects them on exit, abort and
  signal, ending the #283 leak class structurally. A converted suite
  carries **no trap statement of its own** — its local trap would
  replace the harness trap and silently disarm the registry; the
  sandbox floor flags that mix. Suites not yet converted keep their
  local trap unchanged until their conversion wave.
  (RM-0137)
- The decision rule for writing NEW scratch: a suite that sources
  `lib/harness.sh` takes scratch from `work_new` (dir) /
  `work_new_file` (file) — never a raw `$(mktemp …)` receiver, which
  registers nothing and tempts a local trap that would disarm the
  registry (the trap floor flags the mix mid-wave, #523 §4);
  standalone suites keep their own mktemp + trap idiom. (RM-0151)
- Code extracted from shipped scripts and eval'd or run by a test
  executes under a **controlled PATH**, never the inherited host PATH:
  any `command -v` inside the extracted block must not see tools that
  merely happen to be installed on the contributor's machine. The
  0.0.48 release blocker: the status verdict matrix evals a block whose
  `command -v openchamber` found the maintainer's nvm-installed
  OpenChamber, flipping the "without OpenChamber" cases red on local
  `make release` while CI (no OpenChamber) stayed green — the
  0.0.46a F2 environment-dependence class. Build a scratch bin with
  symlinks to the block's few externals instead of rewriting the probe
  lines away — the real probe keeps executing (0.0.47c C1 direction). (RM-0017)
- A harness env override consumed through `:-` carries a non-empty
  controlled value: `:-` substitutes on EMPTY as well as unset, so
  `VAR=""` does not override `${VAR:-default}` — the harness silently
  reads the real host state behind the empty string (an m3 arm passed
  `ROOT_EQUIV_SOCKS=""` and scanned the REAL socket list plus ambient
  /mnt/wsl mounts, pr-00590 round a T1). An assert whose outcome
  depends on ambient host state is environment-dependent — learnings
  L4's marking duty applies. (RM-0173)
- The controlled PATH of an extracted-block run enumerates EVERYTHING
  the run can reach, not just the block's first-line externals:
  (i) fallback arms inside the pinned block (the sha256sum→shasum
  macOS class), (ii) every external the STUBS call internally (a stub
  body's `cat` outside the PATH kills every arm, rc 127), and
  (iii) every variable the block expands in message strings is set by
  the runner even on failure paths — unset under `set -u`, the die
  line dies with the shell's unbound-variable diagnostic
  (`parameter not set` in dash, `unbound variable` in bash) instead
  of its message (all three probed 2026-11-18, #616). (RM-0179)

Enforced by `tests/unit/test-sandbox-policy.sh`, three checks over every
unit suite (backslash-continued commands are joined first; full-comment
lines are skipped):

1. **Mutation check** — a mutating verb (`rm`, `mkdir`, `chown`,
   `setfacl`, ...) whose operand is a literal absolute path outside the
   sanctioned prefixes fails, quoted or unquoted (a quoted literal
   operand fails like its unquoted form — #727 closed the
   quote-blanking gap that made `rm -rf "/srv/x"` invisible outside
   the ratchet trees). Source-to-destination verbs (`cp`, `mv`,
   `ln`, ...) flag only the destination; `sed` only with `-i`.
   Variables are exempt — what they hold is the review's job. (RM-0042)
2. **Real-tree ratchet** — any path-shaped literal starting with a
   real-tree prefix (`/var/www` — the whole family, vhosts included,
   since issue #807 wave 1 —, `/srv/other/outside`) fails,
   quoted or not, in fixture strings as much as in commands.
   Policy-INPUT classes — values handed to
   screening/parsing functions or parse-only argument fixtures, never
   executed as paths — are allowlisted in the suite with reasons, and
   an ALLOW row can never cover a mutation finding (#727: the
   screener consults the allowlist for ratchet findings only, so the
   exception channel cannot hide an `rm -rf` operand however long it
   grows). New fixtures are written against fictional open prefixes
   (`/home/some-user-max-mustermann/...` — a home no real host
   carries): the goal is ZERO real host paths in unit tests
   (maintainer directive, issue #727). Enforced today are the ratchet
   trees plus the bound class — a real-tree literal is legitimate
   only where the literal IS the assertion's subject (a source pin
   that must match shipped bytes, a policy control row), named by an
   in-place bound comment plus the ALLOW entry's reason. Real-prefix
   literals OUTSIDE the trees fall into recorded classes: a residual
   sweep deferred to issue #807 wave 2 (host-specific homes — the
   /home/dev fixtures and the agent-home rows; the /var/www family
   without vhosts joined the enforced trees in #807 wave 1), the
   blocklist pins' own subjects
   (FHS system-path literals, /etc/nginx, /root/projects, ...), and
   WSL-context subjects (the /mnt/c mkcert source pins and the
   /mnt/ wsl.conf fixtures — shipped-bytes and conf-fixture
   subjects, not blocklist rows). All inert policy-INPUT —
   recorded, never silently sanctioned.
   Unit-suite-scoped: e2e scripts legitimately name container paths
   (/var/www/vhosts fixtures), so they are not in this check's scope.
   (RM-0043)
3. **rm suffix guard** — any `rm` invocation (flag order and operand
   position aware, statement-scoped) on a variable with a literal suffix
   must carry the `:?` empty-variable guard — quoted unbraced
   (`"$V/x"`), quoted braced (`"${V}/x"`), slash-outside-the-quotes
   (`"$V"/x`) and unquoted (`$V/x`) spellings alike; pure-variable
   operands are exempt (an empty operand is a verified rm no-op — the
   dangerous shape is the suffix). Scope: the unit suites AND the e2e
   helper scripts (`tests/e2e/**/*.sh`). The same `:?` standard
   applies to shipped code's `rm` var+suffix sites, root context
   included: new sites must not regress it (convention, enforced by
   review — the unit guard's scan deliberately stops at tests/). The statement scoping is chain-based,
   not a parse — an unquoted semicolon or redirect boundary breaks
   the chain, but every token INSIDE the span is walked: MESSAGE
   PROSE on a live line can match too — a literal `rm` inside a
   fail/pass message, with only single-space-separated words between
   it and a quoted `"$VAR/suffix"` literal, walks the same middle and
   tail (the #601 chmod arm's fail message tripped it, one red cycle,
   PR #628 — say `remove` in prose near quoted path literals, #630).
   (RM-0044)

The suite self-probes all three checks (continuation-split `rm`, inert
and quoted and redirect-glued literals, the bare /var/www-family
literal (#807 w1), the unguarded suffix shapes —
flag orders, bare `rm`, multi-operand — vs the guarded ones, a clean
sandboxed control, and the #727 arms: an ALLOW row never suppressing
a mutation, quoted literal operands caught in both quote arms, a
quoted `#` keeping the later segment visible, and the ALLOW block
rendering its entries verbatim) so the guard itself cannot rot
silently.
