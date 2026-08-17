#!/bin/sh
# opencode permissions kit -- setup-container-backend.sh
#
# Provisioning helper for the rootless container backends. Called by install.sh
# and config.sh to set up docker-rootless or podman-rootless for the opencode
# user, or to tear down the previously provisioned backend when switching
# between the two.
#
# Usage:
#   setup-container-backend.sh <backend> [--yes]
#     backend: docker-rootless | podman-rootless | docker-group
#     --yes:   skip confirmations
#
# What it does (for rootless backends):
#   1. Install prerequisite packages (uidmap, dbus-user-session, podman or
#      docker-ce-rootless-extras) via apt-get (only if missing).
#   2. Auto-allocate non-overlapping subuid/subgid ranges for the opencode user.
#   3. docker-rootless: run dockerd-rootless-setuptool.sh as opencode, enable the
#      systemd --user service, enable-linger.
#      podman-rootless: daemonless — just packages + subuid/subgid (no socket,
#      no linger unless a podman.socket is desired for docker-CLI compat).
#   4. Print the socket path (if any) on stdout so the caller can record it in
#      install.conf. For podman-rootless daemonless, nothing is printed.
#
# For docker-group: tear down a previously kit-provisioned rootless backend
# (stop/disable the systemd service, disable-linger) and print nothing.
#
# Must run as root. The opencode user must already exist.
# See docs/design/docker-rootless.md §6.4, §6.6, §9.3.
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKEND=""
YES=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        docker-rootless|podman-rootless|docker-group) BACKEND="$1" ;;
        --yes|-y) YES=true ;;
        *) echo "${RED}setup-container-backend.sh: unknown arg '$1'${NC}" >&2; exit 1 ;;
    esac
    shift
done
[ -n "$BACKEND" ] || { echo "${RED}Usage: setup-container-backend.sh <backend> [--yes]${NC}" >&2; exit 1; }

# === Shared helpers (ui.sh, log.sh) ===
LIBDIR="/usr/local/lib/opencode-permissions-kit"
log() { :; }
for cand in "$LIBDIR/ui.sh" "$(dirname "$0")/ui.sh" "$(dirname "$0")/opencode-permissions-kit-lib/ui.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done
log() { :; }
for cand in "$LIBDIR/log.sh" "$(dirname "$0")/log.sh" "$(dirname "$0")/opencode-permissions-kit-lib/log.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

# Read install.conf for OPENCODE_USER.
OPENCODE_USER="opencode"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
if [ -f "$INSTALL_CONF" ]; then
    . "$INSTALL_CONF"
fi
OPENCODE_USER="${OPENCODE_USER:-opencode}"

id "$OPENCODE_USER" >/dev/null 2>&1 || { echo "${RED}User '$OPENCODE_USER' does not exist. Run install.sh first.${NC}" >&2; exit 1; }

OC_UID=$(id -u "$OPENCODE_USER" 2>/dev/null || echo "")
[ -n "$OC_UID" ] || { echo "${RED}Cannot resolve UID for $OPENCODE_USER.${NC}" >&2; exit 1; }

confirm() {
    # Convention: docs/design/conventions.md — default capital in the hint,
    # Enter accepts it, y/yes/n/no case-insensitive.
    [ "$YES" = true ] && return 0
    ui_confirm "$1" "n"
}

# --- package installation -----------------------------------------------------

apt_install() {
    local pkgs=""
    for pkg in "$@"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            pkgs="$pkgs $pkg"
        fi
    done
    [ -z "$pkgs" ] && return 0
    echo "  Installing:$pkgs ..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y $pkgs
}

