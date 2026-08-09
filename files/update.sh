#!/bin/sh
# opencode permissions kit -- update.sh
# Re-deploys the KIT only (wrapper, hooks, protect-projects.sh, jsonc-parser,
# sudoers template, umask profile, uninstall.sh, config.sh) onto a system
# that has already been installed via install.sh. Does NOT touch:
#   - existing /etc/opencode/projects.conf
#   - existing /etc/opencode/install.conf (DEFAULT_USER / OPENCODE_USER)
#   - existing /home/opencode/.config/opencode/opencode.json[c]
#   - the opencode binary at /usr/local/lib/opencode/bin/opencode
#   - any ACLs or filesystem metadata
#
# Run as your default (non-root) user with sudo privileges:
#   ./update.sh
#   ./update.sh --yes            # skip prompts
#   ./update.sh --refresh        # also re-run protect-projects.sh --force at the end
#
# Use install.sh for the very first setup (it asks the questions).
# Use config.sh to change project roots or git-config hardening.
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0.0.0")
LIBDIR="/usr/local/lib/opencode"

# install.conf with legacy fallback to pre-v0.0.9 setup.conf
INSTALL_CONF="/etc/opencode/install.conf"
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
REFRESH=false
for arg do
    case "$arg" in
        --yes|-y) YES=true ;;
        --refresh) REFRESH=true ;;
        -h|--help)
            cat <<EOF
opencode permissions kit -- update.sh  v$VERSION
Re-deploys the kit on an already-installed system. No prompts by default.
Usage: ./update.sh [--yes] [--refresh]
EOF
            exit 0
            ;;
    esac
done

banner() {
    echo ""
    echo "  ${GREEN}opencode permissions kit${NC}  update  v$VERSION"
    echo "  ${CYAN}=============================================${NC}"
    echo ""
}

die() { echo "${RED}$*${NC}" >&2; exit 1; }

confirm() {
    [ "$YES" = true ] && return 0
    printf "[?] %s (Y/n) " "$1" >&2
    read -r ans </dev/tty 2>/dev/null || read -r ans
    case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
        n|no) return 1 ;; *) return 0 ;;
    esac
}

# --- pre-flight ---------------------------------------------------------------

banner

if [ ! -f "$INSTALL_CONF" ] && [ ! -f /etc/opencode/setup.conf ]; then
    die "Not installed yet. Run install.sh first."
fi

if ! id "$OPENCODE_USER" >/dev/null 2>&1; then
    die "User '$OPENCODE_USER' missing. Run install.sh first."
fi

if ! confirm "Re-deploy kit files (binary and existing configs will NOT be touched)?"; then
    echo "Aborted."; exit 0
fi

# --- re-deploy library files --------------------------------------------------

echo ""
echo "--- Re-deploying library files ---"
sudo mkdir -p "$LIBDIR/hooks"

sudo cp "$SCRIPT_DIR/opencode-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-lib/protect-projects.sh" "$LIBDIR/protect-projects.sh"
sudo cp "$SCRIPT_DIR/opencode-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-checkout" "$LIBDIR/hooks/post-checkout"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-merge"    "$LIBDIR/hooks/post-merge"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-commit"   "$LIBDIR/hooks/post-commit"
sudo cp "$SCRIPT_DIR/config.sh"                        "$LIBDIR/config.sh"
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/protect-projects.sh" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/config.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/hooks/post-checkout" "$LIBDIR/hooks/post-merge" "$LIBDIR/hooks/post-commit"
echo "Library files updated: $LIBDIR"

# --- re-link wrapper + protect-projects --------------------------------------

sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
sudo ln -sf "$LIBDIR/protect-projects.sh" /usr/local/sbin/protect-projects.sh
echo "Symlinks refreshed: /usr/local/bin/opencode, /usr/local/sbin/protect-projects.sh"

# --- re-deploy sudoers -------------------------------------------------------

if [ -f "$SCRIPT_DIR/sudoers.template" ]; then
    SUDO_TMP=$(mktemp)
    sed "s/DEFAULT_USER/$DEFAULT_USER/g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
    sudo cp "$SUDO_TMP" /etc/opencode/sudoers
    sudo chmod 440 /etc/opencode/sudoers
    rm -f "$SUDO_TMP"
    sudo ln -sf /etc/opencode/sudoers /etc/sudoers.d/opencode
    if sudo /usr/sbin/visudo -c -f /etc/opencode/sudoers >/dev/null 2>&1; then
        echo "sudoers updated (DEFAULT_USER=$DEFAULT_USER)."
    else
        echo "${RED}sudoers validation failed. Check /etc/opencode/sudoers.${NC}"
        exit 1
    fi
fi

# --- re-deploy umask profile -------------------------------------------------

if [ -f "$SCRIPT_DIR/umask.sh" ]; then
    sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-umask.sh
    sudo chmod 644 /etc/profile.d/opencode-umask.sh
    echo "umask profile updated."
fi

# --- re-apply git hooks path (in case user wiped it) ------------------------

sudo -u "$OPENCODE_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
sudo -u "$DEFAULT_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
echo "core.hooksPath confirmed ($LIBDIR/hooks)."

# --- refresh install.conf version stamp --------------------------------------

NEW_INSTALL_CONF="$(mktemp)"
{
    if [ -f "$INSTALL_CONF" ]; then
        grep -v '^VERSION=' "$INSTALL_CONF" 2>/dev/null
    fi
    echo "VERSION=$VERSION"
} | sort -u > "$NEW_INSTALL_CONF"
sudo cp "$NEW_INSTALL_CONF" /etc/opencode/install.conf
sudo chmod 644 /etc/opencode/install.conf
rm -f "$NEW_INSTALL_CONF"
# Cleanup pre-v0.0.9 legacy file
[ -f /etc/opencode/setup.conf ] && sudo rm -f /etc/opencode/setup.conf
echo "install.conf updated: VERSION=$VERSION"

# --- optional ACL refresh ----------------------------------------------------

if [ "$REFRESH" = true ]; then
    echo ""
    echo "--- Refreshing ACL protection ---"
    sudo "$LIBDIR/protect-projects.sh" --force
else
    echo ""
    echo "Skipped ACL refresh (use --refresh to re-apply protects)."
fi

# --- done --------------------------------------------------------------------

echo ""
echo "  ${GREEN}Update complete.${NC}  v$VERSION"
echo "  Binary, projects.conf and opencode.jsonc were left untouched."
echo ""