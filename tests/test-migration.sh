#!/bin/sh
# Unit tests for migrate-denies.sh (DDEV-WORKING §4 migration).
# Runs against a fixture tree as the CURRENT user — no root, no real
# opencode user required (the deny user and group are parameterized).
# Verifies:
#   - docker-group installs are REFUSED (exit 3) with instructions
#   - hard deny entries (u:<user>:---) are removed from all roots
#   - non-denied files keep their normal entries
#   - the sharing group is re-based (chgrp + setgid + default ACLs)
#   - legacy artifacts (hooks/, protect-projects.sh, ddev-transaction.sh,
#     bin/ddev shim, ddev-rewrites.conf, run dir) are removed
#   - the whole run is idempotent
# Run: sh tests/test-migration.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATE="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/migrate-denies.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc (expected [$expected] got [$actual])"
    fi
}

grep_absent() { ! grep "$@"; }

DENY_USER="$(id -un)"
DENY_GROUP="$(id -gn)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- fixture -----------------------------------------------------------------
mkdir -p "$TMPDIR/roots/project-a/config"
mkdir -p "$TMPDIR/roots/project-b"
touch "$TMPDIR/roots/project-a/.env"
touch "$TMPDIR/roots/project-a/settings.php"
touch "$TMPDIR/roots/project-a/index.php"
touch "$TMPDIR/roots/project-a/config/settings.php"
touch "$TMPDIR/roots/project-b/.env"

# Plant hard denies for DENY_USER on the sensitive files (ddev-breaking ones).
for f in "$TMPDIR/roots/project-a/.env" \
         "$TMPDIR/roots/project-a/settings.php" \
         "$TMPDIR/roots/project-a/config/settings.php" \
         "$TMPDIR/roots/project-b/.env"; do
    setfacl -m "u:$DENY_USER:---" "$f"
done
check "fixture: denies planted" \
    sh -c "getfacl -p '$TMPDIR/roots/project-a/.env' | grep -q 'user:$DENY_USER:---'"
# NOTE: no "deny is effective" assert here — Linux ignores named-user ACL
# entries for the file OWNER, and in this fixture DENY_USER owns everything.
# In the real kit the deny user (opencode) is never the owner.

printf '%s\n%s\n' "$TMPDIR/roots/project-a" "$TMPDIR/roots/project-b" > "$TMPDIR/projects.conf"

# Legacy conf + lib layout.
mkdir -p "$TMPDIR/conf" "$TMPDIR/lib/hooks" "$TMPDIR/lib/bin"
printf '%s\n' \
    'DEFAULT_USER=someone' \
    'OPENCODE_USER=opencode' \
    'WWW_GROUP=www-data' \
    'CONTAINER_BACKEND=podman-rootless' \
    'VERSION=0.0.10' > "$TMPDIR/conf/install.conf"
touch "$TMPDIR/conf/ddev-rewrites.conf"
touch "$TMPDIR/lib/protect-projects.sh"
touch "$TMPDIR/lib/ddev-transaction.sh"
touch "$TMPDIR/lib/bin/ddev"
touch "$TMPDIR/lib/hooks/post-commit"
mkdir -p "$TMPDIR/run/ddev-txn"

echo ""
echo "Migration Tests (DDEV-WORKING §4)"
echo "================================="
echo ""

# --- 1. docker-group refusal ---------------------------------------------------
mkdir -p "$TMPDIR/conf-dg"
printf '%s\n' 'CONTAINER_BACKEND=docker-group' > "$TMPDIR/conf-dg/install.conf"
set +e
OUT=$(sh "$MIGRATE" --projects "$TMPDIR/projects.conf" --conf-dir "$TMPDIR/conf-dg" --lib-dir "$TMPDIR/lib" 2>&1)
RC=$?
set -e
assert_eq "docker-group: exits 3" "3" "$RC"
check "docker-group: prints re-install instructions" \
    sh -c "printf '%s' \"\$1\" | grep -q 'install.sh --container-backend'" _ "$OUT"
check "docker-group: denies NOT touched on refusal" \
    sh -c "getfacl -p '$TMPDIR/roots/project-a/.env' | grep -q 'user:$DENY_USER:---'"

# --- 2. successful migration ---------------------------------------------------
set +e
OUT=$(sh "$MIGRATE" \
    --projects "$TMPDIR/projects.conf" \
    --conf-dir "$TMPDIR/conf" \
    --lib-dir "$TMPDIR/lib" \
    --run-dir "$TMPDIR/run" \
    --opencode-user "$DENY_USER" \
    --group "$DENY_GROUP" 2>&1)
RC=$?
set -e
assert_eq "migration: exits 0" "0" "$RC"
check "migration: reports removed deny count" \
    sh -c "printf '%s' \"\$1\" | grep -q 'removed hard deny entries'" _ "$OUT"

# Denies gone everywhere.
for f in "$TMPDIR/roots/project-a/.env" \
         "$TMPDIR/roots/project-a/settings.php" \
         "$TMPDIR/roots/project-a/config/settings.php" \
         "$TMPDIR/roots/project-b/.env"; do
    check "deny removed: ${f#$TMPDIR/}" \
        sh -c "! getfacl -p '$f' 2>/dev/null | grep -q 'user:$DENY_USER:'"
done
check "deny removal restores readability (ddev goal)" \
    test -r "$TMPDIR/roots/project-b/.env"

# Group baseline.
check "group re-based: default ACL on project-a" \
    sh -c "getfacl -p -d '$TMPDIR/roots/project-a' | grep -q 'group:$DENY_GROUP:rwx'"
check "group re-based: default ACL on nested dir" \
    sh -c "getfacl -p -d '$TMPDIR/roots/project-a/config' | grep -q 'group:$DENY_GROUP:rwx'"
check "setgid on roots" \
    sh -c "test -g '$TMPDIR/roots/project-a' && test -g '$TMPDIR/roots/project-b'"

# Artifacts removed.
check "artifact: lib/hooks removed"          sh -c "! test -e '$TMPDIR/lib/hooks'"
check "artifact: protect-projects.sh removed" sh -c "! test -e '$TMPDIR/lib/protect-projects.sh'"
check "artifact: ddev-transaction.sh removed" sh -c "! test -e '$TMPDIR/lib/ddev-transaction.sh'"
check "artifact: bin/ddev shim removed"      sh -c "! test -e '$TMPDIR/lib/bin/ddev'"
check "artifact: ddev-rewrites.conf removed" sh -c "! test -e '$TMPDIR/conf/ddev-rewrites.conf'"
check "artifact: run dir removed"            sh -c "! test -e '$TMPDIR/run'"

# --- 3. idempotency -------------------------------------------------------------
set +e
OUT=$(sh "$MIGRATE" \
    --projects "$TMPDIR/projects.conf" \
    --conf-dir "$TMPDIR/conf" \
    --lib-dir "$TMPDIR/lib" \
    --run-dir "$TMPDIR/run" \
    --opencode-user "$DENY_USER" \
    --group "$DENY_GROUP" 2>&1)
RC=$?
set -e
assert_eq "second run: exits 0" "0" "$RC"
check "second run: zero denies removed" \
    sh -c "printf '%s' \"\$1\" | grep -q 'removed hard deny entries (u:$DENY_USER) on 0 file(s)'" _ "$OUT"
check "second run: files still readable" \
    test -r "$TMPDIR/roots/project-a/.env"

# --- 4. usage errors -------------------------------------------------------------
set +e
sh "$MIGRATE" >/dev/null 2>&1
RC=$?
set -e
assert_eq "missing --projects: exits 1" "1" "$RC"

# --- Summary ---------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
