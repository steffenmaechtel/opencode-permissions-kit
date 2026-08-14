#!/bin/sh
# Unit tests for the container-backend awareness (Phase 1 + Phase 2).
#
# The kit records a CONTAINER_BACKEND in install.conf (docker-group default,
# docker-rootless / podman-rootless opt-in) and the wrapper, status.sh, and the
# sudoers render all react to it. Phase 2 adds install-time provisioning and
# the config.sh container-backend subcommand; see docs/design/DOCKER-ROOTLESS.md §7.
#
# Three layers are checked:
#   (1) sudoers.template — the docker-group RunAs grant is sentinel-wrapped so
#       the render can keep or strip it per backend; env_keep gains DOCKER_HOST
#       + XDG_RUNTIME_DIR for rootless.
#   (2) render logic (mirrors install.sh/update.sh) — keeps the grant for
#       docker-group, strips it (and the sentinels) for rootless, always keeps
#       the base (opencode) RunAs, and renders to a visudo-clean file.
#   (3) static wiring — wrapper dispatch, install.conf keys, update.sh
#       preservation, status.sh reporting, and the CI chmod lists.
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

# Negation helper: succeeds when grep finds NOTHING. (Cannot pass `! grep` as
# args to check() — dash expands "$@" and tries to run `!` as a command.)
grep_absent() { ! grep "$@"; }

# Mirror of the install.sh/update.sh sudoers render: substitute DEFAULT_USER +
# DDEV_BIN, then keep the docker-group block (stripping only the sentinel
# marker lines) for docker-group, or delete the whole block for rootless.
render_sudoers() {
    local template="$1" default_user="$2" ddev_bin="$3" backend="$4" out="$5"
    sed -e "s/DEFAULT_USER/$default_user/g" -e "s#DDEV_BIN#$ddev_bin#g" "$template" > "$out.tmp1"
    case "${backend:-docker-group}" in
        docker-rootless|podman-rootless)
            sed -e '/^#@docker-group-begin$/,/^#@docker-group-end$/d' "$out.tmp1" > "$out"
            ;;
        *)
            sed -e '/^#@docker-group-begin$/d' -e '/^#@docker-group-end$/d' "$out.tmp1" > "$out"
            ;;
    esac
    rm -f "$out.tmp1"
}

# Mirror of the wrapper's container resolution. Given the backend, whether
# container tools were requested, the recorded socket (+ socket existence), and
# (for podman) whether the podman CLI is installed, echoes one of:
#   group  -> sudo -u opencode -g docker  (docker-group backend)
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
                # Optional podman docker-compat socket.
                if [ "$sock_exists" = yes ]; then echo host; else echo none; fi
            elif [ "$podman_installed" = yes ]; then
                echo podman
            else
                echo none
            fi
            ;;
        *) echo group ;;
    esac
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo ""
echo "Container Backend Tests (Phase 1)"
echo "=================================="
echo ""

echo "-- sudoers.template structure --"
check "template preserves OPENCODE_LAUNCH_CWD env_keep" \
    grep -Fq 'env_keep += "OPENCODE_LAUNCH_CWD' "$SUDOERS"
check "template adds DOCKER_HOST to env_keep" \
    grep -Fq 'OPENCODE_LAUNCH_CWD DOCKER_HOST XDG_RUNTIME_DIR' "$SUDOERS"
check "template marks the docker-group block begin" \
    grep -Fq '#@docker-group-begin' "$SUDOERS"
check "template marks the docker-group block end" \
    grep -Fq '#@docker-group-end' "$SUDOERS"
check "docker-group grant is inside the sentinels" \
    awk '/^#@docker-group-begin$/{f=1} /opencode:docker/{if(f){found=1}} /^#@docker-group-end$/{f=0} END{exit !found}' "$SUDOERS"
check "base (opencode) RunAs is always present (outside the block)" \
    grep -Eq 'ALL=\(opencode\) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode \*' "$SUDOERS"
check "base (opencode) RunAs is NOT inside the docker-group block" \
    awk '/^#@docker-group-begin$/{f=1} /^#@docker-group-end$/{f=0; next} f && /ALL=\(opencode\) NOPASSWD/{bad=1} END{exit bad}' "$SUDOERS"
check "template has the rootless socket-check NOPASSWD rule" \
    grep -Fq 'ALL=(opencode)  NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh *' "$SUDOERS"

echo ""
echo "-- sudoers render (per backend) --"
OUT="$TMPDIR/sudoers"

