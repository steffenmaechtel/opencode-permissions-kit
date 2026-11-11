#!/bin/sh
# Unit tests for sh/update-core.sh (issue #346, wave 2): the update
# run's phase functions, sourced from the lib the way update.sh sources
# them — the log.sh pin pattern (source the lib, call the function,
# stub the environment). The fragment harnesses over the lib's blocks
# stay in test-update-flags.sh; the root-run flows stay with e2e. This
# suite pins what only the DECOMPOSED shape can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every phase function + moved helper is defined by sourcing
#   - the pairing guard (#413, #452): real lib passes, truncated lib dies
#     loud, and both completeness riders (every phase the entry calls
#     AND every function the lib defines — comment-stripped,
#     boundary-anchored)
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
update_ensure_backup_dir
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
    pass "all 27 phase/helper functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 3. update.sh resolves the lib checkout-first, loud when missing --------------
# Presence-level pin (the resolver mirrors status.sh's status-core
# resolution, wave 1): the sequencer must not run when the lib is gone.
# Comment-strip on every positive conjunct (conventions.md
# "Source-counting pins", the #451 a Q3 shape): a commented-out
# resolver block must not satisfy the pin.
if live_src "$UPDATE" | grep -qF 'UPDATE_CORE="$SCRIPT_DIR/../sh/update-core.sh"' &&
    live_src "$UPDATE" |
    grep -qF '[ -f "$UPDATE_CORE" ] || UPDATE_CORE="$LIBDIR/sh/update-core.sh"' &&
    live_src "$UPDATE" | grep -qF '. "$UPDATE_CORE"'; then
    pass "update.sh sources update-core.sh checkout-first"
else
    fail "update.sh must resolve update-core.sh checkout-first (entry + \$LIBDIR fallback + sourcing)"
fi
if live_src "$UPDATE" | grep -qF 'error: update-core.sh not found'; then
    pass "update.sh errors loud on a missing lib (no silent phase drops)"
else
    fail "update.sh must error loud on a missing lib"
fi
check "update.sh sequences the phases in run order" \
    sh -c '_tail=$(sed -n "/# --- phases, in run order/,\$p" "$1")
        _l1=$(printf "%s\n" "$_tail" | grep -nF "    update_redeploy_library" | head -1 | cut -d: -f1)
        _l2=$(printf "%s\n" "$_tail" | grep -nF "update_binary_resecure" | head -1 | cut -d: -f1)
        _l3=$(printf "%s\n" "$_tail" | grep -nF "    update_finalize_tui_files" | head -1 | cut -d: -f1)
        [ -n "$_l1" ] && [ -n "$_l2" ] && [ -n "$_l3" ] && [ "$_l1" -lt "$_l2" ] && [ "$_l2" -lt "$_l3" ]' _ "$UPDATE"

# --- 4. library re-deploy section: executes from the lib -------------------------
_lib_run() {
    (
        FILES_ROOT="$WORK/froot"
        LIBDIR="$WORK/ldir"
        UPD_BACKUP_ROOT="$WORK/updbackups"
        log() { echo "log: $*"; }
        ui_section() { echo "section: $*"; }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        ui_warn() { echo "warn: $*"; }
        lib_deploy() { echo "LIB_DEPLOY: $*"; }
        sudo() { echo "SUDO: $*"; }
        . "$LIB"
        update_redeploy_library
    ) 2>&1
}
mkdir -p "$WORK/ldir" # the pre-update tree the B5 backup copies
printf 'old-lib-marker\n' >"$WORK/ldir/marker.txt"
_out=$(_lib_run || true)
if printf '%s\n' "$_out" | grep -qF "LIB_DEPLOY: $WORK/froot $WORK/ldir" &&
    printf '%s\n' "$_out" | grep -qF 'section: Re-deploying library files' &&
    printf '%s\n' "$_out" | grep -qF "success: library re-deployed: $WORK/ldir" &&
    printf '%s\n' "$_out" | grep -qF 'log: library re-deployed: '; then
    pass "library section: deploys via the manifest from FILES_ROOT"
