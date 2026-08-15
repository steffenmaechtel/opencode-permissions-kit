#!/bin/sh
# opencode permissions kit -- config.sh
# Change settings AFTER install.sh has been run. Re-runs without re-asking
# the install-time questions. Reads /etc/opencode-permissions-kit/install.conf for context.
#
# What it can do:
#   - List / add / remove project roots in /etc/opencode-permissions-kit/projects.conf
#   - Toggle .git/config hardening for the opencode user (SOFT-only)
#   - Refresh the group baseline (re-run migrate-denies.sh group re-base)
#   - Switch the container backend (docker-rootless / podman-rootless)
#
# Run as your default (non-root) user with sudo privileges:
#   ./config.sh                       # interactive menu
#   ./config.sh projects list
#   ./config.sh projects add /var/www/vhosts/foo
#   ./config.sh projects remove /var/www/vhosts/foo
#   ./config.sh git-config on|off|status
#   ./config.sh container-backend docker-rootless|podman-rootless|status
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
OPENCODE_GROUP="opencode"
if [ -f "$INSTALL_CONF" ]; then
    . "$INSTALL_CONF"
fi
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
# Sharing group: prefer the OPENCODE_GROUP key, fall back to the legacy
# WWW_GROUP key a pre-rename install.conf still carries. The sharing group
# is the opencode user's own usergroup; prefer the live value over any
# stale conf entry (e.g. www-data from a pre-migration install).
OPENCODE_GROUP="${OPENCODE_GROUP:-${WWW_GROUP:-opencode}}"
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
[ -n "$LIVE_GROUP" ] && OPENCODE_GROUP="$LIVE_GROUP"

YES=false
ACTION=""
SUB=""
TARGETS=""

for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        projects|git-config|refresh|status|container-backend)
            [ -z "$ACTION" ] && ACTION="$arg" && continue
            [ "$ACTION" = "projects" ] && SUB="$arg" && continue
            TARGETS="$TARGETS $arg"
            ;;
        on|off)  [ "$ACTION" = "git-config" ] && SUB="$arg" ;;
        docker-rootless|podman-rootless)
            [ "$ACTION" = "container-backend" ] && SUB="$arg" ;;
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

# Shared ddev handover helpers (.ddev + settings dirs -> opencode user).
# Prefer the copy alongside this config.sh (repo checkout), then the
# installed library — same lookup order as the migrate script below.
_handover=""
for cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" "$LIBDIR/ddev-handover.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        _handover="$cand"
        break
    fi
done
[ -n "$_handover" ] || ddev_handover_root() { :; }

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
        # Apply the group baseline so the developer/agent share files immediately
        sudo chgrp -R "$OPENCODE_GROUP" "$p" 2>/dev/null || true
        sudo chmod g+s "$p"
        sudo setfacl -R -d -m "g:$OPENCODE_GROUP:rwx" "$p" 2>/dev/null || true
        # ddev handover (.ddev + the app-type's settings dirs at any depth):
        # ddev always runs as $OPENCODE_USER and chmods these paths
        # unconditionally — they must belong to it or `ddev start` fails
        # with "operation not permitted". The registered path may be a
        # parent of several projects.
        ddev_handover_root "$p" "$OPENCODE_USER" "$OPENCODE_GROUP"
        echo "  ${GREEN}added${NC} $p (group=$OPENCODE_GROUP, setgid, default-acl)"
        log "project added: $p"
    done
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
        if ! confirm "Remove '$p' from projects.conf?"; then
            echo "  skip $p"
            continue
        fi
        sudo grep -vx "$p" "$PROJECTS_CONF" | sudo tee "$PROJECTS_CONF.tmp" > /dev/null
        sudo mv "$PROJECTS_CONF.tmp" "$PROJECTS_CONF"
        echo "  ${GREEN}removed${NC} $p"
        log "project removed: $p"
    done
}

# --- git-config toggle (SOFT-only) ---------------------------------------------

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
        echo "git-config hardening: ${GREEN}ON${NC}  ($f, soft-only)"
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
    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "$target"
    sudo chmod 664 "$target"

    if [ "$enable" = "on" ]; then
        sudo sed -i 's|//SECURE_GIT: ||' "$target"
        echo "git-config hardening: ${GREEN}ON${NC}  ($target, soft-only)"
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' "$target"
        echo "git-config hardening: ${CYAN}OFF${NC}  ($target)"
    fi
    log "git-config hardening set to $enable ($target)"
    echo "NOTE: existing config was overwritten from template. Restart opencode to pick up changes."
}

