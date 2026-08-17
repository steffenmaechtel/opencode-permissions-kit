#!/bin/sh
# Unit tests for the container-backend wiring (DDEV-WORKING soft-only model).
#
# The kit records CONTAINER_BACKEND in install.conf (docker-rootless |
# podman-rootless — rootless only). Checks:
#   (1) sudoers.template — base (opencode) RunAs + socket-check rule +
#       DOCKER_HOST/XDG_RUNTIME_DIR env_keep; NO docker-group block, NO ddev
#       delegation, NO root-side helpers.
#   (2) render logic (mirrors install.sh/update.sh) — DEFAULT_USER
#       substitution only, visudo-clean shape.
#   (3) wrapper resolution mirror — rootless backends only, no fallback.
#   (4) static wiring — install.sh, update.sh, config.sh, status.sh,
#       setup-container-backend.sh, and the CI chmod lists.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/.."
WRAPPER="$REPO/files/opencode-permissions-kit-lib/wrapper"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/update.sh"
STATUS="$REPO/files/status.sh"
CONFIG="$REPO/files/config.sh"
UNINSTALL="$REPO/files/uninstall.sh"
SUDOERS="$REPO/files/sudoers.template"
TEST_YML="$REPO/.github/workflows/test.yml"
E2E_YML="$REPO/.github/workflows/e2e.yml"

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

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected: [$expected]  got: [$actual]"
        failures=$((failures + 1))
    fi
}

grep_absent() { ! grep "$@"; }

# Mirror of the install.sh/update.sh sudoers render: substitute DEFAULT_USER.
render_sudoers() {
    local template="$1" default_user="$2" out="$3"
    sed -e "s/DEFAULT_USER/$default_user/g" "$template" > "$out"
}

# Mirror of the wrapper's container resolution. Given the backend, whether
# container tools were requested, the recorded socket (+ socket existence), and
# (for podman) whether the podman CLI is installed, echoes one of:
#   host   -> sudo -u opencode with DOCKER_HOST exported (a reachable socket)
#   podman -> sudo -u opencode, no DOCKER_HOST (podman-CLI path, daemonless)
#   none   -> no container tools this session
resolve_backend() {
    local backend="$1" requested="$2" sock_host="$3" sock_exists="$4" podman_installed="$5"
    [ "$requested" = true ] || { echo none; return; }
    case "$backend" in
        docker-rootless)
            if [ "$sock_exists" = yes ] && [ -n "$sock_host" ]; then echo host; else echo none; fi
            ;;
        podman-rootless)
            if [ -n "$sock_host" ]; then
                if [ "$sock_exists" = yes ]; then echo host; else echo none; fi
            elif [ "$podman_installed" = yes ]; then
                echo podman
            else
                echo none
            fi
            ;;
        *) echo none ;;
    esac
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ""
echo "Container Backend Tests (DDEV-WORKING)"
echo "======================================"
echo ""

echo "-- sudoers.template structure --"
check "template keeps DOCKER_HOST + XDG_RUNTIME_DIR env_keep" \
    grep -Fq 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR"' "$SUDOERS"
check "template has NO OPENCODE_LAUNCH_CWD env_keep" \
    grep_absent -Fq 'OPENCODE_LAUNCH_CWD' "$SUDOERS"
check "template has NO docker-group block sentinels" \
    grep_absent -Fq '#@docker-group' "$SUDOERS"
check "template has NO ddev delegation rule" \
    grep_absent -Fq 'DDEV_BIN' "$SUDOERS"
check "template has NO root-side helper grants (protect-projects/ddev-transaction)" \
    grep_absent -Fq 'protect-projects' "$SUDOERS"
check "template has NO ddev-transaction grant" \
    grep_absent -Fq 'ddev-transaction' "$SUDOERS"
check "base (opencode) RunAs for the binary is present" \
    grep -Eq 'ALL=\(opencode\) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode \*' "$SUDOERS"
check "template has the rootless socket-check NOPASSWD rule" \
    grep -Fq 'ALL=(opencode)  NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh *' "$SUDOERS"

echo ""
echo "-- sudoers render --"
OUT="$TMPDIR/sudoers"
render_sudoers "$SUDOERS" dev "$OUT"
check "render: substitutes DEFAULT_USER"       grep -Fq 'dev ALL=(opencode) NOPASSWD' "$OUT"
check "render: no placeholder remains"         grep_absent -Fq 'DEFAULT_USER' "$OUT"
check "render: keeps socket-check rule"        grep -Fq 'socket-check.sh' "$OUT"

