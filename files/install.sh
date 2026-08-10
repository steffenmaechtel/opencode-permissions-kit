#!/bin/sh
# opencode permissions kit -- install.sh
# First-time installer for WSL2 + DDEV environments. Asks interactively.
#
# One-liner (fetches this script + all kit files from GitHub at $KIT_BRANCH):
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH/files/install.sh | sudo bash
#
# From a checkout (same behaviour, uses the local files):
#   sudo bash files/install.sh
#
# To re-deploy the kit without prompts after it is already installed,
# use update.sh instead. To change settings later, use config.sh.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --projects <path...>  Pre-define project roots, skip interactive selection
set -e

# Branch the kit ships from (master = always latest). Overridable for
# testing: KIT_BRANCH=my-branch  KIT_BASE_URL=https://example.invalid/<branch>
KIT_BRANCH="${KIT_BRANCH:-master}"
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` and has no local siblings.
fetch_kit() {
    local base dir f
    base="$(mktemp -d)"
    dir="$base/files"
    mkdir -p "$dir/opencode-lib/hooks"
    for f in install.sh config.sh update.sh uninstall.sh status.sh opencode.jsonc \
             sudoers.template umask.sh VERSION \
             opencode-lib/wrapper opencode-lib/protect-projects.sh opencode-lib/jsonc-parser.py \
             opencode-lib/hooks/post-checkout opencode-lib/hooks/post-merge opencode-lib/hooks/post-commit; do
        echo "  fetching $f ..." >&2
        if [ "$f" = "VERSION" ]; then
            curl -fsSL "$KIT_BASE_URL/VERSION" -o "$base/VERSION" || return 1
        else
            curl -fsSL "$KIT_BASE_URL/files/$f" -o "$dir/$f" || return 1
        fi
    done
    echo "$dir"
}

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STREAMED=false
if [ ! -f "$SCRIPT_DIR/../VERSION" ]; then
    echo "Not a local checkout — fetching kit files from $KIT_BASE_URL ..."
    SCRIPT_DIR="$(fetch_kit)" || { echo "${RED}Failed to fetch kit files from $KIT_BASE_URL${NC}" >&2; exit 1; }
    STREAMED=true
fi
VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0.0.0")

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

OPENCODE_USER="opencode"
WWW_GROUP="www-data"

SKIP_PROMPTS=false
PREDEFINED_PROJECTS=""
SECURE_GIT_CONFIG=false

for arg do
    case "$arg" in
        --yes) SKIP_PROMPTS=true ;;
        --secure-git-config) SECURE_GIT_CONFIG=true ;;
        --projects)
            shift
            while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
                PREDEFINED_PROJECTS="$PREDEFINED_PROJECTS $1"
                shift
            done
            break
            ;;
    esac
    shift 2>/dev/null || true
done

# === Helpers ===

prompt() {
    # prompt "Question?" "Y" "N" "B"
    # Returns: y, n, or b
    local msg="$1"
    local opt_y="$2"
    local opt_n="$3"
    local opt_b="$4"

    if [ "$SKIP_PROMPTS" = true ]; then
        echo "y"
        return
    fi

    echo "" >&2
    printf "[?] %s" "$msg" >&2
    [ -n "$opt_y" ] && printf "  (%s) Yes" "$opt_y" >&2
    [ -n "$opt_n" ] && printf "  (%s) No" "$opt_n" >&2
    [ -n "$opt_b" ] && printf "  (%s) Backup + Yes" "$opt_b" >&2
    echo "" >&2

    while true; do
        printf "    > " >&2
        read -r answer </dev/tty 2>/dev/null || read -r answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        case "$answer" in
            y|yes) echo "y"; return ;;
            n|no)  echo "n"; return ;;
            b|backup)
                if [ -n "$opt_b" ]; then echo "b"; return; fi
                ;;
            "") echo "n"; return ;;
        esac
    done
}

banner() {
    echo ""
    echo "  ${GREEN}opencode permissions kit${NC}  v$VERSION"
    echo "  ${CYAN}=============================================${NC}"
    echo ""
}

# === Start ===

banner

DEFAULT_USER="${SUDO_USER:-$(whoami)}"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    ans=$(prompt "This does not appear to be WSL2. Continue anyway?" "Y" "N" "")
    [ "$ans" != "y" ] && exit 0
fi

# Backup
BACKUP_DIR="/tmp/opencode-install-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Backup directory: $BACKUP_DIR"
sudo -u "$DEFAULT_USER" git config --global --list 2>/dev/null > "$BACKUP_DIR/gitconfig-$DEFAULT_USER.txt" || true
sudo -u "$OPENCODE_USER" git config --global --list 2>/dev/null > "$BACKUP_DIR/gitconfig-$OPENCODE_USER.txt" 2>/dev/null || true
[ -f /etc/opencode/sudoers ] && cp /etc/opencode/sudoers "$BACKUP_DIR/sudoers" 2>/dev/null || true
[ -f /usr/local/bin/opencode ] && cp /usr/local/bin/opencode "$BACKUP_DIR/usr-local-bin-opencode" 2>/dev/null || true
[ -d /usr/local/lib/opencode ] && cp -r /usr/local/lib/opencode "$BACKUP_DIR/opencode-lib" 2>/dev/null || true

echo ""
echo "--- Pre-flight checks ---"

if ! command -v curl >/dev/null 2>&1; then
    echo "${RED}curl is required but not installed.${NC}"
    exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
    ans=$(prompt "'acl' package not installed (setfacl/getfacl missing). Install it now?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y acl
    fi
    if ! command -v setfacl >/dev/null 2>&1; then
        echo "${RED}setfacl required for ACL protection. Install the 'acl' package and re-run.${NC}"
        exit 1
    fi
fi

if getent group "$WWW_GROUP" >/dev/null 2>&1; then
    ans=$(prompt "Group 'www-data' already exists (Apache/Nginx installed?). Use it?" "Y" "N" "")
    [ "$ans" != "y" ] && { echo "Aborted."; exit 1; }
else
    sudo groupadd -f "$WWW_GROUP"
    echo "Group '$WWW_GROUP' created."
fi

if ! command -v ddev >/dev/null 2>&1; then
    echo "${YELLOW}DDEV not found. Continuing anyway.${NC}"
fi

# === Step 1: User ===

if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ans=$(prompt "User '$OPENCODE_USER' already exists. Add to www-data and continue?" "Y" "N" "")
    [ "$ans" != "y" ] && { echo "Aborted."; exit 1; }
else
    sudo useradd -m -s /bin/bash "$OPENCODE_USER"
    echo "User '$OPENCODE_USER' created."
fi

sudo usermod -aG "$WWW_GROUP" "$OPENCODE_USER" 2>/dev/null || true
sudo usermod -aG "$WWW_GROUP" "$DEFAULT_USER" 2>/dev/null || true

# === Step 2: Project roots ===

if [ -n "$PREDEFINED_PROJECTS" ]; then
    PROJECTS_ROOTS="$PREDEFINED_PROJECTS"
else
    echo ""
    echo "--- Project roots ---"
    echo ""
    echo "Select project directories (space-separated numbers), or 'c' for custom, 's' to skip."

    num=1
    options=""
    for dir in /var/www/vhosts /var/www/html /var/www; do
        if [ -d "$dir" ]; then
            echo "  [$num] $dir"
            options="$options $dir"
            num=$((num + 1))
        fi
    done
    if [ -z "$options" ]; then
        echo "  ${YELLOW}No standard directories found.${NC}"
    fi
    echo "  [c] Custom path(s)"
    echo "  [s] Skip (no project ACLs, only user + wrapper + hooks)"
    printf "  > "
    read -r selection </dev/tty 2>/dev/null || read -r selection

    case "$selection" in
        [Cc]*)
            echo "Enter paths (space-separated):"
            printf "  > "
            read -r custom </dev/tty 2>/dev/null || read -r custom
            PROJECTS_ROOTS="$custom"
            ;;
        [Ss]*)
            PROJECTS_ROOTS=""
            echo "Skipping project ACLs."
            ;;
        *)
            PROJECTS_ROOTS=""
            idx=1
            for dir in $options; do
                for s in $selection; do
                    [ "$s" = "$idx" ] && PROJECTS_ROOTS="$PROJECTS_ROOTS $dir"
                done
                idx=$((idx + 1))
            done
            ;;
    esac
fi

sudo mkdir -p /etc/opencode
if [ -n "$PROJECTS_ROOTS" ]; then
    echo "$PROJECTS_ROOTS" | tr ' ' '\n' | sudo tee /etc/opencode/projects.conf > /dev/null
    echo "Project roots: $PROJECTS_ROOTS"
else
    sudo touch /etc/opencode/projects.conf
    echo "No project roots configured."
fi

# Backup project ACLs now that roots are known
if [ -n "$PROJECTS_ROOTS" ]; then
    sudo getfacl -R $PROJECTS_ROOTS 2>/dev/null > "$BACKUP_DIR/getfacl-R-projects.txt" || true
    echo "Project ACLs backed up to $BACKUP_DIR/getfacl-R-projects.txt"
fi

sudo tee /etc/opencode/install.conf > /dev/null <<EOF
DEFAULT_USER=$DEFAULT_USER
OPENCODE_USER=$OPENCODE_USER
WWW_GROUP=$WWW_GROUP
VERSION=$VERSION
EOF
# Migrate legacy setup.conf (pre-v0.0.9) -> install.conf
[ -f /etc/opencode/setup.conf ] && sudo rm -f /etc/opencode/setup.conf

# === Step 3: Filesystem ===

if [ -n "$PROJECTS_ROOTS" ]; then
    echo ""
    echo "--- Filesystem ---"
    ans=$(prompt "Apply group-www-data, setgid, and default ACLs to project roots? (changes metadata on ALL files)" "Y" "N" "B")
    case "$ans" in
        n) echo "Skipping filesystem setup." ;;
        b)
            getfacl -R $PROJECTS_ROOTS 2>/dev/null > "$BACKUP_DIR/getfacl-R-projects.txt" || true
            echo "Backup saved." ;;
        y) ;;
    esac
    if [ "$ans" != "n" ]; then
        for root in $PROJECTS_ROOTS; do
            [ -d "$root" ] || continue
            sudo chgrp -R "$WWW_GROUP" "$root" 2>/dev/null || true
            sudo chmod g+s "$root"
            sudo setfacl -R -d -m "g:$WWW_GROUP:rwx" "$root" 2>/dev/null || true
            echo "  $root done."
        done
    fi
fi

sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-umask.sh
sudo chmod 644 /etc/profile.d/opencode-umask.sh

# === Step 4: opencode binary ===

echo ""
echo "--- opencode installation ---"

SYSTEM_BIN="/usr/local/lib/opencode/bin/opencode"
opencode_found=false

for loc in "/home/$DEFAULT_USER/.opencode/bin/opencode" "/root/.opencode/bin/opencode" "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -x "$loc" ] && [ "$loc" != "/usr/local/bin/opencode" ]; then
        ans=$(prompt "opencode binary found at $loc. Copy to system path and secure with wrapper?" "Y" "N" "B")
        case "$ans" in
            y)
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                sudo cp "$loc" "$SYSTEM_BIN"
                sudo chmod 755 "$SYSTEM_BIN"
                opencode_found=true
                echo "Copied to $SYSTEM_BIN."
                break
                ;;
            b)
                cp "$loc" "$BACKUP_DIR/opencode-binary" 2>/dev/null || true
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                sudo cp "$loc" "$SYSTEM_BIN"
                sudo chmod 755 "$SYSTEM_BIN"
                opencode_found=true
                echo "Backup saved. Copied to $SYSTEM_BIN."
                break
                ;;
            n) echo "Aborted."; exit 1 ;;
        esac
    fi
done

if [ "$opencode_found" = false ]; then
    ans=$(prompt "opencode not found. Run official installer (curl -fsSL https://opencode.ai/install | bash)?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        curl -fsSL https://opencode.ai/install | bash
        # When run via the one-liner (sudo bash), the official installer
        # installs into /root/.opencode/bin. Locally it lands in the user's home.
        if [ -x "/root/.opencode/bin/opencode" ]; then
            sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
            sudo cp "/root/.opencode/bin/opencode" "$SYSTEM_BIN"
            sudo chmod 755 "$SYSTEM_BIN"
            echo "Installed to $SYSTEM_BIN."
        elif [ -x "/home/$DEFAULT_USER/.opencode/bin/opencode" ]; then
            sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
            sudo cp "/home/$DEFAULT_USER/.opencode/bin/opencode" "$SYSTEM_BIN"
            sudo chmod 755 "$SYSTEM_BIN"
            echo "Installed to $SYSTEM_BIN."
        else
            echo "${RED}Installation failed. Install opencode manually and re-run.${NC}"
            exit 1
        fi
    else
        echo "Aborted. Install opencode manually and re-run install.sh."
        exit 1
    fi
fi

for cf in "/home/$DEFAULT_USER/.bashrc" "/home/$DEFAULT_USER/.zshrc" "/home/$DEFAULT_USER/.profile"; do
    if [ -f "$cf" ]; then
        sudo sed -i '\|\.opencode/bin|d' "$cf" 2>/dev/null || true
        if ! sudo grep -q '# opencode permissions kit' "$cf" 2>/dev/null; then
            echo "" | sudo tee -a "$cf" > /dev/null
            echo 'export PATH="/usr/local/bin:$PATH"  # opencode permissions kit' | sudo tee -a "$cf" > /dev/null
        fi
    fi
done

# === Step 5: opencode library (consolidated deployment in /usr/local/lib/opencode/) ===

LIBDIR="/usr/local/lib/opencode"

sudo mkdir -p "$LIBDIR/hooks"

# Copy all our scripts into the library directory
sudo cp "$SCRIPT_DIR/opencode-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-lib/protect-projects.sh" "$LIBDIR/protect-projects.sh"
sudo cp "$SCRIPT_DIR/opencode-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-checkout" "$LIBDIR/hooks/post-checkout"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-merge"    "$LIBDIR/hooks/post-merge"
sudo cp "$SCRIPT_DIR/opencode-lib/hooks/post-commit"   "$LIBDIR/hooks/post-commit"
sudo cp "$SCRIPT_DIR/config.sh"                        "$LIBDIR/config.sh"
sudo cp "$SCRIPT_DIR/update.sh"                        "$LIBDIR/update.sh"
sudo cp "$SCRIPT_DIR/status.sh"                        "$LIBDIR/status.sh"
sudo cp "$SCRIPT_DIR/opencode.jsonc"                   "$LIBDIR/opencode.jsonc"
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/protect-projects.sh" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/hooks/post-checkout" "$LIBDIR/hooks/post-merge" "$LIBDIR/hooks/post-commit"

# Symlink: /usr/local/bin/opencode -> our wrapper
sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
echo "Wrapper installed: /usr/local/bin/opencode -> $LIBDIR/wrapper"

# Symlink: backward-compat path for direct protect-projects calls
sudo ln -sf "$LIBDIR/protect-projects.sh" /usr/local/sbin/protect-projects.sh

# sudoers -> /etc/opencode/sudoers, symlinked as /etc/sudoers.d/opencode
SUDO_TMP=$(mktemp)
sed "s/DEFAULT_USER/$DEFAULT_USER/g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
sudo cp "$SUDO_TMP" /etc/opencode/sudoers
sudo chmod 440 /etc/opencode/sudoers
rm -f "$SUDO_TMP"
sudo ln -sf /etc/opencode/sudoers /etc/sudoers.d/opencode

if sudo /usr/sbin/visudo -c -f /etc/opencode/sudoers >/dev/null 2>&1; then
    echo "sudoers installed."
else
    echo "${RED}sudoers validation failed. Check /etc/opencode/sudoers.${NC}"
    exit 1
fi

# Git hooks — core.hooksPath points directly into our library
sudo -u "$OPENCODE_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
sudo -u "$DEFAULT_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
echo "Git hooks configured (core.hooksPath = $LIBDIR/hooks)."

# === Step 5b: .git/config hardening (optional) ===

if [ "$SECURE_GIT_CONFIG" = true ]; then
    echo "Secure git config: enabled via --secure-git-config flag."
else
    ans=$(prompt "Block .git/config for opencode? WARNING: If enabled, opencode cannot execute ANY git commands (commit, push, pull, status, diff, log, etc.)." "Y" "N" "")
    case "$ans" in
        y) SECURE_GIT_CONFIG=true ;;
        *) SECURE_GIT_CONFIG=false ;;
    esac
fi

# === Step 6: opencode Home ===

sudo mkdir -p /home/opencode/.config/opencode /home/opencode/.agents
# useradd -m leaves the home dir in a private 'opencode' group, which blocks
# the default user (member of $WWW_GROUP) from entering it. Chgrp to
# $WWW_GROUP + setgid so the default user can edit opencode.jsonc etc.
sudo chown "$OPENCODE_USER:$WWW_GROUP" /home/opencode
sudo chmod 2750 /home/opencode
sudo chown -R opencode:www-data /home/opencode/.config /home/opencode/.agents
sudo chmod 2775 /home/opencode/.config /home/opencode/.config/opencode /home/opencode/.agents

if [ ! -f /home/opencode/.config/opencode/opencode.jsonc ] && [ ! -f /home/opencode/.config/opencode/opencode.json ]; then
    sudo cp "$SCRIPT_DIR/opencode.jsonc" /home/opencode/.config/opencode/opencode.jsonc
    sudo chown opencode:www-data /home/opencode/.config/opencode/opencode.jsonc
    sudo chmod 664 /home/opencode/.config/opencode/opencode.jsonc
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        sudo sed -i 's|//SECURE_GIT: ||' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc) — .git/config blocked."
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc)."
    fi
elif [ -f /home/opencode/.config/opencode/opencode.jsonc ] && ! grep -q '"permission"' /home/opencode/.config/opencode/opencode.jsonc; then
    sudo cp /home/opencode/.config/opencode/opencode.jsonc "$BACKUP_DIR/opencode.jsonc-existing" 2>/dev/null || true
    sudo cp "$SCRIPT_DIR/opencode.jsonc" /home/opencode/.config/opencode/opencode.jsonc
    sudo chown opencode:www-data /home/opencode/.config/opencode/opencode.jsonc
    sudo chmod 664 /home/opencode/.config/opencode/opencode.jsonc
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        sudo sed -i 's|//SECURE_GIT: ||' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc) — .git/config blocked. Backup saved."
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc — backup saved)."
    fi
else
    echo "Config already exists, not overwriting."
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        echo "  ${YELLOW}Heads-up: --secure-git-config was set but config already existed.${NC}" >&2
    fi
fi

# === Step 7: Initial protection run ===

if [ -n "$PROJECTS_ROOTS" ]; then
    sudo "$LIBDIR/protect-projects.sh" && echo "Initial ACL protection applied to projects."
fi

# === Done ===

echo ""
echo "  ${GREEN}Installation complete.${NC}"
echo ""
echo "  Run:    ${CYAN}opencode${NC}"
echo "  Backup: $BACKUP_DIR"
echo "  Docs:   ${CYAN}docs/MANUAL.md${NC} (config, skills, verification, uninstall)"
echo ""
