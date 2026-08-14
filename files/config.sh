#!/bin/sh
# opencode permissions kit -- config.sh
# Change settings AFTER install.sh has been run. Re-runs without re-asking
# the install-time questions. Reads /etc/opencode-permissions-kit/install.conf for context.
#
# What it can do:
#   - List / add / remove project roots in /etc/opencode-permissions-kit/projects.conf
#   - Toggle .git/config hardening for the opencode user
#   - Refresh ACL protection (re-run protect-projects.sh --force)
#   - Switch the container backend (docker-group / docker-rootless / podman-rootless)
#
# Run as your default (non-root) user with sudo privileges:
#   ./config.sh                       # interactive menu
#   ./config.sh projects list
#   ./config.sh projects add /var/www/vhosts/foo
#   ./config.sh projects remove /var/www/vhosts/foo
#   ./config.sh git-config on|off|status
#   ./config.sh container-backend docker-group|docker-rootless|podman-rootless|status
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
DDEV_BIN="${DDEV_BIN:-/usr/bin/ddev}"

YES=false
ACTION=""
SUB=""
TARGETS=""

for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        projects|git-config|refresh|status|container-backend|ddev-mode)
            [ -z "$ACTION" ] && ACTION="$arg" && continue
            [ "$ACTION" = "projects" ] && SUB="$arg" && continue
            TARGETS="$TARGETS $arg"
            ;;
        on|off)  [ "$ACTION" = "git-config" ] && SUB="$arg" ;;
        docker-group|docker-rootless|podman-rootless)
            [ "$ACTION" = "container-backend" ] && SUB="$arg" ;;
        delegated|sandbox)
            [ "$ACTION" = "ddev-mode" ] && SUB="$arg" ;;
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

# --- container backend (Phase 2) ----------------------------------------------

container_backend_status() {
    local backend="${CONTAINER_BACKEND:-docker-group}"
    echo "Container backend: ${CYAN}${backend}${NC}"
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
            local dg="$(getent group docker 2>/dev/null | cut -d: -f3)"
            if [ -n "$dg" ]; then
                echo "  docker group: ${GREEN}present (gid $dg)${NC}"
            else
                echo "  docker group: ${YELLOW}absent${NC}"
            fi
            ;;
    esac
}