# --- container backend ----------------------------------------------------------

container_backend_status() {
    local backend="${CONTAINER_BACKEND:-}"
    if [ -z "$backend" ]; then
        echo "Container backend: ${RED}none configured${NC}"
        echo "  A legacy install (docker-group) must be re-installed:"
        echo "    sudo bash files/install.sh --container-backend docker-rootless"
        return
    fi
    echo "Container backend: ${CYAN}$backend${NC}"
    case "$backend" in
        docker-rootless)
            if [ -n "${OPENCODE_DOCKER_HOST:-}" ]; then
                local sock="$OPENCODE_DOCKER_HOST" sp="${OPENCODE_DOCKER_HOST#unix://}"
                if [ -S "$sp" ]; then
                    echo "  socket: ${GREEN}reachable${NC}  $sock"
                else
                    echo "  socket: ${RED}NOT reachable${NC}  $sock"
                fi
            else
                echo "  socket: ${YELLOW}not configured${NC}"
            fi
            ;;
        podman-rootless)
            if [ -n "${OPENCODE_PODMAN_SOCKET:-}" ]; then
                local sp="${OPENCODE_PODMAN_SOCKET#unix://}"
                if [ -S "$sp" ]; then
                    echo "  socket: ${GREEN}reachable${NC}  $OPENCODE_PODMAN_SOCKET"
                else
                    echo "  socket: ${RED}NOT reachable${NC}  $OPENCODE_PODMAN_SOCKET"
                fi
            elif command -v podman >/dev/null 2>&1; then
                echo "  podman CLI: ${GREEN}installed${NC}"
            else
                echo "  podman CLI: ${RED}NOT installed${NC}"
            fi
            ;;
        *)
            echo "  ${YELLOW}legacy backend '$backend' — re-run install.sh with a rootless backend${NC}"
            ;;
    esac
}

# Re-render the sudoers. The soft-only template needs only the DEFAULT_USER
# substitution (no backend/ddev-mode conditionals anymore).
render_sudoers() {
    local template=""
    for cand in "$LIBDIR/sudoers.template" "$SCRIPT_DIR/sudoers.template" "$SCRIPT_DIR/../files/sudoers.template"; do
        if [ -f "$cand" ]; then template="$cand"; break; fi
    done
    [ -n "$template" ] || die "sudoers.template not found."
    local tmp
    tmp=$(mktemp)
    sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" "$template" > "$tmp"
    sudo cp "$tmp" /etc/opencode-permissions-kit/sudoers
    sudo chmod 440 /etc/opencode-permissions-kit/sudoers
    rm -f "$tmp"
    sudo ln -sf /etc/opencode-permissions-kit/sudoers /etc/sudoers.d/opencode-permissions-kit
    if sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1; then
        echo "  sudoers re-rendered."
        log "sudoers re-rendered"
    else
        die "sudoers validation failed. Check /etc/opencode-permissions-kit/sudoers."
    fi
}

# Update install.conf: rewrite the backend keys while preserving everything else.
update_install_conf_backend() {
    local backend="$1" docker_host="$2" podman_socket="$3"
    local tmp
    tmp=$(mktemp)
    {
        if [ -f "$INSTALL_CONF" ]; then
            grep -v -e '^CONTAINER_BACKEND=' -e '^OPENCODE_DOCKER_HOST=' -e '^OPENCODE_PODMAN_SOCKET=' "$INSTALL_CONF" 2>/dev/null
        fi
        echo "CONTAINER_BACKEND=$backend"
        [ -n "$docker_host" ] && echo "OPENCODE_DOCKER_HOST=$docker_host"
        [ -n "$podman_socket" ] && echo "OPENCODE_PODMAN_SOCKET=$podman_socket"
    } | sort -u > "$tmp"
    sudo cp "$tmp" "$INSTALL_CONF"
    sudo chmod 644 "$INSTALL_CONF"
    rm -f "$tmp"
}

