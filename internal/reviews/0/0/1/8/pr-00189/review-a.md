<!-- review-meta
ID: pr-00189
Snapshot: a
Subject: issue-187 y/n prompt consistency (fix wave)
Scope: wave
Base: v0.0.50 @ d7a2d87
Diff: d7a2d87..43bd33e
Date: 2026-10-17
Reviewer: GLM-5.3 (house session, main agent — single-pass wave review, every finding verified against full-file reads and live gate runs)
-->

# Review — pr-00189 snapshot a — issue #187 y/n prompt consistency

> Resolution: [resolution.md](resolution.md)

Wave under review: `origin/master...HEAD` (2 commits, 9 files,
+183/−20): one marker-less y/n prompt shape and one answer semantics
across the three implementations — `sh/ui.sh`'s `ui_confirm` (reference),
`bin/opk`'s damaged-library fallback (mixed-case fix, issue #187 C),
`management/uninstall.sh`'s standalone `prompt_yn` (unknown-input and
marker fix, issue #187 A/B) — plus the conventions/rules-meta record
updates and behavioral pins in `test-ui.sh`, `test-uninstall.sh`,
`test-kit-cli.sh`.

**Verdict: 0 HIGH/MED. 2 LOW, 2 INFO — merge-ready.**

## Findings index

| ID | Severity | Provenance | Summary |
|---|---|---|---|
| W1 | LOW | pre-existing (gap), wave-introduced (2 new dependents) | `script(1)` is load-bearing for now 4 unit suites but absent from `tests/check-host.sh` |
| W2 | LOW | pre-existing (reads), wave-introduced (parity claim) | padded input (` y`) diverges across the "same semantics" prompts — uninstall trims, ui.sh/opk do not |
| W3 | INFO | wave-introduced (deliberate) | garbage under a y default now takes the YES path at the two y-default sites, incl. the wsl.conf consent prompt |
| W4 | INFO | wave-introduced | pty shape pins rely on input-echo-before-prompt ordering inside `script(1)`; near-deterministic, noted for flake triage |

## What the wave claims — verified

1. **#187 C (opk fallback mixed-case) — fixed.** Old arms
   `y|Y|yes|YES` mapped `Yes`/`No`/`yEs` to the default — an explicit
   No under a y default answered YES. New code lowercases before the
   match; the comment's semantics (y/yes/n/no case-insensitive,
   anything else → default, `/dev/tty`-only, fails closed) matches
   `ui.sh`'s `ui_confirm` exactly for the case arms. 5 pty pins in
   `test-kit-cli.sh` green, both mixed-case directions under both
   defaults, plus empty-input and both garbage defaults.
2. **#187 A (prompt_yn unknown → default) — fixed.** Old `*) echo n`
   ignored a y default; new `*)` echoes the default. 2 pty pins
   (`j` under y→y, under n→n) green; explicit `n|no` arm added (was
   missing as its own arm but covered by the old catch-all).
