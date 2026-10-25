#!/bin/sh
# Unit tests for the group-baseline helper with live progress (issue #14):
#   - fs_baseline_root applies chgrp + setgid + group rw + default ACLs
#     (same final state the install/update/config blocks produced)
#   - live per-pass counters ("N entries — done") go to stderr
#   - the chgrp pass never dereferences symlinks (targets outside the
#     tree keep their group — xargs chgrp would follow them)
#   - .git is included (issue #17 semantics carried over)
#   - the python3 health gate (#223): a missing or broken interpreter
#     degrades the passes to a warned-but-applied fallback (one warn
#     line — not silent, #244 a Q2) instead of the old false green,
#     probes once per run, and a dead consumer ends the tee silently
#     (pr-00221 W2/W6 rider)
# Runs against the repo lib as the CURRENT user (FS_SUDO="") — no root.
# Run: sh tests/unit/test-fs-baseline.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/fs-baseline.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

assert_eq() {
    _d="$1" _e="$2" _a="$3"
    if [ "$_e" = "$_a" ]; then pass "$_d"; else fail "$_d (expected [$_e] got [$_a])"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo ""
echo "fs-baseline (group baseline progress, issue #14)"
echo "================================================="
echo ""

# Fixture: a tree with subdir, .git, files (tight modes), a symlink
# pointing OUT of the tree, and a foreign group on the root.
GRP="$(id -gn)"
mkdir -p "$WORK/proj/sub" "$WORK/proj/.git"
printf 'a\n' > "$WORK/proj/file.txt"
printf 'g\n' > "$WORK/proj/.git/config"
ln -s /etc/hostname "$WORK/proj/link-out"
chmod 700 "$WORK/proj" "$WORK/proj/sub" "$WORK/proj/.git"
chmod 600 "$WORK/proj/file.txt" "$WORK/proj/.git/config"

OUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$WORK/proj" "$GRP" 2>&1)"

# --- 1. final state -------------------------------------------------------------
assert_eq "root dir: group + setgid + group rwx (700 -> 2770)" "2770" \
    "$(stat -c %a "$WORK/proj")"
assert_eq "subdir carries setgid" "2770" "$(stat -c %a "$WORK/proj/sub")"
assert_eq ".git included in the baseline (issue #17)" "2770" "$(stat -c %a "$WORK/proj/.git")"
assert_eq "file gets group rw (600 -> 660)" "660" "$(stat -c %a "$WORK/proj/file.txt")"
assert_eq ".git/config gets group rw" "660" "$(stat -c %a "$WORK/proj/.git/config")"
assert_eq "group applied everywhere" "$GRP" "$(stat -c %G "$WORK/proj/sub")"
if getfacl -p "$WORK/proj/sub" 2>/dev/null | grep -q '^default:group:.*:rwx'; then
    pass "default ACL g:<group>:rwx set on directories"
else
    fail "default ACL g:<group>:rwx set on directories"
fi

# --- 2. symlink safety ----------------------------------------------------------
# A bare `chgrp <link>` follows the TARGET; chgrp -R (the old code) did
# not. The pass must skip symlinks entirely — the link's TARGET (here a
# root-owned system file) keeps its group. NB: plain stat(1) lstats a
# symlink, -L dereferences.
if [ "$(stat -L -c %G "$WORK/proj/link-out" 2>/dev/null)" != "$GRP" ]; then
    pass "symlink target untouched (outside the tree, group kept)"
else
    fail "symlink target untouched (target group became $GRP)"
fi

# --- 3. progress output (issue #14) ----------------------------------------------
echo "$OUT" | grep -q "large trees can take several minutes" \
    && pass "heads-up line for large trees present" \
    || fail "heads-up line for large trees present"
echo "$OUT" | grep -q "chgrp *[0-9]* entries — done" \
    && pass "chgrp pass reports a done-counter" \
    || fail "chgrp pass reports a done-counter"
echo "$OUT" | grep -q "dirs g+rwxs *[0-9]* entries — done" \
    && pass "dirs pass reports a done-counter" \
    || fail "dirs pass reports a done-counter"
echo "$OUT" | grep -q "files g+rw *[0-9]* entries — done" \
    && pass "files pass reports a done-counter" \
    || fail "files pass reports a done-counter"
echo "$OUT" | grep -q "default ACLs *[0-9]* entries — done" \
    && pass "ACL pass reports a done-counter" \
    || fail "ACL pass reports a done-counter"

# --- 4. idempotence ---------------------------------------------------------------
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$WORK/proj" "$GRP" >/dev/null 2>&1
assert_eq "re-run is idempotent (modes stable)" \
    "2770 2770 660" \
    "$(stat -c %a "$WORK/proj") $(stat -c %a "$WORK/proj/sub") $(stat -c %a "$WORK/proj/file.txt")"

# --- 5. empty/missing root is a silent no-op ----------------------------------------
OUT3="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2-nope" "$3"' _ "$LIB" "$WORK/proj" "$GRP" 2>&1)"
assert_eq "missing root: no output, no error" "" "$OUT3"

# --- 6. wiring: all three callers use the helper -------------------------------------
for f in "$INSTALL" "$UPDATE" "$CONFIG"; do
    if grep -q 'fs_baseline_root' "$f"; then
        pass "$(basename "$f") runs the baseline through fs_baseline_root"
    else
        fail "$(basename "$f") runs the baseline through fs_baseline_root"
    fi
done
grep -q 'opencode-permissions-kit-lib/sh/fs-baseline.sh' "$INSTALL" \
    && pass "install.sh fetch list includes fs-baseline.sh" \
    || fail "install.sh fetch list includes fs-baseline.sh"
grep -q 'opencode-permissions-kit-lib/sh/fs-baseline.sh' "$UPDATE" \
    && pass "update.sh KIT_FILES includes fs-baseline.sh" \
    || fail "update.sh KIT_FILES includes fs-baseline.sh"
grep -q 'large trees: this can take a while' "$UPDATE" \
    && pass "update.sh hints before the ddev handover scan (issue #14)" \
    || fail "update.sh hints before the ddev handover scan (issue #14)"
grep -q 'large trees: this can take minutes' "$INSTALL" \
    && pass "install.sh hints before the getfacl backup (issue #14)" \
    || fail "install.sh hints before the getfacl backup (issue #14)"

# --- 7. ancestor traversal (fs_ensure_traversable) ------------------------------------
# Fresh chain outside $WORK (which already carries the traverse entry
# from the runs above): $TR (700, group GRP) -> pub (755) -> proj.
# Ancestors of $TR/pub/proj: pub has other-x (untouched), $TR is 700
# with the sharing group (grant), /tmp and / are world-x (untouched).
TR=$(mktemp -d)
mkdir -p "$TR/pub/proj" "$TR/gx/proj"
chmod 700 "$TR"
chmod 755 "$TR/pub"
chmod 750 "$TR/gx"
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$TR/pub/proj" "$GRP" >/dev/null 2>&1
if getfacl -p "$TR" 2>/dev/null | grep -q "^group:$GRP:--x"; then
    pass "blocking ancestor gets a traverse-only ACL (x, no read/list)"
else
    fail "blocking ancestor gets a traverse-only ACL (got: $(getfacl -p "$TR" 2>/dev/null | grep "^group:$GRP" | tr '\n' ' '))"
fi
if getfacl -p "$TR" 2>/dev/null | grep -q "^group:$GRP:r"; then
    fail "traverse grant must not add read (dir stays non-listable)"
else
    pass "traverse grant must not add read (dir stays non-listable)"
fi
if getfacl -p "$TR/pub" 2>/dev/null | grep -q "^group:$GRP:"; then
    fail "other-x ancestor stays untouched (no ACL entry)"
else
    pass "other-x ancestor stays untouched (no ACL entry)"
fi
# 750 dir owned by the sharing group already grants group-x: no entry.
if getfacl -p "$TR/gx" 2>/dev/null | grep -q "^group:$GRP:"; then
    fail "group-x ancestor (dir group == sharing group) stays untouched"
else
    pass "group-x ancestor (dir group == sharing group) stays untouched"
fi
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$TR/gx/proj" "$GRP" >/dev/null 2>&1
_n=$(getfacl -p "$TR" 2>/dev/null | grep -c "^group:$GRP:--x")
assert_eq "traverse grant is idempotent (single ACL entry)" "1" "$_n"
rm -rf "$TR"

# --- 7b. mid-batch failure fails the baseline (0.0.44a V9) ---------------------------
# One failing setfacl entry MID-batch must fail the pass: the inner xargs
# loop used to return only the LAST command's status — a broken entry
# followed by healthy ones stayed green, the caller printed "applied"
# over an incomplete baseline (REVIEW-B W5's falsified premise). A stub
# fails exactly one operand; the rest delegate to the real setfacl.
V9ROOT=$(mktemp -d)
mkdir -p "$V9ROOT/d1" "$V9ROOT/d2" "$V9ROOT/d3"
chmod 700 "$V9ROOT" "$V9ROOT/d1" "$V9ROOT/d2" "$V9ROOT/d3"
STUBBIN=$(mktemp -d)
REAL_SETFACL="$(command -v setfacl)"
cat > "$STUBBIN/setfacl" <<EOF
#!/bin/sh
case "\$*" in *"/d2"*) exit 1 ;; esac
exec "$REAL_SETFACL" "\$@"
EOF
chmod +x "$STUBBIN/setfacl"
_mb_rc=0
FS_SUDO="" PATH="$STUBBIN:$PATH" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$V9ROOT" "$GRP" >/dev/null 2>&1 \
    || _mb_rc=$?
