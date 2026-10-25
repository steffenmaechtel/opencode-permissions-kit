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
#       setup-container-backend, and the git exec bit.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/../.."
WRAPPER="$REPO/files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
STATUS="$REPO/files/opencode-permissions-kit-lib/management/status.sh"
CONFIG="$REPO/files/opencode-permissions-kit-lib/management/config.sh"
UNINSTALL="$REPO/files/opencode-permissions-kit-lib/management/uninstall.sh"
SUDOERS="$REPO/files/opencode-permissions-kit-lib/templates/sudoers.template"
TEST_YML="$REPO/.github/workflows/test-unit.yml"

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
check "template keeps DOCKER_HOST + XDG_RUNTIME_DIR + OPENCODE_SERVER_PASSWORD + USERNAME env_keep" \
    grep -Fq 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME"' "$SUDOERS"
check "template has NO DDEV_DEBUG env_keep (describe URL transport needs none)" \
    grep_absent -Fq 'DDEV_DEBUG' "$SUDOERS"
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
    grep -Fq 'ALL=(opencode)  NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/socket-check *' "$SUDOERS"

echo ""
echo "-- sudoers render --"
OUT="$TMPDIR/sudoers"
render_sudoers "$SUDOERS" dev "$OUT"
check "render: substitutes DEFAULT_USER"       grep -Fq 'dev ALL=(opencode) NOPASSWD' "$OUT"
check "render: no placeholder remains"         grep_absent -Fq 'DEFAULT_USER' "$OUT"
check "render: keeps socket-check rule"        grep -Fq "socket-check *" "$OUT"

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
SOCKCHECK="$REPO/files/opencode-permissions-kit-lib/bin/socket-check"
check "socket-check exists"  [ -f "$SOCKCHECK" ]
check "socket-check has shebang"  sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$SOCKCHECK"
check "socket-check only does test -S (no command execution)" \
    grep -Fq '[ -n "$sock" ] && [ -S "$sock" ]' "$SOCKCHECK"
check "socket-check strips a unix:// prefix" \
    grep -Fq 'sock="${sock#unix://}"' "$SOCKCHECK"
check "wrapper has a sock_reachable probe function" \
    grep -Fq 'sock_reachable()' "$WRAPPER"
check "wrapper probes the socket directly first (root/opencode contexts)" \
    grep -Fq '[ -S "$sock" ] 2>/dev/null && return 0' "$WRAPPER"
check "wrapper re-probes as the opencode user via socket-check.sh" \
    grep -Fq 'sudo -n -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check "$sock"' "$WRAPPER"
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
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check' "$INSTALL"
check "install.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/bin/socket-check 755" "$2" \
        && grep -qF "lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"" "$1"' _ "$INSTALL" "$DEPLOYLIB"
check "install.sh fetches setup-container-backend" \
    grep -Fq 'opencode-permissions-kit-lib/bin/setup-container-backend' "$INSTALL"
check "install.sh deploys setup-container-backend to LIBDIR" \
    grep -Fq '"$LIBDIR/bin/setup-container-backend"' "$INSTALL"
check "install.sh records OPENCODE_GROUP=opencode usergroup" \
    grep -Fq 'OPENCODE_GROUP=$(id -gn "$OPENCODE_USER"' "$INSTALL"
check "install.sh adds the developer to the opencode usergroup" \
    grep -Fq 'usermod -aG "$OPENCODE_GROUP" "$DEFAULT_USER"' "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh KIT_FILES includes socket-check.sh" \
    grep -Fq 'opencode-permissions-kit-lib/bin/socket-check' "$UPDATE"
check "update.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/bin/socket-check 755" "$2" \
        && grep -qF "lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"" "$1"' _ "$UPDATE" "$DEPLOYLIB"
check "update.sh KIT_FILES includes setup-container-backend" \
    grep -Fq 'opencode-permissions-kit-lib/bin/setup-container-backend' "$UPDATE"
check "update.sh deploys setup-container-backend to LIBDIR (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/bin/setup-container-backend 755" "$2" \
        && grep -qF "lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"" "$1"' _ "$UPDATE" "$DEPLOYLIB"
check "update.sh KIT_FILES has NO migrate-denies.sh (legacy cleanup)" \
    sh -c "! sed -n 's/^KIT_FILES=\"\\(.*\\)\"$/\\1/p' \"\$1\" | grep -q migrate-denies" _ "$UPDATE"
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
echo "-- CI wiring (issue #123: exec bits live in the git index) --"
git_mode() { git -C "$REPO" ls-files -s -- "$1" | cut -d' ' -f1; }
check "test-unit.yml runs this test"   grep -Fq 'Run container backend tests' "$TEST_YML"
check "setup-container-backend is executed by path (git 100755)" \
    [ "$(git_mode files/opencode-permissions-kit-lib/bin/setup-container-backend)" = "100755" ]
check "socket-check is executed by path (git 100755)" \
    [ "$(git_mode files/opencode-permissions-kit-lib/bin/socket-check)" = "100755" ]
