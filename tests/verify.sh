#!/bin/sh
# opencode permissions kit — Verification suite
# Run after install.sh to confirm the soft-only model is in place.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

failures=0
passed=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        failures=$((failures + 1))
    fi
}

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${RED}FAIL${NC}  $desc (expected absence)"
        failures=$((failures + 1))
    else
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    fi
}

echo ""
echo "opencode permissions kit — Verification (soft-only model)"
echo "======================================================"
echo ""

echo "--- User & Group ---"
check "User 'opencode' exists"            id opencode >/dev/null 2>&1
check "opencode primary usergroup is 'opencode'"  [ "$(id -gn opencode)" = "opencode" ]
check "Default user is in the opencode group"     id "$(whoami)" | grep -q opencode

echo ""
echo "--- Wrapper & binary ---"
check "Wrapper at /usr/local/bin/opencode"  test -x /usr/local/bin/opencode
check "System binary exists"                test -x /usr/local/lib/opencode-permissions-kit/bin/opencode
check "Wrapper is in PATH first"            test "$(which opencode)" = "/usr/local/bin/opencode"
check_fail "no legacy hooks directory"     test -d /usr/local/lib/opencode-permissions-kit/hooks
check_fail "no legacy protect-projects.sh"  test -e /usr/local/lib/opencode-permissions-kit/protect-projects.sh
check_fail "no legacy ddev shim in library" test -e /usr/local/lib/opencode-permissions-kit/bin/ddev
check_fail "core.hooksPath unset (legacy)" git config --global --get core.hooksPath 2>/dev/null

echo ""
echo "--- Sudoers ---"
check "sudoers file valid"  sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1
check_fail "no (opencode:docker) RunAs grant"  sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit 2>/dev/null

echo ""
echo "--- Backend & ddev runtime ---"
check "install.conf records a rootless backend" \
    grep -qE '^CONTAINER_BACKEND=(docker-rootless|podman-rootless)' /etc/opencode-permissions-kit/install.conf 2>/dev/null
check "ddev home ~opencode/.ddev exists"       sudo test -d /home/opencode/.ddev

echo ""
echo "--- Group baseline ---"
for dir in $(cat /etc/opencode-permissions-kit/projects.conf 2>/dev/null); do
    [ -d "$dir" ] || continue
    check "$dir in the opencode group" \
        [ "$(stat -c %G "$dir")" = "opencode" ]
    check "$dir default ACL g:opencode:rwx" \
        sudo getfacl -p -d "$dir" 2>/dev/null | grep -q "group:opencode:rwx"
    check "$dir setgid"  test -g "$dir"
done

echo ""
echo "--- Soft file access (readable, no hard deny) ---"
for dir in $(cat /etc/opencode-permissions-kit/projects.conf 2>/dev/null); do
    for f in "$dir"/*/.env "$dir"/*/settings.php "$dir"/*/auth.json; do
        if [ -f "$f" ]; then
            check "$f readable for opencode (soft-only)"  sudo -u opencode test -r "$f" 2>/dev/null
            check_fail "$f has no u:opencode ACL deny"     sudo getfacl -p "$f" 2>/dev/null | grep -q "user:opencode:---"
        fi
    done
done

echo ""
echo "--- Umask ---"
check "umask script deployed"  test -f /etc/profile.d/opencode-permissions-kit-umask.sh

echo ""
echo "======================================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
fi
echo ""