else
    fail "library section broken (out=$_out)"
fi
# #376 B5: the deploy is preceded by a tree-level backup into the
# durable update backup dir (sandbox: UPD_BACKUP_ROOT points the root
# into scratch) — the marker file proves the copy is of the PRE-update
# tree.
_ulb_dir=$(find "$WORK/updbackups" -maxdepth 1 -name 'update-*' -type d 2>/dev/null | head -1)
if [ -n "$_ulb_dir" ] && [ -f "$_ulb_dir/lib/marker.txt" ]; then
    pass "library section: pre-update tree backed up before lib_deploy (#376 B5)"
else
    fail "library section: no pre-update lib backup under the update backup dir (#376 B5)"
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

# --- 16. pairing guard (#413): a version-skewed entry/lib pairing dies loud ----------
# The resolver (section 3) dies loud on a missing FILE; the guard closes
# the missing-FUNCTION twin — a core missing one renamed/newly-added
# function would abort the bare calls (cryptic rc 127 at best, set -e
# mid-update AFTER earlier phases ran; fail-soft silent skips are the
# uninstall shape). extract_func pulls the guard from the ENTRY; both
# directions run in fresh children: the real lib defines every function
# (rc 0), a truncated lib defining NOTHING fails on the FIRST name with
# the diagnosis line. The guard pins EVERY function the run needs,
# phases AND helpers (#452 — a helper-level skew aborts mid-update
# after partial work). The completeness riders derive the entry's own
# call list and the lib's own definitions and require every name inside
# the guard body — a function added to either side without the guard
# list cannot pass silently. Both riders grep a comment-stripped copy
# of the guard source (#452, conventions.md "Source-counting pins" over
# extracted blocks) and match with BOUNDARY-ANCHORED EREs (plain -qF
# would find section names as substrings of helper names in the list
# and a dropped name would false-pass).
_pg_src="$(extract_func "$UPDATE" update_pairing_guard)"
_pg_src_s="$(printf '%s\n' "$_pg_src" | sed 's/^[[:space:]]*#.*$//')"
_pg_full=$(sh -c 'eval "$1"; . "$2"; update_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; update_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every function defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "function 'update_redeploy_library' missing from update-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud naming the first missing function (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
# Comment-strip rider (conventions.md "Source-counting pins", the #451
# a Q3 shape): a commented-out guard wiring line must not satisfy the
# pin.
if live_src "$UPDATE" | grep -qF 'update_pairing_guard || exit 1'; then
    pass "update.sh wires the guard right after the resolver (#413)"
else
    fail "update.sh must call the guard after sourcing update-core.sh (#413)"
fi
_pg_missing=""
# A2 (#460): the digit class the #457 standard names -- no digit-bearing
# entry call exists today (latent), but a future update_2x_sync call
# would silently escape the extraction without it.
_pg_entfns="$(grep -oE '^[[:space:]]*update_[a-z0-9_]+[[:space:]]*$' "$UPDATE" |
    awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' | sort -u)"
# emptiness probe (#457, the #455 a C2 contract -- the sibling-note
# sweep): an empty extraction would run the loop zero times and the
# rider would pass vacuously.
[ -n "$_pg_entfns" ] || _pg_missing="(entry call extraction empty)"
for _fn in $_pg_entfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every phase the entry calls (#413)"
else
    fail "phases called by update.sh but absent from the guard:$_pg_missing (#413)"
fi
# completeness rider (helper direction, #452): every function the LIB
# defines must sit in the guard's list too — a helper missing from the
# list is the helper-skew hole the guard-list fix closes. Same boundary
# anchor, same stripped source. The extraction carries an emptiness
# probe (#455 a C2): an empty list would run the loop zero times and
# pass vacuously, and the harness contract puts that probe on the
# caller.
_pg_hmissing=""
_pg_libfns="$(grep -oE '^[A-Za-z_][A-Za-z_0-9]*\(\) \{' "$LIB" | sed 's/() {//' | sort -u)"
[ -n "$_pg_libfns" ] || _pg_hmissing="(lib function extraction empty)"
for _fn in $_pg_libfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_hmissing="$_pg_hmissing $_fn"
done
if [ -z "$_pg_hmissing" ]; then
    pass "pairing guard list covers every function the lib defines (#452)"
else
    fail "functions defined by update-core.sh but absent from the guard:$_pg_hmissing (#452, #455 a C2)"
fi

# Cross-lib stub rider (#456), strongest form like test-install-core's:
# every function defined by ANY sh/ lib (ui.sh exempt — its surface is
# update_ui_pairing_guard's, own rider in test-ui.sh) and CALLED by the
# entry or the core must be DEFINED in update.sh OR update-core.sh.
# update-core self-sources three libs (wsl-browser-bridge,
# ddev-handover, fs-baseline) with its own || stub arms — those count;
# xdg_shim_needed_for was the unswept example fixed with this wave
# (update-core asks deploy-lib, only lib_deploy was stubbed, and only
# for the missing-FILE case). Comment-stripped both sides. The lib
# list is what THIS RUN sources: the entry's resolver loops plus the
# three libs update-core self-sources with its own stub arms
# (wsl-browser-bridge, ddev-handover, fs-baseline) — not the whole
# sh/ glob, whose wrapper-side scripts define shell hooks (ddev(),
# note()) that are not update's callable surface. Token extraction
# stays line-separated: tr -d '[:space:]()' concatenates every
# definition into one token and the loop goes vacuous (the #456
# sabotage cycle found exactly that on the install twin, L4).
_xl_missing=""
UPDATE_ENTRY="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
_xl_combined="$(
    live_src "$UPDATE_ENTRY"
    live_src "$LIB"
)"
[ -n "$_xl_combined" ] || _xl_missing="(stripped entry+core extraction empty)"
for _xl_rel in opencode-permissions-kit-lib/sh/staged-write.sh \
    opencode-permissions-kit-lib/sh/sudoers-deploy.sh \
    opencode-permissions-kit-lib/sh/secure-binary.sh \
    opencode-permissions-kit-lib/sh/deploy-lib.sh \
    opencode-permissions-kit-lib/sh/tui-plugin.sh \
    opencode-permissions-kit-lib/sh/git-check.sh \
    opencode-permissions-kit-lib/sh/log.sh \
    opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh \
    opencode-permissions-kit-lib/sh/ddev-handover.sh \
    opencode-permissions-kit-lib/sh/fs-baseline.sh; do
    _xl_lib="$SCRIPT_DIR/../../files/$_xl_rel"
    [ -f "$_xl_lib" ] || {
        _xl_missing="$_xl_missing (missing lib $_xl_rel)"
        continue
    }
    for _xl_fn in $(grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$_xl_lib" | tr -d '()'); do
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[^a-zA-Z0-9_])${_xl_fn}([^a-zA-Z0-9_(]|$)" ||
            continue
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[|;[:space:]])${_xl_fn}\(\)" ||
            _xl_missing="$_xl_missing $_xl_fn"
    done
done
if [ -z "$_xl_missing" ]; then
    pass "every lib function entry-or-core calls is stubbed in update.sh/update-core.sh (#456)"
else
    fail "lib functions called but stubbed nowhere in update.sh/update-core.sh:$_xl_missing (#456)"
fi

# LOWS-1 (#371 A5, class sweep from install.sh): the pre-upgrade binary
# backup copy names its cause on failure — the bare call aborted the
# whole update cause-less under set -e (the helper prints nothing), and
# a swallowed failure would let the rc-2 restore path promise a restore
# point that does not exist.
if live_src "$LIB" |
    grep -qF 'error: pre-upgrade backup of $SYSTEM_BIN failed' &&
    live_src "$LIB" |
    grep -A2 -F 'error: pre-upgrade backup of $SYSTEM_BIN failed' |
        grep -qF 'return 1'; then
    pass "pre-upgrade binary backup failure aborts cause-loud (#371 A5 sweep)"
else
    fail "pre-upgrade binary backup still bare or cause-less (#371 A5 sweep)"
fi

# --- 17. update_ensure_backup_dir (#376 B5/B3'): durable root, lazy, fail-loud ----
# Behavioral: the helper creates the run's backup dir under
# UPD_BACKUP_ROOT (sandbox override of /var/backups — the DDEV_MIG_
# BACKUP_ROOT pattern), is idempotent within a run, and fails loud
# (rc 1, no dir) when the root cannot be created.
_UBW="$(work_new)"
_ubd_out=$(
    UPD_BACKUP_ROOT="$_UBW/root" sh -c '
        log() { echo "log: $*"; }
        . "$1"
        update_ensure_backup_dir && echo "rc1=0 dir=$UPD_BACKUP_DIR"
        update_ensure_backup_dir && echo "rc2=0 dir=$UPD_BACKUP_DIR"
    ' _ "$LIB" 2>&1
)
_ubd_dir=$(printf '%s\n' "$_ubd_out" | sed -n 's/^rc1=0 dir=//p' | head -1)
if [ -n "$_ubd_dir" ] && [ -d "$_ubd_dir" ] &&
    [ "$(printf '%s\n' "$_ubd_out" | grep -c 'log: update backup dir created')" -eq 1 ] &&
    printf '%s\n' "$_ubd_out" | grep -qF "rc2=0 dir=$_ubd_dir" &&
    [ "$(stat -c '%a' "$_ubd_dir")" = 700 ]; then
    pass "backup dir: created once per run, mode 700, path echoed (#376 B5)"
else
    fail "backup dir helper broken (out=$_ubd_out) (#376 B5)"
fi
mkdir -p "$_UBW/leafroot"  # EXISTS (mkdir -p passes) but unwritable: the
chmod 500 "$_UBW/leafroot" # failure lands on the LEAF mkdir — the
# pr-00429 a B3 arm (a pre-root failure never reaches the flag and
# cannot discriminate; verified both ways during sabotage)
_ubd_fail=$(UPD_BACKUP_ROOT="$_UBW/leafroot" sh -c '
        log() { :; }
        . "$1"
        if update_ensure_backup_dir; then echo "BAD: rc 0"; else echo "rc1=$?"; fi
        if update_ensure_backup_dir; then echo "BAD: second rc 0"; else echo "rc2=$?"; fi
    ' _ "$LIB" 2>&1)
chmod 700 "$_UBW/leafroot"
case "$_ubd_fail" in
    rc1=1*rc2=1*)
        pass "backup dir: leaf failure fails loud rc 1, BOTH calls — the idempotence flag is not set on failure (pr-00429 a B3)"
        ;;
    *)
        fail "backup dir must refuse rc 1 on leaf failure, first AND second call (got $_ubd_fail) (pr-00429 a B3)"
        ;;
