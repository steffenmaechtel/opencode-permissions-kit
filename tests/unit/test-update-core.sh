#!/bin/sh
# Unit tests for sh/update-core.sh (issue #346, wave 2): the update
# run's phase functions, sourced from the lib the way update.sh sources
# them — the log.sh pin pattern (source the lib, call the function,
# stub the environment). The fragment harnesses over the lib's blocks
# stay in test-update-flags.sh; the root-run flows stay with e2e. This
# suite pins what only the DECOMPOSED shape can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every phase function + moved helper is defined by sourcing
#   - update.sh resolves the lib checkout-first and errors loud when
#     it is missing (presence-level; driving the error needs the whole
#     fetch flow — deliberately not pinned, pin-cost budget)
#   - the library re-deploy section executes from the lib (lib_deploy
#     argv + success line)
#   - the sudoers section: conservative-skip arm and deploy arm
#   - the umask section: terminal-loud skip arm and atomic deploy arm
#   - the cli-links section: the three sudo argv sites
#   - the install.conf re-stamp renders BYTE-EXACTLY (the dq-splice
#     success line — #346 wave 2 moved it, only execution proves the
#     seam) and writes keep+4-keys sorted to a trap-registered temp
#   - the ddev stamp probe keeps the old stamp when nothing answers
#     (environment-marked: skipped on hosts with a real ddev binary —
#     the /usr/local/bin fallback probes literal paths, the 0.0.46a F2
#     class; the update_binary_resecure die-arm is NOT pinned here for
#     the same reason — SYSTEM_BIN is the literal deployed path)
# Run: sh tests/unit/test-update-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"