echo ""
echo "-- wrapper dispatch (mirrored logic) --"
assert_eq "docker-rootless + requested + socket  -> host" "host" "$(resolve_backend docker-rootless true unix:///x yes yes)"
assert_eq "docker-rootless + requested + no socket -> none" "none" "$(resolve_backend docker-rootless true unix:///x no yes)"
assert_eq "docker-rootless + not requested -> none" "none" "$(resolve_backend docker-rootless false unix:///x yes yes)"
assert_eq "docker-rootless + requested + empty socket -> none" "none" "$(resolve_backend docker-rootless true '' yes yes)"
assert_eq "podman-rootless + requested + no socket + podman installed -> podman" "podman" "$(resolve_backend podman-rootless true '' no yes)"
assert_eq "podman-rootless + requested + no socket + podman absent -> none" "none" "$(resolve_backend podman-rootless true '' no no)"
assert_eq "podman-rootless + requested + socket reachable -> host (docker-CLI compat)" "host" "$(resolve_backend podman-rootless true unix:///x yes no)"
assert_eq "podman-rootless + requested + socket unreachable -> none" "none" "$(resolve_backend podman-rootless true unix:///x no yes)"
assert_eq "podman-rootless + not requested -> none" "none" "$(resolve_backend podman-rootless false unix:///x yes yes)"
assert_eq "docker-group (legacy) + requested -> none (no fallback)" "none" "$(resolve_backend docker-group true '' yes yes)"
assert_eq "empty backend + requested -> none" "none" "$(resolve_backend '' true '' yes yes)"

echo ""
echo "-- wrapper static wiring --"
check "wrapper normalizes backends to rootless-or-empty (no docker-group default)" \
    grep -Fq 'CONTAINER_BACKEND="${CONTAINER_BACKEND:-}"' "$WRAPPER"
check "wrapper accepts docker-rootless/podman-rootless backends" \
    grep -Fq 'docker-rootless|podman-rootless' "$WRAPPER"
check "wrapper exports DOCKER_HOST for rootless" \
    grep -Fq 'export DOCKER_HOST="$CONTAINER_DOCKER_HOST"' "$WRAPPER"
check "wrapper warns about unknown/missing backend instead of downgrading" \
    grep -Fq 'no rootless container backend configured' "$WRAPPER"
check "wrapper has podman-CLI path (daemonless, no DOCKER_HOST)" \
    grep -Fq 'CONTAINER_PODMAN=true' "$WRAPPER"
check "wrapper verifies 'command -v podman' for the podman-CLI path" \
    grep -Fq 'command -v podman' "$WRAPPER"
check "wrapper warns when podman-rootless but podman not installed" \
    grep -Fq "'podman' is not installed" "$WRAPPER"

echo ""
echo "-- wrapper rootless socket probe (socket-check.sh) --"
SOCKCHECK="$REPO/files/opencode-permissions-kit-lib/bin/socket-check.sh"
check "socket-check.sh exists"  [ -f "$SOCKCHECK" ]
check "socket-check.sh has shebang"  sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$SOCKCHECK"
check "socket-check.sh only does test -S (no command execution)" \
    grep -Fq '[ -n "$sock" ] && [ -S "$sock" ]' "$SOCKCHECK"
check "socket-check.sh strips a unix:// prefix" \
    grep -Fq 'sock="${sock#unix://}"' "$SOCKCHECK"
check "wrapper has a sock_reachable probe function" \
    grep -Fq 'sock_reachable()' "$WRAPPER"
check "wrapper probes the socket directly first (root/opencode contexts)" \
    grep -Fq '[ -S "$sock" ] 2>/dev/null && return 0' "$WRAPPER"
check "wrapper re-probes as the opencode user via socket-check.sh" \
    grep -Fq 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh "$sock"' "$WRAPPER"
check "docker-rootless branch uses sock_reachable" \
    grep -Fq 'if sock_reachable "$sock_host"; then' "$WRAPPER"
check "podman-rootless socket branch uses sock_reachable" \
    grep -Fq 'if sock_reachable "$sock_host"; then' "$WRAPPER"

echo ""
echo "-- install.sh wiring --"
check "install.sh records CONTAINER_BACKEND in install.conf" \
    grep -Fq 'CONTAINER_BACKEND=$CONTAINER_BACKEND' "$INSTALL"
