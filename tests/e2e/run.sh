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
echo "--- 1b. status.sh before install (not-installed state) ---"
check "status.sh (not installed) reports hardening NOT active" \
    E 'cd /tmp && sh /home/dev/repo/files/status.sh 2>&1 | grep -q "NOT active"'

echo ""
echo "--- 2. Run install (from local repo checkout) ---"
# Pre-create a default-user config so install.sh must back it up and
# install the deny-all config (--yes auto-answers the backup prompt).
E 'mkdir -p /home/dev/.config/opencode && printf "%s\n" "{\"model\":\"dummy\"}" > /home/dev/.config/opencode/opencode.jsonc'
E 'sudo bash /home/dev/repo/files/install.sh --yes --projects /var/www/vhosts'
echo "  Install complete."

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
check "config.sh deployed" \
    E 'test -x /usr/local/lib/opencode/config.sh'
check "update.sh deployed" \
    E 'test -x /usr/local/lib/opencode/update.sh'
check "status.sh deployed" \
    E 'test -x /usr/local/lib/opencode/status.sh'
check "install.conf written" \
    E 'test -f /etc/opencode/install.conf'
check "status.sh reports hardened" \
    E '/usr/local/lib/opencode/status.sh 2>&1 | grep -q "hardened"'

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
check "default user can cd into opencode home" \
    E 'cd /home/opencode'
check "default user can read opencode.jsonc" \
    E 'test -r /home/opencode/.config/opencode/opencode.jsonc'
check "default user can write opencode.jsonc" \
    E 'test -w /home/opencode/.config/opencode/opencode.jsonc'

echo ""
echo "--- 6b. Default-user deny-all config (self-update bypass protection) ---"
check "default-user deny-all config deployed" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "pre-existing default-user config backed up" \
    E 'ls /home/dev/.config/opencode/ | grep -q "opencode.jsonc_BAK_"'
check "deny-all config owned by dev" \
    E 'test "$(stat -c %U /home/dev/.config/opencode/opencode.jsonc)" = "dev"'
check "deny-all config denies read" \
    E 'grep -q "\"read\": \"deny\"" /home/dev/.config/opencode/opencode.jsonc'
check "deny-all config denies bash" \
    E 'grep -q "\"bash\"" /home/dev/.config/opencode/opencode.jsonc'

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
echo "--- 10. Sensitive file created after install ---"
E 'echo "new-secret" | sudo tee /var/www/vhosts/test-project/.env.local > /dev/null'
E 'sudo /usr/local/lib/opencode/protect-projects.sh --force'
check_fail ".env.local blocked after protect run" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env.local'

echo ""
echo "--- 10b. protect-projects cache (second run without --force) ---"
E 'sudo /usr/local/lib/opencode/protect-projects.sh' && \
    echo "  ${GREEN}OK${NC}  protect-projects.sh (no --force) exits 0"

echo ""
echo "--- 10c. protect-projects chown step ---"
# .env is on the deny list; protect-projects.sh chowns opencode-owned files
# back to DEFAULT_USER:www-data
E 'sudo chown opencode:www-data /var/www/vhosts/test-project/.env' && \
    E 'sudo /usr/local/lib/opencode/protect-projects.sh --force'
check "chown: .env re-owned to dev:www-data" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.env)" = "dev"'

echo ""
echo "--- 10d. protect-projects remove_acls (project allow override) ---"
E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "read": { "README.md": "allow", "**/README.md": "allow" },
        "edit": { "README.md": "allow", "**/README.md": "allow" }
    }
}
EOF'
E 'sudo /usr/local/lib/opencode/protect-projects.sh --force --cwd /var/www/vhosts/test-project'
check "allow-override: README.md readable for opencode" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.md'

echo ""
echo "--- 11. update.sh re-deploys kit + preservation contract ---"
# Snapshot files that update.sh must NOT touch (use sudo to be independent of perms)
E 'sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1 > /tmp/sha-opencode-jsonc.before'
E 'sudo sha256sum /usr/local/lib/opencode/bin/opencode | cut -d" " -f1 > /tmp/sha-binary.before'
E 'cat /etc/opencode/projects.conf > /tmp/projects.conf.before'
# Create a copy of the repo files with a sentinel VERSION so we can observe the bump.
# We can't overwrite the bind-mounted VERSION reliably, so we copy update.sh + a
# sentinel VERSION into a temp dir and run it from there.
E 'rm -rf /tmp/update-test && mkdir -p /tmp/update-test/files && cp -r /home/dev/repo/files/* /tmp/update-test/files/ && echo "9.9.9-sentinel" > /tmp/update-test/VERSION'
E 'sudo bash /tmp/update-test/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh completed without prompts"
check "Wrapper still present after update" E 'test -x /usr/local/bin/opencode'
check "config.sh still present"            E 'test -x /usr/local/lib/opencode/config.sh'
check "update.sh still present"            E 'test -x /usr/local/lib/opencode/update.sh'
check "install.conf still present"         E 'test -f /etc/opencode/install.conf'
check "projects.conf untouched"           E 'test -f /etc/opencode/projects.conf'
check_fail ".env still blocked after update" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check "opencode.jsonc byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1)" = "$(cat /tmp/sha-opencode-jsonc.before)"'
check "default-user deny-all config survives update" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "binary byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /usr/local/lib/opencode/bin/opencode | cut -d" " -f1)" = "$(cat /tmp/sha-binary.before)"'
check "projects.conf content unchanged" \
    E 'test "$(cat /etc/opencode/projects.conf)" = "$(cat /tmp/projects.conf.before)"'
