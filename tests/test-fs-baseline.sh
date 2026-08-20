#!/bin/sh
# Unit tests for the group-baseline helper with live progress (issue #14):
#   - fs_baseline_root applies chgrp + setgid + group rw + default ACLs
#     (same final state the install/update/config blocks produced)
#   - live per-pass counters ("N entries — done") go to stderr
#   - the chgrp pass never dereferences symlinks (targets outside the
#     tree keep their group — xargs chgrp would follow them)
#   - .git is included (issue #17 semantics carried over)
# Runs against the repo lib as the CURRENT user (FS_SUDO="") — no root.
# Run: sh tests/test-fs-baseline.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/fs-baseline.sh"
INSTALL="$SCRIPT_DIR/../files/install.sh"
UPDATE="$SCRIPT_DIR/../files/update.sh"
CONFIG="$SCRIPT_DIR/../files/config.sh"
MAKEFILE="$SCRIPT_DIR/../Makefile"
TEST_CI="$SCRIPT_DIR/../.github/workflows/test.yml"
E2E_CI="$SCRIPT_DIR/../.github/workflows/e2e.yml"

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
grep -q 'opencode-permissions-kit-lib/fs-baseline.sh' "$INSTALL" \
    && pass "install.sh fetch list includes fs-baseline.sh" \
    || fail "install.sh fetch list includes fs-baseline.sh"
grep -q 'opencode-permissions-kit-lib/fs-baseline.sh' "$UPDATE" \
    && pass "update.sh KIT_FILES includes fs-baseline.sh" \
    || fail "update.sh KIT_FILES includes fs-baseline.sh"
grep -q 'large trees: this can take a while' "$UPDATE" \
    && pass "update.sh hints before the ddev handover scan (issue #14)" \
    || fail "update.sh hints before the ddev handover scan (issue #14)"
grep -q 'large trees: this can take minutes' "$INSTALL" \
    && pass "install.sh hints before the getfacl backup (issue #14)" \
    || fail "install.sh hints before the getfacl backup (issue #14)"

# --- 7. Makefile + CI wiring -----------------------------------------------------------
grep -q 'test-fs-baseline' "$MAKEFILE" \
    && pass "Makefile test target includes test-fs-baseline" \
    || fail "Makefile test target includes test-fs-baseline"
grep -q 'tests/test-fs-baseline.sh' "$TEST_CI" \
    && pass "test.yml chmod list includes the new test" \
    || fail "test.yml chmod list includes the new test"
grep -q 'opencode-permissions-kit-lib/fs-baseline.sh' "$TEST_CI" \
    && pass "test.yml chmod list includes the new lib" \
    || fail "test.yml chmod list includes the new lib"
[ "$(grep -c 'opencode-permissions-kit-lib/fs-baseline.sh' "$E2E_CI")" = "2" ] \
    && pass "e2e.yml chmod lists include the new lib (both jobs)" \
    || fail "e2e.yml chmod lists include the new lib (both jobs)"

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
