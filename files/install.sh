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
    mkdir -p "$dir/opencode-permissions-kit-lib/hooks" "$dir/opencode-permissions-kit-lib/bin"
    for f in install.sh config.sh update.sh uninstall.sh status.sh opencode.jsonc \
             opencode-deny-all.jsonc \
             sudoers.template umask.sh VERSION \
             opencode-permissions-kit-lib/wrapper opencode-permissions-kit-lib/protect-projects.sh opencode-permissions-kit-lib/jsonc-parser.py \
             opencode-permissions-kit-lib/log.sh opencode-permissions-kit-lib/shell-warn.sh opencode-permissions-kit-lib/setup-container-backend.sh opencode-permissions-kit-lib/bin/ddev opencode-permissions-kit-lib/bin/socket-check.sh \
             opencode-permissions-kit-lib/hooks/post-checkout opencode-permissions-kit-lib/hooks/post-merge opencode-permissions-kit-lib/hooks/post-commit; do
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

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). No-op if
# the helper is missing — logging must never break the install.
log() { :; }
if [ -f "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh" ]; then
    . "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh"
fi

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
CONTAINER_BACKEND_OPT=""

_skip_next=false
for arg do
    if [ "$_skip_next" = true ]; then
        _skip_next=false
        shift 2>/dev/null || true
        continue
    fi
    case "$arg" in
        --yes) SKIP_PROMPTS=true ;;
        --secure-git-config) SECURE_GIT_CONFIG=true ;;
        --container-backend)
            CONTAINER_BACKEND_OPT="$2"
            _skip_next=true
            ;;
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
log "install started (version $VERSION, default user=$DEFAULT_USER)"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    ans=$(prompt "This does not appear to be WSL2. Continue anyway?" "Y" "N" "")
    [ "$ans" != "y" ] && exit 0
fi

# Backup
BACKUP_DIR="/tmp/opencode-install-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Backup directory: $BACKUP_DIR"
log "backup dir created: $BACKUP_DIR"
sudo -u "$DEFAULT_USER" git config --global --list 2>/dev/null > "$BACKUP_DIR/gitconfig-$DEFAULT_USER.txt" || true
sudo -u "$OPENCODE_USER" git config --global --list 2>/dev/null > "$BACKUP_DIR/gitconfig-$OPENCODE_USER.txt" 2>/dev/null || true
[ -f /etc/opencode-permissions-kit/sudoers ] && cp /etc/opencode-permissions-kit/sudoers "$BACKUP_DIR/sudoers" 2>/dev/null || true
[ -f /etc/opencode/sudoers ] && cp /etc/opencode/sudoers "$BACKUP_DIR/sudoers-legacy" 2>/dev/null || true
[ -f /usr/local/bin/opencode ] && cp /usr/local/bin/opencode "$BACKUP_DIR/usr-local-bin-opencode" 2>/dev/null || true
[ -d /usr/local/lib/opencode-permissions-kit ] && cp -r /usr/local/lib/opencode-permissions-kit "$BACKUP_DIR/opencode-permissions-kit-lib" 2>/dev/null || true
[ -d /usr/local/lib/opencode ] && cp -r /usr/local/lib/opencode "$BACKUP_DIR/opencode-lib-legacy" 2>/dev/null || true

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
    log "group created: $WWW_GROUP"
fi

if ! command -v ddev >/dev/null 2>&1; then
    echo "${YELLOW}DDEV not found. Continuing anyway.${NC}"
fi

# Resolve the REAL ddev path (before the kit shim shadows /usr/local/bin/ddev).
# On re-install over an existing kit, `command -v ddev` would return our own
# shim symlink — fall back to the recorded DDEV_BIN or the default location.
# The readlink target is $LIBDIR/bin/ddev (new or pre-0.0.10 layout).
DDEV_BIN="$(command -v ddev 2>/dev/null || true)"
if [ -n "$DDEV_BIN" ] && [ -L "$DDEV_BIN" ] \
   && readlink "$DDEV_BIN" 2>/dev/null | grep -Eq 'lib/opencode(-permissions-kit)?/bin/ddev'; then
    for _c in /etc/opencode-permissions-kit/install.conf /etc/opencode/install.conf; do
        if [ -f "$_c" ]; then
            DDEV_BIN=$(sed -n 's/^DDEV_BIN=//p' "$_c" 2>/dev/null || true)
            break
        fi
    done
