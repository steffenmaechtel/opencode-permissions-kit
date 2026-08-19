#!/bin/sh
# Unit tests for the Windows hosts bridge (ddev-hosts.sh + kit CLI +
# ddev() hook): ddev running as opencode cannot manage the Windows hosts
# file; the kit never grants the agent hosts access — instead the
# developer gets a ready-made command that uses ddev's own elevation path
# (`ddev hostname <name> 127.0.0.1` as the dev user -> ddev-hostname.exe
# -> Windows UAC dialog).
# Run: sh tests/test-ddev-hosts.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../files"
HOSTS="$FILES/opencode-permissions-kit-lib/ddev-hosts.sh"
FUNC="$FILES/opencode-permissions-kit-lib/ddev-as-opencode.sh"
KIT="$FILES/opencode-permissions-kit-lib/kit"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/update.sh"
STATUS="$FILES/status.sh"
MAKEFILE="$SCRIPT_DIR/../Makefile"
TEST_CI="$SCRIPT_DIR/../.github/workflows/test.yml"
E2E_CI="$SCRIPT_DIR/../.github/workflows/e2e.yml"

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

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        fail "$desc (expected absence, got a match)"
    else
        pass "$desc"
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo ""
echo "Windows hosts bridge Tests (ddev-hosts)"
echo "======================================="
echo ""

# --- 1. hostname list from config.yaml ---------------------------------------

mkdir -p "$WORK/proj1/.ddev" "$WORK/proj2/.ddev" "$WORK/proj3/.ddev"
printf 'name: base-typo3-modulset\nproject_tld: local\ntype: typo3\n' > "$WORK/proj1/.ddev/config.yaml"
printf 'type: php\nadditional_hostnames:\n  - shop\n  - api\nadditional_fqdns:\n  - full.example.com\n  - "*.wild.io"\n' > "$WORK/proj2/.ddev/config.yaml"
printf 'name: With_Upper_Case\ntype: php\n' > "$WORK/proj3/.ddev/config.yaml"

assert_eq "list: name + custom project_tld" \
    "base-typo3-modulset.local" \
    "$(sh -c '. "$1" && ddev_hosts_list "$2"' _ "$HOSTS" "$WORK/proj1")"
# NOTE: no `read`-splitting of the function output — dash buffers pipe
# reads and can swallow lines. The primary hostname is line 1, extras are
# sorted by the lib; compare against the sorted whole instead.
assert_eq "list: dir basename + default tld, additional_hostnames + fqdns, wildcards skipped" \
    "api.ddev.site
full.example.com
proj2.ddev.site
shop.ddev.site" \
    "$(sh -c '. "$1" && ddev_hosts_list "$2" | sort' _ "$HOSTS" "$WORK/proj2")"
assert_eq "list: name lowercased (ddev uses ToLower)" \
    "with_upper_case.ddev.site" \
    "$(sh -c '. "$1" && ddev_hosts_list "$2"' _ "$HOSTS" "$WORK/proj3")"

# --- 2. missing check against the Windows hosts file --------------------------

printf '127.0.0.1 localhost\n127.0.0.1 base-typo3-modulset.local other.local\n' > "$WORK/winhosts"

assert_eq "missing: present hostname not reported" "" \
    "$(DDEV_WIN_HOSTS="$WORK/winhosts" sh -c '. "$1" && ddev_hosts_missing "$2"' _ "$HOSTS" "$WORK/proj1")"
assert_eq "missing: absent hostnames reported" \
    "api.ddev.site
full.example.com
proj2.ddev.site
shop.ddev.site" \
    "$(DDEV_WIN_HOSTS="$WORK/winhosts" sh -c '. "$1" && ddev_hosts_missing "$2" | sort' _ "$HOSTS" "$WORK/proj2")"

# Word-boundary safety: a longer hostname containing the checked one must
# NOT count as present.
printf '127.0.0.1 localhost\n127.0.0.1 xbase-typo3-modulset.localy\n' > "$WORK/winhosts2"
assert_eq "missing: substring hosts do not satisfy the check" \
    "base-typo3-modulset.local" \
    "$(DDEV_WIN_HOSTS="$WORK/winhosts2" sh -c '. "$1" && ddev_hosts_missing "$2"' _ "$HOSTS" "$WORK/proj1")"

# Unreadable/absent hosts file: everything counts as missing (hint shows).
assert_eq "missing: absent hosts file => all hostnames reported" \
    "base-typo3-modulset.local" \
    "$(DDEV_WIN_HOSTS="$WORK/nonexistent" sh -c '. "$1" && ddev_hosts_missing "$2"' _ "$HOSTS" "$WORK/proj1")"

# --- 3. add: uses ddev's own elevation path as the developer -------------------

