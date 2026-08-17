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
# Soft protection model (docs/design/ddev-working.md): no hard ACL denies.
# The kit creates the opencode user, provisions a MANDATORY rootless container
# backend (docker-rootless or podman-rootless), prepares ddev to run as that
# user, and sets up the opencode usergroup as the sharing group.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --projects <path...>  Pre-Define project roots, skip interactive selection
#   --container-backend <docker-rootless|podman-rootless>  Non-interactive backend choice
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
    mkdir -p "$dir/opencode-permissions-kit-lib/bin"
    for f in install.sh config.sh update.sh uninstall.sh status.sh opencode.jsonc \
             opencode-deny-all.jsonc \
             sudoers.template umask.sh VERSION \
             opencode-permissions-kit-lib/wrapper opencode-permissions-kit-lib/jsonc-parser.py \
             opencode-permissions-kit-lib/log.sh opencode-permissions-kit-lib/ui.sh opencode-permissions-kit-lib/shell-warn.sh opencode-permissions-kit-lib/setup-container-backend.sh opencode-permissions-kit-lib/bin/socket-check.sh opencode-permissions-kit-lib/migrate-denies.sh opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode opencode-permissions-kit-lib/ddev-handover.sh; do
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
    SCRIPT_DIR="$(fetch_kit)" || { echo "error  Failed to fetch kit files from $KIT_BASE_URL" >&2; exit 1; }
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

# Shared ddev handover helpers (.ddev + settings dirs -> opencode user).
# install.sh always runs from a checkout or a fully fetched temp dir, so the
# helper sits right next to log.sh.
[ -f "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" ] && . "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh"
command -v ddev_handover_root >/dev/null 2>&1 || ddev_handover_root() { :; }

# === Shared UI helpers ===
# The kit files sit next to this script (checkout or fully fetched temp dir);
# a plain fallback keeps install.sh working if ui.sh is somehow missing.
UI_LIB="$SCRIPT_DIR/opencode-permissions-kit-lib/ui.sh"
if [ -f "$UI_LIB" ]; then
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
    ui_plan()    { printf '    %s  %s\n' "$1" "$2"; }
    UI_GREEN=''; UI_RED=''; UI_YELLOW=''; UI_CYAN=''; UI_BLUE=''; UI_NC=''
fi

OPENCODE_USER="opencode"
# The sharing group is the opencode user's own primary usergroup (created by
# useradd -m). Resolved after the user exists; "opencode" is only the default.
OPENCODE_GROUP="opencode"

SKIP_PROMPTS=false
PREDEFINED_PROJECTS=""
# Default true = .git/config deny rules active = git blocked for the agent
# (the recommended, pre-Phase-4 --yes behavior). The questions below and
# the --secure-git-config flag set it explicitly.
SECURE_GIT_CONFIG=true
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
        --secure-git-config) SECURE_GIT_CONFIG=true; GIT_FLAG_GIVEN=true ;;
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
    ui_banner "$VERSION" "installs opencode as its own user behind rootless containers"
}

# === Start ===

banner

DEFAULT_USER="${SUDO_USER:-$(whoami)}"
log "install started (version $VERSION, default user=$DEFAULT_USER)"

# === Install mode ===
# Standard asks only the essential questions and takes recommended defaults
# for everything else (same answers as --yes); Advanced keeps every granular
# prompt of the install steps below.
INTERACTIVE=true
[ "$SKIP_PROMPTS" = true ] && INTERACTIVE=false
MODE="standard"
if [ "$INTERACTIVE" = true ]; then
    _mode=$(ui_menu "How do you want to install?" "1" \
        "1|Standard (recommended — few questions, safe defaults)" \
        "2|Advanced (control every step)" \
        "x|Abort")
    case "$_mode" in
        x) ui_info "Aborted."; exit 0 ;;
        2) MODE="advanced" ;;
    esac
fi
log "install mode: $MODE (interactive=$INTERACTIVE)"

IS_WSL2=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL2=true
if [ "$IS_WSL2" != true ]; then
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

ui_section "Pre-flight"

if ! command -v curl >/dev/null 2>&1; then
    ui_error "curl is required but not installed."
    exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
    ans=$(prompt "'acl' package not installed (setfacl/getfacl missing). Install it now?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y acl
    fi
    if ! command -v setfacl >/dev/null 2>&1; then
        ui_error "setfacl required for the group-collaboration ACLs. Install the 'acl' package and re-run."
        exit 1
    fi
fi

# ddev version (hard gate): rootless ddev needs ddev >= 1.25. Resolve the
# real ddev (a legacy kit shim at /usr/local/bin/ddev still delegates and
# reports its own version) — prefer the recorded DDEV_BIN, then the first
# real ddev on PATH, then /usr/bin/ddev.
DDEV_BIN=""
for _c in /etc/opencode-permissions-kit/install.conf /etc/opencode/install.conf; do
    if [ -f "$_c" ]; then
        DDEV_BIN=$(sed -n 's/^DDEV_BIN=//p' "$_c" 2>/dev/null || true)
        break
    fi
done
if [ -z "$DDEV_BIN" ]; then
    DDEV_BIN="$(command -v ddev 2>/dev/null || true)"
    if [ -n "$DDEV_BIN" ] && [ -L "$DDEV_BIN" ] \
       && readlink "$DDEV_BIN" 2>/dev/null | grep -Eq 'lib/opencode(-permissions-kit)?/bin/ddev'; then
        DDEV_BIN="/usr/bin/ddev"
    fi
fi
DDEV_VERSION=""
if [ -n "$DDEV_BIN" ] && [ -x "$DDEV_BIN" ]; then
    DDEV_VERSION="$("$DDEV_BIN" version 2>/dev/null | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')"
fi
log "detected ddev: bin=${DDEV_BIN:-none} version=${DDEV_VERSION:-unknown}"
if command -v ddev >/dev/null 2>&1 || [ -n "$DDEV_BIN" ]; then
    if [ -n "$DDEV_VERSION" ]; then
        ddev_ok=$(awk -v v="$DDEV_VERSION" 'BEGIN{split(v,a,"."); if(a[1]+0>1 || (a[1]+0==1 && a[2]+0>=25)) print "yes"; else print "no"}')
        if [ "$ddev_ok" != "yes" ]; then
            ui_error "ddev $DDEV_VERSION found — the kit requires ddev >= 1.25 (rootless container support)."
            ui_warn "upgrade ddev (curl -fsSL https://ddev.com/install.sh | bash) and re-run."
            exit 1
        fi
    else
        ui_warn "could not parse the ddev version — continuing anyway (ddev >= 1.25 required)."
    fi
else
    ui_warn "ddev not found — continuing anyway (install it later with ddev >= 1.25)."
fi

# Container backend selection. Rootless is MANDATORY: docker-rootless
# (default) or podman-rootless. The legacy docker-group backend is gone
# (root-equivalent). On a re-install over an existing kit, preserve a
# previously configured rootless backend unless --container-backend overrides.
CONTAINER_BACKEND="docker-rootless"
OPENCODE_DOCKER_HOST=""
OPENCODE_PODMAN_SOCKET=""
for _c in /etc/opencode-permissions-kit/install.conf /etc/opencode/install.conf; do
    if [ -f "$_c" ]; then
        _be=$(sed -n 's/^CONTAINER_BACKEND=//p' "$_c" 2>/dev/null)
        _dh=$(sed -n 's/^OPENCODE_DOCKER_HOST=//p' "$_c" 2>/dev/null)
        _ps=$(sed -n 's/^OPENCODE_PODMAN_SOCKET=//p' "$_c" 2>/dev/null)
        case "$_be" in
            docker-rootless|podman-rootless)
                CONTAINER_BACKEND="$_be"
                [ -n "$_dh" ] && OPENCODE_DOCKER_HOST="$_dh"
                [ -n "$_ps" ] && OPENCODE_PODMAN_SOCKET="$_ps"
                ;;
        esac
        break
    fi
