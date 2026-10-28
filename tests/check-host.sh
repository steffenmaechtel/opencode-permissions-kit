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
#   shfmt — EXACT version v3.14.1 (format gate; formatting output
#           drifts between shfmt versions, so the pin is hard:
#           make install-shfmt downloads it)
#   setsid + script (util-linux) — hermetic/pty ui prompt tests
# Optional (reported, never blocking):
#   docker, curl, tar + xz  — e2e suites only (make e2e / e2e-rootless)
#   / make e2e-ddev; the ddev suite additionally needs a real ddev binary
#   and builds a cached golden image

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Shared UI helpers — same visual language as every kit script.
UI_LIB="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    . "$UI_LIB"
else
    ui_info() { echo "  info     $1"; }
    ui_success() { echo "  success  $1"; }
    ui_warn() { echo "  warn     $1"; }
    ui_error() { echo "  error    $1" >&2; }
    ui_detail() { echo "     $1"; }
    ui_section() {
        echo ""
        echo "  --- $1 ---"
        echo ""
    }
    ui_have() { printf '  ok   %s  %s\n' "$1" "$2"; }
    ui_atten() { printf '  !    %s  %s\n' "$1" "$2"; }
    ui_miss() { printf '  x    %s  %s\n' "$1" "$2"; }
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
check git "branching, git-config tests" "$APT git / $BREW git"
check make "make test / make lint / make e2e" "$APT make / $BREW make"
check python3 "jsonc parser + kit CLI + git-config tests" "$APT python3 / $BREW python"
check shellcheck "static analysis of the shipped scripts (make lint)" "$APT shellcheck / $BREW shellcheck"
check setsid "hermetic ui tests (detach the controlling tty)" "$APT util-linux"
check script "pty capture for prompt pins — test-ui, test-kit-cli, test-uninstall, test-browser-bridge (util-linux -qec)" "$APT util-linux"
check seq "probes in test-skills-lint + test-line-length (pr-00263 a F26 — load-bearing counters)" "$APT coreutils"

# shfmt — the canonical format gate (make lint, issue #255 stage 0a).
# The version pin is EXACT on purpose: 3.7.0 and 3.12.0 each reformat
# lines that 3.14.1 leaves alone (measured 2026-10-28), so any other
# version reddens the gate with confusing diffs on one host but not
# the other. Distro packages are too old (apt 3.7.0, snap 3.12.0 —
# and the dash language variant needs 3.14.x anyway); the single
# static binary needs no root.
SHFMT_PINNED="v3.14.1"
if command -v shfmt >/dev/null 2>&1; then
    _shfmt_v="$(shfmt --version 2>/dev/null)"
    if [ "$_shfmt_v" = "$SHFMT_PINNED" ]; then
        ui_have "shfmt" "canonical shell format (make lint, pinned $_shfmt_v)"
    else
        ui_miss "shfmt" "WRONG VERSION — found ${_shfmt_v:-unknown}, need $SHFMT_PINNED"
        ui_detail "install: make install-shfmt (pinned download to ~/.local/bin)"
        missing="$missing shfmt"
        missing_hint="$missing_hint
  shfmt: make install-shfmt"
    fi
else
    ui_miss "shfmt" "MISSING — canonical shell format (make lint)"
    ui_detail "install: make install-shfmt (pinned download to ~/.local/bin)"
    missing="$missing shfmt"
    missing_hint="$missing_hint
  shfmt: make install-shfmt"
fi

ui_section "Optional (e2e suites only — make e2e / e2e-rootless)"
check_opt docker "runs the containerized e2e suites" "$APT docker-ce"
check_opt curl "fetches opencode binaries / kit files" "$APT curl / $BREW curl"
check_opt tar "unpacks the opencode release tarball" "$APT tar / $BREW tar"
check_opt xz "decompresses the opencode release tarball" "$APT xz-utils / $BREW xz"

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
