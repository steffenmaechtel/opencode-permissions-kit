# shellcheck shell=sh
# opencode permissions kit -- uninstall-core.sh
#
# The uninstall run's section logic (issue #346, wave 4): every removal
# section of management/uninstall.sh as functions -- pure code movement,
# user-visible output byte-identical (the entry calls them in the former
# statement order; --debug xtrace adds the sourcing/call lines --
# diagnostics, not output). Sourced (never executed) by uninstall.sh via
# a candidate list
# like update.sh's UPDATE_CORE -- checkout-first (readlink -f-resolved
# $0 → ../sh, the checkout or the DEPLOYED tree `opk uninstall` execs), then the
# deployed $LIBDIR fallback, loud abort when both miss (the #165 class:
# no silent section drops). This differs DELIBERATELY from install.sh's
# kit_source-without-fallback: install.sh never runs from the installed
# tree (re-deploys go through update.sh), while uninstall.sh regularly
# runs from the deployed library -- update.sh's resolver shape is the
# honest model here.
#
# POSIX sh, no top-level side effects (definitions and comments only).
# The functions run in the CALLER's shell (uninstall.sh sets no set -e)
# and read the globals the entry sets before the section calls: YES,
# DRY_RUN (arg loop), DEFAULT_USER, OPENCODE_USER (initialized
# "opencode"), OPENCODE_GROUP, RED/GREEN/YELLOW/NC, DEBUG (trace).
# un_context_load re-stamps OPENCODE_USER/OPENCODE_GROUP (install.conf
# + the shape gate) and resolves UN_OC_UID/UN_OC_GID/UN_DEV_GROUP/
# UN_DEV_GID -- the later sections read those (the id capture precedes
# userdel on purpose, issue #74). un_projects_revert additionally reads
# UNINSTALL_PROJECTS_CONF (the entry sets it and guards the call with
# the conf's existence check). un_rc_q maintains the shared
# _un_partial/_un_revert_failed state every section resets and closes
# over. Functions here call the entry's helpers (trace; log -- the
# entry's stub or its sourced sh/log.sh) and the entry-sourced sh/ libs
# (browser_bridge_remove from sh/wsl-browser-bridge.sh, agent_home_sane
# from sh/staged-write.sh -- stub-or-real per the entry's candidate
# loops), plus externals (sudo, id, getent, find, setfacl, chmod ...).
#
# The wrapped sections are NOT new logic: their bodies are the exact
# blocks tests/unit/test-uninstall.sh used to extract by anchors (#346
# wave 4 pays #396 back -- the pins source this lib and call the
# functions); bodies keep the block content with 4 spaces more indent,
# nothing else moved. un_projects_revert keeps its loop verbatim at the
# former nesting (the entry's `if [ -f ... ]` guard equals the
# function's base indent).

prompt_yn() {
    # prompt_yn "message" default
    # Returns "y" or "n"
    # Prompt convention: agent/conventions.md — [Y/n] / [y/N],
    # default as capital letter, Enter accepts it; unknown input
    # falls back to the default (issue #187 A — same semantics as
    # ui.sh's ui_confirm since the 0.0.44a V17 fix; this standalone
    # sibling was missed by that sweep). The un-prefixed reads trim
    # edge whitespace — the shared answer pipeline since #189 a W2
    # (a padded " y" is an explicit y in every implementation).
    local msg="$1" default="$2"
    local hint="[y/N]"
    [ "$default" = "y" ] && hint="[Y/n]"
    if [ "$YES" = true ]; then
        trace "prompt '$msg' -> yes (--yes)"
        echo "y"
        return
    fi
    if ! [ -t 0 ] && ! (exec </dev/tty) 2>/dev/null; then
        echo "${RED}No terminal available. Run interactively or use --yes to skip prompts.${NC}" >&2
        exit 1
    fi
    printf '  %s %s ' "$msg" "$hint" >&2
    trace "prompt '$msg': waiting for input"
    read -r answer </dev/tty 2>/dev/null || read -r answer
    trace "prompt '$msg': got '$answer'"
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
        y | yes) echo "y" ;;
        n | no) echo "n" ;;
        *) [ "$default" = "y" ] && echo "y" || echo "n" ;;
    esac
}

# Direct invocation only — no eval, no `sh -c` (agent/conventions.md).
# Output and failures are silenced (the former "cmd 2>/dev/null || true"
# call sites — best-effort cleanup). pr-00263 e W3: the unsilenced run()
# helper was removed here — its last two callers went to un_rc_q (#246
# site 7); run_q keeps its callers.
run_q() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

# rc-observing runner for the per-root revert loop (#218) and the
# config-dirs removal (#243 a S1/S2): run_q ends in `|| true` by
# design, so a closing log could claim "reverted + removed" over ops
# that failed (revert loop: find-chown, setfacl x2, chmod g-s — four
# call sites, six invocations when both gids are known). Same [DRY]
# echo and same silence as run_q, but a failure records the op label
# in the caller's partial list — the closing log then degrades to
# PARTIALLY with the failed ops named, plus a stderr WARN and a
# FAILED log line where the caller arms them (gpasswd/userdel arm
# pattern, #211 b W1/c W1; f W2 naming form). Label first, command
# after. Renamed from un_revert_q (#243 b Q4): it observes rc for the
# revert loop AND the config-dirs removal — the name must not claim
# "revert" only.
un_rc_q() { # <op label> <command...>
    _un_rc_label="$1"
    shift
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    elif ! "$@" >/dev/null 2>&1; then
        _un_revert_failed=1
        _un_partial="${_un_partial:+$_un_partial, }$_un_rc_label failed"
    fi
}

# Shape-gate the sourced value (#243 e X1, tightened #243 f X1):
# install.conf is root-owned but hand-editable, and the writer stamps
# a literal here (install.sh sets OPENCODE_USER="opencode" and its
# conf heredoc carries that literal — the writer's charset gate
# covers DEFAULT_USER, not this name). A shape-invalid value (e.g. a
# trailing slash) would silently defang the agent-home refusal in the
# project loop and the agents-backup walk below — fall back to the
# canonical literal, loudly. Charset: the writer's conservative set
# MINUS leading dot/hyphen and trailing dot (deliberate divergence
# from writer parity, #243 f X1): `.`, `..`, `opencode.`, `-x`, `--`
# are not agent names, and a leading `-` is also an option-injection
# shape into the id/userdel argv below; the writer never produces
# any of them, so no legit value is refused. A merely DIFFERENT
# valid name still passes by design (the conf is the source of truth
# for a customized agent; the mismatch residual is recorded in the
# review chain, snapshot f).
# (Wrapped as a function for unit pinning, #346 wave 4; called by
# un_context_load right after install.conf is sourced.)
un_opencode_user_gate() {
    case "$OPENCODE_USER" in
        '' | *[!A-Za-z0-9_.-]* | [.-]* | *[.])
            # pr-00263 a F9: sanitized echo — a corrupted value (newline/
            # escape bytes) must not forge transcript lines.
            _ou_bad="$(printf '%s' "$OPENCODE_USER" | tr -c 'A-Za-z0-9_.-' '?')"
            echo "WARN: invalid OPENCODE_USER value in install.conf ('$_ou_bad') — falling back to 'opencode'" >&2
            OPENCODE_USER=opencode
            ;;
    esac
}

