#!/bin/sh
# e2e/run.sh — End-to-end test in Docker container
# Builds an Ubuntu image, installs opencode + our kit, verifies protection.
# Run from repo root: ./tests/e2e/run.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

IMAGE="opencode-e2e"
CONTAINER="opencode-e2e-test"

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
        echo "  ${RED}FAIL${NC}  $desc (expected failure, got success)"
        failures=$((failures + 1))
    else
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    fi
}

cleanup() {
    docker rm -f "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "${CYAN}=============================================${NC}"
echo "${CYAN}  opencode permissions kit — E2E Test${NC}"
echo "${CYAN}=============================================${NC}"
echo ""

echo "--- Building Docker image ---"
docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

echo ""
echo "--- Preparing test project ---"
TMP_PROJECT=$(mktemp -d)
mkdir -p "$TMP_PROJECT/test-project/subdir"
echo "DB_PASS=secret123"    > "$TMP_PROJECT/test-project/.env"
echo "API_KEY=hunter2"       > "$TMP_PROJECT/test-project/settings.php"
echo '{"token":"abc"}'       > "$TMP_PROJECT/test-project/auth.json"
echo "# README"               > "$TMP_PROJECT/test-project/README.md"
echo "normal source code"    > "$TMP_PROJECT/test-project/index.php"

echo ""
echo "--- Running E2E container ---"
docker run -d --name "$CONTAINER" \
    -v "$REPO_DIR:/home/dev/repo" \
    -v "$TMP_PROJECT/test-project:/var/www/vhosts/test-project" \
    --privileged \
    "$IMAGE" sleep infinity

E() { docker exec -u dev "$CONTAINER" sh -c "$@"; }

echo ""
echo "--- 1. Install opencode ---"
E 'curl -fsSL https://opencode.ai/install | bash' || {
    echo "  ${RED}FAIL${NC}  opencode installer failed (network issue?)"
    if E 'test -x /home/dev/.opencode/bin/opencode'; then
        echo "  ${GREEN}OK${NC}  opencode binary already present"
    else
        failures=1; passed=0
        echo ""
        echo "${RED}E2E aborted — cannot install opencode.${NC}"
        rm -rf "$TMP_PROJECT"
        exit 1
    fi
}

echo ""
echo "--- 2. Run setup (from local repo, plugin-only distribution) ---"
E 'sudo bash /home/dev/repo/files/setup.sh --yes --projects /var/www/vhosts'
echo "  Setup complete."

echo ""
echo "--- 3. Wrapper & binary ---"
check "Wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "Binary at /usr/local/lib/opencode/bin/opencode" \
    E 'test -x /usr/local/lib/opencode/bin/opencode'
check "Wrapper is first in PATH" \
    E 'test "$(which opencode)" = "/usr/local/bin/opencode"'
check "Uninstall script deployed" \
    E 'test -x /usr/local/lib/opencode/uninstall.sh'

echo ""
echo "--- 4. User & group ---"
check "User opencode exists" \
    E 'id opencode'
check "opencode is in www-data" \
    E 'id opencode | grep -q www-data'
check "www-data group exists" \
    E 'getent group www-data'

echo ""
echo "--- 5. File protection (ACL deny for opencode) ---"
check_fail ".env blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check_fail "settings.php blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/settings.php'
check_fail "auth.json blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/auth.json'
check_fail "README.md blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.md'
check "index.php readable" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/index.php'

echo ""
echo "--- 6. Config & agents ---"
check "Config deployed" \
    E 'sudo test -f /home/opencode/.config/opencode/opencode.jsonc'
check "Agents dir exists" \
    E 'sudo test -d /home/opencode/.agents/'

echo ""
echo "--- 7. Git hooks ---"
check "core.hooksPath set" \
    E 'git config --global core.hooksPath | grep -q /usr/local/lib/opencode/hooks'
check "Hooks directory exists" \
    E 'test -d /usr/local/lib/opencode/hooks'

echo ""
echo "--- 7b. Hook applies project-level config (--cwd) ---"
E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "read": { "deploy-key.pem": "deny", "**/deploy-key.pem": "deny" },
        "edit": { "deploy-key.pem": "deny", "**/deploy-key.pem": "deny" }
    }
}
EOF'
E 'sudo touch /var/www/vhosts/test-project/deploy-key.pem'
E 'cd /var/www/vhosts/test-project && sudo /usr/local/lib/opencode/hooks/post-commit' && \
    echo "  ${GREEN}OK${NC}  post-commit hook completed"
check_fail "post-commit applied project deny via --cwd" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/deploy-key.pem'
check "other project files still protected" \
    E '! sudo -u opencode test -r /var/www/vhosts/test-project/.env'

echo ""
echo "--- 8. Umask ---"
check "umask script deployed" \
    E 'test -f /etc/profile.d/opencode-umask.sh'

echo ""
echo "--- 9. protect-projects idempotent ---"
E 'sudo /usr/local/lib/opencode/protect-projects.sh --force' && \
    echo "  ${GREEN}OK${NC}  protect-projects.sh runs without error"

echo ""
echo "--- 10. Sensitive file created after setup ---"
E 'echo "new-secret" | sudo tee /var/www/vhosts/test-project/.env.local > /dev/null'
E 'sudo /usr/local/lib/opencode/protect-projects.sh --force'
check_fail ".env.local blocked after protect run" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env.local'

echo ""
echo "--- 11. Uninstall & cleanup verification ---"
E 'bash /usr/local/lib/opencode/uninstall.sh --yes' && \
    echo "  ${GREEN}OK${NC}  uninstall.sh completed"
check_fail "Wrapper removed"          E 'test -e /usr/local/bin/opencode'
check_fail "Library removed"          E 'test -e /usr/local/lib/opencode'
check_fail "Sudoers removed"          E 'test -e /etc/sudoers.d/opencode'
check_fail "/etc/opencode removed"    E 'test -e /etc/opencode'
check_fail "Umask removed"            E 'test -e /etc/profile.d/opencode-umask.sh'
check_fail "opencode user removed"    E 'id opencode'
check_fail "core.hooksPath unset"     E 'git config --global --get core.hooksPath'
check_fail "Project ACLs cleaned"     E 'getfacl -p /var/www/vhosts/test-project/.env 2>/dev/null | grep -q "user:opencode"'

echo ""
echo "=============================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
fi
echo ""

rm -rf "$TMP_PROJECT"

[ "$failures" -eq 0 ] || exit 1
