# shellcheck shell=sh
# opencode permissions kit -- install-core.sh
#
# The install run's phase logic (issue #346, wave 3): the three phases
# of install.sh as functions — pure code movement, output byte-identical
# except the four helpers extracted for unit pinning (see below).
# Sourced (never executed) by install.sh via kit_source from $SCRIPT_DIR
# — the checkout, or the streamed fetch tree (install.sh re-points
# SCRIPT_DIR at $_FK_DIR before the first kit_source; deliberately NO
# deployed-$LIBDIR fallback, install.sh never runs from the installed
# tree — updates go through update.sh). POSIX sh, no top-level side
# effects (definitions and comments only). The functions run in the
# CALLER's shell under its `set -eu`: they read the globals install.sh
# sets before the phase calls (KIT_BRANCH, VERSION, LIBDIR, SCRIPT_DIR,
# OPENCODE_USER, OPENCODE_GROUP, SKIP_PROMPTS, PREDEFINED_PROJECTS,
# PROJECTS_ARG_SPACED, SECURE_GIT_CONFIG, CONTAINER_BACKEND_OPT,
# SKIP_DDEV_MIGRATION, MIGRATE_AGENTS_OPT, DDEV_DEV_OWNED,
# DDEV_SETTINGS_GIVEN,
# GIT_FLAG_GIVEN, OPENCHAMBER_POLICY_OPT/GIVEN, FORCE_UNSUPPORTED_DISTRO
# via _distro_gate) and call the entry's
# helpers (banner, confirm, _yes_no_backup_menu, _distro_gate,
# _py3_health_probe, _root_user_gate, _tmp_track) plus the shared libs
# install.sh sources first (ui_*, log, kit_source'd sh/ helpers:
# ddev_handover_*, ddev_migrate_*, fs_baseline_root, project_path_sane,
# git_check_report, staged_write, sudoers_deploy, secure_binary,
# copy_*_atomic, lib_deploy, agent_config_render, tui_plugin_sync_user,
# browser_bridge_*, agent_home_sane). Cross-phase state stays global by
# design: do_plan_phase resolves the run (DEFAULT_USER, DEV_HOME,
# PROJECT_TILDE_HOME, MODE, BACKUP_DIR/_BK_FAIL, PROJECTS_ROOTS,
# OPENCODE_GROUP, CONTAINER_BACKEND, SECURE_GIT_CONFIG,
# OPENCHAMBER_POLICY, DDEV_BIN_DEV); do_ddev_phase reads those and sets
# DD_MIG_DUMP_DIR; do_deploy_phase consumes all of them — install.sh's
# closing summary reads VERSION/KIT_BRANCH/CONTAINER_BACKEND/
# PROJECTS_ROOTS/DD_MIG_DUMP_DIR/SECURE_GIT_CONFIG/OPENCHAMBER_POLICY/
# BACKUP_DIR/_BK_FAIL/DEV_HOME after the last phase.
#
# The four small helpers above their phases (install_reuse_home_guard,
# install_reuse_group_guard, install_project_roots_select,
# install_agents_form_normalize) are NOT new logic: they are the exact
# blocks tests/unit/test-install-args.sh used to extract by indentation
# anchors (#346 wave 3 closes the #396 payoff — the pins source this lib
# and call them, test-install-core.sh); their bodies keep the block
# content with 4 spaces less indent, nothing else moved.

# --- plan-phase helpers (extracted for unit pinning, #346 wave 3) ---------------

# reuse-guard-home (0.0.44a V15, maintainer decision: fail-loud):
# every agent-side provision writes /home/<agent>, and the runtime
# (sudo env_reset, the wrapper) reads the user's REAL passwd home —
# a deviating home would park config, TUI registration and CA in a
# shadow home nobody reads: protections silently absent under a
# success banner. Rejected with remediation instead.
install_reuse_home_guard() {
    _oc_home="$(getent passwd "$OPENCODE_USER" 2>/dev/null | cut -d: -f6 || true)"
    if [ "$_oc_home" != "/home/$OPENCODE_USER" ]; then
        ui_error "user '$OPENCODE_USER' exists with home '$_oc_home',""\
 but the kit provisions /home/$OPENCODE_USER — the runtime reads the passwd home,"
        ui_error "so config, TUI registration and the mkcert CA would land in a shadow home."
        ui_error "Move the user's home or remove the user, then re-run."
        log "reuse refused: home deviation ($OPENCODE_USER -> $_oc_home)"
        exit 1
    fi
}

# reuse-guard-group (0.0.44a V15): the primary group becomes the
# sharing group — the group baseline widens onto it. A foreign
# primary group widens the kit onto users it was never meant for.
install_reuse_group_guard() {
    _oc_pgrp="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
    if [ "$_oc_pgrp" != "$OPENCODE_USER" ]; then
        ui_error "user '$OPENCODE_USER' exists with primary group '$_oc_pgrp', but the kit's""\
 sharing group IS the user's own primary usergroup (useradd -m default)"
        ui_error "— a foreign primary group would widen the group baseline onto it."
        ui_error "Point the user's primary group at a group of its own name, or remove the user, then re-run."
        log "reuse refused: primary group deviation ($OPENCODE_USER -> $_oc_pgrp)"
        exit 1
    fi
}

# Step-2 interactive selection (ui_section .. done), extracted whole:
# reads PREDEFINED_PROJECTS-armed globals (options is built inside), sets
# PROJECTS_ROOTS; the two EOF-bail guards (0.0.44a V6 / 0.0.44b W6) live
# in its loops.
install_project_roots_select() {
    ui_section "Project roots"
    echo "Select project directories (space-separated numbers), or 'c' for custom, 's' to skip."

    num=1
    options=""
    for dir in /var/www/vhosts /var/www/html /var/www; do
        if [ -d "$dir" ]; then
            echo "  [$num] $dir"
            options="$options $dir"
            num=$((num + 1))
        fi
    done
    if [ -z "$options" ]; then
        ui_warn "no standard directories found."
    fi
    echo "  [c] Custom path(s)"
    echo "  [s] Skip (no project baseline, only user + wrapper)"
    # Re-ask until the selection resolves: an out-of-range number or stray
    # input used to yield an empty root list and silently continue (0.0.38 C11).
    # Empty reads count toward a bail-out (0.0.44a V6): EOF without a
    # terminal (checkout runs without --yes from cron/CI/ssh -T) used to
    # spin this loop forever — five consecutive empties abort loudly.
    _sel_done=""
    _sel_empty=0
    selection=""
    while [ -z "$_sel_done" ]; do
        printf "  > "
        _ui_read selection
        if [ -z "$selection" ]; then
            _sel_empty=$((_sel_empty + 1))
            if [ "$_sel_empty" -ge 5 ]; then
                ui_error "no usable input after 5 empty reads (EOF without a terminal?) — aborting."
                exit 1
            fi
            continue
        fi
        _sel_empty=0

        case "$selection" in
            [Cc]*)
                echo "Enter paths (space-separated):"
                _custom=""
                custom=""
                _custom_empty=0
                while [ -z "$_custom" ]; do
                    printf "  > "
                    _ui_read custom
                    # custom-path-bail (0.0.44b W6): the same EOF
                    # guard as the outer loop — without it a dead
                    # stdin spun this sub-loop forever.
                    if [ -z "$custom" ]; then
                        _custom_empty=$((_custom_empty + 1))
                        if [ "$_custom_empty" -ge 5 ]; then
                            ui_error "no usable input after 5 empty reads (EOF without a terminal?) — aborting."
                            exit 1
                        fi
                        continue
                    fi
                    _custom_empty=0
                    # Glob gate (issue #372 A2, the --projects sibling's
                    # 0.0.42f S2 rule): the for-loop below expands $custom
                    # UNQUOTED — a word with glob characters that matches
                    # files silently substitutes them for what was typed.
                    # Reject the raw input before that loop runs.
                    case "$custom" in
                        *[\*\?\[]*)
                            ui_error "paths must not contain glob characters (* ? [): $custom"
                            continue
                            ;;
                    esac
                    _custom=""
                    _bad=""
                    for p in $custom; do
                        if project_path_sane "$p"; then
                            _custom="$_custom $_PP_NORM"
                        else
                            ui_error "'$p' is not a valid project root (system path, symlink, or malformed form) — rejected."
                            _bad=1
                        fi
                    done
                    [ -n "$_bad" ] && _custom=""
                done
                PROJECTS_ROOTS="$_custom"
                _sel_done=1
                ;;
            [Ss]*)
                PROJECTS_ROOTS=""
                echo "Skipping project baseline."
                _sel_done=1
                ;;
            *)
                PROJECTS_ROOTS=""
                idx=1
                for dir in $options; do
                    for s in $selection; do
                        [ "$s" = "$idx" ] && PROJECTS_ROOTS="$PROJECTS_ROOTS $dir"
                    done
                    idx=$((idx + 1))
                done
                if [ -n "$PROJECTS_ROOTS" ]; then
                    _sel_done=1
                else
                    ui_error "invalid selection '$selection' — pick numbers from the list, ""\
'c' for custom, or 's' to skip."
                fi
                ;;
        esac
    done
}

# === Phase 1: plan + provision (Start .. Step 3) ================================
# Everything from the first question to the provisioned backend: mode,
# backup, pre-flight, backend choice, inventory, standard questions,
# plan + confirm, Steps 1-3 (user + group, project roots, container
# backend). Moved verbatim from install.sh (#346 wave 3; the body was a
# verbatim wrap since issue #113): statement lines keep their exact
# indentation and bytes — the two reuse guards and the Step-2 selection
# block are the wrapped helpers above, called at their original sites.