assert_eq "mid-batch ACL failure fails the baseline (V9)" "1" "$_mb_rc"
rm -rf "$V9ROOT" "$STUBBIN"

# --- 7c. the batch loop fails on a MIDDLE entry regardless of find order (0.0.44b W11) ----
# The V9 stub test is find-order-dependent (readdir decides which operand
# is batch-final). The loop body itself is extracted and executed with a
# FIXED operand list: a failing middle entry must fail the batch, a
# symlink-last batch must not.
_batch_body=$(sed -n '/^                _n=\$1; shift$/,/^                \[ "\$_fail" -eq 0 \]$/p' "$LIB")
if [ -n "$_batch_body" ]; then
    pass "fs-baseline: batch loop body extractable (W11)"
    _bstub=$(mktemp -d)
    cat > "$_bstub/failmid" <<'EOS'
#!/bin/sh
case "$1" in *midfail*) exit 1 ;; esac
exit 0
EOS
    chmod +x "$_bstub/failmid"
    _brc=0
    # Root arg is deliberately a path that cannot exist (#211 b W27):
    # the W11 drives assert batch rc semantics, not root-relative walks
    # — an absent root keeps the drives about the operands alone.
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 midfail ok2 || _brc=$?
    assert_eq "mid-batch failure fails the batch, order-independent (W11)" "1" "$_brc"
    _brc=0
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 ok2 || _brc=$?
    assert_eq "all-healthy batch stays green (W11)" "0" "$_brc"
    ln -sf /etc/hostname "$_bstub/lnk"
    _brc=0
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 "$_bstub/lnk" || _brc=$?
    assert_eq "symlink-last batch stays green (skip is not a failure)" "0" "$_brc"
    rm -rf "$_bstub"
