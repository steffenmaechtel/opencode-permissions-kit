#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode-permissions-kit/status.sh
# or from a checkout:
#   files/status.sh
set -u

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode-permissions-kit/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"

VERSION="0.0.0"
DEFAULT_USER=""
OPENCODE_USER="opencode"
WWW_GROUP="www-data"
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi

# installed = the wrapper is active (user + wrapper + library present)
installed=false
if id "$OPENCODE_USER" >/dev/null 2>&1 && [ -x "$LIBDIR/wrapper" ] && [ -L /usr/local/bin/opencode ]; then
    installed=true
fi

echo ""
echo "  ${GREEN}opencode permissions kit${NC}  v$VERSION"
echo "  ${CYAN}=============================================${NC}"
echo ""

if [ "$installed" = false ]; then
    echo "  ${YELLOW}Hardening NOT active.${NC}"
    echo ""
    echo "  Install it with:"
    echo "      curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash"
    echo ""
    exit 0
fi

echo "  Mode:       ${GREEN}hardened${NC} (opencode runs as its own user)"
echo "  User:       $OPENCODE_USER $(id "$OPENCODE_USER" >/dev/null 2>&1 && echo "exists" || echo "${RED}MISSING${NC}")"
echo "  Wrapper:    /usr/local/bin/opencode -> $(readlink /usr/local/bin/opencode 2>/dev/null || echo missing)"
echo "  Library:    $LIBDIR"
echo "  Config:     $(ls /home/$OPENCODE_USER/.config/opencode/opencode.jsonc 2>/dev/null || ls /home/$OPENCODE_USER/.config/opencode/opencode.json 2>/dev/null || echo "${YELLOW}none${NC}")"
echo "  Default user: $DEFAULT_USER  group: $WWW_GROUP"

echo ""
echo "  ${CYAN}Project roots ($(grep -c . "$PROJECTS_CONF" 2>/dev/null || echo 0)):${NC}"
if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        echo "    - $root"
    done < "$PROJECTS_CONF"
else
    echo "    (none)"
fi

f="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$f" ] || f="/home/$OPENCODE_USER/.config/opencode/opencode.json"
if [ -f "$f" ]; then
    if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
        echo ""
        echo "  .git/config hardening: ${GREEN}ON${NC} (opencode cannot run git)"
    else
        echo ""
        echo "  .git/config hardening: ${CYAN}OFF${NC}"
    fi
fi

echo ""
echo "  ${CYAN}Container tools (docker/ddev):${NC}"
case "${CONTAINER_BACKEND:-docker-group}" in
    docker-rootless)
        echo "    backend:    docker-rootless"
        sock="${OPENCODE_DOCKER_HOST:-}"
        sockpath="$sock"
        case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
        # The opencode user's runtime dir (/run/user/<uid>) is mode 700
        # opencode:opencode, so a non-root status.sh caller cannot stat the
        # socket inside it. Try stat directly; if that fails (perm), use sudo.
        if [ -n "$sock" ]; then
            if [ -S "$sockpath" ] 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            elif sudo test -S "$sockpath" 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            else
                echo "    socket:     ${RED}NOT reachable${NC}  $sock"
            fi
        else
            echo "    socket:     ${YELLOW}not configured${NC}"
        fi
        # linger is best-effort: loginctl may need auth, ignore errors.
        if command -v loginctl >/dev/null 2>&1; then
            linger=$(loginctl show-user "$OPENCODE_USER" 2>/dev/null | sed -n 's/^Linger=//p')
            [ -n "$linger" ] && echo "    linger:     $linger"
        fi
        ;;
    podman-rootless)
        echo "    backend:    podman-rootless"
        sock="${OPENCODE_PODMAN_SOCKET:-}"
        if [ -n "$sock" ]; then
            # Optional podman docker-CLI-compat socket.
            sockpath="$sock"
            case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
            if [ -S "$sockpath" ] 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            elif sudo test -S "$sockpath" 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            else
                echo "    socket:     ${RED}NOT reachable${NC}  $sock"
            fi
        elif command -v podman >/dev/null 2>&1; then
            # Daemonless podman-CLI path (no socket needed, §9.8).
            pver=$(podman --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -1)
            echo "    podman CLI: ${GREEN}installed${NC}${pver:+  ($pver)}"
        else
            echo "    podman CLI: ${RED}NOT installed${NC}"
        fi
        ;;
    *)
        docker_group="$(getent group docker 2>/dev/null | cut -d: -f3)"
        if [ -n "$docker_group" ]; then
            echo "    backend:    docker-group  (docker group: ${GREEN}present (gid $docker_group)${NC})"
        else
            echo "    backend:    docker-group  (docker group: ${YELLOW}absent${NC})"
        fi
        echo "    reachable via: opencode -g docker"
        ;;
esac
if grep -qE '"[^"]*docker[^"]*": "deny"' "$f" 2>/dev/null; then
    echo "    direct access: ${GREEN}blocked${NC} (docker/ddev denied in opencode.jsonc)"
else
    echo "    direct access: ${RED}NOT blocked${NC} — add the kit's docker/ddev deny rules!"
fi

echo ""
echo "  ${CYAN}ddev delegation shim:${NC}"
if [ -L /usr/local/bin/ddev ] && [ "$(readlink /usr/local/bin/ddev)" = "$LIBDIR/bin/ddev" ]; then
    echo "    shim: ${GREEN}active${NC}  /usr/local/bin/ddev -> $LIBDIR/bin/ddev"
    echo "    real ddev: ${DDEV_BIN:-/usr/bin/ddev}"
    echo "    delegates to: $DEFAULT_USER (the developer)"
    if [ -n "${DDEV_VERSION:-}" ]; then
        ddev_low=$(awk -v v="$DDEV_VERSION" 'BEGIN{split(v,a,"."); if(a[1]+0<1 || (a[1]+0==1 && a[2]+0<25)) print "yes"; else print "no"}' 2>/dev/null)
        case "${CONTAINER_BACKEND:-docker-group}" in
            docker-rootless|podman-rootless)
                if [ "$ddev_low" = yes ]; then
                    echo "    ddev version: $DDEV_VERSION  ${YELLOW}(ddev < 1.25 — rootless for ddev needs ddev >= 1.25)${NC}"
                else
                    echo "    ddev version: $DDEV_VERSION"
                fi
                ;;
            *)
                echo "    ddev version: $DDEV_VERSION"
                ;;
        esac
    fi
elif [ -e /usr/local/bin/ddev ] && [ ! -L /usr/local/bin/ddev ]; then
    echo "    shim: ${YELLOW}NOT active${NC}  /usr/local/bin/ddev is a real ddev (delegation unavailable)"
else
    echo "    shim: ${YELLOW}NOT installed${NC}"
fi

echo ""
echo "  Management (run in a terminal):"
echo "      sudo $LIBDIR/config.sh                 change settings"
echo "      sudo $LIBDIR/update.sh                 re-deploy kit after an update"
echo "      bash $LIBDIR/uninstall.sh              remove the kit"
echo ""