do_plan_phase() {
    # === Start ===

    banner

    DEFAULT_USER="${SUDO_USER:-$(whoami)}"

    # The username is interpolated into sudoers (sed) and sourced from
    # install.conf — reject anything outside the conservative Unix name
    # charset (letters, digits, _, ., -) before it can corrupt either.
    case "$DEFAULT_USER" in
        '' | *[!A-Za-z0-9_.-]*)
            echo "error: Invalid user name '$DEFAULT_USER' (allowed: letters, digits, '_', '.', '-')" >&2
            exit 1
            ;;
    esac

    # Root-shell installs register root as the developer (issue #192) —
    # refuse them before the first prompt. Runs before the distro gate:
    # a root shell is a broken install no later choice can repair.
    _root_user_gate "$DEFAULT_USER"

    # ~ in project paths must expand to the DEFAULT user's home, not $HOME
    # (under sudo, $HOME is /root and "~/dev" would be rejected as a
    # "/root system path" with a confusing error). One implementation in
    # sh/path-sane.sh (issue #340): install.sh and config.sh shared this
    # block near-identically before.
    path_sane_tilde_home
    # Developer home for every developer-side provisioning path (0.0.44a
    # V14): ddev discovery, the .ddev registry check, binary candidates,
    # rc-file hooks, agents-migration sources, the deny-all config and the
    # TUI theme. getent, /home/<name> only as fallback — the same class
    # the 0.0.43a/b waves closed in the sibling files (F12/W1/W2); a
    # relocated home must not silently miss the protections.
    DEV_HOME="/home/$DEFAULT_USER"
    _opk_dh="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "$_opk_dh" ] && DEV_HOME="$_opk_dh"
    log "install started (version $VERSION, default user=$DEFAULT_USER)"

    # === Distro gate (fail fast, before any prompt) ============================
    # sed, not sourcing: os-release must not clobber the installer's
    # variables; tr strips both quote styles (both are spec-legal) and a
    # trailing CR (CRLF-edited file). || true on the reads: a missing
    # os-release is an exotic system that passes the gate as "unknown" —
    # under set -eu + pipefail sed's rc 2 would otherwise abort the
    # install silently with zero output (0.0.45a S1).
    _dg_id=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | head -1 | tr -d "\"'\r") || true
    _dg_ver=$(sed -n 's/^VERSION_ID=//p' /etc/os-release 2>/dev/null | head -1 | tr -d "\"'\r") || true
    _distro_gate "${_dg_id:-unknown}" "$_dg_ver"

    # === Install mode ===
    # Standard asks only the essential questions and takes recommended defaults
    # for everything else (same answers as --yes); Advanced keeps every granular
    # prompt of the install steps below.
    INTERACTIVE=true
    [ "$SKIP_PROMPTS" = true ] && INTERACTIVE=false
    MODE="standard"
    if [ "$INTERACTIVE" = true ]; then
        _mode=$(ui_menu "How do you want to install?" "1" \
            "1|Standard (recommended — few questions, safe defaults)" \
            "2|Advanced (control every step)" \
            "x|Abort")
        case "$_mode" in
            x)
                ui_info "Aborted."
                exit 0
                ;;
            2) MODE="advanced" ;;
        esac
    fi
    log "install mode: $MODE (interactive=$INTERACTIVE)"

    IS_WSL2=false
    grep -qi microsoft /proc/version 2>/dev/null && IS_WSL2=true
    if [ "$IS_WSL2" != true ]; then
        confirm "This does not appear to be WSL2. Continue anyway?" || exit 0
    fi

    # Backup. Durable location (#370 a I1): these are the ONLY copies of the
    # recovery material (sudoers, gitconfigs, prior binary/config) and must
    # survive a reboot — the old mktemp dir under /tmp died with it (tmpfs
    # wipe at boot, systemd-tmpfiles age-out). Root-owned /var/backups needs
    # no unpredictable name (no other user can pre-create paths there), so a
    # readable timestamp is safe and findable after a failed run; the base is
    # shared with the ddev dumps and the uninstall agents-backup.
    _bk_root=/var/backups/opencode-permissions-kit
    mkdir -p "$_bk_root" || exit 1
    BACKUP_DIR="$_bk_root/install-$(date +%Y%m%d-%H%M%S)"
    # same-second rerun: PID suffix instead of clobbering existing material
    [ -e "$BACKUP_DIR" ] && BACKUP_DIR="$BACKUP_DIR.$$"
    mkdir -m 700 "$BACKUP_DIR" || exit 1
    echo "Backup directory: $BACKUP_DIR"
    log "backup dir created: $BACKUP_DIR"
    # pr-00263 a F6: the backup dir is announced as recovery material —
    # a copy that failed must not be silent. Every failed copy records
    # itself loudly and degrades the closing Backup summary row.
    _BK_FAIL=""
    _bk_fail() {
        _BK_FAIL="${_BK_FAIL:+$_BK_FAIL, }$1"
        echo "  warn     backup copy failed: $1 — the recovery material is incomplete" >&2
        log "backup copy FAILED: $1"
    }
    # shellcheck disable=SC2024  # install.sh runs as root; the redirect is root's job
    # -C /: same unreadable-CWD class as issue #116 (git >= 2.55).
    sudo -u "$DEFAULT_USER" git -C / config --global --list \
        >"$BACKUP_DIR/gitconfig-$DEFAULT_USER.txt" 2>/dev/null || _bk_fail "gitconfig-$DEFAULT_USER"
    # The agent user's gitconfig only exists on a RE-install: this phase
    # runs before Step 1 creates the user, and `sudo -u` on a missing
    # user fails unconditionally — the a-F6 recorder fired on every
    # fresh install and the closing Backup row read INCOMPLETE over
    # material that never existed (issue #371 A1). Review a S1+P4
    # (#424): gate on the gitconfig FILES, not the user alone —
    # `git config --global --list` also fails rc 128 when the user
    # exists but has no global config (re-install after an aborted
    # install), and a userdel-without-`-r` leaves the home behind.
    # Both of git's global-scope locations count; the skip log names
    # what was actually checked.
    _oc_gcfg_home="$(getent passwd "$OPENCODE_USER" 2>/dev/null | cut -d: -f6 || true)"
    if [ -n "$_oc_gcfg_home" ] &&
        { [ -f "$_oc_gcfg_home/.gitconfig" ] || [ -f "$_oc_gcfg_home/.config/git/config" ]; }; then
        # shellcheck disable=SC2024  # install.sh runs as root; the redirect is root's job
        sudo -u "$OPENCODE_USER" git -C / config --global --list \
            >"$BACKUP_DIR/gitconfig-$OPENCODE_USER.txt" 2>/dev/null || _bk_fail "gitconfig-$OPENCODE_USER"
    else
        # Per-scenario wording (review b B1, #424): "user absent" is
        # false on the most common re-install shape (user exists, the
        # kit never creates a gitconfig for the agent) — name what was
        # actually checked instead.
        if [ -n "$_oc_gcfg_home" ]; then
            log "backup skipped: no global gitconfig for '$OPENCODE_USER' (checked""\
 ${_oc_gcfg_home}/.gitconfig and ${_oc_gcfg_home}/.config/git/config — neither exists) — nothing to copy"
        else
            log "backup skipped: user '$OPENCODE_USER' absent — no home to check for a global gitconfig"
        fi
    fi
    if [ -f /etc/opencode-permissions-kit/sudoers ]; then
        cp /etc/opencode-permissions-kit/sudoers "$BACKUP_DIR/sudoers" 2>/dev/null || _bk_fail "sudoers"
    fi
    if [ -f /usr/local/bin/opencode ]; then
        cp /usr/local/bin/opencode "$BACKUP_DIR/usr-local-bin-opencode" 2>/dev/null ||
            _bk_fail "usr-local-bin-opencode"
    fi
    if [ -d /usr/local/lib/opencode-permissions-kit ]; then
        cp -r /usr/local/lib/opencode-permissions-kit "$BACKUP_DIR/opencode-permissions-kit-lib" 2>/dev/null ||
            _bk_fail "opencode-permissions-kit-lib"
    fi

    ui_section "Pre-flight"

    if ! command -v curl >/dev/null 2>&1; then
        ui_error "curl is required but not installed."
        exit 1
    fi

    # python3 is a hard runtime dependency (ddev describe JSON parsing,
    # 2.x version resolution, status checks, the jsonc parser — the
    # group baseline itself degrades without it, #223) — probe presence
    # AND health up front instead of failing mid-install (0.0.39a D8;
    # the old presence-only gate was the findable-but-broken hole,
    # #244 a W1/W2).
    _py3_health_probe

    if ! command -v setfacl >/dev/null 2>&1; then
        if confirm "'acl' package not installed (setfacl/getfacl missing). Install it now?"; then
            sudo apt-get update -qq 2>/dev/null || true
            sudo apt-get install -y acl
        fi
        if ! command -v setfacl >/dev/null 2>&1; then
            ui_error "setfacl required for the group-collaboration ACLs. Install the 'acl' package and re-run."
            exit 1
        fi
    fi

    # git (soft floor, issue #118): shared helper sh/git-check.sh —
    # warn-only (never aborts) with the git-core PPA upgrade hint;
    # the rationale lives in the helper's header.
    git_check_report

    # ddev version (hard gate): rootless ddev needs ddev >= 1.25.
    # Probed twice: as root first, then as the DEFAULT user — `ddev version`
    # can come up empty under root (HOME=/root, no docker context) while the
    # very same binary answers fine as the user who actually uses ddev. The
    # second probe only runs when the first could not parse a version.
    DDEV_BIN="$(command -v ddev 2>/dev/null || true)"
    DDEV_VERSION=""
    if [ -n "$DDEV_BIN" ] && [ -x "$DDEV_BIN" ]; then
        # pr-309 b M1 (consistency): root-run probe — root never performs
        # ddev's commands walk on any 1.25.x (verified round b), but the
        # neutral cwd keeps every ddev invocation in the kit uniform and
        # future-proof against a root-permissive ddev.
        DDEV_VERSION="$( (cd / && "$DDEV_BIN" version) 2>/dev/null |
            grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//' || true)"
    fi
    DDEV_BIN_DEV=""
    if [ -z "$DDEV_VERSION" ] && id "$DEFAULT_USER" >/dev/null 2>&1; then
        DDEV_BIN_DEV="$(sudo -u "$DEFAULT_USER" env HOME="$DEV_HOME" sh -c 'command -v ddev 2>/dev/null || true')"
        if [ -n "$DDEV_BIN_DEV" ] && [ -x "$DDEV_BIN_DEV" ]; then
            # issue #279 (pr-309 a Q3): probed from / via sh -c — sudo
            # preserves the caller's cwd, and the installer runs wherever
            # the user invoked it (project directories included); ddev's
            # command walk would chmod the cwd project's .ddev/commands.
            DDEV_VERSION="$(sudo -u "$DEFAULT_USER" \
                env HOME="$DEV_HOME" sh -c 'cd / && exec "$0" version' "$DDEV_BIN_DEV" 2>/dev/null |
                grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//' || true)"
            [ -z "$DDEV_BIN" ] && DDEV_BIN="$DDEV_BIN_DEV"
        fi
    fi
    log "detected ddev: bin=${DDEV_BIN:-none} version=${DDEV_VERSION:-unknown}"
    if command -v ddev >/dev/null 2>&1 || [ -n "$DDEV_BIN" ]; then
        if [ -n "$DDEV_VERSION" ]; then
            ddev_ok=$(awk -v v="$DDEV_VERSION" 'BEGIN{split(v,a,"."); \
                if(a[1]+0>1 || (a[1]+0==1 && a[2]+0>=25)) print "yes"; else print "no"}')
            if [ "$ddev_ok" != "yes" ]; then
                ui_error "ddev $DDEV_VERSION found — the kit requires ddev >= 1.25 (rootless container support)."
                ui_warn "upgrade ddev (curl -fsSL https://ddev.com/install.sh | bash) and re-run."
                exit 1
            fi
        else
            ui_warn "ddev found but the version could not be read (as root nor as '$DEFAULT_USER')""\
 — continuing anyway (ddev >= 1.25 required)."
        fi
    else
        ui_warn "ddev not found — continuing anyway (install it later with ddev >= 1.25)."
    fi

    # Existing secured opencode binary (0.0.44f F1): re-installs REUSE it
    # (Step 6, "binary reused on re-install"), so a wedged binary — a 2.x
    # that cannot bind its port hangs even --version (issue #80) — would
    # survive the install. Warn EARLY, before the Step 5 handover; never
    # abort: the wrapper fail-opens per start (0.0.44b W10) and 'opk
    # update' replaces the binary. The major stamp itself is anchored in
    # Step 8 (F1): an unparseable probe leaves it untouched.
    # || true inside the substitution (0.0.45c C1): under bash +
    # set -eu + pipefail a timeout KILL (rc 124) took the pipeline's
    # status and errexit aborted the WHOLE install with zero output —
    # the exact hang case this block exists to warn about; the same
    # idiom as the os-release reads above.
    _pf_oc_bin=/usr/local/lib/opencode-permissions-kit/bin/opencode
    if [ -x "$_pf_oc_bin" ]; then
        _pf_oc_ver=$(timeout 10 "$_pf_oc_bin" --version 2>/dev/null | head -1 || true)
        _pf_oc_maj=$(printf '%s' "$_pf_oc_ver" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p')
        if [ -n "$_pf_oc_maj" ]; then
            log "preflight: existing opencode binary answers --version (major $_pf_oc_maj)"
        elif printf '%s' "$_pf_oc_ver" | grep -qE '^[0-9]+(\.[0-9]+)*$'; then
            log "preflight: existing opencode binary answers --version (major 1)"
        else
            ui_warn "the existing opencode binary does not answer --version (hang or noise) — continuing"
            ui_detail "the install reuses this binary; fix it afterwards (e.g. 'opk update' replaces it)"
            log "preflight: existing opencode binary unresponsive (probe line: '${_pf_oc_ver:-empty}')"
        fi
    fi

    # The container backend is rootless-only: docker-rootless (default) or
    # podman-rootless. On a re-install over an existing kit, preserve a
    # previously configured rootless backend unless --container-backend overrides.
    CONTAINER_BACKEND="docker-rootless"
    OPENCODE_DOCKER_HOST=""
    OPENCODE_PODMAN_SOCKET=""
    # Pre-set migration stamp: install.conf is REWRITTEN in Step 2, so the
    # "already exported" state must be captured here (Step 4b checks it).
    # || true: the file is optional (fresh install) — with pipefail the sed
    # failure must not abort (the old tail-masking hid it).
    DDEV_EXPORTED_PRE=$(sed -n 's/^DDEV_EXPORTED=//p' /etc/opencode-permissions-kit/install.conf \
        2>/dev/null | tail -1 || true)
    if [ -f /etc/opencode-permissions-kit/install.conf ]; then
        _be=$(sed -n 's/^CONTAINER_BACKEND=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null)
        _dh=$(sed -n 's/^OPENCODE_DOCKER_HOST=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null)
        _ps=$(sed -n 's/^OPENCODE_PODMAN_SOCKET=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null)
        case "$_be" in
            docker-rootless | podman-rootless)
                CONTAINER_BACKEND="$_be"
                [ -n "$_dh" ] && OPENCODE_DOCKER_HOST="$_dh"
                [ -n "$_ps" ] && OPENCODE_PODMAN_SOCKET="$_ps"
                ;;
        esac
    fi

    # --container-backend flag overrides (for non-interactive scripting).
    if [ -n "$CONTAINER_BACKEND_OPT" ]; then
        case "$CONTAINER_BACKEND_OPT" in
            docker-rootless | podman-rootless)
                CONTAINER_BACKEND="$CONTAINER_BACKEND_OPT"
                ;;
            *)
                ui_error "Invalid --container-backend: '$CONTAINER_BACKEND_OPT'"
                ui_info "Supported: docker-rootless | podman-rootless (rootless only)"
                exit 1
                ;;
        esac
    fi

    # Interactive backend choice (only when not --yes and no flag override).
    # Both backends confine containers to the opencode UID — no root-equivalent
    # docker socket is ever granted. Standard asks ONLY when podman is present
    # ("stay with podman?"); docker-rootless is the silent default otherwise.
    if [ "$INTERACTIVE" = true ] && [ -z "$CONTAINER_BACKEND_OPT" ]; then
        if [ "$MODE" = "advanced" ]; then
            _be_sel=$(ui_menu "Container backend for the agent user? (rootless, required)" \
                "$([ "$CONTAINER_BACKEND" = "podman-rootless" ] && echo 2 || echo 1)" \
                "1|docker-rootless (default — needs systemd --user + docker-ce-rootless-extras)" \
                "2|podman-rootless (daemonless, no systemd required)")
            case "$_be_sel" in
                2) CONTAINER_BACKEND="podman-rootless" ;;
                *) CONTAINER_BACKEND="docker-rootless" ;;
            esac
        elif command -v podman >/dev/null 2>&1; then
            _be_def="podman"
            [ "$CONTAINER_BACKEND" = "docker-rootless" ] && _be_def="docker"
            _be_sel=$(ui_menu "Podman is installed. Which rootless backend should the agent use?" \
                "$_be_def" \
                "podman|podman-rootless (daemonless — no systemd needed)" \
                "docker|docker-rootless (provisioned for the opencode user)")
            case "$_be_sel" in
                podman) CONTAINER_BACKEND="podman-rootless" ;;
                *) CONTAINER_BACKEND="docker-rootless" ;;
            esac
        fi
    fi

    # === Pre-flight inventory =====================================================
    # Read-only summary of what the checks found and what the installer will do
    # about it — the user confirms the plan before anything is modified.
    ui_section "Inventory"

    [ "$IS_WSL2" = true ] && ui_have "WSL2" "detected" || ui_atten "WSL2" "not detected — continuing anyway"
    ui_have "curl" "present"
    command -v setfacl >/dev/null 2>&1 && ui_have "acl tools" "present" || ui_add "acl tools" "installing now"
    if [ -n "$DDEV_VERSION" ]; then
        ui_have "ddev" "v$DDEV_VERSION (>= 1.25)"
    elif [ -n "$DDEV_BIN" ]; then
        ui_atten "ddev" "found (${DDEV_BIN}) but the version could not be read — treated as >= 1.25"
    else
        ui_atten "ddev" "not installed (optional — needs >= 1.25)"
    fi
    # ddev migration detection (issue #15): projects in the DEFAULT user's
    # registry lose their daemon after the switch — the export is offered.
    # Gated on the registry file alone: ddev may live off root's PATH (the
    # binary is resolved again at export time with per-user fallbacks).
    DD_MIG_ALL=""
    if [ -d "$DEV_HOME/.ddev" ]; then
        DD_MIG_ALL=$(ddev_migrate_registry "$DEV_HOME/.ddev")
    fi
    DD_MIG_COUNT=$(printf '%s\n' "$DD_MIG_ALL" | grep -c . || true)
    if [ "$DD_MIG_COUNT" -gt 0 ]; then
        ui_atten "ddev projects" "$DD_MIG_COUNT registered for '$DEFAULT_USER' — database export offered"
    else
        ui_have "ddev projects" "none registered (nothing to migrate)"
    fi
    HAVE_DOCKER=false
    HAVE_PODMAN=false
    command -v docker >/dev/null 2>&1 && HAVE_DOCKER=true
    command -v podman >/dev/null 2>&1 && HAVE_PODMAN=true
    if [ "$HAVE_DOCKER" = true ]; then
        ui_have "docker CLI" "present — rootless backend will be provisioned for 'opencode'"
    elif [ "$HAVE_PODMAN" = true ]; then
        ui_have "podman" "present — used rootless for 'opencode'"
    else
        ui_add "$CONTAINER_BACKEND" "will be installed + provisioned for 'opencode'"
    fi

    # Existing kit detection: user 'opencode', install.conf, or a wrapper symlink.
    if id "$OPENCODE_USER" >/dev/null 2>&1 || [ -f /etc/opencode-permissions-kit/install.conf ] ||
        [ -L /usr/local/bin/opencode ]; then
        _ekv="unknown"
        [ -f /etc/opencode-permissions-kit/install.conf ] &&
            _ekv=$(sed -n 's/^VERSION=//p' /etc/opencode-permissions-kit/install.conf)
        ui_atten "existing kit" "detected (v${_ekv:-?}) — update.sh is the usual upgrade path"
        if [ "$INTERACTIVE" = true ]; then
            # Convention: agent/conventions.md — [Y/n] via ui_confirm.
            # The y default is deliberate (#428 disposition, uniform
            # with update.sh's confirm()): install.sh reaching this
            # gate is an explicit invocation whose yes is the purpose
            # — the re-configure touches kit config only (user config
            # is detected and kept downstream), the prompt is
            # INTERACTIVE-gated (the curl|bash path never sees it),
            # and "no" just points at opk update and exits 0. The
            # conventions' carve-out (agent/conventions.md,
            # "Interactive prompts"): y where "no" is the surprising
            # answer for the command's declared intent.
            if ! ui_confirm "Re-configure the existing installation with install.sh?" "y"; then
                ui_info "Aborted — run: opk update"
                exit 0
            fi
        fi
    fi

    # opencode binary candidates (the copy+secure step runs later).
    OC_BINARY_FOUND=""
    for loc in "$DEV_HOME/.opencode/bin/opencode" "/root/.opencode/bin/opencode" \
        "/usr/local/bin/opencode" "/usr/bin/opencode"; do
        # /usr/local/bin/opencode is skipped only as the kit WRAPPER
        # SYMLINK (present after any completed install — copying it over
        # the secured binary would deploy the wrapper script as the
        # binary). A REAL file there (a manual official-installer
        # install) is a valid pickup source (issue #372 I4).
        if [ -x "$loc" ] && { [ "$loc" != "/usr/local/bin/opencode" ] || [ ! -L "$loc" ]; }; then
            OC_BINARY_FOUND="$loc"
            ui_have "opencode binary" "$loc — will be secured under the kit"
            break
        fi
    done
    [ -n "$OC_BINARY_FOUND" ] || ui_add "opencode binary" "official installer will fetch it"

    # WSL2 /mnt/c exposure preview (hardening snippet comes later in step 4).
    if [ -d /mnt/c ]; then
        _pm=$(stat -c %a /mnt/c 2>/dev/null || echo "")
        if [ -n "$_pm" ] && [ $((0$_pm & 0004)) -ne 0 ]; then
            ui_atten "/mnt/c" "world-readable (mode $_pm) — hardening snippet shown in step 4"
        else
            ui_have "/mnt/c" "restricted (mode ${_pm:-?})"
        fi
    fi

    # Router-port readiness preview.
    _pps=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
    if [ "${_pps:-1024}" -le 80 ] 2>/dev/null; then
        ui_have "router ports" "ready (ip_unprivileged_port_start=$_pps)"
    else
        ui_add "router ports" "sysctl to 80 offered (ddev-router 80/443)"
    fi

    # Validate --projects values against the same policy (fail fast, before
    # anything is touched). The list is rebuilt from _PP_NORM so a tilde path
    # like ~/dev is stored expanded — the raw value would never match a real
    # directory in any consumer (review 0.0.39b C1).
    if [ -n "$PREDEFINED_PROJECTS" ]; then
        _fp_norm=""
        for _fp in $PREDEFINED_PROJECTS; do
            # Glob characters were already rejected on the raw argument
            # in parse_args (0.0.42f S2) — pathname expansion can never
            # widen this loop's word list.
            if ! project_path_sane "$_fp"; then
                ui_error "'$_fp' is not a valid project root (system path, symlink, or malformed form) — refusing to use it."
                ui_info "Use a dedicated folder like /var/www/vhosts or /home/<you>/projects."
                # Issue #372 A3: a --projects value with internal
                # whitespace word-splits here — the fragment above may
                # be HALF a path the user typed. Name the cause instead
                # of leaving a misleading "system path" diagnosis.
                if [ "${PROJECTS_ARG_SPACED:-false}" = true ]; then
                    ui_info "a --projects value contained whitespace: if '$_fp' is part of one path,""\
 that path cannot be a project root (roots are stored space-separated) — pass each root as its own argument."
                fi
                exit 1
            fi
            _fp_norm="$_fp_norm $_PP_NORM"
        done
        PREDEFINED_PROJECTS="${_fp_norm# }"
    fi

    # === Standard questions ========================================================
    # Standard asks exactly: project directory + git access. The podman exception
    # was already asked during backend selection. --yes takes the defaults.
    if [ "$MODE" = "standard" ] && [ "$INTERACTIVE" = true ]; then
        ui_section "Standard setup"

        if [ -z "$PREDEFINED_PROJECTS" ]; then
            _pdef="/var/www/vhosts"
            [ -d "$_pdef" ] || _pdef=""
            ui_detail "a parent folder holding your projects — the agent may only"
            ui_detail "start inside it. Example paths:"
            ui_detail "  /var/www/vhosts"
            ui_detail "  ~/dev"
            ui_detail "  ~/projects"
            while true; do
                _p=$(ui_ask "Project directory (agent workspaces)" "$_pdef")
                # Empty (no default existed) falls through to the project
                # selection later — which, since 0.0.44a V6, means the
                # numbered prompt interactively and the documented skip
                # under --yes. Only validate what was actually entered.
                if [ -n "$_p" ]; then
                    if ! project_path_sane "$_p"; then
                        ui_error "'$_p' is not a valid project root (system path, symlink, or malformed form)."
                        ui_info "Use a dedicated folder like /var/www/vhosts, ~/dev or ~/projects."
                        continue
                    fi
                    _p="$_PP_NORM" # ~ expanded to $HOME
                fi
                break
            done
            [ -n "$_p" ] && PREDEFINED_PROJECTS="$_p"
        fi
        if [ "$GIT_FLAG_GIVEN" != true ]; then
            _g=$(ui_menu "Allow opencode access to git commands?" "no" \
                "no|block .git/config for the agent (recommended)" \
                "yes|allow git commands")
            if [ "$_g" = "yes" ]; then SECURE_GIT_CONFIG=false; else SECURE_GIT_CONFIG=true; fi
        fi
        if [ "$DDEV_SETTINGS_GIVEN" != true ]; then
            _ds=$(ui_menu "ddev settings management? (dev-owned projects)" "dev-owned" \
                "dev-owned|kit disables it — settings files stay yours, permanent 2775 (recommended)" \
                "ddev|ddev keeps writing CMS settings (handover model)")
            [ "$_ds" = "ddev" ] && DDEV_DEV_OWNED=false
        fi
    fi

    # === OpenChamber policy pin (issue #154) =======================================
    # OpenChamber's one-click "Update to OpenCode 2" pins its own opencode
    # binary (~/.opencode/bin/...) in settings.json — every OpenChamber
    # session then runs OUTSIDE the kit. An admin-owned policy file
    # (/etc/openchamber/policy.json) pins it back to the kit wrapper,
    # retroactively. Opt-in: it disables OpenChamber's self-update buttons
    # (updates go through `opk upgrade-opencode`). Asked only when
    # OpenChamber is present; --yes without the flag keeps it off; an
    # earlier opt-in survives re-installs; later: sudo opk openchamber-secure.
    if [ "$OPENCHAMBER_POLICY_GIVEN" != true ]; then
        _oc_seen=false
        [ -d "$DEV_HOME/.config/openchamber" ] && _oc_seen=true
        [ -e "$DEV_HOME/.opencode/bin/opencode" ] && _oc_seen=true
        [ -e "$DEV_HOME/.opencode/bin/opencode2" ] && _oc_seen=true
        [ -f /etc/openchamber/policy.json ] && _oc_seen=true
        command -v openchamber >/dev/null 2>&1 && _oc_seen=true
        _oc_prev=""
        if [ -f /etc/opencode-permissions-kit/install.conf ]; then
            _oc_prev=$(sed -n 's/^OPENCHAMBER_POLICY=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1)
        fi
        if [ "$INTERACTIVE" = true ] && [ "$_oc_seen" = true ]; then
            if ui_confirm "Protect OpenChamber sessions too? (policy pin — its self-update buttons go dark)" "y"; then
                OPENCHAMBER_POLICY=yes
            else
                OPENCHAMBER_POLICY=no
            fi
        elif [ "$_oc_prev" = "yes" ]; then
            OPENCHAMBER_POLICY=yes # keep an earlier opt-in (non-interactive)
        fi
    else
        OPENCHAMBER_POLICY="$OPENCHAMBER_POLICY_OPT"
    fi
    [ -n "$OPENCHAMBER_POLICY" ] || OPENCHAMBER_POLICY=no

    # === Plan + confirmation ========================================================
    # The full plan with the effective values; C proceeds, A switches to the
    # granular prompts (Advanced), X aborts. Non-interactive runs print the plan
    # without asking.
    ui_section "Plan"

    # Numbered dynamically: optional steps (mnt/c, port sysctl) are omitted
    # when not applicable — no gaps in the list the user confirms.
    _plan_n=0
    _plan() {
        _plan_n=$((_plan_n + 1))
        ui_plan "$_plan_n" "$1" "$2"
    }

    _plan "create user 'opencode' + sharing group" "(developer '$DEFAULT_USER' added)"
    _plan "provision $CONTAINER_BACKEND for 'opencode'" "(mandatory — aborts on failure)"
    if [ "${DD_MIG_COUNT:-0}" -gt 0 ]; then
        _plan "export ddev databases to SQL dumps" "($DD_MIG_COUNT project(s), before the .ddev handover)"
    fi
    if [ -n "$PREDEFINED_PROJECTS" ]; then
        _plan "group + setgid + default ACLs" "on $PREDEFINED_PROJECTS"
    else
        _plan "group + setgid + default ACLs" "(project roots selected next)"
    fi
    if [ "$DDEV_DEV_OWNED" = true ]; then
        _plan "ddev dev-owned mode" "(writes disable_settings_management: true into .ddev/config.yaml)"
    fi
    _plan "secure the opencode binary + wrapper" "root:opencode 750"
    if [ "$OPENCHAMBER_POLICY" = yes ]; then
        _plan "pin OpenChamber to the kit wrapper" "(/etc/openchamber/policy.json — self-update off)"
    fi
    if [ -d /mnt/c ]; then
        _pm=$(stat -c %a /mnt/c 2>/dev/null || echo "")
        if [ -n "$_pm" ] && [ $((0$_pm & 0004)) -ne 0 ]; then
            _plan "print /mnt/c hardening snippet" "(manual — the kit never writes /etc/wsl.conf)"
        fi
    fi
    _pps=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
    [ "${_pps:-1024}" -gt 80 ] 2>/dev/null && _plan "lower ip_unprivileged_port_start to 80" "(ddev-router 80/443)"
    _plan "deny-all config for your user" "(self-update bypass guard)"
    _plan "deploy library, sudoers, audit log" "/usr/local/lib/opencode-permissions-kit"
    if browser_bridge_is_wsl; then
        _plan "deploy WSL browser bridge stand-in" "(login fix; wsl.conf carrier via 'opk wsl-add-opencode-1-fix')"
    fi

    if [ "$INTERACTIVE" = true ]; then
        echo ""
        _go=$(ui_menu "Proceed?" "C" "C|Confirm" "A|Switch to Advanced" "X|Abort")
        case "$_go" in
            X)
                ui_info "Aborted — nothing was changed."
                exit 0
                ;;
            A)
                MODE="advanced"
                ui_info "Advanced mode — the remaining steps ask for your decisions."
                ;;
        esac
    fi

    # Standard answers every remaining decision with the recommended value
    # (identical to --yes); Advanced keeps the granular prompts below.
    [ "$MODE" = "standard" ] && SKIP_PROMPTS=true
    log "plan confirmed (mode=$MODE)"

    # === Step 1: User + group ===

    ui_info "Creating user + sharing group ..."
    if id "$OPENCODE_USER" >/dev/null 2>&1; then
        confirm "User '$OPENCODE_USER' already exists. Reuse it?" || {
            ui_info "Aborted."
            exit 1
        }
        install_reuse_home_guard
        install_reuse_group_guard
    else
        sudo useradd -m -s /bin/bash "$OPENCODE_USER"
        ui_success "user '$OPENCODE_USER' created"
        log "user created: $OPENCODE_USER"
    fi

    # The sharing group is the opencode user's PRIMARY usergroup (auto-created by
    # useradd -m). No www-data, no extra group to create or remove.
    OPENCODE_GROUP=$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")
    # The developer's membership is the kit's core sharing mechanism — a silent
    # failure here would leave the whole model without its foundation, so this
    # fails loud (and verifies membership instead of trusting the exit code).
    if ! sudo usermod -aG "$OPENCODE_GROUP" "$DEFAULT_USER"; then
        ui_error "failed to add '$DEFAULT_USER' to the sharing group '$OPENCODE_GROUP'."
        log "sharing group: usermod FAILED for $DEFAULT_USER — install aborted"
        exit 1
    fi
    if ! id -nG "$DEFAULT_USER" | tr ' ' '\n' | grep -qx "$OPENCODE_GROUP"; then
        # usermod returned success but the group database disagrees — surface it
        # instead of reporting unqualified success.
        ui_warn "membership not yet visible via id(1) — verify with 'id -nG $DEFAULT_USER' after the install"
    fi
    ui_success "sharing group '$OPENCODE_GROUP' (developer '$DEFAULT_USER' added)"
    log "sharing group: $OPENCODE_GROUP (developer $DEFAULT_USER added)"

    # === Step 2: Project roots ===

    if [ -n "$PREDEFINED_PROJECTS" ]; then
        PROJECTS_ROOTS="$PREDEFINED_PROJECTS"
    elif [ "$SKIP_PROMPTS" = true ]; then
        # --yes without --projects (0.0.44a V6): every sibling prompt
        # honors SKIP_PROMPTS — this selection loop was the one hold-out,
        # and on EOF without a controlling tty (checkout-mode runs from
        # cron/CI/ssh -T: no UI_NO_STDIN_FALLBACK there) it spun forever
        # on `invalid selection ''`. The --yes default is the skip: user
        # + wrapper, no project baseline.
        PROJECTS_ROOTS=""
        ui_info "--yes without --projects: no project baseline configured (skip)"
        log "project roots: skipped (--yes, no --projects given)"
    else
        install_project_roots_select
    fi

    sudo mkdir -p /etc/opencode-permissions-kit
    if [ -n "$PROJECTS_ROOTS" ]; then
        # Atomic write (#482 F19 sweep, config.sh's projects_remove
        # shape): a kill mid-tee left a truncated projects.conf whose
        # partial root list silently narrows every later read (status,
        # the config.sh rewrites) — stage beside it, then rename in.
        _PRJ_CONF_TMP="/etc/opencode-permissions-kit/projects.conf.opk-new.$$"
        _tmp_track "$_PRJ_CONF_TMP"
        echo "$PROJECTS_ROOTS" | tr ' ' '\n' | sudo tee "$_PRJ_CONF_TMP" >/dev/null
        sudo mv -f "$_PRJ_CONF_TMP" /etc/opencode-permissions-kit/projects.conf
        echo "Project roots: $PROJECTS_ROOTS"
        log "projects.conf written: $PROJECTS_ROOTS"
    else
        sudo touch /etc/opencode-permissions-kit/projects.conf
        echo "No project roots configured."
        log "projects.conf written: (empty)"
    fi

    # Backup project ACLs now that roots are known
    if [ -n "$PROJECTS_ROOTS" ]; then
        # shellcheck disable=SC2086,SC2024  # word splitting intended (root list); root redirects
        # pr-00263 a F8: the success line must observe the copy (getfacl
        # absent or errored used to pass silently into recovery material).
        if sudo getfacl -R $PROJECTS_ROOTS 2>/dev/null >"$BACKUP_DIR/getfacl-R-projects.txt"; then
            echo "Project ACLs backed up to $BACKUP_DIR/getfacl-R-projects.txt"
        else
            echo "  warn     project ACL backup FAILED (getfacl absent or errored) — no ACL recovery material" >&2
            log "getfacl project backup FAILED"
        fi
    fi

    ui_info "Writing /etc/opencode-permissions-kit/install.conf ..."
    # Atomic stamp rewrite (0.0.39g C5): tee in place truncated the stamp on a
    # mid-write crash; write the full stamp beside it, then rename it in.
    # Per-process suffix (0.0.42f C1): a fixed name let concurrent runs
    # clobber each other's staging file (root-created by the tee below —
    # mktemp cannot create in the root-only conf dir).
    _INSTALL_CONF_TMP="/etc/opencode-permissions-kit/install.conf.opk-new.$$"
    _tmp_track "$_INSTALL_CONF_TMP"
    sudo tee "$_INSTALL_CONF_TMP" >/dev/null <<EOF
