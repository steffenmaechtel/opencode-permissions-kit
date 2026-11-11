#!/bin/sh
# opencode permissions kit -- uninstall.sh
# Removes ALL changes made by install.sh. Must be run as your default user with sudo.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --dry-run    Show what would be removed without changing anything
#   --debug      Trace execution (set -x)
#
# Thin entry since issue #346 wave 4: arg parsing, helper-lib sourcing,
# guards and the closing summary stay here; the removal sections live in
# sh/uninstall-core.sh (sourced below, checkout-first with the deployed
# $LIBDIR fallback -- the update.sh resolver shape; see the lib header).

# Colors resolved to REAL bytes once at load (printf interprets \033 in
# the format string; a bare echo does not portably — dash yes, bash
# prints the literal). Off for NO_COLOR / non-tty, same rule as sh/ui.sh
# (0.0.39e C10/C12).
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
else
    RED=$(printf '\033[0;31m')
    GREEN=$(printf '\033[0;32m')
    YELLOW=$(printf '\033[0;33m')
    NC=$(printf '\033[0m')
fi

YES=false
DRY_RUN=false
DEBUG=false
for arg; do
    case "$arg" in
        --yes | -y) YES=true ;;
        --dry-run) DRY_RUN=true ;;
        --debug) DEBUG=true ;;
        # Unknown options die loudly (0.0.44a V7): a silent drop turned
        # `opk uninstall --dryrun --yes` (one missing hyphen) into a real
        # unprompted uninstall — the highest-blast-radius script in the
        # kit. Every sibling command already rejected unknowns.
        *)
            echo "error: unknown option: $arg" >&2
            echo "usage: opk uninstall [--yes|-y] [--dry-run] [--debug]" >&2
            exit 1
            ;;
    esac
done

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Sourced
# before any removal so the final lines are written before the library and
# the log directory itself are deleted.
#
# Caller-dir anchor (#405; #433 hardening), placed before the first
# dirname-$0 lookup: a streamed stdin run (curl ... | sudo sh) has no
# real $0 — the lookups below would resolve a cwd-sibling lib and source
# it as root, unpinned. Pin stdin runs to the deployed library's
# management dir on the FLAT layout (review a B1: the repo-layout path
# does not exist deployed); checkout and installed runs keep their own
# dir — resolved through readlink like the pre-#405 UNINSTALL_CORE line
# (review a B1: the bare dirname lost symlink resolution). The stdin
# discriminator compares $0 against the interpreter's own argv[0]
# (#433: a planted cwd FILE named like the interpreter must not
# re-open the cwd trust; same discriminator at all six #405 anchors).
UN_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")"
_opk_stdin=false
_opk_argv0="$(tr '\0' '\n' 2>/dev/null </proc/$$/cmdline | head -n 1)"
if [ -n "$_opk_argv0" ]; then
    if [ "$0" = "$_opk_argv0" ]; then
        _opk_stdin=true
    fi
elif ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" ]; then
    _opk_stdin=true
fi
if [ "$_opk_stdin" = true ]; then
    UN_CALL_DIR="/usr/local/lib/opencode-permissions-kit/management"
fi
log() { :; }
for cand in "$UN_CALL_DIR/../sh/log.sh" \
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
for cand in "$UN_CALL_DIR/../sh/wsl-browser-bridge.sh" \
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
for cand in "$UN_CALL_DIR/../sh/staged-write.sh" "/usr/local/lib/opencode-permissions-kit/sh/staged-write.sh"; do
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
if (exec </dev/tty) 2>/dev/null; then
    trace "/dev/tty: readable"
else
    trace "/dev/tty: NOT readable"
fi

if [ "$DEFAULT_USER" = "root" ] || [ "$DEFAULT_USER" = "opencode" ]; then
    echo "${RED}Do not run as root or opencode. ""\
Run as your normal user WITHOUT the 'sudo' prefix (./uninstall.sh).${NC}"
    exit 1
fi

trace "checking sudo (-n true) ..."
if ! sudo -n true 2>/dev/null; then
    trace "no cached/passwordless sudo -> sudo -v"
    if ! sudo -v 2>&1; then
        echo "This script requires sudo. Run it as your normal user (no 'sudo' prefix);""\
 you will be asked for your password."
        exit 1
    fi
fi
trace "sudo OK"
if [ "$DRY_RUN" = true ]; then
    echo "${YELLOW}DRY RUN -- no changes will be made.${NC}"
    echo ""
fi