done

# --container-backend flag overrides (for non-interactive scripting).
if [ -n "$CONTAINER_BACKEND_OPT" ]; then
    case "$CONTAINER_BACKEND_OPT" in
        docker-rootless|podman-rootless)
            CONTAINER_BACKEND="$CONTAINER_BACKEND_OPT"
            ;;
        *)
            echo "${UI_RED}Invalid --container-backend: '$CONTAINER_BACKEND_OPT'${UI_NC}"
            echo "${UI_YELLOW}Supported: docker-rootless | podman-rootless (rootless only — docker-group was removed)${UI_NC}"
            exit 1
            ;;
    esac
fi

# Interactive backend choice (only when not --yes and no flag override).
# Both backends confine containers to the opencode UID — no root-equivalent
# docker socket is ever granted. Standard asks ONLY when podman is present
# ("stay with podman?"); docker-rootless is the silent default otherwise.
if [ "$INTERACTIVE" = true ] && [ -z "$CONTAINER_BACKEND_OPT" ]; then
    if [ "$MODE" = "advanced" ]; then
        _be_sel=$(ui_menu "Container backend for the agent user? (rootless, required)" \
            "$([ "$CONTAINER_BACKEND" = "podman-rootless" ] && echo 2 || echo 1)" \
            "1|docker-rootless (default — needs systemd --user + docker-ce-rootless-extras)" \
            "2|podman-rootless (daemonless, no systemd required)")
        case "$_be_sel" in
            2) CONTAINER_BACKEND="podman-rootless" ;;
            *) CONTAINER_BACKEND="docker-rootless" ;;
        esac
    elif command -v podman >/dev/null 2>&1; then
        _be_def="podman"
        [ "$CONTAINER_BACKEND" = "docker-rootless" ] && _be_def="docker"
        _be_sel=$(ui_menu "Podman is installed. Which rootless backend should the agent use?" \
            "$_be_def" \
            "podman|podman-rootless (daemonless — no systemd needed)" \
            "docker|docker-rootless (provisioned for the opencode user)")
        case "$_be_sel" in
            podman) CONTAINER_BACKEND="podman-rootless" ;;
            *)      CONTAINER_BACKEND="docker-rootless" ;;
        esac
    fi
fi

# === Pre-flight inventory =====================================================
# Read-only summary of what the checks found and what the installer will do
# about it — the user confirms the plan before anything is modified.
ui_section "Inventory"

[ "$IS_WSL2" = true ] && ui_have "WSL2" "detected" || ui_atten "WSL2" "not detected — continuing anyway"
ui_have "curl" "present"
command -v setfacl >/dev/null 2>&1 && ui_have "acl tools" "present" || ui_add "acl tools" "installing now"
if [ -n "$DDEV_VERSION" ]; then
    ui_have "ddev" "v$DDEV_VERSION (>= 1.25)"
else
    ui_atten "ddev" "not installed (optional — needs >= 1.25)"
fi
HAVE_DOCKER=false; HAVE_PODMAN=false
command -v docker  >/dev/null 2>&1 && HAVE_DOCKER=true
command -v podman  >/dev/null 2>&1 && HAVE_PODMAN=true
if [ "$HAVE_DOCKER" = true ]; then
    ui_have "docker CLI" "present — rootless backend will be provisioned for 'opencode'"
elif [ "$HAVE_PODMAN" = true ]; then
    ui_have "podman" "present — used rootless for 'opencode'"
else
    ui_add "$CONTAINER_BACKEND" "will be installed + provisioned for 'opencode'"
fi

# Existing kit detection: user 'opencode', install.conf, or a wrapper symlink.
EXISTING_KIT=false
if id "$OPENCODE_USER" >/dev/null 2>&1 || [ -f /etc/opencode-permissions-kit/install.conf ] || [ -L /usr/local/bin/opencode ]; then
    EXISTING_KIT=true
    _ekv="unknown"
    [ -f /etc/opencode-permissions-kit/install.conf ] && _ekv=$(sed -n 's/^VERSION=//p' /etc/opencode-permissions-kit/install.conf)
    ui_atten "existing kit" "detected (v${_ekv:-?}) — update.sh is the usual upgrade path"
    if [ "$INTERACTIVE" = true ]; then
        # Convention: docs/design/conventions.md — [Y/n] via ui_confirm.
        if ! ui_confirm "Re-configure the existing installation with install.sh?" "y"; then
            ui_info "Aborted — run: opencode-permissions-kit update"
            exit 0
        fi
    fi
fi

# opencode binary candidates (the copy+secure step runs later).
OC_BINARY_FOUND=""
for loc in "/home/$DEFAULT_USER/.opencode/bin/opencode" "/root/.opencode/bin/opencode" "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -x "$loc" ] && [ "$loc" != "/usr/local/bin/opencode" ]; then
        OC_BINARY_FOUND="$loc"
        ui_have "opencode binary" "$loc — will be secured under the kit"
        break
    fi
