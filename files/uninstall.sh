#!/bin/sh
# opencode permissions kit -- uninstall.sh
# Removes ALL changes made by install.sh. Must be run as your default user with sudo.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --dry-run    Show what would be removed without changing anything
#   --debug      Trace execution (set -x)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

YES=false
DRY_RUN=false
DEBUG=false
for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        --dry-run) DRY_RUN=true ;;
        --debug) DEBUG=true ;;
    esac
done

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Sourced
# before any removal so the final lines are written before the library and
# the log directory itself are deleted.
log() { :; }
for cand in "$(dirname "$0")/log.sh" "$(dirname "$0")/opencode-permissions-kit-lib/log.sh" "/usr/local/lib/opencode-permissions-kit/log.sh" "/usr/local/lib/opencode/log.sh"; do
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
# Sharing group default: the opencode user's own usergroup. A sourced
# install.conf (below) or the live value (see the LIVE_GROUP override)
# takes precedence; the pre-soft-only default www-data is long gone.
WWW_GROUP="opencode"

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
    echo "${RED}Do not run as root or opencode. Run as your normal user WITHOUT the 'sudo' prefix (./uninstall.sh).${NC}"
    exit 1
fi

trace "checking sudo (-n true) ..."
if ! sudo -n true 2>/dev/null; then
    trace "no cached/passwordless sudo -> sudo -v"
    if ! sudo -v 2>&1; then
        echo "This script requires sudo. Run it as your normal user (no 'sudo' prefix); you will be asked for your password."
        exit 1
    fi
fi
trace "sudo OK"

prompt_yn() {
    # prompt_yn "message" default
    # Returns "y" or "n"
    local msg="$1" default="$2"
    local hint="(y/N)"
    [ "$default" = "y" ] && hint="(Y/n)"
    if [ "$YES" = true ]; then
        trace "prompt '$msg' -> yes (--yes)"
        echo "y"
        return
    fi
    if ! [ -t 0 ] && ! (exec < /dev/tty) 2>/dev/null; then
        echo "${RED}No terminal available. Run interactively or use --yes to skip prompts.${NC}" >&2
        exit 1
    fi
    printf "[?] %s %s " "$msg" "$hint" >&2
    trace "prompt '$msg': waiting for input"
    read -r answer </dev/tty 2>/dev/null || read -r answer
    trace "prompt '$msg': got '$answer'"
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
    [ -z "$answer" ] && answer="$default"
    case "$answer" in y|yes) echo "y" ;; *) echo "n" ;; esac
}

if [ "$DRY_RUN" = true ]; then
    echo "${YELLOW}DRY RUN -- no changes will be made.${NC}"
    echo ""
fi

run() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY] $*"
    else
        eval "$*"
    fi
}

# Source install.conf (new path first, then legacy pre-0.0.10 /etc/opencode/
# and pre-0.0.9 setup.conf).
INSTALL_CONF=""
for _c in /etc/opencode-permissions-kit/install.conf /etc/opencode-permissions-kit/setup.conf \
          /etc/opencode/install.conf /etc/opencode/setup.conf; do
    if [ -f "$_c" ]; then
        INSTALL_CONF="$_c"
        break
    fi
done
if [ -n "$INSTALL_CONF" ]; then
    trace "sourcing $INSTALL_CONF"
    . "$INSTALL_CONF"
fi
OPENCODE_USER="${OPENCODE_USER:-opencode}"
# Sharing group: the opencode user's primary usergroup (soft-only model).
# Prefer the live value; stale confs may still say www-data.
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
if [ -n "$LIVE_GROUP" ]; then
    WWW_GROUP="$LIVE_GROUP"
else
    WWW_GROUP="${WWW_GROUP:-opencode}"
fi
trace "OPENCODE_USER=$OPENCODE_USER WWW_GROUP=$WWW_GROUP"

trace "first prompt ..."
ans=$(prompt_yn "Proceed with uninstall?" "n")
[ "$ans" != "y" ] && { echo "Aborted."; exit 0; }
log "uninstall started (dry_run=$DRY_RUN)"

echo ""
echo "--- Removing Git hooks (legacy cleanup) ---"
# The soft-only kit no longer installs hooks, but a pre-migration install left
# core.hooksPath pointing at the (deleted) kit hooks dir — git would warn on
# every command. Unset for both users (best-effort).
run "sudo -u \"$OPENCODE_USER\" git config --global --unset core.hooksPath 2>/dev/null || true"
run "sudo -u \"$DEFAULT_USER\" git config --global --unset core.hooksPath 2>/dev/null || true"
echo "Git hooks config removed."
log "git hooks config removed (core.hooksPath unset, legacy)"

echo ""
echo "--- Removing sudoers ---"
run "sudo rm -f /etc/sudoers.d/opencode-permissions-kit"
run "sudo rm -f /etc/sudoers.d/opencode"
echo "sudoers removed."
log "sudoers removed: /etc/sudoers.d/opencode-permissions-kit (+ legacy /etc/sudoers.d/opencode)"

echo ""
echo "--- Removing wrapper ---"
run "sudo rm -f /usr/local/bin/opencode"
echo "Wrapper removed."
log "wrapper removed: /usr/local/bin/opencode"

