#!/bin/sh
# opencode permissions kit -- config.sh
# Change settings AFTER install.sh has been run. Re-runs without re-asking
# the install-time questions. Reads /etc/opencode-permissions-kit/install.conf for context.
#
# What it can do:
#   - List / add / remove project roots in /etc/opencode-permissions-kit/projects.conf
#   - Toggle .git/config hardening for the opencode user (SOFT-only)
#   - Refresh the group baseline (re-apply chgrp/setgid/default ACLs)
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

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LIBDIR="/usr/local/lib/opencode-permissions-kit"

# === Shared UI helpers ===
# Checkout copy first, then the deployed library; a plain fallback keeps
# config.sh working on an install whose library predates ui.sh.
UI_LIB=""
for _cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/ui.sh" "$LIBDIR/ui.sh"; do
    if [ -f "$_cand" ]; then UI_LIB="$_cand"; break; fi
done
if [ -n "$UI_LIB" ]; then
    . "$UI_LIB"
else
    ui_info()    { echo "  info     $1"; }
    ui_success() { echo "  success  $1"; }
    ui_warn()    { echo "  warn     $1"; }
    ui_error()   { echo "  error    $1" >&2; }
    ui_detail()  { echo "     $1"; }
    ui_section() { echo ""; echo "  --- $1 ---"; echo ""; }
    ui_banner()  { echo ""; echo "  opencode permissions kit  v${1:-}"; echo ""; }
    ui_kv()      { printf '  %-14s %s\n' "$1" "$2"; }
    ui_kv_warn() { printf '  %-14s %s\n' "$1" "$2"; }
    UI_GREEN=''; UI_RED=''; UI_YELLOW=''; UI_CYAN=''; UI_BLUE=''; UI_NC=''
fi
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"

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

# install.conf (canonical path since 0.0.10)
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"

DEFAULT_USER=""
OPENCODE_USER="opencode"
OPENCODE_GROUP="opencode"
if [ -f "$INSTALL_CONF" ]; then
    . "$INSTALL_CONF"
fi
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
# ~ in project paths must expand to the DEFAULT user's home, not $HOME:
# config.sh usually runs via sudo, where $HOME is /root and "~/dev" would
# be rejected as a "/root system path" with a confusing error.
# project_path_sane reads PROJECT_TILDE_HOME.
PROJECT_TILDE_HOME="$HOME"
if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ]; then
    _th="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
    if [ -n "$_th" ]; then PROJECT_TILDE_HOME="$_th"; fi
fi
# Sharing group: the opencode user's own usergroup; prefer the live value
# over any stale conf entry.
OPENCODE_GROUP="${OPENCODE_GROUP:-opencode}"
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
    ui_banner "${VERSION:-}" "config — change settings"
}

die() { ui_error "$*"; exit 1; }

confirm() {
    # Convention: docs/design/conventions.md — default capital in the hint,
    # Enter accepts it, y/yes/n/no case-insensitive. ui_confirm handles all
    # of that; this wrapper only adds the --yes shortcut.
    [ "$YES" = true ] && return 0
    ui_confirm "$1" "n"
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
# installed library — same lookup order as everywhere else.
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
    ui_info "Project roots ($PROJECTS_CONF):"
    if [ ! -f "$PROJECTS_CONF" ] || [ ! -s "$PROJECTS_CONF" ]; then
        ui_detail "(none configured)"
        return
    fi
    num=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        num=$((num + 1))
        if [ -d "$line" ]; then
            ui_have "[$num] $line" ""
        else
            ui_atten "[$num] $line" "missing"
        fi
    done < "$PROJECTS_CONF"
    [ "$num" -eq 0 ] && ui_detail "(none configured)"
}

