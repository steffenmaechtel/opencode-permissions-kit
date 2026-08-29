#!/bin/sh
# opencode permissions kit -- update.sh
# Re-deploys the KIT (wrapper, kit cli, jsonc-parser, sudoers template,
# umask profile, uninstall.sh, config.sh, status.sh, log.sh) onto a system
# that has already been installed via install.sh. Does NOT touch:
#   - existing /etc/opencode-permissions-kit/projects.conf
#   - existing /etc/opencode-permissions-kit/install.conf (except the
#     VERSION stamp and the OPENCODE_GROUP re-base)
#   - existing /home/opencode/.config/opencode/opencode.json[c]
#   - the DEFAULT user's existing opencode config (a deny-all config is only
#     deployed when that user has no opencode.jsonc yet)
#   - the opencode binary at /usr/local/lib/opencode-permissions-kit/bin/opencode — UNLESS
#     --binary is given (fetch the latest release and install it) or
#     --binary-path <file> (install the given binary without downloading).
#
# Supported upgrade floor: the installed kit must be >= 0.0.14. Older
# installs abort with instructions (re-run install.sh).
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

# Branch the kit ships from (master = always latest). Overridable for
# testing: KIT_BRANCH=my-branch  KIT_BASE_URL=https://example.invalid/<branch>
KIT_BRANCH="${KIT_BRANCH:-master}"
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Canonical kit file list. Single source of truth shared by fetch_kit() and
# the pre-deploy verification (ensure_local_file), so the two can never drift
# and a stale installed update.sh fetching an incomplete temp dir is healed
# before the deploy cp's run.
# REMOVED kit files must keep a compatibility stub under files/ while any
# update.sh within the upgrade floor still lists them (a 404 aborts the old
# fetch before the new update.sh takes over) — see
# opencode-permissions-kit-lib/migrate-denies.sh.
KIT_FILES="install.sh config.sh update.sh uninstall.sh status.sh opencode.jsonc \
opencode-deny-all.jsonc \
sudoers.template umask.sh VERSION \
opencode-permissions-kit-lib/wrapper opencode-permissions-kit-lib/kit opencode-permissions-kit-lib/jsonc-parser.py \
opencode-permissions-kit-lib/log.sh opencode-permissions-kit-lib/ui.sh opencode-permissions-kit-lib/shell-warn.sh opencode-permissions-kit-lib/setup-container-backend.sh opencode-permissions-kit-lib/bin/socket-check.sh opencode-permissions-kit-lib/bin/cwd-check.sh opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode opencode-permissions-kit-lib/ddev-handover.sh opencode-permissions-kit-lib/ddev-migrate.sh opencode-permissions-kit-lib/ddev-hosts.sh opencode-permissions-kit-lib/fs-baseline.sh \
opencode-permissions-kit-lib/tui/kit-mode.tsx opencode-permissions-kit-lib/tui/opencode-danger.theme.json opencode-permissions-kit-lib/tui/tui.json opencode-permissions-kit-lib/tui/tui-danger.json"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` or run from the installed library
# (which only holds the previously deployed, possibly older, files).
fetch_kit() {
    local base dir f
    base="$(mktemp -d)"
    dir="$base/files"
    # Pre-create every subdirectory referenced by KIT_FILES (bin/, tui/):
    # curl -o cannot write into a missing directory and aborts the fetch
    # with error 23 ("Failure writing output to destination").
    mkdir -p "$dir/opencode-permissions-kit-lib/bin" "$dir/opencode-permissions-kit-lib/tui"
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
# Heals an incomplete temp-fetch when an older installed update.sh re-exec'd
# this freshly fetched copy with a smaller file list. For a real local
# checkout every file is present and this is a no-op.
ensure_local_file() {
    local f="$1"
    [ -f "$SCRIPT_DIR/$f" ] && return 0
    mkdir -p "$(dirname "$SCRIPT_DIR/$f")"
    echo "  re-fetching missing $f ..." >&2
    curl -fsSL "$KIT_BASE_URL/files/$f" -o "$SCRIPT_DIR/$f" 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# Binary-only modes (--only-binary / --binary-path) need NO kit files at
# all — when running from the installed library, skip the self-fetch
# (and the per-file heal loop below, which would re-fetch the whole kit
# for the flat LIBDIR layout). The flags must work while the installed
# update.sh IS the current one; an older installed copy rejects them as
# unknown options (run one regular update first).
_opk_binonly=false
for _opk_a in "$@"; do
    case "$_opk_a" in
        --only-binary|--binary-path) _opk_binonly=true; break ;;
    esac
done
if [ "$_opk_binonly" != true ] && [ ! -f "$SCRIPT_DIR/../VERSION" ]; then
    echo "No local checkout — fetching kit files from $KIT_BASE_URL ..."
    SCRIPT_DIR="$(fetch_kit)" || { echo "error  Failed to fetch kit files from $KIT_BASE_URL" >&2; exit 1; }
    # Do NOT continue executing this (installed, possibly older) copy: the
    # deploy below overwrites $LIBDIR/update.sh with the freshly fetched one,
    # which would replace the very file we are still running from. bash reads
    # a script incrementally, so a self-modifying script corrupts its parser
    # mid-run ("syntax error near unexpected token '('"). Re-exec the fetched
    # copy instead — its own overwrite of $LIBDIR/update.sh is then harmless.
    exec bash "$SCRIPT_DIR/update.sh" "$@"
fi
# Heal an incomplete fetched temp dir (see ensure_local_file above) before we
# touch any of the files. No-op for a real local checkout; skipped entirely
# for binary-only runs from the installed library.
if [ "$_opk_binonly" != true ]; then
    for f in $KIT_FILES; do
        [ "$f" = "VERSION" ] && continue
        ensure_local_file "$f"
    done
fi
# Library runs have no ../VERSION — fall back to the installed stamp so the
# banner/summary show the real version (binary-only runs never re-stamp it).
VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null \
    || sed -n 's/^VERSION=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1 \
    || echo "0.0.0")
LIBDIR="/usr/local/lib/opencode-permissions-kit"
CONFDIR="/etc/opencode-permissions-kit"
PROJECTS_CONF="$CONFDIR/projects.conf"

# === Shared UI helpers ===
# Checkout copy first, then the deployed library; a plain fallback keeps
# update.sh working on an install whose library predates ui.sh.
UI_LIB=""
for _cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/ui.sh" "$LIBDIR/ui.sh"; do
    if [ -f "$_cand" ]; then UI_LIB="$_cand"; break; fi
done
if [ -n "$UI_LIB" ]; then
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

# install.conf (upgrade floor 0.0.14: the canonical path always exists)
INSTALL_CONF="$CONFDIR/install.conf"

DEFAULT_USER=""
OPENCODE_USER="opencode"
OPENCODE_GROUP=""
INSTALLED_VERSION=""
# Save the version from the VERSION file (read above) before sourcing
# install.conf, which also has a VERSION= line (the old stamp). We don't
# want install.conf to overwrite the freshly-read VERSION from the repo.
KIT_VERSION="$VERSION"
if [ -f "$INSTALL_CONF" ]; then
    INSTALLED_VERSION=$(sed -n 's/^VERSION=//p' "$INSTALL_CONF" | tail -1)
    . "$INSTALL_CONF"
fi
VERSION="$KIT_VERSION"
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"

# --- upgrade floor: >= 0.0.14 -------------------------------------------------
# Updates are only supported from 0.0.14 onwards (all older migrations were
# removed). Compare numerically: major*1000000 + minor*1000 + patch.
floor_check() {
    _fv="${1%%-*}" _av="${2%%-*}"
    _f1=${_fv%%.*}; _rest=${_fv#*.}; _f2=${_rest%%.*}; _f3=${_rest#*.}
    _a1=${_av%%.*}; _rest=${_av#*.}; _a2=${_rest%%.*}; _a3=${_rest#*.}
    _f1=${_f1:-0}; _f2=${_f2:-0}; _f3=${_f3:-0}
    _a1=${_a1:-0}; _a2=${_a2:-0}; _a3=${_a3:-0}
    [ $((_a1 * 1000000 + _a2 * 1000 + _a3)) -ge $((_f1 * 1000000 + _f2 * 1000 + _f3)) ]
}
if [ -f "$INSTALL_CONF" ]; then
    if [ -z "$INSTALLED_VERSION" ] || ! floor_check "0.0.14" "$INSTALLED_VERSION"; then
        ui_error "Unsupported upgrade path: installed kit version is '${INSTALLED_VERSION:-unknown}'."
        echo ""
        echo "  Updates are only supported from kit 0.0.14 onwards (older"
        echo "  migrations have been removed). Re-run install.sh instead:"
        echo "    curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash"
        echo ""
        exit 1
    fi
fi

YES=false
REFRESH=false
BINARY_UPDATE=false
ONLY_BINARY=false
BINARY_PATH=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y) YES=true ;;
        --refresh) REFRESH=true ;;
        --binary) BINARY_UPDATE=true ;;
        --only-binary)
            # issue #24: skip every kit step, only upgrade the binary
            ONLY_BINARY=true
            BINARY_UPDATE=true
            ;;
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
Usage: ./update.sh [--yes] [--refresh] [--binary] [--only-binary] [--binary-path <file>]
  --yes            skip the confirmation prompt
  --refresh        also re-apply the group baseline (chgrp/setgid/default ACLs)
  --binary         also upgrade the opencode binary to the latest release
  --only-binary    skip every kit step, ONLY upgrade the opencode binary
  --binary-path    install the given binary file instead of downloading
EOF
            exit 0
            ;;
        *) echo "error: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

banner() {
    ui_banner "$VERSION" "update — re-deploys the kit, keeps your configuration"
}

die() { ui_error "$*"; exit 1; }

confirm() {
    # Convention: docs/design/conventions.md — [Y/n] default capital,
    # Enter accepts it, y/yes/n/no case-insensitive.
    [ "$YES" = true ] && return 0
    ui_confirm "$1" "y"
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
NEW_OPENCODE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"

if [ "$ONLY_BINARY" = true ]; then
    _uc_msg="Only upgrade the opencode binary (kit files untouched)?"
else
    _uc_msg="Re-deploy kit files (existing configs will NOT be touched)?"
fi
if ! confirm "$_uc_msg"; then
    echo "Aborted."; exit 0
fi

if [ "$ONLY_BINARY" != true ]; then

# --- re-deploy library files (skipped by --only-binary) ------------------------

ui_section "Re-deploying library files"
sudo mkdir -p "$LIBDIR/bin"

sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/wrapper"            "$LIBDIR/wrapper"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/kit"                "$LIBDIR/kit"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/jsonc-parser.py"     "$LIBDIR/jsonc-parser.py"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/log.sh"              "$LIBDIR/log.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ui.sh"               "$LIBDIR/ui.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/shell-warn.sh"       "$LIBDIR/shell-warn.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/setup-container-backend.sh" "$LIBDIR/setup-container-backend.sh"
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
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/cwd-check.sh" "$LIBDIR/bin/cwd-check.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-as-opencode.sh" "$LIBDIR/ddev-as-opencode.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/bin/ddev-as-opencode" "$LIBDIR/bin/ddev-as-opencode"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" "$LIBDIR/ddev-handover.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-migrate.sh" "$LIBDIR/ddev-migrate.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/fs-baseline.sh" "$LIBDIR/fs-baseline.sh"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-hosts.sh" "$LIBDIR/ddev-hosts.sh"
# TUI mode display (docs/_archive/design/plan-ui-tui-opencode.md): plugin + templates.
sudo mkdir -p "$LIBDIR/tui"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/kit-mode.tsx" "$LIBDIR/tui/kit-mode.tsx"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/opencode-danger.theme.json" "$LIBDIR/tui/opencode-danger.theme.json"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/tui.json" "$LIBDIR/tui/tui.json"
sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/tui-danger.json" "$LIBDIR/tui/tui-danger.json"
sudo chmod 644 "$LIBDIR/ddev-as-opencode.sh" "$LIBDIR/ddev-handover.sh" "$LIBDIR/ddev-migrate.sh" "$LIBDIR/ddev-hosts.sh" "$LIBDIR/fs-baseline.sh"
sudo chmod 644 "$LIBDIR/tui/kit-mode.tsx" "$LIBDIR/tui/opencode-danger.theme.json" "$LIBDIR/tui/tui.json" "$LIBDIR/tui/tui-danger.json"
sudo chmod 755 "$LIBDIR/wrapper" "$LIBDIR/kit" "$LIBDIR/jsonc-parser.py" \
               "$LIBDIR/log.sh" "$LIBDIR/ui.sh" "$LIBDIR/shell-warn.sh" "$LIBDIR/setup-container-backend.sh" \
               "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
               "$LIBDIR/bin/socket-check.sh" "$LIBDIR/bin/cwd-check.sh" "$LIBDIR/bin/ddev-as-opencode"
ui_success "library re-deployed: $LIBDIR"
log "library re-deployed: $LIBDIR"

# --- re-link wrapper + cli dispatcher ------------------------------------------

sudo ln -sf "$LIBDIR/wrapper" /usr/local/bin/opencode
ui_success "wrapper symlink refreshed: /usr/local/bin/opencode"
sudo rm -f /usr/local/bin/opencode-permissions-kit
sudo ln -sf "$LIBDIR/kit" /usr/local/bin/opk
ui_success "cli symlink refreshed: /usr/local/bin/opk (legacy name removed)"

# --- re-deploy sudoers -------------------------------------------------------

sudo mkdir -p "$CONFDIR"

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
        ui_success "sudoers re-deployed (DEFAULT_USER=$DEFAULT_USER)"
        log "sudoers re-deployed (DEFAULT_USER=$DEFAULT_USER)"
    else
        die "sudoers validation failed. Check $CONFDIR/sudoers."
    fi
fi

# --- re-deploy umask profile -------------------------------------------------

if [ -f "$SCRIPT_DIR/umask.sh" ]; then
    sudo cp "$SCRIPT_DIR/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
    sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
    # Remove the pre-0.0.10 umask profile so only the new name is loaded.
    sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
    ui_success "umask profile re-deployed"
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
            ui_success "wrapper-bypass warning hooked into $cf"
            log "shell-startup warning hook appended: $cf"
        fi
        # ddev always runs as the opencode user: hook the `ddev()` shell
        # function (sudoers helper). Only the DEFAULT user — the opencode
        # session must never be wrapped (the function's id check is the guard).
        if ! sudo grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' "$cf" 2>/dev/null; then
            echo '[ -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh ] && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh  # opencode permissions kit (ddev always runs as opencode)' | sudo tee -a "$cf" > /dev/null
            ui_success "ddev-as-opencode function hooked into $cf"
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
# migrated — the common upgrade path — are healed too. .git dirs are
# never chowned — they stay developer-owned (the group baseline makes
# them group-accessible).
if [ -f "$PROJECTS_CONF" ] && [ -n "$NEW_OPENCODE_GROUP" ]; then
    # Shared helper: prefer the copy next to this script (checkout — same
    # vintage as the running update.sh), fall back to the deployed library.
    [ -f "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh" ] && . "$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-handover.sh"
    [ -f "$LIBDIR/ddev-handover.sh" ] && . "$LIBDIR/ddev-handover.sh"
    command -v ddev_handover_root >/dev/null 2>&1 || ddev_handover_root() { :; }
    ui_detail "scanning project roots for ddev directories (large trees: this can take a while) ..."
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || continue
        ddev_handover_root "$root" "$OPENCODE_USER" "$NEW_OPENCODE_GROUP" "$DEFAULT_USER"
        log "ddev handover applied under $root"
    done < "$PROJECTS_CONF"
fi

# git "dubious ownership" exception for the opencode user (issue #17) —
# every registered project root is developer-owned, the agent's git needs
# safe.directory to run there. Unconditional so existing installs get it
# on the first update; the get guard keeps it idempotent.
if command -v git >/dev/null 2>&1; then
    if ! sudo -u "$OPENCODE_USER" -H git config --global --get-all safe.directory 2>/dev/null | grep -qFx '*'; then
        sudo -u "$OPENCODE_USER" -H git config --global --add safe.directory '*' \
            && ui_success "git safe.directory '*' set for $OPENCODE_USER (agent git access)"
    fi
    log "git safe.directory ensured for $OPENCODE_USER"
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
            echo "  ${UI_YELLOW}WARNING: /mnt/c restriction configured but still pending 'wsl --shutdown' (Windows)${UI_NC}"
            echo "  ${UI_YELLOW}— the mount stays world-readable (mode $mnt_mode) and opencode warns on${UI_NC}"
            echo "  ${UI_YELLOW}every start until the distro is reopened.${UI_NC}"
        else
            echo "  ${UI_YELLOW}WARNING: /mnt/c is world-readable (mode $mnt_mode) — every WSL user incl. the agent${UI_NC}"
            echo "  ${UI_YELLOW}can read the Windows profile. opencode warns on every start until fixed.${UI_NC}"
            echo "  ${UI_YELLOW}Recommended fix in /etc/wsl.conf:${UI_NC}"
            echo "    [automount]"
            echo "    enabled = true"
            echo "    options = \"uid=$(id -u "$DEFAULT_USER" 2>/dev/null || echo '<uid>'),gid=$(id -g "$DEFAULT_USER" 2>/dev/null || echo '<gid>'),dmask=027,fmask=037\""
            echo "  ${UI_YELLOW}then 'wsl --shutdown' from Windows. install.sh can apply this for you (interactive).${UI_NC}"
        fi
    fi
fi

fi   # ONLY_BINARY skip: kit re-deploy ... pre-binary sections

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

# Download + extract the latest opencode release into <dir>. Prints the
# candidate binary path on success, nothing on failure. The CALLER owns
# <dir> — cleanup happens only after the install attempt (the old flow
# deleted the extracted candidate before verification could run: every
# downloaded upgrade failed with "candidate failed verification",
# issue #24).
fetch_latest_opencode() {
    _flo_dst="${1:-}"
    [ -n "$_flo_dst" ] && [ -d "$_flo_dst" ] || return 1
    _flo_ver=$(curl -fsSL --max-time 10 https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
    [ -n "$_flo_ver" ] || return 1
    _flo_asset=$(detect_asset || true)
    [ -n "$_flo_asset" ] || return 1
    curl -fsSL --max-time 120 "https://github.com/anomalyco/opencode/releases/download/v$_flo_ver/$_flo_asset" \
        -o "$_flo_dst/opencode.tar.gz" || return 1
    tar -xzf "$_flo_dst/opencode.tar.gz" -C "$_flo_dst" || return 1
    [ -x "$_flo_dst/opencode" ] || return 1
    echo "$_flo_dst/opencode"
    return 0
}

if [ "$BINARY_UPDATE" = true ]; then
    ui_section "Upgrading opencode binary"
    SRC=""
    TMP=""
    if [ -n "$BINARY_PATH" ]; then
        if [ -x "$BINARY_PATH" ]; then
            SRC="$BINARY_PATH"
        else
            ui_warn "binary path not found or not executable: $BINARY_PATH — left untouched"
            log "opencode binary upgrade skipped: --binary-path not executable"
        fi
    else
        TMP="$(mktemp -d)"
        if SRC=$(fetch_latest_opencode "$TMP"); then
            :   # candidate extracted; TMP stays alive until after the install
        else
            ui_warn "download of the latest opencode release failed — binary left untouched"
            log "opencode binary upgrade skipped: download failed"
            rm -rf "$TMP"
            TMP=""
        fi
    fi
    if [ -n "$SRC" ]; then
        BACKUP_DIR="$(mktemp -d /tmp/opencode-upgrade-backup.XXXXXX)"
        if [ -x "$SYSTEM_BIN" ]; then
            sudo cp "$SYSTEM_BIN" "$BACKUP_DIR/opencode.current"
        fi
        if install_binary "$SRC"; then
            ui_detail "backup kept in $BACKUP_DIR (remove once you are satisfied)"
        else
            ui_warn "candidate binary failed verification/install — binary left untouched"
            log "opencode binary upgrade skipped: candidate failed verification/install"
            rm -rf "$BACKUP_DIR"
        fi
        # Candidate dir cleanup AFTER the install attempt — never before
        # verification (issue #24).
        [ -n "$TMP" ] && rm -rf "$TMP"
    fi
else
    ui_detail "opencode binary left untouched (use --binary to upgrade)"
fi

if [ "$ONLY_BINARY" != true ]; then

# --- ensure default user can access the opencode home -------------------------
# The home belongs to the opencode user's own usergroup; older installs had it
# in www-data with mode 750. Apply the current ownership/mode.
if [ -d "/home/$OPENCODE_USER" ]; then
    sudo chown "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "/home/$OPENCODE_USER"
    sudo chmod 2750 "/home/$OPENCODE_USER"
    ui_success "/home/$OPENCODE_USER re-based to group $NEW_OPENCODE_GROUP (mode 2750)"
fi

# --- ensure default-user deny-all config (self-update bypass protection) ------
# Older installs predate this config. Deploy it only if the default user has
# no config yet — update.sh must not silently clobber an existing one.
if [ -n "$DEFAULT_USER" ] && [ -d "/home/$DEFAULT_USER" ]; then
    DEFAULT_OC_CONF="/home/$DEFAULT_USER/.config/opencode/opencode.jsonc"
    if [ ! -f "$DEFAULT_OC_CONF" ]; then
        sudo mkdir -p "$(dirname "$DEFAULT_OC_CONF")"
        sudo cp "$SCRIPT_DIR/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
        sudo chown "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_OC_CONF"
        sudo chmod 664 "$DEFAULT_OC_CONF"
        ui_success "deny-all config installed for default user: $DEFAULT_OC_CONF"
        log "deny-all config installed for default user: $DEFAULT_OC_CONF"
    else
        ui_detail "default-user config exists — left untouched (re-run install.sh to back it up)"
    fi
fi

# --- refresh install.conf (version stamp + group key) --------------------------

NEW_INSTALL_CONF="$(mktemp)"
{
    if [ -f "$INSTALL_CONF" ]; then
        # Strip keys this update owns: VERSION (re-stamped) and
        # OPENCODE_GROUP (re-based to the opencode usergroup).
        grep -v -e '^VERSION=' -e '^OPENCODE_GROUP=' "$INSTALL_CONF" 2>/dev/null
    fi
    echo "OPENCODE_GROUP=$NEW_OPENCODE_GROUP"
    echo "VERSION=$VERSION"
} | sort -u > "$NEW_INSTALL_CONF"
sudo cp "$NEW_INSTALL_CONF" "$CONFDIR/install.conf"
sudo chmod 644 "$CONFDIR/install.conf"
rm -f "$NEW_INSTALL_CONF"
ui_success "install.conf updated: VERSION=$VERSION OPENCODE_GROUP=$NEW_OPENCODE_GROUP"
log "install.conf updated: VERSION=$VERSION OPENCODE_GROUP=$NEW_OPENCODE_GROUP"

# --- TUI mode display user files (docs/_archive/design/plan-ui-tui-opencode.md) ---------
# Same only-if-absent-or-kit-written policy as install.sh (marker key
# _opencode_permissions_kit): user edits survive updates.
OC_TUI_DIR="/home/$OPENCODE_USER/.config/opencode"
OC_TUI_CONF="$OC_TUI_DIR/tui.json"
sudo mkdir -p "$OC_TUI_DIR"
if [ ! -f "$OC_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$OC_TUI_CONF" 2>/dev/null; then
    sudo cp "$LIBDIR/tui/tui.json" "$OC_TUI_CONF"
    sudo chown "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "$OC_TUI_CONF"
    sudo chmod 664 "$OC_TUI_CONF"
    log "tui mode display refreshed: $OC_TUI_CONF"
fi
DEFAULT_TUI_CONF="/home/$DEFAULT_USER/.config/opencode/tui.json"
DEFAULT_THEME_DIR="/home/$DEFAULT_USER/.config/opencode/themes"
if [ ! -f "$DEFAULT_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$DEFAULT_TUI_CONF" 2>/dev/null; then
    sudo mkdir -p "$DEFAULT_THEME_DIR"
    sudo cp "$LIBDIR/tui/opencode-danger.theme.json" "$DEFAULT_THEME_DIR/opencode-danger.json"
    sudo cp "$LIBDIR/tui/tui-danger.json" "$DEFAULT_TUI_CONF"
    sudo chown -R "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_THEME_DIR"
    sudo chown "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_TUI_CONF"
    sudo chmod 664 "$DEFAULT_TUI_CONF" "$DEFAULT_THEME_DIR/opencode-danger.json"
    log "tui danger theme refreshed: $DEFAULT_TUI_CONF"
fi

# --- optional group-baseline refresh ------------------------------------------

if [ "$REFRESH" = true ]; then
    ui_section "Refreshing group baseline"
    # Shared helper with live per-pass progress (issue #14 — large trees
    # used to run minutes in silence during --refresh).
    _fsbl=""
    for _fsbl_cand in "$SCRIPT_DIR/opencode-permissions-kit-lib/fs-baseline.sh" "$LIBDIR/fs-baseline.sh"; do
        if [ -f "$_fsbl_cand" ]; then . "$_fsbl_cand"; _fsbl="$_fsbl_cand"; break; fi
    done
    [ -n "$_fsbl" ] || fs_baseline_root() { :; }
    if [ -f "$PROJECTS_CONF" ]; then
        while IFS= read -r root; do
            [ -z "$root" ] && continue
            [ -d "$root" ] || continue
            fs_baseline_root "$root" "$NEW_OPENCODE_GROUP"
            ddev_handover_root "$root" "$OPENCODE_USER" "$NEW_OPENCODE_GROUP" "$DEFAULT_USER"
        done < "$PROJECTS_CONF"
    fi
    ui_success "group baseline refreshed (chgrp + setgid + g+rw + default ACLs)"
    log "group baseline refresh requested (--refresh)"
else
    ui_detail "skipped group-baseline refresh (use --refresh to re-apply chgrp/setgid/default ACLs)"
fi

fi   # ONLY_BINARY skip: post-binary sections

# --- done --------------------------------------------------------------------

ui_section "Update complete"

if [ "$ONLY_BINARY" = true ]; then
    ui_kv "Mode"     "binary-only (kit files untouched)"
else
    ui_kv "Kit"      "v$VERSION"
    ui_kv "Configs"  "projects.conf and opencode.jsonc untouched"
fi
[ "$BINARY_UPDATE" = true ] || ui_kv "Binary"   "untouched (use --binary to upgrade)"
ui_info "Next:"
ui_detail "opk status   verify the protection"
ui_detail "opk upgrade-opencode    upgrade the opencode binary"
log "update complete (version $VERSION)"
