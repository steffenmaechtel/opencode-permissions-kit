<!-- review-meta
ID: pr-00234
Snapshot: a
Subject: issue-215 exec-time symlink gate on the .ddev handover pair (fix wave)
Scope: wave
Base: v0.0.56 @ caeb9a8
Diff: caeb9a8..395fee7
Date: 2026-10-23
Reviewer: GLM-5.3 (main, verification duty) + 5x GLM-5.3-Flash axes (S/Q/T/C/P fan-out)
-->

> Resolution: [resolution.md](resolution.md)

# Wave review — pr-00234 snapshot a — issue #215 exec-time gate on the .ddev pair

Wave pass over 395fee7 (single commit): `_ddev_components_sane` — the
exec-time component walk chained before the `.ddev` `chmod -R g+w` /
`chown -R` pair in `ddev_handover_root`
(files/opencode-permissions-kit-lib/sh/ddev-handover.sh:502-541, gate at
617-620), the rewritten gate/order comment blocks (563-586, 608-616), and
the racing fixture pins in tests/unit/test-ddev-as-opencode.sh:975-1095
(buffered PATH-stubbed find seam, slashed-root and spaced-components
drives).

Five axis reviewers (S security/TOCTOU, Q shell semantics, T test
fidelity, C claim audit, P class sweep) ran read-only over the diff;
every MED/HIGH and every load-bearing anchor was re-verified by the main
agent against the tree. Axis IDs map into the W-scheme below (Reported
by).

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified | Prov |
|---|---|---|---|---|---|---|
| W1 | MED | ddev-handover.sh:591-620, 635-646 | "a swapped parent skips the WHOLE iteration (project handovers and flag write included)" holds ONLY on the pair branch: the `_ddev_tree_conforms` fast path (591) bypasses the gate (617), and the iteration tail (635-646: `ddev_devowned_flag`, `ddev_handover_project`/`_back`/`project_root`) then acts through the swapped parent — the settings pairs' resolved containment (760-768, 679-687) canonicalizes BOTH sides through the swap and passes, so root `chmod -R g+w` + `chown -R` can reach out-of-tree developer files when the victim `.ddev` already conforms (steady state of every handed-over project) and its settings dirs drifted dev-owned | P1, S1, S2, T1, C1 | yes (code trace; fixture's own comment concedes the branch: victim deliberately `chmod 755` so the fast path must NOT void the gate) | delta-introduced claim over pre-existing residual |
| W2 | LOW | tests/unit/test-ddev-as-opencode.sh:975-1095 | the branch W1 describes is pinned nowhere (no conforming-victim race drive), and the "flag write included" half is unexercisable in the race drives (dev-owned mode off there: `OPK_INSTALL_CONF` exported nonexistent at :36-37, no `DDEV_DEV_OWNED`) — a regression relocating the gate below the `ddev_devowned_flag` call passes all race pins | T2, T3 | yes | wave-introduced |
| W3 | LOW | ddev-handover.sh:618 | skip message says "a parent component is a symlink" but the walk's final step checks the LEAF too (534-536) — in the micro-window between the :587 leaf gate and :617 the gate can fire on a swapped leaf and the message misleads an incident debugger | Q1 | yes | wave-introduced |
| W4 | LOW | ddev-handover.sh:521-541 | walk fail-open edges: operand == root / not under root returns 0 unchecked (case at 526-539), and root `/` silently degrades to a whole-filesystem walk where the mirrored `_fsb_pass` refuses loudly (fs-baseline.sh:142-161) — unreachable in the shipped call shape (no caller passes a `.ddev`-named or `/` scan root; leaf covered by :587) | S3, S4, C3 | yes | wave-introduced |
| W5 | LOW | docs/concepts/security-model.md:52-92 | RM-0100: no stale sentence found, but "Known residual gaps" carries no handover-race entry — the new gate (and the W1 residual) belong there; the new warn line is undocumented like its sibling at :631 (matches existing granularity, a sentence is owed, not a correction) | C5 | yes (section read) | pre-existing granularity, wave adds the trigger |
| W6 | INFO | files/opencode-permissions-kit-lib/bin/opk:497-523, 565, 579, 590 | opk handover executors recheck the operand leaf (`[ ! -L ]`) but never the ancestor chain — same class under the parent-swap definition this wave elevates; operator-invoked on operator-chosen paths, materially narrower; note for the next class pass | P2 | yes (gates present as claimed; ancestor gap confirmed) | pre-existing |
| W7 | INFO | ddev-handover.sh:617-624 | accepted residuals confirmed and documented as such: the inherent gate->op window (a swap between 617 and 622/624 is undetected; mid-recheck at 623 is leaf-only), the trailing-slash operand defeat of `[ -L link/ ]` (find never emits one), and the 0.0.46a F8 flag-write TOCTOU boundary — all match their comments | S5, S6, P7 | yes (F8 citation resolves: pr-00151 resolution.md:44) | pre-existing |
| W8 | INFO | ddev-handover.sh:563-565 | rewritten block calls the :587 `[ -L ]` a "scan-time gate" catching "statically planted links" — it runs at consume time, and static link plants never reach it at all (find's `-type d` excludes them before output); what it catches is leaf swaps | C4 | yes (find expression traced) | delta-introduced wording |
| W9 | INFO | sweep (files/ + scripts/) | class sweep verified exact: pattern `chmod -R\|chown -R` over files/ = 44 hits, per-file 9/20/6/4/1/1/1/2 matches the commit verbatim; wider patterns audited (`chgrp -R`, `setfacl -R`, `find -exec chmod/chown`, `xargs`, `tar -x`) — every hit maps to a disposition, none uncovered | P (sweep evidence) | yes (grep re-run by main agent) | wave claim confirmed |

## Retracted / ghost findings

- **C2 (C-axis, LOW) — retracted by verification.** Claim: the
  sabotage red-counts (5 vs 4) are "statically inconsistent — both
  sabotages void the same gate, predicted red set identical". Main-agent
  derivation: gate-call deletion voids BOTH drives — plain drive 4 red
  (victim secret 620, victim settings 620, warn absent, success echo
  present; seam + rc stay green) + spaced drive 1 red (mode 620) =
  **5**; root-normalization deletion voids only the slashed-root drive
  (plain), the spaced drive passes its root unslashed and stays green =
  **4**, and the commit names the drive ("on the slashed-root drive").
  T4 independently reconciled the same counts. Ghost — C2 counted only
  the plain drive's checks and missed the spaced drive's mode pin.

## Verified clean (no findings)

- **Walk mechanics** (S + Q, empirical probes in dash/bash): the peel
  loop is correct for spaced components, glob characters, `-`-leading
  components, internal/leading `//`; the trailing-slash normalization
  terminates for every input including `/` and `//`; the quoted-literal
  case prefix defeats lexical-prefix confusion (`/a/b` does not match
  `/a/b/*` for operand `/a/bb`); leaf included as the walk's last step
  (W4's operand==root corner excepted).
- **"No legitimate tree ever trips the gate"** (S): verified — find
  without `-L` never descends or prints through a symlinked
  intermediate, so a symlinked component below the root at exec time
  can only be a swap.
- **ORDER unchanged**: chmod-before-chown intact; the mid-recheck and
  `chown -R -P` semantics claims match the code (S6 documents the
  residual honestly).
- **set -e/-u safety + hygiene** (Q, probed): `[ -L ] && return 1` is
  errexit-exempt and its only call site is an `if !` condition;
  `_dcs_*` globals collision-clean across files/ + tests/, house style
  consistent; callers with `set -eu` (install.sh, config.sh, update.sh)
  unaffected.
- **Line length + shellcheck** (Q + main agent): no ratchet breach under
  tests/unit/test-line-length.sh's metric; `make lint` green with zero
  new diagnostics on the changed region (62 base = 62 HEAD).
- **Seam mechanics** (T5): production calls bare `find` (PATH intercept
  valid); `$(command -v find)` baked before the stub dir is prepended —
  no recursion; the buffer is an airtight barrier (consumer sees
  nothing until `cat`); `_rc` captured before the swap and survives
  `cat`/`rm -f`; a dead seam reds the seam pin, not silently green.
- **Pin placement + errexit safety** (T6 + main agent): pins end ~1095,
  summary gate at the file end — before it; no new line can abort the
  `set -e` suite mid-way.
- **Production observation path** (T7 + main agent): all six primary
  call sites (install.sh:1805; config.sh:390, 730, 760; update.sh:905,
  1517) invoke `ddev_handover_root` bare — stderr reaches the operator;
  the `2>&1` pins observe the production channel. (Nuance kept from T7:
  the warn is not mirrored into log-file channels.)
- **Sandbox policy** (T8): mktemp-only scratch, `rm -rf "${VAR:?}"`
  guarded, no repo/system-tree writes.
- **Citations** (C): #211 a F1, b W7, 0.0.45e W1, 0.0.46a F8, 0.0.46b
  W1 all resolve in internal/reviews/ with matching content.
- **Commit gate claims** (C, classified): unit/lint/check-version
  verified green by the main agent this session; sabotage 5/4 counts
  derived consistent (see C2 retraction); the e2e counts (309/0,
  47/0) and the 10x stability loop are author-observed restatements,
  not re-executed.

## Provenance, gates, recommendation

- **Run provenance:** fan-out host window 2026-10-23T20:20:58Z →
  2026-10-23T20:35:03Z; five axes on GLM-5.3-Flash, verification by
  GLM-5.3 main agent; checkpoints at /tmp/opencode/review-234/
  {S,Q,T,C,P}.checkpoint.md (launch/section/return lines). No sabotage
  during the reader window; tree clean at 395fee7 throughout.
- **Gates run (main agent, this session):** `sh
  tests/unit/test-ddev-as-opencode.sh` 274 PASS / 0 FAIL; `make test`
  green (full unit suite incl. rules-index parity, 115 rows); `make
  lint` green; `make check-version` green. e2e suites NOT re-run
  (author-observed 309/0 + 47/0 ride to the release gate as recorded
  debt).
- **Severity mapping note:** C reported the W1 mechanism as HIGH; mapped
  to MED during verification — the escalation needs a four-way
  precondition conjunction (race won in the scan->exec window + victim
  `.ddev` already conforming + settings dirs drifted dev-owned + config
  unflagged), and the `.ddev` pair itself (the a F1 HIGH shape) is not
  reachable on this path. Four axes independently reported MED.
- **Recommendation: [GO with conditions]** — the fix is sound for the
  pair branch (correct walk, correct placement there, honest warn,
  verified no-false-trip property, exact sweep). Conditions:
  1. W1 must be dispositioned: either weaken the "WHOLE iteration"
     claim (ddev-handover.sh:574-575, 611-613, commit narrative) to the
     pair branch and record the fast-path residual, or hoist the gate
     above the `_ddev_tree_conforms` probe and pin the conforming-victim
     drive (W2).
  2. W5: one sentence in docs/concepts/security-model.md "Known
     residual gaps".
  3. W3/W4/W8 ride along as comment/hardening touch-ups; W6/W7 are
     notes for the next class pass / documented residuals.
