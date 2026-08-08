#!/bin/sh
# opencode permissions kit -- uninstall.sh
# Removes ALL changes made by setup.sh. Must be run as your default user with sudo.
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

trace() {
    [ "$DEBUG" = true ] && echo "[debug] $*" >&2
}

if [ "$DEBUG" = true ]; then
    set -x
fi

DEFAULT_USER=$(whoami)
OPENCODE_USER="opencode"
WWW_GROUP="www-data"

echo ""
echo "  ${RED}opencode permissions kit -- UNINSTALL${NC}"
echo "  This will remove ALL changes made by setup.sh."
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

# Source setup.conf for variables
if [ -f /etc/opencode/setup.conf ]; then
    trace "sourcing /etc/opencode/setup.conf"
    . /etc/opencode/setup.conf
fi
OPENCODE_USER="${OPENCODE_USER:-opencode}"
WWW_GROUP="${WWW_GROUP:-www-data}"
trace "OPENCODE_USER=$OPENCODE_USER WWW_GROUP=$WWW_GROUP"

trace "first prompt ..."
ans=$(prompt_yn "Proceed with uninstall?" "n")
[ "$ans" != "y" ] && { echo "Aborted."; exit 0; }

echo ""
echo "--- Removing Git hooks ---"
run "sudo -u \"$OPENCODE_USER\" git config --global --unset core.hooksPath 2>/dev/null || true"
run "sudo -u \"$DEFAULT_USER\" git config --global --unset core.hooksPath 2>/dev/null || true"
echo "Git hooks removed."

echo ""
echo "--- Removing sudoers ---"
run "sudo rm -f /etc/sudoers.d/opencode"
echo "sudoers removed."

echo ""
echo "--- Removing wrapper ---"
run "sudo rm -f /usr/local/bin/opencode"
echo "Wrapper removed."

echo ""
echo "--- Removing opencode library ---"
run "sudo rm -f /usr/local/sbin/protect-projects.sh"
run "sudo rm -rf /usr/local/lib/opencode"
echo "opencode library removed."

echo ""
echo "--- Removing umask profile ---"
run "sudo rm -f /etc/profile.d/opencode-umask.sh"
echo "Umask profile removed."

echo ""
echo "--- Removing opencode user ---"
if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ans=$(prompt_yn "Remove user '$OPENCODE_USER' and their home directory?" "n")
    if [ "$ans" = "y" ]; then
        run "sudo userdel -r \"$OPENCODE_USER\" 2>/dev/null || true"
        echo "User '$OPENCODE_USER' removed."
    else
        echo "User '$OPENCODE_USER' kept."
    fi
else
    echo "User '$OPENCODE_USER' does not exist."
fi

echo ""
echo "--- Removing default user from www-data ---"
if id "$DEFAULT_USER" | grep -q "$WWW_GROUP"; then
    ans=$(prompt_yn "Remove '$DEFAULT_USER' from group '$WWW_GROUP'?" "n")
    if [ "$ans" = "y" ]; then
        run "sudo gpasswd -d \"$DEFAULT_USER\" \"$WWW_GROUP\" 2>/dev/null || true"
        echo "Removed from $WWW_GROUP."
    else
        echo "Group membership kept."
    fi
fi

echo ""
echo "--- Removing project ACLs and setgid ---"
if [ -f /etc/opencode/projects.conf ]; then
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
    done < /etc/opencode/projects.conf
fi

echo ""
echo "--- Removing /etc/opencode/ ---"
run "sudo rm -rf /etc/opencode"
echo "Removed."

echo ""
echo "  ${GREEN}Uninstall complete.${NC}"
echo "  Backups (if any) remain in /tmp/opencode-setup-backup-* for manual cleanup."
echo ""
