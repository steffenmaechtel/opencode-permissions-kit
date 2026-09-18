# Test fidelity — why some bugs only real users hit

> Status: **CURRENT (reference).** Why kit bugs can pass unit and e2e
> and still break in a real user's terminal, which bug classes live in
> those gaps, and the patterns and tools that close them. Motivating
> incident: commit `b14a198` (ddev consumed the export loop's stdin —
> one database dump per run, production finding; see the partial-export
> entry in [troubleshooting](../troubleshooting.md)). The real-ddev
> answer to one instance of the class is
> [ddev-e2e-test.md](ddev-e2e-test.md); this record generalizes it.

## 1. The execution environments

The kit's code runs in at least three environments that differ in more
ways than "interactive vs not". Bugs survive in the differences:

| | Real user terminal | Agent bash session | Unit suite / e2e |
|---|---|---|---|
| stdio | **PTY** on all three fds (`[ -t 0 ]` true) | no TTY; stdin not a keyboard | no TTY; stdin `/dev/null`, pipe, or `docker exec` EOF |
| stdin semantics | a reading program **blocks visibly** (the user sees it) | a reading program gets EOF or silently drains a pipe | same — but test doubles may not read at all |
| Shell startup | interactive/login: rc files loaded → **`ddev()` function, `BASH_ENV` hook, PATH, umask exist** | non-interactive: no rc files | non-interactive; functions sourced explicitly |
| Program behavior | colors, progress bars, TUI probing, prompts (`isatty()` branches all taken) | branches for non-tty | same |
| Signals/job control | Ctrl+C → foreground process group; sudo asks via `/dev/tty` | no controlling terminal | no controlling terminal |
| Binaries | the **real** ddev/docker/opencode | real docker (rootless daemon), real kit scripts | `fake-ddev`, unit shims |

The agent bash session is *not* a proxy for the user terminal: it runs
as the `opencode` user inside the wrapper's environment — closer to
production than CI, but rc-file loading, TTY, and interactive prompts
are all absent there too.

## 2. The bug classes that live in the gaps

### 2.1 stdin semantics — the `b14a198` class

The production bug: `ddev-migrate export` looped over projects via
`printf '<list>' | while read ...` and called ddev per project. Real
ddev probes stdin (prompt/TUI detection) and **consumed the remaining
project list** on the first call — `read` hit EOF, the loop ended after
one project, and the resume logic made each re-run dump exactly the next
one. The import loop had the same class (its stdin was the manifest
itself).

Two lessons:

