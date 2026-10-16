# Review resolution — pr-00189 (issue-187 y/n prompt consistency)

Status: closed — fix wave `4fb7ebd` (a W1, a W2) dispositioned; micro-
wave review `b` (fix commit only): 0 HIGH/MED/LOW, 2 INFO — both
deliberately not done, no code touched by the dispositions, stop rule
met.

Case: wave review `a` of `feature/y-n-prompt-consistency`
(`d7a2d87..43bd33e`, prompt-shape/semantics fix wave). Verdict at review
time: 0 HIGH/MED, 2 LOW + 2 INFO. Dispositions below; the maintainer go
for the fix wave came in chat 2026-10-17 (W1 yes, W2 yes without a trim
helper, W3/W4 no action).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `4fb7ebd` | check-host `script` row + header list — see detail |
| a W2 (LOW) | **implemented** | `4fb7ebd` | `IFS=` dropped ×3; 8 padded pins; sabotage 4/2/2 — see detail |
| a W3 (INFO) | **deliberately not done** | — | intended RM-0006 semantics; maintainer acknowledged — see detail |
| a W4 (INFO) | **deliberately not done** | — | pty-ordering note for future flake triage; no action owed |
| b B1 (INFO) | **deliberately not done** | — | whitespace-only = empty read, 5-empty abort intent — review-b |
| b B2 (INFO) | **deliberately not done** | — | presence-only probe; util-linux named in why-text — review-b |

## Evidence detail

### a W1 (LOW) — script(1) unlisted in check-host.sh

Row added in the "Required for the unit suite" section, naming all four
dependent suites and the util-linux `-qec` flag set; install hint
`$APT util-linux` (same package as setsid). The header comment now
lists setsid + script too — it had drifted as well (listed only git,
make, python3, shellcheck while setsid was already probed). Residual,
deliberate: no test pins check-host's tool list itself — a generic
"every tool a suite executes appears in check-host" guard would be the
0.0.42e C2 guard-class (guards are review objects) and is future work,
not this wave; the probe is self-evident the next time it runs.

### a W2 (LOW) — padded input diverged; trim everywhere, no helper

Direction (maintainer chat 2026-10-17): trim EVERYWHERE; `read`'s field
splitting IS the trim — no `_trim` helper. Code: `IFS=` dropped from
both `_ui_read` reads (ui.sh) and the opk fallback read; uninstall's
`prompt_yn` needed no code change (its un-prefixed reads always
trimmed — it becomes the reference). Blast radius through `_ui_read`:
ui_confirm, ui_menu, ui_ask and install.sh's two direct `_ui_read`
calls (selection/custom at the reviewed tree's :1206/:1225) — all
decision/key/path inputs where edge-trim is the safer reading (a
trailing space in a path answer would be a bug, not data).

Claims swept with the code (L3): opk fallback comment no longer claims
"padded input falls back to the default"; ui_confirm's V17 note and the
`'y '` pin label now say trimmed-explicit; uninstall's `prompt_yn`
comment states the shared pipeline; conventions.md RM-0006 bullet gains
the trim clause; RM-0006 record updated (body, check line, review log —
and the stale wrapper reference replaced with opk's fallback; the
wrapper carries no prompt since 0.0.21, per RM-0004's log).

Pins (both defaults, all three implementations + the `_ui_read`
consumers): test-ui +4 (` y` under n, `no ` under y, menu key ` 2`,
ui_ask ` name ` → `name`) — the relabeled `'y '`-under-y pin is
deliberately NOT trim-discriminating; it stays green under trim removal
by design and guards the V17 regression (unknown → no even under a y
default); test-kit-cli +2 pty pins; test-uninstall +2 pty pins (pinning
prompt_yn's pre-existing trim for the first time).

Sabotage (trim deleted = `IFS=` re-added, all three sites at once,
committed tree, restored green afterwards): test-ui 4 FAILs (the four
new pins), test-kit-cli 2 FAILs, test-uninstall 2 FAILs — the uninstall
FAILs' `got:` lines show the discriminating mechanism (padded answer
fell to the default instead of being honored). Measurement note: the
first uninstall sabotage attempt used a sed with a typo (`2/dev/null`,
missing `>`) that broke the redirect instead of deleting the trim —
8 FAILs, discarded as invalid, redone clean with the result above.

### a W3 (INFO) — garbage under a y default now consents

No action. What changed: unknown/garbage input at the two y-default
prompts (uninstall.sh :324 wsl.conf bridge block, :564 audit-log
deletion) now resolves to the DEFAULT = yes; pre-wave it resolved to a
hard-coded "n". This is the intended RM-0006 semantics ("unknown input
falls back to the default") with RM-0002-sanctioned y defaults; the
n-default sites answer garbage "no" before and after. The maintainer
read this finding in chat and asked for explanation only — acknowledged,
no change requested. The consent surface stays governed by AGENTS.md
(opk uninstall asks before touching wsl.conf; the prompt is the ask).

### a W4 (INFO) — pty shape pins' echo-before-prompt ordering

No action. The note exists so a future spurious shape-pin failure on a
loaded host is triaged in seconds (answer pins unaffected); the ordering
is near-deterministic (the piped input reaches the pty master at spawn,
before fork/exec/eval complete).

## Gates at disposition time

Full unit sweep (`make test`) green after the fix; make lint green;
rules-meta audit green (RM-0006 quote unchanged — still a true prefix
of the extended bullet); reviews lint + parity green after the index
regen; check-host run shows the new probe. e2e not owed (no
install.sh/update.sh/wrapper/backend change; uninstall.sh answer
semantics are covered by the behavioral pins).
