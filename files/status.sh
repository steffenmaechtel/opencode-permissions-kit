#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode/status.sh
# or from a checkout:
#   files/status.sh
set -u

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

LIBDIR="/usr/local/lib/opencode"
INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"

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
    echo "      curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$VERSION/files/install.sh | sudo bash"
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
echo "  ${CYAN}Project roots ($(grep -c . /etc/opencode/projects.conf 2>/dev/null || echo 0)):${NC}"
if [ -f /etc/opencode/projects.conf ] && [ -s /etc/opencode/projects.conf ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        echo "    - $root"
    done < /etc/opencode/projects.conf
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
echo "  Management (run in a terminal):"
echo "      sudo $LIBDIR/config.sh                 change settings"
echo "      sudo $LIBDIR/update.sh                 re-deploy kit after an update"
echo "      bash $LIBDIR/uninstall.sh              remove the kit"
echo ""