else
    fail "fs-baseline: batch loop body extractable (W11)"
fi

# --- 8. Makefile + CI wiring -----------------------------------------------------------
grep -q 'test-fs-baseline' "$MAKEFILE" \
    && pass "Makefile test target includes test-fs-baseline" \
    || fail "Makefile test target includes test-fs-baseline"
grep -q 'tests/unit/test-fs-baseline.sh' "$TEST_CI" \
    && pass "test-unit.yml run step includes the new test" \
    || fail "test-unit.yml run step includes the new test"
# fs-baseline.sh is a sourced lib (install.sh, config.sh, update.sh) —
# per the repo invariant (755 <=> executed by path) it must be 100644.
[ "$(git -C "$SCRIPT_DIR/../.." ls-files -s -- files/opencode-permissions-kit-lib/sh/fs-baseline.sh | cut -d' ' -f1)" = "100644" ] \
    && pass "fs-baseline.sh is a sourced lib (git 100644, not executed by path)" \
    || fail "fs-baseline.sh is a sourced lib (git 100644, not executed by path)"

# --- 8b. exec-time symlink recheck (0.0.39e S1) -----------------------------------------
# The leaf race (swap between find's scan and xargs' exec) cannot be
# scripted deterministically via stream interleaving — what CAN be
# asserted is the guard: the consumer re-tests [ -L ] immediately before
# running the command, so a path that is a symlink AT EXEC TIME is
# skipped even when find's expression matched it. (The PARENT-swap form
# IS scripted deterministically — section 9's wrapper find performs the
# swap between scan output and replay.) Simulate by driving _fsb_pass
# with an expression (-true) that deliberately includes symlinks: the
# target OUTSIDE the root must keep its mode, the regular file inside
# must not.
SW=$(mktemp -d)
mkdir -p "$SW/root"
printf 'inside\n' > "$SW/root/in-file"
chmod 600 "$SW/root/in-file"
printf 'target\n' > "$SW/target"       # outside the pass root below
chmod 600 "$SW/target"
ln -s "$SW/target" "$SW/root/link"     # symlink INSIDE the pass root
FS_SUDO="" sh -c '. "$1" && _fsb_pass "test" "$2" -true -- chmod g+rw' _ "$LIB" "$SW/root" >/dev/null 2>&1
if [ "$(stat -c %a "$SW/target")" = "600" ]; then
    pass "exec-time recheck: symlink operands are skipped — target outside the root untouched"
else
    fail "exec-time recheck: symlink operands are skipped — target outside the root untouched (mode now $(stat -c %a "$SW/target"))"
fi
if [ "$(stat -c %a "$SW/root/in-file")" = "660" ]; then
    pass "exec-time recheck: regular files inside the pass root still processed (chain works)"
else
    fail "exec-time recheck: regular files still processed (mode $(stat -c %a "$SW/root/in-file"))"
fi
rm -rf "$SW"

# --- 8c. pass failures propagate (0.0.43a F10) ----------------------------------------
# A wholesale pass failure used to be invisible (pipeline status dropped,
# unconditional return 0) while callers printed "applied" regardless. Now:
# a failing per-path command warns per pass, the summary names the root,
# and fs_baseline_root exits non-zero (install/config/update fail loud
# under set -e instead of lying green).
FB="$WORK/failroot"
mkdir -p "$FB/root"
printf 'x\n' > "$FB/root/f"
STUBS="$WORK/failstubs"
mkdir -p "$STUBS"
cat > "$STUBS/setfacl" <<'EOF'
#!/bin/sh
echo "setfacl stub: deliberate failure" >&2
exit 1
EOF
chmod +x "$STUBS/setfacl"
FBOUT="$(PATH="$STUBS:$PATH" FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$FB/root" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$FBOUT" | grep -q BASELINE-RC0; then
    fail "a failing pass must propagate a non-zero exit"
else
    pass "a failing pass must propagate a non-zero exit"
fi
if printf '%s\n' "$FBOUT" | grep -qF 'baseline pass "default ACLs" hit errors'; then
    pass "the failing pass is named in the warn line"
else
    fail "the failing pass is named in the warn line"
fi
if printf '%s\n' "$FBOUT" | grep -qF 'may be incomplete'; then
    pass "the summary names the root and the risk"
else
    fail "the summary names the root and the risk"
fi
rm -rf "$FB" "$STUBS"

# A missing required tool dies loudly BEFORE any pass runs (the old code
# lost find's failure inside the redirected pipeline and xargs -r happily
# no-op'd on empty input). PATH is narrowed INSIDE the subshell so the
# /bin/sh invocation itself stays resolvable.
EMPTY="$WORK/emptypath"
mkdir -p "$EMPTY"
MTOUT="$(FS_SUDO="" /bin/sh -c '. "$1" && PATH="$2" && fs_baseline_root "$3" "$4"' \
    sh "$LIB" "$EMPTY" "$WORK/proj" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$MTOUT" | grep -qF 'required tool missing for the group baseline: find'; then
    pass "a missing tool is reported before any pass runs"
else
    fail "a missing tool is reported before any pass runs"
fi
rm -rf "$EMPTY"