# Shared harness (issue #394): pass/fail, counters + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# --- 1. sourcing purity: definitions only, zero side effects ----------------------
_purity_out=$(sh -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing update-core.sh runs nothing, prints nothing"
else
    fail "sourcing update-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi

# --- 2. every phase function + moved helper is defined by sourcing ----------------
_defs="update_redeploy_library update_redeploy_wsl_bridge
update_redeploy_cli_links update_redeploy_xdg_shim update_redeploy_sudoers
update_redeploy_umask update_redeploy_openchamber update_redeploy_shell_hooks
update_redeploy_project_roots update_redeploy_git_safe update_redeploy_wsl_mntc
update_binary_resecure update_binary_upgrade
detect_target opencode_version_line install_binary version_major
current_opencode_major resolve_latest_opencode_version fetch_opencode_version
sync_tui_registration
update_finalize_opencode_home update_finalize_default_config
update_finalize_ddev_stamp update_finalize_install_conf
update_finalize_tui_files"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all 26 phase/helper functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 3. update.sh resolves the lib checkout-first, loud when missing --------------
# Presence-level pin (the resolver mirrors status.sh's status-core
# resolution, wave 1): the sequencer must not run when the lib is gone.
check "update.sh sources update-core.sh checkout-first" \
    sh -c 'grep -qF "UPDATE_CORE=\"\$SCRIPT_DIR/../sh/update-core.sh\"" "$1" \
        && grep -qF "[ -f \"\$UPDATE_CORE\" ] || UPDATE_CORE=\"\$LIBDIR/sh/update-core.sh\"" "$1" \
        && grep -qF ". \"\$UPDATE_CORE\"" "$1"' _ "$UPDATE"
check "update.sh errors loud on a missing lib (no silent phase drops)" \
    sh -c 'grep -qF "error: update-core.sh not found" "$1"' _ "$UPDATE"
check "update.sh sequences the phases in run order" \
    sh -c '_l1=$(grep -nF "    update_redeploy_library" "$1" | head -1 | cut -d: -f1)
        _l2=$(grep -nF "update_binary_resecure" "$1" | head -1 | cut -d: -f1)
        _l3=$(grep -nF "    update_finalize_tui_files" "$1" | head -1 | cut -d: -f1)
        [ -n "$_l1" ] && [ -n "$_l2" ] && [ -n "$_l3" ] && [ "$_l1" -lt "$_l2" ] && [ "$_l2" -lt "$_l3" ]' _ "$UPDATE"

# --- 4. library re-deploy section: executes from the lib -------------------------
_lib_run() {
    (
        FILES_ROOT="$WORK/froot"
        LIBDIR="$WORK/ldir"
        log() { echo "log: $*"; }
        ui_section() { echo "section: $*"; }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        lib_deploy() { echo "LIB_DEPLOY: $*"; }
        sudo() { echo "SUDO: $*"; }
        . "$LIB"
        update_redeploy_library
    ) 2>&1
}
_out=$(_lib_run || true)
if printf '%s\n' "$_out" | grep -qF "LIB_DEPLOY: $WORK/froot $WORK/ldir" &&
    printf '%s\n' "$_out" | grep -qF 'section: Re-deploying library files' &&
    printf '%s\n' "$_out" | grep -qF "success: library re-deployed: $WORK/ldir" &&
    printf '%s\n' "$_out" | grep -qF 'log: library re-deployed: '; then
    pass "library section: deploys via the manifest from FILES_ROOT"
else
    fail "library section broken (out=$_out)"
fi

# --- 5. sudoers section: conservative skip + deploy arms --------------------------
_sk_run() {
    # $1 = FILES_ROOT (with or without the template)
    (
        FILES_ROOT="$1"
        DEFAULT_USER=skdev
        die() {
            echo "die: $*"
            exit 1
        }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        log() { echo "log: $*"; }
        sudoers_deploy() { echo "SUDOERS_DEPLOY: $*"; }
        . "$LIB"
        update_redeploy_sudoers
    ) 2>&1
}
_out=$(_sk_run "$WORK/froot-missing" || true)
if printf '%s\n' "$_out" | grep -qF 'detail: sudoers re-deploy skipped: template missing (existing sudoers kept)' &&
    printf '%s\n' "$_out" | grep -qF 'log: sudoers re-deploy skipped: ' &&
    ! printf '%s\n' "$_out" | grep -q 'SUDOERS_DEPLOY'; then
    pass "sudoers section: missing template skips terminal-loud, keeps sudoers"
else
    fail "sudoers section skip arm broken (out=$_out)"
fi
mkdir -p "$WORK/froot-tpl/opencode-permissions-kit-lib/templates"
: >"$WORK/froot-tpl/opencode-permissions-kit-lib/templates/sudoers.template"
_out=$(_sk_run "$WORK/froot-tpl" || true)
if printf '%s\n' "$_out" | grep -qF "SUDOERS_DEPLOY: $WORK/froot-tpl/opencode-permissions-kit-lib/templates/sudoers.template skdev" &&
    printf '%s\n' "$_out" | grep -qF 'success: sudoers re-deployed + validated (DEFAULT_USER=skdev)'; then
    pass "sudoers section: present template deploys with DEFAULT_USER"
else
    fail "sudoers section deploy arm broken (out=$_out)"
fi

# --- 6. umask section: terminal-loud skip + atomic deploy arms (#211 a F6) --------
_um_run() {
    # $1 = FILES_ROOT; $2 = copy_file_atomic rc
    (
        FILES_ROOT="$1"
        CFA_RC="$2"
        die() {
            echo "die: $*"
            exit 1
        }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        log() { echo "log: $*"; }
        copy_file_atomic() {
            echo "COPY_FILE_ATOMIC: $*"
            return "$CFA_RC"
        }
        sudo() { echo "SUDO: $*"; }
        . "$LIB"
        update_redeploy_umask
    ) 2>&1
}
_out=$(_um_run "$WORK/froot-missing" 0 || true)
if printf '%s\n' "$_out" | grep -qF 'detail: umask profile re-deploy skipped: source file missing (existing profile kept)' &&
    ! printf '%s\n' "$_out" | grep -q 'COPY_FILE_ATOMIC'; then
    pass "umask section: missing source skips terminal-loud"
else
    fail "umask section skip arm broken (out=$_out)"
fi
mkdir -p "$WORK/froot-um/etc"
printf 'umask 027\n' >"$WORK/froot-um/etc/umask.sh"
_out=$(_um_run "$WORK/froot-um" 0 || true)
if printf '%s\n' "$_out" | grep -qF "COPY_FILE_ATOMIC: $WORK/froot-um/etc/umask.sh /etc/profile.d/opencode-permissions-kit-umask.sh 644" &&
    printf '%s\n' "$_out" | grep -qF 'success: umask profile re-deployed'; then
    pass "umask section: deploys atomically at mode 644"
else
    fail "umask section deploy arm broken (out=$_out)"
fi
_out=$(_um_run "$WORK/froot-um" 1 || true)
if printf '%s\n' "$_out" | grep -qF 'die: umask profile re-deploy failed (atomic deploy)'; then
    pass "umask section: failed atomic deploy dies loud"
else
    fail "umask section failure arm broken (out=$_out)"
fi

# --- 7. cli-links section: the three sudo argv sites ------------------------------
_cl_out=$(
    (
        LIBDIR="$WORK/ldir"
        ui_success() { echo "success: $*"; }
        sudo() { echo "SUDO: $*"; }
        . "$LIB"
        update_redeploy_cli_links
    ) 2>&1
) || true
if printf '%s\n' "$_cl_out" | grep -qF "SUDO: ln -sf $WORK/ldir/bin/opencode-as-opencode /usr/local/bin/opencode" &&
    printf '%s\n' "$_cl_out" | grep -qF 'SUDO: rm -f /usr/local/bin/opencode-permissions-kit' &&
    printf '%s\n' "$_cl_out" | grep -qF "SUDO: ln -sf $WORK/ldir/bin/opk /usr/local/bin/opk" &&
    printf '%s\n' "$_cl_out" | grep -qF 'success: cli symlink refreshed' &&
    [ "$(printf '%s\n' "$_cl_out" | grep -c '^SUDO: ')" = 3 ]; then
    pass "cli-links section: wrapper + legacy rm + cli symlink, exactly three sudo sites"
else
    fail "cli-links section broken (out=$_cl_out)"
fi

# --- 8. install.conf re-stamp: byte-exact splice lines + sorted content -----------
# The success/log lines carry the file's one remaining dq-splice pair —
# #346 wave 2 moved them, and a seam mutation passes every substring
# pin (the #331 a a-1 class): the rendered line must match FULL-LINE.
mkdir -p "$WORK/conf"
_ic_run() {
    # $1 = initial install.conf content
    printf '%s\n' "$1" >"$WORK/conf/install.conf"
    (
        CONFDIR="$WORK/conf"
        INSTALL_CONF="$WORK/conf/install.conf"
        NEW_OPENCODE_GROUP=ocgrp
        KIT_BRANCH=stable
        VERSION=9.9.9
        NEW_DDEV_VERSION=1.2.3
        _tmp_track() { echo "TRACK: $*"; }
        die() {
            echo "die: $*"
            exit 1
        }
        ui_success() { printf 'success: %s\n' "$*"; }
        log() { printf 'log: %s\n' "$*"; }
        sudo() { "$@"; } # scratch operands only: tee/chmod/mv pass through
        . "$LIB"
        update_finalize_install_conf
    ) 2>&1
}
_out=$(_ic_run 'DEFAULT_USER=dev
OPENCODE_MAJOR=2
VERSION=0.0.1
KIT_CHANNEL=old
OPENCODE_GROUP=oldgrp
DDEV_VERSION=0.1.0' || true)
if printf '%s\n' "$_out" | grep -qxF 'success: install.conf updated: VERSION=9.9.9 CHANNEL=stable OPENCODE_GROUP=ocgrp DDEV_VERSION=1.2.3' &&
    printf '%s\n' "$_out" | grep -qxF 'log: install.conf updated: VERSION=9.9.9 CHANNEL=stable OPENCODE_GROUP=ocgrp DDEV_VERSION=1.2.3' &&
    printf '%s\n' "$_out" | grep -qF 'TRACK: '"$WORK"'/conf/install.conf.opk-new.'; then
    pass "install.conf re-stamp: splice lines render byte-exactly, temp trap-registered"
else
    fail "install.conf re-stamp output broken (out=$_out)"
fi
# File content: keep-lines survive, the four owned keys re-stamp. The
# deployed order follows the HOST sort's collation (pre-existing, the
# original block sorted the same way) — assert the SET of lines under
# LC_ALL=C, not the byte order.
_ic_file="$WORK/conf/install.conf"
if [ "$(LC_ALL=C sort "$_ic_file")" = "$(printf '%s\n' \
    'DEFAULT_USER=dev' \
    'DDEV_VERSION=1.2.3' \
    'KIT_CHANNEL=stable' \
    'OPENCODE_GROUP=ocgrp' \
    'OPENCODE_MAJOR=2' \
    'VERSION=9.9.9' | LC_ALL=C sort)" ]; then
    pass "install.conf re-stamp: keep + four owned keys (set-equal)"
else
    fail "install.conf re-stamp content broken ($(cat "$_ic_file"))"
fi

# --- 9. ddev stamp probe: the old stamp survives when nothing answers --------------
# Environment-marked (the 0.0.46a F2 class): the fallback probes the
# literal /usr/local/bin/ddev and /usr/bin/ddev paths — a ddev on the
# contributor host answers and the leg would test that host's version.
if [ -x /usr/local/bin/ddev ] || [ -x /usr/bin/ddev ] || command -v ddev >/dev/null 2>&1; then
    echo "  SKIP  ddev stamp probe keeps the old stamp (host has ddev on PATH or the probe paths)"
else
    mkdir -p "$WORK/ddev-conf"
    printf 'DDEV_VERSION=1.2.3\n' >"$WORK/ddev-conf/install.conf"
    _dv_out=$(
        (
            CONFDIR="$WORK/ddev-conf"
            INSTALL_CONF="$WORK/ddev-conf/install.conf"
            LIBDIR="$WORK/ldir-noprobe"
            OPENCODE_USER=opencode-no-such-user-424242
            . "$LIB"
            update_finalize_ddev_stamp
            printf 'STAMP=%s\n' "$NEW_DDEV_VERSION"
        ) 2>&1
    ) || true
    if printf '%s\n' "$_dv_out" | grep -qxF 'STAMP=1.2.3'; then
        pass "ddev stamp probe: old stamp survives when no binary answers"
    else
        fail "ddev stamp probe broken (out=$_dv_out)"
    fi
fi

suite_done