# Re-render the sudoers for a given backend. Mirrors install.sh/update.sh: keep
# the (opencode:docker) grant for docker-group, strip it for rootless. Also
# keeps only the ddev block matching DDEV_MODE (delegated vs sandbox are
# mutually exclusive).
render_sudoers() {
    local backend="$1"
    local ddev_mode="${2:-${DDEV_MODE:-delegated}}"
    local template=""
    for cand in "$LIBDIR/sudoers.template" "$SCRIPT_DIR/sudoers.template" "$SCRIPT_DIR/../files/sudoers.template"; do
        if [ -f "$cand" ]; then template="$cand"; break; fi
    done
    [ -n "$template" ] || die "sudoers.template not found."
    local tmp
    tmp=$(mktemp)
    sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" -e "s#DDEV_BIN#$DDEV_BIN#g" "$template" > "$tmp"
    case "$backend" in
        docker-rootless|podman-rootless)
            sed -e '/^#@docker-group-begin$/,/^#@docker-group-end$/d' "$tmp" > "$tmp.2"
            ;;
        *)
            sed -e '/^#@docker-group-begin$/d' -e '/^#@docker-group-end$/d' "$tmp" > "$tmp.2"
            ;;
    esac
    mv -f "$tmp.2" "$tmp"
    if [ "$ddev_mode" = "sandbox" ]; then
        sed -e '/^#@ddev-delegated-begin$/,/^#@ddev-delegated-end$/d' \
            -e '/^#@ddev-sandbox-begin$/d' -e '/^#@ddev-sandbox-end$/d' "$tmp" > "$tmp.2"
    else
        sed -e '/^#@ddev-sandbox-begin$/,/^#@ddev-sandbox-end$/d' \
            -e '/^#@ddev-delegated-begin$/d' -e '/^#@ddev-delegated-end$/d' "$tmp" > "$tmp.2"
    fi
    mv -f "$tmp.2" "$tmp"
    sudo cp "$tmp" /etc/opencode-permissions-kit/sudoers
    sudo chmod 440 /etc/opencode-permissions-kit/sudoers
    rm -f "$tmp"
    sudo ln -sf /etc/opencode-permissions-kit/sudoers /etc/sudoers.d/opencode-permissions-kit
    if sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1; then
        echo "  sudoers re-rendered for $backend."
        log "sudoers re-rendered (backend=$backend)"
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

    local prev="${CONTAINER_BACKEND:-docker-group}"
    echo "Switching container backend: ${CYAN}${prev}${NC} -> ${CYAN}${new_backend}${NC}"

    if ! confirm "Provision '$new_backend' for $OPENCODE_USER?"; then
        echo "  Aborted."
        return 1
    fi

    # Provision the new backend (or teardown for docker-group).
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

    # Combo guard: sandbox ddev requires a rootless backend. Switching to
    # docker-group therefore falls back to delegated ddev mode.
    if [ "$new_backend" = "docker-group" ] && [ "${DDEV_MODE:-delegated}" = "sandbox" ]; then
        echo "${YELLOW}Backend docker-group is incompatible with ddev mode 'sandbox' — falling back to 'delegated'.${NC}"
        update_install_conf_ddev_mode "delegated"
        DDEV_MODE="delegated"
    fi

    # Re-render the sudoers for the new backend.
    render_sudoers "$new_backend" "${DDEV_MODE:-delegated}"

    echo ""
    echo "  ${GREEN}Container backend switched to '$new_backend'.${NC}"
    echo "  Restart any running opencode sessions to pick up the new backend."
    log "container backend switched: $prev -> $new_backend"
}

# --- ddev mode (delegated | sandbox) ------------------------------------------

REWRITES_CONF="/etc/opencode-permissions-kit/ddev-rewrites.conf"

update_install_conf_ddev_mode() {
    local mode="$1" tmp
    tmp=$(mktemp)
    {
        if [ -f "$INSTALL_CONF" ]; then
            grep -v '^DDEV_MODE=' "$INSTALL_CONF" 2>/dev/null
        fi
        echo "DDEV_MODE=$mode"
    } | sort -u > "$tmp"
    sudo cp "$tmp" "$INSTALL_CONF"
    sudo chmod 644 "$INSTALL_CONF"
    rm -f "$tmp"
}

ddev_mode_status() {
    local mode="${DDEV_MODE:-delegated}"
    echo "ddev mode: ${CYAN}${mode}${NC}"
    case "$mode" in
        sandbox) echo "  ddev (and its host commands) runs as '$OPENCODE_USER' inside a transaction;" ;;
        *)       echo "  ddev invoked by the agent runs as '$DEFAULT_USER' via the delegation shim;" ;;
    esac
    echo "  mutating subcommands: $( [ "$mode" = sandbox ] && echo 'ddev-transaction.sh (OPEN/RUN/CLOSE)' || echo "sudo -u $DEFAULT_USER $DDEV_BIN" )"
    if [ "$mode" = "sandbox" ]; then
        if [ -f "$REWRITES_CONF" ]; then
            echo "  rewrite list: $REWRITES_CONF ($(grep -vc '^\s*#\|^\s*$' "$REWRITES_CONF" 2>/dev/null || echo '?') entries)"
        else
            echo "  rewrite list: ${YELLOW}missing ($REWRITES_CONF)${NC}"
        fi
    fi
}