# --- subuid/subgid auto-allocation (§9.3) -------------------------------------
# Find a free contiguous range that does not overlap any existing entry in the
# given file. Starts from 100000, uses 65536 per user, increments by 65536.
allocate_range() {
    local file="$1" user="$2" start count
    start=100000
    count=65536
    # If the user already has an entry, keep it.
    if grep -q "^${user}:" "$file" 2>/dev/null; then
        return 0
    fi
    while true; do
        local overlap=false
        while IFS=: read -r u s c; do
            [ -z "$u" ] && continue
            local s2="${s:-0}" c2="${c:-0}"
            # Overlap check: [start, start+count) vs [s2, s2+c2)
            local end=$((start + count))
            local end2=$((s2 + c2))
            if [ "$start" -lt "$end2" ] && [ "$s2" -lt "$end" ]; then
                overlap=true
                break
            fi
        done < "$file" 2>/dev/null || true
        if [ "$overlap" = false ]; then
            break
        fi
        start=$((start + count))
    done
    echo "${user}:${start}:${count}" >> "$file"
    echo "  Allocated ${user} subuid/subgid range: ${start}-$((start + count - 1))"
    log "allocated subuid/subgid for ${user}: ${start}:${count}"
}

allocate_subuid_subgid() {
    local user="$1"
    touch /etc/subuid /etc/subgid
    allocate_range /etc/subuid "$user"
    allocate_range /etc/subgid "$user"
}

# --- systemd --user helpers ----------------------------------------------------

systemd_user_available() {
    # Check if `systemctl --user` works for the opencode user. Requires systemd
    # (WSL2: enabled via /etc/wsl.conf [boot] systemd=true) + dbus-user-session.
    # The opencode user has no login session (it was created by useradd and only
    # ever runs via sudo -u), so user@<uid>.service is not active. Enable linger
    # first — that starts the systemd --user manager for the user, which is
    # exactly what docker-rootless needs (the daemon must survive logout).
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$OPENCODE_USER" 2>/dev/null || true
        # loginctl enable-linger starts user@<uid>.service asynchronously;
        # give it a moment to come up.
        sleep 1
    fi
    # Ensure the runtime dir exists (systemd --user needs XDG_RUNTIME_DIR).
    mkdir -p "/run/user/$OC_UID" 2>/dev/null || true
    chown "$OPENCODE_USER:$OPENCODE_USER" "/run/user/$OC_UID" 2>/dev/null || true
    chmod 700 "/run/user/$OC_UID" 2>/dev/null || true
    sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user is-active dbus >/dev/null 2>&1 || \
    sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user status >/dev/null 2>&1
}

enable_linger() {
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$OPENCODE_USER" 2>/dev/null || true
        echo "  Linger enabled for $OPENCODE_USER (daemon survives logout)."
        log "linger enabled for $OPENCODE_USER"
    fi
}

disable_linger() {
    if command -v loginctl >/dev/null 2>&1; then
        loginctl disable-linger "$OPENCODE_USER" 2>/dev/null || true
        echo "  Linger disabled for $OPENCODE_USER."
        log "linger disabled for $OPENCODE_USER"
    fi
}

# --- docker-rootless setup ----------------------------------------------------