- **Call sites:** every child process invoked inside a data-driven loop
  gets an explicit `</dev/null` unless it genuinely needs stdin. The
  child's stdin behavior is not the loop's to rely on — util-linux'
  own `script(1)` documents the same trap ("avoid use of script in
  command pipes, as script can read more input than you would expect").
- **Doubles:** the e2e `fake-ddev` never read stdin — the suite was
  structurally unable to catch the bug. The fix taught the fakes the
  behavior: the unit fake eats stdin under `DDEV_EAT_STDIN=1`, the e2e
  fake reads stdin unconditionally (`docker exec` provides EOF).

### 2.2 rc-file loading — the hook installation class

The `ddev()` shell function and the `BASH_ENV` hook only exist in
shells that loaded the developer's rc files. Unit and e2e source the
function directly, so the path "fresh login shell of a real user" is
never exercised — vendor `runTests.sh` under `#!/bin/sh`, cronjobs, and
IDE tasks ran real ddev as the wrong user (troubleshooting entry;
original transport issues #18). Covering it requires spawning real
login/interactive shells (`bash -lic '...'`, `su - <user> -c '...'`),
not sourcing.

### 2.3 `isatty()`-conditional behavior

Programs switch on TTY detection: colors, progress, and — critically —
**prompting**. The kit's own countermeasure is in `ui.sh`: prompts read
from `/dev/tty`, never stdin, because under `curl | bash` stdin *is the
script stream* (same class, other direction). Testing prompt flows
therefore needs a PTY (§4.4); with piped stdin a `read` either gets EOF
or eats test data.

### 2.4 Signal and job-control differences

Interactive shells run job control (process groups, `SIGTTIN`/`SIGTTOU`
suspension, Ctrl+C delivering SIGINT to the foreground group). Kit code
that spawns daemons or long-running children can behave differently when
killed, and sudo password prompts go through `/dev/tty` — impossible
without a terminal. Lower-frequency class for this repo, but the reason
`sudoers` entries are provisioned rather than interactively prompted
during e2e.

## 3. Terminology: test doubles and fidelity

Following Fowler/Meszaros ("Mocks Aren't Stubs"): a **test double** is
any stand-in for a real dependency; the relevant kinds here are

- **stub** — canned answers, no behavior;
- **fake** — working lightweight implementation (the kit's `fake-ddev`);
- **mock** — pre-programmed call expectations.

The incident was a **fidelity gap**: the fake was faithful to the
calls/outputs the tests asserted, but not to an I/O side effect the
production code path touched (draining stdin). Rule for this repo:

> A double must replicate every observable behavior the code under test
> can touch — arguments, exit codes, output, **and stdio side effects**
> (stdin consumption, tty probing). When the real binary surprises you,
> encode the surprise in the double plus a regression test, so the
> fidelity is locked.

## 4. Patterns that close the gaps

1. **Behavioral doubles + contract lock** (cheap, hermetic — first line
   of defense). When real-binary behavior bites, the double learns it
   (`DDEV_EAT_STDIN`) and a regression test keeps it.
2. **Real-binary tiers** (expensive, authoritative — the `e2e-ddev`
   golden-image suite). Where a fake's fidelity can't be trusted
   (ddev's chmod/mutagen/router behavior), run the real thing; cache the
   provisioned environment so repeat runs stay cheap. Keep coverage of
   each loop/plumbing path there too, not only happy-path lifecycles —
   the stdin bug was in a loop the real-binary suite did not drive
   (shipped since 2026-09-18: suite section DD15 drives both
   ddev-migrate loops with real ddev; the import-loop check is
   mutation-verified — removing its `</dev/null` makes only the first
   project import. Caveat learned there: a FAILING real ddev never
   reaches its stdin probing, so a fail-path scenario proves loop
   survival only — the drain itself needs the success path).
3. **Environment matrix as a test dimension.** For flows that read any
   fd, run the scenario against stdin variants: closed (`<&-`), EOF
   (`</dev/null`), pipe-with-data (`< <(printf ...)`), and PTY (§4.4).
   A bug in one variant is a bug.
4. **PTY harnesses**, by weight:
   - `script -qec '<command>' /dev/null` (util-linux) — gives the
     command a real PTY in any CI script; cheap enough for one check
     per prompt flow: does it ask, does it accept the default, does the
     default-fallback work.
   - **pexpect** (Python) / **expect** (Tcl) — spawn, `expect` a
     pattern, `send` input; the tool for multi-step dialogues (the
     installer's y/n chains). pexpect documents the flip side: programs
     *only* show interactive behavior when they detect a terminal.
   - **tmux** (`send-keys`/`capture-pane`) — pragmatic harness for TUI
     surfaces (the kit-mode TUI) where even pexpect gets awkward.
   - `bash -lic '<cmd>'` / `su - <user> -c '<cmd>'` — not a PTY, but
     exercises rc-file loading (§2.2).
5. **Recording real sessions** to derive double contracts: `script
   --log-io` (input+output streams, timing) or asciinema capture of a
   real run — then codify the observed stdio behavior into the fake.
   Cheapest way to keep fakes honest without running real binaries in
   every suite.

## 5. Framework options for shell tests

The kit's unit tier is plain `sh` test scripts + ShellCheck + docker
e2e — hermetic and dependency-free; keep that. If the unit tier
outgrows it, the candidates in the shell-testing ecosystem:

- **shellspec** — BDD framework for dash/bash/all POSIX shells with
  first-class **command-based mocks** (`Mock` directive), a `--sandbox`
  mode that forces mocks over real commands, a `Data` directive for
  stdin control, parameterized examples, parallel runs, kcov coverage.
  The mock/sandbox model directly addresses double fidelity — but a
  framework alone does not fix fidelity; the behavioral lessons above
  apply in any framework.
- **bats-core** (+ bats-assert/bats-support) — the other mainstream
  choice; no built-in mocking discipline.
- **pexpect/expect/tmux** — not unit frameworks; PTY harnesses for the
  interactive tier (§4.4).

Adopting either is a maintainer decision; nothing here blocks on it.

## 6. Checklist for new kit code

- Child process inside a `while read`/pipe loop → `</dev/null` at the
  call site unless stdin is genuinely wanted (audit the existing
  call sites when touched).
- Prompt → `read </dev/tty` via `ui.sh` helpers, never bare stdin.
- New fake/shim → replicate the real binary's stdio behavior (stdin
  consumption, tty probing), and add a contract/regression test that
  would fail if the double regressed or the real binary changed.
- rc-installed behavior (functions, hooks, PATH) → needs a
  fresh-login-shell check in e2e, not just sourced-function unit tests.
- Interactive-only surfaces (browser launch, Windows hosts file) →
  assert the container-side half only, as `e2e-ddev` does (non-goal
  there: the Windows side).

## References

- Commit `b14a198` — the stdin-draining production bug and the
  double-fidelity fix (regression tests both tiers).
- [ddev-e2e-test.md](ddev-e2e-test.md) — the real-ddev golden-image
  suite; §1 names the fake-ddev coverage gap this record generalizes.
- Martin Fowler, *Mocks Aren't Stubs* — test double vocabulary
  (dummy/fake/stub/spy/mock), classical vs mockist testing:
  <https://martinfowler.com/articles/mocksArentStubs.html>
- Gerard Meszaros, *xUnit Test Patterns* — the test double pattern
  catalog: <http://xunitpatterns.com/Test%20Double.html>
- shellspec — BDD unit testing framework for POSIX shells (mocking,
  sandbox, stdin control): <https://github.com/shellspec/shellspec>
- bats-core — bash automated testing system: <https://bats-core.readthedocs.io/>
- pexpect — spawn/expect automation over PTYs:
  <https://pexpect.readthedocs.io/en/stable/overview.html>
- `script(1)` — run a command under a PTY from any script (`-c`), and
  its own warning about stdin over-consumption in pipes:
  <https://man7.org/linux/man-pages/man1/script.1.html>

## Glossary

The terms this record leans on, in one place:

- **stdio** — the three standard streams every Unix process is born
  with: stdin (fd 0, input), stdout (fd 1, normal output), stderr
  (fd 2, error output). What they are *connected to* (terminal, pipe,
  file, `/dev/null`) is decided by whoever starts the process — that
  connection, not the program, is what differs between the
  environments in §1.
- **stdin** — standard input, fd 0: the stream a `read` reads from.
  May be a keyboard (via a TTY), a pipe, a file — or nothing at all.
- **TTY** — a terminal. Historically a hardware teletype; today a
  terminal emulator (Windows Terminal, GNOME Terminal) represented by
  a device file (`/dev/pts/N`). Programs probe with `isatty()`
  whether stdio is a TTY and switch behavior accordingly (colors,
  progress bars, prompts, input echo).
- **PTY** — pseudo-terminal: a kernel-provided *fake* TTY — a pipe
  pair with terminal line discipline in between. What a terminal
  emulator, `script(1)`, pexpect, or tmux hands a child process so it
  behaves as if a user were attached. The tool for §4.4.
- **Shell** — the program that reads and executes commands (bash,
  dash, zsh). *Interactive*: attached to a user's TTY, shows a
  prompt, loads rc files (`~/.bashrc` etc.) — where the kit's
  `ddev()` function lives. *Non-interactive*: executes a script or
  command string, loads no rc files (except `BASH_ENV`).
- **Pipe** — a one-way kernel buffer (`cmd | other`, `<(cmd)`)
  connecting one process's stdout to another's stdin — or feeding a
  loop's `read`. Piped data is consumed: once read, it is gone; there
  is no rewinding.
- **"gets EOF"** — end of file on stdin: no more data will ever come
  (writer closed the pipe, `/dev/null`, `docker exec` without `-i`).
  A `read` returns immediately with failure instead of waiting —
  programs take it as "no input available".
- **"drains a pipe"** — a child process inside a loop reads stdin it
  was never meant to have and consumes the data destined for the
  loop's next iterations; the loop starves and ends early. The
  `b14a198` mechanism (§2.1).