check "install.conf VERSION bumped to sentinel" \
    E 'grep -q "VERSION=9.9.9-sentinel" /etc/opencode/install.conf'
E 'rm -rf /tmp/update-test'

echo ""
echo "--- 11b. setup.conf -> install.conf legacy migration ---"
E 'sudo cp /etc/opencode/install.conf /etc/opencode/setup.conf' && \
    E 'sudo rm -f /etc/opencode/install.conf'
check "legacy setup.conf created" E 'test -f /etc/opencode/setup.conf'
check "install.conf removed for migration test" E '! test -f /etc/opencode/install.conf'
E 'sudo bash /home/dev/repo/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh migrated setup.conf -> install.conf"
check "setup.conf removed after update" E '! test -f /etc/opencode/setup.conf'
check "install.conf created by update" E 'test -f /etc/opencode/install.conf'
check "install.conf contains DEFAULT_USER" \
    E 'grep -q "DEFAULT_USER=" /etc/opencode/install.conf'

echo ""
echo "--- 12. config.sh adds a project non-interactively ---"
E 'sudo mkdir -p /var/www/vhosts/extra-project' && \
    E 'sudo touch /var/www/vhosts/extra-project/.env'
E 'sudo bash /usr/local/lib/opencode/config.sh --yes projects add /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh add completed"
check "extra-project in projects.conf" \
    E 'grep -q /var/www/vhosts/extra-project /etc/opencode/projects.conf'
check_fail "extra-project .env blocked after config add" \
    E 'sudo -u opencode test -r /var/www/vhosts/extra-project/.env'

echo ""
echo "--- 12b. config.sh projects remove ---"
E 'sudo bash /usr/local/lib/opencode/config.sh --yes projects remove /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh remove completed"
check "extra-project removed from projects.conf" \
    E '! grep -q /var/www/vhosts/extra-project /etc/opencode/projects.conf'

echo ""
echo "--- 12c. config.sh git-config toggle ---"
E 'sudo bash /usr/local/lib/opencode/config.sh --yes git-config on' && \
    echo "  ${GREEN}OK${NC}  git-config on completed"
check "git-config ON: .git/config deny rule active" \
    E 'sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config ON: status reports ON" \
    E 'sudo bash /usr/local/lib/opencode/config.sh git-config status 2>&1 | grep -q "ON"'
E 'sudo bash /usr/local/lib/opencode/config.sh --yes git-config off' && \
    echo "  ${GREEN}OK${NC}  git-config off completed"
check "git-config OFF: no active .git/config rule" \
    E '! sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config OFF: status reports OFF" \
    E 'sudo bash /usr/local/lib/opencode/config.sh git-config status 2>&1 | grep -q "OFF"'

echo ""
echo "--- 12d. config.sh interactive menu (displays) ---"
E 'sudo mkdir -p /var/www/vhosts/menu-project' && \
    E 'sudo touch /var/www/vhosts/menu-project/.env'
# The interactive menu uses read </dev/tty which blocks in a non-TTY
# environment. We capture whatever output appears within 3 seconds before
# timeout kills the process. At minimum the banner + current settings +
# projects list should print. The full menu options ([2], [3], [q]) may
# or may not appear depending on buffering and how far the script gets
# before the read blocks.
E 'timeout 3 sudo bash /usr/local/lib/opencode/config.sh < /dev/null > /tmp/menu-out.txt 2>&1 || true'
E 'sudo chown dev /tmp/menu-out.txt'
check "menu: banner shown" \
    E 'grep -q "opencode permissions kit" /tmp/menu-out.txt'
check "menu: shows current settings" \
    E 'grep -q "Current settings" /tmp/menu-out.txt'
check "menu: project list shown" \
    E 'grep -q "\[1\]" /tmp/menu-out.txt'

echo ""
echo "--- 12e. wrapper actual invocation ---"
# Valid CWD: wrapper should show SECURED banner
E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-valid.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper ran from valid CWD"
check "wrapper: SECURED banner from valid CWD" \
    E 'grep -q "SECURED BY opencode permissions kit" /tmp/wrapper-valid.txt'
# Invalid CWD: wrapper should refuse
E 'cd /tmp && /usr/local/bin/opencode 2>&1 | tee /tmp/wrapper-invalid.txt; test $? -ne 0' && \
    echo "  ${GREEN}OK${NC}  wrapper refused from invalid CWD"
check "wrapper: ERROR banner from invalid CWD" \
    E 'grep -q "ERROR: opencode cannot be started here" /tmp/wrapper-invalid.txt'

echo ""
echo "--- 12f. uninstall.sh --dry-run (no-op) ---"
E 'bash /usr/local/lib/opencode/uninstall.sh --yes --dry-run' && \
    echo "  ${GREEN}OK${NC}  uninstall --dry-run completed"
check "dry-run: wrapper still exists"   E 'test -e /usr/local/bin/opencode'
check "dry-run: library still exists"   E 'test -e /usr/local/lib/opencode'
check "dry-run: /etc/opencode intact"  E 'test -e /etc/opencode'
check "dry-run: user still exists"      E 'id opencode'

echo ""
echo "--- 13. Uninstall & cleanup verification ---"
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