DEFAULT_USER=$DEFAULT_USER
OPENCODE_USER=$OPENCODE_USER
OPENCODE_GROUP=$OPENCODE_GROUP
DDEV_VERSION=$DDEV_VERSION
CONTAINER_BACKEND=$CONTAINER_BACKEND
OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST
OPENCODE_PODMAN_SOCKET=$OPENCODE_PODMAN_SOCKET
DDEV_DEV_OWNED=$DDEV_DEV_OWNED
OPENCHAMBER_POLICY=$OPENCHAMBER_POLICY
KIT_CHANNEL=$KIT_BRANCH
VERSION=$VERSION
EOF
    sudo mv -f "$_INSTALL_CONF_TMP" /etc/opencode-permissions-kit/install.conf
    log "install.conf written (version $VERSION, channel $KIT_BRANCH)"

    # === Step 3: Provision the rootless container backend (mandatory) ===
    # A failed provisioning ABORTS the install — the kit never falls back to a
    # root-equivalent path. The helper installs packages, allocates
    # subuid/subgid, and sets up the daemon; it prints OPENCODE_DOCKER_HOST=... on
    # stdout for the caller to record.
    ui_section "Provisioning container backend: $CONTAINER_BACKEND"
    SETUP_SCRIPT="$SCRIPT_DIR/opencode-permissions-kit-lib/bin/setup-container-backend"
    [ -f "$SETUP_SCRIPT" ] || SETUP_SCRIPT="$LIBDIR/bin/setup-container-backend"
    _setup_out=$(sh "$SETUP_SCRIPT" "$CONTAINER_BACKEND" --yes 2>&1) || {
        ui_error "Container backend provisioning failed."
        echo "$_setup_out"
        ui_warn "fix the issue above and re-run. podman-rootless needs no systemd — try it when docker-rootless cannot run."
        log "container backend provisioning FAILED ($CONTAINER_BACKEND) — install aborted"
        exit 1
    }
    _sock=$(echo "$_setup_out" | sed -n 's/^\(OPENCODE_DOCKER_HOST=.*\)/\1/p' | tail -1)
    if [ -n "$_sock" ]; then
        OPENCODE_DOCKER_HOST="${_sock#OPENCODE_DOCKER_HOST=}"
    fi
    # { grep -v || true }: display-only filter — grep -v exits 1 when the
    # setup output consists solely of OPENCODE_ key lines, which pipefail
    # would turn into an abort right after successful provisioning
    # (fix-wave review).
    echo "$_setup_out" | { grep -v '^OPENCODE_' || true; } | sed 's/^/     /'
    ui_success "container backend provisioned: $CONTAINER_BACKEND"
    # Re-stamp the socket into install.conf. The value is kit-controlled
    # (setup-container-backend output) but is still escaped for the sed
    # replacement — '#', '&' or '\' in a socket path must not corrupt the
    # rewrite (review 0.0.39b C4).
    _odh_esc=$(printf '%s' "$OPENCODE_DOCKER_HOST" | sed 's/[&\\#]/\\&/g')
    sudo sed -i "s#^OPENCODE_DOCKER_HOST=.*#OPENCODE_DOCKER_HOST=$_odh_esc#" /etc/opencode-permissions-kit/install.conf
    log "container backend provisioned: $CONTAINER_BACKEND"
}

# === Phase 2: ddev (Step 4 .. Step 4b) ==========================================
# ddev runtime for the agent user (home, mkcert CA reuse, router ports,
# bind-mounts switch) and the dev-user database export wave, incl. the
# DDEV_EXPORTED stamp carry-over. Moved verbatim — see phase 1.