# A find that DIES wholesale mid-walk with an empty stream (0.0.43b W4):
# xargs -r no-ops green on empty input, so the old pipeline rc said
# nothing — the baseline printed "applied" over a walk that never ran.
# The temp-file restructure tracks find's own rc.
DEAD="$WORK/deadfind"
mkdir -p "$DEAD"
cat > "$DEAD/find" <<'EOF'
#!/bin/sh
echo "find stub: simulated wholesale failure" >&2
exit 1
EOF
chmod +x "$DEAD/find"
DFOUT="$(FS_SUDO="" /bin/sh -c '. "$1" && PATH="$2:$PATH" && fs_baseline_root "$3" "$4" && echo BASELINE-RC0' \
    sh "$LIB" "$DEAD" "$WORK/proj" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$DFOUT" | grep -q BASELINE-RC0; then
    fail "a wholesale find failure must propagate a non-zero exit (W4)"
else
    pass "a wholesale find failure must propagate a non-zero exit (W4)"
fi
if printf '%s\n' "$DFOUT" | grep -qF 'baseline pass "chgrp" hit errors (rc 1)'; then
    pass "the dead find is attributed to its pass with its rc (W4)"
else
    fail "the dead find is attributed to its pass with its rc (W4)"
fi
if printf '%s\n' "$DFOUT" | grep -qF 'simulated wholesale failure'; then
    pass "find's stderr survives for diagnosis (the why behind the rc)"
else
    fail "find's stderr survives for diagnosis (the why behind the rc)"
fi
rm -rf "$DEAD"

# --- 9. parent-swap race: component walk (#211 a F1, 0.0.39h F2 class) ------------------
# The scan->act window spans the whole temp-file replay, and the agent
# can swap a PARENT directory for a symlink inside it: find recorded
# proj/x/y/secret as a regular file, then x/y becomes a link to a dir
# OUTSIDE the tree — the operand now resolves there, and the leaf-only
# [ -L ] recheck passes (the leaf is a regular file). Deterministic
# seam: a PATH-stubbed find runs the REAL find (paths land in the temp
# file), performs the swap, then exits — the replay then chews stale
# paths. Without the component walk, chmod g+w hits the victim (mode
# 600 -> 620); with it, the operand is skipped and the pass stays green
# (a skip is not a failure).
F1DIR=$(mktemp -d)
F1STUB=$(mktemp -d)
F1REAL="$(command -v find)"
mkdir -p "$F1DIR/proj/x/y" "$F1DIR/victim"
printf 'secret\n' > "$F1DIR/proj/x/y/secret"
printf 'victim\n' > "$F1DIR/victim/secret"
chmod 600 "$F1DIR/proj/x/y/secret" "$F1DIR/victim/secret"
cat > "$F1STUB/find" <<EOF
#!/bin/sh
"$F1REAL" "\$@"
_rc=\$?
if [ -d "$F1DIR/proj/x/y" ] && [ ! -L "$F1DIR/proj/x/y" ]; then
    mv "$F1DIR/proj/x/y" "$F1DIR/proj/x/moved-away"
    ln -s "$F1DIR/victim" "$F1DIR/proj/x/y"
fi
exit \$_rc
EOF
chmod +x "$F1STUB/find"
F1RC=0
# Slashed root on purpose (#211 b W7): this one drive covers both the
# a F1 walk (victim keeps its mode only when the walk runs) and the
# b W7 normalization (an unnormalized root voids the walk pattern —
# victim would go 620).
FS_SUDO="" PATH="$F1STUB:$PATH" \
    sh -c '. "$1" && _fsb_pass "parent-swap" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1DIR/proj/" >/dev/null 2>&1 || F1RC=$?
if [ -f "$F1DIR/proj/x/moved-away/secret" ] && [ -L "$F1DIR/proj/x/y" ]; then
    pass "race fixture: parent swapped between scan and replay (seam fired)"
else
    fail "race fixture: parent swapped between scan and replay (seam fired)"
fi
assert_eq "parent-swap: victim outside the tree keeps its mode (#211 a F1)" "600" \
    "$(stat -c %a "$F1DIR/victim/secret")"
assert_eq "parent-swap: skipped operand does not fail the pass (rc 0)" "0" "$F1RC"
rm -rf "$F1DIR" "$F1STUB"

# Root '/' is refused loud, never walked (#211 b W7): the refusal fires
# before any find runs — nothing on the host is touched.
F1RRC=0
F1RMSG=$(FS_SUDO="" sh -c '. "$1" && _fsb_pass "refuse" "/" -type f -- chmod g+w' _ "$LIB" 2>&1) || F1RRC=$?
assert_eq "root / refused: rc 1 (#211 b W7)" "1" "$F1RRC"
case "$F1RMSG" in
    *never*) pass "root / refused: loud message (#211 b W7)" ;;
    *) fail "root / refused: loud message (got: $F1RMSG)" ;;
esac
# The message must name the refused ROOT (#211 c W2): the shift at the
# prologue renumbers positionals, so a ${_fsbp_root:-$2} fallback named
# a find-expression word instead ('/' drive) — and the '//' drive shows
# the ORIGINAL form, proving the capture happened before the shift.
case "$F1RMSG" in
    *"refusing scan root '/'"*) pass "root / refused: names the refused root (#211 c W2)" ;;
    *) fail "root / refused: names the refused root (got: $F1RMSG) (#211 c W2)" ;;
