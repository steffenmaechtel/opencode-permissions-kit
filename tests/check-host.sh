#!/bin/sh
# check-host.sh — contributor environment pre-flight
#
# Verifies that everything needed to work on this repo is present on the
# host and tells the user how to install what is missing. Run it before
# `make test` / `make lint`:
#
#   sh tests/check-host.sh
#
# Exit status: 0 = ready to contribute (optional tools may still be
# missing — reported as info only), 1 = required tools missing.
#
# Required for the unit suite (make test):
#   git, make, python3, shellcheck
# Optional (reported, never blocking):
#   docker, curl, tar + xz  — e2e suites only (make e2e / e2e-rootless)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Shared UI helpers — same visual language as every kit script.
UI_LIB="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/ui.sh"
if [ -f "$UI_LIB" ]; then
    . "$UI_LIB"
else
    ui_info()    { echo "  info     $1"; }
    ui_success() { echo "  success  $1"; }
    ui_warn()    { echo "  warn     $1"; }
    ui_error()   { echo "  error    $1" >&2; }
    ui_detail()  { echo "     $1"; }
    ui_section() { echo ""; echo "  --- $1 ---"; echo ""; }
    ui_have()    { printf '  ok   %s  %s\n' "$1" "$2"; }
    ui_atten()   { printf '  !    %s  %s\n' "$1" "$2"; }
    ui_miss()    { printf '  x    %s  %s\n' "$1" "$2"; }
fi

missing=""
missing_hint=""

# check <tool> <why-needed> <install-hint>
check() {
    _tool="$1" _why="$2" _hint="$3"
    if command -v "$_tool" >/dev/null 2>&1; then
        ui_have "$_tool" "$_why"
    else
        ui_miss "$_tool" "MISSING — $_why"
        [ -n "$_hint" ] && ui_detail "install: $_hint"
        missing="$missing $_tool"
        missing_hint="$missing_hint
  $_tool: $_hint"
    fi
}

# check_opt <tool> <why-needed> <install-hint>
check_opt() {
    _tool="$1" _why="$2" _hint="$3"
    if command -v "$_tool" >/dev/null 2>&1; then
        ui_have "$_tool" "$_why"
    else
        ui_atten "$_tool" "not installed — $_why (optional)"
        [ -n "$_hint" ] && ui_detail "install: $_hint"
    fi
}

APT="sudo apt install"
BREW="brew install"

ui_section "Required for the unit suite (make test)"
check git      "branching, git-config tests"                 "$APT git / $BREW git"
check make     "make test / make lint / make e2e"            "$APT make / $BREW make"
check python3  "jsonc parser + kit CLI + git-config tests"   "$APT python3 / $BREW python"
check shellcheck "static analysis of the shipped scripts (make lint)" "$APT shellcheck / $BREW shellcheck"
check setsid   "hermetic ui tests (detach the controlling tty)"  "$APT util-linux"

ui_section "Optional (e2e suites only — make e2e / e2e-rootless)"
check_opt docker "runs the containerized e2e suites"         "$APT docker-ce"
check_opt curl   "fetches opencode binaries / kit files"     "$APT curl / $BREW curl"
check_opt tar    "unpacks the opencode release tarball"      "$APT tar / $BREW tar"
check_opt xz     "decompresses the opencode release tarball" "$APT xz-utils / $BREW xz"

echo ""

if [ -n "$missing" ]; then
    ui_error "host not ready — required tools missing:$missing"
    echo ""
    echo "  Install them, then re-run:  sh tests/check-host.sh"
    echo "$missing_hint"
    exit 1
fi

ui_success "host ready — run the suite with:  make test"
exit 0