done
[ -n "$OC_BINARY_FOUND" ] || ui_add "opencode binary" "official installer will fetch it"

# WSL2 /mnt/c exposure preview (question + fix come later in step 4).
if [ -d /mnt/c ]; then
    _pm=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$_pm" ] && [ $((0$_pm & 0004)) -ne 0 ]; then
        ui_atten "/mnt/c" "world-readable (mode $_pm) — restriction offered in step 4"
    else
        ui_have "/mnt/c" "restricted (mode ${_pm:-?})"
    fi
fi

# Router-port readiness preview.
_pps=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
if [ "${_pps:-1024}" -le 80 ] 2>/dev/null; then
    ui_have "router ports" "ready (ip_unprivileged_port_start=$_pps)"
else
    ui_add "router ports" "sysctl to 80 offered (ddev-router 80/443)"
fi

# === Standard questions ========================================================
# Standard asks exactly: project directory + git access. The podman exception
# was already asked during backend selection. --yes takes the defaults.
if [ "$MODE" = "standard" ] && [ "$INTERACTIVE" = true ]; then
    ui_section "Standard setup"

    if [ -z "$PREDEFINED_PROJECTS" ]; then
        _pdef="/var/www/vhosts"
        [ -d "$_pdef" ] || _pdef=""
        _p=$(ui_ask "Project directory (agent workspaces)" "$_pdef")
        [ -n "$_p" ] && PREDEFINED_PROJECTS="$_p"
    fi
    if [ "$GIT_FLAG_GIVEN" != true ]; then
        _g=$(ui_menu "Allow opencode access to git commands?" "no" \
            "no|block .git/config for the agent (recommended)" \
            "yes|allow git commands")
        if [ "$_g" = "yes" ]; then SECURE_GIT_CONFIG=false; else SECURE_GIT_CONFIG=true; fi
    fi
fi

# === Plan + confirmation ========================================================
# The full plan with the effective values; C proceeds, A switches to the
# granular prompts (Advanced), X aborts. Non-interactive runs print the plan
# without asking.
ui_section "Plan"

# Numbered dynamically: optional steps (mnt/c, port sysctl) are omitted
# when not applicable — no gaps in the list the user confirms.
_plan_n=0
_plan() { _plan_n=$((_plan_n + 1)); ui_plan "$_plan_n" "$1" "$2"; }

_plan "create user 'opencode' + sharing group" "(developer '$DEFAULT_USER' added)"
_plan "provision $CONTAINER_BACKEND for 'opencode'" "(mandatory — aborts on failure)"
if [ -n "$PREDEFINED_PROJECTS" ]; then
    _plan "group + setgid + default ACLs" "on $PREDEFINED_PROJECTS"
else
    _plan "group + setgid + default ACLs" "(project roots selected next)"
fi
_plan "secure the opencode binary + wrapper" "root:opencode 750"
if [ -d /mnt/c ]; then
    _pm=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$_pm" ] && [ $((0$_pm & 0004)) -ne 0 ]; then
        _plan "restrict /mnt/c via /etc/wsl.conf" "(takes effect after wsl --shutdown)"
    fi
fi
_pps=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
[ "${_pps:-1024}" -gt 80 ] 2>/dev/null && _plan "lower ip_unprivileged_port_start to 80" "(ddev-router 80/443)"
_plan "deny-all config for your user" "(self-update bypass guard)"
_plan "deploy library, sudoers, audit log" "/usr/local/lib/opencode-permissions-kit"

if [ "$INTERACTIVE" = true ]; then
    echo ""
    _go=$(ui_menu "Proceed?" "C" "C|Confirm" "A|Switch to Advanced" "X|Abort")
    case "$_go" in
        X)  ui_info "Aborted — nothing was changed."; exit 0 ;;
        A)  MODE="advanced"
            ui_info "Advanced mode — the remaining steps ask for your decisions." ;;
    esac
fi

# Standard answers every remaining decision with the recommended value
# (identical to --yes); Advanced keeps the granular prompts below.
[ "$MODE" = "standard" ] && SKIP_PROMPTS=true
log "plan confirmed (mode=$MODE)"

# === Step 1: User + group ===

ui_info "Creating user + sharing group ..."
if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ans=$(prompt "User '$OPENCODE_USER' already exists. Reuse it?" "Y" "N" "")
    [ "$ans" != "y" ] && { ui_info "Aborted."; exit 1; }
else
    sudo useradd -m -s /bin/bash "$OPENCODE_USER"
    ui_success "user '$OPENCODE_USER' created"
    log "user created: $OPENCODE_USER"
fi

# The sharing group is the opencode user's PRIMARY usergroup (auto-created by
# useradd -m). No www-data, no extra group to create or remove.
OPENCODE_GROUP=$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")
sudo usermod -aG "$OPENCODE_GROUP" "$DEFAULT_USER" 2>/dev/null || true
ui_success "sharing group '$OPENCODE_GROUP' (developer '$DEFAULT_USER' added)"
log "sharing group: $OPENCODE_GROUP (developer $DEFAULT_USER added)"

# === Step 2: Project roots ===

if [ -n "$PREDEFINED_PROJECTS" ]; then
    PROJECTS_ROOTS="$PREDEFINED_PROJECTS"
else
    ui_section "Project roots"
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
        ui_warn "no standard directories found."
    fi
    echo "  [c] Custom path(s)"
    echo "  [s] Skip (no project baseline, only user + wrapper)"
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
            echo "Skipping project baseline."
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

ui_info "Writing /etc/opencode-permissions-kit/install.conf ..."
sudo tee /etc/opencode-permissions-kit/install.conf > /dev/null <<EOF
DEFAULT_USER=$DEFAULT_USER
OPENCODE_USER=$OPENCODE_USER
OPENCODE_GROUP=$OPENCODE_GROUP
DDEV_VERSION=$DDEV_VERSION
CONTAINER_BACKEND=$CONTAINER_BACKEND
OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST
OPENCODE_PODMAN_SOCKET=$OPENCODE_PODMAN_SOCKET
VERSION=$VERSION
EOF
# Migrate legacy setup.conf (pre-v0.0.9) -> install.conf
[ -f /etc/opencode-permissions-kit/setup.conf ] && sudo rm -f /etc/opencode-permissions-kit/setup.conf
log "install.conf written (version $VERSION)"

