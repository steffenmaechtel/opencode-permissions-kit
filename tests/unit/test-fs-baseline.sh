#!/bin/sh
# Unit tests for the group-baseline helper with live progress (issue #14):
#   - fs_baseline_root applies chgrp + setgid + group rw + default ACLs
#     (same final state the install/update/config blocks produced)
#   - live per-pass counters ("N entries — done") go to stderr
#   - the chgrp pass never dereferences symlinks (targets outside the
#     tree keep their group — xargs chgrp would follow them)
#   - .git is included (issue #17 semantics carried over)
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

# --- 8. exec-time symlink recheck (0.0.39e S1) ------------------------------------------
# The race itself (swap between find's scan and xargs' exec) cannot be
# scripted deterministically — what CAN be asserted is the guard: the
# consumer re-tests [ -L ] immediately before running the command, so a
# path that is a symlink AT EXEC TIME is skipped even when find's
# expression matched it. Simulate by driving _fsb_pass with an
# expression (-true) that deliberately includes symlinks: the target
# OUTSIDE the root must keep its mode, the regular file inside must not.
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

# --- 7b. pass failures propagate (0.0.43a F10) ----------------------------------------
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