ddev_mode_apply() {
    local new_mode="$1"
    local prev="${DDEV_MODE:-delegated}"
    [ "$new_mode" = "$prev" ] && { echo "ddev mode is already '$new_mode'."; return 0; }

    if [ "$new_mode" = "sandbox" ]; then
        # Hard gate: sandbox ddev requires a rootless backend (on docker-group
        # the container root would void every ACL deny — PROOF-3 C3).
        case "${CONTAINER_BACKEND:-docker-group}" in
            docker-rootless|podman-rootless) ;;
            *) die "ddev mode 'sandbox' requires a rootless container backend (current: ${CONTAINER_BACKEND:-docker-group}). Run 'config.sh container-backend docker-rootless|podman-rootless' first." ;;
        esac
        # Soft gate: ddev >= 1.25 for rootless operation (--yes skips: the
        # admin takes responsibility, e.g. for a version the parser can't read).
        local dver="${DDEV_VERSION:-}"
        if [ -z "$dver" ] && [ -x "$DDEV_BIN" ]; then
            dver="$("$DDEV_BIN" version 2>/dev/null | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')"
        fi
        if [ -n "$dver" ]; then
            local ok
            ok=$(awk -v v="$dver" 'BEGIN{split(v,a,"."); if(a[1]+0>1 || (a[1]+0==1 && a[2]+0>=25)) print "yes"; else print "no"}')
            if [ "$ok" != "yes" ] && [ "$YES" != true ]; then
                die "ddev mode 'sandbox' needs ddev >= 1.25 (found ${dver}). Use --yes to override."
            fi
            [ "$ok" != "yes" ] && echo "${YELLOW}WARNING: overriding the ddev >= 1.25 requirement (found ${dver}).${NC}"
        else
            [ "$YES" = true ] || die "cannot determine the ddev version — use --yes to override."
        fi
    fi

    echo "Switching ddev mode: ${CYAN}${prev}${NC} -> ${CYAN}${new_mode}${NC}"
    confirm "Apply ddev mode '$new_mode'?" || { echo "  Aborted."; return 1; }

    if [ "$new_mode" = "sandbox" ]; then
        # Provision the sandbox-side ddev home + the root-owned rewrite list
        # (mirrors install.sh; idempotent).
        sudo mkdir -p "/home/$OPENCODE_USER/.ddev"
        sudo chown "$OPENCODE_USER:$WWW_GROUP" "/home/$OPENCODE_USER/.ddev"
        sudo chmod 755 "/home/$OPENCODE_USER/.ddev"
        if [ ! -f "$REWRITES_CONF" ]; then
            sudo tee "$REWRITES_CONF" > /dev/null <<'EOF'