# === Step 3: Provision the rootless container backend (mandatory) ===
# A failed provisioning ABORTS the install — the kit does not fall back to a
# root-equivalent docker-group path. The helper installs packages, allocates
# subuid/subgid, and sets up the daemon; it prints OPENCODE_DOCKER_HOST=... on
# stdout for the caller to record.
ui_section "Provisioning container backend: $CONTAINER_BACKEND"
SETUP_SCRIPT="$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh"
[ -f "$SETUP_SCRIPT" ] || SETUP_SCRIPT="$LIBDIR/setup-container-backend.sh"
_setup_out=$(sh "$SETUP_SCRIPT" "$CONTAINER_BACKEND" --yes 2>&1) || {
    ui_error "Container backend provisioning failed."
    echo "$_setup_out"
    ui_warn "fix the issue above and re-run. podman-rootless needs no systemd — try it when docker-rootless cannot run."
    log "container backend provisioning FAILED ($CONTAINER_BACKEND) — install aborted"
    exit 1
}
_sock=$(echo "$_setup_out" | sed -n 's/^\(OPENCODE_DOCKER_HOST=.*\)/\1/p' | tail -1)
if [ -n "$_sock" ]; then
    OPENCODE_DOCKER_HOST="${_sock#OPENCODE_DOCKER_HOST=}"
fi
echo "$_setup_out" | grep -v '^OPENCODE_' | sed 's/^/     /'
ui_success "container backend provisioned: $CONTAINER_BACKEND"
sudo sed -i "s#^OPENCODE_DOCKER_HOST=.*#OPENCODE_DOCKER_HOST=$OPENCODE_DOCKER_HOST#" /etc/opencode-permissions-kit/install.conf
log "container backend provisioned: $CONTAINER_BACKEND"

# === Step 4: ddev as the opencode user ===
# /home/<oc>/.ddev is the opencode user's global ddev home (project registry,
# mutagen state, `ddev auth ssh` key cache). mkcert CA reuse keeps Windows
# browsers trusting ddev's HTTPS certs. Router ports: rootless ddev-router
# cannot bind 80/443 unless ip_unprivileged_port_start <= 80.
ui_section "ddev runtime for user $OPENCODE_USER"
sudo mkdir -p "/home/$OPENCODE_USER/.ddev"
sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" "/home/$OPENCODE_USER/.ddev"
sudo chmod 755 "/home/$OPENCODE_USER/.ddev"
log "ddev home provisioned: /home/$OPENCODE_USER/.ddev"

port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)
if [ "${port_start:-1024}" -gt 80 ] 2>/dev/null; then
    ans=$(prompt "Lower net.ipv4.ip_unprivileged_port_start to 80 so ddev-router can bind 80/443? (host-wide sysctl)" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        if echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-ddev-rootless.conf >/dev/null 2>&1; then
            if sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1; then
                ui_success "unprivileged port start lowered to 80 (persisted: /etc/sysctl.d/99-ddev-rootless.conf)"
                log "net.ipv4.ip_unprivileged_port_start=80 applied"
                # docker-rootless: the daemon's network namespace inherited the
                # OLD value at start; restart it so it re-inherits 80.
                # podman-rootless is daemonless (fresh netns per run) — no restart.
                oc_uid=$(id -u "$OPENCODE_USER" 2>/dev/null)
                if [ "$CONTAINER_BACKEND" = "docker-rootless" ] && [ -n "$oc_uid" ]; then
                    if sudo -u "$OPENCODE_USER" XDG_RUNTIME_DIR="/run/user/$oc_uid" systemctl --user restart docker.service 2>/dev/null; then
                        ui_success "restarted the opencode rootless docker daemon (its netns re-inherits port-start 80)"
                        log "rootless docker daemon restarted for port-start 80"
                    else
                        ui_warn "could not restart the rootless daemon — run it manually:"
                        echo "  sudo -u $OPENCODE_USER XDG_RUNTIME_DIR=/run/user/$oc_uid systemctl --user restart docker.service"
                        log "rootless daemon restart failed (admin must restart manually)"
                    fi
                fi
            else
                ui_warn "sysctl persisted but not activated live (read-only /proc/sys?) — reboot or run:"
                echo "  sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
                log "sysctl persisted but not activated live"
            fi
        else
            ui_warn "could not write /etc/sysctl.d/99-ddev-rootless.conf — apply the sysctl manually or use higher router ports."
        fi
    else
        ui_detail "skipped — either set the sysctl manually or use higher router ports:"
        echo "  sudo -u $OPENCODE_USER ddev config global --router-http-port 8080 --router-https-port 8443"
    fi
fi

# WSL2 /mnt/c restriction: the drvfs mount runs with the Windows session
# token, so NTFS ACLs do NOT distinguish WSL users — the world-readable
# default (mode 777) exposes the whole Windows profile (.ssh, NTUSER.DAT,
# browser data) to every WSL user, including the agent's. Offer to restrict
# the mount to the default user. Takes effect only after 'wsl --shutdown'
# from Windows (the kit cannot reboot the distro).
if [ -d /mnt/c ]; then
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -z "$mnt_mode" ] || [ $((0$mnt_mode & 0004)) -eq 0 ]; then
        echo "  /mnt/c already restricted (mode ${mnt_mode:-?}) — Windows profile not exposed."
    elif grep -q '^\[automount\]' /etc/wsl.conf 2>/dev/null; then
        echo "  ${UI_YELLOW}NOTE: /etc/wsl.conf already has an [automount] section — left untouched.${UI_NC}"
        echo "  /mnt/c is world-readable (mode $mnt_mode); every WSL user incl. the agent"
        echo "  can read the Windows profile. Restrict it manually if unintended."
        log "wsl.conf has a pre-existing [automount] section — /mnt/c restriction skipped"
    else
        echo "  ${UI_YELLOW}WARNING: /mnt/c is world-readable (mode $mnt_mode) — every WSL user incl. the${UI_NC}"
        echo "  ${UI_YELLOW}agent can read the Windows profile (.ssh, NTUSER.DAT, browser data).${UI_NC}"
        ans=$(prompt "Restrict /mnt/c to your user? (WSL2 drvfs is world-readable by default; recommended)" "Y" "N" "")
        if [ "$ans" = "y" ]; then
            d_uid=$(id -u "$DEFAULT_USER" 2>/dev/null || echo "")
            d_gid=$(id -g "$DEFAULT_USER" 2>/dev/null || echo "")
            if [ -n "$d_uid" ] && [ -n "$d_gid" ]; then
                printf '\n[automount]\nenabled = true\noptions = "uid=%s,gid=%s,dmask=027,fmask=037"\n' "$d_uid" "$d_gid" | sudo tee -a /etc/wsl.conf >/dev/null
                echo "  /etc/wsl.conf: [automount] restricted to uid=$d_uid/gid=$d_gid (dmask=027,fmask=037)"
                echo "  ${UI_YELLOW}Takes effect after 'wsl --shutdown' (Windows PowerShell) and reopening the distro.${UI_NC}"
                log "wsl.conf automount restricted to uid=$d_uid gid=$d_gid"
            else
                echo "  ${UI_YELLOW}Could not resolve uid/gid for '$DEFAULT_USER' — add manually to /etc/wsl.conf:${UI_NC}"
                echo "    [automount]"
                echo "    enabled = true"
                echo '    options = "uid=<your-uid>,gid=<your-gid>,dmask=027,fmask=037"'
            fi
        else
            echo "  Skipped — /mnt/c stays world-readable; status.sh will keep reporting the exposure."
            log "wsl.conf /mnt/c restriction declined"
        fi
    fi