do_ddev_phase() {
    # === Step 4: ddev as the opencode user ===
    # /home/<oc>/.ddev is the opencode user's global ddev home (project registry,
    # mutagen state, `ddev auth ssh` key cache). mkcert CA reuse keeps Windows
    # browsers trusting ddev's HTTPS certs. Router ports: rootless ddev-router
    # cannot bind 80/443 unless ip_unprivileged_port_start <= 80.
    ui_section "ddev runtime for user $OPENCODE_USER"
    # Operand gate (review 0.0.39h F1) BEFORE any chown/chmod: both
    # dereference a symlink OPERAND, and ~/.ddev is agent-replaceable after
    # any completed install — a planted link there must never hand the
    # pointed tree to the agent or chmod it. Skip loudly (user-managed).
    if agent_home_sane "$OPENCODE_USER" "/home/$OPENCODE_USER/.ddev"; then
        sudo mkdir -p "/home/$OPENCODE_USER/.ddev"
        sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "/home/$OPENCODE_USER/.ddev"
        sudo chmod 755 "/home/$OPENCODE_USER/.ddev"
        log "ddev home provisioned: /home/$OPENCODE_USER/.ddev"
    else
        log "ddev home provisioning skipped: /home/$OPENCODE_USER/.ddev is a symlink (user-managed)""\
 or the home-sane gate was unavailable (staged-write.sh incomplete — fix: sudo opk update)"
    fi

    # docker-rootless + ddev 1.25.0-1.25.2: the global no-bind-mounts switch
    # is required or the first `ddev start` hard-errors (upstream fixed
    # rootless bind mounts in v1.25.3 — newer ddevs keep bind mounts). The
    # if/else keeps set -e out of the picture: "not needed" is rc=1.
    if [ "$CONTAINER_BACKEND" = "docker-rootless" ] && [ -n "$DDEV_BIN" ] && [ -n "$DDEV_VERSION" ]; then
        if ddev_rootless_bindmounts "$OPENCODE_USER" "$CONTAINER_BACKEND" "$DDEV_VERSION" "$DDEV_BIN"; then
            ui_success "ddev no-bind-mounts global set (required for ddev $DDEV_VERSION on docker-rootless)"
            log "ddev no-bind-mounts set (backend=docker-rootless, ddev=$DDEV_VERSION)"
        else
            case $? in
                2)
                    ui_warn "could not set ddev's no-bind-mounts global — ddev $DDEV_VERSION on docker-rootless"
                    ui_warn "may fail with 'bind mounts can't be used with Docker Rootless'. Fix manually:"
                    ui_detail "sudo -u $OPENCODE_USER env HOME=/home/$OPENCODE_USER ddev config global --no-bind-mounts"
                    log "ddev no-bind-mounts setup failed (backend=docker-rootless, ddev=$DDEV_VERSION)"
                    ;;
            esac
        fi
    fi

    port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)
    if [ "${port_start:-1024}" -gt 80 ] 2>/dev/null; then
        if confirm "Lower net.ipv4.ip_unprivileged_port_start to 80 so ddev-router can bind 80/443?""\
 (host-wide sysctl)"; then
            if echo 'net.ipv4.ip_unprivileged_port_start=80' |
                sudo tee /etc/sysctl.d/99-ddev-rootless.conf >/dev/null 2>&1; then
                if sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1; then
                    ui_success "unprivileged port start lowered to 80 (persisted: /etc/sysctl.d/99-ddev-rootless.conf)"
                    log "net.ipv4.ip_unprivileged_port_start=80 applied"
                    # docker-rootless: the daemon's network namespace inherited the
                    # OLD value at start; restart it so it re-inherits 80.
                    # podman-rootless is daemonless (fresh netns per run) — no restart.
                    oc_uid=$(id -u "$OPENCODE_USER" 2>/dev/null)
                    if [ "$CONTAINER_BACKEND" = "docker-rootless" ] && [ -n "$oc_uid" ]; then
                        if sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$oc_uid" \
                            systemctl --user restart docker.service 2>/dev/null; then
                            ui_success "restarted the opencode rootless docker daemon (its netns re-inherits port-start 80)"
                            log "rootless docker daemon restarted for port-start 80"
                        else
                            ui_warn "could not restart the rootless daemon — run it manually:"
                            echo "  sudo -u $OPENCODE_USER XDG_RUNTIME_DIR=/run/user/$oc_uid""\
 systemctl --user restart docker.service"
                            log "rootless daemon restart failed (admin must restart manually)"
                        fi
                    fi
                else
                    ui_warn "sysctl persisted but not activated live (read-only /proc/sys?) — reboot or run:"
                    echo "  sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
                    log "sysctl persisted but not activated live"
                fi
            else
                ui_warn "could not write /etc/sysctl.d/99-ddev-rootless.conf""\
 — apply the sysctl manually or use higher router ports."
            fi
        else
            ui_detail "skipped — either set the sysctl manually or use higher router ports:"
            echo "  sudo -u $OPENCODE_USER ddev config global --router-http-port 8080 --router-https-port 8443"
        fi
    fi

    # WSL2 /mnt/c restriction (report-only — the kit NEVER writes /etc/wsl.conf,
    # internal/records/wsl-conf-consent.md): the drvfs mount runs with the Windows
    # session token, so NTFS ACLs do NOT distinguish WSL users — the
    # world-readable default (mode 777) exposes the whole Windows profile
    # (.ssh, NTUSER.DAT, browser data) to every WSL user, including the
    # agent's. Print the ready-to-run snippet; applying it is the user's
    # explicit call and takes effect only after 'wsl --shutdown' from Windows.
    if [ -d /mnt/c ]; then
        mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
        if [ -z "$mnt_mode" ] || [ $((0$mnt_mode & 0004)) -eq 0 ]; then
            echo "  /mnt/c already restricted (mode ${mnt_mode:-?}) — Windows profile not exposed."
        elif grep -q '^\[automount\]' /etc/wsl.conf 2>/dev/null; then
            ui_warn "NOTE: /etc/wsl.conf already has an [automount] section — left untouched."
            echo "  /mnt/c is world-readable (mode $mnt_mode); every WSL user incl. the agent"
            echo "  can read the Windows profile. Restrict it manually if unintended."
            log "wsl.conf has a pre-existing [automount] section — no hardening snippet printed"
        else
            d_uid=$(id -u "$DEFAULT_USER" 2>/dev/null || echo "")
            d_gid=$(id -g "$DEFAULT_USER" 2>/dev/null || echo "")
            ui_warn "/mnt/c is world-readable (mode $mnt_mode) — every WSL user incl. the agent"
            ui_warn "can read the Windows profile (.ssh, NTUSER.DAT, browser data)."
            ui_warn "The kit does not edit /etc/wsl.conf — apply the restriction yourself:"
            ui_detail "[automount]"
            ui_detail "enabled = true"
            if [ -n "$d_uid" ] && [ -n "$d_gid" ]; then
                ui_detail "options = \"uid=$d_uid,gid=$d_gid,dmask=027,fmask=037\""
            else
                ui_detail 'options = "uid=<your-uid>,gid=<your-gid>,dmask=027,fmask=037"'
            fi
            ui_warn "(append to /etc/wsl.conf, then 'wsl --shutdown' from Windows + reopen the distro)."
            log "/mnt/c hardening snippet printed (kit never writes wsl.conf)"
        fi
    fi

    # mkcert CA reuse: search order 1. Windows CA (WSL2 /mnt/c), 2. developer's
    # Linux CAROOT, 3. 'mkcert -install' (new, untrusted CA). $caroot lives in
    # the AGENT-owned home: every root write below goes through staged_write
    # (mv replaces a planted link, never follows it) and every chown/chmod on
    # the directory itself is [ -L ]-gated — chown/chmod dereference a symlink
    # operand (review 0.0.39g S1).
    caroot="/home/$OPENCODE_USER/.local/share/mkcert"
    if [ ! -f "$caroot/rootCA.pem" ]; then
        # Chain gate (review 0.0.39h F2) BEFORE mkdir -p: every component of
        # the chain to $caroot (~/.local, ~/.local/share) is
        # agent-replaceable — a planted link passes `sudo mkdir -p` silently
        # and would redirect the staged_write mvs + the caroot chown/chmod
        # below into the link target. Skip loudly (user-managed); no CA will
        # exist, so warn like the other no-CA ends (0.0.39h F5).
        if ! agent_home_sane "$OPENCODE_USER" "$caroot"; then
            ui_warn "mkcert: the chain to $caroot contains a symlink — CA provisioning skipped""\
 (the kit never follows links in the agent home) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)."
            ui_warn "no mkcert CA exists at $caroot — ddev HTTPS will use an untrusted or no certificate. ""\
Remove a link in the chain or place your CA at $caroot and re-run — if the home-sane""\
 gate was unavailable instead: sudo opk update."
            log "mkcert CA provisioning skipped: symlink in the chain to $caroot (no CA""\
 provisioned) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
        else
            sudo mkdir -p "$caroot"
            src=""
            src_label=""
            # 1. Windows CA: scan the user profiles DIRECTLY. powershell.exe /
            #    cmd.exe are frequently not on a WSL PATH, so %USERNAME% probing is
            #    unreliable — a failed probe silently skipped the Windows CA and
            #    fell through to an untrusted one (browsers showed "not secure").
            if [ -d /mnt/c/Users ]; then
                for wca in /mnt/c/Users/*/AppData/Local/mkcert; do
                    if [ -f "$wca/rootCA.pem" ] && [ -f "$wca/rootCA-key.pem" ]; then
                        src="$wca"
                        wuser=${wca#/mnt/c/Users/}
                        src_label="Windows user '${wuser%%/*}'"
                        break
                    fi
                done
            fi
            if [ -z "$src" ] && [ -n "$DEFAULT_USER" ] && [ -f "$DEV_HOME/.local/share/mkcert/rootCA.pem" ]; then
                src="$DEV_HOME/.local/share/mkcert"
                src_label="developer '$DEFAULT_USER'"
            fi
            if [ -n "$src" ]; then
                # No && chain: a mid-chain failure silently skipped the chmod 600
                # on the copied CA PRIVATE KEY (0.0.39e C2). Each step is explicit;
                # a failure aborts the reuse loudly and falls through to the
                # mkcert -install fallback below. The CA files go through
                # staged_write (mode + owner applied on the staged file); the
                # directory inode handover rechecks [ -L ] immediately before
                # chown/chmod touch it (0.0.39g S1).
                if staged_write 644 "$OPENCODE_USER:$OPENCODE_GROUP" "$src/rootCA.pem" "$caroot/rootCA.pem" &&
                    staged_write 600 "$OPENCODE_USER:$OPENCODE_GROUP" "$src/rootCA-key.pem" "$caroot/rootCA-key.pem" &&
                    [ ! -L "$caroot" ] &&
                    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "$caroot" &&
                    sudo chmod 700 "$caroot"; then
                    echo "  mkcert CA reused from $src_label -> $caroot (Windows browsers already trust it)"
                    log "mkcert CA reused from $src_label for $OPENCODE_USER"
                else
                    ui_warn "mkcert CA reuse from $src_label FAILED — removing the partial copy, falling back to a new CA."
                    sudo rm -f "${caroot:?}/rootCA.pem" "${caroot:?}/rootCA-key.pem"
                    log "mkcert CA reuse FAILED (source: $src_label) — partial copy removed"
                    # The elif below no longer applies once this branch ran — do
                    # the new-CA fallback here, and VERIFY it: a failed step above
                    # may have left $caroot root-owned (mkcert -install as the
                    # agent would then fail), and "falling back" must not
                    # silently end without any CA (wave-f review).
                    if [ ! -L "$caroot" ]; then
                        sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "$caroot" 2>/dev/null || true
                    fi
                    if command -v mkcert >/dev/null 2>&1; then
                        sudo -u "$OPENCODE_USER" env CAROOT="$caroot" mkcert -install >/dev/null 2>&1 || true
                    fi
                    if [ ! -f "$caroot/rootCA.pem" ]; then
                        ui_warn "no mkcert CA exists at $caroot after the fallback""\
 — ddev HTTPS will use an untrusted or no certificate. Install mkcert or copy your CA to $caroot and re-run."
                        log "mkcert CA fallback produced no CA at $caroot"
                    fi
                fi
            elif command -v mkcert >/dev/null 2>&1; then
                # Fresh CA. mkcert runs as the agent and can only write $caroot
                # once the kit user owns it — hand the ([ -L ]-gated, root-created)
                # directory over FIRST; the old silent-no-CA path ran mkcert
                # against a root-owned dir (0.0.39g C1). The system/Windows trust
                # stores are NOT touched: mkcert as the agent cannot reach them
                # (0.0.39g Q7), and installing an agent-writable CA system-wide
                # is the developer's call — see the hint below.
                if [ ! -L "$caroot" ]; then
                    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "$caroot" 2>/dev/null || true
                    sudo chmod 700 "$caroot" 2>/dev/null || true
                fi
                sudo -u "$OPENCODE_USER" env CAROOT="$caroot" mkcert -install >/dev/null 2>&1 || true
                if [ -f "$caroot/rootCA.pem" ]; then
                    ui_warn "mkcert: no existing CA found — a new one was created at $caroot."
                    ui_warn "It is NOT trusted by the system or Windows stores (mkcert ran as '$OPENCODE_USER')""\
: browsers will warn."
                    ui_detail "Import $caroot/rootCA.pem into your browser, ""\
or run 'sudo env CAROOT=$caroot mkcert -install' yourself."
                    log "mkcert: no existing CA — new one created for $OPENCODE_USER (system trust store not updated)"
                else
                    ui_warn "no mkcert CA exists at $caroot after the install attempt""\
 — ddev HTTPS will use an untrusted or no certificate. Install mkcert or copy your CA to $caroot and re-run."
                    log "mkcert: fresh-install attempt produced no CA at $caroot"
                fi
            else
                ui_warn "NOTE: mkcert not installed and no CA to reuse — install mkcert or copy your CA to $caroot."
            fi
        fi
    fi

    # === Step 4b: ddev database export (dev user -> SQL dumps) ===================
    # Issue #15: pre-kit ddev projects live in the DEFAULT user's registry and
    # daemon. After the kit takes over, ddev runs as $OPENCODE_USER against the
    # new rootless daemon — the dev-side containers/volumes become unreachable
    # and containers cannot move between daemons. SQL dumps are the only
    # portable copy, so they are exported NOW, while dev-side ddev still works:
    # the .ddev handover at the end of Step 5 chowns .ddev to $OPENCODE_USER
    # and would break dev-side `ddev start` (the chmod-is-owner-only rule).
    # The IMPORT is deliberately NOT part of the install: it is a separate,
    # user-driven step (first opencode-side start pulls images) — see the
    # summary below and docs/concepts/ddev-integration.md.
    DD_MIG_DUMP_DIR=""
    # Partial-export detector (production finding: a pre-registry-fix run
    # exported 1 of 12 databases, stamped DDEV_EXPORTED=1, and every later
    # install silently skipped the export while eleven databases stayed in
    # the old daemon). Loud warning whenever the CURRENT dev registry lists
    # more projects than the newest manifest recorded — no-op without a
    # manifest or without growth.
    _ddev_mig_gap_warn() {
        # shellcheck disable=SC2086  # word splitting intended (root list)
        _g=$(ddev_migrate_gap "$DEFAULT_USER" $PROJECTS_ROOTS) || return 0
        _g_have=${_g%% *}
        _g_rest=${_g#* }
        _g_now=${_g_rest%% *}
        ui_warn "partial ddev export detected: the registry lists $_g_now project(s)""\
 under the roots, only $_g_have dump(s) recorded"
        ui_warn "the missing databases stay in the old daemon — bridge them ""\
(docs/troubleshooting.md, 'My databases are gone after the install')"
        ui_detail "see what is missing: /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate""\
 registry $DEFAULT_USER $PROJECTS_ROOTS"
        log "ddev migration gap detected: registry=$_g_now dumps=$_g_have"
    }
    if [ "${DD_MIG_COUNT:-0}" -gt 0 ]; then
        ui_section "ddev databases (user $DEFAULT_USER)"
        if [ "$SKIP_DDEV_MIGRATION" = true ]; then
            ui_detail "skipped (--skip-ddev-migration) — the databases become unreachable"
            ui_detail "with the old daemon; export manually BEFORE using ddev again:"
            ui_detail "  sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate""\
 export $DEFAULT_USER ${PROJECTS_ROOTS:-<roots>}"
            log "ddev database export skipped (--skip-ddev-migration)"
        elif [ "$DDEV_EXPORTED_PRE" = "1" ]; then
            _ddev_mig_gap_warn
            ui_detail "already exported on a previous run (DDEV_EXPORTED=1) — skipping"
            log "ddev database export skipped (DDEV_EXPORTED stamp present)"
        elif ddev_migrate_done "$OPENCODE_USER"; then
            _ddev_mig_gap_warn
            ui_detail "$OPENCODE_USER already has ddev projects registered — skipping the export"
            log "ddev database export skipped (opencode registry already populated)"
        elif [ -z "$PROJECTS_ROOTS" ]; then
            ui_detail "no project roots configured — export skipped (only projects under"
            ui_detail "the registered roots are migrated; see docs/troubleshooting.md)"
            log "ddev database export skipped (no project roots)"
        else
            if [ "$MODE" = "advanced" ] && [ "$INTERACTIVE" = true ]; then
                confirm "Export the dev user's ddev databases before the handover?""\
 (recommended — dumps under /var/backups/opencode-permissions-kit)" || SKIP_DDEV_MIGRATION=true
            fi
            if [ "$SKIP_DDEV_MIGRATION" != true ]; then
                # shellcheck disable=SC2086  # word splitting intended (root list)
                ddev_migrate_export "$DEFAULT_USER" "$OPENCODE_USER" "$OPENCODE_GROUP" $PROJECTS_ROOTS || true
                # Counts and the FAIL list come from the FUNCTION's return
                # state (0.0.44d F1): the export sets them from the
                # authoritative stage copy BEFORE finalize hands the tree
                # to the agent — re-greping the dump-dir manifest here
                # would read an agent-owned file as root (forged content
                # could hide real FAILs past the abort question, or fake
                # OKs; a replaced FIFO would hang). Only the inner project
                # loop runs in a subshell; the function-level DD_MIG_*
                # globals propagate (this block always relied on
                # DD_MIG_DUMP_DIR doing exactly that).
                if [ -n "${DD_MIG_DUMP_DIR:-}" ] && [ -n "${DD_MIG_OK:-}${DD_MIG_FAIL:-}" ]; then
                    if [ "$DD_MIG_OK" -gt 0 ]; then
                        ui_success "ddev databases exported: $DD_MIG_OK ok, $DD_MIG_FAIL failed — $DD_MIG_DUMP_DIR"
                    else
                        ui_warn "ddev database export produced NO dumps ($DD_MIG_FAIL failed)"
                    fi
                    if [ "$DD_MIG_FAIL" -eq 0 ]; then
                        if ! grep -q '^DDEV_EXPORTED=' /etc/opencode-permissions-kit/install.conf 2>/dev/null; then
                            echo "DDEV_EXPORTED=1" | sudo tee -a /etc/opencode-permissions-kit/install.conf >/dev/null
                        fi
                        log "ddev databases exported: ok=$DD_MIG_OK fail=0 dir=$DD_MIG_DUMP_DIR"
                    else
                        # Old production projects sometimes no longer start — their
                        # DBs would be unreachable after the handover. All OTHER
                        # projects were still exported (the loop continues on
                        # failure); now the user decides: fix first (abort — the
                        # handover has not run, the dev side still works) or accept.
                        ui_warn "these projects could NOT be exported (no database dump):"
                        printf '%s\n' "${DD_MIG_FAILLIST:-}" | sed '/^$/d; s/^/     /'
                        ui_detail "once the install continues, their databases are only reachable via"
                        ui_detail "the old daemon — a later dev-side export is impossible (handover)."
                        if [ "$INTERACTIVE" = true ]; then
                            # Convention: agent/conventions.md — default "n":
                            # continuing is the destructive choice here.
                            if ! ui_confirm "Continue the install anyway?""\
 (the listed databases become unreachable)" "n"; then
                                ui_info "Aborted — the .ddev handover did NOT run, your dev-side ddev still works."
                                ui_detail "fix the failed projects (ddev start <name> as $DEFAULT_USER),""\
 then re-run install.sh"
                                ui_detail "dumps already written stay in $DD_MIG_DUMP_DIR"
                                log "install aborted: $DD_MIG_FAIL ddev export(s) failed (user decision) — no handover ran"
                                exit 1
                            fi
                        else
                            ui_warn "continuing (--yes): the listed databases become unreachable"
                        fi
                        log "ddev databases exported: ok=$DD_MIG_OK fail=$DD_MIG_FAIL""\
 dir=$DD_MIG_DUMP_DIR (failures accepted)"
                    fi
                elif [ -n "${DD_MIG_DUMP_DIR:-}" ]; then
                    # dump dir exists but no counts: the export refused
                    # (tamper guard) or died before accounting — the old
                    # code fell back to stale manifest numbers here.
                    ui_warn "ddev database export did not complete — see the REFUSED/failed messages above"
                    ui_detail "fix the cause and re-run install.sh: the export resumes the dump directory"
                    log "ddev export incomplete: no counts returned for $DD_MIG_DUMP_DIR"
                else
                    ui_warn "ddev database export produced no dumps — import manually later if needed"
                    ui_detail "retry after install: sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate""\
 export $DEFAULT_USER $PROJECTS_ROOTS"
                    log "ddev database export produced no dumps"
                fi
            else
                ui_detail "declined — the dev databases become unreachable with the old daemon"
                ui_detail "export manually BEFORE using ddev again:"
                ui_detail "  sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate""\
 export $DEFAULT_USER $PROJECTS_ROOTS"
                log "ddev database export declined (advanced prompt)"
            fi
        fi
    fi
    # Carry a pre-existing stamp over the install.conf rewrite in Step 2 —
    # without this, every second re-install would re-attempt (and fail) the
    # dev-side export.
    if [ "$DDEV_EXPORTED_PRE" = "1" ] &&
        ! grep -q '^DDEV_EXPORTED=' /etc/opencode-permissions-kit/install.conf 2>/dev/null; then
        echo "DDEV_EXPORTED=1" | sudo tee -a /etc/opencode-permissions-kit/install.conf >/dev/null
    fi
}

# --- deploy-phase helper (extracted for unit pinning, #346 wave 3) -------------

# normalize-agents-forms (0.0.44a V1): the semantics inside
# _opk_migrate_one compare the LETTER (`[ "$_opk_ag" = m ]`), the
# flag takes WORDS — the 0.0.43a dispatch fix accepted the words
# but never translated them back, so `--migrate-agents move`
# silently degraded to a copy. Normalize once, before any
# consumer; the dispatch in do_deploy_phase keeps both forms as belt.
install_agents_form_normalize() {
    case "$_opk_ag" in
        m | move) _opk_ag=m ;;
        c | copy) _opk_ag=c ;;
        s | skip) _opk_ag=s ;;
    esac
}

# install_deploy_library (#482 F44, the #376 B5 update twin
# update_redeploy_library): lib_deploy is atomic PER ENTRY only — a
# failed or interrupted deploy over an EXISTING install (re-install)
# leaves a mixed old/new library set behind, previously healed solely
# by re-running (the exact gap #376 closed on the update side). Back
# the deployed tree up into the run's durable BACKUP_DIR (created in
# do_plan_phase) first; a backup that cannot be produced aborts BEFORE
# anything is touched (fail-closed, the update twin's pre-deploy
# doctrine). On a FAILED deploy the mixed tree is moved aside (kept
# for inspection, no rm -rf of a live path) and the pre-install tree
# restored. A fresh install has no previous tree — that arm aborts
# loud too; the partial new tree stays but is inert (the wrapper/cli
# symlinks are only created after this call).
install_deploy_library() {
    if [ -d "$LIBDIR" ] && ! cp -a "$LIBDIR" "$BACKUP_DIR/lib"; then
        ui_error "cannot back up the existing library tree ($LIBDIR) — install aborted, nothing changed"
        exit 1
    fi
    if ! lib_deploy "$SCRIPT_DIR" "$LIBDIR"; then
        if [ -d "$BACKUP_DIR/lib" ]; then
            _ilb_failed="$BACKUP_DIR/lib-failed.$$"
            if mv "$LIBDIR" "$_ilb_failed" 2>/dev/null &&
                cp -a "$BACKUP_DIR/lib" "$LIBDIR"; then
                ui_warn "library deploy FAILED — previous library tree restored"
                ui_detail "the mixed tree is kept for inspection: $_ilb_failed"
                log "lib_deploy failed; library tree restored from $BACKUP_DIR/lib (mixed state: $_ilb_failed)"
            else
                ui_warn "library deploy FAILED and the automatic restore did not complete"
                ui_warn "the pre-install tree is recoverable at $BACKUP_DIR/lib — restore manually:"
                ui_warn "  sudo cp -a $BACKUP_DIR/lib/. $LIBDIR/"
                log "lib_deploy failed; AUTOMATIC RESTORE INCOMPLETE, manual material: $BACKUP_DIR/lib"
            fi
        else
            ui_warn "library deploy FAILED — no previous install existed (partial new tree left; re-run install.sh)"
            log "lib_deploy failed; no rollback material existed (fresh deploy)"
        fi
        ui_error "library deploy failed — install aborted"
        exit 1
    fi
}

# === Phase 3: deploy (Step 5 .. Step 9) =========================================
# Group baseline + ddev handover + git safe.directory, opencode binary +
# wrapper + shell hooks, library/sudoers/browser-bridge deploy, agent
# home + resource migrations + configs (default-user deny-all, TUI),
# stale-runtime cleanup. Moved verbatim except the agents-form normalize
# helper above — see phase 1.

do_deploy_phase() {
    # === Step 5: Filesystem (group baseline) ===

    if [ -n "$PROJECTS_ROOTS" ]; then
        ui_section "Filesystem (group baseline)"
        ans=$(_yes_no_backup_menu "Apply group-$OPENCODE_GROUP, setgid, and default ACLs to project roots?""\
 (changes metadata on ALL files)")
        case "$ans" in
            n) ui_detail "skipping filesystem setup." ;;
            b)
                # shellcheck disable=SC2086  # word splitting intended (root list)
                ui_detail "reading current ACLs with getfacl -R (large trees: this can take minutes) ..."
                # pr-00263 a F8: success line observes the copy (sweep twin
                # of the project-roots site above).
                if getfacl -R $PROJECTS_ROOTS 2>/dev/null >"$BACKUP_DIR/getfacl-R-projects.txt"; then
                    echo "Backup saved."
                else
                    echo "  warn     ACL backup FAILED (getfacl absent or errored) — no ACL recovery material" >&2
                    log "getfacl interactive backup FAILED"
                fi
                ;;
            y) ;;
        esac
        if [ "$ans" != "n" ]; then
            for root in $PROJECTS_ROOTS; do
                # Symlinked root gate (issue #245): the writer refuses
                # links, this is the scan->act recheck (L5) — the
                # baseline passes would silently no-op on a link
                # (measured, issue #245) while this loop prints its
                # success line right below. Before [ -d ] on purpose
                # (review a S3): a dangling link is a symlink first,
                # [ -d ] would swallow it silently.
                if [ -L "$root" ]; then
                    ui_warn "skip $root (symlink — register the target directory instead)"
                    continue
                fi
                [ -d "$root" ] || continue
                # Group baseline via the shared helper: chgrp + setgid +
                # group rw + default ACLs, .git included (issue #17), with a
                # live per-pass progress counter (issue #14 — large trees
                # used to run minutes in silence). The agent user enables
                # the exact per-ancestor traversal probe (roots under a
                # 0750 developer home — see fs_ensure_traversable).
                fs_baseline_root "$root" "$OPENCODE_GROUP" "$OPENCODE_USER"
                ui_success "$root — group + setgid + default ACLs applied"
            done
        fi
        # .ddev + settings-dir handover (ddev always runs as $OPENCODE_USER):
        # ddev chmods .ddev and the app-type's settings directories
        # unconditionally, and chmod is owner-only — they must belong to the
        # opencode user or `ddev start` fails with "operation not permitted"
        # (e.g. "chmod .../config/system"). Searched at ANY depth under each
        # root (a root is often a parent of several projects). Idempotent;
        # .git dirs are never chowned — they stay developer-owned (the group
        # baseline above makes them group-accessible). With the dev-owned
        # mode on (DDEV_DEV_OWNED, see internal/records/ddev-dev-owned-projects.md)
        # the scan instead flags the project and keeps settings dirs + root
        # developer-owned. Advanced mode decides here (Standard/--yes already
        # did, --ddev-settings forces).
        if [ "$DDEV_SETTINGS_GIVEN" != true ] && [ "$INTERACTIVE" = true ] && [ "$MODE" = "advanced" ]; then
            _ds=$(ui_menu "ddev settings management? (dev-owned projects)" "dev-owned" \
                "dev-owned|kit disables it — settings files stay yours, permanent 2775 (recommended)" \
                "ddev|ddev keeps writing CMS settings (handover model)")
            [ "$_ds" = "ddev" ] && DDEV_DEV_OWNED=false
        fi
        for root in $PROJECTS_ROOTS; do
            # Symlinked root gate (review a X1, issue #245): the sibling
            # baseline loop above got its gate first — this loop writes
            # the handover stamp and the "applied" audit line for the
            # SAME root and must refuse it identically. Reachable with
            # no writer check at all: preset-menu selections enter
            # PROJECTS_ROOTS by [ -d ] only, project_path_sane never
            # runs for them. Before [ -d ] for the same S3 reason as
            # the baseline loop (dangling link = symlink first).
            if [ -L "$root" ]; then
                ui_warn "skip $root (symlink — register the target directory instead)"
                continue
            fi
            [ -d "$root" ] || continue
            ddev_handover_root "$root" "$OPENCODE_USER" "$OPENCODE_GROUP" "$DEFAULT_USER"
            ddev_handover_stamp_write "$root" "$OPENCODE_USER" "$OPENCODE_GROUP" "$DEFAULT_USER"
            log "ddev handover applied under $root"
        done
    fi

    # git refuses to work in repositories owned by someone else ("detected
    # dubious ownership") — every project root here IS developer-owned, so the
    # agent's git needs the global exception (issue #17). Idempotent: the get
    # guard prevents duplicate entries on re-install.
    # -C / (issue #116): sudo keeps the invoking user's CWD — run from an
    # unreadable home (the developer's, mode 750), git >= 2.55 dies with
    # "fatal: error reading '<cwd>/.git'" before touching the global config.
    # chdir to / first; --global ignores the worktree anyway.
    # The audit line must match reality (#211 a F4, update.sh twin): a
    # failed --add used to print nothing while the log claimed "ensured".
    if command -v git >/dev/null 2>&1; then
        if sudo -u "$OPENCODE_USER" -H git -C / config --global --get-all safe.directory \
            2>/dev/null | grep -qFx '*'; then
            log "git safe.directory ensured for $OPENCODE_USER (already set)"
        elif sudo -u "$OPENCODE_USER" -H git -C / config --global --add safe.directory '*'; then
            ui_success "git safe.directory '*' set for $OPENCODE_USER (agent git access)"
            log "git safe.directory ensured for $OPENCODE_USER"
        else
            ui_warn "could not set git safe.directory '*' for $OPENCODE_USER — agent git may fail""\
 with 'dubious ownership' (git config --global --add failed)"
            log "git safe.directory NOT ensured for $OPENCODE_USER (git config --add failed)"
        fi
    fi

    # 0.0.49b C1: atomic umask deploy — a plain in-place cp killed
    # mid-write leaves a truncated profile with intact mode bits,
    # sourced at every login (the #163 class on a protection layer).
    # Same shape as the lib deploys (0.0.49a W2): sibling temp in the
    # target dir, mode 644 before the mv (every user's shell must be
    # able to read the profile).
    copy_file_atomic "$SCRIPT_DIR/etc/umask.sh" \
        /etc/profile.d/opencode-permissions-kit-umask.sh 644 ||
        {
            echo "error: umask profile deploy failed" >&2
            exit 1
        }
    log "umask profile installed: /etc/profile.d/opencode-permissions-kit-umask.sh"

    # === Step 6: opencode binary ===

    ui_section "opencode binary + wrapper"

    SYSTEM_BIN="/usr/local/lib/opencode-permissions-kit/bin/opencode"
    # root:$BINARY_GROUP mode 750 (applied by the shared secure_binary
    # helper, sh/secure-binary.sh): lets the opencode user (a group member)
    # run the binary and keeps unrelated users out. It is NOT a
    # developer-side bypass guard: the developer is in the sharing group
    # too and CAN exec this path directly — the soft layer (deny-all
    # config + red theme + warnings) is what deters that, per the kit's
    # declared model.
    BINARY_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"
    # The wrapper warns about a self-installed binary shadowing it from
    # ~/.opencode/bin. Once our secured copy exists, remove the user-local
    # original (backed up first) so the first wrapper run is warning-free.
    remove_shadow_binary() {
        case "$1" in
            */.opencode/bin/opencode) ;;
            *) return 0 ;; # never touch /usr/bin, /usr/local/bin, ...
        esac
        [ -e "$1" ] || return 0
        # pr-00263 a F6 (class sweep): the removal claim names the backup —
        # a failed copy must not be announced as one.
        if cp "$1" "$BACKUP_DIR/opencode-binary" 2>/dev/null; then
            sudo rm -f "$1"
            echo "Removed user-local copy: $1 (backup: $BACKUP_DIR/opencode-binary)"
            log "user-local opencode binary removed: $1 (backed up to $BACKUP_DIR/opencode-binary)"
        else
            _bk_fail "opencode-binary (kept in place)"
        fi
    }
    opencode_found=false

    # Re-install over an existing kit: the secured binary is already in place.
    # Reuse it — do NOT re-run the official installer (its `opencode --version`
    # probe reaches the real binary through the wrapper now and reports
    # "already installed", skipping the download, which would abort here).
    if [ -x "$SYSTEM_BIN" ]; then
        secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"
        opencode_found=true
        ui_detail "binary already secured under the kit — reusing $SYSTEM_BIN"
        log "binary reused on re-install: $SYSTEM_BIN"
    fi

    for loc in "$DEV_HOME/.opencode/bin/opencode" "/root/.opencode/bin/opencode" \
        "/usr/local/bin/opencode" "/usr/bin/opencode"; do
        # Same symlink-aware /usr/local/bin/opencode exclusion as the
        # inventory loop in do_plan_phase (issue #372 I4): the wrapper
        # symlink is never a pickup source; a real file is.
        if [ -x "$loc" ] && { [ "$loc" != "/usr/local/bin/opencode" ] || [ ! -L "$loc" ]; }; then
            ans=$(_yes_no_backup_menu "opencode binary found at $loc. Copy to system path and secure with wrapper?")
            case "$ans" in
                y)
                    sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                    copy_binary_atomic "$loc" "$SYSTEM_BIN" ||
                        {
                            echo "error: copying the opencode binary $loc -> $SYSTEM_BIN failed — aborting" >&2
                            log "binary copy FAILED: $loc -> $SYSTEM_BIN"
                            exit 1
                        }
                    secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"
                    remove_shadow_binary "$loc"
                    opencode_found=true
                    echo "Copied to $SYSTEM_BIN."
                    log "binary copied: $loc -> $SYSTEM_BIN"
                    break
                    ;;
                b)
                    # pr-00263 d W1 (the a F6 class sweep): the branch-b
                    # backup observes the copy — a failed cp degrades the
                    # announce and feeds the summary row, no false claim.
                    if cp "$loc" "$BACKUP_DIR/opencode-binary" 2>/dev/null; then
                        _ocb_bk="Backup saved."
                    else
                        _bk_fail "opencode-binary"
                        _ocb_bk="binary backup FAILED — see Backup summary"
                    fi
                    sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                    copy_binary_atomic "$loc" "$SYSTEM_BIN" ||
                        {
                            echo "error: copying the opencode binary $loc -> $SYSTEM_BIN failed — aborting" >&2
                            log "binary copy FAILED: $loc -> $SYSTEM_BIN"
                            exit 1
                        }
                    secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"
                    remove_shadow_binary "$loc"
                    opencode_found=true
                    echo "Copied to $SYSTEM_BIN. $_ocb_bk"
                    log "binary copied: $loc -> $SYSTEM_BIN ($_ocb_bk)"
                    break
                    ;;
                n)
                    echo "Aborted."
                    exit 1
                    ;;
            esac
        fi
    done

    if [ "$opencode_found" = false ]; then
        if confirm "opencode not found. Run official installer (curl -fsSL https://opencode.ai/v2/install | bash)?"; then
            # pr-00263 a F19: pipefail (set at the top) carries a curl
            # failure through the pipe — the wrapper fires on either a
            # failed fetch or a failed installer run.
            curl -fsSL https://opencode.ai/v2/install | bash ||
                {
                    echo "error: the official opencode installer failed — run it manually:" >&2
                    echo "  curl -fsSL https://opencode.ai/v2/install | bash" >&2
                    exit 1
                }
            # The v2 installer (issue #197): resolves the current 2.x
            # through the npm registry and installs into ~/.opencode/bin —
            # the same layout the v1 installer used, so the pickup paths
            # below are unchanged. When run via the one-liner (sudo bash),
            # it installs into /root/.opencode/bin. Locally it lands in
            # the user's home.
            if [ -x "/root/.opencode/bin/opencode" ]; then
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                copy_binary_atomic "/root/.opencode/bin/opencode" "$SYSTEM_BIN" ||
                    {
                        echo "error: copying the opencode binary /root/.opencode/bin/opencode -> $SYSTEM_BIN failed — aborting" >&2
                        log "binary copy FAILED: /root/.opencode/bin/opencode -> $SYSTEM_BIN"
                        exit 1
                    }
                secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"
                remove_shadow_binary "/root/.opencode/bin/opencode"
                echo "Installed to $SYSTEM_BIN."
                log "binary installed (official installer): /root/.opencode/bin/opencode -> $SYSTEM_BIN"
            elif [ -x "$DEV_HOME/.opencode/bin/opencode" ]; then
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                copy_binary_atomic "$DEV_HOME/.opencode/bin/opencode" "$SYSTEM_BIN" ||
                    {
                        echo "error: copying the opencode binary $DEV_HOME/.opencode/bin/opencode -> $SYSTEM_BIN failed — aborting" >&2
                        log "binary copy FAILED: $DEV_HOME/.opencode/bin/opencode -> $SYSTEM_BIN"
                        exit 1
                    }
                secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"
                remove_shadow_binary "$DEV_HOME/.opencode/bin/opencode"
                echo "Installed to $SYSTEM_BIN."
                log "binary installed (official installer): $DEV_HOME/.opencode/bin/opencode -> $SYSTEM_BIN"
            else
                ui_error "Installation failed. Install opencode manually and re-run."
                exit 1
            fi
        else
            echo "Aborted. Install opencode manually and re-run install.sh."
            exit 1
        fi
    fi

    # Stamp the installed binary's major into install.conf (issue #80): the
    # wrapper gates opencode 2.x-only flags (session `--standalone`) on it.
    # Anchored like the update.sh twins (install_binary's re-stamp and
    # current_opencode_major — 0.0.44f F1): "opencode v<digits>" -> N, a
    # full-line bare digit version -> 1, anything else — an EMPTY probe
    # (wedged binary, issue #80) or noise — leaves the previous stamp
    # untouched instead of overwriting a good 2 with 1; on a fresh install
    # the key stays UNSET and the wrapper detects at runtime. NOTE: sed
    # exits 0 even without a match, so the append must be grep-gated.
    # Bounded probe: every other probe of this binary carries a timeout
    # (wrapper issue #80) — a wedged binary must not hang the installer at
    # the very last step (review 0.0.39b C5). || true inside the
    # substitution (0.0.45c C2): under bash + set -eu + pipefail the
    # timeout kill (rc 124) used to abort the installer rc 124 with ZERO
    # output — post-provisioning, a half install — instead of reaching
    # the keep-the-previous-stamp arm below (which now also covers the
    # hang case, not just an answer-with-noise probe).
    _stamp_ver=$(timeout 10 "$SYSTEM_BIN" --version 2>/dev/null | head -1 || true)
    _stamp_maj=$(printf '%s' "$_stamp_ver" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p')
    if [ -n "$_stamp_maj" ]; then
        : # "opencode v2..." — the 2.x shape
    elif printf '%s' "$_stamp_ver" | grep -qE '^[0-9]+(\.[0-9]+)*$'; then
        _stamp_maj=1 # bare version line = 1.x, full-line anchored
    else
        _stamp_maj="" # unparseable/empty — keep the previous stamp
    fi
    if [ -n "$_stamp_maj" ]; then
        OPENCODE_MAJOR="$_stamp_maj"
        if grep -q '^OPENCODE_MAJOR=' /etc/opencode-permissions-kit/install.conf 2>/dev/null; then
            sudo sed -i "s/^OPENCODE_MAJOR=.*/OPENCODE_MAJOR=$OPENCODE_MAJOR/" /etc/opencode-permissions-kit/install.conf
        else
            echo "OPENCODE_MAJOR=$OPENCODE_MAJOR" | sudo tee -a /etc/opencode-permissions-kit/install.conf >/dev/null
        fi
        log "install.conf stamped: OPENCODE_MAJOR=$OPENCODE_MAJOR"
    else
        # The FILE keeps its previous value (or stays unset — the wrapper
        # detects at runtime); the in-process gate below follows the same
        # value so the 2.x TUI branch matches what the wrapper resolves.
        OPENCODE_MAJOR=$(sed -n 's/^OPENCODE_MAJOR=//p' /etc/opencode-permissions-kit/install.conf \
            2>/dev/null | tail -1 || true)
        OPENCODE_MAJOR="${OPENCODE_MAJOR:-1}"
        ui_warn "opencode version probe unparseable — OPENCODE_MAJOR stamp left unchanged"
        ui_detail "if the binary hangs (issue #80), fix it and re-run install.sh — an unset stamp is detected at runtime"
        log "major stamp skipped: version probe unparseable (resolved OPENCODE_MAJOR=$OPENCODE_MAJOR)"
    fi

    # Stale PATH cleanup (issue #371 A7): the opencode installer appends
    # `export PATH=".../.opencode/bin:$PATH"` lines that keep the
    # user-local binary first in every NEW shell. Only those PATH EXPORT
    # lines are removed — the old sed deleted ANY line mentioning
    # .opencode/bin (aliases, comments included). The rc files are backed
    # up before any edit WHEN THE COPY SUCCEEDS (review a S2, #424): a
    # failed backup records itself and the edit proceeds anyway — the
    # appends below are load-bearing protections (bypass warning, ddev
    # hook) and must not be skipped over a missing recovery copy; the
    # degradation is observed (warn + summary row), never silent. A
    # failed cleanup warns too (issue #371 I3).
    _rc_cleaned=0
    _rc_files=0
    for cf in "$DEV_HOME/.bashrc" "$DEV_HOME/.zshrc" "$DEV_HOME/.profile"; do
        if [ -f "$cf" ]; then
            _rc_files=$((_rc_files + 1))
            if sudo cp "$cf" "$BACKUP_DIR/rc-$(basename "$cf")" 2>/dev/null; then
                :
            else
                _bk_fail "rc-$(basename "$cf")"
            fi
            if sudo grep -q '^[[:space:]]*export PATH=.*[.]opencode/bin' "$cf" 2>/dev/null; then
                if sudo sed -i '\|^[[:space:]]*export PATH=.*[.]opencode/bin|d' "$cf" 2>/dev/null; then
                    _rc_cleaned=$((_rc_cleaned + 1))
                    log "stale .opencode/bin PATH export removed from $cf"
                else
                    ui_warn "could not remove a stale .opencode/bin PATH export from $cf — edit the file yourself"
                    log "rc PATH cleanup FAILED for $cf"
                fi
            fi
            if ! sudo grep -q 'export PATH="/usr/local/bin:$PATH"' "$cf" 2>/dev/null; then
                echo "" | sudo tee -a "$cf" >/dev/null
                echo 'export PATH="/usr/local/bin:$PATH"' | sudo tee -a "$cf" >/dev/null
            fi
            # Interactive-shell bypass warning: sources shell-warn.sh so a
            # self-installed opencode binary is reported in non-login shells too.
            # The [ -f ... ] guard keeps the line harmless after uninstall.
            if ! sudo grep -q 'opencode-permissions-kit/sh/shell-warn.sh' "$cf" 2>/dev/null; then
                echo "[ -f /usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh ] && . ""\
/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh  # opencode permissions kit""\
 (wrapper bypass warning)" | sudo tee -a "$cf" >/dev/null
            fi
            # Interactive-shell ddev function: `ddev` always runs as the opencode
            # user (sudoers helper), so the developer terminal and the agent share
            # one ddev home. The [ -f ... ] guard keeps the line harmless after
            # uninstall. Only the DEFAULT user gets it — the opencode session must
            # never be wrapped (the function's id check would be recursive).
            if ! sudo grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' "$cf" 2>/dev/null; then
                echo "[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . ""\
/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh  # opencode permissions kit""\
 (ddev always runs as opencode)" | sudo tee -a "$cf" >/dev/null
            fi
        fi
    done
    # Honest no-op claim (review a S4, #424): with no rc file at all the
    # loop never ran — the log must not claim updates or installed hooks.
    if [ "$_rc_files" -gt 0 ]; then
        log "shell PATH config updated for $DEFAULT_USER""\
 (stale PATH exports cleaned in $_rc_cleaned rc file(s); wrapper bypass warning + ddev terminal hook installed)"
    else
        log "no rc files found for $DEFAULT_USER (.bashrc/.zshrc/.profile) — no PATH config written"
    fi

    # === Step 7: opencode library (consolidated deployment in /usr/local/lib/opencode-permissions-kit/) ===

    ui_section "Deploying the kit library"

    # Deploy the library via the shared manifest (sh/deploy-lib.sh): the
    # single source of truth for what ships into $LIBDIR — layout, file
    # set and modes live there, enforced against the fetch lists by
    # test-kit-files. The browser-bridge stand-in tree + wsl.conf carrier
    # are applied by browser_bridge_install below, after the library is
    # in place. Tree-level rollback around the deploy (#482 F44):
    # install_deploy_library backs an existing tree up and restores it
    # when lib_deploy fails mid-deploy.
    install_deploy_library
    log "library deployed to $LIBDIR"
    ui_success "kit library deployed: $LIBDIR"

    # Symlink: /usr/local/bin/opencode -> the wrapper (bin/opencode-as-opencode)
    sudo ln -sf "$LIBDIR/bin/opencode-as-opencode" /usr/local/bin/opencode
    ui_success "wrapper installed: /usr/local/bin/opencode -> $LIBDIR/bin/opencode-as-opencode"
    log "wrapper symlink: /usr/local/bin/opencode -> $LIBDIR/bin/opencode-as-opencode"

    # CLI dispatcher: /usr/local/bin/opk -> bin/opk
    sudo rm -f /usr/local/bin/opencode-permissions-kit
    sudo ln -sf "$LIBDIR/bin/opk" /usr/local/bin/opk
    ui_success "cli installed: opk -> $LIBDIR/bin/opk"
    log "cli symlink: /usr/local/bin/opk -> $LIBDIR/bin/opk"

    # OpenChamber policy pin (issue #154): admin-owned file, read by
    # OpenChamber's web server, desktop app, and VS Code extension. Pins
    # their opencode spawn to the kit wrapper — beats the settings pin,
    # env, and PATH, retroactively. root:root 0644 is sufficient
    # (OpenChamber only reads it as the user; live-verified, see the
    # design record).
    # 0.0.47a F1: never overwrite a divergent existing file — admin-owned
    # content is skipped loudly (same rule as update.sh's re-apply).
    # Issue #164: the presence probe runs at the write's authority (sudo),
    # keeping the gate honest if install.sh is ever run outside root.
    if [ "$OPENCHAMBER_POLICY" = yes ]; then
        _oc_expected='{ "opencodeBinary": "/usr/local/bin/opencode" }'
        if sudo test -f /etc/openchamber/policy.json &&
            [ "$(sudo cat /etc/openchamber/policy.json 2>/dev/null)" != "$_oc_expected" ]; then
            ui_warn "existing /etc/openchamber/policy.json diverges from the kit pin"
            ui_warn "(admin-owned content) — left untouched"
            ui_detail "force it with: sudo opk openchamber-secure (replaces the file)"
            log "openchamber policy pin skipped at install: existing file diverges (admin-owned)"
        else
            ui_info "Pinning OpenChamber to the kit wrapper ..."
            sudo mkdir -p /etc/openchamber
            # Atomic stage+mv (#482 F17, install twin of #211 a F17): the
            # live policy.json flips via rename only — a kill mid-tee used
            # to leave a truncated file and a silently inactive pin.
            _ocp_tmp="/etc/openchamber/policy.json.opk-new.$$"
            # Registered BEFORE staging (#211 b W8, order per #211 c W3):
            # the trap's rm -f tolerates an absent path, so an abort DURING
            # the tee (temp created, write fails — ENOSPC under set -e) is
            # covered too, not just aborts between staging and the flip.
            _tmp_track "$_ocp_tmp"
            printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' |
                sudo tee "$_ocp_tmp" >/dev/null
            sudo chown root:root "$_ocp_tmp" 2>/dev/null || true
            sudo chmod 644 "$_ocp_tmp"
            # mv replaces a symlink at policy.json rather than writing
            # through it (#211 b W19) — replaces are this arm's job, the
            # divergent-content case never reaches here.
            sudo mv -f "$_ocp_tmp" /etc/openchamber/policy.json
            ui_success "openchamber policy pin: /etc/openchamber/policy.json"
            log "openchamber policy pin written: /etc/openchamber/policy.json"
        fi
    fi

    # xdg-open fallback (opencode 1.18.33+ / 2.0.18+ login fix): their
    # bundled opener (open@11) falls back to xdg-open when powershell.exe
    # is not executable for the caller — without any xdg-open the device
    # login dies (2.x: uncaught crash). Deploy the kit shim ONLY while
    # no real xdg-open exists (never shadow one) AND the deployed
    # binary still needs it: opencode >= 2.0.32 handles a missing
    # xdg-open itself (upstream #52548, PR #56082; the 1.x line never
    # got the fix — xdg_shim_needed_for in sh/deploy-lib.sh, issue
    # #257). Bounded probe like every sibling (issue #80); an
    # unparseable probe keeps the shim (fail-safe direction). The
    # probe is RAW timeout here, deliberately unlike update-core's
    # two-class gate (review a B6): a broken-but-findable timeout
    # yields an empty probe → keep shim — the conservative direction —
    # while update's gate degrades to the unbounded probe and gets a
    # real verdict; both directions fail safe and mirror each file's
    # neighboring probe idioms.
    _xdi_ver=$(timeout 10 "$SYSTEM_BIN" --version 2>/dev/null | head -1 || true)
    _xdi_maj=$(printf '%s' "$_xdi_ver" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p')
    if [ -z "$_xdi_maj" ] && printf '%s' "$_xdi_ver" | grep -qE '^[0-9]+(\.[0-9]+)*$'; then
        _xdi_maj=1 # bare version line = 1.x, full-line anchored
    fi
    _xdi_trip=$(printf '%s' "$_xdi_ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if ! xdg_shim_needed_for "${_xdi_maj:-}" "$_xdi_trip"; then
        log "xdg-open shim skipped: opencode ${_xdi_trip:-<unparsed>} >= $XDG_SHIM_FIX_VERSION opens without one (#257)"
    elif ! command -v xdg-open >/dev/null 2>&1 &&
        ! [ -e /usr/local/bin/xdg-open ] && ! [ -L /usr/local/bin/xdg-open ]; then
        sudo ln -s "$LIBDIR/bin/xdg-open" /usr/local/bin/xdg-open
        ui_success "xdg-open fallback installed: /usr/local/bin/xdg-open -> $LIBDIR/bin/xdg-open"
        log "xdg-open shim symlink: /usr/local/bin/xdg-open -> $LIBDIR/bin/xdg-open"
    else
        log "xdg-open shim skipped: an xdg-open already exists ($(command -v xdg-open || echo /usr/local/bin/xdg-open))"
    fi

    # sudoers -> /etc/opencode-permissions-kit/sudoers, symlinked as
    # /etc/sudoers.d/opencode-permissions-kit. Shared pipeline
    # (sh/sudoers-deploy.sh): charset gate, render, visudo validation
    # BEFORE anything is deployed, install mode 440, sudoers.d link,
    # legacy-name cleanup. Nothing is deployed unless visudo approves.
    if ! sudoers_deploy "$SCRIPT_DIR/opencode-permissions-kit-lib/templates/sudoers.template" "$DEFAULT_USER"; then
        ui_error "sudoers deployment failed — nothing was deployed (user '$DEFAULT_USER')."
        log "sudoers deployment FAILED (charset gate, render or visudo, user $DEFAULT_USER) — install aborted"
        exit 1
    fi
    ui_success "sudoers installed + validated (/etc/sudoers.d/opencode-permissions-kit)"
    log "sudoers installed: /etc/opencode-permissions-kit/sudoers -> /etc/sudoers.d/opencode-permissions-kit"

    # WSL browser bridge (issues #91, #100): the helper library is always
    # deployed; the stand-in tree only materializes on WSL (the helper no-ops
    # elsewhere). The /etc/wsl.conf carrier is NOT written here — the kit
    # never edits wsl.conf implicitly (internal/records/wsl-conf-consent.md); the
    # user opts in explicitly via 'sudo opk wsl-add-opencode-1-fix'. A legacy
    # 0.0.36 section is stripped (kit-owned regression cleanup).
    # (The helper library itself ships via the lib_deploy manifest above.)
    if browser_bridge_is_wsl; then
        # Failure-honest since 0.0.45c C4: browser_bridge_install propagates
        # a failed stand-in deploy or legacy strip — the old unconditional
        # success line reported "deployed" even when nothing was written.
        if browser_bridge_install "$SCRIPT_DIR" "$LIBDIR"; then
            ui_success "WSL browser bridge stand-in deployed"
        else
            ui_warn "WSL browser bridge: stand-in deploy or legacy wsl.conf strip FAILED"
            ui_detail "see the errors above; re-run the install or fix /etc/wsl.conf manually"
        fi
        if grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null; then
            ui_detail "wsl.conf carrier already present — bridge fully active"
            log "wsl browser bridge stand-in deployed: $LIBDIR/wsl (carrier present)"
        else
            ui_detail "enable the login fix yourself (the kit does not edit /etc/wsl.conf):"
            ui_detail "  sudo opk wsl-add-opencode-1-fix"
            log "wsl browser bridge stand-in deployed: $LIBDIR/wsl (carrier left to 'opk wsl-add-opencode-1-fix')"
        fi
        ui_detail "on a hardened /mnt/c the browser cannot auto-open for the agent;"
        ui_detail "opencode prints URL + code — open them from your own browser"
    else
        log "wsl browser bridge skipped (not WSL)"
    fi

    # === Step 7b: .git/config hardening (optional, SOFT-only) ===

    # Advanced mode asks here (Standard already asked in its question section;
    # --yes runs skip everything).
    if [ "$GIT_FLAG_GIVEN" != true ] && [ "$INTERACTIVE" = true ] && [ "$MODE" = "advanced" ]; then
        if confirm "Block .git/config for opencode? (SOFT-only: opencode tools respect it,""\
 bash-spawned reads are not OS-blocked)"; then
            SECURE_GIT_CONFIG=true
        else
            SECURE_GIT_CONFIG=false
        fi
    fi
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        ui_info "git for the agent: BLOCKED (.git/config deny active, soft-only""\
 — enforced by opencode's permission layer, not the OS)"
    fi

    # === Step 8: opencode Home ===

    # The opencode home belongs to the user's own usergroup; the developer (member
    # of $OPENCODE_GROUP) can enter and edit opencode.jsonc etc. The home inode
    # itself is NOT agent-replaceable (no write on /home) — it stays ungated.
    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode
    sudo chmod 2750 /home/opencode
    # Operand gates (review 0.0.39h F1): chown -R/chmod dereference a symlink
    # OPERAND, and after any completed install every operand below is
    # agent-replaceable — a planted ~/.config -> /etc would recursively hand an
    # arbitrary tree to the agent, chmod 2775 on a linked .config/opencode would
    # make an arbitrary dir world-writable+setgid. Skip each linked operand
    # loudly (user-managed). The walker also covers the PARENT chain of
    # .config/opencode (0.0.39h F2). Each mkdir sits INSIDE its gate too
    # (0.0.39i F1): mkdir -p passes through a linked parent silently — ungated
    # it would plant a root-owned dir in the link target.
    if agent_home_sane "$OPENCODE_USER" /home/opencode/.config; then
        sudo mkdir -p /home/opencode/.config
        # Exec-time recheck (pr-00429 a C3, the _opk_migrate_one twin —
        # the #267 L5 shape): chown -R/chmod dereference the OPERAND
        # (chmod has no -P; measured), and the operand is
        # agent-replaceable — re-walk before acting. Same for the two
        # blocks below (.config/opencode, .agents).
        if agent_home_sane "$OPENCODE_USER" /home/opencode/.config; then
            sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config
            sudo chmod 2775 /home/opencode/.config
        else
            log "agent config dir baseline skipped: /home/opencode/.config turned into a symlink""\
 mid-step (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
        fi
    else
        log "agent config dir skipped: /home/opencode/.config is (below) a symlink (user-managed)""\
 — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
    fi
    if agent_home_sane "$OPENCODE_USER" /home/opencode/.config/opencode; then
        sudo mkdir -p /home/opencode/.config/opencode
        if agent_home_sane "$OPENCODE_USER" /home/opencode/.config/opencode; then
            # Own chown -R (0.0.39j F1): gate 1's `chown -R .config` runs BEFORE
            # this leaf exists on a fresh install — without this chown the dir
            # ends root-owned (live-verified). Write access would survive via the
            # setgid-inherited sharing group (the agent's own primary group,
            # 0.0.39k wording fix), but the agent's config dir must be OWNED by
            # the agent user — like .config and .agents.
            sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config/opencode
            sudo chmod 2775 /home/opencode/.config/opencode
        else
            log "agent config dir baseline skipped: /home/opencode/.config/opencode turned into a""\
 symlink mid-step (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
        fi
    else
        log "agent config dir skipped: /home/opencode/.config/opencode is (below) a symlink""\
 (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
    fi
    if agent_home_sane "$OPENCODE_USER" /home/opencode/.agents; then
        sudo mkdir -p /home/opencode/.agents
        if agent_home_sane "$OPENCODE_USER" /home/opencode/.agents; then
            sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.agents
            sudo chmod 2775 /home/opencode/.agents
        else
            log "agent skills dir baseline skipped: /home/opencode/.agents turned into a symlink""\
 mid-step (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
        fi
    else
        log "agent skills dir skipped: /home/opencode/.agents is (below) a symlink (user-managed)""\
 — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
    fi

    # === Step 8a: migrate the developer's agent resources (issue #19) ==============
    # opencode auto-loads skills from ~/.agents/skills/ and ~/.claude/skills/
    # (plus the same-named dirs up the project tree) — collected in the
    # DEVELOPER's home they are invisible to the agent, which reads
    # /home/opencode. Offer move (recommended — one canonical copy, the
    # developer keeps rw via the sharing group), copy (both sides keep their
    # own, may drift) or skip. The choice is made once and applies to
    # whichever exist.
    #
    # Scope (review 0.0.22): ~/.agents is opencode's OWN directory and
    # migrates WHOLE — everything in it belongs to the agent namespace
    # anyway. ~/.claude is Claude Code's home and carries OAuth tokens
    # (.credentials.json) and account state at its top level — only
    # skills/ crosses (the only part opencode loads), so credentials
    # never reach the agent's group-readable home.
    MIGRATE_AGENT_DIRS=".agents .claude/skills"
    _opk_migrate_one() {
        _opk_src="$DEV_HOME/$1"
        _opk_dst="/home/$OPENCODE_USER/$1"
        [ -d "$_opk_src" ] || return 0
        [ -n "$(ls -A "$_opk_src" 2>/dev/null)" ] || return 0
        # Operand gate (review 0.0.39h F1), covering the whole chain incl. the
        # destination leaf and its parent (~/.claude for .claude/skills):
        # mkdir -p passes through a linked parent silently, cp -a would write
        # developer content THROUGH a linked destination, chown -R would hand
        # the pointed tree to the agent. Skip loudly (user-managed).
        if ! agent_home_sane "$OPENCODE_USER" "$_opk_dst"; then
            ui_warn "agent resources not migrated: the chain to $_opk_dst contains a symlink""\
 (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update) — $_opk_src left untouched"
            log "agents migration skipped: symlink in the chain to $_opk_dst — or the home-sane""\
 gate was unavailable (staged-write.sh incomplete — fix: sudo opk update)"
            return 0
        fi
        sudo mkdir -p "$_opk_dst"
        # Exec-time recheck (#377, review #370 a O2 — the L5 rule, #267
        # shape): the entry gate above classified the chain ONCE, and
        # every operand below is agent-replaceable (/home/opencode
        # belongs to the agent) — a leaf swapped for a dir-symlink in
        # the gate->op window makes the copy write developer content
        # THROUGH the link (live-verified in review #370). Which legs
        # dereference: cp -a AND the chmod OPERANDS (chmod follows a
        # symlink command-line operand — no -P exists; measured,
        # pr-00429 a C2); the find walks stay inside (find never
        # descends a symlinked intermediate), chown -R stays bounded on
        # current coreutils (-P default). Re-run the gate immediately
        # before the copy (it walks the chain again, covering a swapped
        # parent too) and skip loudly on a trip. Accepted residual
        # (pr-00429 a A5, the #267-accepted window class): the mkdir
        # above runs un-rechecked — a parent swapped between the entry
        # gate and it plants one EMPTY root-owned dir in the link
        # target (no content, agent-removable, no escalation).
        if ! agent_home_sane "$OPENCODE_USER" "$_opk_dst"; then
            ui_warn "agent resources not migrated: the chain to $_opk_dst turned into a symlink""\
 before the copy (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update) — $_opk_src left untouched"
            log "agents migration skipped: exec-time recheck tripped for $_opk_dst"
            return 0
        fi
        # cp -a (not mv): merges into the existing target and works when src
        # and dst would collide on a re-install.
        if sudo cp -a "$_opk_src/." "$_opk_dst/" 2>/dev/null; then
            # SECOND exec-time recheck (pr-00429 a C2): the baseline legs
            # below end in chmod OPERANDS that dereference a swapped leaf
            # (the find walks themselves stay inside). A trip skips the
            # baseline loudly — and move mode's source removal waits for
            # the pass arm (pr-00429 b D1): the dev's original survives
            # as recovery, so the re-run remedy below holds for BOTH
            # modes (the entry gate skips a vanished source, and no
            # other code path baselines .claude/skills).
            if ! agent_home_sane "$OPENCODE_USER" "$_opk_dst"; then
                ui_warn "agent resources copied but the sharing baseline was NOT applied:""\
 the chain to $_opk_dst turned into a symlink mid-step (user-managed)""\
 — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
                ui_warn "the original at $_opk_src is untouched — re-run the install to normalize""\
 $_opk_dst"
                log "agents migration: exec-time recheck tripped before the baseline legs for $_opk_dst (source kept)"
            else
                # Sharing baseline: opencode owns, the developer keeps rw
                # through the group (dirs setgid so new files inherit it). The
                # top dir gets the explicit 2775 — mkdir's mode depends on the
                # process umask. Sub-path migrations (.claude/skills) also
                # normalize the parent the kit just created (mkdir -p leaves it
                # root-owned otherwise) — never /home/opencode itself, whose
                # mode 2750 (no world bit) is by design. The parent legs are
                # covered by the recheck above: the walk includes every
                # component of $_opk_dst's chain, $_opk_parent included.
                # ORDER (0.0.45e W1, the 0.0.45c S4 class): the chmod walks
                # run FIRST, while the copied-in tree is still dev-owned —
                # chown-first would walk a just-re-owned, fully agent-writable
                # tree (re-install over a live agent: scan-then-act for a
                # racing agent); chown -R hands over LAST.
                sudo find "$_opk_dst" -type d -exec chmod g+rwxs {} + 2>/dev/null || true
                sudo find "$_opk_dst" -type f -exec chmod g+rw {} + 2>/dev/null || true
                sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" "$_opk_dst"
                sudo chmod 2775 "$_opk_dst"
                case "$1" in
                    */*)
                        _opk_parent="$(dirname "$_opk_dst")"
                        sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "$_opk_parent" 2>/dev/null || true
                        sudo chmod 2775 "$_opk_parent" 2>/dev/null || true
                        ;;
                esac
                # Move-mode source removal runs LAST, after copy AND
                # baseline both succeeded (pr-00429 b D1) — a trip above
                # keeps the dev's original as recovery material.
                [ "$_opk_ag" = m ] && sudo rm -rf "$_opk_src"
                if [ "$_opk_ag" = m ]; then
                    ui_success "agent resources MOVED: $_opk_src -> $_opk_dst (group $OPENCODE_GROUP: both sides read/write)"
                    log "agents migration: moved $_opk_src -> $_opk_dst"
                else
                    ui_success "agent resources COPIED: $_opk_src -> $_opk_dst (group $OPENCODE_GROUP: both sides read/write)"
                    log "agents migration: copied $_opk_src -> $_opk_dst"
                fi
            fi
        else
            # _opk_ag may be a flag-given word (move|copy) or the interactive
            # letter (m|c) — the message must name the action, not the letter
            # (0.0.39e C7).
            _opk_word=$(printf '%s' "$_opk_ag" | sed 's/^m$/move/; s/^c$/copy/')
            ui_warn "could not ${_opk_word} $_opk_src — left untouched"
            log "agents migration failed: $_opk_src"
        fi
    }
    _opk_have_agent_dirs=false
    for _opk_d in $MIGRATE_AGENT_DIRS; do
        [ -d "$DEV_HOME/$_opk_d" ] && [ -n "$(ls -A "$DEV_HOME/$_opk_d" 2>/dev/null)" ] &&
            _opk_have_agent_dirs=true
    done
    if [ "$DEFAULT_USER" != "$OPENCODE_USER" ] && [ "$_opk_have_agent_dirs" = true ]; then
        _opk_ag="${MIGRATE_AGENTS_OPT:-}"
        if [ -z "$_opk_ag" ]; then
            if [ "$INTERACTIVE" = true ]; then
                # ui_menu with a NON-destructive default (0.0.43a F18,
                # conventions.md "install.sh menus"): Enter = Skip. Move —
                # the recommended action — rm -rf's the developer-side
                # sources after the copy; it must never ride on an empty
                # Enter. The explanatory lines stay plain echo >&2 (they
                # are context, not options).
                echo "" >&2
                echo "    Existing agent resources (~/.agents, ~/.claude/skills)" >&2
                printf "    — bring them into /home/%s?\n" "$OPENCODE_USER" >&2
                echo "    (~/.agents moves whole; from ~/.claude only skills/" >&2
                echo "     — credentials like .credentials.json stay in your home)" >&2
                _opk_ag=$(ui_menu "Bring the developer's agent resources over?" "s" \
                    "m|Move — recommended: one canonical copy; you keep read/write via the $OPENCODE_GROUP group" \
                    "c|Copy — duplicate; both sides keep their own copy (may drift)" \
                    "s|Skip — leave them in your home (the agent cannot use them)")
            else
                _opk_ag=m
            fi
        fi
        install_agents_form_normalize
        case "$_opk_ag" in
            m | move | c | copy) for _opk_d in $MIGRATE_AGENT_DIRS; do _opk_migrate_one "$_opk_d"; done ;;
            s | skip)
                ui_detail "skipped: ~/.agents and ~/.claude/skills stay in your home — the agent cannot use them"
                log "agents migration: skipped by choice"
                ;;
        esac
    fi

    # The config writes below target the AGENT-owned ~/.config/opencode: a
    # pre-planted symlink at the destination (dangling or not) would be
    # followed by root cp/chown/chmod. staged_write replaces the link itself
    # with the kit's regular file (review 0.0.39g S1); the backup cp only
    # READS through an existing config and writes into the root-owned
    # backup dir.
    # Parent-chain gate (review 0.0.39h F2): staged_write secures the
    # destination NAME only — a replaced PARENT (~/.config or
    # ~/.config/opencode, agent-replaceable after any completed install)
    # passes `sudo mkdir -p` silently and would redirect the mv below into
    # the link target. Skip loudly (user-managed).
    #
    # 0.0.39h F8: the FINAL content is rendered OFFLINE (template + the
    # SECURE_GIT edit on a scratch copy) and deployed with ONE staged_write —
    # the old sudo sed -i follow-up was a SECOND privileged write on the
    # agent-owned destination; a link swapped in the window between the two
    # would disclose a root-readable file into the agent config.
    _oc_install_agent_config() {
        _oic_tmp=$(mktemp) || return 1
        _tmp_track "$_oic_tmp"
        _oic_mode=off
        [ "$SECURE_GIT_CONFIG" = true ] && _oic_mode=on
        if ! agent_config_render \
            "$SCRIPT_DIR/opencode-permissions-kit-lib/templates/opencode.jsonc" \
            "$_oic_tmp" "$_oic_mode"; then
            rm -f "$_oic_tmp"
            return 1
        fi
        # Explicit rc propagation (issue #371 A4R): the trailing rm must
        # not mask staged_write's exit status for a future tested-context
        # caller — today's bare calls abort under set -e either way.
        if staged_write 664 "$OPENCODE_USER:$OPENCODE_GROUP" "$_oic_tmp" \
            /home/opencode/.config/opencode/opencode.jsonc; then
            rm -f "$_oic_tmp"
            return 0
        else
            _oic_rc=$?
            rm -f "$_oic_tmp"
            return "$_oic_rc"
        fi
    }
    if ! agent_home_sane "$OPENCODE_USER" /home/opencode/.config/opencode; then
        ui_warn "the chain to /home/opencode/.config/opencode contains a symlink — agent config NOT (re)installed""\
 (user-managed; the kit never follows links in the agent home) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)."
        log "agent config skipped: symlink in the parent chain of /home/opencode/.config/opencode""\
 — or the home-sane gate was unavailable (staged-write.sh incomplete — fix: sudo opk update)"
    elif [ ! -f /home/opencode/.config/opencode/opencode.jsonc ] &&
        [ ! -f /home/opencode/.config/opencode/opencode.json ]; then
        _oc_install_agent_config
        if [ "$SECURE_GIT_CONFIG" = true ]; then
            echo "Default config installed (opencode.jsonc) — .git/config blocked (soft)."
        else
            echo "Default config installed (opencode.jsonc)."
        fi
        log "opencode config installed: /home/opencode/.config/opencode/opencode.jsonc (secure_git=$SECURE_GIT_CONFIG)"
    elif [ -f /home/opencode/.config/opencode/opencode.jsonc ] &&
        ! grep -qE '^[[:space:]]*//[[:space:]]*_opencode_permissions_kit|"permission"' \
            /home/opencode/.config/opencode/opencode.jsonc; then
        # User-authored config (issue #372 I6): no kit marker (the
        # template carries one since this change; the grep is anchored
        # to its comment-line form — review a S6, #424: a config merely
        # MENTIONING the kit stays user-authored) and no permission
        # block (the legacy kit-config heuristic — configs written by
        # earlier kit versions). Neither present means the file is not
        # kit-managed — a hand-written config (kept untouched like a
        # custom opencode.json) or broken/unreadable content (kept too;
        # the copy replaces nothing either way — review a G2, #424).
        ui_detail "existing opencode.jsonc has no kit marker and no permission block""\
 — left untouched (user-authored or broken/unreadable content)"
        log "agent config kept: opencode.jsonc without kit marker or permission block (not overwritten)"
    elif [ -f /home/opencode/.config/opencode/opencode.json ] &&
        [ ! -f /home/opencode/.config/opencode/opencode.jsonc ]; then
        ui_detail "opencode.json exists — left untouched (custom user config)"
        log "opencode config kept: custom opencode.json (not overwritten)"
    else
        # Kit-managed opencode.jsonc already exists (re-install): the
        # file carries the kit marker or (legacy configs from earlier
        # kit versions) a permission block — the elif above keeps
        # everything else user-authored. The git choice above must not
        # be silently ignored: re-render from the template with the
        # chosen SECURE_GIT state — same semantics as `config.sh
        # git-config on|off` — with a backup of the previous file.
        if sudo cp /home/opencode/.config/opencode/opencode.jsonc "$BACKUP_DIR/opencode.jsonc-existing" 2>/dev/null; then
            _occ_bk="backup saved"
        else
            _bk_fail "opencode.jsonc-existing"
            _occ_bk="config backup FAILED — see Backup summary"
        fi
        _oc_install_agent_config
        if [ "$SECURE_GIT_CONFIG" = true ]; then
            ui_success "agent config re-applied — .git/config blocked (soft, $_occ_bk)"
        else
            ui_success "agent config re-applied — git allowed ($_occ_bk)"
        fi
        log "opencode config re-rendered with the chosen git setting""\
 (secure_git=$SECURE_GIT_CONFIG, backup attempt: $BACKUP_DIR/opencode.jsonc-existing — $_occ_bk)"
    fi

    # === Step 8b: Default-user config (self-update bypass protection) ===

    # opencode's self-updater / installer can re-add ~/.opencode/bin to PATH, so
    # 'opencode' would run the real binary as $DEFAULT_USER — bypassing the
    # wrapper and the 'opencode' user. Deploy a deny-* config for the default
    # user so that mode is completely locked down.
    DEFAULT_OC_DIR="$DEV_HOME/.config/opencode"
    DEFAULT_OC_CONF="$DEFAULT_OC_DIR/opencode.jsonc"
    sudo mkdir -p "$DEFAULT_OC_DIR"
    if [ -f "$DEFAULT_OC_CONF" ]; then
        # Default y with backup (0.0.43a F19, maintainer re-decision):
        # the deny-all config IS the self-update bypass protection —
        # Standard mode (SKIP_PROMPTS) installs it unconditionally, and
        # the interactive default must not silently skip it either. "yes"
        # is reversible (the previous config is kept as
        # opencode.jsonc_BAK_<timestamp>); declining stays the explicit
        # opt-out it always was.
        if [ "$SKIP_PROMPTS" = true ] ||
            ui_confirm "Default-user config $DEFAULT_OC_CONF already exists.""\
 Back it up as opencode.jsonc_BAK_<timestamp> and install the deny-all config?" "y"; then
            BAK_STAMP=$(date +%Y%m%d-%H%M%S)
            sudo mv "$DEFAULT_OC_CONF" "$DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
            ui_success "default-user config backed up: $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
            log "default-user config backed up: $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
        else
            ui_warn "existing default-user config kept — deny-all protection NOT installed"
        fi
    fi
    if [ ! -f "$DEFAULT_OC_CONF" ]; then
        # Atomic deploy (#482 F19, staged_write — the WRITE shape of the
        # agent config in Step 8a; its agent_home_sane chain gate does
        # NOT apply here, the developer's home is trusted per the
        # staged-write.sh contract, #497 a S1): a plain cp killed
        # mid-write leaves a TRUNCATED deny-all config that this
        # only-if-absent gate then reads as existing — the protection
        # silently inactive until the next INSTALL heals it (the backup
        # arm above, default y; the update twin leaves existing files
        # untouched, so update never heals, #497 a Q1). staged_write
        # flips content, owner and mode in via one mv, closing the
        # truncation window itself; a bare call aborts under set -e
        # (#371 A4R contract).
        staged_write 664 "$DEFAULT_USER:$OPENCODE_GROUP" \
            "$SCRIPT_DIR/opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc" \
            "$DEFAULT_OC_CONF"
        ui_success "deny-all config installed for default user: $DEFAULT_OC_CONF"
        log "deny-all config installed for default user: $DEFAULT_OC_CONF"
    fi

    # === Step 8c: TUI mode display (internal/records/_archive/design/plan-ui-tui-opencode.md) ============
    # Two HOME-keyed effects, no env transport (sudo's env_reset rewrites
    # HOME, the TUI loads its global config from $HOME):
    #   opencode user  -> kit tui.json registers the mode plugin (text row
    #                     in app_bottom: "opencode-permissions-kit Mode:
    #                     with ddev/docker" / "no ddev/docker", live from
    #                     install.conf). The user's own theme choice is
    #                     NEVER touched (no theme key anywhere).
    #   default user   -> red opencode-danger theme (the bypass warning:
    #                     running the ORIGINAL opencode binary as yourself
    #                     defeats the kit's UID separation; deny-all still
    #                     guards, the red is the visible amplifier).
    # Both files carry the _opencode_permissions_kit marker: the kit only
    # writes them if absent or previously kit-written — user edits survive
    # re-installs and updates (same policy as the deny-all config above).
    OC_TUI_DIR="/home/$OPENCODE_USER/.config/opencode"
    OC_TUI_CONF="$OC_TUI_DIR/tui.json"
    # Chain gate BEFORE mkdir -p (review 0.0.39h F2): the [ -L ] gate below
    # checks the destination NAME only — a linked PARENT (~/.config or
    # ~/.config/opencode, agent-replaceable) passes `sudo mkdir -p` silently
    # and would redirect the staged_write mv into the link target. Skip
    # loudly (user-managed). The gate includes the .config/opencode leaf:
    # mkdir -p through a linked leaf redirects the write the same way.
    if ! agent_home_sane "$OPENCODE_USER" "$OC_TUI_DIR"; then
        ui_detail "the chain to $OC_TUI_CONF contains a symlink — TUI mode display NOT installed""\
 (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
        log "tui mode display skipped: symlink in the chain to $OC_TUI_CONF — or the home-sane""\
 gate was unavailable (staged-write.sh incomplete — fix: sudo opk update)"
    else
        sudo mkdir -p "$OC_TUI_DIR"
        # A symlink at the destination is user structure (dotfile setups): never
        # written through (root cp/chown would follow it — 0.0.39g S1), never
        # silently destroyed — same user-managed policy as an unmarked tui.json.
        if [ -L "$OC_TUI_CONF" ]; then
            ui_detail "existing $OC_TUI_CONF is a symlink — TUI mode display NOT installed (user-managed link)"
            log "tui mode display skipped: $OC_TUI_CONF is a symlink (user-managed)"
        elif [ ! -f "$OC_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$OC_TUI_CONF" 2>/dev/null; then
            staged_write 664 "$OPENCODE_USER:$OPENCODE_GROUP" "$LIBDIR/tui/tui.json" "$OC_TUI_CONF"
            ui_success "TUI mode display installed for $OPENCODE_USER: $OC_TUI_CONF (plugin row in the TUI footer)"
            log "tui mode display installed: $OC_TUI_CONF"
        else
            ui_detail "existing $OC_TUI_CONF kept — TUI mode display NOT installed (user-managed file)"
        fi
    fi

    DEFAULT_TUI_CONF="$DEFAULT_OC_DIR/tui.json"
    DEFAULT_THEME_DIR="$DEFAULT_OC_DIR/themes"
    if [ ! -f "$DEFAULT_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$DEFAULT_TUI_CONF" 2>/dev/null; then
        sudo mkdir -p "$DEFAULT_THEME_DIR"
        sudo cp "$LIBDIR/tui/opencode-danger.theme.json" "$DEFAULT_THEME_DIR/opencode-danger.json"
        sudo cp "$LIBDIR/tui/tui-danger.json" "$DEFAULT_TUI_CONF"
        sudo chown -R "$DEFAULT_USER:$OPENCODE_GROUP" "$DEFAULT_THEME_DIR"
        sudo chown "$DEFAULT_USER:$OPENCODE_GROUP" "$DEFAULT_TUI_CONF"
        sudo chmod 664 "$DEFAULT_TUI_CONF" "$DEFAULT_THEME_DIR/opencode-danger.json"
        ui_success "danger theme installed for $DEFAULT_USER: red warning look when the original binary runs as you"
        log "tui danger theme installed: $DEFAULT_TUI_CONF"
    else
        ui_detail "existing $DEFAULT_TUI_CONF kept — TUI mode display NOT installed (user-managed file)"
    fi

    # opencode 2.x (issue #80): the TUI discovers local CLI plugins as
    # DIRECTORIES under ~/.config/opencode/plugins/<name>/ whose tui entrypoint
    # (tui.tsx) is resolved by the host — file paths in cli.json `plugins` are
    # deliberately skipped by the reconciliation, so registering there does
    # nothing. Register the kit-mode-2x.tsx port as a symlinked plugin dir for
    # both users: LIBDIR stays the single source of truth (opk update swaps
    # the file, the TUI's file watcher reloads it). Any file-path kit entries
    # an earlier kit version may have written into cli.json are inert and get
    # unregistered. The tui.json deployment above stays: it is inert under
    # 2.x and makes a later 1.x binary swap work instantly.
    if [ "$OPENCODE_MAJOR" = 2 ]; then
        # Honest closing row (issue #371 A6 + I2/H2): the per-user skip
        # arms (rc 2/3) print their own notes — the old unconditional
        # "registered (both users)" success line claimed registration
        # even when every user was skipped.
        _oc_tps_ok=0
        for _oc_dir_user in "/home/$OPENCODE_USER/.config/opencode:$OPENCODE_USER" "$DEFAULT_OC_DIR:$DEFAULT_USER"; do
            _oc_user_dir="${_oc_dir_user%%:*}"
            _oc_dir_owner="${_oc_dir_user#*:}"
            # Shared per-user sync (sh/tui-plugin.sh): gates + plugin dir +
            # symlink + chowns + inert-entry unregister. Skip reasons are
            # logged by the helper; rc 2/3 surface as user-managed notes,
            # rc 1 aborts like the former inline body did under set -e.
            # Explicit if/elif (0.0.41f C2): a bare `[ … ] && ui_detail`
            # tail would leak status 1 into the loop and make a future
            # reorder silently abort the install.
            if tui_plugin_sync_user "$OPENCODE_MAJOR" "$_oc_user_dir" "$_oc_dir_owner" \
                "$OPENCODE_GROUP" "$LIBDIR" "$OPENCODE_USER"; then
                _oc_tps_ok=$((_oc_tps_ok + 1))
            else
                _oc_tps_rc=$?
                if [ "$_oc_tps_rc" -eq 1 ]; then
                    ui_error "TUI plugin registration failed for $_oc_user_dir — aborting."
                    exit 1
                elif [ "$_oc_tps_rc" -eq 2 ]; then
                    ui_detail "the chain to $_oc_user_dir contains a symlink""\
 — TUI plugin registration skipped (user-managed) — or the home-sane gate was unavailable""\
 (staged-write.sh incomplete — fix: sudo opk update)"
                elif [ "$_oc_tps_rc" -eq 3 ]; then
                    ui_detail "existing $_oc_user_dir/plugins is a symlink""\
 — TUI plugin registration skipped (user-managed link)"
                fi
            fi
        done
        if [ "$_oc_tps_ok" -eq 2 ]; then
            ui_success "TUI mode display registered for opencode 2.x: plugins/opencode-permissions-kit/tui.tsx (both users)"
            log "tui mode registered for 2.x: plugin dir + symlink (kit-mode-2x.tsx)"
        elif [ "$_oc_tps_ok" -eq 1 ]; then
            ui_detail "TUI mode display registered for one user only — the other was skipped (see the note above)"
            log "tui mode registered for 2.x: one user, the other skipped (user-managed)"
        fi
    fi

    # === Step 9: Clean stale runtime state ===
    sudo rm -rf /run/opencode-permissions-kit 2>/dev/null || true
}
