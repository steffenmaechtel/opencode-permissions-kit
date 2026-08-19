#!/bin/sh
# Unit tests for the "ddev always runs as the opencode user" feature
# (DDEV-WORKING §7): bin/ddev-as-opencode (sudoers helper) +
# ddev-as-opencode.sh (sourced `ddev()` shell function).
# Runs against the repo files as the CURRENT user — no root, no real
# opencode user required. Verifies:
#   - the helper refuses any non-opencode caller (exit 1)
#   - the helper's ddev resolution / env / exec logic (static)
#   - the function file sources cleanly, defines `ddev()`, and the
#     already-opencode branch execs the REAL ddev (no recursion)
#   - no reference to the removed legacy bin/ddev shim anywhere
#   - wiring: sudoers rule, install.sh/update.sh fetch+deploy+hook,
#     config.sh / migrate-denies.sh .ddev handover, status.sh reporting,
#     Makefile target, CI workflow chmod lists + test step
# Run: sh tests/test-ddev-as-opencode.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../files"
HELPER="$FILES/opencode-permissions-kit-lib/bin/ddev-as-opencode"
FUNC="$FILES/opencode-permissions-kit-lib/ddev-as-opencode.sh"
TEMPLATE="$FILES/opencode.jsonc"
SUDOERS="$FILES/sudoers.template"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/update.sh"
CONFIG="$FILES/config.sh"
HANDOVER="$FILES/opencode-permissions-kit-lib/ddev-handover.sh"
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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ""
echo "ddev-as-opencode Tests (DDEV-WORKING §7)"
echo "========================================"
echo ""

# --- 1. helper refuses a non-opencode caller ----------------------------------
# Runs as the current user. Skipped when the current user IS the opencode
# user (then the guard must NOT fire) or when root + no opencode user (the
# guard cannot distinguish that case either).
if [ "$(id -u)" != "$(id -u opencode 2>/dev/null || echo 0)" ]; then
    set +e
    OUT=$(sh "$HELPER" --version 2>&1)
    RC=$?
    set -e
    assert_eq "helper refuses a non-opencode caller (exit 1)" "1" "$RC"
    check "helper prints 'must run as' hint" \
        sh -c "printf '%s' \"\$1\" | grep -q 'must run as'" _ "$OUT"
else
    echo "  ${GREEN}PASS${NC}  (guard test skipped: current user IS opencode/undeterminable)"
    passed=$((passed + 1))
fi

# --- 2. helper ddev-resolution / env / exec logic (static) ---------------------
check "helper resolves the real ddev via PATH" \
    sh -c "grep -q 'command -v ddev' \"\$1\"" _ "$HELPER"
check "helper falls back to /usr/local/bin/ddev" \
    sh -c "grep -qF '/usr/local/bin/ddev' \"\$1\"" _ "$HELPER"
check "helper falls back to /usr/bin/ddev" \
    sh -c "grep -qF '/usr/bin/ddev' \"\$1\"" _ "$HELPER"
check "helper exits 127 with a hint when ddev is missing" \
    sh -c "grep -q 'exit 127' \"\$1\"" _ "$HELPER"
check "helper re-sets HOME for the opencode user" \
    sh -c "grep -q 'export HOME=\"/home/\$OPENCODE_USER\"' \"\$1\"" _ "$HELPER"
check "helper re-sets XDG_RUNTIME_DIR" \
    sh -c "grep -q 'XDG_RUNTIME_DIR' \"\$1\"" _ "$HELPER"
check "helper exports DOCKER_HOST for docker-rootless" \
    sh -c "grep -q 'OPENCODE_DOCKER_HOST' \"\$1\"" _ "$HELPER"
check "helper exports DOCKER_HOST for podman-rootless" \
    sh -c "grep -q 'OPENCODE_PODMAN_SOCKET' \"\$1\"" _ "$HELPER"
check "helper applies umask 002" \
    sh -c "grep -q 'umask 002' \"\$1\"" _ "$HELPER"
check "helper execs the resolved ddev binary" \
    sh -c "grep -q 'exec \"\$DDEV\" \"\$@\"' \"\$1\"" _ "$HELPER"
check_fail "helper never references the removed legacy bin/ddev shim" \
    sh -c "grep -qE 'opencode-permissions-kit/bin/ddev(\$|[^-])' \"\$1\"" _ "$HELPER"

