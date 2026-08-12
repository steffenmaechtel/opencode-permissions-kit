#!/bin/sh
# opencode permissions kit -- config.sh
# Change settings AFTER install.sh has been run. Re-runs without re-asking
# the install-time questions. Reads /etc/opencode-permissions-kit/install.conf for context.
#
# What it can do:
#   - List / add / remove project roots in /etc/opencode-permissions-kit/projects.conf
#   - Toggle .git/config hardening for the opencode user
#   - Refresh ACL protection (re-run protect-projects.sh --force)
#
# Run as your default (non-root) user with sudo privileges:
#   ./config.sh                       # interactive menu
#   ./config.sh projects list
#   ./config.sh projects add /var/www/vhosts/foo
#   ./config.sh projects remove /var/www/vhosts/foo
#   ./config.sh git-config on|off|status
#   ./config.sh refresh
#
# Options:
#   --yes   Skip confirmations, assume Yes
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LIBDIR="/usr/local/lib/opencode-permissions-kit"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Works from
# both a repo checkout and the installed library.
log() { :; }
for cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh" "$LIBDIR/log.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

# install.conf with legacy fallback (pre-0.0.10 /etc/opencode/, pre-0.0.9 setup.conf)
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode-permissions-kit/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"

DEFAULT_USER=""
OPENCODE_USER="opencode"
WWW_GROUP="www-data"
if [ -f "$INSTALL_CONF" ]; then
    . "$INSTALL_CONF"
fi
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
WWW_GROUP="${WWW_GROUP:-www-data}"

YES=false
ACTION=""
SUB=""
TARGETS=""

for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        projects|git-config|refresh|status)
            [ -z "$ACTION" ] && ACTION="$arg" && continue
            [ "$ACTION" = "projects" ] && SUB="$arg" && continue
            TARGETS="$TARGETS $arg"
            ;;
        on|off)  [ "$ACTION" = "git-config" ] && SUB="$arg" ;;
        list|add|remove)
            [ "$ACTION" = "projects" ] && SUB="$arg" && continue
            ;;
        *)  TARGETS="$TARGETS $arg" ;;
    esac
done
TARGETS="${TARGETS# }"

banner() {
    echo ""
    echo "  ${GREEN}opencode permissions kit${NC}  config"
    echo "  ${CYAN}=============================================${NC}"
    echo ""
}

die() { echo "${RED}$*${NC}" >&2; exit 1; }

confirm() {
    [ "$YES" = true ] && return 0
    printf "[?] %s (y/N) " "$1" >&2
    read -r ans </dev/tty 2>/dev/null || read -r ans
    case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
        y|yes) return 0 ;; *) return 1 ;;
    esac
}

need_install() {
    if [ ! -f "$INSTALL_CONF" ]; then
        die "Not installed yet. Run install.sh first."
    fi
    [ -d "$LIBDIR" ] || die "Library missing at $LIBDIR. Run install.sh first."
}

# --- projects ----------------------------------------------------------------

projects_list() {
    echo "Project roots in ${CYAN}$PROJECTS_CONF${NC}:"
    if [ ! -f "$PROJECTS_CONF" ] || [ ! -s "$PROJECTS_CONF" ]; then
        echo "  (none configured)"
        return
    fi
    num=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        num=$((num + 1))
        if [ -d "$line" ]; then
            echo "  [$num] $line"
        else
            echo "  [$num] $line ${YELLOW}(missing)${NC}"
        fi
    done < "$PROJECTS_CONF"
    [ "$num" -eq 0 ] && echo "  (none configured)"
}

projects_add() {
    [ -z "$TARGETS" ] && die "Usage: config.sh projects add <path...>"
    sudo mkdir -p "$(dirname "$PROJECTS_CONF")"
    for p in $TARGETS; do
        p="$(cd "$p" 2>/dev/null && pwd)" || p="$p"
        if ! [ -d "$p" ]; then
            echo "  ${YELLOW}skip${NC} $p (not a directory)"
            continue
        fi
        if [ -f "$PROJECTS_CONF" ] && grep -qxF "$p" "$PROJECTS_CONF"; then
            echo "  ${CYAN}exists${NC} $p"
            continue
        fi
        echo "$p" | sudo tee -a "$PROJECTS_CONF" > /dev/null
        # Apply filesystem basics so ACLs function immediately
        sudo chgrp -R "$WWW_GROUP" "$p" 2>/dev/null || true
        sudo chmod g+s "$p"
        sudo setfacl -R -d -m "g:$WWW_GROUP:rwx" "$p" 2>/dev/null || true
        echo "  ${GREEN}added${NC} $p (group=$WWW_GROUP, setgid, default-acl)"
        log "project added: $p"
    done
    echo ""
    echo "Running protect-projects.sh --force ..."
    sudo "$LIBDIR/protect-projects.sh" --force
}

projects_remove() {
    [ -z "$TARGETS" ] && die "Usage: config.sh projects remove <path...>"
    [ -f "$PROJECTS_CONF" ] || { echo "No projects.conf — nothing to remove."; return; }
    for p in $TARGETS; do
        p="$(cd "$p" 2>/dev/null && pwd)" || p="$p"
        if ! grep -qxF "$p" "$PROJECTS_CONF"; then
            echo "  ${YELLOW}not found${NC} $p"
            continue
        fi
        if ! confirm "Remove '$p' from projects.conf? (ACL denies remain on disk until manually cleared)"; then
            echo "  skip $p"
            continue
        fi
        sudo grep -vx "$p" "$PROJECTS_CONF" | sudo tee "$PROJECTS_CONF.tmp" > /dev/null
        sudo mv "$PROJECTS_CONF.tmp" "$PROJECTS_CONF"
        echo "  ${GREEN}removed${NC} $p"
        log "project removed: $p"
    done
}

