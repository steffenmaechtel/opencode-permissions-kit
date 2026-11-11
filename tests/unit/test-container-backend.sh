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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/../.."
WRAPPER="$REPO/files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
# The wrapper's executable sections live in sh/as-opencode-core.sh
# since #449 (the #346 wave shape): pins on moved code target the lib.
WRAPPER_CORE="$REPO/files/opencode-permissions-kit-lib/sh/as-opencode-core.sh"
INSTALL="$REPO/files/install.sh"
INSTALL_CORE="$REPO/files/opencode-permissions-kit-lib/sh/install-core.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
STATUS="$REPO/files/opencode-permissions-kit-lib/management/status.sh"
STATUS_CORE="$REPO/files/opencode-permissions-kit-lib/sh/status-core.sh"
UPDATE_CORE="$REPO/files/opencode-permissions-kit-lib/sh/update-core.sh"
CONFIG="$REPO/files/opencode-permissions-kit-lib/management/config.sh"
UNINSTALL="$REPO/files/opencode-permissions-kit-lib/management/uninstall.sh"
UNINSTALL_CORE="$REPO/files/opencode-permissions-kit-lib/sh/uninstall-core.sh"
SUDOERS="$REPO/files/opencode-permissions-kit-lib/templates/sudoers.template"
TEST_YML="$REPO/.github/workflows/test-unit.yml"

# Shared harness (issue #417 adoption, the #394 pattern): pass/fail,
# assert_eq, extract_func + the counters live in lib/harness.sh now;
# the work registry (issue #395) owns cleanup -- this suite carries no
# trap of its own (a local trap would disarm the harness registry).
. "$SCRIPT_DIR/lib/harness.sh"

grep_absent() { ! grep "$@"; }

# Mirror of the install.sh/update.sh sudoers render: substitute DEFAULT_USER.
render_sudoers() {
    local template="$1" default_user="$2" out="$3"
    sed -e "s/DEFAULT_USER/$default_user/g" "$template" >"$out"
}