# install.conf sourcing + sharing-group/kit-id context: the entry
# calls this before the first prompt (see the body comments).
un_context_load() {
    # Source install.conf (canonical path since 0.0.10).
    INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
    if [ -f "$INSTALL_CONF" ]; then
        trace "sourcing $INSTALL_CONF"
        . "$INSTALL_CONF"
    fi
    OPENCODE_USER="${OPENCODE_USER:-opencode}"
    un_opencode_user_gate
    # Sharing group: the opencode user's own usergroup; prefer the live value.
    OPENCODE_GROUP="${OPENCODE_GROUP:-opencode}"
    LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
    if [ -n "$LIVE_GROUP" ]; then
        OPENCODE_GROUP="$LIVE_GROUP"
    fi
    # Kit-user ids, captured BEFORE the user removal below: once userdel ran,
    # project files still owned by opencode carry an ORPHANED uid — the
    # ownership revert in the project section below can only match those
    # numerically (issue #74). UN_DEV_GROUP feeds the chown revert (the
    # developer's own login group — the kit's sharing group dies with the
    # opencode user); the ACL revert uses the NUMERIC gids below (0.0.42g
    # D3: names can stop resolving mid-run, gids never do).
    UN_OC_UID=$(id -u "$OPENCODE_USER" 2>/dev/null || true)
    UN_OC_GID=$(id -g "$OPENCODE_USER" 2>/dev/null || true)
    UN_DEV_GROUP=$(id -gn "$DEFAULT_USER" 2>/dev/null || true)
    # Numeric fallback for the ACL qualifiers (0.0.42f C2): setfacl -x parses
    # `g:<name>` at parse time and dies wholesale (rc 2) on an empty or
    # unresolvable name — a numeric gid never needs resolution.
    UN_DEV_GID=$(id -g "$DEFAULT_USER" 2>/dev/null || true)
    trace "OPENCODE_USER=$OPENCODE_USER OPENCODE_GROUP=$OPENCODE_GROUP uid=$UN_OC_UID gid=$UN_OC_GID""\
 devgroup=$UN_DEV_GROUP devgid=$UN_DEV_GID"
}