fi
[ -n "$DDEV_BIN" ] || DDEV_BIN="/usr/bin/ddev"
log "detected DDEV_BIN=$DDEV_BIN"

# ddev version (advisory). Recorded for the rootless ddev-version gate —
# DDEV >= 1.25 is required for Docker Rootless / Podman support (see
# docs/DOCKER-ROOTLESS.md §6.8). Parse the first semver-like token from the
# real binary's `version` output; empty when ddev is absent or unparseable.
DDEV_VERSION=""
if [ -x "$DDEV_BIN" ]; then
    DDEV_VERSION="$("$DDEV_BIN" version 2>/dev/null | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')"
fi
log "detected DDEV_VERSION=${DDEV_VERSION:-unknown}"

# Container backend selection (Phase 2: detection + provisioning, see
# docs/DOCKER-ROOTLESS.md §6.4, §6.7). On a re-install over an existing kit,
# preserve a previously configured backend unless --container-backend overrides.
CONTAINER_BACKEND="docker-group"
OPENCODE_DOCKER_HOST=""
OPENCODE_PODMAN_SOCKET=""
for _c in /etc/opencode-permissions-kit/install.conf /etc/opencode/install.conf; do
    if [ -f "$_c" ]; then
        _be=$(sed -n 's/^CONTAINER_BACKEND=//p' "$_c" 2>/dev/null)
        _dh=$(sed -n 's/^OPENCODE_DOCKER_HOST=//p' "$_c" 2>/dev/null)
        _ps=$(sed -n 's/^OPENCODE_PODMAN_SOCKET=//p' "$_c" 2>/dev/null)
        [ -n "$_be" ] && CONTAINER_BACKEND="$_be"
        [ -n "$_dh" ] && OPENCODE_DOCKER_HOST="$_dh"
        [ -n "$_ps" ] && OPENCODE_PODMAN_SOCKET="$_ps"
        break
    fi
done

# --container-backend flag overrides (for non-interactive scripting).
if [ -n "$CONTAINER_BACKEND_OPT" ]; then
    case "$CONTAINER_BACKEND_OPT" in
        docker-group|docker-rootless|podman-rootless|none)
            CONTAINER_BACKEND="$CONTAINER_BACKEND_OPT"
            ;;
        *)
            echo "${RED}Invalid --container-backend: '$CONTAINER_BACKEND_OPT'${NC}"
            echo "${YELLOW}Supported: docker-group | docker-rootless | podman-rootless | none${NC}"
            exit 1
            ;;
    esac
fi

# Interactive prompt (only when not --yes and no --container-backend flag).
# Auto-detect the container situation and present a choice. --yes defaults to
# docker-group (zero host change); explicit selection is done via the flag.
if [ "$SKIP_PROMPTS" != true ] && [ -z "$CONTAINER_BACKEND_OPT" ]; then
    echo ""
    echo "--- Container backend ---"
    echo ""
    echo "  The container backend decides how opencode reaches Docker/Podman."
    echo "  docker-group (default) gives root-equivalent host access via the docker socket."
    echo "  docker-rootless / podman-rootless confine containers to the opencode UID so"
    echo "  the kit's ACL denies hold inside bind-mounted containers (see docs/DOCKER-ROOTLESS.md)."
    echo ""
    echo "  [1] docker-group (default — no host change, root-equivalent)"
    if command -v podman >/dev/null 2>&1 && sudo -u "$OPENCODE_USER" podman info >/dev/null 2>&1; then
        echo "  [2] podman-rootless (RECOMMENDED — podman already installed, ACL denies hold)"
        echo "  [3] docker-rootless (needs systemd --user + docker-ce-rootless-extras)"
    else
        echo "  [2] podman-rootless (RECOMMENDED — will install podman + uidmap)"
        echo "  [3] docker-rootless (needs systemd --user + docker-ce-rootless-extras)"
    fi
    echo "  [4] none (no container access)"
    printf "  > "
    read -r _be_sel </dev/tty 2>/dev/null || read -r _be_sel
    case "$_be_sel" in
        2) CONTAINER_BACKEND="podman-rootless" ;;
        3) CONTAINER_BACKEND="docker-rootless" ;;
        4) CONTAINER_BACKEND="none" ;;
        *) CONTAINER_BACKEND="docker-group" ;;
    esac