check "test-unit.yml has no test-migration.sh (removed)" \
    grep_absent -Fq './tests/unit/test-migration.sh' "$TEST_YML"

echo ""
echo "-- setup-container-backend structure --"
SETUP="$REPO/files/opencode-permissions-kit-lib/bin/setup-container-backend"
check "setup-container-backend exists"  [ -f "$SETUP" ]
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
check "setup checks systemd for docker-rootless" grep -Fq 'systemctl --user is-active dbus' "$SETUP"

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
# --yes is an accepted no-op (0.0.44b W16/V28)
_v28_out=$(sh "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/setup-container-backend" --yes 2>&1 || true)
case "$_v28_out" in
    *"unknown arg"*) check "--yes accepted as no-op, usage error only for the missing backend (V28)" false ;;
    *Usage*) check "--yes accepted as no-op, usage error only for the missing backend (V28)" true ;;
    *) check "--yes accepted as no-op (V28, got: $_v28_out)" false ;;
esac

# --- backend switch preserves a hand-set OPENCODE_PODMAN_SOCKET (#211 a F10) ---
# update_install_conf_backend grep-removes all three backend keys and
# re-adds only what the caller hands it; container_backend_apply used
# to hand an always-empty podman_socket, silently deleting a key the
# user added by hand (install.sh preserves it across re-installs).
# Pin: the REAL function against a scratch conf — the key survives a
# switch TO podman-rootless and clears when switching away — plus the
# caller-side carry-over wiring.
_f10_fn="$(sed -n '/^update_install_conf_backend() {/,/^}/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh")"
if [ -n "$_f10_fn" ]; then
    check "update_install_conf_backend extractable (#211 a F10)" true
    F10=$(mktemp -d)
    printf 'DEFAULT_USER=dev\nOPENCODE_PODMAN_SOCKET=unix:///run/user/1000/podman/podman.sock\nCONTAINER_BACKEND=docker-rootless\n' \
        > "$F10/install.conf"
    _f10_run() {
        # $1..$3 = backend, docker_host, podman_socket — runs the REAL
        # function against $F10/install.conf with stubbed sudo/_tmp_track.
        (
            INSTALL_CONF="$F10/install.conf"
            _tmp_track() { :; }
            die() { echo "die: $*"; exit 1; }
            sudo() {
                case "$1" in
                    tee) shift; tee "$@" ;;
                    *)   "$@" ;;
                esac
            }
            eval "$_f10_fn"
            update_install_conf_backend "$1" "$2" "$3"
        )
    }
    _f10_run podman-rootless "" "unix:///run/user/1000/podman/podman.sock" >/dev/null 2>&1 || true
    if grep -q '^OPENCODE_PODMAN_SOCKET=unix:///run/user/1000/podman/podman.sock$' "$F10/install.conf" \
       && grep -q '^CONTAINER_BACKEND=podman-rootless$' "$F10/install.conf"; then
        check "hand-set podman socket survives the switch TO podman (#211 a F10)" true
    else
        check "hand-set podman socket survives the switch TO podman (#211 a F10)" false
    fi
    _f10_run docker-rootless "unix:///run/user/1000/docker.sock" "" >/dev/null 2>&1 || true
    if grep -q '^OPENCODE_PODMAN_SOCKET=' "$F10/install.conf"; then
        check "socket key clears when switching away (documented direction)" false
    else
        check "socket key clears when switching away (documented direction)" true
    fi
    rm -rf "$F10"
    if grep -q 'podman_socket=\$(sed -n .s/\^OPENCODE_PODMAN_SOCKET=//p' \
        "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"; then
        check "caller carries the pre-existing key over (#211 a F10 wiring)" true
    else
        check "caller carries the pre-existing key over (#211 a F10 wiring)" false
    fi
else
    check "update_install_conf_backend extractable (#211 a F10)" false
fi

