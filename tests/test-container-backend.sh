#!/bin/sh
# Unit tests for the container-backend awareness (Phase 1).
#
# The kit records a CONTAINER_BACKEND in install.conf (docker-group default,
# docker-rootless / podman-rootless opt-in) and the wrapper, status.sh, and the
# sudoers render all react to it. This is Phase 1 (backend awareness only — no
# rootless provisioning); see docs/DOCKER-ROOTLESS.md §7.
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

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""