fi

# mkcert CA reuse: search order 1. Windows CA (WSL2 /mnt/c), 2. developer's
# Linux CAROOT, 3. 'mkcert -install' (new, untrusted CA).
caroot="/home/$OPENCODE_USER/.local/share/mkcert"
if [ ! -f "$caroot/rootCA.pem" ]; then
    sudo mkdir -p "$caroot"
    src=""
    src_label=""
    # 1. Windows CA: scan the user profiles DIRECTLY. powershell.exe /
    #    cmd.exe are frequently not on a WSL PATH, so %USERNAME% probing is
    #    unreliable — a failed probe silently skipped the Windows CA and
    #    fell through to an untrusted one (browsers showed "not secure").
    if [ -d /mnt/c/Users ]; then
        for wca in /mnt/c/Users/*/AppData/Local/mkcert; do
            if [ -f "$wca/rootCA.pem" ] && [ -f "$wca/rootCA-key.pem" ]; then
                src="$wca"
                wuser=${wca#/mnt/c/Users/}
                src_label="Windows user '${wuser%%/*}'"
                break
            fi
        done
    fi
    if [ -z "$src" ] && [ -n "$DEFAULT_USER" ] && [ -f "/home/$DEFAULT_USER/.local/share/mkcert/rootCA.pem" ]; then
        src="/home/$DEFAULT_USER/.local/share/mkcert"; src_label="developer '$DEFAULT_USER'"
    fi
    if [ -n "$src" ]; then
        sudo cp "$src/rootCA.pem" "$src/rootCA-key.pem" "$caroot/" 2>/dev/null && \
        sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" "$caroot" && \
        sudo chmod 700 "$caroot" && sudo chmod 600 "$caroot/rootCA-key.pem" && \
        echo "  mkcert CA reused from $src_label -> $caroot (Windows browsers already trust it)" && \
        log "mkcert CA reused from $src_label for $OPENCODE_USER"
    elif command -v mkcert >/dev/null 2>&1; then
        sudo -u "$OPENCODE_USER" env CAROOT="$caroot" mkcert -install >/dev/null 2>&1 || true
        [ -f "$caroot/rootCA.pem" ] && \
            echo "  ${UI_YELLOW}mkcert: no existing CA found — a new one was created at $caroot.${UI_NC}" && \
            echo "  ${UI_YELLOW}Import $caroot/rootCA.pem into your browser's trust store for HTTPS.${UI_NC}" && \
            log "mkcert: no existing CA — new one created for $OPENCODE_USER"
    else
        echo "  ${UI_YELLOW}NOTE: mkcert not installed and no CA to reuse — install mkcert or copy your CA to $caroot.${UI_NC}"
    fi
fi

# === Step 5: Filesystem (group baseline) ===

if [ -n "$PROJECTS_ROOTS" ]; then
    ui_section "Filesystem (group baseline)"
    ans=$(prompt "Apply group-$OPENCODE_GROUP, setgid, and default ACLs to project roots? (changes metadata on ALL files)" "Y" "N" "B")
    case "$ans" in
        n) ui_detail "skipping filesystem setup." ;;
        b)
            getfacl -R $PROJECTS_ROOTS 2>/dev/null > "$BACKUP_DIR/getfacl-R-projects.txt" || true
            echo "Backup saved." ;;
        y) ;;
    esac
    if [ "$ans" != "n" ]; then
        for root in $PROJECTS_ROOTS; do
            [ -d "$root" ] || continue
            sudo chgrp -R "$OPENCODE_GROUP" "$root" 2>/dev/null || true
            sudo chmod g+s "$root"
            sudo setfacl -R -d -m "g:$OPENCODE_GROUP:rwx" "$root" 2>/dev/null || true
            ui_success "$root — group + setgid + default ACLs applied"
        done
    fi
    # .ddev + settings-dir handover (ddev always runs as $OPENCODE_USER):
    # ddev chmods .ddev and the app-type's settings directories
    # unconditionally, and chmod is owner-only — they must belong to the
    # opencode user or `ddev start` fails with "operation not permitted"
    # (e.g. "chmod .../config/system"). Searched at ANY depth under each
    # root (a root is often a parent of several projects). Idempotent;
    # the mode-700 .git dir stays dev-owned.
    for root in $PROJECTS_ROOTS; do
        [ -d "$root" ] || continue
        ddev_handover_root "$root" "$OPENCODE_USER" "$OPENCODE_GROUP"
        log "ddev handover applied under $root"
    done
fi

sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
log "umask profile installed: /etc/profile.d/opencode-permissions-kit-umask.sh"

# === Step 6: opencode binary ===

ui_section "opencode binary + wrapper"

SYSTEM_BIN="/usr/local/lib/opencode-permissions-kit/bin/opencode"
# The binary must be executable only for root and the opencode user, so a tool
# invoking the absolute path as the default user cannot bypass the wrapper.
BINARY_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"
secure_binary() {
    sudo chown "root:$BINARY_GROUP" "$SYSTEM_BIN" 2>/dev/null || true
    sudo chmod 750 "$SYSTEM_BIN" 2>/dev/null || true
}
# The wrapper warns about a self-installed binary shadowing it from
# ~/.opencode/bin. Once our secured copy exists, remove the user-local
# original (backed up first) so the first wrapper run is warning-free.
remove_shadow_binary() {
    case "$1" in
        */.opencode/bin/opencode) ;;
        *) return 0 ;;   # never touch /usr/bin, /usr/local/bin, ...
    esac
    [ -e "$1" ] || return 0
    cp "$1" "$BACKUP_DIR/opencode-binary" 2>/dev/null || true
    sudo rm -f "$1"
    echo "Removed user-local copy: $1 (backup: $BACKUP_DIR/opencode-binary)"
    log "user-local opencode binary removed: $1 (backed up to $BACKUP_DIR/opencode-binary)"
}
opencode_found=false