# Mirror of the wrapper's container resolution. Given the backend, whether
# container tools were requested, the recorded socket (+ socket existence), and
# (for podman) whether the podman CLI is installed, echoes one of:
#   host   -> sudo -u opencode with DOCKER_HOST exported (a reachable socket)
#   podman -> sudo -u opencode, no DOCKER_HOST (podman-CLI path, daemonless)
#   none   -> no container tools this session
resolve_backend() {
    local backend="$1" requested="$2" sock_host="$3" sock_exists="$4" podman_installed="$5"
    [ "$requested" = true ] || {
        echo none
        return
    }
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

# Scratch receiver via the work registry (issue #395). The TMPDIR
# reassignment shape (harness round A A6): the registry path froze at
# harness SOURCE time, so the reassigned TMPDIR's scratch must itself
# be a work_* receiver -- work_new registers it, the central EXIT INT
# TERM trap collects it. The F10/F13/F16 receivers below register the
# same way (they land inside this scratch; their mid-suite rm lines
# leave stale registry paths, which the cleanup rm treats as no-ops).
TMPDIR="$(work_new)"

echo ""
echo "Container Backend Tests (DDEV-WORKING)"
echo "======================================"
echo ""

echo "-- sudoers.template structure --"
check_live "template keeps DOCKER_HOST + XDG_RUNTIME_DIR + OPENCODE_SERVER_PASSWORD + USERNAME env_keep" "$SUDOERS" \
    -Fq 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME"'
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
check_live "base (opencode) RunAs for the binary is present" "$SUDOERS" \
    -Eq 'ALL=\(opencode\) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode \*'
check_live "template has the rootless socket-check NOPASSWD rule" "$SUDOERS" \
    -Fq 'ALL=(opencode)  NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/socket-check *'

echo ""
echo "-- sudoers render --"
OUT="$TMPDIR/sudoers"
render_sudoers "$SUDOERS" dev "$OUT"
check "render: substitutes DEFAULT_USER" grep -Fq 'dev ALL=(opencode) NOPASSWD' "$OUT"
check "render: no placeholder remains" grep_absent -Fq 'DEFAULT_USER' "$OUT"
check "render: keeps socket-check rule" grep -Fq "socket-check *" "$OUT"

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
check_live "wrapper normalizes backends to rootless-or-empty (no docker-group default)" "$WRAPPER" \
    -Fq 'CONTAINER_BACKEND="${CONTAINER_BACKEND:-}"'
check_live "wrapper accepts docker-rootless/podman-rootless backends" "$WRAPPER" -Fq 'docker-rootless | podman-rootless'
check_live "wrapper exports DOCKER_HOST for rootless" "$WRAPPER" -Fq 'export DOCKER_HOST="$CONTAINER_DOCKER_HOST"'
check_live "wrapper warns about unknown/missing backend instead of downgrading" "$WRAPPER_CORE" \
    -Fq 'no rootless container backend configured'
check_live "wrapper has podman-CLI path (daemonless, no DOCKER_HOST)" "$WRAPPER_CORE" -Fq 'CONTAINER_PODMAN=true'
check_live "wrapper verifies 'command -v podman' for the podman-CLI path" "$WRAPPER_CORE" -Fq 'command -v podman'
check_live "wrapper warns when podman-rootless but podman not installed" "$WRAPPER_CORE" -Fq "'podman' is not installed"

echo ""
echo "-- wrapper rootless socket probe (socket-check.sh) --"
SOCKCHECK="$REPO/files/opencode-permissions-kit-lib/bin/socket-check"
check "socket-check exists" [ -f "$SOCKCHECK" ]
if test "$(head -1 "$SOCKCHECK")" = "#!/bin/sh"; then
    pass "socket-check has shebang"
else
    fail "socket-check has shebang"
fi
check_live "socket-check only does test -S (no command execution)" "$SOCKCHECK" -Fq '[ -n "$sock" ] && [ -S "$sock" ]'
check_live "socket-check strips a unix:// prefix" "$SOCKCHECK" -Fq 'sock="${sock#unix://}"'
check_live "wrapper has a sock_reachable probe function" "$WRAPPER_CORE" -Fq 'sock_reachable()'
check_live "wrapper probes the socket directly first (root/opencode contexts)" "$WRAPPER_CORE" \
    -Fq '[ -S "$sock" ] 2>/dev/null && return 0'
check_live "wrapper re-probes as the opencode user via socket-check.sh" "$WRAPPER_CORE" \
    -Fq 'sudo -n -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check "$sock"'
check_live "docker-rootless branch uses sock_reachable" "$WRAPPER_CORE" -Fq 'if sock_reachable "$sock_host"; then'
check_live "podman-rootless socket branch uses sock_reachable" "$WRAPPER_CORE" \
    -Fq 'if sock_reachable "$sock_host"; then'

echo ""
echo "-- install.sh wiring --"
# The install.conf stamp heredoc, the backend validation/arm texts and
# the provisioning call sites live in the phase lib — install-core.sh
# since #346 wave 3 (fetch-list pins stay on the entry).
check_live "install.sh records CONTAINER_BACKEND in install.conf" "$INSTALL_CORE" \
    -Fq 'CONTAINER_BACKEND=$CONTAINER_BACKEND'
check_live "install.sh records OPENCODE_DOCKER_HOST in install.conf" "$INSTALL_CORE" \
    -Fq 'OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST'
check_live "install.sh records OPENCODE_PODMAN_SOCKET in install.conf" "$INSTALL_CORE" \
    -Fq 'OPENCODE_PODMAN_SOCKET=$OPENCODE_PODMAN_SOCKET'
check_live "install.sh records DDEV_VERSION in install.conf" "$INSTALL_CORE" -Fq 'DDEV_VERSION=$DDEV_VERSION'
check_live "install.sh preserves an existing backend on re-install" "$INSTALL_CORE" \
    -Eq 'sed -n '"'"'s/\^CONTAINER_BACKEND=//p'"'"' /etc/opencode-permissions-kit/install.conf'
check_live "install.sh validates --container-backend (rootless only)" "$INSTALL_CORE" \
    -Fq 'docker-rootless | podman-rootless'
check_live "install.sh aborts on provisioning failure (no docker-group fallback)" "$INSTALL_CORE" \
    -Fq 'Container backend provisioning failed'
check_live "install.sh fetches socket-check.sh" "$INSTALL" -Fq 'opencode-permissions-kit-lib/bin/socket-check'
if live_src "$DEPLOYLIB" | grep -qF 'opencode-permissions-kit-lib/bin/socket-check 755' &&
    live_src "$INSTALL_CORE" | grep -qF 'lib_deploy "$SCRIPT_DIR" "$LIBDIR"'; then
    pass "install.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)"
else
    fail "install.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)"
fi
check_live "install.sh fetches setup-container-backend" "$INSTALL" \
    -Fq 'opencode-permissions-kit-lib/bin/setup-container-backend'
check_live "install.sh deploys setup-container-backend to LIBDIR" "$INSTALL_CORE" \
    -Fq '"$LIBDIR/bin/setup-container-backend"'
check_live "install.sh records OPENCODE_GROUP=opencode usergroup" "$INSTALL_CORE" \
    -Fq 'OPENCODE_GROUP=$(id -gn "$OPENCODE_USER"'
check_live "install.sh adds the developer to the opencode usergroup" "$INSTALL_CORE" \
    -Fq 'usermod -aG "$OPENCODE_GROUP" "$DEFAULT_USER"'

echo ""
echo "-- update.sh wiring --"
check_live "update.sh KIT_FILES includes socket-check.sh" "$UPDATE" -Fq 'opencode-permissions-kit-lib/bin/socket-check'
if live_src "$DEPLOYLIB" | grep -qF 'opencode-permissions-kit-lib/bin/socket-check 755' &&
    live_src "$UPDATE_CORE" | grep -qF 'lib_deploy "$FILES_ROOT" "$LIBDIR"'; then
    pass "update.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)"
else
    fail "update.sh deploys socket-check.sh to LIBDIR/bin (lib_deploy manifest)"
fi
check_live "update.sh KIT_FILES includes setup-container-backend" "$UPDATE" \
    -Fq 'opencode-permissions-kit-lib/bin/setup-container-backend'
if live_src "$DEPLOYLIB" | grep -qF 'opencode-permissions-kit-lib/bin/setup-container-backend 755' &&
    live_src "$UPDATE_CORE" | grep -qF 'lib_deploy "$FILES_ROOT" "$LIBDIR"'; then
    pass "update.sh deploys setup-container-backend to LIBDIR (lib_deploy manifest)"
else
    fail "update.sh deploys setup-container-backend to LIBDIR (lib_deploy manifest)"
fi
if ! sed -n 's/^KIT_FILES="\(.*\)"$/\1/p' "$UPDATE" | grep -q migrate-denies; then
    pass "update.sh KIT_FILES has NO migrate-denies.sh (legacy cleanup)"
else
    fail "update.sh KIT_FILES has NO migrate-denies.sh (legacy cleanup)"
fi
check "update.sh stamps no HARD_DENY_REMOVED key anymore" \
    sh -c '! grep -Fq "HARD_DENY_REMOVED=1" "$1" && ! grep -Fq "HARD_DENY_REMOVED=1" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check "update.sh KIT_FILES has NO protect-projects.sh" \
    sh -c '! grep -Fq "protect-projects.sh" "$1" && ! grep -Fq "protect-projects.sh" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check "update.sh KIT_FILES has NO ddev-transaction.sh" \
    sh -c '! grep -Fq "ddev-transaction.sh" "$1" && ! grep -Fq "ddev-transaction.sh" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check "update.sh KIT_FILES has NO ddev shim" \
    sh -c '! grep -Eq "opencode-permissions-kit-lib/bin/ddev([[:space:]]|$)" "$1" && ! grep -Eq "opencode-permissions-kit-lib/bin/ddev([[:space:]]|$)" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check "update.sh KIT_FILES has NO git hooks" \
    sh -c '! grep -Fq "hooks/post-" "$1" && ! grep -Fq "hooks/post-" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check_live "update.sh re-stamps OPENCODE_GROUP to the opencode usergroup" "$UPDATE_CORE" \
    -Fq 'echo "OPENCODE_GROUP=$NEW_OPENCODE_GROUP"'
check "update.sh strips no legacy keys on re-stamp (cleanup done)" \
    sh -c '! grep -Fq "e '"'"'^WWW_GROUP='"'"'" "$1" && ! grep -Fq "e '"'"'^WWW_GROUP='"'"'" "$2"' _ "$UPDATE" "$UPDATE_CORE"
# Inversion (conventions.md "Source-counting pins", the #459 a B3
# class): the pinned literal IS a full-line comment (update.sh's
# OPENCODE_GROUP re-base note at its head) -- a comment-strip rider
# would delete the pinned bytes. Bare grep is the sanctioned shape.
check "update.sh comment documents the re-base" grep -Fq 'OPENCODE_GROUP re-base' "$UPDATE" # rider-inversion (comment-literal pin)

echo ""
echo "-- OPENCODE_GROUP (legacy WWW_GROUP removed) --"
check "config.sh has no WWW_GROUP fallback" \
    grep_absent -Fq 'OPENCODE_GROUP:-${WWW_GROUP:-opencode}' "$CONFIG"
check "status.sh has no WWW_GROUP fallback" \
    grep_absent -Fq 'OPENCODE_GROUP:-${WWW_GROUP:-opencode}' "$STATUS"
check "uninstall.sh has no WWW_GROUP fallback" \
    sh -c '! grep -Fq "\$WWW_GROUP" "$1" && ! grep -Fq "\$WWW_GROUP" "$2"' _ \
    "$UNINSTALL" "$UNINSTALL_CORE"
check "no remaining WWW_GROUP variable use in install.sh" \
    sh -c '! grep -Fq "\$WWW_GROUP" "$1" && ! grep -Fq "\$WWW_GROUP" "$2"' _ "$INSTALL" "$INSTALL_CORE"

echo ""
echo "-- config.sh wiring --"
check_live "config.sh recognizes container-backend action" "$CONFIG" -Fq 'container-backend)'
check_live "config.sh has container_backend_status" "$CONFIG" -Fq 'container_backend_status()'
check_live "config.sh has container_backend_apply" "$CONFIG" -Fq 'container_backend_apply()'
check_live "config.sh accepts only rootless backends" "$CONFIG" -Fq 'docker-rootless | podman-rootless'
check "config.sh has NO ddev-mode action" \
    grep_absent -Fq 'ddev-mode)' "$CONFIG"
check "config.sh has NO ddev_mode_apply" \
    grep_absent -Fq 'ddev_mode_apply' "$CONFIG"
check_live "config.sh menu has a container backend entry" "$CONFIG" -Fq 'Switch container backend'

echo ""
echo "-- status.sh wiring (section rows live in sh/status-core.sh, #346 wave 1) --"
# #403: 'backend:' matched exactly one line — the re-run HINT (ui_detail
# "...rootless backend:") — and 'docker-rootless|podman-rootless' only the
# hint's install command, so deleting every real backend row kept both
# pins green. The pins bind the ui_kv rows and the case arms; the
# per-backend BEHAVIOR is driven by test-status.sh's run_case sourcing
# pins — kubernetes/empty/docker-rootless since #346, podman-rootless
# (socket probe + both podman-CLI legs) since #440 — so this file keeps
# the structural layer only (rows + dispatch). Strip riders
# on the presence legs (#439 a C3): a row commented out during
# debugging and committed must not keep a pin green — the #261/#244 g
# W1 survivor trap, presence form.
check_live "status.sh backend row: docker-rootless" "$STATUS_CORE" \
    -Fq -- 'ui_kv_ok "backend" "docker-rootless"'
check_live "status.sh backend row: podman-rootless" "$STATUS_CORE" \
    -Fq -- 'ui_kv_ok "backend" "podman-rootless"'
check_live "status.sh backend row: unknown backend flagged bad" "$STATUS_CORE" \
    -Fq -- 'ui_kv_bad "backend" "unknown'
if live_src "$STATUS_CORE" | grep -Fq -- 'docker-rootless)' &&
    live_src "$STATUS_CORE" | grep -Fq -- 'podman-rootless)'; then
    pass "status.sh backend dispatch: rootless case arms"
else
    fail "status.sh backend dispatch: rootless case arms"
fi
check_live "status.sh reports socket reachability" "$STATUS_CORE" -Fq 'NOT reachable'
check "status.sh has no migration-stamp section (legacy cleanup)" \
    sh -c '! grep -Fq "HARD_DENY_REMOVED" "$1" && ! grep -Fq "HARD_DENY_REMOVED" "$2"' _ "$STATUS" "$STATUS_CORE"

echo ""
echo "-- CI wiring (issue #123: exec bits live in the git index) --"
git_mode() { git -C "$REPO" ls-files -s -- "$1" | cut -d' ' -f1; }
check_live "test-unit.yml runs this test" "$TEST_YML" -Fq 'Run container backend tests'
check "setup-container-backend is executed by path (git 100755)" \
    [ "$(git_mode files/opencode-permissions-kit-lib/bin/setup-container-backend)" = "100755" ]
check "socket-check is executed by path (git 100755)" \
    [ "$(git_mode files/opencode-permissions-kit-lib/bin/socket-check)" = "100755" ]
check "test-unit.yml has no test-migration.sh (removed)" \
    grep_absent -Fq './tests/unit/test-migration.sh' "$TEST_YML"

echo ""
echo "-- setup-container-backend structure --"
SETUP="$REPO/files/opencode-permissions-kit-lib/bin/setup-container-backend"
check "setup-container-backend exists" [ -f "$SETUP" ]
if test "$(head -1 "$SETUP")" = "#!/bin/sh"; then
    pass "setup has shebang"
else
    fail "setup has shebang"
fi
check_live "setup accepts rootless backends" "$SETUP" -Fq 'docker-rootless | podman-rootless'
check_live "setup installs uidmap + dbus" "$SETUP" -Fq 'apt_install uidmap'
check_live "setup auto-allocates subuid/subgid" "$SETUP" -Fq 'allocate_subuid_subgid'
check_live "setup allocates non-overlapping range" "$SETUP" -Fq 'allocate_range'
check_live "setup enables linger for docker-rootless" "$SETUP" -Fq 'enable_linger'
check_live "setup runs dockerd-rootless-setuptool.sh as opencode" "$SETUP" -Fq 'dockerd-rootless-setuptool.sh'
check_live "setup installs podman for podman-rootless" "$SETUP" -Fq 'apt_install uidmap dbus-user-session podman'
check_live "setup adds Docker apt repo when docker-ce-rootless-extras missing" "$SETUP" -Fq 'get.docker.com'
check_live "setup prints OPENCODE_DOCKER_HOST on stdout" "$SETUP" -Fq 'echo "OPENCODE_DOCKER_HOST=$SOCK"'
check_live "setup reads opencode user from install.conf" "$SETUP" -Fq 'OPENCODE_USER="opencode"'
check_live "setup checks systemd for docker-rootless" "$SETUP" -Fq 'systemctl --user is-active dbus'

echo ""
echo "-- late pins (arg no-op, daemon-start rc) --"
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
_f10_fn="$(extract_func "$CONFIG" update_install_conf_backend)"
if [ -n "$_f10_fn" ]; then
    check "update_install_conf_backend extractable (#211 a F10)" true
    F10="$(work_new)"
    printf 'DEFAULT_USER=dev\nOPENCODE_PODMAN_SOCKET=unix:///run/user/1000/podman/podman.sock\nCONTAINER_BACKEND=docker-rootless\n' \
        >"$F10/install.conf"
    _f10_run() {
        # $1..$3 = backend, docker_host, podman_socket — runs the REAL
        # function against $F10/install.conf with stubbed sudo/_tmp_track.
        (
            INSTALL_CONF="$F10/install.conf"
            _tmp_track() { :; }
            die() {
                echo "die: $*"
                exit 1
            }
            sudo() {
                case "$1" in
                    tee)
                        shift
                        tee "$@"
                        ;;
                    *) "$@" ;;
                esac
            }
            eval "$_f10_fn"
            update_install_conf_backend "$1" "$2" "$3"
        )
    }
    _f10_run podman-rootless "" "unix:///run/user/1000/podman/podman.sock" >/dev/null 2>&1 || true
    if grep -q '^OPENCODE_PODMAN_SOCKET=unix:///run/user/1000/podman/podman.sock$' "$F10/install.conf" &&
        grep -q '^CONTAINER_BACKEND=podman-rootless$' "$F10/install.conf"; then
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
    if grep -q 'podman_socket=\$(sed -n .s/\^OPENCODE_PODMAN_SOCKET=//p' "$CONFIG"; then
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
_f13_fn="$(extract_func "$SETUP" enable_linger)"
if [ -n "$_f13_fn" ]; then
    check "enable_linger extractable (#211 a F13)" true
    F13="$(work_new)"
    mkdir -p "$F13/bin"
    printf '#!/bin/sh\nexit 0\n' >"$F13/bin/loginctl"
    chmod +x "$F13/bin/loginctl"
    _out=$(OPENCODE_USER=oc F13LOG="$F13/log" PATH="$F13/bin:$PATH" \
        sh -c 'log() { echo "$*" >> "$F13LOG"; }; eval "$1"; enable_linger' sh "$_f13_fn" 2>&1) || true
    case "$_out" in
        *"Linger enabled for oc"*) check "ok rc: success line (#211 a F13)" true ;;
        *) check "ok rc: success line (#211 a F13, got: $_out)" false ;;
    esac
    printf '#!/bin/sh\nexit 1\n' >"$F13/bin/loginctl"
    _out=$(OPENCODE_USER=oc F13LOG="$F13/log" PATH="$F13/bin:$PATH" \
        sh -c 'log() { echo "$*" >> "$F13LOG"; }; eval "$1"; enable_linger' sh "$_f13_fn" 2>&1) || true
    case "$_out" in
        *"WARN: could not enable linger"*"retry: loginctl enable-linger oc"*)
            check "failed rc: warn + retry hint, no success line (#211 a F13)" true
            ;;
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
    grep -q 'linger enable FAILED for oc' "$F13/log" &&
        check "failed rc logged (#211 a F13)" true ||
        check "failed rc logged (#211 a F13)" false
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
_f16_fn="$(extract_func "$SETUP" allocate_range)"
if [ -n "$_f16_fn" ]; then
    check "allocate_range extractable (#211 a F16)" true
    F16="$(work_new)"
    printf 'gooduser:100000:65536\njunk:12abc:100\nzeros:010:100\nalpha:abc:100\nzerocount:1000:09\noverflow:99999999999999999999:1\nu32max:9999999999:100\nzerostart:0:1000\n' >"$F16/subuid"
    _out=$(F16FILE="$F16/subuid" sh -c '
        log() { :; }
        eval "$1"
        allocate_range "$F16FILE" f16user
    ' sh "$_f16_fn" 2>&1) || _f16_rc=$?
    # Guarded counts (#260, the #244 f W1 class): grep -c exits 1 on zero
    # matches — under set -e the bare assignment aborted before the
    # malformed-lines FAIL could record.
    _f16_warn=$(printf '%s\n' "$_out" | grep -c 'malformed line(s) skipped' || true)
    _f16_cnt=$(printf '%s\n' "$_out" | sed -n 's/.*warn: \([0-9]*\) malformed.*/\1/p')
    _f16_alloc=$(grep -c '^f16user:165536:65536$' "$F16/subuid" 2>/dev/null || true)
    # u32max (10 digits > 4294967295) is malformed on VALUE (#211 c W9)
    # — the length gate alone passed it. zerostart "0" is a GOOD line
    # (#211 c W10): accepted as an occupied empty range, so it must NOT
    # bump the malformed count — both sit in the fixture above.
    if [ "${_f16_rc:-0}" -eq 0 ] && [ "$_f16_warn" = "1" ] && [ "$_f16_cnt" = "6" ] &&
        [ "$_f16_alloc" = "1" ]; then
        check "malformed lines warn+skip, allocation correct (#211 a F16; b W10: zero-count + overflow; c W9: u32 value cap; c W10: zero-start accepted)" true
    else
        check "malformed lines warn+skip, allocation correct (rc=${_f16_rc:-0} warns=$_f16_cnt alloc=$_f16_alloc out=$_out)" false
    fi
    # The warn's enumeration must name EVERY skip cause (#211 e W2):
    # the value cap (#211 c W9) added a third — an above-u32-max line is
    # neither non-numeric nor leading-zero, and the fixture drives it.
    case "$_out" in
        *"above-u32-max"*) check "malformed warn names all skip causes incl. value cap (#211 e W2)" true ;;
        *) check "malformed warn names the value-cap cause (out=$_out) (#211 e W2)" false ;;
    esac
    rm -rf "$F16"
else
    check "allocate_range extractable (#211 a F16)" false
fi

# pr-00263 a F13 + d W4: the daemon-start rc decides the ready message
# — a failed start must WARN, not read as ready; the socket var still
# prints for the caller (the wrapper re-probes every session start).
# Exact count (d W4): capture + default + three gate/print sites = 5 —
# a floor pin would survive deletion of the capture mechanism itself.
check_live "failed daemon start warns instead of ready (pr-00263 a F13)" "$SETUP" \
    -Fq 'daemon start FAILED (rc=$_dc_start_rc)'
# Comment-strip rider (#261, the #244 g W1 class — sweep find beyond the
# issue list): a commented-out observation site stops counting.
_dcsrc_n="$(live_src "$SETUP" | grep -c "_dc_start_rc" || true)"
check "daemon start rc observed at every site, exactly 5 (pr-00263 a F13 + d W4; observed: $_dcsrc_n)" \
    [ "$_dcsrc_n" = 5 ]

suite_done "container backend tests"
