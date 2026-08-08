#!/bin/sh
# opencode permissions kit -- setup.sh
# Idempotent one-shot setup for WSL2 + DDEV environments.
# Run as your default (non-root) user with sudo privileges:
#   ./setup.sh
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --projects <path...>  Pre-define project roots, skip interactive selection
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="0.0.1"

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

if ! sudo -n true 2>/dev/null; then
    echo "This setup requires sudo. Run as your normal user with sudo privileges."
    exit 1
fi

DEFAULT_USER=$(whoami)
if [ "$DEFAULT_USER" = "root" ]; then
    echo "${RED}Do not run setup.sh as root. Run as your normal user with sudo.${NC}"
    exit 1
fi

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    ans=$(prompt "This does not appear to be WSL2. Continue anyway?" "Y" "N" "")
    [ "$ans" != "y" ] && exit 0
fi

# === Version check: compare baked-in version with repo VERSION file ===
REPO_VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0")
if [ "$REPO_VERSION" != "$VERSION" ]; then
    HIGHER=$(printf '%s\n' "$VERSION" "$REPO_VERSION" | sort -V | tail -1)
    if [ "$HIGHER" = "$REPO_VERSION" ] && [ "$REPO_VERSION" != "$VERSION" ]; then
        echo ""
        echo "  ${YELLOW}Repo has newer version ($REPO_VERSION) — you are running v$VERSION.${NC}"
        echo "  Run ${CYAN}git pull${NC} first, then re-run ./setup.sh."
        echo ""
    fi
fi

# Backup
BACKUP_DIR="/tmp/opencode-setup-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Backup directory: $BACKUP_DIR"
getfacl -R /var/www/vhosts 2>/dev/null > "$BACKUP_DIR/getfacl-R-projects.txt" || true
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

sudo tee /etc/opencode/setup.conf > /dev/null <<EOF
DEFAULT_USER=$DEFAULT_USER
OPENCODE_USER=$OPENCODE_USER
WWW_GROUP=$WWW_GROUP
VERSION=$VERSION
EOF

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

for loc in "/home/$DEFAULT_USER/.opencode/bin/opencode" "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -x "$loc" ] && [ "$loc" != "/usr/local/bin/opencode" ]; then
        ans=$(prompt "openCode binary found at $loc. Copy to system path and secure with wrapper?" "Y" "N" "B")
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
    ans=$(prompt "openCode not found. Run official installer (curl -fsSL https://opencode.ai/install | bash)?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        curl -fsSL https://opencode.ai/install | bash
        if [ -x "/home/$DEFAULT_USER/.opencode/bin/opencode" ]; then
            sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
            sudo cp "/home/$DEFAULT_USER/.opencode/bin/opencode" "$SYSTEM_BIN"
            sudo chmod 755 "$SYSTEM_BIN"
            echo "Installed to $SYSTEM_BIN."
        else
            echo "${RED}Installation failed. Install opencode manually and re-run setup.${NC}"
            exit 1
        fi
    else
        echo "Aborted. Install opencode manually and re-run setup.sh."
        exit 1
    fi
fi

for cf in "/home/$DEFAULT_USER/.bashrc" "/home/$DEFAULT_USER/.zshrc" "/home/$DEFAULT_USER/.profile"; do
    if [ -f "$cf" ]; then
        sudo sed -i '\|\.opencode/bin|d' "$cf" 2>/dev/null || true
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
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/protect-projects.sh" "$LIBDIR/jsonc-parser.py"
sudo chmod 755 "$LIBDIR/hooks/post-checkout" "$LIBDIR/hooks/post-merge" "$LIBDIR/hooks/post-commit"

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
sudo chown -R opencode:www-data /home/opencode/.config /home/opencode/.agents
sudo chmod 750 /home/opencode
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
echo "  ${GREEN}Setup complete.${NC}"
echo ""
echo "  Next steps:"
echo "    1. ${CYAN}opencode${NC}              — start (runs as user 'opencode' via wrapper)"
echo "    2. Edit config:  ${CYAN}/home/opencode/.config/opencode/opencode.jsonc${NC}"
echo "    3. Add skills:   ${CYAN}/home/opencode/.agents/${NC}"
echo "    4. Verify:       ${CYAN}./tests/verify.sh${NC}"
echo ""
echo "  Backup stored at: $BACKUP_DIR"
echo "  Uninstall with:   ${CYAN}./uninstall.sh${NC}"
echo ""
