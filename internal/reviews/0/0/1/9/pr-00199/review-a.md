<!-- review-meta
ID: pr-00199
Snapshot: a
Subject: issue-165 feature wave — silently-droppable lib guards warn loudly
Scope: wave
Base: v0.0.52 @ 21cf179
Diff: 21cf179..28c2e0e (feature commit; sabotage matrix run against the same tree)
Date: 2026-10-18
Reviewer: GLM-5.3 (house session — main agent + 2 GLM-5.3-Flash axis subagents: mechanical/regression, claims/pins/sweep; every finding main-agent-verified; 4-mutation sabotage matrix re-run by the main agent)
-->

# Review — pr-00199 snapshot a — issue-165 feature wave (status.sh missing-lib rows)

> Resolution: [resolution.md](resolution.md)

Wave under review: feature commit `28c2e0e` (3 files, +331/−2) —
`management/status.sh` gains counted `ui_kv_warn` fallback rows for four
silently-droppable lib guards (advisories, ddev-terminal, ddev-migrate,
ddev-hosts), `tests/unit/test-status.sh` gains a 22-pin behavioral block
(extracted-block harness + real-`ui.sh` verdict legs), `docs/reference/cli.md`
extends the counting rules. The wave question — "did the implementation
break or lie?" — is answered: no fix-induced regression found; the
findings below are coverage/claim/pin gaps, two of them MED.

## Findings index

| ID | Sev | One-line | Site | Prov |
|---|---|---|---|---|
| W1 | MED | ddev-handover lib guard is an undefended same-shape silent-drop; the sweep's "covered" disposition is hollow for deployed runs | status.sh:595-599 | pre-existing site, wave-introduced class split |
| W2 | MED | hosts readiness split's LOGIC is never executed by any pin — `_h165_run` injects the flag, only four static grep fragments pin tokens | test-status.sh:1636-1644 | wave-introduced (pin gap) |
| W3 | LOW | git-check.sh silent noop-stub drop not dispositioned against the wave's own "broken kit" ruling | status.sh:59-65 | pre-existing |
| W4 | LOW | docs promise "warning row naming the file"; the advisories row names neither `advisories.sh` nor any `sh/` path | cli.md:366 vs status.sh:230 | wave-introduced |
| W5 | LOW | keep-as-is pin greps two exact strings only — an over-sweep row with different wording passes green | test-status.sh:1726-1731 | wave-introduced (pin) |
| W6 | INFO | test extraction anchors are unanchored first-match regexes — brittle, but fail loud ("anchor drift?"), never false-pass | test-status.sh:1601 etc. | wave-introduced (test) |
| W7 | INFO | readiness split evaluation-order delta: `id -u` probe now runs in ready+missing-lib states that previously short-circuited at the lib check | status.sh:832-836 | wave-introduced (benign) |
| W8 | INFO | unreadable-but-present lib (mode 000) escapes all new guards; dash then aborts the dot mid-report (loud crash, rc=2, no verdict line) | status.sh:234,724,838 | pre-existing |
| W9 | INFO | sibling sweep of other shipped scripts clean: update.sh guarded sources fall back to noop stubs in the fail-safe direction; install.sh exits loud | update.sh:631,828; install.sh:224-231 | pre-existing (record) |

## Findings

### W1 (MED) — ddev-handover: same damage scenario, silent drop, no rationale

`_st_dhl` resolves checkout-first with a deployed fallback
(status.sh:595-596) and gates the whole "ddev share" resharde scan behind
`[ -f "$_st_dhl" ] && [ uid precondition ]` (:597) — **no elif, no row**.
The PR sweep lists the site but dispositiones it "checkout-first +
deployed-LIBDIR fallback — the issue's covered class". That coverage is
hollow exactly where the wave's threat model lives: on a **deployed run**
(the normal `sudo opk status`), `dirname $0/../sh/` *is* the deployed
`sh/` dir — both candidates collapse to the same path, the fallback
protects nothing, and a damaged/partially deployed tree missing
`sh/ddev-handover.sh` silently drops the entire ddev-share family while
its two direct siblings in the same damaged tree warn about their own
missing files (`ddev() hook` :567, `db dumps` :780). The verdict can
then read green over a check family that never ran — the exact defect
class the wave's own advisories comment (:224-227) rules "a broken kit,
not an optional feature". The in-code comment (:589-594) justifies only
the checkout-first *ordering* (0.0.46a F4), not the silent drop. The
issue's site table (#165) does not name ddev-handover, and its prose
names only git-check.sh as the covered class — so unlike W3 there is no
upstream disposition to lean on. Fix shape: the sibling `elif` row
(row-free when the uid precondition fails), or an explicit
deliberately-not-done rationale in the PR/test comment — one of the two,
not silence.

