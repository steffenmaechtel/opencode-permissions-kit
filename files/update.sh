#!/bin/sh
# opencode permissions kit -- update.sh
# Re-deploys the KIT (wrapper, jsonc-parser, sudoers template, umask profile,
# uninstall.sh, config.sh, status.sh, log.sh, migrate-denies.sh) onto a system
# that has already been installed via install.sh. Does NOT touch:
#   - existing /etc/opencode-permissions-kit/projects.conf
#   - existing /etc/opencode-permissions-kit/install.conf (except the
#     VERSION stamp, the WWW_GROUP re-base to the opencode usergroup, and
#     removal of the dead DDEV_BIN/DDEV_MODE keys)
#   - existing /home/opencode/.config/opencode/opencode.json[c]
#   - the DEFAULT user's existing opencode config (a deny-all config is only
#     deployed when that user has no opencode.jsonc yet)
#   - the opencode binary at /usr/local/lib/opencode-permissions-kit/bin/opencode — UNLESS
#     --binary is given (fetch the latest release and install it) or
#     --binary-path <file> (install the given binary without downloading).
#
# One-time hard-deny migration (DDEV-WORKING §4): on the first update from a
# pre-soft-only install this removes every u:opencode:--- ACL deny from the
# project roots, re-bases the sharing group to the opencode usergroup, and
# removes the legacy hooks/shim/transaction artifacts. Gated by the
# HARD_DENY_REMOVED stamp in install.conf. A legacy docker-group install
# ABORTS with instructions (rootless is mandatory now).
#
# One-liner (fetches the new update.sh + all kit files at $KIT_BRANCH):
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH/files/update.sh | sudo bash
#
# From a checkout (uses the local files):
#   sudo bash files/update.sh --yes            # skip prompts
#   sudo bash files/update.sh --refresh        # also re-apply the group baseline at the end
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
opencode-permissions-kit-lib/wrapper opencode-permissions-kit-lib/jsonc-parser.py \
opencode-permissions-kit-lib/log.sh opencode-permissions-kit-lib/shell-warn.sh opencode-permissions-kit-lib/setup-container-backend.sh opencode-permissions-kit-lib/bin/socket-check.sh opencode-permissions-kit-lib/migrate-denies.sh opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode opencode-permissions-kit-lib/ddev-handover.sh"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` or run from the installed library
# (which only holds the previously deployed, possibly older, files).
fetch_kit() {
    local base dir f
    base="$(mktemp -d)"
    dir="$base/files"
    mkdir -p "$dir/opencode-permissions-kit-lib/bin"
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
# initial fetch with a smaller file list (e.g. migrate-denies.sh was added
# later), then re-exec'd this freshly fetched copy — the temp dir is incomplete
# but $SCRIPT_DIR/../VERSION exists, so the VERSION guard above does not
# re-fetch. For a real local checkout every file is present and this is a no-op.
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
CONFDIR="/etc/opencode-permissions-kit"
PROJECTS_CONF="$CONFDIR/projects.conf"

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
INSTALL_CONF="$CONFDIR/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="$CONFDIR/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"

DEFAULT_USER=""
OPENCODE_USER="opencode"
WWW_GROUP="opencode"
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
  --refresh        also re-apply the group baseline (chgrp/setgid/default ACLs)
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

# The new sharing group: the opencode user's primary usergroup.
NEW_WWW_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"

if ! confirm "Re-deploy kit files (existing configs will NOT be touched)?"; then
    echo "Aborted."; exit 0
fi

# --- re-deploy library files --------------------------------------------------

echo ""
echo "--- Re-deploying library files ---"
sudo mkdir -p "$LIBDIR/bin"

sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh"              "$LIBDIR/log.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/shell-warn.sh"       "$LIBDIR/shell-warn.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh" "$LIBDIR/setup-container-backend.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/migrate-denies.sh"   "$LIBDIR/migrate-denies.sh"
sudo cp "$SCRIPT_DIR/config.sh"                        "$LIBDIR/config.sh"
sudo cp "$SCRIPT_DIR/update.sh"                        "$LIBDIR/update.sh"
sudo cp "$SCRIPT_DIR/status.sh"                        "$LIBDIR/status.sh"
# sudoers.template: needed by the installed config.sh for backend switches
# (render_sudoers looks in $LIBDIR first).
sudo cp "$SCRIPT_DIR/sudoers.template"                 "$LIBDIR/sudoers.template"
sudo chmod 440 "$LIBDIR/sudoers.template"
sudo cp "$SCRIPT_DIR/opencode.jsonc"                   "$LIBDIR/opencode.jsonc"
sudo cp "$SCRIPT_DIR/uninstall.sh"                     "$LIBDIR/uninstall.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/socket-check.sh" "$LIBDIR/bin/socket-check.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-as-opencode.sh" "$LIBDIR/ddev-as-opencode.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/ddev-as-opencode" "$LIBDIR/bin/ddev-as-opencode"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" "$LIBDIR/ddev-handover.sh"
sudo chmod 644 "$LIBDIR/ddev-as-opencode.sh" "$LIBDIR/ddev-handover.sh"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/log.sh" "$LIBDIR/shell-warn.sh" "$LIBDIR/setup-container-backend.sh" \
               "$LIBDIR/migrate-denies.sh" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/bin/socket-check.sh" "$LIBDIR/bin/ddev-as-opencode"
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

# --- re-link wrapper ----------------------------------------------------------

sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
echo "Symlink refreshed: /usr/local/bin/opencode"

# --- re-deploy sudoers -------------------------------------------------------

# Ensure the new config dir exists (fresh install or migration from pre-0.0.10).
sudo mkdir -p "$CONFDIR"
# Migrate projects.conf from the pre-0.0.10 /etc/opencode/ layout if the new
# copy is missing — update.sh must never drop registered project roots.
if [ ! -f "$PROJECTS_CONF" ] && [ -f /etc/opencode/projects.conf ]; then
    sudo cp /etc/opencode/projects.conf "$PROJECTS_CONF"
    echo "Migrated projects.conf -> $CONFDIR/"
    log "migrated projects.conf: /etc/opencode -> /etc/opencode-permissions-kit"
fi

if [ -f "$SCRIPT_DIR/sudoers.template" ]; then
    SUDO_TMP=$(mktemp)
    sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" "$SCRIPT_DIR/sudoers.template" > "$SUDO_TMP"
    sudo cp "$SUDO_TMP" "$CONFDIR/sudoers"
    sudo chmod 440 "$CONFDIR/sudoers"
    rm -f "$SUDO_TMP"
    sudo ln -sf "$CONFDIR/sudoers" /etc/sudoers.d/opencode-permissions-kit
    # Remove the pre-0.0.10 sudoers symlink so only the new name is active.
    sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
    if sudo /usr/sbin/visudo -c -f "$CONFDIR/sudoers" >/dev/null 2>&1; then
        echo "sudoers updated (DEFAULT_USER=$DEFAULT_USER)."
        log "sudoers re-deployed (DEFAULT_USER=$DEFAULT_USER)"
    else
        echo "${RED}sudoers validation failed. Check $CONFDIR/sudoers.${NC}"
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
        # ddev always runs as the opencode user: hook the `ddev()` shell
        # function (sudoers helper). Only the DEFAULT user — the opencode
        # session must never be wrapped (the function's id check is the guard).
        if ! sudo grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh ] && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh  # opencode permissions kit (ddev always runs as opencode)' | sudo tee -a "$cf" > /dev/null
            echo "ddev-as-opencode function hooked into $cf"
            log "ddev-as-opencode hook appended: $cf"
        fi
    done