echo ""
echo "--- Removing ddev shim (legacy) ---"
# The soft-only kit installs no shim; a pre-migration install did. Removing
# /usr/local/bin/ddev only ever hits OUR symlink — guard against a real ddev.
run "[ -L /usr/local/bin/ddev ] && sudo rm -f /usr/local/bin/ddev || true"
echo "ddev shim removed (if it was ours)."
log "ddev shim removed (legacy)"

echo ""
echo "--- Removing opencode library ---"
run "sudo rm -f /usr/local/sbin/protect-projects.sh"
run "sudo rm -rf /usr/local/lib/opencode-permissions-kit"
run "sudo rm -rf /usr/local/lib/opencode"
echo "opencode library removed."
log "library removed: /usr/local/lib/opencode-permissions-kit (+ legacy /usr/local/lib/opencode)"

echo ""
echo "--- Removing umask profile ---"
run "sudo rm -f /etc/profile.d/opencode-permissions-kit-umask.sh"
run "sudo rm -f /etc/profile.d/opencode-umask.sh"
echo "Umask profile removed."
log "umask profile removed: /etc/profile.d/opencode-permissions-kit-umask.sh (+ legacy opencode-umask.sh)"

echo ""
echo "--- Removing opencode user ---"
# Remove the developer from the sharing group FIRST so userdel can clean up
# the opencode usergroup (its primary group) automatically.
if id "$DEFAULT_USER" >/dev/null 2>&1 && id "$DEFAULT_USER" | grep -q "$WWW_GROUP"; then
    run "sudo gpasswd -d \"$DEFAULT_USER\" \"$WWW_GROUP\" 2>/dev/null || true"
    echo "Removed $DEFAULT_USER from group $WWW_GROUP."
    log "removed $DEFAULT_USER from group $WWW_GROUP"
fi
if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ans=$(prompt_yn "Remove user '$OPENCODE_USER' and their home directory?" "n")
    if [ "$ans" = "y" ]; then
        # A rootless container backend (docker-rootless/podman-rootless) enabled
        # linger and starts the user's systemd manager; userdel refuses while
        # that manager is running. Tear it down first (best-effort), then remove
        # the user.
        OC_UID=$(id -u "$OPENCODE_USER")
        run "sudo loginctl disable-linger \"$OPENCODE_USER\" 2>/dev/null || true"
        run "sudo systemctl stop \"user@$OC_UID.service\" 2>/dev/null || true"
        # Rootless podman storage keeps the home busy — reset it (best-effort).
        run "sudo -u \"$OPENCODE_USER\" XDG_RUNTIME_DIR=/run/user/$OC_UID podman system reset --force >/dev/null 2>&1 || true"
        # Stopping the user manager can leave a rootless container's init
        # (e.g. docker-rootless `catatonit`) orphaned and re-parented to
        # init.scope; userdel refuses while ANY process of the user runs.
        # Kill stragglers (best-effort), then remove the user.
        run "sudo pkill -9 -u \"$OPENCODE_USER\" 2>/dev/null || true"
        sleep 1
        run "sudo userdel -r \"$OPENCODE_USER\" 2>/dev/null || true"
        echo "User '$OPENCODE_USER' removed."
        log "user removed: $OPENCODE_USER"
    else
        echo "User '$OPENCODE_USER' kept."
    fi
else
    echo "User '$OPENCODE_USER' does not exist."
fi

echo ""
echo "--- Removing project ACLs and setgid ---"
UNINSTALL_PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$UNINSTALL_PROJECTS_CONF" ] || UNINSTALL_PROJECTS_CONF="/etc/opencode/projects.conf"
if [ -f "$UNINSTALL_PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ ! -d "$root" ] && continue

        case "$root" in
            /|/etc|/etc/*|/boot|/boot/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|\
            /lib|/lib/*|/lib64|/lib64/*|/sys|/sys/*|/proc|/proc/*|/dev|/dev/*|\
            /run|/run/*|/root|/root/*)
                echo "  Skipping system path: $root"
                continue
                ;;
        esac

        echo "  Cleaning ACLs from: $root"
        run "sudo setfacl -R -b \"$root\" 2>/dev/null || true"
        run "sudo setfacl -R -k \"$root\" 2>/dev/null || true"
        run "sudo chmod g-s \"$root\" 2>/dev/null || true"
    done < "$UNINSTALL_PROJECTS_CONF"
fi

echo ""
echo "--- Removing kit config directories + runtime artifacts ---"
run "sudo rm -rf /run/opencode-permissions-kit"
run "sudo rm -f /etc/sysctl.d/99-ddev-rootless.conf"
run "sudo rm -rf /etc/opencode-permissions-kit"
run "sudo rm -rf /etc/opencode"
echo "Removed."
log "config dirs + runtime artifacts removed (/etc/opencode-permissions-kit, /run/opencode-permissions-kit, 99-ddev-rootless.conf)"

echo ""
echo "--- Removing audit log ---"
if [ "$(prompt_yn "Delete audit log too? (recommended)" "y")" = "y" ]; then
    log "audit log removed: /var/log/opencode-permissions-kit"
    run "sudo rm -rf /var/log/opencode-permissions-kit"
    echo "Audit log removed."
else
    log "audit log kept (requested by user)"
    echo "Audit log kept at /var/log/opencode-permissions-kit"
fi

echo ""
echo "  ${GREEN}Uninstall complete.${NC}"
echo ""
echo "  ${YELLOW}Manual cleanup remaining:${NC}"
echo "    - Backups in /tmp/opencode-install-backup-* (safe to delete)"
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
echo ""