fi

# Provision the chosen backend (only for rootless; docker-group/none = no-op).
# The helper installs packages, allocates subuid/subgid, and sets up the
# daemon. It prints OPENCODE_DOCKER_HOST=... on stdout for the caller to record.
if [ "$CONTAINER_BACKEND" = "docker-rootless" ] || [ "$CONTAINER_BACKEND" = "podman-rootless" ]; then
    echo ""
    echo "--- Provisioning container backend: $CONTAINER_BACKEND ---"
    SETUP_SCRIPT="$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh"
    [ -f "$SETUP_SCRIPT" ] || SETUP_SCRIPT="$LIBDIR/setup-container-backend.sh"
    # Capture stdout (socket key) + let stderr flow to the terminal.
    _setup_out=$(sh "$SETUP_SCRIPT" "$CONTAINER_BACKEND" --yes 2>&1) || {
        echo "${RED}Container backend provisioning failed.${NC}"
        echo "$_setup_out"
        echo "${YELLOW}Falling back to docker-group (root-equivalent). Fix the issue above and re-run.${NC}"
        CONTAINER_BACKEND="docker-group"
        OPENCODE_DOCKER_HOST=""
        OPENCODE_PODMAN_SOCKET=""
    }
    # Extract the socket key from the helper output (last line starting OPENCODE_).
    _sock=$(echo "$_setup_out" | sed -n 's/^\(OPENCODE_DOCKER_HOST=.*\)/\1/p' | tail -1)
    if [ -n "$_sock" ]; then
        OPENCODE_DOCKER_HOST="${_sock#OPENCODE_DOCKER_HOST=}"
    fi
    echo "$_setup_out" | grep -v '^OPENCODE_' | sed 's/^/  /'
fi

# Handle 'none' — no container access at all.
if [ "$CONTAINER_BACKEND" = "none" ]; then
    CONTAINER_BACKEND="docker-group"
    # The wrapper will never get a docker-group grant request because no project
    # will be configured to enable docker tools. Record docker-group but with
    # no socket — same as the legacy default.
fi

log "container backend: $CONTAINER_BACKEND"

# === Step 1: User ===

if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ans=$(prompt "User '$OPENCODE_USER' already exists. Add to www-data and continue?" "Y" "N" "")
    [ "$ans" != "y" ] && { echo "Aborted."; exit 1; }
else
    sudo useradd -m -s /bin/bash "$OPENCODE_USER"
    echo "User '$OPENCODE_USER' created."
    log "user created: $OPENCODE_USER"
fi

sudo usermod -aG "$WWW_GROUP" "$OPENCODE_USER" 2>/dev/null || true
sudo usermod -aG "$WWW_GROUP" "$DEFAULT_USER" 2>/dev/null || true
log "users added to group $WWW_GROUP: $OPENCODE_USER, $DEFAULT_USER"

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

sudo mkdir -p /etc/opencode-permissions-kit
if [ -n "$PROJECTS_ROOTS" ]; then
    echo "$PROJECTS_ROOTS" | tr ' ' '\n' | sudo tee /etc/opencode-permissions-kit/projects.conf > /dev/null
    echo "Project roots: $PROJECTS_ROOTS"
    log "projects.conf written: $PROJECTS_ROOTS"
else
    sudo touch /etc/opencode-permissions-kit/projects.conf
    echo "No project roots configured."
    log "projects.conf written: (empty)"
fi

# Backup project ACLs now that roots are known
if [ -n "$PROJECTS_ROOTS" ]; then
    sudo getfacl -R $PROJECTS_ROOTS 2>/dev/null > "$BACKUP_DIR/getfacl-R-projects.txt" || true
    echo "Project ACLs backed up to $BACKUP_DIR/getfacl-R-projects.txt"
fi