fi

# --- .ddev + settings-dir handover (ddev always runs as the opencode user) -----
# ddev chmods .ddev and the app-type's settings directories unconditionally,
# and chmod is owner-only — they must belong to the opencode user or
# `ddev start` fails with "operation not permitted". Searched at ANY depth
# under each registered root (a root is often a parent of several projects).
# Unconditional (not just inside the migration) so installs that already
# migrated — the common upgrade path — are healed too. The mode-700 .git
# dir stays dev-owned.
if [ -f "$PROJECTS_CONF" ] && [ -n "$NEW_WWW_GROUP" ]; then
    # Shared helper: prefer the copy next to this script (checkout — same
    # vintage as the running update.sh), fall back to the deployed library.
    [ -f "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" ] && . "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh"
    [ -f "$LIBDIR/ddev-handover.sh" ] && . "$LIBDIR/ddev-handover.sh"
    command -v ddev_handover_root >/dev/null 2>&1 || ddev_handover_root() { :; }
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || continue
        ddev_handover_root "$root" "$OPENCODE_USER" "$NEW_WWW_GROUP"
        log "ddev handover applied under $root"
    done < "$PROJECTS_CONF"
fi

# --- WSL2 /mnt/c restriction (report-only — update.sh stays prompt-free) -------
# The drvfs mount runs with the Windows session token; NTFS ACLs do not
# distinguish WSL users, so a world-readable /mnt/c exposes the whole
# Windows profile to every WSL user incl. the agent's. Hint when open,
# remind about the pending 'wsl --shutdown' when the restriction is
# configured but not applied yet.
if [ -d /mnt/c ]; then
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
        if grep -q '^options *=.*dmask' /etc/wsl.conf 2>/dev/null; then
            echo "  NOTE: /mnt/c restriction configured in /etc/wsl.conf — pending 'wsl --shutdown' (Windows)."
        else
            echo "  NOTE: /mnt/c is world-readable (mode $mnt_mode) — every WSL user incl. the agent"
            echo "        can read the Windows profile. Recommended fix in /etc/wsl.conf:"
            echo "          [automount]"
            echo "          enabled = true"
            echo "          options = \"uid=$(id -u "$DEFAULT_USER" 2>/dev/null || echo '<uid>'),gid=$(id -g "$DEFAULT_USER" 2>/dev/null || echo '<gid>'),dmask=027,fmask=037\""
            echo "        then 'wsl --shutdown' from Windows. install.sh can apply this for you (interactive)."
        fi
    fi