# --- 3. function file: sourcing + both branches -------------------------------
# Fixture: a fake ddev on PATH so the already-opencode branch runs something
# observable instead of the (absent) real ddev.
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/ddev" <<'FAKE'
#!/bin/sh
echo "REAL_DDEV_RAN:$*"
FAKE
chmod +x "$TMPDIR/bin/ddev"

check "function file sources cleanly (defines a ddev shell function)" \
    sh -c ". \"\$1\" && type ddev 2>&1 | grep -q function" _ "$FUNC"
# Already the opencode user? The function must exec the REAL ddev (fake id +
# a fake ddev on PATH proves no recursion and no sudo).
RESULT=$(
    PATH="$TMPDIR/bin:$PATH"
    id() { echo 4242; }
    . "$FUNC"
    ddev start web
)
assert_eq "already-opencode branch runs the real ddev (no sudo, no recursion)" \
    "REAL_DDEV_RAN:start web" "$RESULT"
check "function execs the kit's sudoers helper for the developer" \
    sh -c "grep -q 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$FUNC"
check "function uses 'command ddev' in the opencode branch" \
    sh -c "grep -q 'command ddev' \"\$1\"" _ "$FUNC"
check_fail "function never references the removed legacy bin/ddev shim" \
    sh -c "grep -qE 'opencode-permissions-kit/bin/ddev(\$|[^-])' \"\$1\"" _ "$FUNC"

# --- 4. sudoers rule -----------------------------------------------------------
check "sudoers.template grants the ddev-as-opencode helper" \
    sh -c "grep -q 'NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$SUDOERS"

# --- 4b. credential-import gate (ddev auth ssh) ---------------------------------
check "template denies 'ddev auth ssh*' (incl. sudo)" \
    sh -c "grep -q '\"ddev auth ssh\\*\": \"deny\"' \"\$1\" && grep -q '\"sudo ddev auth ssh\\*\": \"deny\"' \"\$1\"" _ "$TEMPLATE"
check "template explains the /home/opencode/.ddev key trade-off" \
    sh -c "grep -q 'home/opencode/.ddev' \"\$1\" && grep -q 'EVERY opencode session' \"\$1\"" _ "$TEMPLATE"
check "template states the import destination is user-independent" \
    sh -c "grep -q 'SAME no matter who runs' \"\$1\"" _ "$TEMPLATE"
check "template warns that project 'ddev *' allows override the gate" \
    sh -c "grep -q 'merge LAST and override' \"\$1\"" _ "$TEMPLATE"
check "template still parses cleanly with the new rules" \
    python3 "$FILES/opencode-permissions-kit-lib/jsonc-parser.py" "$TEMPLATE"

# --- 5. install.sh wiring ------------------------------------------------------
check "install.sh fetches both new files (fetch_kit list)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$INSTALL"
check "install.sh deploys the function file" \
    sh -c "grep -q '\"\$LIBDIR/ddev-as-opencode.sh\"' \"\$1\"" _ "$INSTALL"
check "install.sh deploys the helper (mode 755)" \
    sh -c "grep -q '\"\$LIBDIR/bin/ddev-as-opencode\"' \"\$1\"" _ "$INSTALL"
check "install.sh hooks the function into the developer rc files" \
    sh -c "grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$INSTALL"
check "install.sh hooks use the [ -f ] uninstall-safe guard" \
    sh -c "grep -qF '[ -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh ] && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$INSTALL"
check "install.sh hands over ddev paths in the filesystem step" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$INSTALL"

# --- 6. update.sh wiring -------------------------------------------------------
check "update.sh KIT_FILES includes both new files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$UPDATE"
check "update.sh KIT_FILES includes the handover helper" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-handover.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys the function file" \
    sh -c "grep -q '\"\$LIBDIR/ddev-as-opencode.sh\"' \"\$1\"" _ "$UPDATE"
check "update.sh deploys the helper (mode 755)" \
    sh -c "grep -q '\"\$LIBDIR/bin/ddev-as-opencode\"' \"\$1\"" _ "$UPDATE"
check "update.sh heals the rc-file hook idempotently" \
    sh -c "grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$UPDATE"
check "update.sh runs the ddev handover unconditionally" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$UPDATE"

