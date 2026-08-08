#!/bin/sh
# opencode Permission-Control Setup-Kit — Verification suite
# Run after setup.sh to confirm everything works.
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

echo ""
echo "openCode Permission-Control Setup-Kit — Verification"
echo "======================================================"
echo ""

echo "--- User & Group ---"
check "User 'opencode' exists"            id opencode >/dev/null 2>&1
check "Group 'www-data' exists"           getent group www-data >/dev/null 2>&1
check "opencode is in www-data"           id opencode | grep -q www-data
check "Default user is in www-data"       id "$(whoami)" | grep -q www-data

echo ""
echo "--- Wrapper ---"
check "Wrapper at /usr/local/bin/opencode"  test -x /usr/local/bin/opencode
check "System binary exists"                test -x /usr/local/lib/opencode/bin/opencode
check "Wrapper is in PATH first"            test "$(which opencode)" = "/usr/local/bin/opencode"

echo ""
echo "--- Git Hooks ---"
check "Hooks directory exists"              test -d /usr/local/lib/opencode/hooks
check "post-checkout hook"                  test -x /usr/local/lib/opencode/hooks/post-checkout
check "post-merge hook"                     test -x /usr/local/lib/opencode/hooks/post-merge
check "post-commit hook"                    test -x /usr/local/lib/opencode/hooks/post-commit
check "hooksPath configured"                git config --get core.hooksPath 2>/dev/null | grep -q '/usr/local/lib/opencode/hooks'

echo ""
echo "--- Sudoers ---"
check "sudoers file valid"  sudo /usr/sbin/visudo -c -f /etc/opencode/sudoers >/dev/null 2>&1

echo ""
echo "--- File Protection (read denial for opencode on sensitive files) ---"
for dir in $(cat /etc/opencode/projects.conf 2>/dev/null); do
    for f in "$dir"/*/.env "$dir"/*/settings.php "$dir"/*/auth.json; do
        if [ -f "$f" ]; then
            check "$f blocked for opencode"  ! sudo -u opencode test -r "$f" 2>/dev/null
        fi
    done
done

echo ""
echo "--- Umask ---"
check "umask script deployed"  test -f /etc/profile.d/opencode-umask.sh

echo ""
echo "======================================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
fi
echo ""