esac
F1R2RC=0
F1R2MSG=$(FS_SUDO="" sh -c '. "$1" && _fsb_pass "refuse" "//" -type f -- chmod g+w' _ "$LIB" 2>&1) || F1R2RC=$?
assert_eq "root // refused: rc 1 (#211 c W2)" "1" "$F1R2RC"
case "$F1R2MSG" in
    *"refusing scan root '//'"*) pass "root // refused: original form named (#211 c W2)" ;;
    *) fail "root // refused: original form named (got: $F1R2MSG) (#211 c W2)" ;;
esac

# Walker string safety: components and names with spaces flow through
# the prefix-peeling without word splitting — the chmod still applies.
# rc captured (#211 b W13): the drive used to run unguarded under the
# suite's set -e, aborting the whole suite pre-tally on a walker
# regression instead of recording a FAIL.
F1SP=$(mktemp -d)
mkdir -p "$F1SP/proj/a/dir two"
printf 's\n' > "$F1SP/proj/a/dir two/has space.txt"
chmod 600 "$F1SP/proj/a/dir two/has space.txt"
F1SPRC=0
FS_SUDO="" sh -c '. "$1" && _fsb_pass "spaces" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1SP/proj" >/dev/null 2>&1 || F1SPRC=$?
assert_eq "walker: spaces drive exits 0 (#211 b W13)" "0" "$F1SPRC"
assert_eq "walker: spaces in components and names survive the walk" "620" \
    "$(stat -c %a "$F1SP/proj/a/dir two/has space.txt")"
rm -rf "$F1SP"

# Spaced-path PARENT-SWAP RACE (external mini-review follow-up, post-b):
# the happy-path drive above proves chmod still APPLIES on spaced paths
# (620) — it cannot notice a walk regression that silently stops SKIPPING
# (the operand still chmods, the pin stays green; the b W6 class, missed
# on this pin), and the a F1 race fixture drives unspaced paths only.
# Same deterministic seam as section 9, with spaces in every component:
# find records the operand, the stub swaps the parent for a symlink to a
# victim dir OUTSIDE the tree — the walk must skip (victim stays 600);
# a word-splitting or voided walk chmods through the link (victim 620).
F1SPD=$(mktemp -d)
F1SPS=$(mktemp -d)
mkdir -p "$F1SPD/proj/a/dir two" "$F1SPD/victim dir"
printf 'secret\n' > "$F1SPD/proj/a/dir two/has space.txt"
printf 'victim\n' > "$F1SPD/victim dir/has space.txt"
chmod 600 "$F1SPD/proj/a/dir two/has space.txt" "$F1SPD/victim dir/has space.txt"
cat > "$F1SPS/find" <<EOF
#!/bin/sh
"$(command -v find)" "\$@"
_rc=\$?
if [ -d "$F1SPD/proj/a/dir two" ] && [ ! -L "$F1SPD/proj/a/dir two" ]; then
    mv "$F1SPD/proj/a/dir two" "$F1SPD/proj/a/moved away"
    ln -s "$F1SPD/victim dir" "$F1SPD/proj/a/dir two"
fi
exit \$_rc
EOF
chmod +x "$F1SPS/find"
F1SPDRC=0
FS_SUDO="" PATH="$F1SPS:$PATH" \
    sh -c '. "$1" && _fsb_pass "spaces-race" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1SPD/proj" >/dev/null 2>&1 || F1SPDRC=$?
if [ -f "$F1SPD/proj/a/moved away/has space.txt" ] && [ -L "$F1SPD/proj/a/dir two" ]; then
    pass "spaces race: seam fired (parent swapped between scan and replay)"
else
    fail "spaces race: seam fired (parent swapped between scan and replay)"
fi
assert_eq "spaces race: victim outside the tree keeps its mode (walk skips)" "600" \
    "$(stat -c %a "$F1SPD/victim dir/has space.txt")"
assert_eq "spaces race: skip is not a failure (rc 0)" "0" "$F1SPDRC"
rm -rf "$F1SPD" "$F1SPS"

# --- 10. pass scratch registered with the caller's cleanup trap (#211 a F12) ------
# _fsb_pass's NUL temp was a plain mktemp + rm: an aborted pass (Ctrl-C
# during the minutes-long walk) left the root-owned file in /tmp. The
# staged-write shape registers it with the caller's _tmp_track trap.
# Pin: source the real lib with a RECORDING _tmp_track, run one pass,
# assert the opk-fsb-pass temp was registered.
F12S=$(mktemp -d)
mkdir -p "$F12S/root"
printf 'x\n' > "$F12S/root/f"
F12_TRACK="$F12S/tracked" FS_SUDO="" \
    sh -c '. "$1" && _tmp_track() { printf "%s\n" "$1" >> "$F12_TRACK"; } \
    && _fsb_pass "f12" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F12S/root" >/dev/null 2>&1 || true
if grep -q 'opk-fsb-pass' "$F12S/tracked" 2>/dev/null; then
    pass "pass scratch registered with _tmp_track (#211 a F12)"
else
    fail "pass scratch registered with _tmp_track (#211 a F12)"
fi
rm -rf "$F12S"