# --- 7. handover helper + call sites ---------------------------------------------
check "handover helper searches .ddev at any depth" \
    sh -c "grep -qF 'find \"\$dhr_root\" -type d -name .ddev' \"\$1\"" _ "$HANDOVER"
check "handover helper chowns recursively with g+w" \
    sh -c "grep -q 'chmod -R g+w' \"\$1\"" _ "$HANDOVER"
check "handover helper maps typo3 settings dirs (config/system, typo3conf)" \
    sh -c "grep -qF 'dhp_dirs=\"config/system \$dhp_docroot/typo3conf typo3conf\"' \"\$1\"" _ "$HANDOVER"
check "handover helper maps drupal settings dirs (sites/default)" \
    sh -c "grep -qF '\$dhp_docroot/sites/default' \"\$1\"" _ "$HANDOVER"
check "handover helper skips unknown app types" \
    sh -c "grep -qF 'return 0' \"\$1\"" _ "$HANDOVER"
check "config.sh projects add uses the handover helper" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$CONFIG"
check "update.sh refresh uses the handover helper" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$UPDATE"

# --- 7b. project-root handover (TYPO3 bootstrap, EPERM on fresh clones) ---------
# ddev's settings-path fallback targets the APP ROOT while TYPO3 is not
# yet installed and chmods it to 0755 — owner-only, so the root must
# belong to the ddev user during bootstrap and go back to the developer
# once detection kicks in. Functional test as the CURRENT user (chown to
# self is permitted, so the ownership branches are exercised as no-ops;
# the MODE changes are real).
HWORK=$(mktemp -d)
mkdir -p "$HWORK/proj/.ddev"
printf 'type: typo3\n' > "$HWORK/proj/.ddev/config.yaml"
chmod 2775 "$HWORK/proj"

check "typo3 detection: no vendor, no typo3 dir => undetected" \
    sh -c ". \"\$1\" && if ddev_typo3_detected \"\$2\" .; then exit 1; fi" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "typo3 detection: vendor Typo3Version.php => detected (composer mode)" \
    sh -c ". \"\$1\" && ddev_typo3_detected \"\$2\" ." _ "$HANDOVER" "$HWORK/proj"
rm -rf "$HWORK/proj/vendor"
check "typo3 detection: docroot typo3 dir => detected (legacy)" \
    sh -c "mkdir -p \"\$2/public/typo3\" && . \"\$1\" && ddev_typo3_detected \"\$2\" public" _ "$HANDOVER" "$HWORK/proj"
rm -rf "$HWORK/proj/public"

check "undetected typo3: root becomes 2755 (Perm==0755, ddev chmod is a no-op)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "detected typo3: root handed back with 2775 (g+w restored)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2775" _ "$HANDOVER" "$HWORK/proj"

check "non-typo3 type: root untouched by the project-root handover" \
    sh -c "printf 'type: php\n' > \"\$2/.ddev/config.yaml\" && chmod 2770 \"\$2\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2770" _ "$HANDOVER" "$HWORK/proj"

check "handover_root signature carries the dev user (handback target)" \
    sh -c "grep -qF 'dhr_dev=\"\${4:-}\"' \"\$1\"" _ "$HANDOVER"
check "install.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$root\" \"\$OPENCODE_USER\" \"\$OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$INSTALL"
check "update.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$root\" \"\$OPENCODE_USER\" \"\$NEW_OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$UPDATE"
check "config.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$p\" \"\$OPENCODE_USER\" \"\$OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$CONFIG"
rm -rf "$HWORK"

# --- 8. status.sh reporting ----------------------------------------------------
check "status.sh reports ddev-as-opencode state" \
    sh -c "grep -q 'ddev-as-opencode' \"\$1\"" _ "$STATUS"

# --- 9. Makefile + CI wiring ---------------------------------------------------
check "Makefile has a test-ddev-as-opencode target in the test: list" \
    sh -c "grep -q 'test-ddev-as-opencode' \"\$1\"" _ "$MAKEFILE"
check "test.yml chmod list + run step mention the new test" \
    sh -c "grep -q 'test-ddev-as-opencode.sh' \"\$1\"" _ "$TEST_CI"
check "test.yml chmod list includes the new lib files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$TEST_CI"
check "e2e.yml chmod list includes the new lib files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$E2E_CI"

# --- Summary -------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