sudo tee /etc/opencode-permissions-kit/install.conf > /dev/null <<EOF
DEFAULT_USER=$DEFAULT_USER
OPENCODE_USER=$OPENCODE_USER
WWW_GROUP=$WWW_GROUP
DDEV_BIN=$DDEV_BIN
DDEV_VERSION=$DDEV_VERSION
CONTAINER_BACKEND=$CONTAINER_BACKEND
OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST
OPENCODE_PODMAN_SOCKET=$OPENCODE_PODMAN_SOCKET
VERSION=$VERSION
EOF
# Migrate legacy setup.conf (pre-v0.0.9) -> install.conf
[ -f /etc/opencode-permissions-kit/setup.conf ] && sudo rm -f /etc/opencode-permissions-kit/setup.conf
log "install.conf written (version $VERSION)"

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

sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
log "umask profile installed: /etc/profile.d/opencode-permissions-kit-umask.sh"

# === Step 4: opencode binary ===

echo ""
echo "--- opencode installation ---"

SYSTEM_BIN="/usr/local/lib/opencode-permissions-kit/bin/opencode"
# The binary must be executable only for root and the opencode user, so a tool
# invoking the absolute path as the default user cannot bypass the wrapper.
BINARY_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"
secure_binary() {
    sudo chown "root:$BINARY_GROUP" "$SYSTEM_BIN" 2>/dev/null || true
    sudo chmod 750 "$SYSTEM_BIN" 2>/dev/null || true
}
opencode_found=false

for loc in "/home/$DEFAULT_USER/.opencode/bin/opencode" "/root/.opencode/bin/opencode" "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -x "$loc" ] && [ "$loc" != "/usr/local/bin/opencode" ]; then
        ans=$(prompt "opencode binary found at $loc. Copy to system path and secure with wrapper?" "Y" "N" "B")
        case "$ans" in
            y)
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                sudo cp "$loc" "$SYSTEM_BIN"
                secure_binary
                opencode_found=true
                echo "Copied to $SYSTEM_BIN."
                log "binary copied: $loc -> $SYSTEM_BIN"
                break
                ;;
            b)
                cp "$loc" "$BACKUP_DIR/opencode-binary" 2>/dev/null || true
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                sudo cp "$loc" "$SYSTEM_BIN"
                secure_binary
                opencode_found=true
                echo "Backup saved. Copied to $SYSTEM_BIN."
                log "binary copied: $loc -> $SYSTEM_BIN (backup saved)"
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
            secure_binary
            echo "Installed to $SYSTEM_BIN."
            log "binary installed (official installer): /root/.opencode/bin/opencode -> $SYSTEM_BIN"
        elif [ -x "/home/$DEFAULT_USER/.opencode/bin/opencode" ]; then
            sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
            sudo cp "/home/$DEFAULT_USER/.opencode/bin/opencode" "$SYSTEM_BIN"
            secure_binary
            echo "Installed to $SYSTEM_BIN."
            log "binary installed (official installer): /home/$DEFAULT_USER/.opencode/bin/opencode -> $SYSTEM_BIN"
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
        if ! sudo grep -q 'export PATH="/usr/local/bin:$PATH"' "$cf" 2>/dev/null; then
            echo "" | sudo tee -a "$cf" > /dev/null
            echo 'export PATH="/usr/local/bin:$PATH"  # opencode permissions kit' | sudo tee -a "$cf" > /dev/null
        fi
        # Interactive-shell bypass warning: sources shell-warn.sh so a
        # self-installed opencode binary is reported in non-login shells too.
        # The [ -f ... ] guard keeps the line harmless after uninstall.
        if ! sudo grep -q 'opencode-permissions-kit/shell-warn.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/shell-warn.sh ] && . /usr/local/lib/opencode-permissions-kit/shell-warn.sh  # opencode permissions kit (wrapper bypass warning)' | sudo tee -a "$cf" > /dev/null
        fi
    fi
done
log "shell PATH config cleaned/updated for $DEFAULT_USER (wrapper bypass warning hooked)"

# === Step 5: opencode library (consolidated deployment in /usr/local/lib/opencode-permissions-kit/) ===

LIBDIR="/usr/local/lib/opencode-permissions-kit"

sudo mkdir -p "$LIBDIR/hooks"

