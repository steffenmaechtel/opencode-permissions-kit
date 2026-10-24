#!/bin/sh
# opencode permissions kit -- uninstall.sh
# Removes ALL changes made by install.sh. Must be run as your default user with sudo.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --dry-run    Show what would be removed without changing anything
#   --debug      Trace execution (set -x)

# Colors resolved to REAL bytes once at load (printf interprets \033 in
# the format string; a bare echo does not portably — dash yes, bash
# prints the literal). Off for NO_COLOR / non-tty, same rule as sh/ui.sh
# (0.0.39e C10/C12).
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    RED=''; GREEN=''; YELLOW=''; NC=''
else
    RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m')
    YELLOW=$(printf '\033[0;33m'); NC=$(printf '\033[0m')
fi

YES=false
DRY_RUN=false
DEBUG=false
for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        --dry-run) DRY_RUN=true ;;
        --debug) DEBUG=true ;;
        # Unknown options die loudly (0.0.44a V7): a silent drop turned
        # `opk uninstall --dryrun --yes` (one missing hyphen) into a real
        # unprompted uninstall — the highest-blast-radius script in the
        # kit. Every sibling command already rejected unknowns.
        *)
            echo "error: unknown option: $arg" >&2
            echo "usage: opk uninstall [--yes|-y] [--dry-run] [--debug]" >&2
            exit 1 ;;
    esac
done

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Sourced
# before any removal so the final lines are written before the library and
# the log directory itself are deleted.
log() { :; }
for cand in "$(dirname "$0")/../sh/log.sh" \
    "/usr/local/lib/opencode-permissions-kit/sh/log.sh" "/usr/local/lib/opencode/log.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

# WSL browser bridge helper (issue #91): needed below to strip the kit
# section from /etc/wsl.conf before the library goes. Stub keeps older
# installs (no deployed helper yet) uninstallable — it FAILS (#211 a
# F27): the old silent no-op let the caller below claim "removed" over
# a removal that never ran.
browser_bridge_remove() { return 1; }
for cand in "$(dirname "$0")/../sh/wsl-browser-bridge.sh" \
    "/usr/local/lib/opencode-permissions-kit/sh/wsl-browser-bridge.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

# Agent-home link gates (review 0.0.39h F2, same class as the install/update
# gates): the plugin removal below acts THROUGH a linked parent (~/.config,
# ~/.config/opencode — agent-replaceable). Stub keeps older installs
# (pre-0.0.39h deployed library, no walker yet) uninstallable.
agent_home_sane() { return 0; }
for cand in "$(dirname "$0")/../sh/staged-write.sh" "/usr/local/lib/opencode-permissions-kit/sh/staged-write.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

trace() {
    [ "$DEBUG" = true ] && echo "[debug] $*" >&2
}

if [ "$DEBUG" = true ]; then
    set -x
fi

DEFAULT_USER=$(whoami)
OPENCODE_USER="opencode"
# Sharing group: filled from install.conf / the live value below.
OPENCODE_GROUP=""

echo ""
echo "  ${RED}opencode permissions kit -- UNINSTALL${NC}"
echo "  This will remove ALL changes made by install.sh."
echo ""

trace "DEFAULT_USER=$DEFAULT_USER"
trace "stdin is tty: $([ -t 0 ] && echo yes || echo no)"
if (exec < /dev/tty) 2>/dev/null; then
    trace "/dev/tty: readable"
else
    trace "/dev/tty: NOT readable"
fi

if [ "$DEFAULT_USER" = "root" ] || [ "$DEFAULT_USER" = "opencode" ]; then
    echo "${RED}Do not run as root or opencode. "\
"Run as your normal user WITHOUT the 'sudo' prefix (./uninstall.sh).${NC}"
    exit 1
fi

trace "checking sudo (-n true) ..."
if ! sudo -n true 2>/dev/null; then
    trace "no cached/passwordless sudo -> sudo -v"
    if ! sudo -v 2>&1; then
        echo "This script requires sudo. Run it as your normal user (no 'sudo' prefix);"\
" you will be asked for your password."
        exit 1
    fi
fi
trace "sudo OK"

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
    if ! [ -t 0 ] && ! (exec < /dev/tty) 2>/dev/null; then
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
        y|yes) echo "y" ;;
        n|no)  echo "n" ;;
        *)     [ "$default" = "y" ] && echo "y" || echo "n" ;;
    esac
}

