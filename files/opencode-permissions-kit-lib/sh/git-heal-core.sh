# shellcheck shell=sh
# opencode permissions kit -- git-heal-core.sh
#
# The `opk git-heal` subcommand's logic (issue #671): the on/off/status
# toggle for the git heal hooks. The hooks themselves (git-heal/hooks/,
# four identical post-* bodies) re-pin .git/index and .git/HEAD to the
# agent user after every developer git operation that flipped their
# ownership (git lock+rename -- under the sticky .git of the #651 heal
# the agent can never re-take ownership itself, its main-checkout
# workflow locks out). Sourced (never executed) by bin/opk through its
# $LIBDIR (SELF-resolved, checkout-first); the pairing guard in the
# dispatcher refuses a version-skewed pairing.
#
# POSIX sh, no top-level side effects (definitions and comments only).
# The functions run in the CALLER's shell (bin/opk sets set -u only)
# and read the globals the dispatcher sets: LIBDIR, INSTALL_CONF and
# the ui_* helpers. git_heal_cli parses the subcommand BEFORE the sudo
# hop (usage errors need no elevation), then re-enters bin/opk as root
# (loop-guarded, the #479 a F24 shape) and dispatches.
#
# Explicit consent like wsl-add-opencode-1-fix (the issue #100 consent
# family): install/update never activate the hooks -- only `opk git-heal
# on` does. `on` (idempotent):
#   1. verifies the shipped pieces (heal script + four hooks),
#   2. re-renders the sudoers file from the template (the heal grant
#      line ships there; an install older than #671 would not carry
#      it yet -- this closes that gap without waiting for a kit
#      update),
#   3. sets the developer's global core.hooksPath to the kit hook dir
#      (repo hooks stay disabled for the developer -- the same
#      protective effect secure-git-config.md documents for the
#      /dev/null form, plus the heal),
#   4. heals every kit-managed gitdir once: enumerates every .git
#      under the conf roots RECURSIVELY (roots are scan roots like
#      /var/www/vhosts, the config.sh parent-registration shape --
#      depth-1 <root>/.git would find nothing), after re-validating
#      every conf line reader-side (the files.md root-op contract,
#      #674 a A1: the uninstall-core reader mirror -- a hand-edited
#      system/scratch/agent-home line never steers the root sweep).
# `off` removes ONLY the kit-owned hooksPath value (a foreign value is
# never touched) and leaves the sudoers grant in place (narrow,
# nothing invokes it without the hooksPath). `status` reports the
# state, the pieces and the per-root lockout situation.
#
# Test overrides (unit suite only, never set in production):
#   GH_SUDO     privileged-drop prefix (default sudo; "" runs the
#               developer-side git calls in place)
#   GH_LIBDIR   library base (default $LIBDIR, literal fallback)
#   GH_DEV_HOME developer home (default: getent on the install.conf
#               DEFAULT_USER; the override keeps unit tests off real
#               homes -- the sandbox policy forbids touching /home)

# _ghc_libdir: the library base everything below resolves against.
_ghc_libdir() {
    printf '%s' "${GH_LIBDIR:-${LIBDIR:-/usr/local/lib/opencode-permissions-kit}}"
}

# _ghc_key <key>: read one key from install.conf (doctor-style sed,
# never a source of a root-owned file).
_ghc_key() {
    sed -n "s/^$1=//p" "$INSTALL_CONF" 2>/dev/null | tail -n 1
}

# _ghc_devuser: the developer username; loud empty on a missing key
# (this is a kit-machine command, install.conf must exist).
_ghc_devuser() {
    _ghc_du=$(_ghc_key DEFAULT_USER)
    if [ -z "$_ghc_du" ]; then
        ui_error "DEFAULT_USER not found in $INSTALL_CONF — is the kit installed?"
        exit 1
    fi
    printf '%s' "$_ghc_du"
}

# _ghc_agentuser: the agent username (OPENCODE_USER, canonical
# fallback like every kit lib).
_ghc_agentuser() {
    _ghc_au=$(_ghc_key OPENCODE_USER)
    printf '%s' "${_ghc_au:-opencode}"
}

# _ghc_devhome <devuser>: home via getent (relocated homes included).
# GH_DEV_HOME is the unit-suite override (sandbox: never touch /home).
_ghc_devhome() {
    if [ -n "${GH_DEV_HOME:-}" ]; then
        printf '%s' "$GH_DEV_HOME"
        return 0
    fi
    getent passwd "$1" 2>/dev/null | cut -d: -f6 || true
}