fi

# --- one-time hard-deny migration (DDEV-WORKING §4) ---------------------------

if ! grep -q '^HARD_DENY_REMOVED=1' "$INSTALL_CONF" 2>/dev/null; then
    echo ""
    echo "--- One-time migration: remove hard ACL denies + legacy artifacts ---"
    if sudo sh "$LIBDIR/migrate-denies.sh" \
            --projects "$PROJECTS_CONF" \
            --conf-dir "$CONFDIR" \
            --lib-dir "$LIBDIR" \
            --opencode-user "$OPENCODE_USER" \
            --group "$NEW_WWW_GROUP"; then
        # Legacy git hooks pointed at the (now removed) hooks dir.
        sudo -u "$OPENCODE_USER" git config --global --unset core.hooksPath 2>/dev/null || true
        sudo -u "$DEFAULT_USER" git config --global --unset core.hooksPath 2>/dev/null || true
        # Legacy ddev delegation shim: only ever remove OUR symlink.
        if [ -L /usr/local/bin/ddev ] \
           && readlink /usr/local/bin/ddev 2>/dev/null | grep -Eq 'lib/opencode(-permissions-kit)?/bin/ddev'; then
            sudo rm -f /usr/local/bin/ddev
            echo "Legacy ddev delegation shim removed (/usr/local/bin/ddev) — ddev now runs natively as $OPENCODE_USER."
            log "legacy ddev shim removed: /usr/local/bin/ddev"
        fi
        # Group membership for the developer (fresh login needed to pick it up).
        sudo usermod -aG "$NEW_WWW_GROUP" "$DEFAULT_USER" 2>/dev/null || true
        echo "  developer '$DEFAULT_USER' added to group '$NEW_WWW_GROUP' (start a new login shell to pick it up)"

        # ddev runtime for the opencode user (idempotent, prompt-free).
        sudo mkdir -p "/home/$OPENCODE_USER/.ddev"
        sudo chown "$OPENCODE_USER:$NEW_WWW_GROUP" "/home/$OPENCODE_USER/.ddev"
        sudo chmod 755 "/home/$OPENCODE_USER/.ddev"
        caroot="/home/$OPENCODE_USER/.local/share/mkcert"
        if [ ! -f "$caroot/rootCA.pem" ]; then
            sudo mkdir -p "$caroot"
            src=""
            # 1. Windows CA: scan the user profiles directly (powershell.exe /
            #    cmd.exe are often not on a WSL PATH — probing %USERNAME% is
            #    unreliable; same fix as install.sh).
            if [ -d /mnt/c/Users ]; then
                for wca in /mnt/c/Users/*/AppData/Local/mkcert; do
                    if [ -f "$wca/rootCA.pem" ] && [ -f "$wca/rootCA-key.pem" ]; then
                        src="$wca"
                        break
                    fi
                done
            fi
            # 2. Developer's Linux CAROOT.
            if [ -z "$src" ] && [ -n "$DEFAULT_USER" ] && [ -f "/home/$DEFAULT_USER/.local/share/mkcert/rootCA.pem" ]; then
                src="/home/$DEFAULT_USER/.local/share/mkcert"
            fi
            if [ -n "$src" ]; then
                sudo cp "$src/rootCA.pem" "$src/rootCA-key.pem" "$caroot/" 2>/dev/null || true
                sudo chown -R "$OPENCODE_USER:$NEW_WWW_GROUP" "$caroot" 2>/dev/null || true
                sudo chmod 700 "$caroot" 2>/dev/null || true
                sudo chmod 600 "$caroot/rootCA-key.pem" 2>/dev/null || true
                echo "  mkcert CA reused from $src -> $caroot"
                log "migration: mkcert CA reused for $OPENCODE_USER"
            fi
        fi
        # Router ports: apply live only when the kit's sysctl file already
        # exists (update.sh must stay prompt-free); otherwise hint.
        if [ -f /etc/sysctl.d/99-ddev-rootless.conf ]; then
            sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 >/dev/null 2>&1 || true
        else
            echo "  NOTE: rootless ddev-router needs low ports — either run:"
            echo "    sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
            echo "    echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-ddev-rootless.conf"
            echo "  or use higher router ports (ddev config global --router-http-port 8080)."
        fi
        log "hard-deny migration complete (DDEV-WORKING)"
    else
        rc=$?
        if [ "$rc" = 3 ]; then
            die "This install still uses the removed docker-group backend. Re-run install.sh with a rootless backend:
  sudo bash files/install.sh --container-backend docker-rootless
  sudo bash files/install.sh --container-backend podman-rootless"
        fi
        die "Migration failed (exit $rc). Fix the issue above and re-run."
    fi
fi

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
# The home belongs to the opencode user's own usergroup; older installs had it
# in www-data with mode 750. Apply the current ownership/mode.
if [ -d "/home/$OPENCODE_USER" ]; then
    sudo chown "$OPENCODE_USER:$NEW_WWW_GROUP" "/home/$OPENCODE_USER"
    sudo chmod 2750 "/home/$OPENCODE_USER"
    echo "/home/$OPENCODE_USER is accessible for group $NEW_WWW_GROUP."
fi

# --- ensure default-user deny-all config (self-update bypass protection) ------
# Older installs predate this config. Deploy it only if the default user has
# no config yet — update.sh must not silently clobber an existing one.
if [ -n "$DEFAULT_USER" ] && [ -d "/home/$DEFAULT_USER" ]; then
    DEFAULT_OC_CONF="/home/$DEFAULT_USER/.config/opencode/opencode.jsonc"
    if [ ! -f "$DEFAULT_OC_CONF" ]; then
        sudo mkdir -p "$(dirname "$DEFAULT_OC_CONF")"
        sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
        sudo chown "$DEFAULT_USER:$NEW_WWW_GROUP" "$DEFAULT_OC_CONF"
        sudo chmod 664 "$DEFAULT_OC_CONF"
        echo "Deny-all config installed for default user: $DEFAULT_OC_CONF"
        log "deny-all config installed for default user: $DEFAULT_OC_CONF"
    else
        echo "Default-user config exists — left untouched (re-run install.sh to back it up)."
    fi
fi

# --- refresh install.conf (version stamp + model keys) ------------------------

NEW_INSTALL_CONF="$(mktemp)"
{
    if [ -f "$INSTALL_CONF" ]; then
        # Strip keys this update owns: VERSION (re-stamped), the dead
        # DDEV_BIN/DDEV_MODE keys (shim + modes are gone), and WWW_GROUP
        # (re-based to the opencode usergroup).
        grep -v -e '^VERSION=' -e '^DDEV_BIN=' -e '^DDEV_MODE=' -e '^WWW_GROUP=' -e '^HARD_DENY_REMOVED=' "$INSTALL_CONF" 2>/dev/null
    fi
    echo "WWW_GROUP=$NEW_WWW_GROUP"
    echo "HARD_DENY_REMOVED=1"
    echo "VERSION=$VERSION"
} | sort -u > "$NEW_INSTALL_CONF"
sudo cp "$NEW_INSTALL_CONF" "$CONFDIR/install.conf"
sudo chmod 644 "$CONFDIR/install.conf"
rm -f "$NEW_INSTALL_CONF"
# Cleanup legacy setup.conf (pre-v0.0.9) in both new and old config dirs.
[ -f "$CONFDIR/setup.conf" ] && sudo rm -f "$CONFDIR/setup.conf"
[ -f /etc/opencode/setup.conf ] && sudo rm -f /etc/opencode/setup.conf
echo "install.conf updated: VERSION=$VERSION WWW_GROUP=$NEW_WWW_GROUP"
log "install.conf updated: VERSION=$VERSION WWW_GROUP=$NEW_WWW_GROUP HARD_DENY_REMOVED=1"

# --- remove pre-0.0.10 legacy layout -----------------------------------------
# The new library / config dir / symlinks are all in place now; tear down the
# old /usr/local/lib/opencode and /etc/opencode so only the renamed layout
# remains. Idempotent and safe (no-op on a fresh 0.0.10+ install).
sudo rm -rf /usr/local/lib/opencode 2>/dev/null || true
sudo rm -rf /etc/opencode 2>/dev/null || true
sudo rm -f /etc/sudoers.d/opencode 2>/dev/null || true
sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
log "legacy pre-0.0.10 layout removed (if present)"

# --- optional group-baseline refresh ------------------------------------------

if [ "$REFRESH" = true ]; then
    echo ""
    echo "--- Refreshing group baseline ---"
    sudo sh "$LIBDIR/migrate-denies.sh" \
        --projects "$PROJECTS_CONF" \
        --conf-dir "$CONFDIR" \
        --lib-dir "$LIBDIR" \
        --opencode-user "$OPENCODE_USER" \
        --group "$NEW_WWW_GROUP"
    log "group baseline refresh requested (--refresh)"
else
    echo ""
    echo "Skipped group-baseline refresh (use --refresh to re-apply chgrp/setgid/default ACLs)."
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