if [ "$DRY_RUN" = true ]; then
    echo "${YELLOW}DRY RUN -- no changes will be made.${NC}"
    echo ""
fi

# Direct invocation only — no eval, no `sh -c` (agent/conventions.md).
# Failures print their error and the uninstall continues (no set -e here).
run() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    else
        "$@"
    fi
}

# Like run, but output and failures are silenced (the former
# "cmd 2>/dev/null || true" call sites — best-effort cleanup).
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
    _un_rc_label="$1"; shift
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    elif ! "$@" >/dev/null 2>&1; then
        _un_revert_failed=1
        _un_partial="${_un_partial:+$_un_partial, }$_un_rc_label failed"
    fi
}

# Source install.conf (canonical path since 0.0.10).
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
if [ -f "$INSTALL_CONF" ]; then
    trace "sourcing $INSTALL_CONF"
    . "$INSTALL_CONF"
fi
OPENCODE_USER="${OPENCODE_USER:-opencode}"
# Shape-gate the sourced value (#243 e X1): install.conf is root-owned
# but hand-editable, and the writer stamps a literal here (install.sh
# sets OPENCODE_USER="opencode" and its conf heredoc carries that
# literal — the writer's charset gate covers DEFAULT_USER, not this
# name). A shape-invalid value (e.g. a trailing slash) would silently
# defang the agent-home refusal in the project loop and the
# agents-backup walk below — fall back to the canonical literal,
# loudly. Same conservative charset as the writer's DEFAULT_USER gate.
case "$OPENCODE_USER" in
    ''|*[!A-Za-z0-9_.-]*)
        echo "WARN: invalid OPENCODE_USER value in install.conf ('$OPENCODE_USER') — falling back to 'opencode'" >&2
        OPENCODE_USER=opencode
        ;;
esac
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
trace "OPENCODE_USER=$OPENCODE_USER OPENCODE_GROUP=$OPENCODE_GROUP uid=$UN_OC_UID gid=$UN_OC_GID"\
" devgroup=$UN_DEV_GROUP devgid=$UN_DEV_GID"

trace "first prompt ..."
ans=$(prompt_yn "Proceed with uninstall?" "n")
[ "$ans" != "y" ] && { echo "Aborted."; exit 0; }
log "uninstall started (dry_run=$DRY_RUN)"

echo ""
echo "--- Removing sudoers ---"
run sudo rm -f /etc/sudoers.d/opencode-permissions-kit
echo "sudoers removed."
log "sudoers removed: /etc/sudoers.d/opencode-permissions-kit"

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
            run sudo rm -f /etc/sudoers.d/opencode
            echo "Legacy sudoers symlink removed (/etc/sudoers.d/opencode)."
            log "legacy sudoers symlink removed: /etc/sudoers.d/opencode"
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
    for _un_leg in sudoers install.conf projects.conf setup.conf; do
        run sudo rm -f "/etc/opencode/$_un_leg"
    done
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] sudo rmdir /etc/opencode (only if empty)"
    elif sudo rmdir /etc/opencode 2>/dev/null; then
        echo "Legacy conf dir removed (/etc/opencode)."
        log "legacy conf dir removed: /etc/opencode (kit files)"
    else
        echo "/etc/opencode still holds foreign content — kit files removed, dir kept."
        log "legacy conf dir partially handled: /etc/opencode (foreign content kept)"
    fi
fi

echo ""
echo "--- Removing wrapper ---"
run sudo rm -f /usr/local/bin/opencode
echo "Wrapper removed."
log "wrapper removed: /usr/local/bin/opencode"

echo ""
echo "--- Removing cli dispatcher ---"
run sudo rm -f /usr/local/bin/opk /usr/local/bin/opencode-permissions-kit
echo "CLI dispatcher removed."
log "cli removed: /usr/local/bin/opk"

# xdg-open fallback shim: remove ONLY the kit-owned symlink — a real
# xdg-open (xdg-utils) or anything else at that path is not ours.
echo ""
echo "--- Removing xdg-open fallback ---"
if [ -L /usr/local/bin/xdg-open ] \
   && [ "$(readlink /usr/local/bin/xdg-open 2>/dev/null || true)" \
      = "/usr/local/lib/opencode-permissions-kit/bin/xdg-open" ]; then
    run sudo rm -f /usr/local/bin/xdg-open
    echo "xdg-open fallback removed."
    log "xdg-open shim removed: /usr/local/bin/xdg-open"