esac

# --- 18. library rollback (#376 B5): failed lib_deploy restores the tree -----------
# lib_deploy stubbed to rc 1 after half-planting a new file (the mixed
# old/new state of the finding): the section must move the mixed tree
# aside, restore the pre-update backup, and die — with real cp/mv (no
# sudo in the rollback legs; scratch paths only).
mkdir -p "$WORK/ldir2" # the pre-update tree the rollback restores
printf 'old-lib-2\n' >"$WORK/ldir2/marker-old.txt"
_lrb_out=$(
    UPD_BACKUP_ROOT="$WORK/updbackups2" sh -c '
        FILES_ROOT="$1/froot"
        LIBDIR="$1/ldir2"
        log() { echo "log: $*"; }
        ui_section() { :; }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        ui_warn() { echo "warn: $*"; }
        die() { echo "die: $*"; exit 1; }
        lib_deploy() { echo "new-lib" >"$LIBDIR/planted-new.txt"; return 1; }
        sudo() { echo "SUDO: $*"; }
        . "$2"
        update_redeploy_library
    ' _ "$WORK" "$LIB" 2>&1
) || true
if printf '%s\n' "$_lrb_out" | grep -qF 'warn: library re-deploy FAILED — previous library tree restored' &&
    printf '%s\n' "$_lrb_out" | grep -qF 'die: library re-deploy failed — update aborted' &&
    [ -f "$WORK/ldir2/marker-old.txt" ] &&
    [ ! -f "$WORK/ldir2/planted-new.txt" ] &&
    [ -n "$(find "$WORK/updbackups2" -maxdepth 2 -name 'lib-failed.*' -type d 2>/dev/null)" ] &&
    [ -f "$(find "$WORK/updbackups2" -maxdepth 2 -name 'lib-failed.*' -type d 2>/dev/null | head -1)/planted-new.txt" ]; then
    pass "failed lib_deploy: mixed tree moved aside, pre-update tree restored (#376 B5)"