# Sudoers + legacy sudoers/conf removal section.
un_sudoers_remove() {
    echo ""
    echo "--- Removing sudoers ---"
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm sudoers" sudo rm -f /etc/sudoers.d/opencode-permissions-kit
    if [ -z "$_un_partial" ]; then
        echo "sudoers removed."
        log "sudoers removed: /etc/sudoers.d/opencode-permissions-kit"
    else
        echo "WARN: sudoers removal failed ($_un_partial) — remove manually: /etc/sudoers.d/opencode-permissions-kit" >&2
        log "sudoers removal FAILED ($_un_partial)"
    fi

    # Legacy pre-0.0.10 kit names (0.0.43a F5): kits before v0.0.10 wrote
    # /etc/sudoers.d/opencode -> /etc/opencode/sudoers and kept their conf
    # under /etc/opencode/. `opk update` refuses pre-0.0.14, so that cohort
    # can never have migrated names — leaving the legacy symlink behind
    # keeps an ACTIVE kit sudoers grant alive after "Uninstall complete."
    # Marker-gated (the name /etc/sudoers.d/opencode is generic): only a
    # symlink pointing into the legacy conf dir is kit-owned.
    # #198 a W1: the symlink probe + readlink run at the rm's authority
    # (sudo) — /etc/sudoers.d is 0750 on hardened hosts, and a developer-
    # blind dir must not hide an ACTIVE kit grant from removal (same class
    # as the issue #164 openchamber gates).
    if sudo test -L /etc/sudoers.d/opencode; then
        _un_leg_link="$(sudo readlink /etc/sudoers.d/opencode 2>/dev/null || true)"
        case "$_un_leg_link" in
            /etc/opencode/*)
                _un_partial=""
                _un_revert_failed=0
                un_rc_q "rm legacy sudoers symlink" sudo rm -f /etc/sudoers.d/opencode
                if [ -z "$_un_partial" ]; then
                    echo "Legacy sudoers symlink removed (/etc/sudoers.d/opencode)."
                    log "legacy sudoers symlink removed: /etc/sudoers.d/opencode"
                else
                    echo "WARN: legacy sudoers symlink removal failed ($_un_partial)" >&2
                    log "legacy sudoers symlink removal FAILED ($_un_partial)"
                fi
                ;;
            *)
                echo "/etc/sudoers.d/opencode -> $_un_leg_link is not kit-owned — left untouched."
                ;;
        esac
    elif [ -e /etc/sudoers.d/opencode ]; then
        echo "/etc/sudoers.d/opencode exists but is not a kit symlink — left untouched."
    fi
    # Legacy conf dir: remove only the files pre-0.0.10 kits created there,
    # then the dir itself only if that emptied it — foreign content under
    # /etc/opencode survives.
    if [ -d /etc/opencode ]; then
        _un_partial=""
        _un_revert_failed=0
        for _un_leg in sudoers install.conf projects.conf setup.conf; do
            un_rc_q "rm legacy conf: /etc/opencode/$_un_leg" sudo rm -f "/etc/opencode/$_un_leg"
        done
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY] sudo rmdir /etc/opencode (only if empty)"
        elif [ -n "$_un_partial" ]; then
            echo "WARN: legacy conf removal failed ($_un_partial) — /etc/opencode kept, remove manually" >&2
            log "legacy conf removal FAILED ($_un_partial): /etc/opencode"
        elif sudo rmdir /etc/opencode 2>/dev/null; then
            echo "Legacy conf dir removed (/etc/opencode)."
            log "legacy conf dir removed: /etc/opencode (kit files)"
        else
            echo "/etc/opencode still holds foreign content — kit files removed, dir kept."
            log "legacy conf dir partially handled: /etc/opencode (foreign content kept)"
        fi
    fi
}

# Wrapper removal section.
un_wrapper_remove() {
    echo ""
    echo "--- Removing wrapper ---"
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm wrapper" sudo rm -f /usr/local/bin/opencode
    if [ -z "$_un_partial" ]; then
        echo "Wrapper removed."
        log "wrapper removed: /usr/local/bin/opencode"
    else
        echo "WARN: wrapper removal failed ($_un_partial) — remove manually: /usr/local/bin/opencode" >&2
        log "wrapper removal FAILED ($_un_partial)"
    fi
}

# CLI dispatcher removal section.
un_cli_remove() {
    echo ""
    echo "--- Removing cli dispatcher ---"
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm cli dispatcher" sudo rm -f /usr/local/bin/opk /usr/local/bin/opencode-permissions-kit
    if [ -z "$_un_partial" ]; then
        echo "CLI dispatcher removed."
        log "cli removed: /usr/local/bin/opk"
    else
        echo "WARN: cli dispatcher removal failed ($_un_partial) — remove manually: /usr/local/bin/opk" >&2
        log "cli dispatcher removal FAILED ($_un_partial)"
    fi
}

# xdg-open fallback shim removal section (kit-owned symlink only).
un_xdg_open_remove() {
    # xdg-open fallback shim: remove ONLY the kit-owned symlink — a real
    # xdg-open (xdg-utils) or anything else at that path is not ours.
    echo ""
    echo "--- Removing xdg-open fallback ---"
    if [ -L /usr/local/bin/xdg-open ] &&
        [ "$(readlink /usr/local/bin/xdg-open 2>/dev/null || true)" \
            = "/usr/local/lib/opencode-permissions-kit/bin/xdg-open" ]; then
        _un_partial=""
        _un_revert_failed=0
        un_rc_q "rm xdg-open shim" sudo rm -f /usr/local/bin/xdg-open
        if [ -z "$_un_partial" ]; then
            echo "xdg-open fallback removed."
            log "xdg-open shim removed: /usr/local/bin/xdg-open"
        else
            echo "WARN: xdg-open shim removal failed ($_un_partial) — remove manually: /usr/local/bin/xdg-open" >&2
            log "xdg-open shim removal FAILED ($_un_partial)"
        fi
    else
        echo "xdg-open at /usr/local/bin/xdg-open is not kit-owned — left untouched."
    fi
}

# opencode 2.x plugin registration removal section.
un_tui_plugins_remove() {
    # opencode 2.x (issue #80): drop the kit's plugin registration before the
    # library goes — the discovered plugin dir (symlinked into LIBDIR) and any
    # inert file-path entries older kits may have written into cli.json. The
    # additive manager leaves unmanaged/broken files untouched.
    if [ -x /usr/local/lib/opencode-permissions-kit/py/tui-register.py ]; then
        # Developer home via getent (issue #192, V14 class): a root-shell
        # install recorded root as the developer — /home/root never exists
        # and the plugin cleanup would silently miss root's config dir.
        _un_dev_home="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"
        [ -n "$_un_dev_home" ] || _un_dev_home="/home/$DEFAULT_USER"
        for _un_dir in "/home/$OPENCODE_USER/.config/opencode" "$_un_dev_home/.config/opencode"; do
            # Chain gate (review 0.0.39h F2): rm -rf and the tui-register rewrite
            # below act THROUGH a linked parent (~/.config, ~/.config/opencode —
            # agent-replaceable): a planted link redirects the removal/rewrite
            # into the link target. The walker no-ops outside the agent home (the
            # developer side is trusted). Skip loudly (user-managed).
            if ! agent_home_sane "$OPENCODE_USER" "$_un_dir"; then
                echo "  ${YELLOW}WARNING: the chain to $_un_dir contains a symlink""\
 — plugin registration left in place (user-managed).${NC}"
                log "tui plugin removal skipped: symlink in the chain to $_un_dir"
                continue
            fi
            # pr-00263 d (issue #246 site 7, the a F3 class): both ops were
            # claim-less `run` — silent on failure. Through un_rc_q now:
            # failure WARNs and feeds the partial list; success stays quiet
            # (no success claim existed before — none is invented here).
            _un_partial=""
            _un_revert_failed=0
            un_rc_q "plugins rm" sudo rm -rf "${_un_dir:?}/plugins/opencode-permissions-kit"
            un_rc_q "tui unregister" sudo python3 /usr/local/lib/opencode-permissions-kit/py/tui-register.py "$_un_dir/cli.json" \
                unregister /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
                --drop /usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx
            if [ -n "$_un_partial" ]; then
                echo "WARN: plugin removal failed ($_un_partial) — remove manually:""\
 ${_un_dir:?}/plugins/opencode-permissions-kit (tui-register.py unregister)" >&2
                log "plugin removal FAILED ($_un_partial): $_un_dir"
            fi
        done
    fi
}

# WSL browser bridge removal section (consent-gated wsl.conf block).
un_wsl_bridge_remove() {
    echo ""
    echo "--- Removing WSL browser bridge ---"
    # (issues #91, #100) Consent policy (internal/records/wsl-conf-consent.md): the
    # kit never edits /etc/wsl.conf on its own — not even here. When kit-owned
    # content is present (the bridge comment block, or the legacy 0.0.36
    # section), ASK before removing it; --yes assumes yes, declining leaves
    # the file untouched and prints exactly what to delete by hand (after this
    # uninstall 'opk' is gone — there is no cleanup command anymore). The
    # stand-in tree under the library always goes (it dies with the library).
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] ask: remove the kit-owned wsl.conf bridge block? (default: no)"
        echo "  [DRY] sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl"
    else
        if grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null ||
            grep -q '^\[opencode-permissions-kit\]$' /etc/wsl.conf 2>/dev/null; then
            # (#370 a D1): default n — the conventions' direction for
            # changes to system files (agent/conventions.md,
            # "Interactive prompts"), and wsl.conf is THE user-owned
            # system config the kit guards (AGENTS.md Rules). Consent
            # stays explicit; --yes still assumes yes.
            if [ "$(prompt_yn "Remove the kit's wsl.conf bridge block? (""\
kit-owned lines only; your own entries stay)" "n")" = "y" ]; then
                if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then
                    echo "WSL browser bridge removed (wsl.conf block + stand-in tree)."
                    log "wsl browser bridge removed (/etc/wsl.conf bridge block + library wsl/ tree, consented)"
                else
                    # #211 a F27: a missing helper must not read as a
                    # completed removal. Since #364 the arm is also reachable
                    # with the helper present — its staging mktemp fails on a
                    # dead TMPDIR, the lib's WARNING above stderr-inherits
                    # through here and names the real cause. A silent
                    # _bb_install_conf failure (no WARNING of its own) also
                    # lands here — the WARN below is then the only diagnostic.
                    # (#370 a D2): the stderr reason and the log line name
                    # the same arm; the by-hand hint names BOTH shapes the
                    # gate serves — the comment block AND the legacy
                    # [opencode-permissions-kit] section (not comment-only).
                    echo "WARN: could not remove the wsl.conf bridge block (helper or staging mktemp failed)" >&2
                    echo "      remove the marked lines yourself — the comment block, plus the legacy" >&2
                    echo "      [opencode-permissions-kit] section through its root = line if present" >&2
                    log "wsl browser bridge removal FAILED (helper or staging mktemp failed)"
                fi
            else
                sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl
                echo "wsl.conf left untouched — remove the kit block yourself (WSL never"
                echo "warns about it; no 'wsl --shutdown' needed). It spans these lines:"
                grep -n '^# opencode permissions kit browser bridge -- begin$''|^# opencode permissions kit browser bridge -- end$' \
                    /etc/wsl.conf 2>/dev/null | sed 's/^/    /'
                grep -q '^\[opencode-permissions-kit\]$' /etc/wsl.conf 2>/dev/null &&
                    echo "    plus the legacy [opencode-permissions-kit] section (through its root = line)"
                log "wsl browser bridge: wsl.conf block left in place (user declined)"
            fi
        else
            # Same honesty as the consent arm above (#211 b W11): with the
            # helper missing (F27's failing stub) OR a failed tree drop
            # (#367 b B2 — the bare rm -rf at the helper's tail is this
            # arm's rc), the log must not claim a removal that never ran.
            if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then
                log "wsl browser bridge removed (no wsl.conf content found; library wsl/ tree dropped)"
            else
                echo "WARN: could not remove the wsl browser bridge (helper or tree drop failed)" >&2
                log "wsl browser bridge removal FAILED (no wsl.conf content found; helper or tree drop)"
            fi
        fi
    fi
}

# Library + legacy library/symlink removal section.
un_library_remove() {
    echo ""
    echo "--- Removing opencode library ---"
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm library" sudo rm -rf /usr/local/lib/opencode-permissions-kit
    if [ -z "$_un_partial" ]; then
        echo "opencode library removed."
        log "library removed: /usr/local/lib/opencode-permissions-kit"
    else
        echo "WARN: library removal failed ($_un_partial) — remove manually: /usr/local/lib/opencode-permissions-kit" >&2
        log "library removal FAILED ($_un_partial)"
    fi

    # Legacy pre-0.0.10 library (0.0.43a F5): /usr/local/lib/opencode — home
    # of the root-runnable protect-projects.sh the legacy sudoers rules
    # reference — plus its /usr/local/sbin convenience symlink (0.0.9
    # install.sh:438). Marker-gated on the kit files (wrapper /
    # protect-projects.sh): a foreign directory of that name stays.
    if [ -d /usr/local/lib/opencode ] &&
        { [ -e /usr/local/lib/opencode/wrapper ] ||
            [ -e /usr/local/lib/opencode/protect-projects.sh ]; }; then
        _un_partial=""
        _un_revert_failed=0
        un_rc_q "rm legacy library" sudo rm -rf /usr/local/lib/opencode
        if [ -z "$_un_partial" ]; then
            echo "Legacy library removed (/usr/local/lib/opencode)."
            log "legacy library removed: /usr/local/lib/opencode"
        else
            echo "WARN: legacy library removal failed ($_un_partial) — remove manually: /usr/local/lib/opencode" >&2
            log "legacy library removal FAILED ($_un_partial)"
        fi
    elif [ -d /usr/local/lib/opencode ]; then
        echo "/usr/local/lib/opencode holds no kit markers — left untouched."
    fi
    if [ -L /usr/local/sbin/protect-projects.sh ]; then
        _un_pp_link="$(readlink /usr/local/sbin/protect-projects.sh 2>/dev/null || true)"
        case "$_un_pp_link" in
            /usr/local/lib/opencode/*)
                _un_partial=""
                _un_revert_failed=0
                un_rc_q "rm legacy helper symlink" sudo rm -f /usr/local/sbin/protect-projects.sh
                if [ -z "$_un_partial" ]; then
                    echo "Legacy helper symlink removed (/usr/local/sbin/protect-projects.sh)."
                    log "legacy helper symlink removed: /usr/local/sbin/protect-projects.sh"
                else
                    echo "WARN: legacy helper symlink removal failed ($_un_partial)" >&2
                    log "legacy helper symlink removal FAILED ($_un_partial)"
                fi
                ;;
            *)
                echo "/usr/local/sbin/protect-projects.sh -> $_un_pp_link is not kit-owned — left untouched."
                ;;
        esac
    fi
}

# Umask profile removal section (+ legacy name).
un_umask_remove() {
    echo ""
    echo "--- Removing umask profile ---"
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm umask profile" sudo rm -f /etc/profile.d/opencode-permissions-kit-umask.sh
    # Legacy pre-0.0.10 name (0.0.43a F5) — the same cleanup update.sh and
    # sudoers-deploy.sh already perform on the install/update path.
    un_rc_q "rm legacy umask profile" sudo rm -f /etc/profile.d/opencode-umask.sh
    if [ -z "$_un_partial" ]; then
        echo "Umask profile removed."
        log "umask profile removed: /etc/profile.d/opencode-permissions-kit-umask.sh (+ legacy opencode-umask.sh)"
    else
        echo "WARN: umask profile removal failed ($_un_partial) — remove manually: /etc/profile.d/opencode-*-umask.sh" >&2
        log "umask profile removal FAILED ($_un_partial)"
    fi
}

# Remove the developer from the sharing group FIRST so userdel can clean up
# the opencode usergroup (its primary group) automatically. Exact-name
# match (#211 a F28): a bare substring grep matched opencode2 too, and the
# success echo printed over a silenced gpasswd failure.
un_group_membership_remove() {
    if id "$DEFAULT_USER" >/dev/null 2>&1 &&
        id "$DEFAULT_USER" | grep -qF "($OPENCODE_GROUP)"; then
        # The rc must reach the arms (#211 b W1): run_q ends in `|| true`
        # by design, so wiring a F28's honesty arms through it left the
        # else arm dead code — a failed gpasswd still printed "Removed".
        # DRY_RUN keeps the [DRY] echo and the success lines (the file's
        # run_q convention: dry-run reports the intended outcome).
        _grp_rc=0
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY] sudo gpasswd -d $DEFAULT_USER $OPENCODE_GROUP"
        else
            sudo gpasswd -d "$DEFAULT_USER" "$OPENCODE_GROUP" >/dev/null 2>&1 || _grp_rc=$?
        fi
        if [ "$_grp_rc" -eq 0 ]; then
            echo "Removed $DEFAULT_USER from group $OPENCODE_GROUP."
            log "removed $DEFAULT_USER from group $OPENCODE_GROUP"
        else
            echo "WARN: could not remove $DEFAULT_USER from group $OPENCODE_GROUP (gpasswd failed)" >&2
            log "group removal FAILED for $DEFAULT_USER (gpasswd)"
        fi
    fi
}

# opencode user removal section: consent prompt, agent-resources
# backup, rootless-backend teardown, userdel -r (rc observed).
# The sharing-group removal runs first (own function above).
un_user_remove() {
    echo ""
    echo "--- Removing opencode user ---"
    un_group_membership_remove
    if id "$OPENCODE_USER" >/dev/null 2>&1; then
        ans=$(prompt_yn "Remove user '$OPENCODE_USER' and their home directory?" "n")
        if [ "$ans" = "y" ]; then
            # userdel -r deletes /home/<opencode> INCLUDING migrated agent
            # resources (issue #19 move mode: ~/.agents and ~/.claude with
            # the developer's skills). Back them up to the developer's
            # ownership before the home goes away. BOTH probes run with
            # sudo and the listing fails SAFE (0.0.45c C6 + 0.0.45d W2):
            # the old unprivileged `ls -A` assumed the developer can read
            # the agent home — when they cannot (group membership dropped,
            # different DEFAULT_USER), the probe failed silently, the
            # backup block was skipped and userdel -r deleted the
            # resources without the warning. The 0.0.45c fix kept an
            # unprivileged `[ -d ]` in front of the sudo probe — but that
            # stat needs search on /home/<opencode> (2750
            # opencode:<sharing-group>) and fails exactly for those same
            # invokers, skipping the block silently again (W2). The
            # existence check rides sudo too now; an unreadable dir still
            # counts as NON-EMPTY (probe-failed sentinel), so the backup —
            # or its failure warning — always happens before userdel -r.
            for _un_ag_dirname in .agents .claude; do
                _un_ag_src="/home/$OPENCODE_USER/$_un_ag_dirname"
                _un_ag_ls=""
                if sudo test -d "$_un_ag_src"; then
                    _un_ag_ls=$(sudo ls -A "$_un_ag_src" 2>/dev/null) || _un_ag_ls="probe-failed"
                fi
                if [ -n "$_un_ag_ls" ]; then
                    _un_ag_stamp="$(date +%Y%m%d-%H%M%S)"
                    _un_ag_dir="/var/backups/opencode-permissions-kit/$_un_ag_dirname-backup-$_un_ag_stamp"
                    if [ "$DRY_RUN" = true ]; then
                        echo "  [DRY] sudo mkdir -p '$_un_ag_dir' && sudo cp -a '$_un_ag_src/.' '$_un_ag_dir/'"
                    elif sudo mkdir -p "$_un_ag_dir" && sudo cp -a "$_un_ag_src/." "$_un_ag_dir/" 2>/dev/null; then
                        id "$DEFAULT_USER" >/dev/null 2>&1 && sudo chown -R "$DEFAULT_USER" "$_un_ag_dir"
                        echo "Agent resources backed up: $_un_ag_dir (restore with: cp -a $_un_ag_dir/. ~/$_un_ag_dirname/)"
                        log "agents backup before userdel: $_un_ag_dir"
                    else
                        # Names the failing commands like the WARN siblings
                        # (#211 f W2 — review-f class sweep).
                        echo "WARNING: could not back up $_un_ag_src — its content will be deleted with the user (mkdir/cp failed)."
                        log "agents backup FAILED before userdel: $_un_ag_dirname (mkdir/cp)"
                    fi
                fi
            done
            # A rootless container backend (docker-rootless/podman-rootless) enabled
            # linger and starts the user's systemd manager; userdel refuses while
            # that manager is running. Tear it down first (best-effort), then remove
            # the user.
            OC_UID=$(id -u "$OPENCODE_USER")
            run_q sudo loginctl disable-linger "$OPENCODE_USER"
            run_q sudo systemctl stop "user@$OC_UID.service"
            # Rootless podman storage keeps the home busy — reset it (best-effort).
            run_q sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR=/run/user/"$OC_UID" podman system reset --force
            # Stopping the user manager can leave a rootless container's init
            # (e.g. docker-rootless `catatonit`) orphaned and re-parented to
            # init.scope; userdel refuses while ANY process of the user runs.
            # Kill stragglers (best-effort), then remove the user.
            run_q sudo pkill -9 -u "$OPENCODE_USER"
            sleep 1
            # The rc must reach the arms (#211 c W1): run_q ends in `|| true`
            # by design, so a failed userdel still printed "User … removed" —
            # userdel refuses while ANY process of the user runs (a straggler
            # the pkill above can miss). DRY_RUN keeps the [DRY] echo and the
            # success lines (the file's run_q convention).
            _udel_rc=0
            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY] sudo userdel -r $OPENCODE_USER"
            else
                sudo userdel -r "$OPENCODE_USER" >/dev/null 2>&1 || _udel_rc=$?
            fi
            if [ "$_udel_rc" -eq 0 ]; then
                echo "User '$OPENCODE_USER' removed."
                log "user removed: $OPENCODE_USER"
            else
                echo "WARN: could not remove user '$OPENCODE_USER' (userdel failed)" >&2
                log "user removal FAILED for $OPENCODE_USER (userdel)"
            fi
        else
            echo "User '$OPENCODE_USER' kept."
        fi
    else
        echo "User '$OPENCODE_USER' does not exist."
    fi
}

# _un_revert_chown <root>: the revert loop's chown pass with the
# exec-time operand recheck (#267 — the _fsb_pass per-entry shape,
# fs-baseline.sh #211 a F1). The old one-shot
#   find <root> ! -type l ( -uid .. -o -gid .. ) -exec chown .. {} +
# classified every operand at SCAN time and never re-verified it at exec
# time — and the reverted trees are agent-group-writable (the baseline
# pattern), so a scanned regular file swapped for a symlink mid-walk
# made the root-run chown follow it and retarget an arbitrary
# out-of-tree path (ownership corruption). The userdel-before-loop
# mitigation fails exactly when userdel refuses on a live straggler
# process — WARN-and-continue — so the adversary can be live in the
# window. Shape: find streams NUL-separated operands into a temp file;
# an xargs worker then re-tests each LEAF with [ -L ] and re-walks every
# component between <root> and the operand immediately before the chown
# (chain-walker, #211 a F1). Anything that is a symlink NOW is a
# mid-walk swap (find ! -type l never emitted links) — skipped AND
# failed: entries left behind must degrade the closing log (the #211
# a F14 honesty class; un_rc_q turns rc nonzero into PARTIALLY + WARN).
# Swap-skips and genuine chown errors share the "find-chown failed"
# label deliberately: both mean "entries stayed behind — inspect the
# tree", and a per-cause channel through xargs is not worth the
# machinery (the fs-baseline twin logs the same way). Residual windows
# (#420 a A4/A5, recorded here): the per-operand recheck->chown gap is
# microsecond-scale and undetectable (same accepted shape as the
# handover pair's gate->op residual and _fsb_pass's); and the walk
# starts BELOW the scan root — the ROOT itself swapped between find and
# the worker still redirects the batch (the pre-existing _fsb_pass
# shape, :364 there; closing it is a two-worker class sweep, work order
# proposed in this PR's review).
_un_revert_chown() { # <root>; UN_OC_UID/UN_OC_GID select, DEFAULT_USER/
    #                  UN_DEV_GROUP are the chown target
    _unr_root="$1"
    # Fail LOUD with a distinct message (#420 a A3): a silent || return 1
    # here is indistinguishable from the later find failure — the message
    # is what the pin (and the operator) discriminates on.
    _unr_nul="$(mktemp "${TMPDIR:-/tmp}/opk-un-revert.XXXXXXXX")" || {
        echo "  WARN: cannot stage the revert operand stream (mktemp failed) — chown pass refused" >&2
        return 1
    }
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_unr_nul"
    fi
    # find's rc must survive (0.0.43b W4 shape): a wholesale find death
    # never counts as a green revert over a half-walked tree.
    # shellcheck disable=SC2024  # deliberate: the redirect is the
    # CALLER's (the dev-owned mktemp temp — dev can write it); sudo only
    # elevates find, whose stdout flows through the inherited fd — the
    # same capture _fsb_pass does via its _fsb_sudo variable.
    if ! sudo find "$_unr_root" ! -type l \( -uid "$UN_OC_UID" -o -gid "$UN_OC_GID" \) \
        -print0 >"$_unr_nul"; then
        rm -f "$_unr_nul"
        return 1
    fi
    _unr_rc=0
    sudo xargs -0 -r sh -c '
        # $1 = scan root (the component walk bound), $2 = the chown
        # target, then the batch of NUL-separated operands xargs
        # appended. _fail accumulates across the WHOLE batch (0.0.44a
        # V9 shape): a for-loop status alone is the LAST command.
        _root=$1; shift
        _own=$1; shift
        _fail=0
        for _p in "$@"; do
            if [ -L "$_p" ]; then
                _fail=1
                continue
            fi
            # Parent-component recheck (#211 a F1): skip operands whose
            # path crosses a symlinked DIRECTORY below the scan root —
            # the leaf gate alone misses a parent swapped in the
            # scan->act window. String ops only: spaced paths survive.
            case "$_p" in
            "$_root"/*)
                _pre="$_root"
                _rest="${_p#"$_root"/}"
                while [ -n "$_rest" ]; do
                    case "$_rest" in
                        */*) _pre="$_pre/${_rest%%/*}"
                             _rest="${_rest#*/}" ;;
                        *)   _pre="$_p"; _rest="" ;;
                    esac
                    if [ -L "$_pre" ]; then
                        _fail=1
                        continue 2
                    fi
                done
                ;;
            esac
            chown "$_own" "$_p" || _fail=1
        done
        [ "$_fail" -eq 0 ]
      ' un-revert-chown "$_unr_root" "$DEFAULT_USER:$UN_DEV_GROUP" <"$_unr_nul" ||
        _unr_rc=$?
    rm -f "$_unr_nul"
    [ "$_unr_rc" -eq 0 ]
}