setup_docker_rootless() {
    echo ""
    echo "  ${CYAN}Setting up docker-rootless for $OPENCODE_USER ...${NC}"

    # Base prerequisite packages — must be installed BEFORE the systemd check
    # because dbus-user-session is what makes `systemctl --user` work. On a
    # fresh WSL2 install (even with systemd in /etc/wsl.conf), the opencode
    # user has no D-Bus session and `systemctl --user` fails until this
    # package is present. Install uidmap + dbus-user-session first, then
    # enable-linger (which starts user@<uid>.service), then verify.
    apt_install uidmap dbus-user-session

    # systemd --user is a hard requirement for the rootless daemon. Enable
    # linger first (the opencode user has no login session — it was created
    # by useradd and only ever runs via sudo -u — so user@<uid>.service is
    # not active. enable-linger starts the systemd --user manager for it).
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$OPENCODE_USER" 2>/dev/null || true
        # loginctl enable-linger starts user@<uid>.service asynchronously;
        # give it a moment to come up.
        sleep 1
    fi
    # Ensure the runtime dir exists (systemd --user needs XDG_RUNTIME_DIR).
    mkdir -p "/run/user/$OC_UID" 2>/dev/null || true
    chown "$OPENCODE_USER:$OPENCODE_USER" "/run/user/$OC_UID" 2>/dev/null || true
    chmod 700 "/run/user/$OC_UID" 2>/dev/null || true

    if ! sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user is-active dbus >/dev/null 2>&1; then
        if ! sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user status >/dev/null 2>&1; then
            echo "${RED}systemd --user is not available for $OPENCODE_USER.${NC}" >&2
            echo "${YELLOW}Docker rootless needs systemd (WSL2: enable via /etc/wsl.conf [boot] systemd=true + reboot).${NC}" >&2
            echo "${YELLOW}dbus-user-session was just installed — a reboot may be needed for the user session to start.${NC}" >&2
            echo "${YELLOW}Consider podman-rootless instead (daemonless, no systemd required).${NC}" >&2
            # Debug: show what failed (helps diagnose WSL2-specific issues).
            echo "${CYAN}--- diagnostic (stderr) ---${NC}" >&2
            echo "loginctl show-user $OPENCODE_USER:" >&2
            loginctl show-user "$OPENCODE_USER" 2>&1 | sed 's/^/  /' >&2
            echo "/run/user/$OC_UID:" >&2
            ls -la "/run/user/$OC_UID" 2>&1 | sed 's/^/  /' >&2
            echo "systemctl --user is-active dbus:" >&2
            sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user is-active dbus 2>&1 | sed 's/^/  /' >&2
            echo "systemctl --user status:" >&2
            sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" systemctl --user status 2>&1 | head -10 | sed 's/^/  /' >&2
            exit 1
        fi
    fi

    # docker-ce-rootless-extras provides dockerd-rootless-setuptool.sh and
    # dockerd-rootless.sh. It is NOT in Ubuntu's default repos — it lives in
    # Docker's official apt repo. The helper also needs docker-ce itself (the
    # dockerd binary), which most fresh WSL2 installations do not have.
    # get.docker.com installs both docker-ce + docker-ce-rootless-extras.
    if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
        echo "  dockerd-rootless-setuptool.sh not found — adding Docker's apt repo ..."
        # Try the distro package first (some distros ship it).
        if apt_install docker-ce-rootless-extras 2>/dev/null && command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
            : # installed from an existing repo
        else
            # Docker's repo is not configured. Add it via the official get.docker.com
            # installer, which adds the repo + keyring AND installs docker-ce
            # (the dockerd binary that dockerd-rootless.sh wraps). This is the
            # canonical way and does NOT conflict with an existing Docker install.
            echo "  Running get.docker.com (installs docker-ce + docker-ce-rootless-extras) ..."
            if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
                sh /tmp/get-docker.sh 2>&1 | sed 's/^/    /' || true
                rm -f /tmp/get-docker.sh
                apt-get update -qq 2>/dev/null || true
                apt_install docker-ce-rootless-extras
            else
                # Offline / no network: last-ditch attempt.
                apt_install docker-ce-rootless-extras 2>/dev/null || true
            fi
        fi
    fi
    if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
        echo "${RED}dockerd-rootless-setuptool.sh still not found.${NC}" >&2
        echo "${YELLOW}Could not install docker-ce-rootless-extras (no network, or Docker's repo unavailable).${NC}" >&2
        echo "${YELLOW}Install Docker + the rootless extras manually from https://docs.docker.com/engine/security/rootless/ and re-run,${NC}" >&2
        echo "${YELLOW}or use podman-rootless instead (daemonless, no Docker repo needed).${NC}" >&2
        exit 1
    fi

    # subuid/subgid for opencode
    allocate_subuid_subgid "$OPENCODE_USER"

    # Run the rootless setup as the opencode user (never as root).
    echo "  Running dockerd-rootless-setuptool.sh as $OPENCODE_USER ..."
    sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" \
        dockerd-rootless-setuptool.sh install || {
        echo "${RED}dockerd-rootless-setuptool.sh failed.${NC}" >&2
        exit 1
    }

    # Enable + start the systemd --user service.
    sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" \
        systemctl --user enable docker.service 2>/dev/null || true
    # Rootless ddev-router cannot bind 80/443 unless the unprivileged port
    # start is <=80 BEFORE the daemon starts (its netns inherits the value
    # at start). Apply it now so a fresh rootless install is ddev-ready out
    # of the box. If it is lowered later, restart the daemon to re-inherit.
    if [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)" -gt 80 ] 2>/dev/null; then
        echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-ddev-rootless.conf >/dev/null 2>&1 || true
        sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1 || true
        log "docker-rootless: net.ipv4.ip_unprivileged_port_start=80 applied before daemon start"
    fi
    sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" \
        systemctl --user start docker.service 2>/dev/null || true

    enable_linger

    # The socket path.
    SOCK="unix:///run/user/$OC_UID/docker.sock"
    echo "  ${GREEN}docker-rootless is ready for $OPENCODE_USER.${NC}"
    echo "  Socket: $SOCK"
    log "docker-rootless provisioned for $OPENCODE_USER (socket=$SOCK)"
    # Print the socket for the caller to record.
    echo "OPENCODE_DOCKER_HOST=$SOCK"
}

