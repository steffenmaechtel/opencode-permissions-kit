#!/bin/sh
# opencode permissions kit -- update.sh
# Re-deploys the KIT (wrapper, hooks, protect-projects.sh, jsonc-parser,
# sudoers template, umask profile, uninstall.sh, config.sh, status.sh, log.sh)
# onto a system that has already been installed via install.sh. Does NOT touch:
#   - existing /etc/opencode-permissions-kit/projects.conf
#   - existing /etc/opencode-permissions-kit/install.conf (DEFAULT_USER / OPENCODE_USER)
#   - existing /home/opencode/.config/opencode/opencode.json[c]
#   - any ACLs
#   (except: normalizes the /home/opencode ownership/mode so the default user
#   can edit opencode.jsonc — see the "opencode home" step below)
#   - the DEFAULT user's existing opencode config (a deny-all config is only
#   deployed when that user has no opencode.jsonc yet)
#   - the opencode binary at /usr/local/lib/opencode-permissions-kit/bin/opencode — UNLESS
#   --binary is given (fetch the latest release and install it) or
#   --binary-path <file> (install the given binary without downloading).
#
# One-liner (fetches the new update.sh + all kit files at $KIT_BRANCH):
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH/files/update.sh | sudo bash
#
# From a checkout (uses the local files):
#   sudo bash files/update.sh --yes            # skip prompts
#   sudo bash files/update.sh --refresh        # also re-run protect-projects.sh --force at the end
#   sudo bash files/update.sh --binary         # also upgrade opencode to the latest release
#
# `opencode upgrade` cannot work behind the wrapper (the binary is root-owned
# and opencode runs as an unprivileged user), so this script is the upgrade
# entry point. Binary upgrades are best-effort: a download/verify failure warns
# and leaves the current binary in place — the kit update still completes.
#
# Use install.sh for the very first setup (it asks the questions).
# Use config.sh to change project roots or git-config hardening.
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Branch the kit ships from (master = always latest). Overridable for
# testing: KIT_BRANCH=my-branch  KIT_BASE_URL=https://example.invalid/<branch>
KIT_BRANCH="${KIT_BRANCH:-master}"
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Canonical kit file list. Single source of truth shared by fetch_kit() and
# the pre-deploy verification (ensure_local_file), so the two can never drift
# and a stale installed update.sh fetching an incomplete temp dir is healed
# before the deploy cp's run.
KIT_FILES="install.sh config.sh update.sh uninstall.sh status.sh opencode.jsonc \
opencode-deny-all.jsonc \
sudoers.template umask.sh VERSION \
opencode-permissions-kit-lib/wrapper opencode-permissions-kit-lib/protect-projects.sh opencode-permissions-kit-lib/jsonc-parser.py \
opencode-permissions-kit-lib/log.sh opencode-permissions-kit-lib/shell-warn.sh opencode-permissions-kit-lib/setup-container-backend.sh opencode-permissions-kit-lib/bin/ddev \
opencode-permissions-kit-lib/hooks/post-checkout opencode-permissions-kit-lib/hooks/post-merge opencode-permissions-kit-lib/hooks/post-commit"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` or run from the installed library
# (which only holds the previously deployed, possibly older, files).
fetch_kit() {
    local base dir f
    base="$(mktemp -d)"
    dir="$base/files"
    mkdir -p "$dir/opencode-permissions-kit-lib/hooks" "$dir/opencode-permissions-kit-lib/bin"
    for f in $KIT_FILES; do
        echo "  fetching $f ..." >&2
        if [ "$f" = "VERSION" ]; then
            curl -fsSL "$KIT_BASE_URL/VERSION" -o "$base/VERSION" || return 1
        else
            curl -fsSL "$KIT_BASE_URL/files/$f" -o "$dir/$f" || return 1
        fi
    done
    echo "$dir"
}

# Re-fetch any single kit file that is missing under $SCRIPT_DIR (best-effort).
# Handles the transition case where an OLDER installed update.sh performed the
# initial fetch with a smaller file list (e.g. shell-warn.sh was added later),
# then re-exec'd this freshly fetched copy — the temp dir is incomplete but
# $SCRIPT_DIR/../VERSION exists, so the VERSION guard above does not re-fetch.
# For a real local checkout every file is present and this is a no-op.
ensure_local_file() {
    local f="$1"
    [ -f "$SCRIPT_DIR/$f" ] && return 0
    mkdir -p "$(dirname "$SCRIPT_DIR/$f")"
    echo "  re-fetching missing $f ..." >&2
    curl -fsSL "$KIT_BASE_URL/files/$f" -o "$SCRIPT_DIR/$f" 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
if [ ! -f "$SCRIPT_DIR/../VERSION" ]; then
    echo "No local checkout — fetching kit files from $KIT_BASE_URL ..."
    SCRIPT_DIR="$(fetch_kit)" || { echo "${RED}Failed to fetch kit files from $KIT_BASE_URL${NC}" >&2; exit 1; }
    # Do NOT continue executing this (installed, possibly older) copy: the
    # deploy below overwrites $LIBDIR/update.sh with the freshly fetched one,
    # which would replace the very file we are still running from. bash reads
    # a script incrementally, so a self-modifying script corrupts its parser
    # mid-run ("syntax error near unexpected token '('"). Re-exec the fetched
    # copy instead — its own overwrite of $LIBDIR/update.sh is then harmless.
    exec bash "$SCRIPT_DIR/update.sh" "$@"
fi
# Heal an incomplete fetched temp dir (see ensure_local_file above) before we
# touch any of the files. No-op for a real local checkout.
for f in $KIT_FILES; do
    [ "$f" = "VERSION" ] && continue
    ensure_local_file "$f"
done
VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0.0.0")
LIBDIR="/usr/local/lib/opencode-permissions-kit"

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Covers all
# three run modes: repo checkout, streamed temp dir, installed library.
log() { :; }
for cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh" "$SCRIPT_DIR/log.sh" "$LIBDIR/log.sh"; do
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
# Save the version from the VERSION file (read above) before sourcing
# install.conf, which also has a VERSION= line (the old stamp). We don't
# want install.conf to overwrite the freshly-read VERSION from the repo.
KIT_VERSION="$VERSION"
if [ -f "$INSTALL_CONF" ]; then
    . "$INSTALL_CONF"
fi
VERSION="$KIT_VERSION"
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
WWW_GROUP="${WWW_GROUP:-www-data}"

# DDEV_BIN: real ddev path for the delegation shim. Preserve the value
# recorded in install.conf; only detect (skipping our own shim symlink) when
# migrating an install that predates the feature.
if [ -z "$DDEV_BIN" ]; then
    DDEV_BIN="$(command -v ddev 2>/dev/null || true)"
    if [ -n "$DDEV_BIN" ] && [ -L "$DDEV_BIN" ] \
       && readlink "$DDEV_BIN" 2>/dev/null | grep -Eq 'lib/opencode(-permissions-kit)?/bin/ddev'; then
        DDEV_BIN="/usr/bin/ddev"
    fi
    [ -n "$DDEV_BIN" ] || DDEV_BIN="/usr/bin/ddev"
fi

YES=false
REFRESH=false
BINARY_UPDATE=false
BINARY_PATH=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y) YES=true ;;
        --refresh) REFRESH=true ;;
        --binary) BINARY_UPDATE=true ;;
        --binary-path)
            [ "$#" -ge 2 ] || { echo "error: --binary-path requires a file path" >&2; exit 1; }
            BINARY_UPDATE=true
            BINARY_PATH="$2"
            shift
            ;;
        -h|--help)
            cat <<EOF
opencode permissions kit -- update.sh  v$VERSION
Re-deploys the kit on an already-installed system. No prompts by default.
Usage: ./update.sh [--yes] [--refresh] [--binary] [--binary-path <file>]
  --yes            skip the confirmation prompt
  --refresh        also re-run protect-projects.sh --force at the end
  --binary         also upgrade the opencode binary to the latest release
  --binary-path    install the given binary file instead of downloading
EOF
            exit 0
            ;;
        *) echo "error: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
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
log "update started (version $VERSION, refresh=$REFRESH)"

if [ ! -f "$INSTALL_CONF" ]; then
    die "Not installed yet. Run install.sh first."
fi

if ! id "$OPENCODE_USER" >/dev/null 2>&1; then
    die "User '$OPENCODE_USER' missing. Run install.sh first."
fi

if ! confirm "Re-deploy kit files (existing configs will NOT be touched)?"; then
    echo "Aborted."; exit 0
fi

# --- re-deploy library files --------------------------------------------------

echo ""
echo "--- Re-deploying library files ---"
sudo mkdir -p "$LIBDIR/hooks"

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
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
# ddev delegation shim
sudo mkdir -p "$LIBDIR/bin"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/ddev"            "$LIBDIR/bin/ddev"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/protect-projects.sh" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/log.sh" "$LIBDIR/shell-warn.sh" "$LIBDIR/setup-container-backend.sh" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/hooks/post-checkout" "$LIBDIR/hooks/post-merge" "$LIBDIR/hooks/post-commit" \
               "$LIBDIR/bin/ddev"
echo "Library files updated: $LIBDIR"
log "library re-deployed: $LIBDIR"

# --- migrate opencode binary from pre-0.0.10 layout --------------------------
# Pre-0.0.10 installs kept the binary at /usr/local/lib/opencode/bin/opencode.
# Move it into the new library so a normal update (no --binary) preserves it.
if [ -d /usr/local/lib/opencode ] && [ ! -x "$LIBDIR/bin/opencode" ] && [ -x /usr/local/lib/opencode/bin/opencode ]; then
    sudo mkdir -p "$LIBDIR/bin"
    sudo mv /usr/local/lib/opencode/bin/opencode "$LIBDIR/bin/opencode"
    sudo chown "root:$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")" "$LIBDIR/bin/opencode" 2>/dev/null || true
    sudo chmod 750 "$LIBDIR/bin/opencode"
    echo "Migrated opencode binary -> $LIBDIR/bin/opencode"
    log "migrated opencode binary: /usr/local/lib/opencode/bin/opencode -> $LIBDIR/bin/opencode"
fi

# --- re-link wrapper + protect-projects --------------------------------------

sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
sudo ln -sf "$LIBDIR/protect-projects.sh" /usr/local/sbin/protect-projects.sh
echo "Symlinks refreshed: /usr/local/bin/opencode, /usr/local/sbin/protect-projects.sh"

# --- re-link ddev shim -------------------------------------------------------
# Shadow /usr/local/bin/ddev with our delegating shim, but never clobber a real
# ddev installed there — in that layout the real binary wins on PATH and
# delegation is unavailable (documented limitation).
if [ -e /usr/local/bin/ddev ] && [ ! -L /usr/local/bin/ddev ]; then
    echo "  ${YELLOW}/usr/local/bin/ddev is a real ddev (not the kit shim) — delegation NOT shadowed.${NC}"
    log "ddev shim NOT shadowed: /usr/local/bin/ddev occupied"
else
    sudo ln -sf "$LIBDIR/bin/ddev" /usr/local/bin/ddev
    echo "ddev shim refreshed: /usr/local/bin/ddev -> $LIBDIR/bin/ddev (delegates to $DDEV_BIN as $DEFAULT_USER)"
    log "ddev shim re-linked: /usr/local/bin/ddev -> $LIBDIR/bin/ddev (DDEV_BIN=$DDEV_BIN)"
fi

# --- re-deploy sudoers -------------------------------------------------------

# Ensure the new config dir exists (fresh install or migration from pre-0.0.10).
sudo mkdir -p /etc/opencode-permissions-kit
# Migrate projects.conf from the pre-0.0.10 /etc/opencode/ layout if the new
# copy is missing — update.sh must never drop registered project roots.
if [ ! -f /etc/opencode-permissions-kit/projects.conf ] && [ -f /etc/opencode/projects.conf ]; then
    sudo cp /etc/opencode/projects.conf /etc/opencode-permissions-kit/projects.conf
    echo "Migrated projects.conf -> /etc/opencode-permissions-kit/"
    log "migrated projects.conf: /etc/opencode -> /etc/opencode-permissions-kit"
fi

if [ -f "$SCRIPT_DIR/sudoers.template" ]; then
    SUDO_TMP=$(mktemp)
    sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" -e "s#DDEV_BIN#$DDEV_BIN#g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
    # The (opencode:docker) RunAs grant is only needed for the docker-group
    # backend. For the rootless backends strip that block; empty/unknown
    # defaults to docker-group (matching the wrapper's normalization) so the
    # grant stays available. CONTAINER_BACKEND is read from install.conf above
    # (preserved across the update — never re-provisioned here).
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
    # Remove the pre-0.0.10 sudoers symlink so only the new name is active.
    sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
    if sudo /usr/sbin/visudo -c -f /etc/opencode-permissions-kit/sudoers >/dev/null 2>&1; then
        echo "sudoers updated (DEFAULT_USER=$DEFAULT_USER)."
        log "sudoers re-deployed (DEFAULT_USER=$DEFAULT_USER)"
    else
        echo "${RED}sudoers validation failed. Check /etc/opencode-permissions-kit/sudoers.${NC}"
        exit 1
    fi
fi

# --- re-deploy umask profile -------------------------------------------------

if [ -f "$SCRIPT_DIR/umask.sh" ]; then
    sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
    sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
    # Remove the pre-0.0.10 umask profile so only the new name is loaded.
    sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
    echo "umask profile updated."
    log "umask profile re-deployed: /etc/profile.d/opencode-permissions-kit-umask.sh"
fi

# --- ensure shell-startup wrapper-bypass warning -------------------------------
# Older installs lack the interactive-shell hook. Append it idempotently so a
# self-installed opencode binary is reported in non-login shells too. The
# [ -f ... ] guard keeps the line harmless after uninstall. Never removes user
# lines — the warning tells the user how to clean up a real reinstall.
if [ -n "$DEFAULT_USER" ] && [ -d "/home/$DEFAULT_USER" ]; then
    for cf in "/home/$DEFAULT_USER/.bashrc" "/home/$DEFAULT_USER/.zshrc" "/home/$DEFAULT_USER/.profile"; do
        [ -f "$cf" ] || continue
        if ! sudo grep -q 'opencode-permissions-kit/shell-warn.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/shell-warn.sh ] && . /usr/local/lib/opencode-permissions-kit/shell-warn.sh  # opencode permissions kit (wrapper bypass warning)' | sudo tee -a "$cf" > /dev/null
            echo "Wrapper-bypass warning hooked into $cf"
            log "shell-startup warning hook appended: $cf"
        fi
    done
fi

# --- re-apply git hooks path (in case user wiped it) ------------------------

sudo -u "$OPENCODE_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
sudo -u "$DEFAULT_USER" git config --global core.hooksPath "$LIBDIR/hooks" 2>/dev/null || true
echo "core.hooksPath confirmed ($LIBDIR/hooks)."

# --- opencode binary upgrade (--binary / --binary-path) ----------------------

SYSTEM_BIN="/usr/local/lib/opencode-permissions-kit/bin/opencode"

# --- re-assert opencode binary permissions ------------------------------------
# The binary must stay executable only for root and the opencode user, so a
# tool invoking the absolute path as the default user cannot bypass the wrapper.
BINARY_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"
if [ -x "$SYSTEM_BIN" ]; then
    sudo chown "root:$BINARY_GROUP" "$SYSTEM_BIN" 2>/dev/null || true
    sudo chmod 750 "$SYSTEM_BIN" 2>/dev/null || true
fi

# Detect the release asset name for this host (mirrors the official installer).
detect_asset() {
    local os arch target
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        darwin*) os="darwin" ;;
        linux*) os="linux" ;;
        *) return 1 ;;
    esac
    arch=$(uname -m)
    if [ "$arch" = "aarch64" ]; then arch="arm64"; fi
    if [ "$arch" = "x86_64" ]; then arch="x64"; fi
    target="$os-$arch"
    if [ "$arch" = "x64" ] && [ "$os" = "linux" ] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
        target="$target-baseline"
    fi
    if [ "$os" = "linux" ] && { [ -f /etc/alpine-release ] || { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; }; then
        target="$target-musl"
    fi
    echo "opencode-$target.tar.gz"
}

# Verify a candidate binary actually runs, then install it over $SYSTEM_BIN.
install_binary() {
    local src="$1" current new
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 "$src" --version >/dev/null 2>&1 || return 1
    else
        "$src" --version >/dev/null 2>&1 || return 1
    fi
    current=$("$SYSTEM_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    sudo cp "$src" "$SYSTEM_BIN" || return 1
    sudo chown "root:$BINARY_GROUP" "$SYSTEM_BIN" 2>/dev/null || true
    sudo chmod 750 "$SYSTEM_BIN" || return 1
    new=$("$SYSTEM_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    echo "  opencode binary upgraded: ${current} -> ${new}"
    log "opencode binary upgraded: ${current} -> ${new}"
}

if [ "$BINARY_UPDATE" = true ]; then
    echo ""
    echo "--- Upgrading opencode binary ---"
    SRC=""
    if [ -n "$BINARY_PATH" ]; then
        if [ -x "$BINARY_PATH" ]; then
            SRC="$BINARY_PATH"
        else
            echo "  ${YELLOW}Binary path not found or not executable: $BINARY_PATH${NC}"
            echo "  Binary left untouched."
            log "opencode binary upgrade skipped: --binary-path not executable"
        fi
    else
        VER=$(curl -fsSL --max-time 10 https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null \
            | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
        if [ -z "$VER" ]; then
            echo "  ${YELLOW}Could not resolve latest opencode version (network?). Binary left untouched.${NC}"
            log "opencode binary upgrade skipped: cannot resolve latest version"
        else
            TMP="$(mktemp -d)"
            asset=$(detect_asset || true)
            if [ -n "$asset" ] \
                && curl -fsSL --max-time 120 "https://github.com/anomalyco/opencode/releases/download/v$VER/$asset" \
                    -o "$TMP/opencode.tar.gz" \
                && tar -xzf "$TMP/opencode.tar.gz" -C "$TMP" \
                && [ -x "$TMP/opencode" ]; then
                SRC="$TMP/opencode"
            else
                echo "  ${YELLOW}Download of opencode $VER failed. Binary left untouched.${NC}"
                log "opencode binary upgrade skipped: download failed (v$VER)"
            fi
            rm -rf "$TMP"
        fi
    fi
    if [ -n "$SRC" ]; then
        BACKUP_DIR="$(mktemp -d /tmp/opencode-upgrade-backup.XXXXXX)"
        if [ -x "$SYSTEM_BIN" ]; then
            sudo cp "$SYSTEM_BIN" "$BACKUP_DIR/opencode.current"
        fi
        if install_binary "$SRC"; then
            echo "  Backup kept in $BACKUP_DIR (remove once you are satisfied)."
        else
            echo "  ${YELLOW}Candidate binary failed verification/install. Binary left untouched.${NC}"
            log "opencode binary upgrade skipped: candidate failed verification/install"
            rm -rf "$BACKUP_DIR"
        fi
    fi
else
    echo "  opencode binary left untouched (use --binary to upgrade)."
fi

# --- ensure default user can access the opencode home -------------------------
# useradd -m leaves the home owned by a private group; older installs only
# chmod'd it to 750, so the default user (member of $WWW_GROUP) could not even
# cd into it. Apply the same ownership/mode install.sh uses.
if [ -d "/home/$OPENCODE_USER" ]; then
    sudo chown "$OPENCODE_USER:$WWW_GROUP" "/home/$OPENCODE_USER"
    sudo chmod 2750 "/home/$OPENCODE_USER"
    echo "/home/$OPENCODE_USER is accessible for group $WWW_GROUP."
fi

# --- ensure default-user deny-all config (self-update bypass protection) ------
# Older installs predate this config. Deploy it only if the default user has
# no config yet — update.sh must not silently clobber an existing one.
if [ -n "$DEFAULT_USER" ] && [ -d "/home/$DEFAULT_USER" ]; then
    DEFAULT_OC_CONF="/home/$DEFAULT_USER/.config/opencode/opencode.jsonc"
    if [ ! -f "$DEFAULT_OC_CONF" ]; then
        sudo mkdir -p "$(dirname "$DEFAULT_OC_CONF")"
        sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
        sudo chown "$DEFAULT_USER:$WWW_GROUP" "$DEFAULT_OC_CONF"
        sudo chmod 664 "$DEFAULT_OC_CONF"
        echo "Deny-all config installed for default user: $DEFAULT_OC_CONF"
        log "deny-all config installed for default user: $DEFAULT_OC_CONF"
    else
        echo "Default-user config exists — left untouched (re-run install.sh to back it up)."
    fi
fi

# --- refresh install.conf version stamp --------------------------------------

NEW_INSTALL_CONF="$(mktemp)"
{
    if [ -f "$INSTALL_CONF" ]; then
        grep -v -e '^VERSION=' -e '^DDEV_BIN=' "$INSTALL_CONF" 2>/dev/null
    fi
    echo "DDEV_BIN=$DDEV_BIN"
    echo "VERSION=$VERSION"
} | sort -u > "$NEW_INSTALL_CONF"
sudo cp "$NEW_INSTALL_CONF" /etc/opencode-permissions-kit/install.conf
sudo chmod 644 /etc/opencode-permissions-kit/install.conf
rm -f "$NEW_INSTALL_CONF"
# Cleanup legacy setup.conf (pre-v0.0.9) in both new and old config dirs.
[ -f /etc/opencode-permissions-kit/setup.conf ] && sudo rm -f /etc/opencode-permissions-kit/setup.conf
[ -f /etc/opencode/setup.conf ] && sudo rm -f /etc/opencode/setup.conf
echo "install.conf updated: VERSION=$VERSION"
log "install.conf version stamp updated: VERSION=$VERSION"

# --- remove pre-0.0.10 legacy layout -----------------------------------------
# The new library / config dir / symlinks are all in place now; tear down the
# old /usr/local/lib/opencode and /etc/opencode so only the renamed layout
# remains. Idempotent and safe (no-op on a fresh 0.0.10+ install).
sudo rm -rf /usr/local/lib/opencode 2>/dev/null || true
sudo rm -rf /etc/opencode 2>/dev/null || true
sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
log "legacy pre-0.0.10 layout removed (if present)"

# --- optional ACL refresh ----------------------------------------------------

if [ "$REFRESH" = true ]; then
    echo ""
    echo "--- Refreshing ACL protection ---"
    sudo "$LIBDIR/protect-projects.sh" --force
    log "ACL refresh requested (--refresh)"
else
    echo ""
    echo "Skipped ACL refresh (use --refresh to re-apply protects)."
fi

# --- done --------------------------------------------------------------------

echo ""
echo "  ${GREEN}Update complete.${NC}  v$VERSION"
if [ "$BINARY_UPDATE" = true ]; then
    echo "  projects.conf and opencode.jsonc were left untouched."
else
    echo "  Binary, projects.conf and opencode.jsonc were left untouched."
fi
echo ""
log "update complete (version $VERSION)"