# --- linger message conditioned on its rc (#211 a F13) ----------------------------
# `loginctl enable-linger ... || true` + an unconditional "Linger
# enabled" line claimed session-survival even when enabling failed —
# the rootless daemon died at logout and ddev "randomly" lost its
# backend. Extract the REAL enable_linger and drive it with stubbed
# loginctl: ok -> success, fail -> warn + retry hint, absent -> silent.
_f13_fn="$(sed -n '/^enable_linger() {/,/^}$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/setup-container-backend")"
if [ -n "$_f13_fn" ]; then
    check "enable_linger extractable (#211 a F13)" true
    F13=$(mktemp -d)
    mkdir -p "$F13/bin"
    printf '#!/bin/sh\nexit 0\n' > "$F13/bin/loginctl"; chmod +x "$F13/bin/loginctl"
    _out=$(OPENCODE_USER=oc F13LOG="$F13/log" PATH="$F13/bin:$PATH" \
        sh -c 'log() { echo "$*" >> "$F13LOG"; }; eval "$1"; enable_linger' sh "$_f13_fn" 2>&1) || true
    case "$_out" in
        *"Linger enabled for oc"*) check "ok rc: success line (#211 a F13)" true ;;
        *) check "ok rc: success line (#211 a F13, got: $_out)" false ;;
    esac
    printf '#!/bin/sh\nexit 1\n' > "$F13/bin/loginctl"
    _out=$(OPENCODE_USER=oc F13LOG="$F13/log" PATH="$F13/bin:$PATH" \
        sh -c 'log() { echo "$*" >> "$F13LOG"; }; eval "$1"; enable_linger' sh "$_f13_fn" 2>&1) || true
    case "$_out" in
        *"WARN: could not enable linger"*"retry: loginctl enable-linger oc"*)
            check "failed rc: warn + retry hint, no success line (#211 a F13)" true ;;
        *) check "failed rc: warn + retry hint (got: $_out)" false ;;
    esac
    mkdir -p "$F13/emptybin"
    _f13_sh="$(command -v sh)"
    _out=$(OPENCODE_USER=oc F13LOG="$F13/log" PATH="$F13/emptybin" \
        "$_f13_sh" -c 'log() { echo "$*" >> "$F13LOG"; }; eval "$1"; enable_linger' sh "$_f13_fn" 2>&1) || true
    case "$_out" in
        "") check "no loginctl: block silent (#211 a F13)" true ;;
        *) check "no loginctl: block silent (got: $_out)" false ;;
    esac
    grep -q 'linger enable FAILED for oc' "$F13/log" \
        && check "failed rc logged (#211 a F13)" true \
        || check "failed rc logged (#211 a F13)" false
    rm -rf "$F13"
else
    check "enable_linger extractable (#211 a F13)" false
fi

# --- subuid/subgid fields validated before arithmetic (#211 a F16) ----------------
# allocate_range fed raw /etc/subuid fields into $(( )) — digit-leading
# junk aborted provisioning under set -e with a cryptic foreign error,
# leading zeros misparsed as octal. Malformed lines now warn and skip.
# Pin: the REAL function against a scratch file carrying one good and
# three malformed lines — warns for the bad ones, correct allocation
# past the good range, rc 0.
_f16_fn="$(sed -n '/^allocate_range() {/,/^}$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/setup-container-backend")"
if [ -n "$_f16_fn" ]; then
    check "allocate_range extractable (#211 a F16)" true
    F16=$(mktemp -d)
    printf 'gooduser:100000:65536\njunk:12abc:100\nzeros:010:100\nalpha:abc:100\nzerocount:1000:09\noverflow:99999999999999999999:1\nu32max:9999999999:100\nzerostart:0:1000\n' > "$F16/subuid"
    _out=$(F16FILE="$F16/subuid" sh -c '
        log() { :; }
        eval "$1"
        allocate_range "$F16FILE" f16user
    ' sh "$_f16_fn" 2>&1) || _f16_rc=$?
    _f16_warn=$(printf '%s\n' "$_out" | grep -c 'malformed line(s) skipped')
    _f16_cnt=$(printf '%s\n' "$_out" | sed -n 's/.*warn: \([0-9]*\) malformed.*/\1/p')
    _f16_alloc=$(grep -c '^f16user:165536:65536$' "$F16/subuid" 2>/dev/null)
    # u32max (10 digits > 4294967295) is malformed on VALUE (#211 c W9)
    # — the length gate alone passed it. zerostart "0" is a GOOD line
    # (#211 c W10): accepted as an occupied empty range, so it must NOT
    # bump the malformed count — both sit in the fixture above.
    if [ "${_f16_rc:-0}" -eq 0 ] && [ "$_f16_warn" = "1" ] && [ "$_f16_cnt" = "6" ] \
       && [ "$_f16_alloc" = "1" ]; then
        check "malformed lines warn+skip, allocation correct (#211 a F16; b W10: zero-count + overflow; c W9: u32 value cap; c W10: zero-start accepted)" true
    else
        check "malformed lines warn+skip, allocation correct (rc=${_f16_rc:-0} warns=$_f16_cnt alloc=$_f16_alloc out=$_out)" false
    fi
    # The warn's enumeration must name EVERY skip cause (#211 e W2):
    # the value cap (c W9) added a third — an above-u32-max line is
    # neither non-numeric nor leading-zero, and the fixture drives it.
    case "$_out" in
        *"above-u32-max"*) check "malformed warn names all skip causes incl. value cap (#211 e W2)" true ;;
        *) check "malformed warn names the value-cap cause (out=$_out) (#211 e W2)" false ;;
    esac
    rm -rf "$F16"
else
    check "allocate_range extractable (#211 a F16)" false
fi

# pr-00263 a F13: the daemon-start rc decides the ready message — a
# failed start must WARN, not read as ready; the socket var still
# prints for the caller (the wrapper re-probes every session start).
check "failed daemon start warns instead of ready (pr-00263 a F13)" \
    grep -Fq 'daemon start FAILED (rc=$_dc_start_rc)' "$SETUP"
check "daemon start rc observed at every site (pr-00263 a F13)" \
    sh -c '[ "$(grep -c "_dc_start_rc" "$1")" -ge 3 ]' _ "$SETUP"

if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