# Issue #74: the kit hands .ddev/ trees, app-type settings dirs and (typo3
# bootstrap) project roots over to the opencode user, and everything the
# agent/ddev created while running as opencode is opencode-owned too. Left
# as-is after an uninstall, those files belong to a user (or an orphaned
# uid, after userdel) the developer cannot follow — the project becomes
# inaccessible without sudo. Revert EVERYTHING the kit user owns back to
# the developer: matched by uid/gid so it also catches orphaned ids after
# the user removal above, and restricted to the registered project roots
# (same source of truth as the ACL cleanup). File CONTENTS are never
# touched — only owner and group.
un_projects_revert() {
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        # The agent user's own home is never a project root — the
        # writer's dedicated refusal OUTSIDE its case blocklist
        # (sh/path-sane.sh project_path_sane, config.sh's and
        # install.sh's shared gate since issue #216 — two verbatim
        # copies at the time of review 0.0.39a S4), mirrored here
        # (#243 c Q1): the
        # root-run revert ops must never run over the directory that
        # carries the agent's own config and state. Lexical on purpose
        # and before the [ -d ] gate — the refusal holds even on a
        # host where the user or its home does not exist. The compare
        # takes the once-stripped form ONLY (#243 d Q1): it covers the
        # raw spelling as its no-trailing-slash case, so a trailing
        # slash cannot dodge it (#243 c Q1) while the predicate stays
        # exactly the writer's strip-then-compare shape; `//` forms
        # are the dot gate's job below. The compared value itself is
        # shape-gated right after install.conf is sourced (#243 e X1):
        # a corrupted conf value cannot defang this refusal.
        # pr-00263 a F10: getent alongside the literal spelling — a
        # relocated agent home refuses too (the config.sh twin).
        _un_agent_home="$(getent passwd "$OPENCODE_USER" 2>/dev/null | cut -d: -f6 || true)"
        if [ "${root%/}" = "/home/$OPENCODE_USER" ] ||
            { [ -n "$_un_agent_home" ] && [ "${root%/}" = "$_un_agent_home" ]; }; then
            echo "  Skipping agent home (never a project root): $root"
            continue
        fi
        [ ! -d "$root" ] && continue

        # Form gate (#243 a X2): the sanctioned writer validates these
        # forms (sh/path-sane.sh project_path_sane — absolute, no
        # dot/empty segments); a hand-edited conf must not slip a `//etc` or
        # `/var/.`-style entry past the system-path blocklist below.
        # Same arm order as the writer: absolute first, then dots.
        case "$root" in
            /*) ;;
            *)
                echo "  Skipping non-absolute project path: $root"
                continue
                ;;
        esac
        case "$root" in
            *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]*)
                echo "  Skipping malformed project path (dot, empty segment, or whitespace): $root"
                continue
                ;;
        esac
        # Writer-parity normalization (#243 c X1), after the dot gate:
        # project_path_sane strips one trailing slash before its
        # blocklist (sh/path-sane.sh `_pp="${1%/}"`) — the reader mirrors
        # that so the bare arms without /* siblings (/home, /var) are
        # not open to their trailing-slash spellings: /home/ and
        # /var/ passed gate + blocklist lexically while the writer
        # refuses the stripped form. Placed here, not earlier: every
        # `//` form is already the dot gate's catch above, so at most
        # ONE trailing slash can remain and one strip is exact.
        # `/` strips to the empty string — keep it as `/` (the
        # blocklist's `/` arm refuses it). The skip echo below prints
        # the normalized path, still naming the conf entry.
        _un_root="${root%/}"
        [ -n "$_un_root" ] || _un_root="/"
        root="$_un_root"
        # System-path blocklist — writer parity (#243 b X1, completed
        # by the normalization and agent-home refusal above, #243 c
        # X1/Q1): every system path project_path_sane refuses
        # (sh/path-sane.sh — its trailing-slash strip, its case
        # blocklist here in the writer's arm order, and its agent-home
        # refusal), so a hand-edited conf cannot drive the root-run
        # revert ops over system trees the sanctioned writer would
        # never store.
        # Scope of "parity" (#243 d X1, resolved by #418 a A2): the
        # writer's whitespace refusal (sh/path-sane.sh
        # `*[[:space:]]*` — a storage-format refusal, 0.0.39b C3) was
        # scoped OUT here (#243 a X2 disposition: "a spaced path never
        # lexically equals a system path, and [ ! -d ] plus full
        # quoting defang it"). #247's reader-parity wave closed the
        # pending mirror-or-scope decision the OTHER way: the arm is
        # mirrored now (this case arm above), matching the update-core
        # and config.sh refresh readers — every reader's FORM gate
        # refuses the same spellings (an existence gate may still eat a
        # NONEXISTENT line silently first; docs/reference/files.md
        # names the nuance), and no consumer of a hand-edited conf
        # processes an entry the writer would never store.
        # Deliberate divergence, pinned in the unit suite: the scratch
        # prefixes /tmp and /var/tmp stay processable (the sandbox
        # policy pins unit-fixture roots there, and a temp-prefix
        # entry is bounded — uid/gid-matched chown, kit-gid ACL strip
        # and one setgid-bit clear (chmod g-s) only).
        # #377 (review #370 a O1) + pr-00429 a A1: the /var families are
        # FHS-complete — /var/account, /var/backups, /var/crash, /var/games,
        # /var/local, /var/lock, /var/opt, /var/run (verbatim parity with
        # path-sane.sh).
        case "$root" in
            / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
                /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
                /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /usr | /usr/* | \
                /var | /var/account | /var/account/* | /var/backups | /var/backups/* | /var/cache | \
                /var/cache/* | /var/crash | /var/crash/* | /var/games | /var/games/* | /var/lib | \
                /var/lib/* | /var/local | /var/local/* | /var/lock | /var/lock/* | /var/log | \
                /var/log/* | /var/mail | /var/mail/* | /var/opt | /var/opt/* | /var/run | \
                /var/run/* | /var/spool | /var/spool/*)
                echo "  Skipping system path: $root"
                continue
                ;;
        esac

        # Symlinked root gate (issue #245): [ ! -d ] above follows a
        # link, so a conf entry that IS a symlink reaches the ops —
        # which then dereference the operand: chmod g-s and setfacl
        # -R -x land on the TARGET directory (one mode bit, one ACL
        # entry per table, non-recursive — measured, issue #245) while
        # the find-chown walk visits nothing. Skip loudly instead: no
        # revert ops on an object that is not the configured root.
        # Checked on the NORMALIZED root (the #243 c-wave strip above):
        # a `link/` spelling would dodge a lexical [ -L ] — [ -L
        # "path/" ] is false because the kernel resolves through the
        # slash (measured, issue #245).
        if [ -L "$root" ]; then
            echo "  Skipping symlinked project path (register the target directory instead): $root"
            continue
        fi

        # Per-root partial causes (#218): failed ops (recorded by
        # un_rc_q) and unknown-id skips both land in this ONE
        # list — the closing log below reports them instead of
        # claiming completion. The former second mechanism
        # (_un_acl_skipped, 0.0.42h S1) is folded in here.
        _un_partial=""
        _un_revert_failed=0
        echo "  Reverting kit ownership in: $root"
        if [ -n "$UN_OC_UID" ] && [ -n "$UN_OC_GID" ]; then
            # No -xdev on purpose: project roots are often separate mounts
            # (the e2e bind-mounts them; NFS/overlay in the wild) — the
            # revert must follow, exactly like the setfacl -R below.
            # ! -type l (0.0.42e S1) is the SCAN-time half: it keeps
            # statically planted links out of the operand stream; the
            # exec-time half — per-operand leaf recheck + component walk
            # immediately before each chown — lives in _un_revert_chown
            # (#267, the _fsb_pass shape; leaf and mid-walk parent swaps
            # never retarget the chown — a swap of the ROOT itself
            # between scan and worker remains, the recorded _fsb_pass
            # residual, see the helper's header).
            # DRY names the real command shape, not the helper (the
            # un_rc_q [DRY] echo would print "_un_revert_chown <root>").
            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY] sudo find $root ! -type l \( -uid $UN_OC_UID -o -gid $UN_OC_GID \)""\
 -print0 | exec-time recheck + chown $DEFAULT_USER:$UN_DEV_GROUP"
            else
                un_rc_q "find-chown" _un_revert_chown "$root"
            fi
        else
            _un_partial="${_un_partial:+$_un_partial, }opencode user unknown (chown skipped)"
            echo "    opencode user unknown — skipped (chown manually if files are locked)"
        fi
        echo "  Cleaning kit ACLs from: $root"
        # Dual-principal targeted removal (0.0.42e C4, corrected
        # 0.0.42g S1): the baseline writes g:<OPENCODE_GROUP> entries
        # (fs_baseline_root hands the opencode group — access traversal
        # plus defaults); dev-group qualifiers cover traversal grants
        # and older kit shapes. The former `setfacl -R -b`/`-k` wiped
        # ALL extended ACLs — including pre-existing user entries
        # install never owned. -x is a no-op (rc 0) on absent entries,
        # live-verified for both the access and the default table.
        # Qualifiers are NUMERIC (0.0.42f C2): a name qualifier dies at
        # parse time when the name does not resolve; the gids survive
        # the userdel above (captured before, orphan-proof). A principal
        # whose gid is UNKNOWN is skipped loudly with its manual hint —
        # never silently (0.0.42h S1) — and lands in the partial list
        # so the closing log says "partial" when one was skipped.
        for _un_acl_pair in "opencode group:$UN_OC_GID" "dev group:$UN_DEV_GID"; do
            _un_acl_label="${_un_acl_pair%%:*}"
            _un_acl_gid="${_un_acl_pair#*:}"
            if [ -z "$_un_acl_gid" ]; then
                _un_partial="${_un_partial:+$_un_partial, }${_un_acl_label} id unknown"
                echo "    ${_un_acl_label} id unknown — its ACL entries left in place""\
 (remove manually: setfacl -R -x g:<gid> -d -x g:<gid>)"
                continue
            fi
            un_rc_q "setfacl -x g:$_un_acl_gid" sudo setfacl -R -x "g:$_un_acl_gid" "$root"
            un_rc_q "setfacl -d -x g:$_un_acl_gid" sudo setfacl -R -d -x "g:$_un_acl_gid" "$root"
        done
        un_rc_q "chmod g-s" sudo chmod g-s "$root"
        # Closing log conditioned on what actually happened (#218, the
        # deferred #211 c W1 class sweep; degraded wording #243 a X1):
        # every op site above reports its rc, and every skip cause is
        # in the same list — full success keeps the old line, anything
        # else degrades to PARTIALLY completed naming the causes and
        # never asserts the clause that failed (a failed find-chown
        # must not read as "ownership reverted"). A FAILED op
        # additionally WARNs on stderr and leaves a FAILED log line; a
        # pure skip (unknown id) keeps its own echo only — not
        # attempted is not failed.
        if [ -z "$_un_partial" ]; then
            log "project ownership reverted + kit ACL entries removed: $root"
        else
            log "project revert PARTIALLY completed ($_un_partial): $root"
            if [ "$_un_revert_failed" -eq 1 ]; then
                echo "WARN: could not fully revert $root ($_un_partial)" >&2
                log "project revert FAILED for: $root ($_un_partial)"
            fi
        fi
    done <"$UNINSTALL_PROJECTS_CONF"
}

# Kit config directories + runtime artifacts removal section (rc observed).
un_config_dirs_remove() {
    echo ""
    echo "--- Removing kit config directories + runtime artifacts ---"
    # rc-observing removal (#243 a S1/S2 — the #211 c W1 class sweep this
    # wave owes; the early removal sections above route through un_rc_q
    # since pr-00263 a F3 — the six `run` sites the #243 wave missed, plus
    # the legacy-shape siblings): the former `run` ops fed an
    # unconditional "Removed." + success log even when an rm failed. Same
    # ops through un_rc_q now; a failure lands in the partial list and
    # degrades the closing claim. DRY_RUN keeps the [DRY] echoes and the
    # success lines (the run_q convention, #211 b W1).
    _un_partial=""
    _un_revert_failed=0
    un_rc_q "rm /run/opencode-permissions-kit" sudo rm -rf /run/opencode-permissions-kit
    un_rc_q "rm 99-ddev-rootless.conf" sudo rm -f /etc/sysctl.d/99-ddev-rootless.conf
    # OpenChamber policy pin (issue #154): remove only what the kit wrote — a
    # policy.json pinning OUR wrapper. Any other content is admin-owned and
    # stays; /etc/openchamber itself only goes when empty (OpenChamber may own
    # more files in it).
    # Issue #164: uninstall.sh runs as the developer (root is refused), so the
    # presence probe and the content grep run at the write's authority (sudo) —
    # an admin 0700 /etc/openchamber must not hide a kit pin from removal.
    # Pin removal observes its rc too (#243 a S2): the success log fires only
    # when the rm actually succeeded — audit-log arm pattern (#211 c W1).
    if sudo test -f /etc/openchamber/policy.json &&
        sudo grep -q '"opencodeBinary"[[:space:]]*:[[:space:]]*"/usr/local/bin/opencode"' \
            /etc/openchamber/policy.json 2>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY] sudo rm -f /etc/openchamber/policy.json"
            echo "  [DRY] sudo rmdir /etc/openchamber"
            log "openchamber policy pin removed (kit-owned content only)"
        elif sudo rm -f /etc/openchamber/policy.json >/dev/null 2>&1; then
            sudo rmdir /etc/openchamber 2>/dev/null || true
            log "openchamber policy pin removed (kit-owned content only)"
        else
            _un_partial="${_un_partial:+$_un_partial, }openchamber policy pin rm failed"
            _un_revert_failed=1
            echo "WARN: could not remove the openchamber policy pin (rm failed)" >&2
            log "openchamber policy pin removal FAILED (rm)"
        fi
    fi
    un_rc_q "rm /etc/opencode-permissions-kit" sudo rm -rf /etc/opencode-permissions-kit
    if [ -z "$_un_partial" ]; then
        echo "Removed."
        log "config dirs + runtime artifacts removed (/etc/opencode-permissions-kit""\
, /run/opencode-permissions-kit, 99-ddev-rootless.conf)"
    else
        log "config dirs + runtime artifacts PARTIALLY removed ($_un_partial)"
        # Every partial cause in this section is a FAILED op today (no
        # skip causes exist here), so flag and list coincide — the gate
        # mirrors the project loop's closing and keeps a future skip cause
        # from false-WARNing; the openchamber arm sets the flag so the
        # state is never write-only here (#243 b Q2).
        if [ "$_un_revert_failed" -eq 1 ]; then
            echo "WARN: could not fully remove config dirs + runtime artifacts ($_un_partial)" >&2
        fi
    fi
}

# Audit log removal section (consent prompt, rc observed).
un_audit_log_remove() {
    echo ""
    echo "--- Removing audit log ---"
    if [ "$(prompt_yn "Delete audit log too? (recommended)" "y")" = "y" ]; then
        # Log the outcome, not the intent (#211 c W1): the log line used to
        # fire BEFORE the rm — a removal run_q silenced could fail with the
        # audit trail already claiming success. DRY_RUN keeps the [DRY] echo
        # and the success lines (the run_q convention).
        _al_rc=0
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY] sudo rm -rf /var/log/opencode-permissions-kit"
        else
            sudo rm -rf /var/log/opencode-permissions-kit >/dev/null 2>&1 || _al_rc=$?
        fi
        if [ "$_al_rc" -eq 0 ]; then
            echo "Audit log removed."
            log "audit log removed: /var/log/opencode-permissions-kit"
        else
            # Names the failing command like the userdel/gpasswd arms
            # (#211 e W3 — review-e wording finding).
            echo "WARN: could not remove the audit log at /var/log/opencode-permissions-kit (rm failed)" >&2
            log "audit log removal FAILED for /var/log/opencode-permissions-kit (rm)"
        fi
    else
        log "audit log kept (requested by user)"
        echo "Audit log kept at /var/log/opencode-permissions-kit"
    fi
}