# --- 11. python3 health gate (#223, #221 a W3 shape) ----------------------------------
# _fsb_count_tee sits in the DATA pipeline of a MUTATING pass: an
# ungated missing-or-broken python3 killed the tee at startup, xargs -r
# no-oped GREEN on the empty stream, and the baseline was silently not
# applied (false-green at a root-run site — recorded as the W3 sibling
# in the pr-00221 resolution). The gate probes health once per run and
# degrades the tee to a plain passthrough. Marker FILE, not stderr: the
# production probe discards its own stderr (L1 — observe the way
# production does; the marker lesson of #221 pin 7).
W23="$WORK/issue223"
W23BIN="$WORK/issue223-bin"
W23PROBE="$WORK/issue223-probe.log"
mkdir -p "$W23BIN" "$W23/proj/sub"
chmod 700 "$W23/proj" "$W23/proj/sub"
printf 'gate\n' > "$W23/proj/f"
chmod 600 "$W23/proj/f"
printf '#!/bin/sh\necho probe >> "%s"\nexit 9\n' "$W23PROBE" > "$W23BIN/python3"
chmod +x "$W23BIN/python3"
rm -f "$W23PROBE"
W23RC=0
W23OUT="$(PATH="$W23BIN:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23/proj" "$(id -gn)" 2>&1)" \
    || W23RC=$?
assert_eq "#223 broken python3: baseline still applies (rc 0, no false green)" "0" "$W23RC"
assert_eq "#223 broken python3: file got group rw (600 -> 660 — the gate fed xargs)" "660" \
    "$(stat -c %a "$W23/proj/f")"
# Probe count: 2 = the cached probe + the diagnostic rerun (#244 c
# S3, the installer gate's b-S2 shape) — the rerun is a deliberate
# second interpreter EXECUTION on the failure path. The cache is still
# pinned: without it this would read 8 (2 × four passes).
assert_eq "#223 broken python3: probe+rerun ran exactly once per run (cache across the four passes)" "2" \
    "$(wc -l < "$W23PROBE" 2>/dev/null || echo 0)"
assert_eq "#223 broken python3: degradation warn exactly once per run" "1" \
    "$(printf '%s\n' "$W23OUT" | grep -c 'live progress unavailable')"
if printf '%s\n' "$W23OUT" | grep -q 'Traceback'; then
    fail "#223 broken python3: no traceback on the fallback path"
else
    pass "#223 broken python3: no traceback on the fallback path"
fi
# ...and the healthy path through the SAME fixture still counts (the
# gate must not eat the tee when python3 is fine — rc + done-line):
W23RC2=0
W23OUT2="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23/proj" "$(id -gn)" 2>&1)" \
    || W23RC2=$?
assert_eq "#223 healthy python3: baseline applies (control for the gate)" "0" "$W23RC2"
if printf '%s\n' "$W23OUT2" | grep -q 'chgrp *[0-9]* entries — done'; then
    pass "#223 healthy python3: live counter still runs (gate passes the tee through)"
else
    fail "#223 healthy python3: live counter still runs (gate ate the tee)"
fi
rm -rf "$W23" "$W23BIN"
rm -f "$W23PROBE"

# --- 11b. python3 absent entirely (restricted PATH, no shim) ---------------------------
# "missing" and "broken" are different probe outcomes: a PATH without
# any python3 must take the same bare fallback. Controlled PATH per the
# sandbox rules (conventions "Test sandbox"): symlinks to the few
# externals the baseline needs, python3 deliberately absent.
W23NP="$WORK/issue223-nopy"
W23NPBIN="$WORK/issue223-nopy-bin"
mkdir -p "$W23NPBIN" "$W23NP/proj"
chmod 700 "$W23NP/proj"
printf 'nopy\n' > "$W23NP/proj/f"
chmod 600 "$W23NP/proj/f"
for _t in sh find cat chgrp chmod setfacl mktemp dirname stat getfacl grep rm xargs; do
    ln -s "$(command -v "$_t")" "$W23NPBIN/$_t"
done
W23NPRC=0
W23NPOUT="$(FS_SUDO="" PATH="$W23NPBIN" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23NP/proj" "$(id -gn)" 2>&1)" \
    || W23NPRC=$?
assert_eq "#223 python3 absent: baseline still applies (rc 0)" "0" "$W23NPRC"
assert_eq "#223 python3 absent: file got group rw (600 -> 660)" "660" \
    "$(stat -c %a "$W23NP/proj/f")"
assert_eq "#223 python3 absent: degradation warn exactly once" "1" \
    "$(printf '%s\n' "$W23NPOUT" | grep -c 'live progress unavailable')"

# Missing cat is now loud TOO (the fallback pipes the pass through it —
# a missing cat would rebuild the exact empty-stream false-green the
# gate closes): same restricted bin minus cat, probed BEFORE walking.
W23NPBIN2="$WORK/issue223-nopy-bin2"
mkdir -p "$W23NPBIN2"
# reset the fixture the 11b run already baselined: the loud abort must
# leave the file at 600, proving no pass ran at all
chmod 600 "$W23NP/proj/f"
for _t in sh find chgrp chmod setfacl mktemp dirname stat getfacl grep rm xargs; do
    ln -s "$(command -v "$_t")" "$W23NPBIN2/$_t"
done
W23CATRC=0
W23CATOUT="$(FS_SUDO="" PATH="$W23NPBIN2" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23NP/proj" "$(id -gn)" 2>&1)" \
    || W23CATRC=$?
assert_eq "#223 missing cat: fails loud before any pass runs" "1" "$W23CATRC"
if printf '%s\n' "$W23CATOUT" | grep -qF 'required tool missing for the group baseline: cat'; then
    pass "#223 missing cat: the error names cat"
else
    fail "#223 missing cat: the error names cat (got: $W23CATOUT)"
fi
assert_eq "#223 missing cat: nothing applied (file keeps 600)" "600" \
    "$(stat -c %a "$W23NP/proj/f")"
rm -rf "$W23NP" "$W23NPBIN" "$W23NPBIN2"