else
    fail "failed lib_deploy must restore the pre-update tree (out=$_lrb_out) (#376 B5)"
fi
# The aborted run leaves the fresh backup dir with BOTH trees for
# inspection — the recovery material survives the abort (the old
# volatile-mktemp loss class is what #376 B3' closes).
_lrb_bdir=$(find "$WORK/updbackups2" -maxdepth 1 -name 'update-*' -type d 2>/dev/null | head -1)
if [ -f "$_lrb_bdir/lib/marker-old.txt" ]; then
    pass "failed deploy keeps the pre-update copy as recovery material (#376 B5)"
else
    fail "recovery copy missing after failed deploy (#376 B5)"
fi

# --- 19. binary backup base is durable (#376 B3') ---------------------------------
# Static + executed hybrid: no volatile mktemp may remain in the
# upgrade path, the backup lands in $UPD_BACKUP_DIR/bin, and the
# no-backup-dir arm skips the upgrade loudly instead of proceeding
# unprotected (driven through update_binary_upgrade with the fetch
# already resolved: SRC set, TMP/_BIN_TMP empty, install_binary
# stubbed — the helper under test is the backup-base selection).
_b3p_out=$(UPD_BACKUP_ROOT="/nonexistent-root-$$" sh -c '
        SRC="/dev/null"
        TMP=""
        _BIN_TMP=""
        UPD_BACKUP_ROOT="$UPD_BACKUP_ROOT"
        export UPD_BACKUP_ROOT
        log() { echo "log: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_detail() { :; }
        ui_success() { :; }
        die() { echo "die: $*"; exit 1; }
        copy_binary_atomic() { echo "CBA: $*"; return 0; }
        secure_binary() { return 0; }
        current_opencode_major() { echo 1; }
        install_binary() { echo "INSTALL_BIN"; return 0; }
        rm() { echo "RM: $*"; command rm "$@"; }
        . "$1"
        # Post-source stubs (maintainer steering 2026-11-09, the 0.0.46a
        # F2 class): update-core.sh DEFINES its own resolver, fetch,
        # major probe, installer and TUI registration — pre-source stubs
        # for those five are dead (sourcing re-defines them; the former
        # pre-source sync_tui_registration stub was removed for exactly
        # that reason, #439 b B2), so this pin ran the REAL network path
        # on every green run (api.github.com resolve + release-asset
        # download), reddening whenever the shared host-IP budget was
        # exhausted. The helper under test is the backup-base selection;
        # resolution/fetch behavior is pinned hermetically in
        # test-update-flags.sh (curl stub). Stubs must sit AFTER sourcing.
        ui_section() { :; }
        current_opencode_major() { echo 1; }
        resolve_latest_opencode_version() { echo "1.9.9"; }
        fetch_opencode_version() { echo /dev/null; }
        install_binary() { echo "INSTALL_BIN"; return 0; }
        update_binary_upgrade
    ' _ "$LIB" 2>&1)
if printf '%s\n' "$_b3p_out" | grep -qF 'warn: no durable backup dir available — opencode binary upgrade skipped (nothing changed)' &&
    ! printf '%s\n' "$_b3p_out" | grep -qF 'INSTALL_BIN' &&
    ! grep -q 'opencode-upgrade-backup' "$LIB"; then
    pass "binary upgrade: no backup dir means no upgrade, volatile mktemp gone (#376 B3')"
else
    fail "binary upgrade backup base regression (out=$_b3p_out) (#376 B3)"
fi
# Comment-strip rider (conventions.md "Source-counting pins",
# #458): the literal must count only in live lines -- a commented-out
# backup line must not satisfy the pin. check_live carries the rider
# (#460): the plain check helper takes argv, not a pipe, but check_live
# is the single-file pipe shape.
check_live "binary upgrade backs up into the durable update dir (#377-less, #376 B3')" \
    "$LIB" -qF 'BACKUP_DIR="$UPD_BACKUP_DIR/bin"'
# B4 class sweep: the upgrade flow's OWN mktemp (the candidate download
# staging dir) gets the named-cause guard — set -e would abort the whole
# update on the raw error; the guard degrades to the best-effort skip
# (binary untouched, warn + log). Driven with a pinned --version and an
# uncreatable TMPDIR (uid-independent failure injection).
_b4g_out=$(UPGRADE_VERSION=9.9.9 TMPDIR="/nonexistent-b4g-$$" sh -c '
        ui_section() { :; }
        ui_warn() { echo "warn: $*"; }
        ui_detail() { :; }
        ui_success() { :; }
        log() { echo "log: $*"; }
        install_binary() { echo "BAD: install_binary ran"; return 0; }
        . "$1"
        update_binary_upgrade
    ' _ "$LIB" 2>&1)
if printf '%s\n' "$_b4g_out" | grep -qF 'warn: mktemp failed (is $TMPDIR writable?) — opencode binary upgrade skipped, binary left untouched' &&
    printf '%s\n' "$_b4g_out" | grep -qF 'log: opencode binary upgrade skipped: mktemp failed' &&
    ! printf '%s\n' "$_b4g_out" | grep -qF 'BAD: install_binary ran'; then
    pass "upgrade-flow mktemp failure degrades to the loud skip (#376 B4 sweep)"
else
    fail "upgrade-flow mktemp guard broken (out=$_b4g_out) (#376 B4 sweep)"
fi

# --- 20. shell-hook rc backups (#425): copy before edit, degrade loud --------------
# The install-side rc invariant (PR #424) holds update-side: every rc
# file touched by the hook loop gets a recovery copy in the update
# backup dir FIRST; a failed copy degrades loudly and the edit still
# runs (the #424 a S2 doctrine — the hooks are load-bearing heals).
_RCB="$(work_new)"
mkdir -p "$_RCB/home"
printf 'export PATH="/usr/local/bin:$PATH"\n' >"$_RCB/home/.bashrc"
# NOTE: the env assignments ride the sh -c PREFIX line — split lines
# would leave them unexported in this shell and the child would see
# only UPD_BACKUP_ROOT (the silent no-op arm of the function).
_rcb_out=$(
    DEFAULT_USER=rcdev DEFAULT_HOME="$_RCB/home" OPENCODE_USER=oc \
        UPD_BACKUP_ROOT="$_RCB/backups" sh -c '
        log() { echo "log: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_detail() { :; }
        sudo() { "$@"; }
        . "$1"
        update_redeploy_shell_hooks
    ' _ "$LIB" 2>&1
)
_rcb_bdir=$(find "$_RCB/backups" -maxdepth 1 -name 'update-*' -type d 2>/dev/null | head -1)
if [ -f "$_rcb_bdir/rc-.bashrc" ] &&
    [ "$(cat "$_rcb_bdir/rc-.bashrc")" = 'export PATH="/usr/local/bin:$PATH"' ] &&
    grep -qF 'opencode-permissions-kit/sh/shell-warn.sh' "$_RCB/home/.bashrc"; then
    pass "shell hooks: rc file backed up before the edit (#425)"
else
    fail "shell hooks must back up the rc file before editing it (out=$_rcb_out) (#425)"
fi
# Degradation arm: the backup root cannot be created — the warn fires
# and the hook is STILL appended (no recovery copy, never a silent or
# missing hook).
_RCB2="$(work_new)"
mkdir -p "$_RCB2/home" "$_RCB2/full"
chmod 500 "$_RCB2/full"
printf 'x\n' >"$_RCB2/home/.profile"
_rcb2_out=$(
    DEFAULT_USER=rcdev DEFAULT_HOME="$_RCB2/home" OPENCODE_USER=oc \
        UPD_BACKUP_ROOT="$_RCB2/full/nodir" sh -c '
        log() { echo "log: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_detail() { :; }
        sudo() { "$@"; }
        . "$1"
        update_redeploy_shell_hooks
    ' _ "$LIB" 2>&1
)
chmod 700 "$_RCB2/full"
if printf '%s\n' "$_rcb2_out" | grep -qF 'warn: could not back up' &&
    printf '%s\n' "$_rcb2_out" | grep -qF 'log: rc backup FAILED' &&
    grep -qF 'opencode-permissions-kit/sh/shell-warn.sh' "$_RCB2/home/.profile"; then
    pass "shell hooks: failed backup degrades loud, hook still applied (#425)"
else
    fail "failed rc backup must degrade loudly without skipping the hook (out=$_rcb2_out) (#425)"
fi

# --- timeout two-class probe (#248) ----------------------------------------------
# `command -v timeout` proves findability, not function: a broken-but-
# findable timeout must degrade to the unguarded arm, not fail the
# probe. Controlled PATH: scratch bin with a broken timeout shadows the
# real one; the probe caches its verdict per process (fresh sh each).
_TO="$(work_new)"
mkdir -p "$_TO/bin"
printf '#!/bin/sh\nexit 1\n' >"$_TO/bin/timeout"
chmod +x "$_TO/bin/timeout"
printf '#!/bin/sh\necho "opencode v2.2.6"\n' >"$_TO/bin/fake-oc"
chmod +x "$_TO/bin/fake-oc"
if PATH="$_TO/bin:/usr/bin:/bin" sh -c '. "$1"
    if _opk_timeout_ok; then echo gate-ok; else echo gate-fallback; fi
    SYSTEM_BIN="$2"
    printf "version=%s\n" "$(opencode_version_line)"
' _ "$LIB" "$_TO/bin/fake-oc" >"$_TO/out" 2>&1; then
    :
fi
if grep -q '^gate-fallback$' "$_TO/out" && grep -q '^version=opencode v2.2.6$' "$_TO/out"; then
    pass "timeout probe: broken timeout degrades to fallback arm, probe still answers (#248)"
else
    fail "broken timeout must not fail the bounded probe (got: $(cat "$_TO/out")) (#248)"
fi
# Healthy timeout present: the gate takes the bounded arm (the probe
# runs in the suite's own PATH, which check-host verified).
if sh -c '. "$1" && _opk_timeout_ok' _ "$LIB"; then
    pass "timeout probe: healthy timeout passes the gate (#248)"
else
    fail "healthy timeout must pass the gate (#248)"
fi

# --- resolve_latest_opencode_version under hostile PYTHONHOME (#249) --------------
# The 2.x arm pipes the packument through `python3 -I`: a poisoned
# PYTHONHOME must not break the resolution. curl is faked on PATH
# (hermetic — no network); detect_target runs for real.
_RES="$(work_new)"
mkdir -p "$_RES/bin"
cat >"$_RES/bin/curl" <<'EOF'
#!/bin/sh
# fake registry packument for @opencode/cli-<any-target>
printf '{"dist-tags":{"latest":"2.9.9"}}\n'
EOF
chmod +x "$_RES/bin/curl"
_res_rc=0
_res_out=$(PATH="$_RES/bin:/usr/bin:/bin" PYTHONHOME="$_RES/nonexistent-py-home" \
    sh -c '. "$1"; resolve_latest_opencode_version 2' _ "$LIB" 2>"$_RES/err") || _res_rc=$?
if [ "$_res_out" = "2.9.9" ]; then
    pass "resolve: hostile PYTHONHOME cannot break the 2.x resolution (-I, #249)"
else
    fail "resolve must ignore PYTHONHOME under -I (rc=$_res_rc got [$_res_out] err $(head -2 "$_RES/err" 2>/dev/null)) (#249)"
fi
# Discriminator: the same hostile env DOES break a bare python3 -c (the
# control arm proves the env is genuinely hostile — without it the pin
# above would pass vacuously on a PYTHONHOME-ignoring build).
if PYTHONHOME="$_RES/nonexistent-py-home" python3 -c 'import json' 2>/dev/null; then
    fail "control arm: PYTHONHOME hostility is not effective on this python (vacuous #249 pin)"
else
    pass "control arm: bare python3 breaks under the hostile PYTHONHOME (#249)"
fi
# Sweep floor: update-core's own site runs isolated (floor — the
# tree-wide absence pin below is the ceiling).
_pc=$(live_src "$LIB" | grep -c 'python3 -I' || true)
if [ "${_pc:-0}" -ge 1 ]; then
    pass "sweep floor: update-core.sh python3 call runs -I ($_pc site(s), #249)"
else
    fail "update-core.sh must invoke python3 -I at the resolve site (#249)"
fi

# --- #249 absence sweep (review a C5): NO bare python3 execution anywhere ----------
# The per-file count pins are floors — a NEW bare site would stay green.
# This is the ceiling: every python3 INVOCATION shape (a flag, "-",
# quoted variable, path) in every shipped file that mentions python3
# must carry -I. Message strings name python3 in prose (a word follows,
# not a flag/quote/dollar/slash) and match no arm of the regex.
# Dual mentions on one line occur only as guard+exec pairs or prose
# (the tui-plugin.sh:82 shape): the -I exclusion drops those lines when
# the exec is isolated — a BARE exec behind a guard keeps the line
# (no -I anywhere) and stays caught. Two known blind spots (review b
# D4, latent — zero hits today): a single line carrying BOTH a bare
# and an -I invocation vanishes under the line-level exclusion, and a
# backslash-continued `python3 \` opener matches no arm; the per-file
# floor pins bound the residual.
_bare_py=""
while IFS= read -r _pyf; do
    _hits=$(live_src "$_pyf" |
        grep -nE 'python3 (-[A-Za-z]|-$|"|/|\$)' | grep -v 'python3 -I' || true)
    [ -z "$_hits" ] || _bare_py="$_bare_py
$_pyf: $_hits"
done <<EOF
$(grep -rl 'python3' "$SCRIPT_DIR/../../files" | grep -v '\.py$' | sort)
EOF
if [ -z "$_bare_py" ]; then
    pass "sweep ceiling: no bare python3 execution site in files/ (#249, review a C5)"
else
    fail "bare python3 execution sites remain (review a C5):$_bare_py"
fi

# --- #257: the xdg shim section gates on the deployed version ---------------------
# Execution against /usr/local/bin literals is not hermetic (sandbox
# policy) — the gate LOGIC is execution-pinned in test-deploy-lib.sh,
# the run ORDER in test-update-flags.sh, the deploy behavior in e2e.
# Here: the section consults the gate on BOTH sides (withhold/remove)
# and names the cause in each arm.
if live_src "$LIB" | grep -qF 'if ! xdg_shim_needed_for "${_xds_maj:-}" "$_xds_trip"; then' &&
    live_src "$LIB" | grep -qF 'needs no fallback (#257)' &&
    live_src "$LIB" | grep -qF 'opens without one (>= $XDG_SHIM_FIX_VERSION, #257)'; then
    pass "xdg shim section: version gate + named causes wired (#257)"
else
    fail "the shim section must gate on xdg_shim_needed_for and name its causes (#257)"
fi
# The probe basis is the post-swap binary: the section reads
# opencode_version_line (SYSTEM_BIN), never a stale install.conf stamp.
if live_src "$LIB" | grep -qF '_xds_ver=$(opencode_version_line)'; then
    pass "xdg shim section probes the deployed binary for its version basis (#257)"
else
    fail "the shim gate must probe the deployed binary, not a stamp (#257)"
fi

suite_done