render_sudoers "$SUDOERS" dev /usr/bin/ddev docker-group "$OUT"
check "docker-group: keeps (opencode:docker) grant"   grep -Fq '(opencode:docker)' "$OUT"
check "docker-group: no sentinel markers remain"      grep_absent -Fq '#@docker-group' "$OUT"
check "docker-group: keeps base (opencode) RunAs"     grep -Eq 'ALL=\(opencode\) NOPASSWD: ' "$OUT"
check "docker-group: keeps ddev delegation rule"       grep -Fq 'NOPASSWD: /usr/bin/ddev' "$OUT"

render_sudoers "$SUDOERS" dev /usr/bin/ddev docker-rootless "$OUT"
check "docker-rootless: strips (opencode:docker) grant" grep_absent -Fq '(opencode:docker)' "$OUT"
check "docker-rootless: no sentinel markers remain"     grep_absent -Fq '#@docker-group' "$OUT"
check "docker-rootless: keeps base (opencode) RunAs"    grep -Eq 'ALL=\(opencode\) NOPASSWD: ' "$OUT"
check "docker-rootless: keeps ddev delegation rule"     grep -Fq 'NOPASSWD: /usr/bin/ddev' "$OUT"

render_sudoers "$SUDOERS" dev /usr/bin/ddev podman-rootless "$OUT"
check "podman-rootless: strips (opencode:docker) grant" grep_absent -Fq '(opencode:docker)' "$OUT"
check "podman-rootless: keeps base (opencode) RunAs"    grep -Eq 'ALL=\(opencode\) NOPASSWD: ' "$OUT"

render_sudoers "$SUDOERS" dev /usr/bin/ddev "" "$OUT"
check "empty backend defaults to docker-group (keeps grant)" grep -Fq '(opencode:docker)' "$OUT"
render_sudoers "$SUDOERS" dev /usr/bin/ddev nonsense "$OUT"
check "unknown backend defaults to docker-group (keeps grant)" grep -Fq '(opencode:docker)' "$OUT"

echo ""
echo "-- wrapper dispatch (mirrored logic) --"
assert_eq "docker-group + requested -> group"    "group" "$(resolve_backend docker-group true '' yes yes)"
assert_eq "docker-rootless + requested + socket  -> host" "host" "$(resolve_backend docker-rootless true unix:///x yes yes)"
assert_eq "docker-rootless + requested + no socket -> none" "none" "$(resolve_backend docker-rootless true unix:///x no yes)"
assert_eq "docker-rootless + not requested -> none" "none" "$(resolve_backend docker-rootless false unix:///x yes yes)"
assert_eq "docker-rootless + requested + empty socket -> none" "none" "$(resolve_backend docker-rootless true '' yes yes)"
assert_eq "podman-rootless + requested + no socket + podman installed -> podman" "podman" "$(resolve_backend podman-rootless true '' no yes)"
assert_eq "podman-rootless + requested + no socket + podman absent -> none" "none" "$(resolve_backend podman-rootless true '' no no)"
assert_eq "podman-rootless + requested + socket reachable -> host (docker-CLI compat)" "host" "$(resolve_backend podman-rootless true unix:///x yes no)"
assert_eq "podman-rootless + requested + socket unreachable -> none" "none" "$(resolve_backend podman-rootless true unix:///x no yes)"
assert_eq "podman-rootless + not requested -> none" "none" "$(resolve_backend podman-rootless false unix:///x yes yes)"

echo ""
echo "-- wrapper static wiring --"
check "wrapper reads CONTAINER_BACKEND from install.conf (default docker-group)" \
    grep -Fq 'CONTAINER_BACKEND="${CONTAINER_BACKEND:-docker-group}"' "$WRAPPER"
check "wrapper accepts docker-rootless/podman-rootless backends" \
    grep -Fq 'docker-rootless|podman-rootless' "$WRAPPER"
check "wrapper exports DOCKER_HOST for rootless" \
    grep -Fq 'export DOCKER_HOST="$CONTAINER_DOCKER_HOST"' "$WRAPPER"
check "wrapper does NOT silently downgrade to -g docker for rootless" \
    grep -Fq 'not downgrading to -g docker' "$WRAPPER"
check "wrapper execs without -g when CONTAINER_DOCKER_HOST is set" \
    grep -Eq 'elif \[ -n "\$CONTAINER_DOCKER_HOST" \]' "$WRAPPER"
check "wrapper still supports explicit -g docker for docker-group" \
    grep -Fq 'docker|0|root)' "$WRAPPER"
