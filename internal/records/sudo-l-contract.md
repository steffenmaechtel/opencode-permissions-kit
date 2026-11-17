# sudo -l's exit codes — why the sudo-rules row keys on answer text

> Status: **CURRENT** (living reference). Measured 2026-11-17 against real
> sudo 1.9.15p5 — a root container (opencode-e2e image) and the target
> host (maintainer probe). Origin: issue #569 M3. The general lesson —
> claims about an external tool's behavior must be measured against the
> tool, not inherited from an issue's fix direction — is
> [agent/test-fidelity.md](../../agent/test-fidelity.md)'s class; this
> record is that class's sudo instance (the issue's "observe the probe's
> own rc" direction is measurably insufficient, see §2).

## 1. The question

status.sh's root-equivalent audit renders a "sudo rules" row for the agent
user. The probe is `LC_ALL=C sudo -n -l -U "$OPENCODE_USER"`, run as root
(the row is root-only). Issue #569 M3's fix direction was "observe the
probe's own rc". Measurement shows rc alone cannot carry that fix: no rc
value separates the healthy state from two broken ones, and the healthy
state's rc differs between sudo generations.

## 2. The measured matrix (sudo 1.9.15p5)

| State | rc | stdout | stderr |
|---|---|---|---|
| healthy, user has no rules | 0 | `User <u> is not allowed to run sudo on <host>.` | empty |
| user has rules | 0 | listing (`User <u> may run the following commands …` + indented runas lines) | empty |
| sudoers.d broken (non-fatal) | 0 | answers anyway (not-allowed OR the listing) | syntax-error diagnostic |
| fatal sudoers damage / unknown `-U` user | 1 | empty | diagnostic |

The non-fatal stderr diagnostic is `<file>:<line>:<col>: syntax error …`
(sudo 1.9; the 1.8-era spelling is `>>> <file>: syntax error near line N`).

Re-measure with (root container):

```sh
docker run --rm --user root opencode-e2e:latest bash -lc '
  useradd -m foo
  out=$(LC_ALL=C sudo -n -l -U foo 2>/tmp/err); rc=$?
  echo "none:   rc=$rc out=[$out] err=[$(cat /tmp/err)]"
  printf "foo ALL=(ALL) NOPASSWD: /bin/true\n" >/etc/sudoers.d/foo; chmod 440 /etc/sudoers.d/foo
  out=$(LC_ALL=C sudo -n -l -U foo 2>/tmp/err); rc=$?
  echo "rules:  rc=$rc err=[$(cat /tmp/err)]"
  rm /etc/sudoers.d/foo
  printf "not valid ((\n" >/etc/sudoers.d/broken; chmod 440 /etc/sudoers.d/broken
  out=$(LC_ALL=C sudo -n -l -U foo 2>/tmp/err); rc=$?
  echo "broken: rc=$rc out=[$out] err=[$(cat /tmp/err)]"
'
```

Production confirmation (target host, maintainer probe, 2026-11-17):
`LC_ALL=C sudo -n -l -U opencode` →
`User opencode is not allowed to run sudo on PC-2025-SM.` rc 0.

NOT measured: sudo 1.8.x. Documented expectation from historical sudo
EXIT-STATUS semantics: the no-rules state answers rc 1 with the same
stdout text. The decision below does not depend on which generation runs.

## 3. The decision

The green "none" verdict keys on sudo's ANSWER TEXT — `is not allowed to
run sudo` (modern) / `may not run sudo` (older spelling) — matched over
the MERGED stdout+stderr capture. rc is reported in the unknown row's text
only; it never selects a verdict. Full verdict order (visible rules win —
they are real even when another sudoers.d fragment is broken):

1. listing pattern (header or any indented runas line, the S3/W3 shape,
   LC_ALL=C pinned at the probe) → red "may run sudo"
2. `syntax error|parse error` anywhere in the capture → uncounted
   "unknown — sudo reported a sudoers problem"
3. no-rules answer text → counted green "none"
4. anything else (silent probe: fatal sudoers damage, unknown user,
   password demand) → uncounted "unknown — sudo -l answered nothing (rc N)"

Why stderr is merged into the capture: sudo's diagnostics have moved
between streams across versions, so matching is stream-agnostic; no
diagnostic shape can false-match the listing pattern (diagnostics are
`sudo:`- or path-prefixed at column 0, listings' runas lines are the only
leading-whitespace `(`-shapes). Benign stderr noise — `unable to resolve
host`, common on WSL — matches no marker and does not flip the verdict
(pinned).

## 4. Where the code and pins live

- Helper: `status_sudo_verdict` in
  `files/opencode-permissions-kit-lib/sh/status-core.sh` (pure, no root
  needed) — rendered by `status_section_root_equiv`.
- Pins: `tests/unit/test-status.sh` — 7 verdict asserts (incl. rc-1
  no-rules tolerance, benign-noise, rules-precedence, translated-header
  replay of the real pattern) + 4 stubbed section scenarios (PATH-stubbed
  `id`/`sudo` drive the real section body through all four states).