3. **#187 B (marker-less shape) — consistent.** All three
   implementations render `  <question> [y/N] ` (two-space indent,
   capitalized default, trailing space, no marker):
   `sh/ui.sh:202`, `bin/opk:44-45`, `uninstall.sh:140`. Class sweep:
   `grep -F '[?]' files/` → no hits; `(yes/no)`, `[yes|no]`, `Y/N`
   → no hits (RM-0007's extended check line holds). `test-uninstall.sh`
   adds a static no-marker ratchet; shape pins in all three suites
   green.
4. **Class sweep — no missed sibling sites.** `install.sh` prompts go
   through `ui.sh`'s `ui_confirm`/`ui_menu` (no standalone parser);
   `bin/setup-container-backend` is non-interactive since 0.0.44a V28
   (the old `confirm()` stub is gone, verified); the wrapper carries no
   y/n prompt — only comments recall the 0.0.21 removal
   (`opencode-as-opencode:585`), matching RM-0004's history row.
5. **Records match the code.** RM-0004 quote/canonical image, the
   conventions.md implementation-table row swap (wrapper → opk
   fallback), RM-0007's pin-gap closure and `[?]`-extended check, and
   the INDEX quote column all describe the shipped state truthfully;
   the shape-pin claims ("pinned behaviorally in test-ui,
   test-uninstall, test-kit-cli") were confirmed by running all three
   suites.

## Findings

### W1 (LOW) — `script(1)` unlisted in check-host.sh, now 4 dependents

`tests/check-host.sh` pins git, make, python3, shellcheck, setsid —
not `script(1)`. This wave makes `script -qec` (util-linux flag set:
`-e` exit-code propagation, `-c` command) load-bearing in
`test-kit-cli.sh:611` and `test-uninstall.sh:462`, joining the
pre-existing `test-ui.sh:74` and `test-browser-bridge.sh:479`. On a
host without util-linux `script` (or with BSD script, where `-e`/`-c`
differ), the new pins fail with empty captures (`got: `) — a red suite
that check-host was designed to prevent (environment-dependence class,
RM-0017/0.0.46a F2 family). Severity depends on the contributor host:
Linux/WSL2 and CI are fine (verified here). Suggested fix: one
`check script` row in check-host.sh (review-relevant code — a fix wave
owes its micro-wave review).

### W2 (LOW) — padded input diverges under the "same semantics" claim

`uninstall.sh` reads with `read -r answer` (no `IFS=`), which strips
leading/trailing IFS whitespace; `ui.sh`'s `_ui_read` and the opk
fallback use `IFS= read -r`, which keeps it. Empirically (dash):
`printf ' y\n' | { read -r a; }` → `y`, `IFS= read -r` → ` y`. So a
padded ` y` answers YES under an n default in uninstall, but falls to
the default (NO) in ui.sh and opk. The reads are pre-existing; what is
new is the wave's comment claiming "same semantics as ui.sh's
ui_confirm" — true for the case arms, not for padded input. Realistic
trigger: a pasted or space-padded answer. Both behaviors are defensible
(ui.sh's 0.0.44a V17 rationale even cites a trailing-space case);
either align the reads (`IFS=` in uninstall) or weaken the comment to
"same accepted answers and default fallback" — a comment-only fix
closes the loop without a successor review (0.0.45f precedent).

### W3 (INFO) — garbage now consents at the two y-default prompts

Behavior change from #187 A: unknown input under a y default now takes
the YES path. Affected sites: `uninstall.sh:324` (remove the kit's
wsl.conf bridge block — a `/etc/wsl.conf` edit, i.e. the consent
governed by AGENTS.md's wsl.conf rule; the prompt is the ask, and
garbage now answers it yes) and `uninstall.sh:564` (audit-log
deletion). This is exactly the intended RM-0006 semantics, the y
defaults are RM-0002-sanctioned, and the n-default sites are unchanged
(garbage declined before and after). Recorded because the consent
surface makes it worth an explicit maintainer YES, not because it is
wrong.

### W4 (INFO) — pty shape pins depend on echo-before-prompt ordering

The shape pins grep the LAST line of the `script(1)` capture for the
prompt; that line is `  <question> [y/N] RESULT=…` only because
script forwards the piped input to the pty master at spawn, so the
tty echo lands before the child prints the prompt (verified with
`cat -A`: `Yes^M$`, then `  Remove them now? [y/N] RESULT=yes^M$`).
If the ordering ever flipped (scheduler pressure), `tail -1` would
degrade to `RESULT=…` and the shape pins would fail spuriously — the
answer pins are unaffected. The input write happens at spawn, before
fork/exec/eval complete, so the ordering is near-deterministic; note
for future flake triage, no action suggested.

## Retracted / ghost findings

- "The shape pins in test-kit-cli/test-uninstall cannot pass —
  `tail -1` sees only the RESULT line": refuted empirically (mechanism
  now documented in W4). Kept here as calibration for pty-capture
  reasoning.

## Provenance, gates, recommendation

- **Model:** GLM-5.3 (house session, main agent, single pass, no
  subagents — ~200-line diff; pr-00179 precedent; every finding
  verified against full-file reads and live runs).
- **Tree:** `feature/y-n-prompt-consistency` @ `43bd33e`, clean; base
  `master` @ `d7a2d87` (v0.0.50).
- **Environment:** kit-managed WSL2 checkout (opencode user);
  util-linux script 2.x; dash as sh; opencode binary not exercised
  (no opencode interaction in scope).
- **Gates run:** check-host OK; `test-ui.sh` 35/35, `test-uninstall.sh`,
  `test-kit-cli.sh` all green; `make lint` green; sandbox-policy green;
  full unit sweep re-run green after this snapshot landed (incl.
  reviews lint + index parity + line-length ratchet). E2E suites not
  owed by the definition of done (no install.sh/update.sh/wrapper/
  backend changes); uninstall.sh prompt semantics are covered by the
  new behavioral pins.
- **Recommendation:** merge-ready — 0 HIGH/MED. Suggested
  dispositions: W1 implemented (check-host row — owes micro-wave
  review b); W2 implemented as comment weakening (comment-only round
  closes the loop) or deliberately not done; W3/W4 no action
  (recorded). If all four are deliberately not done, the loop closes
  with this snapshot.