check "add runs ddev hostname <name> 127.0.0.1 (ddev native UAC flow)" \
    sh -c "grep -qF '\"\$dha_bin\" hostname \"\$dha_h\" 127.0.0.1' \"\$1\"" _ "$HOSTS"
check "add re-execs as the DEFAULT user when called via sudo" \
    sh -c "grep -qF 'sudo -u \"\$dha_dev\" env HOME=\"/home/\$dha_dev\"' \"\$1\"" _ "$HOSTS"
check "add is a no-op when nothing is missing" \
    sh -c "grep -q 'nothing to do' \"\$1\"" _ "$HOSTS"
check "add prints a manual PowerShell fallback on failure" \
    sh -c "grep -q 'Add-Content' \"\$1\"" _ "$HOSTS"
check_fail "add never writes the hosts file itself (no shell redirection)" \
    sh -c "grep -qE '(>>?|tee).*(winhosts|WIN_HOSTS|drivers/etc/hosts)' \"\$1\"" _ "$HOSTS"

# Functional: ddev-hosts-add against a fake ddev on PATH records the calls.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/ddev" <<'FAKE'
#!/bin/sh
echo "ddev:$*" >> "$DDEV_FAKE_LOG"
exit 0
FAKE
chmod +x "$WORK/bin/ddev"

ADD_OUT=$(DDEV_WIN_HOSTS="$WORK/winhosts" DDEV_FAKE_LOG="$WORK/ddev-calls.log" \
    DDEV_HOSTS_DEV_USER="$(id -un)" SUDO_USER="" \
    PATH="$WORK/bin:$PATH" \
    sh -c '. "$1" && ddev_hosts_add "$2" >/dev/null 2>&1 || true' _ "$HOSTS" "$WORK/proj2")
assert_eq "add calls ddev hostname once per missing hostname, 127.0.0.1" \
    "ddev:hostname api.ddev.site 127.0.0.1
ddev:hostname full.example.com 127.0.0.1
ddev:hostname proj2.ddev.site 127.0.0.1
ddev:hostname shop.ddev.site 127.0.0.1" \
    "$(grep '^ddev:hostname' "$WORK/ddev-calls.log" | sort)"

# --- 4. kit CLI wiring ----------------------------------------------------------

check "kit CLI has ddev-hosts-add" \
    sh -c "grep -q 'ddev-hosts-add' \"\$1\"" _ "$KIT"
check "kit CLI has ddev-hosts-check" \
    sh -c "grep -q 'ddev-hosts-check' \"\$1\"" _ "$KIT"
check "kit CLI re-execs as the developer when called under sudo" \
    sh -c "grep -q 'exec sudo -u \"\$_kitsu\"' \"\$1\"" _ "$KIT"
check "kit CLI refuses to run the bridge as root without a resolvable user" \
    sh -c "grep -q 'cannot resolve the developer user' \"\$1\"" _ "$KIT"

# --- 5. ddev() hook: hint after start/restart -----------------------------------

check "hook prints the missing-hostnames hint after start/restart" \
    sh -c "grep -qE 'start\\|restart\\) _opk_hosts_hint' \"\$1\"" _ "$FUNC"
check "hook hint shows the ready-made add command" \
    sh -c "grep -q 'ddev-hosts-add' \"\$1\"" _ "$FUNC"
check "hook stays silent without a project in the cwd" \
    sh -c "grep -qF '[ -f \"\$PWD/.ddev/config.yaml\" ]' \"\$1\"" _ "$FUNC"
check "hook preserves ddev's exit code" \
    sh -c "grep -q 'return \"\$_opk_rc\"' \"\$1\"" _ "$FUNC"

# --- 6. deploy wiring -------------------------------------------------------------

check "install.sh fetch list includes ddev-hosts.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-hosts.sh' \"\$1\"" _ "$INSTALL"
check "install.sh deploys ddev-hosts.sh" \
    sh -c "grep -q '\"\$LIBDIR/ddev-hosts.sh\"' \"\$1\"" _ "$INSTALL"
check "update.sh KIT_FILES includes ddev-hosts.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-hosts.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys ddev-hosts.sh" \
    sh -c "grep -q '\"\$LIBDIR/ddev-hosts.sh\"' \"\$1\"" _ "$UPDATE"
check "status.sh reports missing Windows hostnames" \
    sh -c "grep -q 'hosts (win)' \"\$1\"" _ "$STATUS"
check "Makefile lint list includes ddev-hosts.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-hosts.sh' \"\$1\"" _ "$MAKEFILE"
check "test.yml chmod list includes ddev-hosts.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-hosts.sh' \"\$1\"" _ "$TEST_CI"
check "e2e.yml chmod lists include ddev-hosts.sh" \
    sh -c "grep -c 'opencode-permissions-kit-lib/ddev-hosts.sh' \"\$1\" | grep -q \"^2\$\"" _ "$E2E_CI"

# --- Summary -----------------------------------------------------------------------

echo ""
echo "======================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