else
    echo "xdg-open at /usr/local/bin/xdg-open is not kit-owned — left untouched."
fi

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
            echo "  ${YELLOW}WARNING: the chain to $_un_dir contains a symlink"\
" — plugin registration left in place (user-managed).${NC}"
            log "tui plugin removal skipped: symlink in the chain to $_un_dir"
            continue
        fi
        run sudo rm -rf "${_un_dir:?}/plugins/opencode-permissions-kit"
        run sudo python3 /usr/local/lib/opencode-permissions-kit/py/tui-register.py "$_un_dir/cli.json" \
            unregister /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
            --drop /usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx
    done
fi

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
    echo "  [DRY] ask: remove the kit-owned wsl.conf bridge block? (default: yes)"
    echo "  [DRY] sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl"
else
    if grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null \
       || grep -q '^\[opencode-permissions-kit\]$' /etc/wsl.conf 2>/dev/null; then
        if [ "$(prompt_yn "Remove the kit's wsl.conf bridge block? ("\
"kit-owned comments only; your own entries stay)" "y")" = "y" ]; then
            if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then
                echo "WSL browser bridge removed (wsl.conf block + stand-in tree)."
                log "wsl browser bridge removed (/etc/wsl.conf bridge block + library wsl/ tree, consented)"
            else
                # #211 a F27: near-unreachable (the block writer ships in
                # the same lib) — but a missing helper must not read as a
                # completed removal.
                echo "WARN: could not remove the wsl.conf bridge block (kit helper unavailable)" >&2
                echo "      remove the marked lines yourself — the kit block is comment-only" >&2
                log "wsl browser bridge removal FAILED (helper unavailable)"
            fi
        else
            sudo rm -rf /usr/local/lib/opencode-permissions-kit/wsl
            echo "wsl.conf left untouched — remove the kit block yourself (WSL never"
            echo "warns about it; no 'wsl --shutdown' needed). It spans these lines:"
            grep -n '^# opencode permissions kit browser bridge -- begin$'\
'|^# opencode permissions kit browser bridge -- end$' \
                /etc/wsl.conf 2>/dev/null | sed 's/^/    /'
            grep -q '^\[opencode-permissions-kit\]$' /etc/wsl.conf 2>/dev/null \
                && echo "    plus the legacy [opencode-permissions-kit] section (through its root = line)"
            log "wsl browser bridge: wsl.conf block left in place (user declined)"
        fi
    else
        # Same honesty as the consent arm above (#211 b W11): with the
        # helper missing (F27's failing stub) the log must not claim a
        # removal that never ran.
        if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then
            log "wsl browser bridge removed (no wsl.conf content found; library wsl/ tree dropped)"
        else
            echo "WARN: could not remove the wsl browser bridge (kit helper unavailable)" >&2
            log "wsl browser bridge removal FAILED (helper unavailable, no wsl.conf content found)"
        fi
    fi
fi

echo ""
echo "--- Removing opencode library ---"
run sudo rm -rf /usr/local/lib/opencode-permissions-kit
echo "opencode library removed."
log "library removed: /usr/local/lib/opencode-permissions-kit"

# Legacy pre-0.0.10 library (0.0.43a F5): /usr/local/lib/opencode — home
# of the root-runnable protect-projects.sh the legacy sudoers rules
# reference — plus its /usr/local/sbin convenience symlink (0.0.9
# install.sh:438). Marker-gated on the kit files (wrapper /
# protect-projects.sh): a foreign directory of that name stays.
if [ -d /usr/local/lib/opencode ] \
   && { [ -e /usr/local/lib/opencode/wrapper ] \
        || [ -e /usr/local/lib/opencode/protect-projects.sh ]; }; then
    run sudo rm -rf /usr/local/lib/opencode
    echo "Legacy library removed (/usr/local/lib/opencode)."
    log "legacy library removed: /usr/local/lib/opencode"
elif [ -d /usr/local/lib/opencode ]; then
    echo "/usr/local/lib/opencode holds no kit markers — left untouched."
fi
if [ -L /usr/local/sbin/protect-projects.sh ]; then
    _un_pp_link="$(readlink /usr/local/sbin/protect-projects.sh 2>/dev/null || true)"
    case "$_un_pp_link" in
        /usr/local/lib/opencode/*)
            run sudo rm -f /usr/local/sbin/protect-projects.sh
            echo "Legacy helper symlink removed (/usr/local/sbin/protect-projects.sh)."
            log "legacy helper symlink removed: /usr/local/sbin/protect-projects.sh"
            ;;
        *)
            echo "/usr/local/sbin/protect-projects.sh -> $_un_pp_link is not kit-owned — left untouched."
            ;;
    esac
fi

echo ""
echo "--- Removing umask profile ---"
run sudo rm -f /etc/profile.d/opencode-permissions-kit-umask.sh
# Legacy pre-0.0.10 name (0.0.43a F5) — the same cleanup update.sh and
# sudoers-deploy.sh already perform on the install/update path.
run sudo rm -f /etc/profile.d/opencode-umask.sh
echo "Umask profile removed."
log "umask profile removed: /etc/profile.d/opencode-permissions-kit-umask.sh (+ legacy opencode-umask.sh)"

echo ""
echo "--- Removing opencode user ---"
# Remove the developer from the sharing group FIRST so userdel can clean up
# the opencode usergroup (its primary group) automatically. Exact-name
# match (#211 a F28): a bare substring grep matched opencode2 too, and the
# success echo printed over a silenced gpasswd failure.
if id "$DEFAULT_USER" >/dev/null 2>&1 \
    && id "$DEFAULT_USER" | grep -qF "($OPENCODE_GROUP)"; then
    # The rc must reach the arms (#211 b W1): run_q ends in `|| true`
    # by design, so wiring a F28's honesty arms through it left the
    # else arm dead code — a failed gpasswd still printed "Removed".
    # DRY_RUN keeps the [DRY] echo and the success lines (the file's
    # run/run_q convention: dry-run reports the intended outcome).
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
        # success lines (the file's run/run_q convention).
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

echo ""
echo "--- Reverting project ownership + ACLs ---"
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
UNINSTALL_PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
if [ -f "$UNINSTALL_PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        # The agent user's own home is never a project root — the
        # writer's dedicated refusal OUTSIDE its case blocklist
        # (config.sh project_path_sane and the install.sh validator
        # copy, review 0.0.39a S4), mirrored here (#243 c Q1): the
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
        if [ "${root%/}" = "/home/$OPENCODE_USER" ]; then
            echo "  Skipping agent home (never a project root): $root"
            continue
        fi
        [ ! -d "$root" ] && continue

        # Form gate (#243 a X2): the sanctioned writer validates these
        # forms (config.sh project_path_sane — absolute, no dot/empty
        # segments); a hand-edited conf must not slip a `//etc` or
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
            *..*|/./|*/./*|./*|*/.|*//*)
                echo "  Skipping malformed project path (dot or empty segment): $root"
                continue
                ;;
        esac
        # Writer-parity normalization (#243 c X1), after the dot gate:
        # project_path_sane strips one trailing slash before its
        # blocklist (config.sh `_pp="${1%/}"`) — the reader mirrors
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
        # (config.sh — its trailing-slash strip, its case blocklist
        # here in the writer's arm order, and its agent-home refusal),
        # so a hand-edited conf cannot drive the root-run revert ops
        # over system trees the sanctioned writer would never store.
        # Scope of "parity" (#243 d X1): the writer's whitespace
        # refusal (config.sh `*[[:space:]]*` — a storage-format
        # refusal, 0.0.39b C3) is deliberately NOT mirrored here
        # (recorded a X2 disposition): a spaced path never lexically
        # equals a system path, and [ ! -d ] plus full quoting defang
        # it; the mirror-or-scope decision rides #247 with the other
        # writer-side parity work.
        # Deliberate divergence, pinned in the unit suite: the scratch
        # prefixes /tmp and /var/tmp stay processable (the sandbox
        # policy pins unit-fixture roots there, and a temp-prefix
        # entry is bounded — uid/gid-matched chown, kit-gid ACL strip
        # and one setgid-bit clear (chmod g-s) only).
        case "$root" in
            /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/lib*|\
            /media|/media/*|/mnt|/mnt/*|/opt|/opt/*|/proc|/proc/*|/root|/root/*|\
            /run|/run/*|/sbin|/sbin/*|/srv|/srv/*|/sys|/sys/*|/usr|/usr/*|\
            /var|/var/cache|/var/cache/*|/var/lib|/var/lib/*|/var/log|/var/log/*|\
            /var/mail|/var/mail/*|/var/spool|/var/spool/*)
                echo "  Skipping system path: $root"
                continue
                ;;
        esac

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
            # ! -type l (0.0.42e S1): chown on a symlink operand FOLLOWS
            # it — an agent-planted link in the project must not make the
            # root-run revert chown an arbitrary target outside it.
            un_rc_q "find-chown" sudo find "$root" ! -type l \( -uid "$UN_OC_UID" -o -gid "$UN_OC_GID" \) \
                -exec chown "$DEFAULT_USER:$UN_DEV_GROUP" {} +
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
                echo "    ${_un_acl_label} id unknown — its ACL entries left in place"\
" (remove manually: setfacl -R -x g:<gid> -d -x g:<gid>)"
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
    done < "$UNINSTALL_PROJECTS_CONF"
fi

echo ""
echo "--- Removing kit config directories + runtime artifacts ---"
# rc-observing removal (#243 a S1/S2 — the #211 c W1 class sweep this
# wave owes): the former `run` ops fed an unconditional "Removed." +
# success log even when an rm failed. Same ops through un_rc_q
# now; a failure lands in the partial list and degrades the closing
# claim. DRY_RUN keeps the [DRY] echoes and the success lines (the
# run/run_q convention, #211 b W1).
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
if sudo test -f /etc/openchamber/policy.json \
    && sudo grep -q '"opencodeBinary"[[:space:]]*:[[:space:]]*"/usr/local/bin/opencode"' \
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
    log "config dirs + runtime artifacts removed (/etc/opencode-permissions-kit"\
", /run/opencode-permissions-kit, 99-ddev-rootless.conf)"
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

echo ""
echo "--- Removing audit log ---"
if [ "$(prompt_yn "Delete audit log too? (recommended)" "y")" = "y" ]; then
    # Log the outcome, not the intent (#211 c W1): the log line used to
    # fire BEFORE the rm — a removal run_q silenced could fail with the
    # audit trail already claiming success. DRY_RUN keeps the [DRY] echo
    # and the success lines (the run/run_q convention).
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

echo ""
echo "  ${GREEN}Uninstall complete.${NC}"
echo ""
echo "  ${YELLOW}Manual cleanup remaining:${NC}"
echo "    - Backups in /tmp/opencode-install-backup* (safe to delete)"
echo "    - Shell RC files (~/.bashrc, ~/.zshrc, ~/.profile) still contain"
echo "      lines tagged '# opencode permissions kit' (PATH export +"
echo "      shell-warn.sh hook). They are harmless after uninstall"
echo "      (the shell-warn hook is guarded by [ -f ... ] and silently"
echo "      skips when the library is gone), but you can remove every"
echo "      matching line manually if you want a clean file:"
echo "        grep -n 'opencode permissions kit' ~/.bashrc ~/.zshrc ~/.profile"
echo "        # then delete the reported lines with your editor"
echo "    - Default-user opencode config at"
echo "      ~/.config/opencode/opencode.jsonc (and any opencode.jsonc_BAK_*)"
echo "      is left untouched — delete it manually if you no longer use opencode."
echo "    - TUI mode display leftovers (all harmless without the kit):"
echo "      /home/$OPENCODE_USER/.config/opencode/tui.json (registers the kit"
echo "      plugin; opencode skips it when the plugin file is gone),"
echo "      ~/.config/opencode/tui.json + ~/.config/opencode/themes/"
echo "      opencode-danger.json (red bypass theme for your user)."
echo "    - Windows hosts file: entries added by 'opk ddev-hosts-add'"
echo "      (C:\\Windows\\System32\\drivers\\etc\\hosts) keep resolving"
echo "      project domains to 127.0.0.1 — remove them manually if you"
echo "      no longer need them (project domains under *.ddev.site were"
echo "      never added)."
echo ""
# Session hint (issue #73): the running shell still carries kit leftovers
# a fresh session drops by itself — the ddev() function from the rc hook
# (its sudoers helper is gone now, every call would error), the PATH/umask
# additions from the removed profile script, and the sharing-group
# membership (gpasswd -d above only takes effect on the next login).
echo "  ${YELLOW}Restart your terminal (or log in again) — the current session${NC}"
echo "  ${YELLOW}still carries the kit's ddev shell function (now pointing at a${NC}"
echo "  ${YELLOW}deleted helper), its PATH/umask additions and the old group${NC}"
echo "  ${YELLOW}membership; a fresh session starts clean.${NC}"
echo ""