# Re-install over an existing kit: the secured binary is already in place.
# Reuse it — do NOT re-run the official installer (its `opencode --version`
# probe reaches the real binary through the wrapper now and reports
# "already installed", skipping the download, which would abort here).
if [ -x "$SYSTEM_BIN" ]; then
    secure_binary
    opencode_found=true
    ui_detail "binary already secured under the kit — reusing $SYSTEM_BIN"
    log "binary reused on re-install: $SYSTEM_BIN"
fi

for loc in "/home/$DEFAULT_USER/.opencode/bin/opencode" "/root/.opencode/bin/opencode" "/usr/local/bin/opencode" "/usr/bin/opencode"; do
    if [ -x "$loc" ] && [ "$loc" != "/usr/local/bin/opencode" ]; then
        ans=$(prompt "opencode binary found at $loc. Copy to system path and secure with wrapper?" "Y" "N" "B")
        case "$ans" in
            y)
                sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
                sudo cp "$loc" "$SYSTEM_BIN"
                secure_binary
                remove_shadow_binary "$loc"
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
                remove_shadow_binary "$loc"
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
            remove_shadow_binary "/root/.opencode/bin/opencode"
            echo "Installed to $SYSTEM_BIN."
            log "binary installed (official installer): /root/.opencode/bin/opencode -> $SYSTEM_BIN"
        elif [ -x "/home/$DEFAULT_USER/.opencode/bin/opencode" ]; then
            sudo mkdir -p "$(dirname "$SYSTEM_BIN")"
            sudo cp "/home/$DEFAULT_USER/.opencode/bin/opencode" "$SYSTEM_BIN"
            secure_binary
            remove_shadow_binary "/home/$DEFAULT_USER/.opencode/bin/opencode"
            echo "Installed to $SYSTEM_BIN."
            log "binary installed (official installer): /home/$DEFAULT_USER/.opencode/bin/opencode -> $SYSTEM_BIN"
        else
            echo "${UI_RED}Installation failed. Install opencode manually and re-run.${UI_NC}"
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
            echo 'export PATH="/usr/local/bin:$PATH"' | sudo tee -a "$cf" > /dev/null
        fi
        # Interactive-shell bypass warning: sources shell-warn.sh so a
        # self-installed opencode binary is reported in non-login shells too.
        # The [ -f ... ] guard keeps the line harmless after uninstall.
        if ! sudo grep -q 'opencode-permissions-kit/shell-warn.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/shell-warn.sh ] && . /usr/local/lib/opencode-permissions-kit/shell-warn.sh  # opencode permissions kit (wrapper bypass warning)' | sudo tee -a "$cf" > /dev/null
        fi
        # Interactive-shell ddev function: `ddev` always runs as the opencode
        # user (sudoers helper), so the developer terminal and the agent share
        # one ddev home. The [ -f ... ] guard keeps the line harmless after
        # uninstall. Only the DEFAULT user gets it — the opencode session must
        # never be wrapped (the function's id check would be recursive).
        if ! sudo grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh ] && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh  # opencode permissions kit (ddev always runs as opencode)' | sudo tee -a "$cf" > /dev/null
        fi
    fi
done
log "shell PATH config cleaned/updated for $DEFAULT_USER (wrapper bypass warning + ddev-as-opencode hooked)"

# === Step 7: opencode library (consolidated deployment in /usr/local/lib/opencode-permissions-kit/) ===

ui_section "Deploying the kit library"
LIBDIR="/usr/local/lib/opencode-permissions-kit"

sudo mkdir -p "$LIBDIR/bin"

# Copy all our scripts into the library directory
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/kit"                "$LIBDIR/kit"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh"              "$LIBDIR/log.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ui.sh"               "$LIBDIR/ui.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/shell-warn.sh"       "$LIBDIR/shell-warn.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh" "$LIBDIR/setup-container-backend.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/migrate-denies.sh"   "$LIBDIR/migrate-denies.sh"
sudo cp "$SCRIPT_DIR/config.sh"                        "$LIBDIR/config.sh"
sudo cp "$SCRIPT_DIR/update.sh"                        "$LIBDIR/update.sh"
sudo cp "$SCRIPT_DIR/status.sh"                        "$LIBDIR/status.sh"
# sudoers.template is deployed alongside config.sh: the installed config.sh
# re-renders /etc/opencode-permissions-kit/sudoers on container-backend
# switches and needs the template next to it.
sudo cp "$SCRIPT_DIR/sudoers.template"                 "$LIBDIR/sudoers.template"
sudo chmod 440 "$LIBDIR/sudoers.template"
sudo cp "$SCRIPT_DIR/opencode.jsonc"                   "$LIBDIR/opencode.jsonc"
sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc"          "$LIBDIR/opencode-deny-all.jsonc"
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
# rootless socket probe helper
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/socket-check.sh" "$LIBDIR/bin/socket-check.sh"
# ddev always runs as the opencode user: the sourced shell function (hooked
# into the developer's rc files) + the sudoers helper that execs the real ddev.
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-as-opencode.sh" "$LIBDIR/ddev-as-opencode.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/ddev-as-opencode" "$LIBDIR/bin/ddev-as-opencode"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" "$LIBDIR/ddev-handover.sh"
sudo chmod 644 "$LIBDIR/ddev-as-opencode.sh" "$LIBDIR/ddev-handover.sh"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/kit" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/log.sh" "$LIBDIR/ui.sh" "$LIBDIR/shell-warn.sh" "$LIBDIR/setup-container-backend.sh" \
               "$LIBDIR/migrate-denies.sh" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/bin/socket-check.sh" "$LIBDIR/bin/ddev-as-opencode"
log "library deployed to $LIBDIR"
ui_success "kit library deployed: $LIBDIR"