# opencode permissions kit — ddev sandbox rewrite list.
# Relative paths/globs under registered project roots that `ddev start` and
# friends rewrite on the HOST. The transaction helper grants u:opencode
# access on these for the duration of a mutating ddev run only. ROOT-OWNED:
# entries here are executed as root-side file operations — keep this file
# unwritable for everyone but root (mode 644, no group write).
# Default: TYPO3 layout.
config/system
config/system/settings.php
config/system/additional.php
config/system/.gitignore
EOF
            sudo chmod 644 "$REWRITES_CONF"
        fi
        sudo mkdir -p /run/opencode-permissions-kit/ddev-txn 2>/dev/null || true
        sudo chmod 755 /run/opencode-permissions-kit/ddev-txn 2>/dev/null || true

        # Router ports: rootless ddev-router cannot bind <1024. Lower the
        # unprivileged port start to 80, persisted via sysctl.d. Host-wide
        # change: interactive runs are asked (default N); --yes applies.
        port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)
        if [ "${port_start:-1024}" -gt 80 ] 2>/dev/null; then
            if confirm "Lower net.ipv4.ip_unprivileged_port_start to 80 so ddev-router can bind 80/443?"; then
                if echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-ddev-rootless.conf >/dev/null 2>&1; then
                    if sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1; then
                        echo "  unprivileged port start lowered to 80 (persisted: /etc/sysctl.d/99-ddev-rootless.conf)"
                        log "ddev sandbox: net.ipv4.ip_unprivileged_port_start=80 applied"
                    else
                        echo "${YELLOW}WARNING: sysctl persisted but not activated live (read-only /proc/sys?) — reboot or run:${NC}"
                        echo "  sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
                        log "ddev sandbox: sysctl persisted but not activated live"
                    fi
                else
                    echo "${YELLOW}WARNING: could not write /etc/sysctl.d/99-ddev-rootless.conf — apply the sysctl manually or use higher router ports.${NC}"
                fi
            else
                echo "  Skipped — either set the sysctl manually or use higher router ports:"
                echo "  sudo -u $OPENCODE_USER ddev config global --router-http-port 8080 --router-https-port 8443"
            fi
        fi

        # HTTPS first-run: create the sandbox user's mkcert CA (best-effort).
        # ddev bundles mkcert in ~/.ddev/bin only after the first ddev start;
        # until then print the manual step. The system-trust part of
        # 'mkcert -install' cannot succeed unprivileged — harmless, the CA
        # files are what ddev needs; browser/host trust stays a manual import.
        caroot="/home/$OPENCODE_USER/.local/share/mkcert"
        mkcert_bin="/home/$OPENCODE_USER/.ddev/bin/mkcert"
        if [ ! -f "$caroot/rootCA.pem" ]; then
            if [ -x "$mkcert_bin" ]; then
                sudo -u "$OPENCODE_USER" env CAROOT="$caroot" "$mkcert_bin" -install >/dev/null 2>&1 || true
                if [ -f "$caroot/rootCA.pem" ]; then
                    echo "  mkcert CA created: $caroot (import rootCA.pem into your browser for HTTPS trust)"
                    log "ddev sandbox: mkcert CA created for $OPENCODE_USER"
                fi
            else
                echo "  NOTE: mkcert not downloaded yet — after the first ddev start create the CA:"
                echo "  sudo -u $OPENCODE_USER env CAROOT=$caroot $mkcert_bin -install"
            fi
        fi
    fi

    update_install_conf_ddev_mode "$new_mode"
    DDEV_MODE="$new_mode"
    render_sudoers "${CONTAINER_BACKEND:-docker-group}" "$new_mode"

    echo ""
    echo "  ${GREEN}ddev mode switched to '$new_mode'.${NC}"
    if [ "$new_mode" = "sandbox" ]; then
        echo "  ddev now runs as '$OPENCODE_USER' (transactional); restart running opencode sessions."
    else
        echo "  ddev invoked by the agent is delegated to '$DEFAULT_USER' again; restart running opencode sessions."
    fi
    log "ddev mode switched: $prev -> $new_mode"
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
        container_backend_status 2>/dev/null || true
        projects_list
        echo ""
        echo "  [1] Add project root"
        echo "  [2] Remove project root"
        echo "  [3] Toggle .git/config hardening (on/off)"
        echo "  [4] Refresh ACL protection now"
        echo "  [5] Switch container backend (docker-group / rootless)"
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
            5)
                banner
                container_backend_status
                echo ""
                echo "  [1] docker-group (default — no host change, root-equivalent)"
                echo "  [2] podman-rootless (daemonless — ACL denies hold)"
                echo "  [3] docker-rootless (needs systemd --user)"
                echo "  [q] Cancel"
                printf "  > "
                read -r _be_sel </dev/tty 2>/dev/null || read -r _be_sel
                case "$_be_sel" in
                    1) container_backend_apply docker-group || true ;;
                    2) container_backend_apply podman-rootless || true ;;
                    3) container_backend_apply docker-rootless || true ;;
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
            docker-group|docker-rootless|podman-rootless)
                banner; container_backend_apply "$SUB" ;;
            status|"") banner; container_backend_status ;;
            *)      die "Usage: config.sh container-backend docker-group|docker-rootless|podman-rootless|status" ;;
        esac
        ;;
    ddev-mode)
        case "$SUB" in
            delegated|sandbox)
                banner; ddev_mode_apply "$SUB" ;;
            status|"") banner; ddev_mode_status ;;
            *)      die "Usage: config.sh ddev-mode delegated|sandbox|status" ;;
        esac
        ;;
    refresh)    banner; refresh ;;
    *)          die "Unknown action: $ACTION" ;;
esac

echo ""
echo "  ${GREEN}Done.${NC}"