# Same policy as install.sh: never run the group baseline (chgrp -R +
# setfacl -R) over a system path. Allowed: dedicated project folders
# (/var/www/..., /home/<user>/..., ~/...). "~" is expanded; the normalized
# path is returned in _PP_NORM for the caller.
project_path_sane() {
    _pp="${1%/}"
    [ -n "$_pp" ] || return 1
    # expand ~ / ~/... / ~name is rejected (no user lookup). Note: the ~ in
    # the pattern must be escaped (\~) or it tilde-expands and never matches.
    # ~ resolves against PROJECT_TILDE_HOME (the DEFAULT user's home when
    # running under sudo — $HOME would be /root).
    # shellcheck disable=SC2088  # tilde deliberately literal: matching ~ input
    if [ "$_pp" = "~" ]; then _pp="${PROJECT_TILDE_HOME:-$HOME}"; else case "$_pp" in
        "~/"*) _pp="${PROJECT_TILDE_HOME:-$HOME}${_pp#\~}" ;;
        "~"*) return 1 ;;
    esac; fi
    _PP_NORM="$_pp"
    case "$_pp" in
        /*) ;;
        *)  return 1 ;;   # relative paths are error-prone in projects.conf
    esac
    case "$_pp" in
        *..*|/./|*/./*|./*) return 1 ;;   # traversal / dot segments
    esac
    case "$_pp" in
        /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/lib*|\
/media|/media/*|/mnt|/mnt/*|/opt|/opt/*|/proc|/proc/*|/root|/root/*|\
/run|/run/*|/sbin|/sbin/*|/srv|/srv/*|/sys|/sys/*|/tmp|/var/tmp/*|\
/usr|/usr/*|/var|/var/tmp|/var/cache|/var/cache/*|/var/lib|/var/lib/*|\
/var/log|/var/log/*|/var/mail|/var/mail/*|/var/spool|/var/spool/*)
            return 1
            ;;
    esac
    return 0
}

projects_add() {
    [ -z "$TARGETS" ] && die "Usage: config.sh projects add <path...>"
    sudo mkdir -p "$(dirname "$PROJECTS_CONF")"
    for p in $TARGETS; do
        if ! project_path_sane "$p"; then
            ui_error "'$p' is a system path — refusing to add it (chgrp -R/setfacl -R would run over it)."
            continue
        fi
        p="${_PP_NORM:-$p}"
        if _p_abs=$(cd "$p" 2>/dev/null && pwd); then p="$_p_abs"; fi
        if ! [ -d "$p" ]; then
            ui_warn "skip $p (not a directory)"
            continue
        fi
        if [ -f "$PROJECTS_CONF" ] && grep -qxF "$p" "$PROJECTS_CONF"; then
            ui_detail "exists: $p"
            continue
        fi
        echo "$p" | sudo tee -a "$PROJECTS_CONF" > /dev/null
        # Apply the group baseline so the developer/agent share files immediately
            sudo chgrp -R "$OPENCODE_GROUP" "$p" 2>/dev/null || true
            sudo chmod g+s "$p"
            # Recursive baseline like install.sh Step 5: setgid on every
            # directory, group-write on files — .git stays developer-private.
            sudo find "$p" -name .git -prune -o -type d -exec chmod g+s {} + 2>/dev/null || true
            sudo find "$p" -name .git -prune -o -type f -exec chmod g+rw {} + 2>/dev/null || true
            sudo setfacl -R -d -m "g:$OPENCODE_GROUP:rwx" "$p" 2>/dev/null || true
        # ddev handover (.ddev + the app-type's settings dirs at any depth):
        # ddev always runs as $OPENCODE_USER and chmods these paths
        # unconditionally — they must belong to it or `ddev start` fails
        # with "operation not permitted". The registered path may be a
        # parent of several projects.
        ddev_handover_root "$p" "$OPENCODE_USER" "$OPENCODE_GROUP" "$DEFAULT_USER"
        ui_success "added $p (group=$OPENCODE_GROUP, setgid, default-acl)"
        log "project added: $p"
    done
}

projects_remove() {
    [ -z "$TARGETS" ] && die "Usage: config.sh projects remove <path...>"
    [ -f "$PROJECTS_CONF" ] || { echo "No projects.conf — nothing to remove."; return; }
    for p in $TARGETS; do
        if _p_abs=$(cd "$p" 2>/dev/null && pwd); then p="$_p_abs"; fi
        if ! grep -qxF "$p" "$PROJECTS_CONF"; then
            ui_warn "not found: $p"
            continue
        fi
        if ! confirm "Remove '$p' from projects.conf?"; then
            ui_detail "skip $p"
            continue
        fi
        sudo grep -vxF "$p" "$PROJECTS_CONF" | sudo tee "$PROJECTS_CONF.tmp" > /dev/null
        sudo mv "$PROJECTS_CONF.tmp" "$PROJECTS_CONF"
        ui_success "removed $p"
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
        ui_kv "git-config" "ON  ($f, soft-only)" "$UI_GREEN"
    elif grep -q '//SECURE_GIT' "$f" 2>/dev/null; then
        ui_kv "git-config" "OFF  ($f — markers present, rules inactive)"
    else
        ui_kv "git-config" "OFF  ($f)"
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
        ui_kv "git-config" "ON  ($target, soft-only)" "$UI_GREEN"
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' "$target"
        ui_kv "git-config" "OFF  ($target)"
    fi
    log "git-config hardening set to $enable ($target)"
    ui_warn "existing config was overwritten from template. Restart opencode to pick up changes."
}

# --- container backend ----------------------------------------------------------

container_backend_status() {
    local backend="${CONTAINER_BACKEND:-}"
    if [ -z "$backend" ]; then
        ui_kv "backend" "none configured" "$UI_RED"
        ui_detail "re-run install.sh to configure a rootless backend:"
        ui_detail "sudo bash files/install.sh --container-backend docker-rootless"
        return
    fi
    ui_kv "backend" "$backend"
    case "$backend" in
        docker-rootless)
            if [ -n "${OPENCODE_DOCKER_HOST:-}" ]; then
                local sock="$OPENCODE_DOCKER_HOST" sp="${OPENCODE_DOCKER_HOST#unix://}"
                if [ -S "$sp" ]; then
                    ui_kv "socket" "reachable — $sock" "$UI_GREEN"
                else
                    ui_kv "socket" "NOT reachable — $sock" "$UI_RED"
                fi
            else
                ui_kv "socket" "not configured" "$UI_YELLOW"
            fi
            ;;
        podman-rootless)
            if [ -n "${OPENCODE_PODMAN_SOCKET:-}" ]; then
                local sp="${OPENCODE_PODMAN_SOCKET#unix://}"
                if [ -S "$sp" ]; then
                    ui_kv "socket" "reachable — $OPENCODE_PODMAN_SOCKET" "$UI_GREEN"
                else
                    ui_kv "socket" "NOT reachable — $OPENCODE_PODMAN_SOCKET" "$UI_RED"
                fi
            elif command -v podman >/dev/null 2>&1; then
                ui_kv "podman CLI" "installed" "$UI_GREEN"
            else
                ui_kv "podman CLI" "NOT installed" "$UI_RED"
            fi
            ;;
        *)
            ui_kv "backend" "unknown '$backend' — re-run install.sh with a rootless backend" "$UI_YELLOW"
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
        ui_success "sudoers re-rendered"
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
    ui_info "switching container backend: $prev -> $new_backend"

    if ! confirm "Provision '$new_backend' for $OPENCODE_USER?"; then
        ui_detail "aborted."
        return 1
    fi

    # Provision the new backend.
    local docker_host="" podman_socket=""
    local setup_out
    setup_out=$(sudo sh "$setup_script" "$new_backend" --yes 2>&1) || {
        ui_error "provisioning failed:"
        echo "$setup_out" | grep -v '^OPENCODE_' | sed 's/^/     /'
        ui_warn "backend not changed."
        return 1
    }
    echo "$setup_out" | grep -v '^OPENCODE_' | sed 's/^/     /'
    # Capture socket key from the helper output.
    docker_host=$(echo "$setup_out" | sed -n 's/^OPENCODE_DOCKER_HOST=//p' | tail -1)

    # Update install.conf.
    update_install_conf_backend "$new_backend" "$docker_host" "$podman_socket"

    # Re-render the sudoers.
    render_sudoers

    echo ""
    ui_success "container backend switched to '$new_backend'."
    ui_detail "restart any running opencode sessions to pick up the new backend"
    log "container backend switched: $prev -> $new_backend"
}

# --- refresh (group baseline) ---------------------------------------------------

refresh() {
    ui_info "re-applying the group baseline (chgrp $OPENCODE_GROUP + setgid + g+rw + default ACLs) ..."
    if [ -f "$PROJECTS_CONF" ]; then
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            [ -d "$p" ] || continue
            sudo chgrp -R "$OPENCODE_GROUP" "$p" 2>/dev/null || true
            sudo chmod g+s "$p" 2>/dev/null || true
            # Recursive baseline like install.sh Step 5: setgid on every
            # directory, group-write on files — .git stays developer-private.
            sudo find "$p" -name .git -prune -o -type d -exec chmod g+s {} + 2>/dev/null || true
            sudo find "$p" -name .git -prune -o -type f -exec chmod g+rw {} + 2>/dev/null || true
            sudo setfacl -R -d -m "g:$OPENCODE_GROUP:rwx" "$p" 2>/dev/null || true
            ddev_handover_root "$p" "$OPENCODE_USER" "$OPENCODE_GROUP" "$DEFAULT_USER"
        done < "$PROJECTS_CONF"
    fi
    ui_success "group baseline refreshed."
    log "group baseline refresh requested"
}

# --- interactive menu --------------------------------------------------------

menu() {
    banner
    while true; do
        ui_section "Current settings"
        git_config_status 2>/dev/null || true
        container_backend_status 2>/dev/null || true
        projects_list
        echo ""
        sel=$(ui_menu "What do you want to do?" "1" \
            "1|Add project root" \
            "2|Remove project root" \
            "3|Toggle .git/config hardening (on/off, soft-only)" \
            "4|Refresh group baseline now" \
            "5|Switch container backend (docker-rootless / podman-rootless)" \
            "q|Quit")
        case "$sel" in
            1)
                paths=$(ui_ask "Paths to add (space-separated)" "")
                [ -z "$paths" ] && continue
                ACTION=projects; SUB=add; TARGETS="$paths"; projects_add
                ;;
            2)
                paths=$(ui_ask "Path to remove" "")
                [ -z "$paths" ] && continue
                ACTION=projects; SUB=remove; TARGETS="$paths"; projects_remove
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
                _be_sel=$(ui_menu "Switch to which backend?" "1" \
                    "1|docker-rootless (needs systemd --user)" \
                    "2|podman-rootless (daemonless)" \
                    "q|Cancel")
                case "$_be_sel" in
                    1) container_backend_apply docker-rootless || true ;;
                    2) container_backend_apply podman-rootless || true ;;
                    *) ui_detail "cancelled." ;;
                esac
                ;;
            q) ui_info "Bye."; exit 0 ;;
            *) ui_warn "Unknown selection." ;;
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

ui_success "Done."