# --- 11c. dead consumer ends the tee silently (#223 rider, pr-00221 W2/W6) -------------
# The tee had no except clause: a downstream xargs dying first ended it
# in a BrokenPipeError traceback. 1 MiB input (beyond the pipe buffer)
# against a reader that exits at once fires EPIPE deterministically —
# the reader is gone before python finishes starting. stderr is
# captured at the ENCLOSING sh -c: a redirect on the pipeline's last
# member would capture only the reader's stderr and prove nothing.
# Sabotage (drop the except clause) drops a Traceback into the asserted
# file; the devnull dup2 in the clause keeps the interpreter's own
# shutdown flush quiet too ("Exception ignored").
W23BP="$WORK/issue223-bp"
python3 -c 'import sys; sys.stdout.buffer.write(b"e\0" * 524288)' > "$W23BP"
FS_SUDO="" sh -c '. "$1" && _fsb_count_tee bp < "$2" | sh -c "exit 0"' \
    _ "$LIB" "$W23BP" >/dev/null 2>"$W23BP.err"
# rc assert dropped (#244 a Q5): under this suite's dash (no pipefail)
# the reader rc is 0 regardless of tee behavior — dead weight that
# could never fail. The stderr greps below are the discriminators.
if grep -q 'Traceback\|Exception ignored' "$W23BP.err"; then
    fail "#223 broken pipe: tee dies silently when xargs goes first"
else
    pass "#223 broken pipe: tee dies silently when xargs goes first"
fi
# No completion line for an aborted pass (#244 a S2/W3/Q4): counted is
# bytes READ, not entries applied — the consumer died mid-stream.
if grep -q '— done' "$W23BP.err"; then
    fail "#244 broken pipe: no completion line for an aborted pass"
else
    pass "#244 broken pipe: no completion line for an aborted pass"
fi
# Production-shape rider (#244 a Q1): install/update/config run bash
# WITH pipefail — the tee must exit 0 on EPIPE or a green pass fails
# through the old traceback rc. Environment-dependent (L4b): skipped
# with a note where bash is absent.
if command -v bash >/dev/null 2>&1; then
    W23PFRC=0
    FS_SUDO="" bash -c 'set -o pipefail; . "$1" && _fsb_count_tee pf < "$2" | sh -c "exit 0"' \
        _ "$LIB" "$W23BP" >/dev/null 2>&1 || W23PFRC=$?
    assert_eq "#244 pipefail rider: tee exits 0 on EPIPE under bash pipefail" "0" "$W23PFRC"
else
    echo "  note: bash absent — pipefail rider skipped (#244 a Q1)"
fi
rm -rf "$W23BP"

# --- 11d. env poison cannot reach the gate (#244 a S1) --------------------------------
# PYTHONHOME poison: without -I a bogus PYTHONHOME breaks interpreter
# startup (rc 1) and the probe would degrade the passes to a
# counter-less fallback; with -I the interpreter ignores the env
# entirely — the baseline runs WITH its live counters. (An os.py
# PYTHONPATH shadow cannot be the vehicle here: os is already in
# sys.modules at -c startup, the shadow never loads — a vacuous-pin
# trap caught by sabotage during the fix wave.)
W23EP="$WORK/issue223-envpoison"
mkdir -p "$W23EP/proj"
chmod 700 "$W23EP/proj"
printf 'env\n' > "$W23EP/proj/f"
chmod 600 "$W23EP/proj/f"
W23EPRC=0
W23EPOUT="$(FS_SUDO="" PYTHONHOME=/nonexistent-opk \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23EP/proj" "$(id -gn)" 2>&1)" \
    || W23EPRC=$?
assert_eq "#244 env poison: baseline applies despite hostile PYTHONHOME (rc 0)" "0" "$W23EPRC"
assert_eq "#244 env poison: file got group rw (600 -> 660)" "660" \
    "$(stat -c %a "$W23EP/proj/f")"
if printf '%s\n' "$W23EPOUT" | grep -q 'entries — done'; then
    pass "#244 env poison: live counters still run (the -I isolation works)"
else
    fail "#244 env poison: live counters still run (got: $W23EPOUT)"
fi
if printf '%s\n' "$W23EPOUT" | grep -q 'live progress unavailable'; then
    fail "#244 env poison: no degradation warn (isolation, not fallback)"
else
    pass "#244 env poison: no degradation warn (isolation, not fallback)"
fi
rm -rf "$W23EP"

