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
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/opencode-permissions-kit-lib/management/update.sh | sudo env KIT_BRANCH=stable bash
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

# Ref the kit updates from. Resolution (issue #38, docs/design/
# release-handling.md): --channel flag (pre-scanned below) > explicit
# KIT_BRANCH env > KIT_CHANNEL stamp in install.conf (the channel this
# machine installed/last updated from) > master (development channel;
# 'stable' is the release mirror the docs one-liners use). Must run BEFORE
# the self-fetch below. Overridable for testing:
# KIT_BASE_URL=https://example.invalid/<branch>
#
# --channel <ref> pre-scan: 'opk update --channel <ref>' switches the
# tracking ref for THIS update and every future one — update.sh re-stamps
# KIT_CHANNEL at the end, so the switch persists. The scan must happen
# before the resolution below and before the fetch; the regular arg loop
# below consumes and validates the flag again.
_prev_arg=""
for _arg in "$@"; do
    if [ "$_prev_arg" = "--channel" ]; then
        [ -n "$_arg" ] || { echo "error: --channel requires a ref (stable, master, a branch, or a tag)" >&2; exit 1; }
        KIT_BRANCH="$_arg"
    fi
    _prev_arg="$_arg"
done
_kit_stamped_channel="$(sed -n 's/^KIT_CHANNEL=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1)"
KIT_BRANCH="${KIT_BRANCH:-${_kit_stamped_channel:-master}}"
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Canonical kit file list. Single source of truth shared by fetch_kit() and
# the pre-deploy verification (ensure_local_file), so the two can never drift
# and a stale installed update.sh fetching an incomplete temp dir is healed
# before the deploy cp's run.
# Layout (docs/design/streamline.md): bin/ = commands, sh/ = sourced libs,
# py/ = python, tui/ = assets; the management scripts and templates keep
# their files/ root paths (streamed entry points) and deploy into
# management/ and templates/.
# BREAKING (0.0.29): the pre-0.0.29 flat layout moved — `opk update` from
# an older install aborts on the old fetch list (404); migrate once via
#   curl -fsSL .../files/opencode-permissions-kit-lib/management/update.sh | sudo bash
# which deploys the new layout and removes the old files (see the cleanup
# section below). No compatibility stubs are kept for the old paths.
KIT_FILES="install.sh VERSION \
             opencode-permissions-kit-lib/management/config.sh opencode-permissions-kit-lib/management/update.sh opencode-permissions-kit-lib/management/status.sh opencode-permissions-kit-lib/management/uninstall.sh \
             opencode-permissions-kit-lib/templates/opencode.jsonc \
             opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc \
             opencode-permissions-kit-lib/templates/sudoers.template etc/umask.sh \
opencode-permissions-kit-lib/bin/opencode-as-opencode opencode-permissions-kit-lib/bin/opk opencode-permissions-kit-lib/py/jsonc-parser.py opencode-permissions-kit-lib/py/tui-register.py \
opencode-permissions-kit-lib/sh/log.sh opencode-permissions-kit-lib/sh/ui.sh opencode-permissions-kit-lib/sh/shell-warn.sh opencode-permissions-kit-lib/bin/setup-container-backend opencode-permissions-kit-lib/bin/socket-check opencode-permissions-kit-lib/bin/cwd-check opencode-permissions-kit-lib/sh/ddev-terminal.sh opencode-permissions-kit-lib/bin/ddev-as-opencode opencode-permissions-kit-lib/sh/ddev-handover.sh opencode-permissions-kit-lib/sh/ddev-migrate.sh opencode-permissions-kit-lib/bin/ddev-migrate opencode-permissions-kit-lib/sh/ddev-hosts.sh opencode-permissions-kit-lib/sh/fs-baseline.sh opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh opencode-permissions-kit-lib/bin/browser-bridge \
opencode-permissions-kit-lib/tui/kit-mode.tsx opencode-permissions-kit-lib/tui/kit-mode-2x.tsx opencode-permissions-kit-lib/tui/opencode-danger.theme.json opencode-permissions-kit-lib/tui/tui.json opencode-permissions-kit-lib/tui/tui-danger.json"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` or run from the installed library
# (which only holds the previously deployed, possibly older, files).
fetch_kit() {
    local base dir f
    base="$(mktemp -d)"
    dir="$base/files"
    # Pre-create every subdirectory referenced by KIT_FILES (bin/, sh/,
    # py/, tui/): curl -o cannot write into a missing directory and aborts
    # the fetch with error 23 ("Failure writing output to destination").
    mkdir -p "$dir/opencode-permissions-kit-lib/bin" "$dir/opencode-permissions-kit-lib/sh" "$dir/opencode-permissions-kit-lib/py" "$dir/opencode-permissions-kit-lib/tui" "$dir/opencode-permissions-kit-lib/management" "$dir/opencode-permissions-kit-lib/templates" "$dir/etc"
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

# Re-fetch any single kit file that is missing under $FILES_ROOT (best-effort).
# Heals an incomplete temp-fetch when an older installed update.sh re-exec'd
# this freshly fetched copy with a smaller file list. For a real local
# checkout every file is present and this is a no-op.
ensure_local_file() {
    local f="$1"
    [ -f "$FILES_ROOT/$f" ] && return 0
    mkdir -p "$(dirname "$FILES_ROOT/$f")"
    echo "  re-fetching missing $f ..." >&2
    curl -fsSL "$KIT_BASE_URL/files/$f" -o "$FILES_ROOT/$f" 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# Binary-only mode (--only-binary) needs NO kit files at all — when running
# from the installed library, skip the self-fetch (and the per-file heal loop
# below, which would re-fetch the whole kit for the deployed layout).
# --binary-path ALONE does a full update PLUS the binary swap, so it must NOT
# skip the fetch (review 0.0.29: from the installed library it would have
# crashed the deploy section with FILES_ROOT=/usr/local/lib).
_opk_binonly=false
for _opk_a in "$@"; do
    case "$_opk_a" in
        --only-binary) _opk_binonly=true; break ;;
    esac
done
if [ "$_opk_binonly" != true ] && [ ! -f "$SCRIPT_DIR/../../../VERSION" ]; then
    echo "No local checkout — fetching kit files from $KIT_BASE_URL ..."
    SCRIPT_DIR="$(fetch_kit)" || { echo "error  Failed to fetch kit files from $KIT_BASE_URL" >&2; exit 1; }
    # Do NOT continue executing this (installed, possibly older) copy: the
    # deploy below overwrites $LIBDIR/management/update.sh with the freshly fetched one,
    # which would replace the very file we are still running from. bash reads
    # a script incrementally, so a self-modifying script corrupts its parser
    # mid-run ("syntax error near unexpected token '('"). Re-exec the fetched
    # copy instead — its own overwrite of $LIBDIR/management/update.sh is then harmless.
    exec bash "$SCRIPT_DIR/opencode-permissions-kit-lib/management/update.sh" "$@"
fi
# The files/ root this update deploys from: after the fetch+re-exec above
# $SCRIPT_DIR is the fetched files/ directory itself; run from a checkout it
# is files/opencode-permissions-kit-lib/management (two levels down).
FILES_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd -P)"

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
VERSION=$(cat "$FILES_ROOT/../VERSION" 2>/dev/null \
    || sed -n 's/^VERSION=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1 \
    || echo "0.0.0")
LIBDIR="/usr/local/lib/opencode-permissions-kit"
CONFDIR="/etc/opencode-permissions-kit"
PROJECTS_CONF="$CONFDIR/projects.conf"

# === Shared UI helpers ===
# Checkout copy first, then the deployed library; a plain fallback keeps
# update.sh working on an install whose library predates ui.sh.
UI_LIB=""
for _cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/ui.sh" "$LIBDIR/sh/ui.sh"; do
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
for cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/log.sh" "$LIBDIR/sh/log.sh"; do
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
        echo "    curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash"
        echo ""
        exit 1
    fi
fi

YES=false
REFRESH=false
BINARY_UPDATE=false
ONLY_BINARY=false
BINARY_PATH=""
UPGRADE_MAJOR=""
UPGRADE_VERSION=""
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
        --channel)
            # consumed by the pre-scan above (before the self-fetch);
            # accepted here so it never reaches the unknown-option trap
            [ "$#" -ge 2 ] || { echo "error: --channel requires a ref (stable, master, a feature branch, or a tag)" >&2; exit 1; }
            shift
            ;;
        --major)
            # issue #99: switch the opencode major (1 <-> 2); without it
            # upgrades stay within the current major
            [ "$#" -ge 2 ] || { echo "error: --major requires a number (1 or 2)" >&2; exit 1; }
            case "$2" in
                1|2) UPGRADE_MAJOR="$2" ;;
                *) echo "error: --major must be 1 or 2" >&2; exit 1 ;;
            esac
            shift
            ;;
        --version)
            # issue #99: pin an exact opencode version; the download
            # channel follows the version prefix (2.* npm, 1.x GitHub)
            [ "$#" -ge 2 ] || { echo "error: --version requires an opencode version (e.g. 2.0.11)" >&2; exit 1; }
            UPGRADE_VERSION="$2"
            shift
            ;;
        -h|--help)
            cat <<EOF
opencode permissions kit -- update.sh  v$VERSION
Re-deploys the kit on an already-installed system. No prompts by default.
Usage: ./update.sh [--yes] [--refresh] [--binary] [--only-binary] [--binary-path <file>] [--channel <ref>] [--major 1|2] [--version <ver>]
  --yes            skip the confirmation prompt
  --refresh        also re-apply the group baseline (chgrp/setgid/default ACLs)
  --binary         also upgrade the opencode binary to the latest release
                   of the CURRENT major (issue #99: never crosses majors)
  --only-binary    skip every kit step, ONLY upgrade the opencode binary
  --binary-path    install the given binary file instead of downloading
  --channel        switch the tracking ref for this and every future update
                   (stable, master, a feature branch, or a pinned tag)
  --major          switch the opencode major: 1 or 2 (default: stay on the
                   current major; the TUI registration flips with it)
  --version        upgrade to exactly this opencode version (channel by
                   prefix: 2.* from npm, 1.x from GitHub)
EOF
            exit 0
            ;;
        *) echo "error: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

banner() {
    ui_banner "$VERSION" "update — channel '$KIT_BRANCH' — re-deploys the kit, keeps your configuration"
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
sudo mkdir -p "$LIBDIR/bin" "$LIBDIR/sh" "$LIBDIR/py" "$LIBDIR/tui" "$LIBDIR/management" "$LIBDIR/templates"

sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/opencode-as-opencode" "$LIBDIR/bin/opencode-as-opencode"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/opk"                "$LIBDIR/bin/opk"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/py/jsonc-parser.py"    "$LIBDIR/py/jsonc-parser.py"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/py/tui-register.py"    "$LIBDIR/py/tui-register.py"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/log.sh"             "$LIBDIR/sh/log.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/ui.sh"              "$LIBDIR/sh/ui.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/shell-warn.sh"      "$LIBDIR/sh/shell-warn.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/setup-container-backend" "$LIBDIR/bin/setup-container-backend"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/management/config.sh"                        "$LIBDIR/management/config.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/management/update.sh"                        "$LIBDIR/management/update.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/management/status.sh"                        "$LIBDIR/management/status.sh"
# sudoers.template: needed by the installed config.sh for backend switches
# (render_sudoers looks in $LIBDIR/templates first).
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/templates/sudoers.template"                 "$LIBDIR/templates/sudoers.template"
sudo chmod 440 "$LIBDIR/templates/sudoers.template"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/templates/opencode.jsonc"                   "$LIBDIR/templates/opencode.jsonc"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/management/uninstall.sh"                     "$LIBDIR/management/uninstall.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/socket-check" "$LIBDIR/bin/socket-check"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/cwd-check" "$LIBDIR/bin/cwd-check"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-terminal.sh" "$LIBDIR/sh/ddev-terminal.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/ddev-as-opencode" "$LIBDIR/bin/ddev-as-opencode"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-handover.sh" "$LIBDIR/sh/ddev-handover.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-migrate.sh"  "$LIBDIR/sh/ddev-migrate.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/ddev-migrate"    "$LIBDIR/bin/ddev-migrate"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/fs-baseline.sh"  "$LIBDIR/sh/fs-baseline.sh"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-hosts.sh"    "$LIBDIR/sh/ddev-hosts.sh"
# browser-bridge stand-in source (deploys into the wsl/ tree; source of
# 'opk wsl-add-opencode-1-fix' re-runs)
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/bin/browser-bridge" "$LIBDIR/bin/browser-bridge"
# WSL browser bridge (issues #91, #100): the deploy helper joins the
# library; the stand-in tree + /etc/wsl.conf comment block are (re)applied
# below after the library is in place.
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh" "$LIBDIR/sh/wsl-browser-bridge.sh"
# TUI mode display (docs/_archive/design/plan-ui-tui-opencode.md): plugin + templates.
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/kit-mode.tsx" "$LIBDIR/tui/kit-mode.tsx"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/kit-mode-2x.tsx" "$LIBDIR/tui/kit-mode-2x.tsx"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/opencode-danger.theme.json" "$LIBDIR/tui/opencode-danger.theme.json"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/tui.json" "$LIBDIR/tui/tui.json"
sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/tui-danger.json" "$LIBDIR/tui/tui-danger.json"
sudo chmod 644 "$LIBDIR/sh/ddev-terminal.sh" "$LIBDIR/sh/ddev-handover.sh" "$LIBDIR/sh/ddev-migrate.sh" "$LIBDIR/sh/ddev-hosts.sh" "$LIBDIR/sh/fs-baseline.sh" "$LIBDIR/sh/wsl-browser-bridge.sh"
sudo chmod 644 "$LIBDIR/tui/kit-mode.tsx" "$LIBDIR/tui/kit-mode-2x.tsx" "$LIBDIR/tui/opencode-danger.theme.json" "$LIBDIR/tui/tui.json" "$LIBDIR/tui/tui-danger.json"
sudo chmod 755 "$LIBDIR/py/tui-register.py"
sudo chmod 755 "$LIBDIR/bin/opencode-as-opencode" "$LIBDIR/bin/opk" "$LIBDIR/py/jsonc-parser.py" \
               "$LIBDIR/sh/log.sh" "$LIBDIR/sh/ui.sh" "$LIBDIR/sh/shell-warn.sh" "$LIBDIR/bin/setup-container-backend" \
               "$LIBDIR/management/config.sh" "$LIBDIR/management/update.sh" "$LIBDIR/management/status.sh" "$LIBDIR/management/uninstall.sh" \
               "$LIBDIR/bin/socket-check" "$LIBDIR/bin/cwd-check" "$LIBDIR/bin/ddev-as-opencode" "$LIBDIR/bin/ddev-migrate" \
               "$LIBDIR/bin/browser-bridge"

# --- old-layout cleanup (0.0.29 streamline, docs/design/streamline.md §5) --------
# Remove the union of pre-0.0.29 deployed paths after the new layout is in
# place. Idempotent rm -f — covers every historical location since 0.0.14.
for _opk_old in \
    "$LIBDIR/wrapper" "$LIBDIR/kit" "$LIBDIR/jsonc-parser.py" \
    "$LIBDIR/bin/socket-check.sh" "$LIBDIR/bin/cwd-check.sh" \
    "$LIBDIR/log.sh" "$LIBDIR/ui.sh" "$LIBDIR/shell-warn.sh" \
    "$LIBDIR/setup-container-backend.sh" "$LIBDIR/ddev-as-opencode.sh" \
    "$LIBDIR/ddev-handover.sh" "$LIBDIR/ddev-migrate.sh" \
    "$LIBDIR/ddev-hosts.sh" "$LIBDIR/fs-baseline.sh" \
    "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
    "$LIBDIR/sudoers.template" "$LIBDIR/opencode.jsonc" "$LIBDIR/opencode-deny-all.jsonc" \
    "$LIBDIR/migrate-denies.sh"; do
    [ -e "$_opk_old" ] && sudo rm -f "$_opk_old" && ui_detail "removed old file: $_opk_old"
done
ui_success "library re-deployed: $LIBDIR"
log "library re-deployed: $LIBDIR (old-layout cleanup applied)"

# --- WSL browser bridge (issues #91, #100) -------------------------------------
# (Re)apply the stand-in tree and strip the legacy 0.0.36 section (kit-owned
# regression cleanup). The /etc/wsl.conf carrier is NEVER written here —
# the kit does not edit wsl.conf implicitly (docs/design/wsl-conf-consent.md);
# the user opts in via 'sudo opk wsl-add-opencode-1-fix'. An existing
# carrier stays untouched and keeps working.
[ -f "$FILES_ROOT/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh" ] && . "$FILES_ROOT/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh"
[ -f "$LIBDIR/sh/wsl-browser-bridge.sh" ] && . "$LIBDIR/sh/wsl-browser-bridge.sh"
command -v browser_bridge_is_wsl  >/dev/null 2>&1 || browser_bridge_is_wsl()  { return 1; }
command -v browser_bridge_install >/dev/null 2>&1 || browser_bridge_install() { :; }
if browser_bridge_is_wsl; then
    browser_bridge_install "$FILES_ROOT" "$LIBDIR"
    if grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null; then
        ui_success "WSL browser bridge re-applied (carrier present — fully active)"
        log "wsl browser bridge re-applied: $LIBDIR/wsl (carrier present)"
    else
        ui_success "WSL browser bridge stand-in re-applied (no wsl.conf carrier)"
        ui_detail "enable the opencode 1.x login fix yourself (the kit does not edit /etc/wsl.conf):"
        ui_detail "  sudo opk wsl-add-opencode-1-fix"
        log "wsl browser bridge stand-in re-applied: $LIBDIR/wsl (carrier left to 'opk wsl-add-opencode-1-fix')"
    fi
fi

# --- re-link wrapper + cli dispatcher ------------------------------------------

sudo ln -sf "$LIBDIR/bin/opencode-as-opencode" /usr/local/bin/opencode
ui_success "wrapper symlink refreshed: /usr/local/bin/opencode -> $LIBDIR/bin/opencode-as-opencode"
sudo rm -f /usr/local/bin/opencode-permissions-kit
sudo ln -sf "$LIBDIR/bin/opk" /usr/local/bin/opk
ui_success "cli symlink refreshed: /usr/local/bin/opk -> $LIBDIR/bin/opk (legacy name removed)"

# --- re-deploy sudoers -------------------------------------------------------

sudo mkdir -p "$CONFDIR"

if [ -f "$FILES_ROOT/opencode-permissions-kit-lib/templates/sudoers.template" ]; then
    SUDO_TMP=$(mktemp)
    sed -e "s/DEFAULT_USER/$DEFAULT_USER/g" "$FILES_ROOT/opencode-permissions-kit-lib/templates/sudoers.template" > "$SUDO_TMP"
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

if [ -f "$FILES_ROOT/etc/umask.sh" ]; then
    sudo cp "$FILES_ROOT/etc/umask.sh" /etc/profile.d/opencode-permissions-kit-umask.sh
    sudo chmod 644 /etc/profile.d/opencode-permissions-kit-umask.sh
    # Remove the pre-0.0.10 umask profile so only the new name is loaded.
    sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
    ui_success "umask profile re-deployed"
    log "umask profile re-deployed: /etc/profile.d/opencode-permissions-kit-umask.sh"
fi

# --- shell-startup hooks (rewrite old paths, append when missing) ---------------
# Older installs lack the interactive-shell hooks — append them idempotently
# so a self-installed opencode binary is reported and `ddev()` stays wrapped.
# 0.0.29 moved the hooked files (shell-warn.sh, ddev-as-opencode.sh ->
# sh/ddev-terminal.sh): the rc lines reference them by absolute path, and
# their [ -f ... ] guard would silently disable the hook after the move.
# The kit-owned line is therefore REWRITTEN in place (exact path match —
# user lines are never touched, the guard keeps the line harmless after
# uninstall); the hook is only appended when no kit hook line exists at all.
if [ -n "$DEFAULT_USER" ] && [ -d "/home/$DEFAULT_USER" ]; then
    for cf in "/home/$DEFAULT_USER/.bashrc" "/home/$DEFAULT_USER/.zshrc" "/home/$DEFAULT_USER/.profile"; do
        [ -f "$cf" ] || continue
        if sudo grep -q 'opencode-permissions-kit/sh/shell-warn.sh\|opencode-permissions-kit/shell-warn.sh' "$cf" 2>/dev/null; then
            sudo sed -i 's|/usr/local/lib/opencode-permissions-kit/shell-warn\.sh|/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh|g' "$cf"
        else
            echo '[ -f /usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh  # opencode permissions kit (wrapper bypass warning)' | sudo tee -a "$cf" > /dev/null
            ui_success "wrapper-bypass warning hooked into $cf"
            log "shell-startup warning hook appended: $cf"
        fi
        # ddev always runs as the opencode user: hook the `ddev()` shell
        # function (sudoers helper). Only the DEFAULT user — the opencode
        # session must never be wrapped (the function's id check is the guard).
        if sudo grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh\|opencode-permissions-kit/ddev-as-opencode.sh' "$cf" 2>/dev/null; then
            sudo sed -i 's|/usr/local/lib/opencode-permissions-kit/ddev-as-opencode\.sh|/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh|g' "$cf"
        else
            echo '[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh  # opencode permissions kit (ddev always runs as opencode)' | sudo tee -a "$cf" > /dev/null
            ui_success "ddev terminal hook installed into $cf"
            log "ddev-terminal hook appended: $cf"
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
    [ -f "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-handover.sh" ] && . "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-handover.sh"
    [ -f "$LIBDIR/sh/ddev-handover.sh" ] && . "$LIBDIR/sh/ddev-handover.sh"
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
            echo "  ${UI_YELLOW}then 'wsl --shutdown' from Windows. The kit never edits /etc/wsl.conf —${UI_NC}"
            echo "  ${UI_YELLOW}apply the snippet yourself.${UI_NC}"
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

# Detect the opencode release target for this host (mirrors the official
# installer; the same string is the npm package suffix, see
# tests/e2e/lib.sh).
detect_target() {
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
    echo "$target"
}

# Release asset name for this host (1.x GitHub assets).
detect_asset() {
    echo "opencode-$(detect_target).tar.gz"
}

# Verify a candidate binary actually runs, then install it over $SYSTEM_BIN.
install_binary() {
    local src="$1" current new
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 "$src" --version >/dev/null 2>&1 || return 1
    else
        "$src" --version >/dev/null 2>&1 || return 1
    fi
    # opencode 2.x keeps a background service daemon running the binary
    # (issue #80): replacing it while the daemon lives fails with "Text
    # file busy". Stop the service best-effort first — 2.x answers the
    # graceful stop, 1.x reports an unknown command and both errors are
    # ignored; the pkill is the belt to that braces (also catches a
    # wedged daemon). The next 2.x command re-ensures the service.
    sudo -u "$OPENCODE_USER" "$SYSTEM_BIN" service stop >/dev/null 2>&1 || true
    sudo pkill -u "$OPENCODE_USER" -f "serve --servic[e]" >/dev/null 2>&1 || true
    current=$("$SYSTEM_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    sudo cp "$src" "$SYSTEM_BIN" || return 1
    sudo chown "root:$BINARY_GROUP" "$SYSTEM_BIN" 2>/dev/null || true
    sudo chmod 750 "$SYSTEM_BIN" || return 1
    new=$("$SYSTEM_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    # Re-stamp the major so the wrapper's 2.x --standalone gating follows
    # the binary ("opencode v2..." -> 2, anything else -> 1).
    _new_major=$(printf '%s' "$new" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p')
    [ -n "$_new_major" ] || _new_major=1
    if [ -f "$CONFDIR/install.conf" ] && grep -q '^OPENCODE_MAJOR=' "$CONFDIR/install.conf" 2>/dev/null; then
        sudo sed -i "s/^OPENCODE_MAJOR=.*/OPENCODE_MAJOR=$_new_major/" "$CONFDIR/install.conf"
    elif [ -f "$CONFDIR/install.conf" ]; then
        echo "OPENCODE_MAJOR=$_new_major" | sudo tee -a "$CONFDIR/install.conf" >/dev/null
    fi
    echo "  opencode binary upgraded: ${current} -> ${new}"
    log "opencode binary upgraded: ${current} -> ${new}"
}

# Major of an opencode --version line (issue #99): 2.x prints
# "opencode v2.0.11" -> 2; 1.x prints the bare version ("1.18.31") -> 1.
version_major() {
    printf '%s' "$1" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p'
}

# Major of the currently installed binary — the source of truth; the
# install.conf stamp is the fallback (older kits), 1 the last resort.
current_opencode_major() {
    _com_ver=$("$SYSTEM_BIN" --version 2>/dev/null | head -1 || true)
    if [ -n "$_com_ver" ]; then
        _com_maj=$(version_major "$_com_ver")
        [ -n "$_com_maj" ] || _com_maj=1
        echo "$_com_maj"
        return 0
    fi
    _com_maj=$(sed -n 's/^OPENCODE_MAJOR=//p' "$CONFDIR/install.conf" 2>/dev/null | tail -1)
    echo "${_com_maj:-1}"
}

# Latest version for a major (issue #99): upgrades never hop majors
# silently. 1.x resolves through GitHub releases/latest (still the 1.x
# channel), 2.x through the npm dist-tag `latest` of @opencode/cli-<target>
# — the channel the official v2 installer resolves through; 2.x ships no
# GitHub release assets (docs/design/opencode-2x.md §8). A resolution
# outside the requested major fails loudly instead of crossing majors.
resolve_latest_opencode_version() {
    _rlov_major="$1"
    _rlov_target=$(detect_target) || return 1
    if [ "$_rlov_major" = 2 ]; then
        _rlov_ver=$(curl -fsSL --max-time 10 "https://registry.npmjs.org/@opencode/cli-$_rlov_target" 2>/dev/null \
            | tr ',' '\n' | sed -n 's/.*"latest": *"\([^"]*\)".*/\1/p' | head -1 || true)
        case "$_rlov_ver" in
            2.*) echo "$_rlov_ver"; return 0 ;;
            *)  return 1 ;;
        esac
    else
        _rlov_ver=$(curl -fsSL --max-time 10 https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null \
            | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
        case "$_rlov_ver" in
            1.*) echo "$_rlov_ver"; return 0 ;;
            *)  return 1 ;;
        esac
    fi
}

# Download + extract one exact opencode version into <dir> (channel by
# version prefix, same split as tests/e2e/lib.sh): 2.* from the npm
# registry (legacy @opencode-ai scope as fallback for pre-migration
# versions, tarball layout package/bin/opencode), 1.x from GitHub release
# assets. Prints the candidate binary path on success, nothing on failure.
# The CALLER owns <dir> — cleanup happens only after the install attempt
# (issue #24).
fetch_opencode_version() {
    _fov_dst="$1" _fov_ver="$2"
    [ -n "$_fov_dst" ] && [ -d "$_fov_dst" ] || return 1
    _fov_target=$(detect_target) || return 1
    case "$_fov_ver" in
        2.*)
            if ! curl -fsSL --max-time 240 "https://registry.npmjs.org/@opencode/cli-$_fov_target/-/cli-$_fov_target-$_fov_ver.tgz" \
                    -o "$_fov_dst/opencode.tar.gz" 2>/dev/null; then
                curl -fsSL --max-time 240 "https://registry.npmjs.org/@opencode-ai/cli-$_fov_target/-/cli-$_fov_target-$_fov_ver.tgz" \
                    -o "$_fov_dst/opencode.tar.gz" || return 1
            fi
            mkdir -p "$_fov_dst/npmx" || return 1
            tar -xzf "$_fov_dst/opencode.tar.gz" -C "$_fov_dst/npmx" || return 1
            [ -x "$_fov_dst/npmx/package/bin/opencode" ] || return 1
            mv "$_fov_dst/npmx/package/bin/opencode" "$_fov_dst/opencode" || return 1
            rm -rf "$_fov_dst/npmx" "$_fov_dst/opencode.tar.gz"
            ;;
        *)
            curl -fsSL --max-time 240 "https://github.com/anomalyco/opencode/releases/download/v$_fov_ver/opencode-$_fov_target.tar.gz" \
                -o "$_fov_dst/opencode.tar.gz" || return 1
            tar -xzf "$_fov_dst/opencode.tar.gz" -C "$_fov_dst" || return 1
            rm -f "$_fov_dst/opencode.tar.gz"
            ;;
    esac
    [ -x "$_fov_dst/opencode" ] || return 1
    echo "$_fov_dst/opencode"
    return 0
}

# Latest release for a major, downloaded into <dir> (issue #99 wrapper).
fetch_latest_opencode() {
    _fll_dst="$1" _fll_major="$2"
    [ -n "$_fll_major" ] || _fll_major=$(current_opencode_major)
    _fll_ver=$(resolve_latest_opencode_version "$_fll_major") || return 1
    fetch_opencode_version "$_fll_dst" "$_fll_ver" || return 1
}

# TUI mode display per major (issue #80): the 1.x artifacts (tui.json +
# danger theme) are major-agnostic — 2.x ignores them and they make a 1.x
# swap work instantly. Only the 2.x CLI-plugin dir flips: present on 2.x
# (symlink to kit-mode-2x.tsx, LIBDIR stays the source of truth), removed
# on 1.x. Inert file-path entries from pre-0.0.35 kits are unregistered
# best-effort on both paths.
sync_tui_registration() {
    _str_major="$1"
    for _str_dir_user in "/home/$OPENCODE_USER/.config/opencode:$OPENCODE_USER" "/home/$DEFAULT_USER/.config/opencode:$DEFAULT_USER"; do
        _str_user_dir="${_str_dir_user%%:*}"
        _str_dir_owner="${_str_dir_user#*:}"
        if [ "$_str_major" = 2 ]; then
            sudo mkdir -p "$_str_user_dir/plugins/opencode-permissions-kit"
            sudo ln -sfn "$LIBDIR/tui/kit-mode-2x.tsx" "$_str_user_dir/plugins/opencode-permissions-kit/tui.tsx"
            sudo chown "$_str_dir_owner:$NEW_OPENCODE_GROUP" "$_str_user_dir/plugins" "$_str_user_dir/plugins/opencode-permissions-kit" 2>/dev/null || true
            sudo chown -h "$_str_dir_owner:$NEW_OPENCODE_GROUP" "$_str_user_dir/plugins/opencode-permissions-kit/tui.tsx" 2>/dev/null || true
            log "tui mode registered for 2.x: $_str_user_dir/plugins/opencode-permissions-kit/tui.tsx"
        else
            sudo rm -rf "$_str_user_dir/plugins/opencode-permissions-kit"
            log "tui mode 2.x registration removed: $_str_user_dir/plugins/opencode-permissions-kit"
        fi
        sudo python3 "$LIBDIR/py/tui-register.py" "$_str_user_dir/cli.json" unregister "$LIBDIR/tui/kit-mode-2x.tsx" --drop "$LIBDIR/tui/kit-mode.tsx" >/dev/null 2>&1 || true
    done
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
        # Version resolution (issue #99): --version pin > --major switch >
        # stay on the current major. Never crosses majors silently.
        _up_ver=""
        if [ -n "$UPGRADE_VERSION" ]; then
            _up_ver="$UPGRADE_VERSION"
            ui_detail "target version pinned: $_up_ver"
        else
            _up_major="${UPGRADE_MAJOR:-$(current_opencode_major)}"
            ui_detail "resolving the latest opencode $_up_major.x release"
            if ! _up_ver=$(resolve_latest_opencode_version "$_up_major"); then
                ui_warn "could not resolve the latest opencode $_up_major.x release — binary left untouched"
                if [ -z "$UPGRADE_MAJOR" ]; then
                    ui_detail "to switch the opencode major run: opk upgrade-opencode --major 1|2"
                fi
                log "opencode binary upgrade skipped: no $_up_major.x release resolved"
            fi
        fi
        if [ -n "$_up_ver" ]; then
            TMP="$(mktemp -d)"
            if ! SRC=$(fetch_opencode_version "$TMP" "$_up_ver"); then
                ui_warn "download of opencode $_up_ver failed — binary left untouched"
                log "opencode binary upgrade skipped: download of $_up_ver failed"
                rm -rf "$TMP"
                TMP=""
                SRC=""
            fi
        fi
    fi
    if [ -n "$SRC" ]; then
        BACKUP_DIR="$(mktemp -d /tmp/opencode-upgrade-backup.XXXXXX)"
        if [ -x "$SYSTEM_BIN" ]; then
            sudo cp "$SYSTEM_BIN" "$BACKUP_DIR/opencode.current"
        fi
        _maj_before=$(current_opencode_major)
        if install_binary "$SRC"; then
            ui_detail "backup kept in $BACKUP_DIR (remove once you are satisfied)"
            # A major flip (v1 <-> v2, issue #99) must re-anchor the TUI
            # registration even in --only-binary runs — the plugin dir is
            # binary-coupled, not kit-coupled.
            _maj_after=$(current_opencode_major)
            if [ "$_maj_before" != "$_maj_after" ]; then
                sync_tui_registration "$_maj_after"
                ui_detail "opencode major changed ($_maj_before -> $_maj_after): TUI registration flipped"
                log "opencode major flipped: $_maj_before -> $_maj_after (tui registration synced)"
            fi
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
        sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
        sudo chown "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_OC_CONF"
        sudo chmod 664 "$DEFAULT_OC_CONF"
        ui_success "deny-all config installed for default user: $DEFAULT_OC_CONF"
        log "deny-all config installed for default user: $DEFAULT_OC_CONF"
    else
        ui_detail "default-user config exists — left untouched (re-run install.sh to back it up)"
    fi
fi

# --- live ddev version for the install.conf refresh (issue #72) ------------------
# DDEV_VERSION is an install-time stamp; a ddev upgrade leaves it behind.
# Re-probe on every update so the stamp fallback stays honest. Ask the
# kit's own helper first: ddev >= 1.25.4 refuses to run as root ("DDEV is
# not designed to be run with root privileges", exit 1 before any output)
# and updates run as root — the helper runs ddev exactly the way the kit
# does (as the opencode user, HOME/DOCKER_HOST re-set). The direct binary
# (PATH, then the two standard locations) is the fallback; when neither
# answers, the old stamp survives.
NEW_DDEV_VERSION="$(sed -n 's/^DDEV_VERSION=//p' "$INSTALL_CONF" 2>/dev/null | tail -1)"
_ddev_probe=""
if [ -x "$LIBDIR/bin/ddev-as-opencode" ] && id "$OPENCODE_USER" >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    _ddev_probe=$(sudo -n -u "$OPENCODE_USER" "$LIBDIR/bin/ddev-as-opencode" --version 2>/dev/null | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
fi
if [ -z "$_ddev_probe" ]; then
    _ddev_bin=""
    for _ddev_cand in "$(command -v ddev 2>/dev/null || true)" /usr/local/bin/ddev /usr/bin/ddev; do
        [ -n "$_ddev_cand" ] && [ -x "$_ddev_cand" ] && { _ddev_bin="$_ddev_cand"; break; }
    done
    if [ -n "$_ddev_bin" ]; then
        _ddev_probe=$("$_ddev_bin" --version 2>/dev/null | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
    fi
fi
if [ -n "$_ddev_probe" ]; then
    NEW_DDEV_VERSION="$_ddev_probe"
fi

# --- refresh install.conf (version stamp + group key) --------------------------

NEW_INSTALL_CONF="$(mktemp)"
{
    if [ -f "$INSTALL_CONF" ]; then
        # Strip keys this update owns: VERSION (re-stamped),
        # OPENCODE_GROUP (re-based to the opencode usergroup),
        # KIT_CHANNEL (re-stamped to the ref just updated from), and
        # DDEV_VERSION (re-probed above — the fallback stays fresh).
        grep -v -e '^VERSION=' -e '^OPENCODE_GROUP=' -e '^KIT_CHANNEL=' -e '^DDEV_VERSION=' "$INSTALL_CONF" 2>/dev/null
    fi
    echo "OPENCODE_GROUP=$NEW_OPENCODE_GROUP"
    echo "KIT_CHANNEL=$KIT_BRANCH"
    echo "VERSION=$VERSION"
    echo "DDEV_VERSION=$NEW_DDEV_VERSION"
} | sort -u > "$NEW_INSTALL_CONF"
sudo cp "$NEW_INSTALL_CONF" "$CONFDIR/install.conf"
sudo chmod 644 "$CONFDIR/install.conf"
rm -f "$NEW_INSTALL_CONF"
ui_success "install.conf updated: VERSION=$VERSION CHANNEL=$KIT_BRANCH OPENCODE_GROUP=$NEW_OPENCODE_GROUP DDEV_VERSION=$NEW_DDEV_VERSION"
log "install.conf updated: VERSION=$VERSION CHANNEL=$KIT_BRANCH OPENCODE_GROUP=$NEW_OPENCODE_GROUP DDEV_VERSION=$NEW_DDEV_VERSION"

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

# opencode 2.x (issue #80, #99): keep the TUI mode registration anchored
# to the installed major — register the kit-mode-2x.tsx plugin dir on 2.x,
# remove it on 1.x (the 1.x tui.json/danger theme are major-agnostic and
# stay). The major comes from the install.conf stamp, freshly re-stamped
# by any binary upgrade above.
_oc_major=$(sed -n 's/^OPENCODE_MAJOR=//p' "$CONFDIR/install.conf" 2>/dev/null | tail -1)
[ -n "$_oc_major" ] || _oc_major=1
sync_tui_registration "$_oc_major"

# --- optional group-baseline refresh ------------------------------------------

if [ "$REFRESH" = true ]; then
    ui_section "Refreshing group baseline"
    # Shared helper with live per-pass progress (issue #14 — large trees
    # used to run minutes in silence during --refresh).
    _fsbl=""
    for _fsbl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/fs-baseline.sh" "$LIBDIR/sh/fs-baseline.sh"; do
        if [ -f "$_fsbl_cand" ]; then . "$_fsbl_cand"; _fsbl="$_fsbl_cand"; break; fi
    done
    [ -n "$_fsbl" ] || fs_baseline_root() { :; }
    if [ -f "$PROJECTS_CONF" ]; then
        while IFS= read -r root; do
            [ -z "$root" ] && continue
            [ -d "$root" ] || continue
            fs_baseline_root "$root" "$NEW_OPENCODE_GROUP" "$OPENCODE_USER"
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