check "install.sh records OPENCODE_DOCKER_HOST in install.conf" \
    grep -Fq 'OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST' "$INSTALL"
check "install.sh records OPENCODE_PODMAN_SOCKET in install.conf" \
    grep -Fq 'OPENCODE_PODMAN_SOCKET=$OPENCODE_PODMAN_SOCKET' "$INSTALL"
check "install.sh records DDEV_VERSION in install.conf" \
    grep -Fq 'DDEV_VERSION=$DDEV_VERSION' "$INSTALL"
check "install.sh preserves an existing backend on re-install" \
    grep -Eq 'sed -n '"'"'s/\^CONTAINER_BACKEND=//p'"'"' /etc/opencode-permissions-kit/install.conf' "$INSTALL"
check "install.sh validates --container-backend (rootless only)" \
    grep -Fq 'docker-rootless|podman-rootless' "$INSTALL"
check "install.sh aborts on provisioning failure (no docker-group fallback)" \
    grep -Fq 'Container backend provisioning failed' "$INSTALL"
check "install.sh fetches socket-check.sh" \
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check.sh' "$INSTALL"
check "install.sh deploys socket-check.sh to LIBDIR/bin" \
    grep -Fq '"$LIBDIR/bin/socket-check.sh"' "$INSTALL"
check "install.sh fetches setup-container-backend.sh" \
    grep -Fq 'opencode-permissions-kit-lib/setup-container-backend.sh' "$INSTALL"
check "install.sh deploys setup-container-backend.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/setup-container-backend.sh"' "$INSTALL"
check "install.sh records OPENCODE_GROUP=opencode usergroup" \
    grep -Fq 'OPENCODE_GROUP=$(id -gn "$OPENCODE_USER"' "$INSTALL"
check "install.sh adds the developer to the opencode usergroup" \
    grep -Fq 'usermod -aG "$OPENCODE_GROUP" "$DEFAULT_USER"' "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh KIT_FILES includes socket-check.sh" \
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check.sh' "$UPDATE"
check "update.sh deploys socket-check.sh to LIBDIR/bin" \
    grep -Fq '"$LIBDIR/bin/socket-check.sh"' "$UPDATE"
check "update.sh KIT_FILES includes setup-container-backend.sh" \
    grep -Fq 'opencode-permissions-kit-lib/setup-container-backend.sh' "$UPDATE"
check "update.sh deploys setup-container-backend.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/setup-container-backend.sh"' "$UPDATE"
check "update.sh KIT_FILES has NO migrate-denies.sh (legacy cleanup)" \
    grep_absent -Fq 'opencode-permissions-kit-lib/migrate-denies.sh' "$UPDATE"
check "update.sh stamps no HARD_DENY_REMOVED key anymore" \
    grep_absent -Fq 'HARD_DENY_REMOVED=1' "$UPDATE"
check "update.sh KIT_FILES has NO protect-projects.sh" \
    grep_absent -Fq 'protect-projects.sh' "$UPDATE"
check "update.sh KIT_FILES has NO ddev-transaction.sh" \
    grep_absent -Fq 'ddev-transaction.sh' "$UPDATE"
check "update.sh KIT_FILES has NO ddev shim" \
    grep_absent -Eq 'opencode-permissions-kit-lib/bin/ddev([[:space:]]|$)' "$UPDATE"
check "update.sh KIT_FILES has NO git hooks" \
    grep_absent -Fq 'hooks/post-' "$UPDATE"
check "update.sh re-stamps OPENCODE_GROUP to the opencode usergroup" \
    grep -Fq 'echo "OPENCODE_GROUP=$NEW_OPENCODE_GROUP"' "$UPDATE"
check "update.sh strips no legacy keys on re-stamp (cleanup done)" \
    grep_absent -Fq "e '^WWW_GROUP='" "$UPDATE"
check "update.sh comment documents the re-base" \
    grep -Fq 'OPENCODE_GROUP re-base' "$UPDATE"

echo ""
echo "-- OPENCODE_GROUP (legacy WWW_GROUP removed) --"
check "config.sh has no WWW_GROUP fallback" \
    grep_absent -Fq 'OPENCODE_GROUP:-${WWW_GROUP:-opencode}' "$CONFIG"
check "status.sh has no WWW_GROUP fallback" \
    grep_absent -Fq 'OPENCODE_GROUP:-${WWW_GROUP:-opencode}' "$STATUS"