# Symlink: /usr/local/bin/opencode -> our wrapper
sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
ui_success "wrapper installed: /usr/local/bin/opencode -> $LIBDIR/wrapper"
log "wrapper symlink: /usr/local/bin/opencode -> $LIBDIR/wrapper"

# CLI dispatcher: /usr/local/bin/opencode-permissions-kit -> kit
sudo ln -sf "$LIBDIR/kit" /usr/local/bin/opencode-permissions-kit
ui_success "cli installed: opencode-permissions-kit -> $LIBDIR/kit"
log "cli symlink: /usr/local/bin/opencode-permissions-kit -> $LIBDIR/kit"

# Remove a legacy ddev delegation shim (pre-DDEV-WORKING installs shadowed
# /usr/local/bin/ddev). Only ever touch a symlink pointing at OUR library —
# never a real ddev binary.
if [ -L /usr/local/bin/ddev ] \
   && readlink /usr/local/bin/ddev 2>/dev/null | grep -Eq 'lib/opencode(-permissions-kit)?/bin/ddev'; then
    sudo rm -f /usr/local/bin/ddev
    echo "Legacy ddev delegation shim removed (/usr/local/bin/ddev) — ddev now runs natively as $OPENCODE_USER."
    log "legacy ddev shim removed: /usr/local/bin/ddev"
fi

# sudoers -> /etc/opencode-permissions-kit/sudoers, symlinked as /etc/sudoers.d/opencode-permissions-kit
SUDO_TMP=$(mktemp)
sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
sudo cp "$SUDO_TMP" /etc/opencode-permissions-kit/sudoers
sudo chmod 440 /etc/opencode-permissions-kit/sudoers
rm -f "$SUDO_TMP"
sudo ln -sf /etc/opencode-permissions-kit/sudoers /etc/sudoers.d/opencode-permissions-kit

if sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1; then
    ui_success "sudoers installed + validated (/etc/sudoers.d/opencode-permissions-kit)"
    log "sudoers installed: /etc/opencode-permissions-kit/sudoers -> /etc/sudoers.d/opencode-permissions-kit"
else
    ui_error "sudoers validation failed. Check /etc/opencode-permissions-kit/sudoers."
    exit 1
fi

# === Step 7b: .git/config hardening (optional, SOFT-only) ===

# Advanced mode asks here (Standard already asked in its question section;
# --secure-git-config decided via flag). --yes runs skip everything.
GIT_ASKED=false
if [ "$GIT_FLAG_GIVEN" != true ] && [ "$INTERACTIVE" = true ] && [ "$MODE" = "advanced" ]; then
    ans=$(prompt "Block .git/config for opencode? (SOFT-only: opencode tools respect it, bash-spawned reads are not OS-blocked)" "Y" "N" "")
    case "$ans" in
        y) SECURE_GIT_CONFIG=true ;;
        *) SECURE_GIT_CONFIG=false ;;
    esac
    GIT_ASKED=true
fi
if [ "$SECURE_GIT_CONFIG" = true ]; then
    ui_info "git for the agent: BLOCKED (.git/config deny active, soft-only — enforced by opencode's permission layer, not the OS)"
fi

# === Step 8: opencode Home ===

sudo mkdir -p /home/opencode/.config/opencode /home/opencode/.agents
# The opencode home belongs to the user's own usergroup; the developer (member
# of $OPENCODE_GROUP) can enter and edit opencode.jsonc etc.
sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode
sudo chmod 2750 /home/opencode
sudo chown -R "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config /home/opencode/.agents
sudo chmod 2775 /home/opencode/.config /home/opencode/.config/opencode /home/opencode/.agents

if [ ! -f /home/opencode/.config/opencode/opencode.jsonc ] && [ ! -f /home/opencode/.config/opencode/opencode.json ]; then
    sudo cp "$SCRIPT_DIR/opencode.jsonc" /home/opencode/.config/opencode/opencode.jsonc
    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config/opencode/opencode.jsonc
    sudo chmod 664 /home/opencode/.config/opencode/opencode.jsonc
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        sudo sed -i 's|//SECURE_GIT: ||' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc) — .git/config blocked (soft)."
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc)."
    fi
    log "opencode config installed: /home/opencode/.config/opencode/opencode.jsonc (secure_git=$SECURE_GIT_CONFIG)"
elif [ -f /home/opencode/.config/opencode/opencode.jsonc ] && ! grep -q '"permission"' /home/opencode/.config/opencode/opencode.jsonc; then
    sudo cp /home/opencode/.config/opencode/opencode.jsonc "$BACKUP_DIR/opencode.jsonc-existing" 2>/dev/null || true
    sudo cp "$SCRIPT_DIR/opencode.jsonc" /home/opencode/.config/opencode/opencode.jsonc
    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config/opencode/opencode.jsonc
    sudo chmod 664 /home/opencode/.config/opencode/opencode.jsonc
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        sudo sed -i 's|//SECURE_GIT: ||' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc) — .git/config blocked (soft). Backup saved."
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' /home/opencode/.config/opencode/opencode.jsonc
        echo "Default config installed (opencode.jsonc — backup saved)."
    fi
    log "opencode config replaced (backup: $BACKUP_DIR/opencode.jsonc-existing)"
elif [ -f /home/opencode/.config/opencode/opencode.json ] && [ ! -f /home/opencode/.config/opencode/opencode.jsonc ]; then
    ui_detail "opencode.json exists — left untouched (custom user config)"
    log "opencode config kept: custom opencode.json (not overwritten)"
else
    # Kit-managed opencode.jsonc already exists (re-install). The git choice
    # above must not be silently ignored: re-render from the template with
    # the chosen SECURE_GIT state — same semantics as `config.sh git-config
    # on|off` — with a backup of the previous file.
    sudo cp /home/opencode/.config/opencode/opencode.jsonc "$BACKUP_DIR/opencode.jsonc-existing" 2>/dev/null || true
    sudo cp "$SCRIPT_DIR/opencode.jsonc" /home/opencode/.config/opencode/opencode.jsonc
    sudo chown "$OPENCODE_USER:$OPENCODE_GROUP" /home/opencode/.config/opencode/opencode.jsonc
    sudo chmod 664 /home/opencode/.config/opencode/opencode.jsonc
    if [ "$SECURE_GIT_CONFIG" = true ]; then
        sudo sed -i 's|//SECURE_GIT: ||' /home/opencode/.config/opencode/opencode.jsonc
        ui_success "agent config re-applied — .git/config blocked (soft, backup saved)"
    else
        sudo sed -i '/\/\/SECURE_GIT:/d' /home/opencode/.config/opencode/opencode.jsonc
        ui_success "agent config re-applied — git allowed (backup saved)"
    fi
    log "opencode config re-rendered with the chosen git setting (secure_git=$SECURE_GIT_CONFIG, backup: $BACKUP_DIR/opencode.jsonc-existing)"