# _ghc_devgit <devuser> <devhome> <git-args...>: git AS THE DEVELOPER.
# The sudo hop drops to the user with the right HOME; the unit override
# (GH_SUDO set-and-empty) runs git in place with the scratch HOME --
# the -u/env prefix only exists on the sudo leg (an empty expansion
# would otherwise turn -u into the command word).
_ghc_devgit() {
    _gd_user="$1"
    _gd_home="$2"
    shift 2
    if [ -n "${GH_SUDO+x}" ] && [ -z "${GH_SUDO:-}" ]; then
        HOME="$_gd_home" git "$@"
    else
        ${GH_SUDO-sudo} -u "$_gd_user" env HOME="$_gd_home" git "$@"
    fi
}

# _ghc_hooksdir: the kit hook directory core.hooksPath must point at.
_ghc_hooksdir() {
    printf '%s/git-heal/hooks' "$(_ghc_libdir)"
}

# _ghc_dev_hooks_path <devuser>: the developer's current global
# core.hooksPath value ('' when unset or the gitconfig unreadable).
_ghc_dev_hooks_path() {
    _ghc_dh=$(_ghc_devhome "$1")
    [ -n "$_ghc_dh" ] || return 0
    git config -f "$_ghc_dh/.gitconfig" core.hooksPath 2>/dev/null || true
}

# _ghc_state: echoes on | off | foreign | unknown. `foreign` means a
# hooksPath WE did not set (left untouched by `off`, warned about in
# `status`); `unknown` means the developer's gitconfig cannot be read.
_ghc_state() {
    _ghc_st_dev=$(_ghc_devuser)
    _ghc_st_home=$(_ghc_devhome "$_ghc_st_dev")
    [ -n "$_ghc_st_home" ] || {
        echo unknown
        return 0
    }
    _ghc_st_gc="$_ghc_st_home/.gitconfig"
    [ -r "$_ghc_st_gc" ] || {
        echo unknown
        return 0
    }
    _ghc_st_cur=$(_ghc_dev_hooks_path "$_ghc_st_dev")
    if [ -z "$_ghc_st_cur" ]; then
        echo off
    elif [ "$_ghc_st_cur" = "$(_ghc_hooksdir)" ]; then
        echo on
    else
        echo foreign
    fi
}

# _ghc_pieces_ok: rc 0 when heal script + all four hooks exist in the
# library (version-skew guard -- `on` refuses to activate half a kit).
_ghc_pieces_ok() {
    _ghc_pc_dir="$(_ghc_libdir)/git-heal"
    [ -f "$_ghc_pc_dir/heal-index-head" ] || return 1
    [ -d "$_ghc_pc_dir/hooks" ] || return 1
    for _ghc_pc_h in post-merge post-checkout post-rewrite post-index-change; do
        [ -f "$_ghc_pc_dir/hooks/$_ghc_pc_h" ] || return 1
    done
    return 0
}

# _ghc_heal_once <gitdir>: run the root heal on one gitdir (already
# root here; GH_* env overrides pass through for the unit suite).
_ghc_heal_once() {
    "$(_ghc_libdir)/git-heal/heal-index-head" "$1"
}