container_backend_apply() {
    local new_backend="$1"
    # Prefer the setup script alongside this config.sh (repo checkout), then
    # fall back to the installed library. This ensures the repo version is used
    # when running from a checkout — important during development / testing.
    local setup_script=""
    for cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh" "$LIBDIR/setup-container-backend.sh"; do
        if [ -f "$cand" ]; then setup_script="$cand"; break; fi
    done
    [ -n "$setup_script" ] || die "setup-container-backend.sh not found."

    local prev="${CONTAINER_BACKEND:-none}"
    echo "Switching container backend: ${CYAN}${prev}${NC} -> ${CYAN}${new_backend}${NC}"

    if ! confirm "Provision '$new_backend' for $OPENCODE_USER?"; then
        echo "  Aborted."
        return 1
    fi

    # Provision the new backend.
    local docker_host="" podman_socket=""
    local setup_out
    setup_out=$(sudo sh "$setup_script" "$new_backend" --yes 2>&1) || {
        echo "${RED}Provisioning failed:${NC}"
        echo "$setup_out" | grep -v '^OPENCODE_' | sed 's/^/  /'
        echo "${YELLOW}Backend not changed.${NC}"
        return 1
    }
    echo "$setup_out" | grep -v '^OPENCODE_' | sed 's/^/  /'
    # Capture socket key from the helper output.
    docker_host=$(echo "$setup_out" | sed -n 's/^OPENCODE_DOCKER_HOST=//p' | tail -1)

    # Update install.conf.
    update_install_conf_backend "$new_backend" "$docker_host" "$podman_socket"

    # Re-render the sudoers.
    render_sudoers

    echo ""
    echo "  ${GREEN}Container backend switched to '$new_backend'.${NC}"
    echo "  Restart any running opencode sessions to pick up the new backend."
    log "container backend switched: $prev -> $new_backend"
}

# --- refresh (group baseline) ---------------------------------------------------

refresh() {
    local migrate=""
    for cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/migrate-denies.sh" "$LIBDIR/migrate-denies.sh"; do
        if [ -f "$cand" ]; then migrate="$cand"; break; fi
    done
    [ -n "$migrate" ] || die "migrate-denies.sh not found."
    echo "Re-applying the group baseline (chgrp $OPENCODE_GROUP + setgid + default ACLs) ..."
    sudo sh "$migrate" \
        --projects "$PROJECTS_CONF" \
        --conf-dir /etc/opencode-permissions-kit \
        --lib-dir "$LIBDIR" \
        --opencode-user "$OPENCODE_USER" \
        --group "$OPENCODE_GROUP"
    echo "${GREEN}Group baseline refreshed.${NC}"
    log "group baseline refresh requested"
}

# --- interactive menu --------------------------------------------------------

menu() {
    banner
    while true; do
        echo "Current settings:"
        git_config_status 2>/dev/null || true
        container_backend_status 2>/dev/null || true
        projects_list
        echo ""
        echo "  [1] Add project root"
        echo "  [2] Remove project root"
        echo "  [3] Toggle .git/config hardening (on/off, soft-only)"
        echo "  [4] Refresh group baseline now"
        echo "  [5] Switch container backend (docker-rootless / podman-rootless)"
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
                    if confirm "Enable .git/config hardening (soft-only)? opencode tools will not touch .git/config."; then
                        git_config_apply on
                    fi
                fi
                ;;
            4) refresh ;;
            5)
                banner
                container_backend_status
                echo ""
                echo "  [1] docker-rootless (needs systemd --user)"
                echo "  [2] podman-rootless (daemonless)"
                echo "  [q] Cancel"
                printf "  > "
                read -r _be_sel </dev/tty 2>/dev/null || read -r _be_sel
                case "$_be_sel" in
                    1) container_backend_apply docker-rootless || true ;;
                    2) container_backend_apply podman-rootless || true ;;
                    *) echo "  Cancelled." ;;
                esac
                ;;
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
    container-backend)
        case "$SUB" in
            docker-rootless|podman-rootless)
                banner; container_backend_apply "$SUB" ;;
            status|"") banner; container_backend_status ;;
            *)      die "Usage: config.sh container-backend docker-rootless|podman-rootless|status" ;;
        esac
        ;;
    refresh)    banner; refresh ;;
    *)          die "Unknown action: $ACTION" ;;
esac

echo ""
echo "  ${GREEN}Done.${NC}"