# --- phase logic: sh/uninstall-core.sh (issue #346, wave 4) -----------------------
# Every removal section below lives in the sourced lib -- checkout-first
# like update.sh's update-core.sh (a checkout uninstall.sh runs its own
# sections; an older deployed lib could predate one). A deployed run via
# `opk uninstall` resolves both candidates to the same path, so a missing
# lib is a broken kit (the #165 class): loud error, no silent section
# drops. Unlike install.sh's kit_source there IS a $LIBDIR fallback here
# -- uninstall.sh runs from the deployed tree, install.sh never does.
UNINSTALL_CORE="$UN_CALL_DIR/../sh/uninstall-core.sh"
[ -f "$UNINSTALL_CORE" ] || UNINSTALL_CORE="/usr/local/lib/opencode-permissions-kit/sh/uninstall-core.sh"
if [ -f "$UNINSTALL_CORE" ]; then
    # shellcheck disable=SC1090
    . "$UNINSTALL_CORE"
else
    echo "error: uninstall-core.sh not found (expected ../sh/uninstall-core.sh next to uninstall.sh or deployed)" >&2
    exit 1
fi

# Pairing guard (#413, PR #412 round a S2 — this entry is the finding's
# own example) — LOAD-BEARING here: uninstall is deliberately fail-soft
# (no set -e; a failing op must not kill the remaining removals), so an
# undefined call does NOT abort — it prints "not found", returns rc 127
# and the run CONTINUES, skipping that removal silently and still
# printing "Uninstall complete." at the end. A version-skewed entry/lib
# pairing is a wiring error, not an op failure: refuse loud, before the
# first prompt, exit 1. The guard pins every function the paired core
# defines — the sections the entry calls AND the helpers they call
# internally (#452, the doctor precedent: a helper-level skew skips
# removals silently behind a green "Uninstall complete.", e.g. a
# missing un_rc_q strands every op in the sections that drive it).
# Functions from other sourced libs sit outside this guard by design —
# the core pairing is what is pinned here; the cross-lib surface rides
# the entry's pre-source stub arms (log, browser_bridge_remove,
# agent_home_sane — the #455 a Q1 "already mitigated" surface, kept
# clean by its own rider, #456). prompt_yn
# rides the
# list for the same reason (it lives in the core and gates the consent
# the whole run hangs on). The list is kept equal to uninstall-core.sh's
# function definitions (the test-suite completeness riders enforce both
# directions).
un_pairing_guard() {
    for _npg in un_context_load prompt_yn un_sudoers_remove \
        un_wrapper_remove un_cli_remove un_xdg_open_remove \
        un_tui_plugins_remove un_wsl_bridge_remove un_library_remove \
        un_umask_remove un_user_remove un_projects_revert \
        un_config_dirs_remove un_audit_log_remove \
        _un_revert_chown run_q un_group_membership_remove \
        un_opencode_user_gate un_rc_q; do
        command -v "$_npg" >/dev/null 2>&1 || {
            echo "error: function '$_npg' missing from uninstall-core.sh — version-skewed entry/lib pairing, refusing to run" >&2
            return 1
        }
    done
}
un_pairing_guard || exit 1

# === Main ===
# The uninstall as a linear section list; everything above is bootstrap,
# helpers and the section-lib resolver (the definitions live in
# sh/uninstall-core.sh). Plain statements in the former top-level order
# -- user-visible output byte-identical (proven by dry-run execution;
# --debug xtrace legitimately adds the sourcing event and the section
# call lines — diagnostics, not output).
un_context_load

trace "first prompt ..."
ans=$(prompt_yn "Proceed with uninstall?" "n")
[ "$ans" != "y" ] && {
    echo "Aborted."
    exit 0
}
log "uninstall started (dry_run=$DRY_RUN)"
un_sudoers_remove
un_wrapper_remove
un_cli_remove
un_xdg_open_remove
un_tui_plugins_remove
un_wsl_bridge_remove
un_library_remove
un_umask_remove
un_user_remove

echo ""
echo "--- Reverting project ownership + ACLs ---"
UNINSTALL_PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
if [ -f "$UNINSTALL_PROJECTS_CONF" ]; then
    un_projects_revert
fi

un_config_dirs_remove
un_audit_log_remove

echo ""
echo "  ${GREEN}Uninstall complete.${NC}"
echo ""
echo "  ${YELLOW}Manual cleanup remaining:${NC}"
echo "    - Backups in /var/backups/opencode-permissions-kit/install-* (safe to delete)"
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