# _ghc_root_ok <line>: reader-side conf-line gate for the on-sweep
# (files.md contract — every consumer that runs root operations over
# the roots re-validates each line; the uninstall-core reader mirror,
# #674 a A1). rc 0: usable root, trailing-slash-stripped form in
# _ghc_root_norm. rc 1: refused, form (non-absolute, dot/empty
# segment, whitespace); rc 2: refused, agent home; rc 3: refused,
# system path (incl. the bare "/" that strips to empty, #674 b D1) —
# the caller maps each rc to its skip line.
# The system-path and agent-home arms sit behind GH_CONF_RELAX (unit
# scratch zones live under /tmp); the form arms never relax.
_ghc_root_ok() {
    _ghc_ro="$1"
    case "$_ghc_ro" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$_ghc_ro" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]*) return 1 ;;
    esac
    while :; do
        case "$_ghc_ro" in
            */) _ghc_ro="${_ghc_ro%/}" ;;
            *) break ;;
        esac
    done
    # "/" strips to empty: rc 3 (system path), never the generic rc 1
    # form message — "/" is absolute and not malformed (#674 b D1).
    [ -n "$_ghc_ro" ] || return 3
    if [ "${GH_CONF_RELAX:-}" != "1" ]; then
        _ghc_ah=$(getent passwd "$(_ghc_agentuser)" 2>/dev/null | cut -d: -f6) ||
            true
        if [ "$_ghc_ro" = "/home/$(_ghc_agentuser)" ] ||
            { [ -n "$_ghc_ah" ] && [ "$_ghc_ro" = "$_ghc_ah" ]; }; then
            return 2
        fi
        case "$_ghc_ro" in
            # The writer's FHS-complete blocklist (sh/path-sane.sh
            # project_path_sane — same arms as every reader mirror).
            / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
                /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
                /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /tmp | /tmp/* | /var/tmp/* | \
                /usr | /usr/* | /var | /var/tmp | /var/account | /var/account/* | /var/backups | \
                /var/backups/* | /var/cache | /var/cache/* | /var/crash | /var/crash/* | /var/games | \
                /var/games/* | /var/lib | /var/lib/* | /var/local | /var/local/* | /var/lock | \
                /var/lock/* | /var/log | /var/log/* | /var/mail | /var/mail/* | /var/opt | \
                /var/opt/* | /var/run | /var/run/* | /var/spool | /var/spool/* | /var/yp | /var/yp/*)
                return 3
                ;;
        esac
    fi
    _ghc_root_norm="$_ghc_ro"
    return 0
}

_git_heal_on() {
    _ghc_on_dev=$(_ghc_devuser)
    _ghc_on_home=$(_ghc_devhome "$_ghc_on_dev")
    if [ -z "$_ghc_on_home" ] || [ ! -d "$_ghc_on_home" ]; then
        ui_error "git-heal: no home for user $_ghc_on_dev — cannot set core.hooksPath"
        exit 1
    fi
    if ! _ghc_pieces_ok; then
        ui_error "git-heal: heal hooks incomplete under $(_ghc_libdir)/git-heal — run 'opk update' first"
        exit 1
    fi
    # Sudoers first: without the grant the hooks would fire but the
    # heal could never elevate (a kit installed before #671 carries a
    # template without the line). Sudoers_deploy validates with visudo
    # and stages atomically; it refuses loud on any failure.
    if [ -f "$(_ghc_libdir)/sh/sudoers-deploy.sh" ] &&
        [ -f "$(_ghc_libdir)/templates/sudoers.template" ]; then
        # shellcheck disable=SC1090
        SD_SUDO="" . "$(_ghc_libdir)/sh/sudoers-deploy.sh" ||
            {
                ui_error "git-heal: could not source sudoers-deploy.sh"
                exit 1
            }
        if ! SD_SUDO="" sudoers_deploy "$(_ghc_libdir)/templates/sudoers.template" "$_ghc_on_dev"; then
            ui_error "git-heal: sudoers re-render failed — nothing else was changed"
            exit 1
        fi
    else
        ui_error "git-heal: sudoers-deploy.sh or sudoers.template missing under $(_ghc_libdir) — run 'opk update' first"
        exit 1
    fi
    ui_info "Setting the developer's global core.hooksPath to the kit heal hooks ..."
    if ! _ghc_devgit "$_ghc_on_dev" "$_ghc_on_home" \
        config --global core.hooksPath "$(_ghc_hooksdir)"; then
        ui_error "git-heal: could not write core.hooksPath for $_ghc_on_dev"
        exit 1
    fi
    # Heal every kit-managed gitdir once: enumerate the .git dirs
    # under each projects.conf root (the same universe the hook
    # allowlist covers — roots are SCAN roots like /var/www/vhosts,
    # not project dirs, so depth-1 would find nothing), with every
    # conf line re-validated reader-side first (files.md contract,
    # #674 a A1). No path-sane sourcing here by design: the reader
    # mirror is the house shape (uninstall-core, update-core, config
    # refresh, bin/opk handover all ship inline mirrors).
    _ghc_on_conf="${GH_PROJECTS_CONF:-/etc/opencode-permissions-kit/projects.conf}"
    if [ -f "$_ghc_on_conf" ]; then
        _ghc_on_list=$(mktemp) || {
            ui_error "git-heal: mktemp failed — cannot enumerate heal targets"
            exit 1
        }
        while IFS= read -r _ghc_on_root; do
            case "$_ghc_on_root" in '' | '#'*) continue ;; esac
            _ghc_rk_rc=0
            _ghc_root_ok "$_ghc_on_root" || _ghc_rk_rc=$?
            if [ "$_ghc_rk_rc" -ne 0 ]; then
                case "$_ghc_rk_rc" in
                    2) _ghc_on_why="agent home is never a project root" ;;
                    3) _ghc_on_why="system path is never a project root" ;;
                    *) _ghc_on_why="not an absolute root, or malformed (dot, empty segment, or whitespace)" ;;
                esac
                ui_detail "skip (conf): $_ghc_on_why: $_ghc_on_root"
                continue
            fi
            _ghc_on_root="$_ghc_root_norm"
            [ -d "$_ghc_on_root" ] || continue
            find "$_ghc_on_root" -type d -name .git >>"$_ghc_on_list" 2>/dev/null || true
        done <"$_ghc_on_conf"
        while IFS= read -r _ghc_on_gd; do
            if _ghc_heal_once "$_ghc_on_gd"; then
                # rc-true is "the heal ran", not "every chown
                # succeeded": the heal exits 0 even when an operand's
                # chown failed (it must never break a git op), so the
                # detail line names the run, not a per-file result
                # (#674 a A2 — the audit log carries those).
                ui_detail "heal ran for $_ghc_on_gd"
            else
                ui_detail "heal skipped for $_ghc_on_gd (see messages above)"
            fi
        done <"$_ghc_on_list"
        rm -f "$_ghc_on_list"
    fi
    ui_success "git heal hooks active — developer git operations now re-pin"
    ui_success ".git/index and .git/HEAD to the agent user (repo hooks stay"
    ui_success "off for the developer; hooksPath=$(_ghc_hooksdir))"
}

_git_heal_off() {
    _ghc_off_dev=$(_ghc_devuser)
    _ghc_off_home=$(_ghc_devhome "$_ghc_off_dev")
    if [ -z "$_ghc_off_home" ] || [ ! -d "$_ghc_off_home" ]; then
        ui_error "git-heal: no home for user $_ghc_off_dev — cannot unset core.hooksPath"
        exit 1
    fi
    _ghc_off_cur=$(_ghc_dev_hooks_path "$_ghc_off_dev")
    if [ "$_ghc_off_cur" = "$(_ghc_hooksdir)" ]; then
        if _ghc_devgit "$_ghc_off_dev" "$_ghc_off_home" \
            config --global --unset core.hooksPath; then
            ui_success "git heal hooks off — core.hooksPath unset for $_ghc_off_dev"
        else
            ui_error "git-heal: could not unset core.hooksPath for $_ghc_off_dev"
            exit 1
        fi
    elif [ -z "$_ghc_off_cur" ]; then
        ui_success "git heal hooks already off (no core.hooksPath set)"
    else
        # Kit-owned bytes only (the issue #100 consent discipline): a
        # foreign value is never modified, only reported.
        ui_success "git heal hooks off — core.hooksPath holds a foreign value"
        ui_detail "($_ghc_off_cur) — left untouched"
    fi
}

_git_heal_status() {
    _ghc_stt_dev=$(_ghc_devuser)
    _ghc_stt_agent=$(_ghc_agentuser)
    _ghc_stt_state=$(_ghc_state)
    case "$_ghc_stt_state" in
        on)
            ui_info "git-heal: ON — heal hooks active (core.hooksPath=$(_ghc_hooksdir))"
            ;;
        off)
            ui_info "git-heal: OFF — run 'sudo opk git-heal on' to keep the agent's"
            ui_info "        main-checkout git workflow (git add / git switch) green"
            ;;
        foreign)
            # Same state word the opk status / doctor rows render for a
            # foreign hooksPath ("OFF — ...", #674 a C6): one vocabulary
            # across the two surfaces the how-to documents as parallel.
            ui_info "git-heal: OFF — core.hooksPath holds a foreign value"
            ui_info "        ($(_ghc_dev_hooks_path "$_ghc_stt_dev")) — heal hooks not in effect;"
            ui_info "        'sudo opk git-heal on' would retake the path"
            ;;
        unknown)
            ui_info "git-heal: UNKNOWN — cannot read the developer's gitconfig"
            ;;
    esac
    if _ghc_pieces_ok; then
        ui_detail "kit pieces present (heal script + four hooks)"
    else
        ui_detail "kit pieces INCOMPLETE under $(_ghc_libdir)/git-heal — run 'opk update'"
    fi
    # Per-gitdir lockout rows: dev-owned index/HEAD under a sticky .git
    # lock the agent out until the heal hooks fire (off/foreign) or
    # the next developer git operation re-pins them (on: transient —
    # the same classification the opk status / doctor rows render,
    # #674 a C7). The enumeration mirrors the on-sweep's RECURSION
    # (#674 a C3: every .git under each conf root — conf roots are
    # scan roots, config.sh parent registration; the literal
    # <root>/.git would miss every nested repo), deliberately NOT its
    # conf-line reader gate (#674 b D2): status is display-only, no
    # root operation — it renders the conf as written, so a
    # hand-edited line the sweep refuses loudly can still show rows
    # here (a bounded display residual; the sanctioned writer refuses
    # such lines, and the rows say something is off).
    _ghc_stt_conf="${GH_PROJECTS_CONF:-/etc/opencode-permissions-kit/projects.conf}"
    [ -f "$_ghc_stt_conf" ] || return 0
    # Loud but never fatal (#674 b D3): status must not die, but a
    # swallowed mktemp failure would silently drop the lockout rows
    # this section exists to show (the on-sweep twin fails loud).
    _ghc_stt_list=$(mktemp) || {
        ui_detail "git-heal: lockout rows unavailable (mktemp failed)"
        return 0
    }
    while IFS= read -r _ghc_stt_root; do
        case "$_ghc_stt_root" in '' | '#'*) continue ;; esac
        [ -d "$_ghc_stt_root" ] || continue
        # Loud on partial failure (#674 c E4): an unreadable subtree
        # silently loses its lockout rows otherwise — one notice per
        # affected root keeps the section honest (find rc 1 = errors
        # encountered, output still collected).
        find "$_ghc_stt_root" -type d -name .git >>"$_ghc_stt_list" 2>/dev/null ||
            ui_detail "git-heal: lockout rows may be incomplete under $_ghc_stt_root (unreadable)"
    done <"$_ghc_stt_conf"
    while IFS= read -r _ghc_stt_gd; do
        [ -n "$_ghc_stt_gd" ] || continue
        for _ghc_stt_f in index HEAD; do
            _ghc_stt_own=$(stat -c %U "$_ghc_stt_gd/$_ghc_stt_f" 2>/dev/null) || continue
            if [ "$_ghc_stt_own" != "$_ghc_stt_agent" ]; then
                if [ "$_ghc_stt_state" = on ]; then
                    ui_detail "lockout (transient — the next developer git operation"
                    ui_detail "heals it): $_ghc_stt_gd/$_ghc_stt_f is $_ghc_stt_own-owned"
                else
                    ui_detail "lockout risk: $_ghc_stt_gd/$_ghc_stt_f is $_ghc_stt_own-owned —"
                    ui_detail "'sudo opk git-heal on' heals and keeps it healed"
                fi
            fi
        done
    done <"$_ghc_stt_list"
    rm -f "$_ghc_stt_list"
}

git_heal_cli() {
    _ghc_cmd="${1:-}"
    [ $# -gt 0 ] && shift
    if [ "$_ghc_cmd" != "on" ] && [ "$_ghc_cmd" != "off" ] &&
        [ "$_ghc_cmd" != "status" ]; then
        ui_error "usage: opk git-heal <on|off|status>"
        exit 64
    fi
    [ $# -eq 0 ] || {
        ui_error "usage: opk git-heal <on|off|status>"
        exit 64
    }
    if [ "$(id -u)" -ne 0 ]; then
        # Loop guard (#479 a F24, the openchamber shape): the re-exec
        # enters bin/opk again, which dispatches back into this arm --
        # a sudo that exits 0 without actually elevating (fake or
        # broken sudo) would exec this cycle forever. Refuse on the
        # marker the re-exec itself carries.
        if [ "${OPK_GITHEAL_ROOT:-}" = "1" ]; then
            ui_error "git-heal: sudo did not elevate — giving up"
            exit 1
        fi
        exec ${GH_SUDO-sudo} env OPK_GITHEAL_ROOT=1 sh "$(_ghc_libdir)/bin/opk" git-heal "$_ghc_cmd"
    fi
    # Running as root from here.
    case "$_ghc_cmd" in
        on) _git_heal_on "$@" ;;
        off) _git_heal_off "$@" ;;
        status) _git_heal_status "$@" ;;
    esac
}
