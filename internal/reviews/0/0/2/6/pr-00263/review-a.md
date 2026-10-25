<!-- review-meta
ID: pr-00263
Snapshot: a
Subject: release 0.0.57 full-scope review (pre-tag)
Scope: full
Base: 0.0.57 @ 4eacabb
Diff: c979654..c38f9e5 (tag 0.0.56..master: 101 files, +16971/-2146, 127 commits, 10 merged PRs #234 #235 #240 #241 #242 #243 #244 #256 #258 #259; reviewed tree = release/0.0.57 @ 4eacabb, one VERSION-chore commit ahead of the diff head)
Date: 2026-10-25
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 10x GLM-5.3-Flash reviewer subagents — 5 axes x 2 independent each (A install/update, B management surface, C wrapper+bin+sh, D security horizontal, E tests+docs+CI)
Skills: opk-review-pass
-->

# Full-scope review — pr-00263 snapshot a — release 0.0.57

> Resolution: [resolution.md](resolution.md)

Release full pass ("what rotted sideways?") over the whole tree at 4eacabb
(VERSION 0.0.57). The birth-PR #263 carries the VERSION bump; the reviewed
object is the tree, with the 0.0.56..master delta as the round's material
(10 merged PRs). Ten reviewer subagents ran five axes, two independent
agents each, staged at ≤ 5 concurrent; the main agent (GLM-5.3) re-verified
every finding against the code before it entered this snapshot — including
six reviewer-evidence corrections and two twin-disagreements resolved by
main-session reads (see "Retracted / ghost findings" and "Calibration").
Cross-agent duplicates merged (F2, F14, F23); nothing retracted.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| F1 | MED | sh/ddev-migrate.sh:458-460 (+355-356, 418) | Root-run ddev-migration writes DB dumps through an agent-plantable symlink in the agent-group-writable dump dir — no leaf gate on the dump operand (dev-privilege write-through; ddev's overwrite behavior unverified) | D1 | yes (code read) |
| F2 | MED | management/update.sh:893-895, 1523-1531 + config.sh:103-107, 351 + update.sh:441, status.sh:72 | The #243 reader-parity sweep landed in uninstall.sh only — update.sh's project loops consume projects.conf with a bare `[ -d ]` gate and run recursive root ops over hand-edited entries; OPENCODE_USER stays unshaped at every consumer incl. the config.sh writer refusal it protects | D1+D2 | yes (code read; D2's /etc/subuid arm defused by its own id gate — see detail) |
| F3 | MED | management/uninstall.sh:264-266, 314-316, 320-322, 331-333, 421-423, 455-460 (+claim at 745-750) | Six rc-blind `run` ops with unconditional success echoes/logs survive in uninstall.sh under the comment that claims "the #211 c W1 class sweep this wave owes" — incl. the sudoers rm ("sudoers removed." over a failed rm) | B1 | yes (code read, all six sites) |
| F4 | MED | sh/ddev-handover.sh:609 vs 720-722, 799-801 (+592-600, 633-639) | The #234 exec-time component walk fires once per iteration; the settings-handover `chown -R`/`chmod -R` pairs later in the same iteration keep only leaf `[ -L ]` gates whose containment canonicalizes through a post-gate parent swap — their window spans the whole `.ddev` recursive pair, wider than the residual the fix documents | C2 | yes (code read; C1/D1 clean verdicts checked — no contradiction, see detail) |
| F5 | MED | docs/getting-started.md:9-11 vs install.sh:574-586 | Prerequisites bullet says the installer "probes" python3 and "the baseline still applies without it, minus the live counters" — both probe arms `exit 1`; the list is abort/warn-precise everywhere else (git: "never aborts", ddev: "aborts") | E2 | yes (code read; overrides E1's clean note — see Calibration) |
| F6 | LOW | install.sh:713-722 (+2612, 45-52) | All five pre-install backup copies swallow cp failure (`2>/dev/null \|\| true`) while the closing summary unconditionally announces the backup dir the header calls "recovery material after a failed run" | A1 | yes (code read; anchors corrected 2636→2612) |
| F7 | LOW | management/update.sh:724-727, 745-751 (+343, 766-769) | sudoers/umask re-deploy skips emit `log` only — no terminal line, and with log.sh missing from both roots `log()` is the `:;` no-op stub, so the in-code contract "the skip must not be silent" is violated by construction (terminal-quiet alone was accepted by #211 a F6) | A1 (A2 dissents: documented-deliberate) | yes (code read; scoped to the stub residual) |
| F8 | LOW | install.sh:1371-1372, 1814-1815 (+739/744/895) | Both getfacl backup sites print unconditional "backed up"/"Backup saved." over a `2>/dev/null \|\| true`-swallowed failure — and the pre-flight probes only setfacl, so an acl install with getfacl absent passes the gate | A2 | yes (code read) |
| F9 | LOW | management/uninstall.sh:228-233 | The OPENCODE_USER shape-gate WARN echoes the just-rejected raw value — a corrupted conf value (newline/escape bytes) can forge transcript lines; admin-paste only, no boundary crossed | B1 | yes (code read) |
| F10 | LOW | management/uninstall.sh:603 (+config.sh:351 twin) | Agent-home refusal compares the hardcoded `/home/$OPENCODE_USER` spelling — the house getent pattern (opk, status.sh) is not used; trigger narrowed on verification: install refuses home deviation on reuse (install.sh:1191-1205), so the residual is a post-install hand-moved home registered as a root | B2 | yes (code read; trigger corrected — B2's install-acceptance claim was wrong) |
| F11 | LOW | management/status.sh:542-551 | The #244 c S3 stderr passthrough turns a JSON non-array feed (dict envelope, array of scalars) into a raw Python traceback on cron stderr — rc still 1, verdict stays the correct uncounted unknown row | B2 | yes (code read) |
| F12 | LOW | bin/opencode-as-opencode:246, 290, 298 | The printed bypass-fix advice `rm -f$_oc_bins` word-splits/globs on pasting when $HOME carries spaces or glob metacharacters — the expansion itself is quoted (no executed-code violation); the glob-char path is the actual deletion vector (rm -f refuses directories, so the space case mostly errors) | C1 | yes (code read; damage analysis corrected) |
| F13 | LOW | bin/setup-container-backend:327-338 (+191-207) | Failed `systemctl --user start docker.service` is silenced and the provisioner unconditionally prints "docker-rootless is ready" + the socket to record — the linger sibling got the failure-honest shape (#211 a F13); mitigation: the wrapper re-probes the socket at every session start | C1 | yes (code read) |
| F14 | LOW | sh/fs-baseline.sh:353 + sh/ddev-handover.sh:565 (+update.sh:905-906) | A symlinked registered root passes `[ -d ]` but `find -P` never descends it: all four baseline passes no-op, `_FSB_ERRORS` stays 0, callers print the success line the file's own contract forbids — and the scan-skip stamp is written, so routine updates never retry (only --refresh) | C2+D2 | yes (code read; both entry checks + stamp write) |
| F15 | LOW | management/uninstall.sh:687-688 (+556-564, 541-545) | Revert-loop `find ! -type l -exec chown` has scan-time classification only, no exec-time recheck (the #211 a F1 shape) — the structural mitigation (userdel ran first) fails exactly when userdel fails on a live straggler process, which is WARN-and-continue | D2 | yes (code read) |
| F16 | LOW | tests/unit/test-skills-lint.sh:15-17 vs 93-94 | Header rule 1 says "every entry under .agents/skills/ is a skill directory" — the loop `for _d in "$_root"/*/` examines directories only; a bare file at the skills root (which the header itself says the loader picks up) is silently unexamined | E1 | yes (code read, full file) |
| F17 | LOW | tests/unit/ (10 sites) | Ten delta-introduced bare finding-ID refs (`(b S3)`, `a-W1 class`, `b W7 shape`, `b-S2 shape`, `e-S1 class` …) violate the conventions.md citation format — the #259 a Q1 sweep qualified only test-rules-revisit.sh; three pre-existing siblings named for the class sweep | E1 | yes (grep + added-line proof; count corrected ~9 → 10) |
| F18 | LOW | tests/unit/test-docs.sh:201 | The #256 W1 claim-drift guard extracts only the first `codeigniter\|…` case arm (`head -n 1`) while its comment claims "every root-file type ddev-handover.sh matches" — a future second arm escapes direction A | E2 | yes (code read) |
| F19 | INFO | install.sh:1965 | Official-opencode installer fetch is a bare `curl -fsSL … \| bash` with no kit-level error wrapper — aborts with curl's own stderr only; neighbors use the `\|\| { echo "error: …" >&2; exit 1; }` shape (e.g. :1887-1889) | A1 | yes (code read; anchor corrected 1987→1965) |
| F20 | INFO | management/uninstall.sh:662 | Reader blocklist arm `/lib*` is broader than 0.0.56's `/lib\|/lib/*\|/lib64\|/lib64/*` — fail-closed direction, arm-for-arm writer parity (config.sh), loud "Skipping system path" echo; recorded as a delta behavior change | B1 | yes (code read + 0.0.56 comparison) |
| F21 | INFO | bin/opk:305-327 | Settings-edit failure branch (four rc-1 causes shared, deliberate #244 h S3) tells the user to remove the "opencodeBinary" *line* even when the grep matched the literal as a value — wording residue of an accepted disposition | B2 | yes (code read) |
| F22 | INFO | sh/tui-plugin.sh:44-64 | Gate→op window (agent_home_sane at :44, ops at :53-61/:64) with no adjacent re-check — same shrunk-not-closed residual the house documents at the .ddev site; recorded for the L5 ledger | C1 | yes (code read) |
| F23 | INFO | sh/ddev-handover.sh:540-551 + sh/fs-baseline.sh:299-312 | Neither component walk `[ -L ]`-tests the scan root itself — trigger needs write on the root's parent, outside the agent threat model (ancestors carry traverse-only ACLs); the new #234 gate copied the pre-existing walker shape | C2+D2 | yes (code read) |
| F24 | INFO | sh/ddev-handover.sh:575-576 | `find -prune -print \| while read` splits a newline-bearing `.ddev` name into two stream lines; gates then act on same-tree prefixes — bounded effect inside the project tree; the `-print0` shape exists in the kit | D1 | yes (code read) |
| F25 | INFO | sh/secure-binary.sh:38-39 | After the atomic mv, `chown` runs before `chmod 750` on the live name — a ms-wide cp-natural-755 window; the atomic helpers get mode-before-mv right; public software, hardening not secrecy | D2 | yes (code read) |
| F26 | INFO | tests/check-host.sh vs test-skills-lint.sh:221, test-line-length.sh:163-172 | `seq` is load-bearing in two suites' probes but absent from check-host's tool list — failures are loud (PIN/PROBE BROKEN), so hint-quality only | E1 | yes (grep; both uses delta-born) |
| F27 | INFO | internal/reviews/0/0/2/5/pr-00259/resolution.md:3 | The format-bound Status line carries a German verbatim maintainer quote — parses correctly as `closed`, no house rule violated (internal evidence, not shipped content); corpus-hygiene ledger entry | E2 | yes (code read) |

Severity counts: **5 MED, 13 LOW, 9 INFO** (27 findings, 3 cross-agent
duplicates merged). No HIGH — the pr-00211 a F1 class (parent-symlink TOCTOU
in the group-baseline walker) is closed at the `.ddev` site with a documented
residual; the two fresh gate-sweep gaps (F2, F4) are MED.

## MED findings detail

### F1 (MED) — ddev-migrate dump operand: agent-plantable symlink, dev-privilege write-through

`_dm_export` runs the export loop via `_ddev_migrate_run_as "$dm_dev"` with
the dump operand inside the dump dir that is deliberately agent-group-
writable for the whole minutes-long loop:

```sh
# ddev-migrate.sh:355-356
chown "$dm_dev:$dm_ocg" "$DD_MIG_DUMP_DIR" 2>/dev/null || true
chmod 3770 "$DD_MIG_DUMP_DIR" 2>/dev/null || true
# :458-460
if _ddev_migrate_run_as "$dm_dev" "$dm_bin" export-db "$dm_n" \
   --file="$DD_MIG_DUMP_DIR/$dm_n.sql.gz" </dev/null >"$dm_err" 2>&1 \
   && [ -s "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" ]; then
```

`dm_ocg` is the opencode user's own group; sticky (mode 3770) blocks
rename/unlink of others' entries but not creation of one's own — the agent
plants `<project>.sql.gz` as a symlink to any dev-writable path. There is no
`[ -L ]`/unlink-first gate on the dump operand anywhere; the only pre-check
is the resume probe `[ -s … ]` (:418), which *follows* links. The 0.0.44a/b/c
hardening in this exact directory covered the manifest (root-only stage +
seed ownership check :385-393), the err file (moved into the root stage,
:454-457 comment) and the finalize `find ! -type l` passes — the dump
operand itself was left on the write path. The dir comment at :345-354 names
"the AGENT — the wave's own threat premise". Impact: developer-privilege
file clobbering with dump content (not root, content not attacker-chosen);
secondary: `[ -s ]` + an existing OK manifest entry can resume-mark a
project off a planted non-empty link. One open point the tree cannot
answer: whether `ddev export-db --file` overwrites an existing path
(upstream ddev v1.25.3) — the absent leaf gate is the finding either way;
overwrite behavior marked unverified. Provenance: pre-existing —
bug-form bounded by the taxonomy refactor 72d474a, first shipped ≤ 0.0.29
(the hardening layers around it are 0.0.44-era).

### F2 (MED) — the #243 conf-reader hardening swept uninstall.sh only

This range added full reader-parity gates to the uninstall project loop
(#243 a-f): OPENCODE_USER shape gate (uninstall.sh:216-233, charset minus
leading dot/hyphen, trailing dot), agent-home refusal, form gate,
system-path blocklist — explicitly reasoned "a hand-edited conf must not
slip a `//etc` or `/var/.`-style entry past the system-path blocklist"
(uninstall.sh:612-615 area). The class sweep stopped there:

1. **update.sh:893-895** (handover rescan) and **:1523-1531** (`--refresh`)
   consume the same `projects.conf` with the only gate being `[ -d "$root" ]`
   — then run `fs_baseline_root` (recursive chgrp + g+rwxs + default ACLs)
   and `ddev_handover_root` (recursive chown-to-agent + chmod -R g+w) over
   the entry. A hand-edited `/etc` or `/home/opencode` line turns
   `sudo opk update` / `--refresh` into a root-run permission rewrite over
   that tree — exactly the scenario the uninstall block refuses loudly.
2. **OPENCODE_USER from the same hand-editable install.conf stays unshaped**
   at every consumer outside uninstall.sh: config.sh:103-107 → :351 (the
   *writer's* agent-home refusal `[ "$_pp" = "/home/${OPENCODE_USER:-opencode}" ]`
   — a value like `opencode/` makes the comparison miss, so the agent home
   becomes storable as a project root and feeds the loops above), update.sh:441,
   status.sh:72 (both fail loud downstream per D2). D2 also named
   setup-container-backend:87 → :177 (raw value appended to /etc/subuid) —
   main-session verification defuses that arm: the script's own
   `id "$OPENCODE_USER"` gate (:89-90) exits loud before any write, and a
   value that passes `id` is a real username, which cannot carry colons or
   newlines. The arm is recorded as defused, not as exposure.

Severity MED: the precondition (hand-edited root-owned conf) is the same one
#243 e X1 itself accepted as real enough to gate. Provenance: fix-induced —
the sweep gap was born with the #243 disposition inside this range; the
ungated readers themselves are pre-existing.

### F3 (MED) — six rc-blind success claims survive the sweep that claims to have swept them

uninstall.sh:745-750 comments: "rc-observing removal (#243 a S1/S2 — the
#211 c W1 class sweep this wave owes): the former `run` ops fed an
unconditional 'Removed.' + success log even when an rm failed. Same ops
through un_rc_q now". The sweep armed the config-dirs, audit-log, gpasswd,
userdel and wsl-bridge sites (all verified rc-gated) — but six same-shape
sites in the same file still run rc-blind `run` and then unconditionally
claim success on stdout and in the audit log:

- :264-266 sudoers rm → "sudoers removed." + log
- :314-316 wrapper rm → "Wrapper removed." + log
- :320-322 cli dispatcher rm → "CLI dispatcher removed." + log
- :331-333 xdg-open shim rm → "xdg-open fallback removed." + log
- :421-423 library `rm -rf` → "opencode library removed." + log
- :455-460 umask profile rm ×2 → "Umask profile removed." + log

The sudoers site is the load-bearing one: a failed root rm (immutable
attribute, read-only mount) yields "Uninstall complete." over a surviving
passwordless sudo rule for the agent user. Rare conditions — precisely the
class's premise at the armed sites. Provenance: the six sites are
pre-existing (bounded by the taxonomy refactor 72d474a, ≤ 0.0.29); the
misleading sweep-claim comment at :745 is delta-born (#243 a-wave).

### F4 (MED) — settings-handover pairs sit beyond the walk residual the #234 fix documents

The exec-time component walk (`_ddev_components_sane`) fires once per
`.ddev` iteration, hoisted above the conform probe (d1dcf34, #234 a W1):

```sh
# ddev-handover.sh:609
if ! _ddev_components_sane "$dhr_root" "$dhr_d"; then
```

The fix's own comment states why the walk must cover the whole iteration:
"the settings pairs' own gates cannot catch a relocated project root —
their resolved containment (0.0.42e S2 / 0.0.42f S1) canonicalizes BOTH
sides through the swapped parent, so the victim stays 'contained'"
(:592-600). That is exactly the residual: a parent swap landing *after*
the gate passes every downstream gate — the leaf `[ -L ]` checks
(:721, :800) and the containment both resolve through the swap — and the
settings pairs' root `chown -R`/`chmod -R` (:720-722, :799-801) act on the
swap-chosen out-of-tree target. Their window spans the entire `.ddev`
recursive pair (:641-643), strictly wider than the gate→op residual the
fix documents for the `.ddev` pair itself (:633-639). The registered root
is agent-group-writable by design (baseline `g+rwxs`), so the agent's
group can rename a project dir inside `root` at any time. Rated MED (not
the #211 a F1 HIGH class) because a statically planted swap is caught at
gate time — the attack needs a live race mid-iteration — and the gate
genuinely narrowed the exposure versus pre-#234. Per the class-sweep rule
("a class fix counts only after all same-shape sibling sites are swept",
agent/learnings.md L2), the sweep stopped at the `.ddev` pair.
`ddev_handover_project_root` (:664) is single-inode with its own leaf gate
— outside this finding. Provenance: fix-induced — the asymmetry was born
in-range (395fee7 #215/#234 + d1dcf34); the sibling pair sites themselves
are pre-existing (0.0.45e era).

Cross-check against the C1/D1 clean verdicts (kept): C1 verified the
containment has no false-negative path and D1 verified the walk plus its
documented residual — both checked a different question (correctness of
what exists) than C2 (what the sweep left adjacent); the verdicts and the
finding are consistent.

### F5 (MED) — the getting-started prerequisites bullet contradicts the installer's hard gate

```markdown
<!-- docs/getting-started.md:9-11 -->
- `sudo` access, `curl`, `python3` — the installer probes `python3` missing
  or broken; the baseline still applies without it, minus the live counters
```

vs the probe both #244 arms of which abort:

```sh
# install.sh:574-586
if ! command -v python3 >/dev/null 2>&1; then
    ui_error "python3 is required but not installed (apt install python3)."
    exit 1
fi
if ! python3 -I -c "$_py3_imports" >/dev/null 2>&1; then
    ...
    ui_error "python3 is present but broken (shim? corrupt install? ...) — fix it and re-run."
    exit 1
fi
```

In a Prerequisites list the sentence tells a user without a healthy python3
that install will merely detect the state and proceed degraded — reality is
a hard refusal in both arms. The same list is abort/warn-precise everywhere
else (git ≥ 2.30: "the installer never aborts over git"; ddev: "the
installer aborts on older versions"). The sibling sentences are correct
(sharing-group.md:64-67 and cli.md:311-312 describe the *component* degrade
that fs-baseline performs on an installed kit). The bullet's current shape
was condensed by 510566e (#244 merge follow-up), whose ledger line lists
"baseline runs without python3 + one warning" as a kept claim — a component
claim transplanted onto the installer. No test-docs pin guards this
sentence. Provenance: delta-introduced (510566e).

## LOW findings detail

**F6** — install.sh:713-722: all five backup copies (two gitconfig dumps,
sudoers, binary, `cp -r` of the lib) silence cp with `2>/dev/null || true`;
the summary at :2612 (`ui_kv "Backup" "$BACKUP_DIR"`) and the header at
:51-52 ("recovery material after a failed run") announce the dir
unconditionally. Trigger: /tmp full or read-only mid-install (`BACKUP_DIR`
is `mktemp -d /tmp/opencode-install-backup.XXXXXX`, :708). Best-effort by
design; the failure path has no pin. Pre-existing, first shipped ≤ 0.0.17
(f36dec1).

**F7** — update.sh:724-727 (sudoers) and :745-751 (umask): the skip arms
emit `log` only; the openchamber divergence skip right below (:766-769)
shows the `ui_warn` contrast. With log.sh missing from both lookup roots,
`log()` is the `:;` stub (:343-349) and the skip is fully silent by
construction — violating the arm's own comment ("the skip must not be
silent"). Verification scopes the finding to that stub residual: the
terminal-quiet-but-logged shape itself was the #211 a F6 disposition
("skip is logged, not silent" is a pinned PASS in test-update-flags).
A2 dissents (documented-deliberate, 0.0.41f S2) — recorded; the
stub-logger case is the part no disposition covers. Pre-existing since
0.0.42 (0d2e349, the 0.0.41f S2 fix).

**F8** — install.sh:1371-1372 (plan phase) and :1814-1815 (`b` menu arm):
`getfacl -R $PROJECTS_ROOTS 2>/dev/null > "$BACKUP_DIR/…"` || true` under
"Project ACLs backed up to …" / "Backup saved." — the pre-flight probes
only `command -v setfacl` (:739, :744, :895; no getfacl probe exists), so
an acl package with setfacl-but-no-getfacl passes and both sites claim a
backup that is an empty file. The mkcert block shows the house shape
(verify the artifact after a swallow). Pre-existing since 0.0.10 (534bc3e,
the setup.sh split).

**F9** — uninstall.sh:230: the shape-gate WARN interpolates the raw
rejected `OPENCODE_USER` the charset case just classified as out-of-allowlist
(which includes newlines/escapes). Quoting is correct, no argv crossing;
impact is forged-looking transcript lines from an admin-paste-corrupted
conf. LOW per conventions.md having no rule for the echo-of-rejected-value
shape. Fix-induced: born with the gate (#243 e X1, 2632c36).

**F10** — uninstall.sh:603: `if [ "${root%/}" = "/home/$OPENCODE_USER" ]`
— the refusal (born #243 c Q1, in-range) hardcodes the /home spelling while
the kit's own pattern for the same user is getent (opk handover filters;
status.sh:279-280 "relocated homes must not blank the verdicts"). B2's
trigger claim did not survive verification: install.sh:1191-1205
(reuse-guard-home, 0.0.44a V15) refuses a pre-existing agent user with a
deviating home, so every kit-managed agent has home == /home/<name>. The
surviving residual: a post-install hand-moved home (`usermod -d`) whose new
path is registered as a project root — the revert ops then run over the
agent's config-carrying home. Writer parity is exact and honest (config.sh
:351 shares the blind spot). Delta-introduced (the reader refusal);
writer arm pre-existing.

**F11** — status.sh:542-551: the #244 c S3 wave dropped `2>/dev/null` from
the advisory feed parse; the `try` guards only `json.load`. A valid-JSON
dict envelope iterates its keys in `for entry in feed or []` →
`AttributeError` traceback on stderr (ungated by tty — cron picks it up);
an array of scalars does the same. rc stays 1, `ADV_PARSE_OK` false, the
rendered row stays the correct uncounted unknown — noise, not a verdict
bug. The wave's other sites (jsonc-parser, leak-scan) print clean one-line
errors. Delta-introduced collateral of #244 c S3.

**F12** — opencode-as-opencode:246 accumulates `_oc_bins="$_oc_bins
$_oc_path"`; :290/:298 print `rm -f$_oc_bins` inside note strings. The
expansion is quoted (no executed-code violation — verification corrected
C1's conventions.md:85-86 cite); the defect is the copy-paste advice: with
spaces in $HOME the pasted command word-splits (rm -f refuses the directory
operand — mostly errors), with glob metacharacters it expands in the user's
shell (the actual deletion vector). The same pattern in bin/opk:295 is
properly quoted. Pre-existing since 0.0.48 (fa50601).

**F13** — setup-container-backend:327-328: `systemctl --user start
docker.service 2>/dev/null || true` then :334 "docker-rootless is ready"
plus the socket line to record — the exact `|| true` + unconditional
success class the same file fixed for linger (:191-207, #211 a F13).
Mitigation in the same breath as the severity: the wrapper re-probes the
socket at every session start (opencode-as-opencode:547-556, loud
"Running WITHOUT container tools") — silent at provisioning time only.
Pre-existing (bounded by 72d474a, ≤ 0.0.29).

**F14** — fs-baseline.sh:353 and ddev-handover.sh:565 gate the root with
`[ -d ]`, which follows symlinks; `find -P` on a symlinked root argument
emits nothing, so all four `_fsb_pass` runs green on an empty stream,
`_FSB_ERRORS` stays 0, the caller prints the success line the file's own
contract forbids (:377-385 "must not print over a baseline that did not
fully apply") — and update.sh:905-906 writes the scan-skip stamp
unconditionally, so routine updates never retry (only `--refresh`).
Registration keeps symlinked paths (project_path_sane never resolves
them; the `cd && pwd` registration preserves them). Consequence: the
"agent cannot write project files weeks later" failure the contract names;
no privilege gain. Pre-existing.

**F15** — uninstall.sh:687-688: the revert chown classifies at scan time
(`find ! -type l`) and never re-checks the operand at exec time — the
#211 a F1 shape, applied to `_fsb_pass` with per-entry rechecks but not
swept here. The ordering mitigation (userdel before the loop) fails
exactly when userdel fails on a live straggler process — its documented
cause (:541-545) — and that failure is WARN-and-continue (:556-564), so
uninstall proceeds into the loop with the adversary live: a scanned
regular file swapped for a symlink mid-find makes the root-run
`-exec chown` retarget an arbitrary path to dev:group (ownership
corruption; no direct agent gain). Pre-existing shape; the line was
touched in range (run_q → un_rc_q rename).

**F16** — test-skills-lint.sh:15-17 (header): "every entry under
.agents/skills/ is a skill directory with a SKILL.md (a bare .md at the
skills root would load too, but the house shape is one directory per
skill)" vs :93-94 `for _d in "$_root"/*/; do [ -d "$_d" ] || continue` —
directories only; a bare file at the skills root is never examined and the
lint reports clean. The directory-without-SKILL.md case is pinned; the
bare-file-at-root case is the header rule's own hole. Delta-introduced
(the whole file, #235).

**F17** — conventions.md:202-210 requires `#NNN <letter> <ID>` qualifiers.
Delta-introduced bare refs (verified as added lines in 0.0.56..master):
test-skills-lint.sh:338, :343, :347, :351 (`(b S3)`, `(b B1)`, `(c S1)` —
the same file qualifies others as `#235 c S1` at :53); test-docs.sh:210
(`a-W1 class`); test-kit-cli.sh:888 (`e-S1 class`);
test-ddev-as-opencode.sh:1031, :1048 (`b W7 shape`, `b W6 class`);
test-fs-baseline.sh:530, :772 (`b-S2 shape`). Ten sites (E1 reported ~9;
count corrected). Pre-existing siblings for the sweep:
test-status.sh:1152/1154 (`W2 class sweep`), test-container-backend.sh:450
(`(c W9)`), test-fs-baseline.sh:446 (`b W6 class`). The #259 a Q1 sweep
declared the class swept scoped to test-rules-revisit.sh while the same
range kept introducing the shape elsewhere.

**F18** — test-docs.sh:201: the W1 root-file-type extraction sed + `head -n 1`
sees only the first `codeigniter|…)` arm; today complete (:466 is the only
root-file arm), the comment claims "every root-file type ddev-handover.sh
matches" — a future second arm silently escapes direction A of the pin.
Delta-introduced (the #256 guard).

## INFO notes

**F19** — install.sh:1965: bare `curl -fsSL https://opencode.ai/v2/install |
bash` — aborts loud with curl's own stderr (no silence), but without the
kit-level error line + next-step hint every neighboring deploy uses
(:1887-1889). Pre-existing since 0.0.56 (cea5da4, the #197/#224 v2
bootstrap).

**F20** — uninstall.sh:662: the reader blocklist arm `/lib*` replaces
0.0.56's `/lib|/lib/*|/lib64|/lib64/*` — fail-closed, arm-for-arm parity
with the writer (config.sh:331 area), loud skip echo. Delta-introduced
behavior change, recorded.

**F21** — opk:305-327: the four-cause rc-1 branch is deliberate (#244 h S3,
pin separates via empty stderr); the manual-removal hint names the
"opencodeBinary" line even on a value-only grep match. Fix-induced wording
residue.

**F22** — tui-plugin.sh:44-64: gate (agent_home_sane, leaf `[ -L ]` pair)
then ops (mkdir/ln/chown or rm -rf with `:?` guard) with no adjacent
re-check — the house-accepted shrunk residual, recorded for the L5 ledger.
Pre-existing.

**F23** — the component walks start below the scan root (ddev-handover.sh
:540-551 sets `_dcs_pre="$_dcs_root"` and tests components of the rest;
fs-baseline worker same shape): the root itself is never `[ -L ]`-tested.
Trigger needs write on the root's parent — outside the agent threat model
(ancestors carry traverse-only `g:<group>:X`, fs-baseline.sh:78). The new
#234 gate copied the pre-existing walker shape; delta shape over a
pre-existing gap.

**F24** — ddev-handover.sh:575-576: `find … -prune -print | while read` —
a newline in a `.ddev` dir name splits the operand; gates then act on a
same-tree lexical prefix (every prefix of a scanned path under the root is
a real dir inside the tree). Bounded; `-print0` exists in the kit
(ddev-as-opencode). Pre-existing (≤ 0.0.29 bound).

**F25** — secure-binary.sh:38-39: `chown` before `chmod 750` on the live
name after the atomic mv — ms-wide cp-natural-755 window; the atomic file
helpers land the mode before the rename. Public binary, hardening not
secrecy. Pre-existing.

**F26** — `seq` is load-bearing in test-skills-lint.sh:221 (401-byte
description fixture) and test-line-length.sh:163-172 (probe fixtures,
delta-extended) but absent from tests/check-host.sh's required-tool list;
failures are loud (PIN/PROBE BROKEN). Delta-introduced hint gap.

**F27** — pr-00259/resolution.md:3: the Status line quotes the maintainer's
German round-b report verbatim — evidence, not shipped content; parses as
`closed`; recorded as a corpus-hygiene note on the format-bound line
(README "Resolution format" binds lines from 2026-10-24 on). No house rule
violated; no disposition implied.

## Retracted / ghost findings

No finding was retracted. Held candidates and verification corrections,
recorded for calibration:

- **E1 held candidate (not reported):** a multi-line YAML block-scalar
  `description:` would pass the 400-byte check (only the first line is
  extracted) — E1 held it as speculative (no realistic trigger named);
  the loader-side behavior is unverified here too. Left as a checkpoint
  ghost, not a finding.
- **E1 killed candidate:** `rm -rf "$GENDIR"` in test-reviews-parity.sh's
  trap — correctly killed by E1 itself against conventions.md:142-150
  (pure-variable operands are exempt from the `:?` rule).
- **Evidence corrections applied during main-session verification** (the
  findings stand, the recorded evidence was fixed): A1's line anchors
  (backup summary is :2612 not :2636; curl pipeline :1965 not :1987);
  C1's damage analysis for F12 (rm -f refuses directory operands — the
  glob-metacharacter path is the deletion vector, not the space path);
  E1's site count for F17 (~9 → 10); B2's trigger claim for F10
  (install.sh:1191-1205 refuses home deviation on reuse — the
  relocated-home-at-install scenario cannot arise); D2's /etc/subuid arm
  for F2 (defused by setup-container-backend's own id gate :89-90).
- **Twin false-cleans caught by the sibling agent** (both directions,
  resolved by main-session reads): E1 blessed getting-started.md:9-11 as
  matching the probe (F5 disproves it — E1 checked the abort behavior and
  still read the sentence as the component-degrade claim); E2's citation
  sweep reported "no unqualified letter-ID refs in living files" while
  F17's ten sites are directly greppable (E2's grep pattern missed the
  bare shapes).
- **Axis-brief errata (commissioning side, disclosed):** the C-axis brief
  named `sh/sem.sh` as a standing sibling and the B-axis brief used the
  term `screen()` — neither exists in the tree (both terms were taken
  from pr-00244-era commit messages). C1 and B2 each verified the
  nonexistence and recorded it; no coverage hole resulted.

## Clean verdicts (axes' verified-clean areas, main-session spot-checked)

- **The 0.0.56..master delta in files/ carries no unpinned fail-soft spot**
  — all five axes that read it concur (A1, A2, B1, B2, C1, C2, D1, D2,
  E1, E2 where their slices overlap): the #244 python3 health gate
  (absent/broken/hostile-PYTHONPATH/noisy matrix + import-union pin), the
  #244 stderr passthroughs (resolve, advisory, leak-scan, status probe,
  ddev json get, tui unregister — expected paths silent, broken
  interpreters loud), the #234 component walk itself (trailing-slash
  normalization, loud `/` refusal, leaf-inclusive, whole-iteration skip
  semantics), the #243 revert-log chain (per-op rc, closing conditions,
  per-spelling negatives, shape gate placement before all argv uses), the
  opk settings-edit sudo-context guard (argv + heredoc passthrough +
  fail-closed sys.exit(1)).
- **Channel chain** (env > stamp > master, charset gates, re-stamp,
  status display, docs) and **strict version probes** — clean (A1, A2, E1).
- **KIT_FILES parity**: install.sh fetch list == update.sh KIT_FILES ==
  deploy-lib manifest == disk — 43 entries, set-equal, canary-pinned
  (test-kit-files.sh). A1's "41 entries" was a miscount (corrected);
  E1's 43 verified by main-session count.
- **project_path_sane twins** (install.sh:979 / config.sh:311): identical
  modulo indentation (main-session diff; parity pinned by
  test-project-paths.sh) — the pr-00211 a F32 drift hazard is closed at
  this tag.
- **Wiring**: 42 unit suites on disk = 42 CI steps = 42 make-test targets;
  test-skills-lint wired in all four places; exec-bit invariant (42×755,
  baseline txt 644 as data); line-length baseline entries all exist.
- **Docs flag/channel tables** match the parsers (cli.md, update.md,
  uninstall.md); docs/README.md indexes every page; the #244 python3
  sentences in sharing-group.md and cli.md describe the component
  degrade correctly (only getting-started.md:9-11 — F5 — conflates it
  with the installer).
- **Soft-only model**: no deny ACLs / chmod-000-as-deny anywhere;
  sudoers.template carries exactly the four documented `(opencode)`
  rules; visudo pre-validates the rendered file; charset gates DEFAULT_USER
  including `ALL`.
- **wsl.conf consent chain** end-to-end: sole carrier writer is the
  opt-in `opk wsl-add-opencode-1-fix` arm; install/update deploy the
  stand-in + sanctioned legacy strip only; uninstall asks; writes atomic.
- **Fail-open/fail-loud contracts**: wrapper hot path fails open by
  design at every probe site; root provisioning, the health probes and
  un_rc_q fail loud; the pr-00211 a F2 config.sh stub disposition is
  complete (every mutating stub loud).
- **Suites' pins** (sampled across the delta suites): pins sit before
  their summary gates; extraction tripwires on every sed-scraped block;
  environment-dependent pins uid/setsid/bash-marked; sandbox policy
  conformance enforced by test-sandbox-policy.sh (self-probing).
- **Reviews corpus structure**: 32 case folders == 32 INDEX rows (before
  this case); all new-format resolutions carry parseable Status lines.

## Run provenance

- **Tree**: working tree at 4eacabb (branch release/0.0.57, porcelain-clean
  throughout the pass; the only untracked residue is gitignored
  `py/__pycache__`, not a release artifact). Reviewed delta
  0.0.56..master (c979654..c38f9e5); the tree is one VERSION-chore commit
  ahead of the diff head (4eacabb vs c38f9e5, VERSION file only).
- **Fan-out**: 10 reviewer subagents (zai-coding-plan glm-5.3-flash),
  5 axes × 2 independent, staged launch with backfill at ≤ 5 concurrent
  (one seat per axis first: A1, B1, C1, D1, E1 at 2026-10-25T17:39:26Z
  host time; twins A2, B2, C2, D2, E2 backfilled as seats freed; last
  return 2026-10-25T18:14:38Z — ~35 min wall for the whole staged run).
  Checkpoint discipline per review-concept "Parallel reviewer agents":
  side files under /tmp/opencode/pr-00263-a/checkpoints/ (A1…E2), one
  line per section, launch/return timestamps per agent (sandbox clocks,
  normalized against the host window). The checkpoint files are absorbed
  by this provenance section; the snapshot renumbers all agent IDs into
  the F-scheme with the original IDs in the "Reported by" column.
- **Verification**: every finding re-verified by the main session
  (GLM-5.3) by code read — including the git dating for provenance
  (`git log -S`/`-L` + `git tag --contains` for the pre-existing classes:
  ≤ 0.0.29 bound 72d474a for F1/F3/F13/F24; 0.0.17 f36dec1 for F6; 0.0.42
  0d2e349 for F7; 0.0.10 534bc3e for F8; 0.0.48 fa50601 for F12; 0.0.56
  cea5da4 for F19).
- **No mutation windows**: the tree stayed porcelain-clean through the
  entire fan-out (re-checked at launch and after the last return); no
  sabotage spot-checks ran during reader windows (all probes read-only;
  the suites wrote only to /tmp and gitignored caches).
- **Gates on this host** (kit-managed checkout, agent user `opencode`,
  UID-separated), run before the snapshot commit on the clean tree:
  `make test` rc=0 (lint + check-py + all unit suites, incl. sandbox
  policy, release helper, pages, rules parity 118 rows);
  `sh tests/unit/test-reviews-lint.sh` OK (32 cases);
  `sh tests/unit/test-reviews-parity.sh` OK (32 rows);
  `sh tests/unit/test-line-length.sh` OK (662 lines over 120, all at
  baseline). The e2e suites are not owed by this snapshot (no shipped
  code changed) and remain the release-gate item
  (agent/review-concept.md, "Release gate": both e2e suites at baseline
  with zero skips before the tag).
- **Environment**: opencode v2.x agent harness, house instance
  (GLM-5.3 strong tier main session; glm-5.3-flash reviewer tier; the
  plan's glm-5.3-highspeed is listed but not accessible on this
  subscription — verified by a smoke test during pre-flight).
- **Provenance split (finding level)**: pre-existing 12 (F1, F3, F6, F7,
  F8, F12, F13, F14, F19, F22, F24, F25); fix-induced 4 (F2, F4, F9, F21
  — sweep gaps and residues of the #243/#234/#244 dispositions inside
  this range); delta-introduced 10 (F5, F10, F11, F16, F17, F18, F20,
  F23, F26, F27); pre-existing-shape-touched-in-range 1 (F15). The delta
  itself introduced no HIGH/MED in shipped code — F5 (MED) is docs, and
  F2/F4 (MED) are sweep gaps of in-range fixes whose gated sites are
  correct.

## Calibration

Reserved for the second snapshot: the external redundancy pass (different
model family, bias-reduced sparse checkout, without house skills — the
maintainer's setup per internal/process/review.md, "External review
machines") has NOT run as of this snapshot; the maintainer commissions it
separately and its results are integrated with a calibration section
naming what each side missed. Twin-agreement data recorded here for that
comparison: the two E-axis twins produced one false-clean each in opposite
directions (E1 on getting-started:9, E2 on the citation sweep — see
"Retracted / ghost findings"), both caught by main-session verification;
the A-axis twins fully concurred (including the A1/A2 dissent on F7's
severity rationale, recorded under F7); the C-axis twins and D-axis twins
each produced one axis-exclusive MED/LOW set (C2-1/C2-2 vs D1-1/D1-2)
with three cross-agent merges (F2, F14, F23).

## Recommendation

**Fix-before-tag, no release blocker of the HIGH class.** The 0.0.57 delta
introduced no HIGH/MED in shipped code (the MEDs: one docs contradiction
of a hard gate, two sweep gaps of in-range fixes, two pre-existing
honesty/security classes). Suggested disposition order: F5 (one-sentence
docs fix, user-facing), F2 + F4 (the two sweep gaps — extend the #243
reader gates to update.sh's loops + shape OPENCODE_USER at the config.sh
writer; give the settings pairs an adjacent re-walk or document their
residual like the .ddev pair's), F3 (arm the six uninstall sites through
un_rc_q as the :745 comment already claims), F1 (leaf-gate or unlink-first
the dump operand; the unverified ddev overwrite behavior is worth one
probe in the e2e-ddev lane). The LOW/INFO tail fits one normal fix wave.
Every disposition owes its pin in the same wave (the F1/F4 fixes are
root-run semantics — both e2e suites in that wave; agent/AGENTS.md
Testing). Release gate (agent/review-concept.md, "Release gate"): both
e2e suites at baseline with zero skips before the tag — unit baseline is
green and recorded above. The loop stays open: this snapshot is the hard
seam; the fix wave starts on the maintainer's go, and every round owes
its wave review.