# --- podman-rootless setup ----------------------------------------------------

setup_podman_rootless() {
    echo ""
    echo "  ${CYAN}Setting up podman-rootless for $OPENCODE_USER ...${NC}"

    apt_install uidmap dbus-user-session podman slirp4netns
    if ! command -v podman >/dev/null 2>&1; then
        echo "${RED}podman installation failed. Install podman + uidmap manually and re-run.${NC}" >&2
        exit 1
    fi

    # subuid/subgid for opencode
    allocate_subuid_subgid "$OPENCODE_USER"

    # Ensure the runtime dir exists (podman uses it even without systemd).
    mkdir -p "/run/user/$OC_UID"
    chown "$OPENCODE_USER:$OPENCODE_USER" "/run/user/$OC_UID"
    chmod 700 "/run/user/$OC_UID"

    # Podman is daemonless — no systemd service, no linger, no socket needed.
    # Optional: enable-linger only if a podman.socket is desired for
    # docker-CLI compat (OPENCODE_PODMAN_SOCKET). That is an opt-in we do not
    # provision by default (§9.8: podman-CLI only).

    # Verify podman works as the opencode user.
    if ! sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" podman info >/dev/null 2>&1; then
        echo "${YELLOW}WARNING: 'podman info' as $OPENCODE_USER failed — rootless podman may need a reboot or 'loginctl enable-linger $OPENCODE_USER'.${NC}"
        log "podman-rootless: 'podman info' failed for $OPENCODE_USER (may need reboot/linger)"
    else
        echo "  ${GREEN}podman-rootless is ready for $OPENCODE_USER.${NC}"
        log "podman-rootless provisioned for $OPENCODE_USER"
    fi
    # No socket to print (daemonless podman-CLI path).
}

# --- teardown (switch to docker-group) -----------------------------------------

teardown_rootless() {
    echo ""
    echo "  ${CYAN}Tearing down rootless backend for $OPENCODE_USER ...${NC}"

    # Stop + disable the docker-rootless systemd --user service (if active).
    if command -v systemctl >/dev/null 2>&1 && systemd_user_available 2>/dev/null; then
        sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" \
            systemctl --user stop docker.service 2>/dev/null || true
        sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$OC_UID" \
            systemctl --user disable docker.service 2>/dev/null || true
    fi

    disable_linger

    # Note: subuid/subgid entries and installed packages are left in place
    # (removing them is too invasive and would break a re-switch). The kit
    # records nothing about having created them, so a manual cleanup is the
    # admin's choice via /etc/subuid + /etc/subgid.
    echo "  ${GREEN}Rootless backend torn down.${NC}"
    echo "  ${YELLOW}Packages (podman/uidmap/...) and /etc/subuid entries left in place.${NC}"
    log "rootless backend torn down for $OPENCODE_USER"
}

# --- dispatch -----------------------------------------------------------------

case "$BACKEND" in
    docker-rootless)  setup_docker_rootless ;;
    podman-rootless)  setup_podman_rootless ;;
    docker-group)     teardown_rootless ;;
    *) echo "${RED}Unknown backend: $BACKEND${NC}" >&2; exit 1 ;;
esac