# Copy all our scripts into the library directory
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/protect-projects.sh" "$LIBDIR/protect-projects.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh"              "$LIBDIR/log.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/shell-warn.sh"       "$LIBDIR/shell-warn.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh" "$LIBDIR/setup-container-backend.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/hooks/post-checkout" "$LIBDIR/hooks/post-checkout"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/hooks/post-merge"    "$LIBDIR/hooks/post-merge"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/hooks/post-commit"   "$LIBDIR/hooks/post-commit"
sudo cp "$SCRIPT_DIR/config.sh"                        "$LIBDIR/config.sh"
sudo cp "$SCRIPT_DIR/update.sh"                        "$LIBDIR/update.sh"
sudo cp "$SCRIPT_DIR/status.sh"                        "$LIBDIR/status.sh"
sudo cp "$SCRIPT_DIR/opencode.jsonc"                   "$LIBDIR/opencode.jsonc"
sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc"          "$LIBDIR/opencode-deny-all.jsonc"
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
# ddev delegation shim
sudo mkdir -p "$LIBDIR/bin"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/ddev"            "$LIBDIR/bin/ddev"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/socket-check.sh" "$LIBDIR/bin/socket-check.sh"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/protect-projects.sh" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/log.sh" "$LIBDIR/shell-warn.sh" "$LIBDIR/setup-container-backend.sh" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/hooks/post-checkout" "$LIBDIR/hooks/post-merge" "$LIBDIR/hooks/post-commit" \
               "$LIBDIR/bin/ddev" "$LIBDIR/bin/socket-check.sh"
log "library deployed to $LIBDIR"

# Symlink: /usr/local/bin/opencode -> our wrapper
sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
echo "Wrapper installed: /usr/local/bin/opencode -> $LIBDIR/wrapper"
log "wrapper symlink: /usr/local/bin/opencode -> $LIBDIR/wrapper"

# Symlink: backward-compat path for direct protect-projects calls
sudo ln -sf "$LIBDIR/protect-projects.sh" /usr/local/sbin/protect-projects.sh

# Symlink: /usr/local/bin/ddev -> our shim, so the opencode agent's bare
# `ddev` invocations hit the delegating shim (ahead of the real ddev in PATH).
# Only shadow when /usr/local/bin/ddev is free or already ours — never clobber
# a real ddev installed there; in that layout delegation is unavailable (the
# real ddev wins on PATH) and the user must move it below /usr/local/bin.
if [ -L /usr/local/bin/ddev ] && [ "$(readlink /usr/local/bin/ddev)" = "$LIBDIR/bin/ddev" ]; then
    :
elif [ -e /usr/local/bin/ddev ]; then
    echo "  ${YELLOW}WARNING: /usr/local/bin/ddev exists (real ddev). ddev delegation shim NOT linked — move ddev below /usr/local/bin (e.g. /usr/bin) to enable delegation.${NC}"
    log "ddev shim NOT shadowed: /usr/local/bin/ddev already occupied"
else
    sudo ln -sf "$LIBDIR/bin/ddev" /usr/local/bin/ddev
    echo "ddev shim installed: /usr/local/bin/ddev -> $LIBDIR/bin/ddev (delegates to $DDEV_BIN as $DEFAULT_USER)"
    log "ddev shim symlinked: /usr/local/bin/ddev -> $LIBDIR/bin/ddev (DDEV_BIN=$DDEV_BIN)"
fi

# sudoers -> /etc/opencode-permissions-kit/sudoers, symlinked as /etc/sudoers.d/opencode-permissions-kit
SUDO_TMP=$(mktemp)
sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" -e "s#DDEV_BIN#$DDEV_BIN#g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
# The (opencode:docker) RunAs grant is only needed for the docker-group backend
# (the wrapper uses `sudo -u opencode -g docker`). The rootless backends run
# WITHOUT the docker group, so strip that block. Empty/unknown defaults to
# docker-group (legacy behaviour, matching the wrapper's normalization) so the
# grant stays available.
case "${CONTAINER_BACKEND:-docker-group}" in
    docker-rootless|podman-rootless)
        sed -e '/^#@docker-group-begin$/,/^#@docker-group-end$/d' "$SUDO_TMP" > "$SUDO_TMP.2"
        ;;
    *)
        sed -e '/^#@docker-group-begin$/d' -e '/^#@docker-group-end$/d' "$SUDO_TMP" > "$SUDO_TMP.2"
        ;;