# --- git-config toggle -------------------------------------------------------

git_config_file() {
    for f in /home/opencode/.config/opencode/opencode.jsonc \
             /home/opencode/.config/opencode/opencode.json; do
        [ -f "$f" ] && { echo "$f"; return; }
    done
    echo ""
}

git_config_status() {
    f="$(git_config_file)"
    [ -z "$f" ] && { echo "No opencode config installed for $OPENCODE_USER."; return; }
    # ON  = .git/config deny rule is active (uncommented) in the config
    # OFF = rule absent or still a //SECURE_GIT comment
    if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
        echo "git-config hardening: ${GREEN}ON${NC}  ($f)"
    elif grep -q '//SECURE_GIT' "$f" 2>/dev/null; then
        echo "git-config hardening: ${CYAN}OFF${NC}  ($f — markers present, rules inactive)"
    else
        echo "git-config hardening: ${CYAN}OFF${NC}  ($f)"
    fi
}

git_config_apply() {
    # Re-renders the bundled opencode.jsonc template with or without SECURE_GIT
    enable="$1"
    target="/home/opencode/.config/opencode/opencode.jsonc"

    # Find the template: bundled alongside this script, or in the repo, or in the lib dir
    template=""
    for cand in "$SCRIPT_DIR/opencode.jsonc" "$SCRIPT_DIR/../files/opencode.jsonc" "$LIBDIR/opencode.jsonc"; do
        if [ -f "$cand" ]; then
            template="$cand"
            break
        fi
    done
    [ -n "$template" ] || die "Template missing: tried $SCRIPT_DIR/opencode.jsonc, $SCRIPT_DIR/../files/opencode.jsonc, $LIBDIR/opencode.jsonc"

    sudo cp "$template" "$target"
    sudo chown "$OPENCODE_USER:$WWW_GROUP" "$target"
    sudo chmod 664 "$target"

    if [ "$enable" = "on" ]; then
        sudo sed -i 's|//SECURE_GIT: ||' "$target"
        echo "git-config hardening: ${GREEN}ON${NC}  ($target)"
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' "$target"
        echo "git-config hardening: ${CYAN}OFF${NC}  ($target)"
    fi
    log "git-config hardening set to $enable ($target)"
    echo "NOTE: existing config was overwritten from template. Restart opencode to pick up changes."
}

# --- refresh -----------------------------------------------------------------

refresh() {
    echo "Re-running protect-projects.sh --force ..."
    sudo "$LIBDIR/protect-projects.sh" --force
    echo "${GREEN}ACL protection refreshed.${NC}"
    log "ACL refresh requested"
}

# --- interactive menu --------------------------------------------------------

menu() {
    banner
    while true; do
        echo "Current settings:"
        git_config_status 2>/dev/null || true
        projects_list
        echo ""
        echo "  [1] Add project root"
        echo "  [2] Remove project root"
        echo "  [3] Toggle .git/config hardening (on/off)"
        echo "  [4] Refresh ACL protection now"
        echo "  [q] Quit"
        printf "  > "
        read -r sel </dev/tty 2>/dev/null || read -r sel
        case "$sel" in
            1)
                echo "Enter paths (space-separated):"
                printf "  > "
                read -r paths </dev/tty 2>/dev/null || read -r paths
                [ -z "$paths" ] && continue
                ACTION=projects; SUB=add; TARGETS="$paths"; projects_add
                ;;
            2)
                ACTION=projects; SUB=remove; TARGETS=""
                echo "Enter path to remove:"
                printf "  > "
                read -r paths </dev/tty 2>/dev/null || read -r paths
                [ -z "$paths" ] && continue
                TARGETS="$paths"; projects_remove
                ;;
            3)
                f="$(git_config_file)"
                if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
                    if confirm "Disable .git/config hardening? opencode will be able to run git again."; then
                        git_config_apply off
                    fi
                else
                    if confirm "Enable .git/config hardening? opencode will NOT be able to run ANY git command."; then
                        git_config_apply on
                    fi
                fi
                ;;
            4) refresh ;;
            q|Q|quit|exit) echo "Bye."; exit 0 ;;
            *) echo "${YELLOW}Unknown selection.${NC}" ;;
        esac
        echo ""
    done
}

# --- dispatch ----------------------------------------------------------------

need_install

if [ -z "$ACTION" ]; then
    menu
    exit 0
fi

case "$ACTION" in
    status)     banner; git_config_status; echo ""; projects_list ;;
    projects)
        case "$SUB" in
            list)   banner; projects_list ;;
            add)    banner; projects_add ;;
            remove) banner; projects_remove ;;
            *)      die "Usage: config.sh projects list|add|remove <path...>" ;;
        esac
        ;;
    git-config)
        case "$SUB" in
            on|off) banner; git_config_apply "$SUB" ;;
            status|"") banner; git_config_status ;;
            *)      die "Usage: config.sh git-config on|off|status" ;;
        esac
        ;;
    refresh)    banner; refresh ;;
    *)          die "Unknown action: $ACTION" ;;
esac

echo ""
echo "  ${GREEN}Done.${NC}"