# --- 11e. Ctrl-C ends the tee silently (#244 a W4 — the KI arm of 11c's clause) --------
# 11c pins BrokenPipeError; the except tuple's OTHER arm —
# KeyboardInterrupt — needs its own executed failure path (L1). The
# tee reads a FIFO a writer holds open: counted > 0, then blocked in
# read. setsid gives the tee its own process group so kill -INT reaches
# the python itself (a bare kill of the sh parent would orphan it and
# the tee would finish normally on EOF — a false pass). Asserts are on
# stderr content only: the sh wrapper's rc after SIGINT is
# shell-dependent. Arm proof before the signal (#244 b W3): the
# writer's drain marker appears once the tee has drained the stream —
# all but at most one pipe buffer (~64 KiB) may still be buffered
# when the blocking write returns (#244 c W5: not the "whole"
# stream), which is enough: the SIGINT always hits an interpreter
# that already initialized. A fixed sleep instead could race the
# startup chain and pass vacuously. Guarded on setsid presence with a
# skip note (#244 b W2, the §11c bash-rider pattern).
W23KI="$WORK/issue223-ki"
if command -v setsid >/dev/null 2>&1; then
    mkdir -p "$W23KI"
    W23KIF="$W23KI/in.fifo"
    mkfifo "$W23KIF"
    # fd 3 on the SUBSHELL (exec 3>): the write end must stay open through
    # the sleep — a redirect on the python command alone closes it when
    # python exits, the tee sees EOF, finishes normally and prints its
    # completion line before the signal ever arrives (fixture bug caught
    # by this very pin on first run). The ready marker after the write
    # is the arm proof (#244 b W3): a fifo write blocks until the
    # reader drains it, so the marker appears once the tee has
    # consumed all but at most one pipe buffer of the stream and sits
    # blocked in read (#244 c W5 wording fix).
    ( exec 3>"$W23KIF"
      python3 -c 'import sys; sys.stdout.buffer.write(b"e\0" * 524288)' >&3 2>/dev/null
      : > "$W23KI/ready"
      sleep 10 ) &
    W23KIWR=$!
    # The async-list SIGINT rule (POSIX): a background command of a
    # non-interactive shell starts with SIGINT IGNORED — CPython then never
    # installs its KeyboardInterrupt handler and kill -INT would be a
    # silent no-op: the pin could not fire AT ALL (caught live — the
    # completion line still appeared and the no-traceback assert passed
    # vacuously). The wrapper RESTORES the disposition — a caught signal
    # resets to default across exec — then execs the real sh+tee.
    setsid python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.default_int_handler)
os.execv(sys.argv[1], [sys.argv[1], "-c",
    ". \"$1\" && _fsb_count_tee ki < \"$2\"", "ki", sys.argv[2], sys.argv[3]])' \
        /bin/sh "$LIB" "$W23KIF" >/dev/null 2>"$W23KI/err" &
    W23KITEE=$!
    # Readiness poll (#244 b W3): signal only an ARMED tee — the marker
    # proves the stream drained (interpreter initialized, read loop
    # live). No marker within 10 s goes red by itself instead of
    # passing green with nothing executed. Integer sleep only (#244 c
    # Q3): POSIX sleep need not accept a fractional operand, and a
    # failing one aborts the whole suite under set -e — the very
    # block the setsid guard made portable. 10 × 1 s keeps the bound.
    W23KIWAIT=0
    while [ ! -e "$W23KI/ready" ] && [ "$W23KIWAIT" -lt 10 ]; do
        sleep 1
        W23KIWAIT=$((W23KIWAIT + 1))
    done
    if [ -e "$W23KI/ready" ]; then
        pass "#244 ctrl-c: tee armed before the signal (stream drained)"
    else
        fail "#244 ctrl-c: tee never armed — inspect $W23KI/err"
    fi
    # No "--" before the negative pid: dash's kill builtin rejects it
    # (rc 2, usage) while bash accepts it — the suite runs under dash, and
    # the group kill silently never happened until this was caught live
    # (bash-vs-dash trap: the debug session ran bash and looked green).
    kill -INT "-$W23KITEE" 2>/dev/null \
        || /bin/kill -INT "-$W23KITEE" 2>/dev/null \
        || kill -INT "$W23KITEE" 2>/dev/null \
        || true
    wait "$W23KITEE" 2>/dev/null || true
    kill "$W23KIWR" 2>/dev/null || true
    wait "$W23KIWR" 2>/dev/null || true
    if grep -q 'Traceback' "$W23KI/err"; then
        fail "#244 ctrl-c: no traceback on the KeyboardInterrupt arm"
    else
        pass "#244 ctrl-c: no traceback on the KeyboardInterrupt arm"
    fi
    if grep -q '— done' "$W23KI/err"; then
        fail "#244 ctrl-c: no completion line for an aborted pass"
    else
        pass "#244 ctrl-c: no completion line for an aborted pass"
    fi
    rm -rf "$W23KI"
else
    echo "  note: setsid absent — ctrl-c pins skipped (#244 b W2)"
fi

# --- 11f. a broken python3 names its problem above the warn (#244 c S3) ---------------
# The probe's rerun (the installer gate's b-S2 shape): a
# present-but-broken interpreter surfaces its own diagnostic stderr
# above the degradation warn — an attributeless degrade hides the
# cause. An ABSENT python3 stays silent (command -v guard: no
# not-found noise for a legitimate absence). Fixture wording is
# CPython's real unhyphenated message.
W23NZ="$WORK/issue223-noisy"
# The diagnostic text lives in a variable: a consuming grep line
# quoting the literal ('platform…' "$VAR/x") chains into the sandbox
# scanner's raw-line rm-suffix pattern — the definition line does
# not (#244 c S1: the wave-2 mechanism is real for grep lines, not
# for the fixture printf shape both reviews probed).
W23DIAG='platform independent libraries'
mkdir -p "$W23NZ/bin"
printf '#!/bin/sh\necho "%s" >&2\nexit 9\n' "$W23DIAG" > "$W23NZ/bin/python3"
chmod +x "$W23NZ/bin/python3"
FS_SUDO="" PATH="$W23NZ/bin:$PATH" \
    sh -c '. "$1" && _fsb_py_probe' _ "$LIB" >"$W23NZ/out" 2>"$W23NZ/err"
if grep -qF "$W23DIAG" "$W23NZ/err" \
    && grep -qF 'live progress unavailable' "$W23NZ/err"; then
    pass "#244 c S3: fs-baseline probe surfaces a broken interpreter's diagnostic"
else
    fail "#244 c S3: probe diagnostic passthrough (err=$(cat "$W23NZ/err"))"
fi
rm -rf "$W23NZ"

# --- Summary ---------------------------------------------------------------------------
echo ""
echo "================================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