esac
mv -f "$SUDO_TMP.2" "$SUDO_TMP"
sudo cp "$SUDO_TMP" /etc/opencode-permissions-kit/sudoers
sudo chmod 440 /etc/opencode-permissions-kit/sudoers
rm -f "$SUDO_TMP"
sudo ln -sf /etc/opencode-permissions-kit/sudoers /etc/sudoers.d/opencode-permissions-kit

if sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1; then
    echo "sudoers installed."
    log "sudoers installed: /etc/opencode-permissions-kit/sudoers -> /etc/sudoers.d/opencode-permissions-kit"
else
    echo "${RED}sudoers validation failed. Check /etc/opencode-permissions-kit/sudoers.${NC}"
    exit 1
fi

# Git hooks — core.hooksPath points directly into our library
sudo -u "$OPENCODE_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
sudo -u "$DEFAULT_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
echo "Git hooks configured (core.hooksPath = $LIBDIR/hooks)."
log "git hooks configured: core.hooksPath = $LIBDIR/hooks"

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
    log "opencode config installed: /home/opencode/.config/opencode/opencode.jsonc (secure_git=$SECURE_GIT_CONFIG)"
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
    log "opencode config replaced (backup: $BACKUP_DIR/opencode.jsonc-existing)"
else
    echo "Config already exists, not overwriting."
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        echo "  ${YELLOW}Heads-up: --secure-git-config was set but config already existed.${NC}" >&2
    fi
fi

# === Step 6b: Default-user config (self-update bypass protection) ===

# opencode's self-updater / installer can re-add ~/.opencode/bin to PATH, so
# 'opencode' would run the real binary as $DEFAULT_USER — bypassing the
# wrapper, its ACL refresh, and the 'opencode' user. Deploy a deny-* config
# for the default user so that mode is completely locked down.
DEFAULT_OC_DIR="/home/$DEFAULT_USER/.config/opencode"
DEFAULT_OC_CONF="$DEFAULT_OC_DIR/opencode.jsonc"
sudo mkdir -p "$DEFAULT_OC_DIR"
if [ -f "$DEFAULT_OC_CONF" ]; then
    ans=$(prompt "Default-user config $DEFAULT_OC_CONF already exists. Back it up as opencode.jsonc_BAK_<timestamp> and install the deny-all config?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        BAK_STAMP=$(date +%Y%m%d-%H%M%S)
        sudo mv "$DEFAULT_OC_CONF" "$DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
        echo "Backed up to $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
        log "default-user config backed up: $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
    else
        echo "${YELLOW}Existing config kept — deny-all protection NOT installed.${NC}"
    fi
fi
if [ ! -f "$DEFAULT_OC_CONF" ]; then
    sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
    sudo chown "$DEFAULT_USER:$WWW_GROUP" "$DEFAULT_OC_CONF"
    sudo chmod 664 "$DEFAULT_OC_CONF"
    echo "Deny-all config installed for default user: $DEFAULT_OC_CONF"
    log "deny-all config installed for default user: $DEFAULT_OC_CONF"
fi

# === Step 7: Initial protection run ===

if [ -n "$PROJECTS_ROOTS" ]; then
    sudo "$LIBDIR/protect-projects.sh" && echo "Initial ACL protection applied to projects."
fi

# === Step 8: Remove pre-0.0.10 legacy layout ===
# A re-install over an older kit leaves the old /usr/local/lib/opencode and
# /etc/opencode behind; tear them down so only the renamed layout remains.
# The opencode binary (if any) was already (re)deployed to $LIBDIR/bin/opencode
# in Step 4, and configs were written to /etc/opencode-permissions-kit above.
sudo rm -rf /usr/local/lib/opencode 2>/dev/null || true
sudo rm -rf /etc/opencode 2>/dev/null || true
sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
log "legacy pre-0.0.10 layout removed (if present)"

# === Done ===

echo ""
echo "  ${GREEN}Installation complete.${NC}"
echo ""
echo "  Run:    ${CYAN}opencode${NC}"
echo "  Backup: $BACKUP_DIR"
echo "  Docs:   ${CYAN}docs/MANUAL.md${NC} (config, skills, verification, uninstall)"
echo ""
log "install complete"