### W2 (MED) — hosts readiness logic unpinned: flag injected, tokens grepped

The readiness split is the wave's own mechanism at this site, and its
"all original conditions preserved verbatim" claim is pinned only by
four **static** grep fragments (`[ -d /mnt/c ]`, the hosts-file `-f`,
`[ -n "${DEFAULT_USER:-}" ]`, `id -u "$OPENCODE_USER"`). Every
behavioral arm bypasses the computation: `_h165_run` sets
`_st_hosts_ready="$_h165_ready"` directly (test-status.sh:1638-1641), so
the "unready host stays row-free" pin proves the elif, not the chain.
Realistic drift that passes every pin green: flipping `!=` to `=` (the
fragments grep no operator), or dropping the `2>/dev/null || echo 1`
sentinel — the #196 sentinel pin covers only the *terminal* block's
`_st_dev_uid` probe (`grep '^ *_st_dev_uid='`), not this one. Either
mutation makes the hosts row fire on healthy agent-uid WSL runs or drop
on developer-uid runs, with the suite staying green — the 0.0.44c C1
fail-but-green class. (Dropping the `${DEFAULT_USER:-}` precondition
*is* caught — my M5 sabotage went red via the static grep — the
unpinned dimension is operator/sentinel semantics.) Fix shape: one
behavioral arm through the real `_h165pre` block (stubbed `id`, both
uid outcomes, assert the flag), next to the existing arms.

### W3 (LOW) — git-check disposition stale against the wave's own ruling

`git_status_row` falls back to a noop stub when neither checkout nor
deployed `sh/git-check.sh` exists (status.sh:59-65) — the Core git-floor
row silently vanishes, same shape and same damaged-deployed-tree
exposure as W1. Mitigation the handover site lacks: the issue itself
names git-check as "the covered class" (checkout-first covers the
realistic *version-skew* case), and the code comment documents
fail-soft intent (issue #118/#158). But the wave's new ruling — missing
lib in a deployed tree = broken kit = counted row — makes that
rationale stale without an update: the test comment's site list
(:1451-1456) also stops at six sites. Needs a one-line explicitly
recorded exclusion (PR body or test comment), not necessarily a row.

### W4 (LOW) — docs "naming the file" is false for 1 of the 4 families

cli.md:366: "the check family renders a warning row naming the file
(`fix: sudo opk update`)". True for the three ddev rows
("kit file sh/ddev-terminal.sh missing" etc.); false for the advisories
row — key "advisories database", value "missing — security checks
skipped (fix: sudo opk update)" — `advisories.sh` and any `sh/` path
appear nowhere (status.sh:230). A user following the docs and grepping
status output for the filename finds nothing. Align the row wording
with its siblings or soften the docs sentence.

### W5 (LOW) — keep-as-is pin under-discriminates

The over-sweep guard (test-status.sh:1726-1731) greps for exactly
`kit file sh/wsl-browser-bridge.sh missing` and `kit file sh/log.sh
missing`. An over-sweep row with any other phrasing passes green. The
likely over-sweep shape is copy-paste of the exact pattern (caught), so
the pin has partial value — but as written it proves absence of one
implementation, not absence of the class.

### W6 (INFO) — extraction anchors: first-match regexes, fail-loud

The five sed ranges (block starts, `/^fi$/` and `ui_section "…"`
ends) are first-match and unanchored to nesting. Verified mechanically:
all starts unique, each capture ends at exactly one column-0 `fi` with
the elif rows inside. Future edits inserting a matching literal (or an
unindented `fi`) shift the capture — the affected pins then fail loudly
("anchor drift?"); no false-pass shape found.

### W7 (INFO) — readiness evaluation-order delta, benign

Original guard order: `/mnt/c`, lib, hosts-file, stamp, uid — the lib
check sat second. The split moves it behind the readiness chain, so in
ready+missing-lib states the side-effect-free `id -u` probe now runs
where it previously short-circuited. No observable difference; probe
bytes preserved verbatim including `2>/dev/null || echo 1`.

### W8 (INFO) — present-but-unreadable lib still escapes the guards

`[ ! -f ]` is false for a mode-000 file: the fallback stays silent,
then `. file` aborts dash mid-report (sandbox-verified: rc=2, "Permission
denied" on stderr, no verdict line). Loud crash, not the silent-green
lie this wave fixes; code and docs honestly scope "missing". Pre-existing
behavior at pre-existing source lines.

### W9 (INFO) — sibling scripts: no same-class silence (record)

update.sh's guarded sources (:631 wsl-browser-bridge, :828 ddev-handover
inside rescan) fall back to noop stubs whose failure direction is safe
(stamp-valid check returns 1 → full rescan; bridge check returns 1 →
optional re-apply skipped); install.sh's `kit_source` exits loudly on
missing libs. config.sh / bin/opk / setup-container-backend carry
guarded-source candidates with loud or candidate-list resolution.

## Verification (main agent)

Every reviewer finding was re-verified against the code before entering
this snapshot; none retracted, one reshaped:

- **Reshaped (from the claims axis):** "sweep claim (e) is FALSE —
  ddev-handover matches the pattern" overstates. The PR's enumeration
  is complete — my independent inventory of every `sh/` lib
  guard/source in status.sh matches the PR's site list exactly (loud
  ui.sh exit; git-check + ddev-handover checkout-first; the four fixed;
  bridge + log keep). The defect is the *disposition* ("covered") of
  two enumerated sites, not a missed site — folded into W1/W3.