check "wrapper has podman-CLI path (daemonless, no DOCKER_HOST)" \
    grep -Fq 'CONTAINER_PODMAN=true' "$WRAPPER"
check "wrapper verifies 'command -v podman' for the podman-CLI path" \
    grep -Fq 'command -v podman' "$WRAPPER"
check "wrapper warns when podman-rootless but podman not installed" \
    grep -Fq "'podman' is not installed" "$WRAPPER"
check "wrapper execs without -g on the podman-CLI branch" \
    grep -Fq '[ "$CONTAINER_PODMAN" = true ]; then' "$WRAPPER"

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
check "install.sh detects DDEV_VERSION from the real binary" \
    grep -Fq '"$DDEV_BIN" version' "$INSTALL"
check "install.sh preserves an existing backend on re-install" \
    grep -Eq 'sed -n '"'"'s/\^CONTAINER_BACKEND=//p'"'"' "\$_c"' "$INSTALL"
check "install.sh renders backend-aware sudoers (sentinel strip)" \
    grep -Fq '#@docker-group-begin' "$INSTALL"
check "install.sh keeps the docker grant for docker-group" \
    grep -Fq 'begin$/d' "$INSTALL"
check "install.sh strips the docker grant for rootless" \
    grep -Fq 'begin$/,/^#@docker-group-end' "$INSTALL"
check "install.sh fetches socket-check.sh" \
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check.sh' "$INSTALL"
check "install.sh deploys socket-check.sh to LIBDIR/bin" \
    grep -Fq '"$LIBDIR/bin/socket-check.sh"' "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh renders backend-aware sudoers (sentinel strip)" \
    grep -Fq '#@docker-group-begin' "$UPDATE"
check "update.sh keeps the docker grant for docker-group" \
    grep -Fq 'begin$/d' "$UPDATE"
check "update.sh strips the docker grant for rootless" \
    grep -Fq 'begin$/,/^#@docker-group-end' "$UPDATE"
# The re-stamp must preserve the new keys: it strips ONLY VERSION + DDEV_BIN.
check "update.sh re-stamp strips only VERSION + DDEV_BIN (new keys pass through)" \
    grep -Eq 'grep -v -e '"'"'\^VERSION='"'"' -e '"'"'\^DDEV_BIN='"'"' "\$INSTALL_CONF"' "$UPDATE"
check "update.sh does NOT strip CONTAINER_BACKEND in the re-stamp" \
    grep_absent -Eq 'grep -v.*CONTAINER_BACKEND' "$UPDATE"
check "update.sh still re-stamps DDEV_BIN + VERSION" \
    grep -Fq 'echo "DDEV_BIN=$DDEV_BIN"' "$UPDATE"
check "update.sh KIT_FILES includes socket-check.sh" \
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check.sh' "$UPDATE"
check "update.sh deploys socket-check.sh to LIBDIR/bin" \
    grep -Fq '"$LIBDIR/bin/socket-check.sh"' "$UPDATE"

echo ""
echo "-- status.sh wiring --"
check "status.sh reports the backend name" \
    grep -Fq 'backend:' "$STATUS"
check "status.sh handles rootless backends" \
    grep -Fq 'docker-rootless|podman-rootless' "$STATUS"
check "status.sh reports socket reachability" \
    grep -Fq 'NOT reachable' "$STATUS"
check "status.sh reports ddev version" \
    grep -Fq 'ddev version:' "$STATUS"
check "status.sh warns when rootless + ddev < 1.25" \
    grep -Fq 'rootless for ddev needs ddev' "$STATUS"

echo ""
echo "-- CI chmod lists --"
check "test.yml chmods the new test"  grep -Fq './tests/test-container-backend.sh' "$TEST_YML"
check "e2e.yml chmods the new test"   grep -Fq './tests/test-container-backend.sh' "$E2E_YML"
check "test.yml runs the new test"   grep -Fq 'Run container backend tests' "$TEST_YML"
check "test.yml chmods setup-container-backend.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/setup-container-backend.sh' "$TEST_YML"
check "e2e.yml chmods setup-container-backend.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/setup-container-backend.sh' "$E2E_YML"
check "test.yml chmods socket-check.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/bin/socket-check.sh' "$TEST_YML"
check "e2e.yml chmods socket-check.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/bin/socket-check.sh' "$E2E_YML"