fi

# === Step 8b: Default-user config (self-update bypass protection) ===

# opencode's self-updater / installer can re-add ~/.opencode/bin to PATH, so
# 'opencode' would run the real binary as $DEFAULT_USER — bypassing the
# wrapper and the 'opencode' user. Deploy a deny-* config for the default
# user so that mode is completely locked down.
DEFAULT_OC_DIR="/home/$DEFAULT_USER/.config/opencode"
DEFAULT_OC_CONF="$DEFAULT_OC_DIR/opencode.jsonc"
sudo mkdir -p "$DEFAULT_OC_DIR"
if [ -f "$DEFAULT_OC_CONF" ]; then
    ans=$(prompt "Default-user config $DEFAULT_OC_CONF already exists. Back it up as opencode.jsonc_BAK_<timestamp> and install the deny-all config?" "Y" "N" "")
    if [ "$ans" = "y" ]; then
        BAK_STAMP=$(date +%Y%m%d-%H%M%S)
        sudo mv "$DEFAULT_OC_CONF" "$DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
        ui_success "default-user config backed up: $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
        log "default-user config backed up: $DEFAULT_OC_DIR/opencode.jsonc_BAK_$BAK_STAMP"
    else
        ui_warn "existing default-user config kept — deny-all protection NOT installed"
    fi
fi
if [ ! -f "$DEFAULT_OC_CONF" ]; then
    sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
    sudo chown "$DEFAULT_USER:$OPENCODE_GROUP" "$DEFAULT_OC_CONF"
    sudo chmod 664 "$DEFAULT_OC_CONF"
    ui_success "deny-all config installed for default user: $DEFAULT_OC_CONF"
    log "deny-all config installed for default user: $DEFAULT_OC_CONF"
fi

# === Step 9: Remove legacy layouts & artifacts ===
# Pre-0.0.10 layout (/usr/local/lib/opencode, /etc/opencode) plus the
# pre-DDEV-WORKING artifacts (hooks dir, ddev shim, transaction helper,
# rewrite list, sbin symlink). Fresh installs are a no-op.
sudo rm -rf /usr/local/lib/opencode 2>/dev/null || true
sudo rm -rf /etc/opencode 2>/dev/null || true
sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
sudo rm -rf "$LIBDIR/hooks" 2>/dev/null || true
sudo rm -f "$LIBDIR/ddev-transaction.sh" "$LIBDIR/protect-projects.sh" "$LIBDIR/bin/ddev" 2>/dev/null || true
sudo rm -f /usr/local/sbin/protect-projects.sh 2>/dev/null || true
sudo rm -f /etc/opencode-permissions-kit/ddev-rewrites.conf 2>/dev/null || true
sudo rm -rf /run/opencode-permissions-kit 2>/dev/null || true
# Legacy installs pointed core.hooksPath at our (now removed) hooks dir —
# unset it for both users so git stops warning.
sudo -u "$OPENCODE_USER" git config --global --unset core.hooksPath 2>/dev/null || true
sudo -u "$DEFAULT_USER" git config --global --unset core.hooksPath 2>/dev/null || true
# A legacy www-data-based install left files in the old sharing group; the
# group baseline step already re-applied $OPENCODE_GROUP. Record the model switch.
sudo grep -q '^HARD_DENY_REMOVED=' /etc/opencode-permissions-kit/install.conf 2>/dev/null || \
    echo "HARD_DENY_REMOVED=1" | sudo tee -a /etc/opencode-permissions-kit/install.conf > /dev/null
log "legacy layouts/artifacts removed (if present); soft-only model active"

# === Done ===

ui_section "Installation complete"
ui_kv "Kit"      "v$VERSION"
ui_kv "Backend"  "$CONTAINER_BACKEND (owned by 'opencode')"
[ -n "$PROJECTS_ROOTS" ] && ui_kv "Projects" "$PROJECTS_ROOTS"
if [ "$SECURE_GIT_CONFIG" = true ]; then
    ui_kv "Git"   "blocked for the agent (.git/config deny active)"
else
    ui_kv "Git"   "allowed"
fi
ui_kv "Backup"   "$BACKUP_DIR"
echo ""
# WSL2 final exposure warning: the wsl.conf restriction only takes effect
# after 'wsl --shutdown' — until then /mnt/c stays world-readable and the
# wrapper warns on every opencode start. Covers both "declined" and
# "configured but pending".
if [ -d /mnt/c ]; then
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
        echo "  ${UI_YELLOW}WARNING: /mnt/c is still world-readable (mode $mnt_mode) — the agent${UI_NC}"
        echo "  ${UI_YELLOW}can read your Windows profile. If the wsl.conf restriction was just${UI_NC}"
        echo "  ${UI_YELLOW}configured, it needs 'wsl --shutdown' from Windows + reopening the distro${UI_NC}"
        echo "  ${UI_YELLOW}to take effect. opencode will warn on every start until then.${UI_NC}"
        echo ""
    fi
fi
# A shell that already ran 'opencode' has the old user-local binary hashed
# (and ~/.opencode/bin still first in its $PATH — the rc cleanup above only
# affects NEW shells). A child process cannot fix the parent shell, so tell
# the user to restart the terminal.
if [ -x "/home/$DEFAULT_USER/.opencode/bin/opencode" ]; then
    echo "  ${UI_YELLOW}IMPORTANT:${UI_NC} open a NEW terminal before running 'opencode'."
    echo "  Your current shell still resolves the old, unwrapped binary from"
    echo "  ~/.opencode/bin (bash caches the path, and it is still first in \$PATH"
    echo "  of this shell). Until you restart, 'opencode' would bypass the wrapper"
    echo "  and the 'opencode' user."
    echo ""
fi
echo ""
ui_info "Next:"
ui_detail "opencode                       start the agent (new terminal!)"
ui_detail "opencode-permissions-kit status   verify the protection"
ui_detail "opencode-permissions-kit config   change settings later (or update/uninstall)"
ui_detail "Docs:  https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/README.md"
log "install complete"