- W1/W2/W3/W4/W5 confirmed by direct read (line numbers above are the
  main agent's, cross-checked against both axis reports).
- W7's "all five preconditions byte-verbatim" confirmed by diffing the
  split's condition text against the pre-wave guard in the wave diff.
- M5-style mutation (drop the `${DEFAULT_USER:-}` precondition) run by
  the main agent: red via the static fragment pin — W2's scope is the
  operator/sentinel semantics, as stated.

**Sabotage matrix (L4 — pins discriminate; tree clean at `28c2e0e`,
mutate → red → restore → green):**

| Mutation | Result |
|---|---|
| M1 advisories fallback block deleted | red, 4 FAILs — incl. both verdict legs; the verdict leg reproduces the issue's defect exactly (`rc=0`, "All green") with the row gone |
| M2 ddev-terminal `elif` arm deleted | red, 2 FAILs |
| M3 hosts row `ui_kv_warn` → `ui_kv` | red, 2 FAILs |
| M5 readiness precondition dropped | red, 1 FAIL |

**Gates run:** `sh tests/unit/test-status.sh` (all 22 `165:` pins
PASS); `make test` (full unit suite + sandbox policy, green); `make
lint` (ShellCheck, green); `make check-version` (green). e2e suites
**not run** — status.sh is not in AGENTS.md's e2e-owed list
(install.sh / update.sh / wrapper / backend provisioning); no healthy
install gains a row, so e2e status assertions are unaffected by
construction. Both e2e suites remain owed before the next release tag
per the release gate, independent of this PR.

**Environment:** house session (WSL2 kit-managed checkout, checkout
ownership — no chmod needed, no mode changes in the diff); reviewer
subagents GLM-5.3-Flash, fresh context, checkpointed per section
(`/tmp/opencode/pr199-review-a-{mech,claims}.chk`); no e2e/docker runs,
so no opencode-binary version dependency this pass.

## Recommendation

**Fix-first (small wave), then snapshot b.** W1 and W2 before merge:
W1 is one `elif` row (or a recorded deliberate exclusion) closing the
last undefended same-shape site; W2 is one behavioral readiness arm.
W4 is a one-line wording alignment; W3 a one-line disposition note;
W5 optional. No regression blocks the merge; the wave's own pins,
controls and verdict legs are strong (all four failure paths executed,
verdict observed the way production observes it, both exit-code legs
discriminate in the sabotage matrix).