echo ""
echo "-- Phase 2: setup-container-backend.sh structure --"
SETUP="$REPO/files/opencode-permissions-kit-lib/setup-container-backend.sh"
check "setup-container-backend.sh exists"  [ -f "$SETUP" ]
check "setup has shebang"  sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$SETUP"
check "setup accepts docker-rootless"        grep -Fq 'docker-rootless|podman-rootless|docker-group' "$SETUP"
check "setup installs uidmap + dbus"         grep -Fq 'apt_install uidmap' "$SETUP"
check "setup auto-allocates subuid/subgid"   grep -Fq 'allocate_subuid_subgid' "$SETUP"
check "setup allocates non-overlapping range" grep -Fq 'allocate_range' "$SETUP"
check "setup enables linger for docker-rootless" grep -Fq 'enable_linger' "$SETUP"
check "setup runs dockerd-rootless-setuptool.sh as opencode" grep -Fq 'dockerd-rootless-setuptool.sh' "$SETUP"
check "setup installs podman for podman-rootless" grep -Fq 'apt_install uidmap dbus-user-session podman' "$SETUP"
check "setup adds Docker apt repo when docker-ce-rootless-extras missing" grep -Fq 'get.docker.com' "$SETUP"
check "setup tears down when switching to docker-group" grep -Fq 'teardown_rootless' "$SETUP"
check "setup prints OPENCODE_DOCKER_HOST on stdout" grep -Fq 'echo "OPENCODE_DOCKER_HOST=$SOCK"' "$SETUP"
check "setup reads opencode user from install.conf" grep -Fq 'OPENCODE_USER="opencode"' "$SETUP"
check "setup checks systemd for docker-rootless" grep -Fq 'systemd_user_available' "$SETUP"

echo ""
echo "-- Phase 2: install.sh provisioning --"
check "install.sh has --container-backend flag" \
    grep -Fq 'CONTAINER_BACKEND_OPT="$2"' "$INSTALL"
check "install.sh validates --container-backend value" \
    grep -Fq 'docker-group|docker-rootless|podman-rootless|none' "$INSTALL"
check "install.sh fetches setup-container-backend.sh" \
    grep -Fq 'opencode-permissions-kit-lib/setup-container-backend.sh' "$INSTALL"
check "install.sh deploys setup-container-backend.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/setup-container-backend.sh"' "$INSTALL"
check "install.sh chmods setup-container-backend.sh" \
    grep -Fq '$LIBDIR/setup-container-backend.sh' "$INSTALL"
check "install.sh has interactive backend prompt" \
    grep -Fq 'Container backend' "$INSTALL"
check "install.sh calls setup helper for rootless" \
    grep -Fq 'setup-container-backend.sh' "$INSTALL"
check "install.sh falls back to docker-group on provisioning failure" \
    grep -Fq 'Falling back to docker-group' "$INSTALL"

echo ""
echo "-- Phase 2: update.sh deploy --"
check "update.sh KIT_FILES includes setup-container-backend.sh" \
    grep -Fq 'opencode-permissions-kit-lib/setup-container-backend.sh' "$UPDATE"
check "update.sh deploys setup-container-backend.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/setup-container-backend.sh"' "$UPDATE"
check "update.sh chmods setup-container-backend.sh" \
    grep -Fq '$LIBDIR/setup-container-backend.sh' "$UPDATE"

echo ""
echo "-- Phase 2: config.sh container-backend subcommand --"
CONFIG="$REPO/files/config.sh"
check "config.sh recognizes container-backend action" \
    grep -Fq 'container-backend)' "$CONFIG"
check "config.sh has container_backend_status" \
    grep -Fq 'container_backend_status()' "$CONFIG"
check "config.sh has container_backend_apply" \
    grep -Fq 'container_backend_apply()' "$CONFIG"
check "config.sh has render_sudoers" \
    grep -Fq 'render_sudoers()' "$CONFIG"
check "config.sh has update_install_conf_backend" \
    grep -Fq 'update_install_conf_backend()' "$CONFIG"
check "config.sh dispatches container-backend subcommand" \
    grep -Fq 'container-backend)' "$CONFIG"
check "config.sh accepts docker-group|docker-rootless|podman-rootless sub" \
    grep -Fq 'docker-group|docker-rootless|podman-rootless' "$CONFIG"
check "config.sh menu has [5] container backend entry" \
    grep -Fq '[5] Switch container backend' "$CONFIG"
check "config.sh calls setup-container-backend.sh" \
    grep -Fq 'setup-container-backend.sh' "$CONFIG"
check "config.sh render_sudoers strips docker-group block for rootless" \
    grep -Fq 'begin$/' "$CONFIG"

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""