check "uninstall.sh has no WWW_GROUP fallback" \
    grep_absent -Fq 'OPENCODE_GROUP:-${WWW_GROUP:-opencode}' "$UNINSTALL"
check "no remaining WWW_GROUP variable use in install.sh" \
    grep_absent -Fq '$WWW_GROUP' "$INSTALL"

echo ""
echo "-- config.sh wiring --"
check "config.sh recognizes container-backend action" \
    grep -Fq 'container-backend)' "$CONFIG"
check "config.sh has container_backend_status" \
    grep -Fq 'container_backend_status()' "$CONFIG"
check "config.sh has container_backend_apply" \
    grep -Fq 'container_backend_apply()' "$CONFIG"
check "config.sh accepts only rootless backends" \
    grep -Fq 'docker-rootless|podman-rootless' "$CONFIG"
check "config.sh has NO ddev-mode action" \
    grep_absent -Fq 'ddev-mode)' "$CONFIG"
check "config.sh has NO ddev_mode_apply" \
    grep_absent -Fq 'ddev_mode_apply' "$CONFIG"
check "config.sh menu has a container backend entry" \
    grep -Fq 'Switch container backend' "$CONFIG"

echo ""
echo "-- status.sh wiring --"
check "status.sh reports the backend name" \
    grep -Fq 'backend:' "$STATUS"
check "status.sh handles rootless backends" \
    grep -Fq 'docker-rootless|podman-rootless' "$STATUS"
check "status.sh reports socket reachability" \
    grep -Fq 'NOT reachable' "$STATUS"
check "status.sh has no migration-stamp section (legacy cleanup)" \
    grep_absent -Fq 'HARD_DENY_REMOVED' "$STATUS"

echo ""
echo "-- CI chmod lists --"
check "test.yml chmods this test"  grep -Fq './tests/test-container-backend.sh' "$TEST_YML"
check "e2e.yml chmods this test"   grep -Fq './tests/test-container-backend.sh' "$E2E_YML"
check "test.yml runs this test"   grep -Fq 'Run container backend tests' "$TEST_YML"
check "test.yml chmods setup-container-backend.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/setup-container-backend.sh' "$TEST_YML"
check "e2e.yml chmods setup-container-backend.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/setup-container-backend.sh' "$E2E_YML"
check "test.yml chmods socket-check.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/bin/socket-check.sh' "$TEST_YML"
check "e2e.yml chmods socket-check.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/bin/socket-check.sh' "$E2E_YML"
check "test.yml has no migrate-denies.sh chmod (removed)" \
    grep_absent -Fq './files/opencode-permissions-kit-lib/migrate-denies.sh' "$TEST_YML"
check "test.yml has no test-migration.sh (removed)" \
    grep_absent -Fq './tests/test-migration.sh' "$TEST_YML"

echo ""
echo "-- setup-container-backend.sh structure --"
SETUP="$REPO/files/opencode-permissions-kit-lib/setup-container-backend.sh"
check "setup-container-backend.sh exists"  [ -f "$SETUP" ]
check "setup has shebang"  sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$SETUP"
check "setup accepts rootless backends"        grep -Fq 'docker-rootless|podman-rootless' "$SETUP"
check "setup installs uidmap + dbus"         grep -Fq 'apt_install uidmap' "$SETUP"
check "setup auto-allocates subuid/subgid"   grep -Fq 'allocate_subuid_subgid' "$SETUP"
check "setup allocates non-overlapping range" grep -Fq 'allocate_range' "$SETUP"
check "setup enables linger for docker-rootless" grep -Fq 'enable_linger' "$SETUP"
check "setup runs dockerd-rootless-setuptool.sh as opencode" grep -Fq 'dockerd-rootless-setuptool.sh' "$SETUP"
check "setup installs podman for podman-rootless" grep -Fq 'apt_install uidmap dbus-user-session podman' "$SETUP"
check "setup adds Docker apt repo when docker-ce-rootless-extras missing" grep -Fq 'get.docker.com' "$SETUP"
check "setup prints OPENCODE_DOCKER_HOST on stdout" grep -Fq 'echo "OPENCODE_DOCKER_HOST=$SOCK"' "$SETUP"
check "setup reads opencode user from install.conf" grep -Fq 'OPENCODE_USER="opencode"' "$SETUP"
check "setup checks systemd for docker-rootless" grep -Fq 'systemd_user_available' "$SETUP"

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
