# Resolution — pr-00243 (#218 uninstall revert-loop closing-log honesty)

Chain: [review-a.md](review-a.md) (wave snapshot 2026-10-24, 11 findings,
3 reviewer axes, all verified) → fix wave 1 (all 11 implemented) →
[review-b.md](review-b.md) (fix-wave snapshot 2026-10-24: 8 findings, 7
verified + 1 ghost retracted; all 11 a-fixes audited landed) → fix wave 2
(b S1/S2/X1/Q1/Q2/Q4 implemented — X1 differently, see row; b X2 held in
Follow-up 1; b Q3 retracted, no defect) → [review-c.md](review-c.md)
(fix-wave snapshot 2026-10-24: 11 findings — 3 MED after the X1
adjustment, 3 LOW, 5 INFO; all 6 b-fixes audited landed) → fix wave 3
(c S1/S2/X1/Q1/Q2/Q3/Q5 implemented; c X2 held for #247, c X3 for
#245, c X4/Q4 deliberately not done) → [review-d.md](review-d.md)
(fix-wave snapshot 2026-10-24: 13 findings — 1 MED, 3 LOW, 9 INFO; all
7 c-fixes audited landed) → fix wave 4 (d X2/S1/S2/X4/Q1/Q2/Q3/Q4/Q5
implemented; d X1 implemented differently — comment scoped, mirror
decision rides #247; d S3/X3/Q6 deliberately not done). Birth PR #243,
branch `feature/218-uninstall-revert-log-honesty`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a S1 (MED) | **implemented** | `a31e62b` | config-dirs rms through un_revert_q; degraded closing + WARN; 4 cfg arms |
| a S2 (LOW) | **implemented** | `a31e62b` | openchamber rm rc-observed; FAILED log + WARN pinned on stderr |
| a S3 (LOW) | **implemented** | `a31e62b` | two-root arm: root 2 closes clean, root 1 degraded — reset per-root |
| a X1 (LOW) | **implemented** | `a31e62b` | degraded line "revert PARTIALLY completed (causes)"; no false clause |
| a X2 (LOW) | **implemented** | `a31e62b` | form gate (absolute + dot/empty arms); //etc, /var/. and . skipped |
| a Q1 (MED) | **implemented** | `a31e62b` | docs: template with <gid> placeholder; the template string pinned |
| a Q2 (LOW) | **implemented** | `a31e62b` | docs: stderr WARN + audit-log "PARTIALLY completed" as the surfaces |
| a Q3 (LOW) | **implemented** | `a31e62b` | driver splits streams; WARN-channel pin (stderr section only) |
| a Q4 (LOW) | **implemented** | `a31e62b` | _unarm_show: red arms print log:/WARN:/skip lines, not the sudo-call tail |
| a Q5 (INFO) | **implemented** | `a31e62b` | dry arm pins the sudo-log section empty |
| a Q6 (INFO) | **implemented** | `a31e62b` | comment: 4 call sites vs 6 invocations with both gids |
| b S1 (LOW) | **implemented** | `1d07e2a` | block-identity awk extraction; parity pin is the second lock |
| b S2 (LOW) | **implemented** | `1d07e2a` | cfg driver plants a stale pre-state; all cfg arms red on deleted reset |
| b X1 (INFO) | **implemented differently** | `1d07e2a` | writer parity minus /tmp,/var/tmp; parity + behavioral pins |
| b X2 (INFO) | **deliberately not done** | — | Follow-up 1 owns the update.sh loops (verified TRUE in snapshot b) |
| b Q1 (LOW) | **implemented** | `1d07e2a` | _unarm_show families completed (Removed./[DRY]/sudo-log/skip echoes) |
| b Q2 (LOW) | **implemented** | `1d07e2a` | openchamber arm sets the flag; cfg WARN gated like the loop closing |
| b Q3 (INFO) | **deliberately not done** | — | retracted as ghost in snapshot b — no defect exists |
| b Q4 (INFO) | **implemented** | `1d07e2a` | renamed un_rc_q; sites, comments, extraction anchors, canaries swept |
| c S1 (INFO) | **implemented** | `822e7a0` | extractor is a function; block-identity pin drives it (decoy fixture) |
| c S2 (INFO) | **implemented** | `822e7a0` | family pin feeds every family through _unarm_show |
| c X1 (MED) | **implemented** | `822e7a0` | one-trailing-slash strip after the dot gate; // stays the gate's catch |
| c X2 (MED) | **deliberately not done** | — | #247 wave scope (writer-side, both validator copies, e2e owed there) |
| c X3 (LOW) | **deliberately not done** | — | #245 owns it; snapshot c measured find + chmod tails |
| c X4 (INFO) | **deliberately not done** | — | restates the recorded a X2 disposition (space arm ungated) |
| c Q1 (MED) | **implemented** | `822e7a0` | lexical agent-home refusal before `[ -d ]`; arm host-independent |
| c Q2 (LOW) | **implemented** | `822e7a0` | tail -6 window removed; every family surfaces on red |
| c Q3 (LOW) | **implemented** | `822e7a0` | fed set built by host existence; assertions name only fed roots |
| c Q4 (INFO) | **deliberately not done** | — | intentional alignment with the loop closing order |
| c Q5 (INFO) | **implemented** | `822e7a0` | comments name all three bounded ops incl. chmod g-s |
| d S1 (LOW) | **implemented** | `09206ab` | 2 isolating fixture lines; ANY regex-alternative drop reds |
| d S2 (INFO) | **implemented** | `09206ab` | `_un_exist_roots` helper; deletion-red pin, host-independent |
| d S3 (INFO) | **deliberately not done** | — | comment-only construct; no pin without grepping comments |
| d X1 (LOW) | **implemented differently** | `09206ab` | parity comment scoped; space-arm mirror decision rides #247 |
| d X2 (MED) | **implemented** | `09206ab` | arm feeds raw + trailing-slash form; both echoes + op negatives |
| d X3 (INFO) | **deliberately not done** | — | writer-side; #247 owns (both validator copies, e2e owed there) |
| d X4 (INFO) | **implemented** | `09206ab` | screen() mirrors the strip; `/etc/` + `/var/` static forms |
| d Q1 (LOW) | **implemented** | `09206ab` | dead raw arm dropped; single stripped compare = writer shape |
| d Q2 (INFO) | **implemented** | `09206ab` | driver comment names all three literal env pins |
| d Q3 (INFO) | **implemented** | `09206ab` | setfacl negatives; both spellings in agent-home/malformed arms |
| d Q4 (INFO) | **implemented** | `09206ab` | find negatives anchored on the op line's ` !` continuation |
| d Q5 (INFO) | **implemented** | `09206ab` | wiring pin: wired SCREEN_PATTERNS free of dot/double-slash |
| d Q6 (INFO) | **deliberately not done** | — | writer-side; #247 owns (same shape family as d X3) |

## Evidence detail

### a S1 (MED) — config-dirs closing claim, and the class sweep record (L2)

Mechanism: the section's three `run sudo rm` ops go through `un_revert_q`
now (labels `rm /run/opencode-permissions-kit`, `rm 99-ddev-rootless.conf`,
`rm /etc/opencode-permissions-kit`); a failure lands in `_un_partial` and
the closing degrades to `WARN` + `log "config dirs + runtime artifacts
PARTIALLY removed (<causes>)"` instead of the unconditional `Removed.` +
success log. DRY keeps the `[DRY]` echoes and success lines (run/run_q
convention, #211 b W1). Pins: section 4d in tests/unit/test-uninstall.sh —
all-ok, openchamber-rm-failure (S2), two-rm-failure (accumulation, in
section order), dry — all green; suite green via `make test`.

Class sweep (pattern: `grep -n 'run sudo\|run_q sudo'` over
files/opencode-permissions-kit-lib/management/uninstall.sh, each site read
with its following log line):

- Converted this wave: the config-dirs section (3 rms + the openchamber
  pin, S2).
- Remaining same-shape sites — single-op `run sudo rm` followed by an
  immediate success `log` — deliberately deferred to a dedicated wave
  (each needs its own extraction + arms; the a F1 ddev-handover
  precedent, the same shape the #218 wave itself used for this loop):
  sudoers (240→242), legacy sudoers symlink (259→261), legacy conf legs
  (275→281/284), wrapper (290→292), cli (296→298), xdg-open shim
  (307→309), tui plugin (336), library (397→399), legacy library
  (409→411), legacy helper (419→421), umask profile (431+434→436).
- The teardown `run_q` sites (513-521: linger/stop/podman-reset/pkill)
  keep no success-claiming closer — their failure surfaces via the
  rc-observing userdel arm (verified in snapshot a, S-axis).
- install.sh/update.sh `|| true` sites are probe/capture shapes with no
  success-claiming closer (snapshot a, S-axis grep list).

### a S2 (LOW) — openchamber pin removal observes its rc

The rm is rc-observed inline (audit-log arm pattern, #211 c W1):
success logs `openchamber policy pin removed (kit-owned content only)`;
failure appends `openchamber policy pin rm failed` to the section's
partial list, WARNs on stderr and logs `openchamber policy pin removal
FAILED (rm)`. The rmdir stays best-effort (`|| true`, silenced) — an
unemptied dir does not falsify the pin-removed claim. DRY echoes both
`[DRY]` lines and keeps the success log. Pins: 4d openchamber arm
asserts the FAILED log, the stderr-channel WARN, the degraded section
closing, and the absence of the false success log + false full removal.

### a S3 (LOW) — per-root reset pinned

Driver gained an `<extra-roots>` arg (space-separated — the storage
format is space-free) and the stub fails ops boundary-matched on the
PRIMARY root only (`*"fakeproj "*|*"fakeproj"`) so fakeproj2 never
matches. The two-root arm: root 1 (find fails) closes degraded, root 2
closes full success with root 1's causes absent, and root 2's chmod is
in the sudo log (it really ran). A reset moved out of the loop turns
root 2's closing degraded → arm red.

### a X1 (LOW) — degraded closing never asserts the failed clause

The degraded line is now `project revert PARTIALLY completed
(<causes>)` — it claims completion of nothing; the failed op is named
inline and the FAILED record follows separately. The find-chown arm
additionally pins `! grep 'ownership reverted'` on the whole output:
a chown-failure record can never read as "ownership reverted". All
degraded-wording assertions updated (find-chown, chmod, gid-unknown,
uid-unknown, two-root arms); the success line is unchanged.

### a X2 (LOW) — reader-side form gate

The loop now mirrors the writer's `project_path_sane` arms BEFORE the
system-path blocklist: non-absolute roots are skipped loudly, then the
dot/empty-segment arms (`*..*|/./|*/./*|./*|*/.|*//*`) — `//etc` no
longer slips past the blocklist (empirically confirmed in snapshot a
verification). Space-forms stay ungated at the reader: `[ ! -d ]` +
quoting make them safe, and a spaced path cannot lexically equal a
system path (no bypass shape); the writer rejects them for storage
reasons (0.0.39b C3).

Pins: the malformed-roots arm feeds `//etc /var/. .` as extra roots —
all three skip echoes asserted, `sudo find //etc` absent from the sudo
log, the primary root still processed. The static SCREEN_PATTERNS
extraction learned to filter the new `/*)` arm (it would splice as a
match-everything pattern; the form gate is pinned behaviorally instead).

Sweep (projects.conf consumers, `grep -rn 'projects.conf' files/`):
uninstall.sh loop (gated now); config.sh `projects add` validates via
`project_path_sane` (and its system-path blocklist); status.sh only
lists; install.sh writes via `sudo tee`. Sibling readers found beyond
the finding — update.sh `--refresh` baseline loop (1513-1519,
fs_baseline_root = chgrp -R + setfacl -R) and ddev-handover loop
(897-912) — have NO form gate (and no system-path blocklist at all):
recorded as Follow-ups F1 (own wave: fixture + arms + both e2e suites
+ the blocklist-parity decision).

RM-0113: this is a semantics change to a root-run script → both e2e
suites run in this wave (see Gates).

### a Q1 (MED) — docs tell the template truth

The sentence now says the uninstaller "prints a `setfacl` line to run
by hand once the orphaned group id is known, with a `<gid>` placeholder
to fill in" — no "exact call" promise (the kit cannot know the gid in
that branch; that is why it skipped). L3: the docs claim is pinned —
the gid-unknown arm asserts the template string
`remove manually: setfacl -R -x g:<gid> -d -x g:<gid>` verbatim.

### a Q2 (LOW) — docs name the real surfaces

The paragraph now names both channels: the terminal prints a WARN
naming the failed operation, and the audit log records the root as
revert PARTIALLY completed — linked to the audit-log reference page.
The old "the report says PARTIALLY removed" (audit-log-only wording
framed as terminal output) is gone; the stderr WARN is now documented
instead of undocumented.

### a Q3 (LOW) — channels separated, comments truthful

The driver captures stdout and stderr to separate files and emits them
as `--- stdout --- / --- stderr --- / --- sudo log ---` sections; the
find-chown arm pins the WARN inside the stderr section AND absent from
the stdout section — a `>&2`-to-stdout regression is caught. The 4c
header comment now states what is actually pinned: the log() ARGUMENT
(the real log() is file-only, sh/log.sh — the stub echo makes the
audit-log wording pinnable), not "the way the user sees it".

### a Q4 (LOW) — red-arm diagnostics show the asserted lines

`_unarm_show` greps the asserted line families (`log:` / `WARN:` /
`PARTIALLY` / `Skipping`) for the fail echoes; the old `tail -3/-4`
showed only the appended sudo-call log. All 4c/4d fail messages use it.

### a Q5 (INFO) — dry non-execution pinned

The dry arm asserts the `--- sudo log ---` section contains no line
starting with `sudo ` — a refactor that executes in dry mode while
dropping rc observation now goes red (the loop's sudo log is the
runner's only execution trace; the [DRY] echo alone proves nothing).

### a Q6 (INFO) — site vs invocation count

The runner comment now says "four call sites, six invocations when both
gids are known"; the closing-log comment says "every op site above"
instead of "the four ops".

### b S1 (LOW) — extraction keyed to block identity

The SCREEN_PATTERNS extraction is no longer shape-keyed: an awk state
machine keeps `/`-leading pattern lines only from the `case "$root"`
block whose body echoes "Skipping system path" — the form-gate blocks
(absolute `/*)`, dot/empty arms) are skipped whole, whatever their
lines look like, so a `/`-leading reorder of the dot pattern line can
no longer splice it in (the exact hazard the finding described). The
shape-keyed `grep -v '/\*)'` filter is gone. Second lock: the b X1
parity pin below compares the extracted set against the writer's — any
extraction anomaly, reorder included, reds the suite instead of
passing silently. Sweep (L2, pattern `grep -n 'SCREEN_PATTERNS'
tests/unit/test-uninstall.sh`): one extraction site, one consumer
(`screen()`); no other shape-keyed pattern filter exists in the suite.

### b S2 (LOW) — the section reset is pinned by a stale pre-state

`_un_cfg_out` no longer pre-initializes `_un_partial`/
`_un_revert_failed` clean (the masking the finding proved) — it plants
the dirty pre-state the real run leaves behind
(`_un_partial="find-chown failed (stale from the project loop)"`,
`_un_revert_failed=1`), which the shipped section reset must clear.
Every cfg arm discriminates now: all-ok/dry assert `Removed.` + the
success logs + no `PARTIALLY` + no `WARN:` + the stale string absent;
the failure arms assert exact degraded closings a leaked stale cause
would shift. Deleting the shipped reset reds the suite (spot-check
recorded in Gates).

### b X1 (INFO) — blocklist at writer parity, temp prefixes pinned out

Mechanism: the reader blocklist is rebuilt in the writer's arm order
from `project_path_sane` — adds `/home`, `/lib*` (replacing the
`/lib`,`/lib64` enumeration), `/media(/…)`, `/mnt(/…)`, `/opt(/…)`,
`/srv(/…)`, `/var` and the `/var/{cache,lib,log,mail,spool}(/*)`
families. **Implemented differently** on one point: the scratch
prefixes `/tmp` and `/var/tmp` stay processable — the sandbox policy
(agent/conventions.md, "Test sandbox (unit suites") pins unit-fixture
roots to exactly those prefixes (this suite's own primary root is a
mktemp path), and a temp-prefix conf entry is bounded
(uid/gid-matched chown + kit-gid ACL strip only). The divergence is a
pinned decision, not drift: allowed-reps assert `/tmp/x`,
`/var/tmp/x` processable, the parity pin excludes exactly those four
tokens, and the script comment names the rationale.

Pins: static rejected reps (/var /home /libexec/x /opt/x /srv/x
/media/x /mnt/x /var/log/x /var/lib/x /var/spool/x) + allowed reps;
set-equality parity pin (reader == writer minus the four temp tokens;
the writer side is shape-extracted but fail-loud — a stray `/`-leading
line in `project_path_sane` breaks equality, never silently passes);
behavioral loop arm feeding `/var /home /opt /srv /media /mnt` as
extra roots (skip echoes, no sudo op on them, primary root processes —
only host-existent dirs, because `[ ! -d ]` runs before the blocklist
and would skip a nonexistent path silently, defanging the arm).

Sweep (L2): projects.conf consumers re-checked — update.sh `--refresh`
and ddev-handover loops remain ungated (Follow-up 1, unchanged); e2e
project root `/var/www/vhosts/extra-project` unaffected (no `/var/*`
catch-all by design, writer and reader agree).

### b Q1 (LOW) — red-arm diagnostics cover every asserted family

`_unarm_show` now greps `log:|WARN:|PARTIALLY|Removed\.|\[DRY\]|
Skipping|skipped|unknown|^sudo ` (tail 6): covers the `Removed.`
closings (cfg all-ok/dry arms), `[DRY]` echoes (dry arms), sudo-log
lines (two-root arm, Q5 emptiness family) and the lowercase skip
echoes (gid/uid-unknown arms; the `<gid>` hint line contains
"unknown"). The comment names the families it actually shows.

### b Q2 (LOW) — the flag is read where it is written

The openchamber failure branch sets `_un_revert_failed=1`; the
config-dirs closing gates its stderr WARN on the flag (mirroring the
project loop's closing; the degraded log stays keyed on the partial
list). Behavior is identical today — every cfg cause is a failed op —
but the write-only trap is gone, and a future skip cause cannot
false-WARN. The wiring is pinned from both sides: the two-rm arm
redses when the RUNNER's flag-set is deleted (its gated section WARN
disappears), and the openchamber arm — extended by the spot-check
below — pins the section WARN
`(openchamber policy pin rm failed)` on stderr, so deleting the
openchamber-side flag-set reds it. The extension was the spot-check's
own finding: the arm as shipped in the fix commit asserted only the
ungated openchamber WARN, which survives a deleted flag-set — the
gate's wiring was unpinned until the arm learned the section WARN.

### b Q4 (INFO) — runner renamed to un_rc_q

`un_revert_q` → `un_rc_q` (def, `_un_rc_label`, 7 call sites, 2
comment mentions; test: extraction anchor, `UN_RC_Q` var, both evals,
the cfg canary). One archaeology line keeps the old name ("Renamed
from un_revert_q (#243 b Q4)"). Sweep (L2, `grep -rn 'un_revert_q\|
UN_REVERT_Q' files/ tests/ docs/`): exactly the archaeology comment
survives; docs never named the runner.

### c S1 (INFO) — the extractor is a function, and the pin drives it

The awk state machine moved into `_un_blocklist_tokens <file>`;
`SCREEN_PATTERNS` and the new pin call the SAME function — a drifting
second copy cannot exist. Pin: a fixture file with a decoy case block
(`/*)` arm, `/`-leading dot-form arms — the b-S1 reorder hazard
shape, backslash continuation) and one keep block echoing "Skipping
system path"; the pin asserts the output is exactly the keep block's
tokens (`/keep|/keep/*|/keep2`). A reversion to shape-keyed extraction
pulls the decoy arms in and reds the pin (sabotage spot-check 4).

### c S2 (INFO) — every diagnostic family is pinned

`_unarm_show` never executes on a green run (it lives in fail
messages) — the new pin feeds a fixture carrying one line per family
(log:/WARN:/PARTIALLY/Removed./[DRY]/Skipping/unknown/^sudo) through
the helper and asserts all of them surface, in order. Dropping a
family from the regex reds the pin (sabotage spot-check 5).

### c X1 (MED) — writer-parity trailing-slash normalization

Mechanism: after the dot gate, the loop strips ONE trailing slash
(`${root%/}`) and reassigns `root`, so `/var/` and `/home/` (the two
bare arms without `/*` siblings) hit the blocklist; `/` strips to
empty and is restored to `/` (the blocklist's `/` arm refuses it).
Placement is the wave's own finding: the strip must sit AFTER the dot
gate — `*//*` means "contains `//`", so every `//` form (incl.
`/var//`) is the gate's catch, and an early strip would turn `/var//`
into `/var/` and reopen the exact hole the fix closes (the first
implementation draft had that regression; caught by the glob probe,
pinned since — the arm feeds `/` and `/var//` explicitly).

Pins (behavioral, same driver): the trailing-slash arm feeds
`/var/ /home/` (existence-filtered) asserting the NORMALIZED skip
echoes (`Skipping system path: /var`), no sudo op on any fed form,
`/` skipping via the blocklist arm (anchored `: /$` echo, no empty
`Reverting` operand, no `sudo find / !`), `/var//` staying the dot
gate's malformed catch (echo pinned verbatim, no `sudo find /var/`),
and the primary root still processing. Sweep (L2): the loop is the
only projects.conf reader matching roots lexically against system
paths — update.sh loops have no gate at all (#247), status.sh lists,
projects_remove never ops on the root; the agent-home compare takes
its own raw-or-stripped form (c Q1 below).

### c Q1 (MED) — the agent home is refused lexically

Mechanism: right after `[ -z ]`, before the `[ -d ]` gate, the loop
refuses `/home/$OPENCODE_USER` comparing the raw AND the
once-stripped form (`/home/opencode/` must not dodge it); `//` forms
remain the dot gate's catch. Before `[ -d ]` on purpose: the refusal
is lexical and holds on hosts where the user or its home does not
exist — which is also what makes the pin host-independent: the driver
pins `OPENCODE_USER=untest-agent` and feeds `/home/untest-agent` (a
directory that never exists), asserting the skip echo, no root op,
and the primary root still processing. The blocklist comment now
names all three mirrored writer refusals (strip, case blocklist,
agent home) — the parity claim it makes is true again, and each piece
carries its own pin (c X1 arm, static reps + parity pin, c Q1 arm).

Sweep (L2, `grep -rn '/home/\$OPENCODE_USER\|/home/\${OPENCODE_USER'\
files/`): config.sh:351 refuses it (the origin, review 0.0.39a S4),
install.sh's validator copy refuses it (install.sh:970-973) — the
uninstall reader was the only missing mirror.

### c Q2 (LOW) — no diagnostic window

`_unarm_show` lost its `tail -6`: red arms with many sudo lines
(system-path, two-roots) can no longer push the asserted
discriminator out of the shown output. The S2 pin covers family
completeness; the window removal is asserted by the same pin (all
eight fixture lines surface).

### c Q3 (LOW) — existence-filtered feeds

The system-path arm builds its fed set by `[ -d ]` over
`/var /home /opt /srv /media /mnt` (FHS-optional dirs no longer
false-red the suite on minimal hosts); every assertion names only fed
roots and the pass line discloses the fed set. The trailing-slash
arm (c X1) and the agent-home arm (c Q1) use the same discipline
(`/home/` filtered; `/home/untest-agent` needs no host dir at all).

### c Q5 (INFO) — the bounded-ops list is complete

The divergence comments in uninstall.sh and the test now name all
three bounded ops — uid/gid-matched chown, kit-gid ACL strip, and one
setgid-bit clear (`chmod g-s`) — instead of "only" two.

### d X2 (MED) — the trailing-slash agent-home form is pinned

The agent-home arm now feeds BOTH spellings
(`/home/untest-agent /home/untest-agent/`) and asserts each skip echo
verbatim (the echo prints the RAW root, so the trailing-slash echo is
distinct), the absence of every root-op verb on the prefix
(find/setfacl both spellings/chmod — d Q3 below) and the primary root
still processing. Deletion-red, host-independent: the refusal is
lexical before `[ -d ]`, so reverting the comparator to raw-only (the
exact d X2 hazard shape) leaves the trailing-slash echo absent → arm
RED without needing the dir to exist (spot-check 1).

### d S1 (LOW) — every regex alternative is isolated

Two fixture lines added: `revert PARTIALLY completed (chmod g-s
failed)` (matches `PARTIALLY` alone — the old PARTIALLY line carries
`log:`) and `  skipped reverting ownership (not kit-owned)` (matches
`skipped` alone — no old line matched it at all). The identity
compare now reds when ANY of the 9 alternatives is dropped from the
regex (spot-check 2); the pin comment states the isolation claim.

### d S2 (INFO) — the existence filter is pinned host-independently

Both feed-set builders (system-path, trailing-slash) moved into one
helper `_un_exist_roots` (filter operand = feed operand
once-stripped, matching both arms' prior inline logic exactly). New
pin feeds `$WORK` (exists) plus `/opk-243d-nonexistent-root` (never
exists) and asserts only `$WORK` comes out — deleting the helper's
`[ -d ]` reds it on EVERY host (spot-check 3), where the old inline
loops could only red on hosts missing a fed dir. Sweep (L2, `grep -n
'\[ -d ' tests/unit/test-uninstall.sh`): line 776 (the helper) is the
only feed-side existence probe left; the other `[ -d ]` hits are
pre-existing pins about the agents-backup gate (505-524) and comments.

### d X1 (LOW, implemented differently) — the parity claim is scoped

The blocklist comment now carries an explicit scope paragraph: the
writer's whitespace refusal (`*[[:space:]]*`, a storage-format
refusal — 0.0.39b C3) is deliberately NOT mirrored, citing the
recorded a X2 disposition (spaced path ≠ any system path lexically;
`[ ! -d ]` + quoting defang), with the mirror-or-scope decision
routed to #247 alongside the other writer-side parity work. The
behavioral mirror was NOT added: it would overturn a disposition
recorded across four snapshots (a X2, b verified-clean, c X4, d X1)
without a maintainer decision — the defect fixed here is the
comment's over-breadth, which was the finding's falsifiable claim.

### d X4 (INFO) — the static helper mirrors the loop's strip

`screen()` strips one trailing slash (`/` restored to `/`) before
matching SCREEN_PATTERNS — the same normalization the shipped loop
applies — so a future static slash-form assertion pins the real
semantics. Pinned: the static rejected-reps loop now feeds `/etc/`
(`/*`-family arm) and `/var/` (bare arm, the c X1 hole shape), both
must stay screened (spot-check 5); the allowed reps are strip-identity
forms, unchanged.

### d Q1 (LOW) — one compare, exactly the writer's shape

The dead raw arm (`[ "$root" = … ]`, subsumed by the stripped
compare) is dropped; the predicate is provably equivalent (a raw
match implies no trailing slash, so the strip is identity on it —
precondition: `OPENCODE_USER` never ends in `/`, it feeds `id -u`
lookups at uninstall.sh:225 and is defaulted at :211). The comment
now describes the single stripped compare and why it covers both
spellings. Equivalence pinned by the d X2 arm (both forms refused by
the one compare). Sweep (L2, `grep -rn '] || \[ "\${[a-z_]*%/}" ='
files/`): no other dual-compare subsumption site exists in files/.

### d Q2 (INFO) — the env-pin comment is true

The driver comment now names all three literal env pins (UN_DEV_GROUP,
DEFAULT_USER pre-existing; OPENCODE_USER the c Q1 addition) instead of
claiming "the one env pin".

### d Q3 (INFO) — op negatives cover every op verb

setfacl negatives added to all four screening arms: system-path loop
and ts loop (`-x` spelling next to the existing chmod backstop),
malformed-roots and agent-home arms (BOTH `-x` and `-d -x` spellings,
plus find/chmod negatives for `/var/.` and `.` in the malformed arm
that previously had none). Sweep (L2, `grep -n 'sudo find\|sudo
setfacl\|sudo chmod' tests/unit/test-uninstall.sh`): every arm that
asserts ops absent for refused roots now names find, setfacl and
chmod; the two-roots arm's roots are processed (positive arm), not
op-negation sites.

### d Q4 (INFO) — find negatives are anchored

The ts loop's unanchored `sudo find $_un_ts` (matched any longer
/var-prefixed operand) is replaced by two ` !`-anchored forms —
`sudo find /var !` (normalized leak) and `sudo find /var/ !` (raw
leak, strip deleted) — and the `/var//` standalone check by
`sudo find /var// !` plus its setfacl/chmod siblings. Anchors bind to
the op line's literal ` ! -type l` continuation (uninstall.sh:663).
Sweep: the remaining unanchored find negatives (`//etc`, `/var/.`,
`/home/untest-agent`) are prefix-unique among their arms' fed
operands (no fed operand is a string-prefix of another), documented
here per L2.

### d Q5 (INFO) — the wiring is pinned, not just the function

New pin right after the c S1 fixture pin: the WIRED `SCREEN_PATTERNS`
must contain no dot and no `//` (case glob `*.*|*//*`) — the exact
tokens a shape-keyed wiring splice would leak (every form-gate arm
carries a dot or double slash; no legit system-path token does).
Reverting the wiring assignment to an inline shape-keyed extraction
redes it (spot-check 6) even though the function pin stays green —
that division of labor is now stated in both pin comments. A future
legit arm needing a dot reds it loudly and gets defanged consciously.

## Gates (fix wave 1, a findings)

- Unit: `sh tests/unit/test-uninstall.sh` green; `make test` green
  (all suites incl. sandbox policy, reviews lint/parity 29 cases).
- `make lint` green; `sh tests/unit/test-docs.sh` green; line-length
  ratchet green (this file ≤ 120 content columns); `make check-version`
  green.
- E2E (RM-0113, in-wave — X2 changes root-run screening semantics):
  `make e2e` green — 309 passed per container, opencode 2.1.4 from the
  warm cache; the uninstall pass exercises the converted section +
  revert loop (openchamber pin, project ACLs, 13a ownership revert).
  `make e2e-rootless` green — 47 passed per container (systemd-in-
  container podman-rootless). Tree: the fix commit's content (`a31e62b`;
  files/ identical between the runs and the commit).
  These runs also discharge the #218 wave's recorded e2e debt
  (observation-layer change riding to the release gate — snapshot a
  run provenance).
- Sabotage spot-checks (after the fix commit, per AGENTS.md; each:
  delete the construct, run the suite, observe the FAIL, restore from
  HEAD, re-run green):
  1. X2 form gate (malformed case block deleted): the malformed-roots
     arm RED — output shows `//etc` actually processed (the bypass the
     finding described).
  2. S1 closing conditioning (else-branch deleted, success
     unconditional): both cfg failure arms RED (openchamber + section).
  3. S3 per-root reset (loop reset lines deleted): the two-roots
     isolation arm RED — root 2's record carried root 1's cause.
  4. Q5 discriminating shape (dry branch executes silently, rc
     swallowed): the dry-run arm RED — and the pre-existing
     "--dry-run executed commands" pin caught it independently (two
     detectors).

## Gates (fix wave 2, b findings)

- Unit: `sh tests/unit/test-uninstall.sh` green; `make test` green
  (all suites incl. sandbox policy — the new `/`-literals are screening
  inputs, not operands of mutating verbs).
- `make lint` green; `sh tests/unit/test-docs.sh` green; line-length
  ratchet green; `make check-version` green.
- E2E (RM-0113 — b X1 changes root-run screening semantics; both
  suites run on this tree before the fix commit, files/ identical):
  `make e2e` green — 309 passed per container, opencode 2.1.4 from the
  warm cache; the uninstall pass + 13a ownership revert exercise the
  gated loop over the real project root `/var/www/vhosts` (allowed by
  the new blocklist, as designed — no `/var/*` catch-all).
  `make e2e-rootless` green — 47 passed per container.
- Sabotage spot-checks (post-commit against `1d07e2a`, each: mutate →
  observe RED → `git checkout --` → suite green; the first run of
  check 3 exposed a pin gap, closed in this commit's arm extension):
  1. b X1 blocklist (`/home` token deleted, one line): three pins RED
     — the static rep (`screening rejects /home`), the parity pin
     (set inequality) and the behavioral arm, whose `_unarm_show`
     diagnostics show `sudo find /home …` actually processed (the
     finding's hazard, demonstrated — via the new `^sudo ` family).
  2. b S2 section reset (both reset lines deleted): the cfg all-ok and
     dry arms RED — the planted stale cause leaks into the closing.
  3. b Q2 flag-set (openchamber `_un_revert_failed=1` deleted alone):
     the openchamber arm RED via the section-WARN assertion added in
     this commit — the arm as shipped stayed green (it pinned only the
     UNGATED openchamber WARN), the gap the spot-check surfaced.
     Runner-side twin (both flag-set lines deleted): the two-rm arm
     RED (gated section WARN absent).
  4. b S1 reorder (dot-arm line reordered to lead with `/./` — the
     finding's scenario): suite stays GREEN — the block-identity
     extraction ignores the line's shape.
  5. Parity drift (writer blocklist in config.sh extended by
     `/opt9|/opt9/*`): exactly the parity pin RED (1 test failed) —
     writer-side drift cannot pass silently.
  b Q1 (diagnostics-only, no pass/fail of its own): observed live
  during 1–3 — red arms now print the asserted families (`sudo …`
  lines, `log:`/`WARN:` records) that were invisible pre-fix.

## Gates (fix wave 3, c findings)

- Unit: `sh tests/unit/test-uninstall.sh` green — all arms incl. the
  five new/extended c arms (S1 fixture pin, S2 family pin, Q3-filtered
  system-path arm, X1 trailing-slash arm with the // and / regression
  pins, Q1 agent-home arm); `make test` green.
- `make lint` green; `sh tests/unit/test-docs.sh` green; line-length
  ratchet green (this file ≤ 120 content columns); `make check-version`
  green.
- E2E (RM-0113 — c X1/c Q1 change which roots a root-run script
  processes): both suites run on the committed fix tree `822e7a0`,
  in parallel (disjoint suites, warm cache):
  `make e2e` green — 309 passed per container (baseline level; the
  uninstall pass + 13a ownership revert exercise the gated loop over
  the real project root `/var/www/vhosts`, allowed by design).
  `make e2e-rootless` green — 47 passed per container (systemd-in-
  container podman-rootless; baseline level).
- Sabotage spot-checks (post-commit against `822e7a0`, in a scratch
  worktree at /tmp/opencode/pr-00243-c/sabotage — the main tree
  stayed clean for the parallel e2e runs; each: mutate → observe the
  named pin RED → restore → suite green at the end):
  1. c X1 normalization (strip lines deleted): the trailing-slash
     arm RED — `/var/` leaks to the ops, the finding's hazard live.
  2. c X1 placement (strip moved BEFORE the dot gate — the first
     implementation draft's regression): the trailing-slash arm RED
     via the `/var//` pin — `//` forms must stay the dot gate's
     catch. This pin exists because the regression was real: the
     draft sat here before the glob probe caught it.
  3. c Q1 refusal (if-block deleted): the agent-home arm RED — the
     fed `/home/untest-agent` reaches the ops.
  4. c S1 extractor (function body reverted to shape-keyed): the
     block-identity pin RED — the decoy arms splice in.
  5. c S2 family (`^sudo ` dropped from the regex): the family pin
     RED.
  6. c Q2 window (`tail -6` reintroduced): the family pin RED — the
     eighth family line falls out of the window.

## Gates (fix wave 4, d findings)

- Unit: `sh tests/unit/test-uninstall.sh` green — all arms incl. the
  extended agent-home arm (both spellings), the isolated family pin,
  the existence-filter pin, the wiring pin, the anchored ts negatives
  and the two new static slash forms; `make test` green.
- `make lint` green (ShellCheck delta vs 3de7f94: IDENTICAL for both
  changed files, code-for-code); `sh tests/unit/test-docs.sh` green;
  line-length ratchet green (this file ≤ 120 content columns);
  `make check-version` green.
- E2E (RM-0113 — uninstall.sh touched: comparator drop is
  equivalence-preserving, comments scoped; both suites run on the
  committed fix tree `09206ab`, in parallel, warm cache, opencode
  2.1.4): `make e2e` green — 309 passed per container (baseline
  level); `make e2e-rootless` green — 47 passed per container
  (baseline level).
- Sabotage spot-checks (post-commit against `09206ab`, in a scratch
  worktree at /tmp/opencode/pr-00243-d/sab-wt; each: mutate → observe
  the named pin RED → `git checkout --` → suite green at the end):
  1. d X2 comparator (reverted to raw-only, the finding's hazard
     shape): the agent-home arm RED — the trailing-slash echo for
     /home/untest-agent/ is absent.
  2. d S1 family pin (`skipped` dropped from the regex): the family
     pin RED — the isolating fixture line falls out (was green
     pre-fix, the d S1 gap demonstrated at suite level in review d).
  3. d S2 filter (helper `[ -d ]` deleted): the existence-filter pin
     RED — host-independent, on this fully-equipped host.
  4. d Q4 anchors (loop strip neutralized, raw leak): the ts arm RED
     — `sudo find /var/ !` fires; the anchored negative discriminates
     the exact regression the anchors were built for.
  5. d X4 strip (screen() normalization deleted): the static arm RED
     — `screening rejects /var/` (the new static form).
  6. d Q5 wiring (dot-arm line reordered to lead with `/./` AND the
     wiring reverted to the pre-b-S1 shape-keyed pipeline — the
     realistic two-step regression): exactly ONE failure, the wiring
     pin (`wired SCREEN_PATTERNS free of dot/double-slash tokens`);
     every other arm green — the pin catches the splice the function
     pin cannot see.

## Follow-ups

1. update.sh projects.conf loops (`--refresh` baseline, ddev-handover):
   add the form gate — and decide system-path-blocklist parity with the
   uninstaller (they have none at all). Own wave: fixture + arms + both
   e2e suites (a X2 sweep finding, recorded above).
   **GitHub: #247** (issue draft in ../opk-issues/, published 2026-10-24).
2. uninstall.sh single-op rm sites (S1 sweep list, 11 sites): convert
   to rc-observing closers. Own wave — each site needs its extraction +
   arms (a F1 ddev-handover precedent).
   **GitHub: #246** (issue draft in ../opk-issues/, published 2026-10-24).
3. projects.conf symlink roots: gate behavior investigation — `find`
   operand is safe (`! -type l`), `chmod g-s` dereferences the operand,
   `setfacl -R` operand semantics unmeasured (snapshot c verified the
   first two tails, review-c X axis; the measurement owes scratch work
   on a real filesystem). **GitHub: #245** (issue draft in
   ../opk-issues/, published 2026-10-24).
