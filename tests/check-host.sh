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
#   gh — agent issue/PR workflow only; versions below the pinned minimum
#   (GH_MIN) get a warning with the --json workaround (plain view is
#   broken, issue #335)

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

# gh_version_ge <have> <min> — rc 0 when have >= min (dotted numbers,
# compared numerically per component — "2.10" < "2.87", a string compare
# would say otherwise)
gh_version_ge() {
    awk -v have="$1" -v min="$2" 'BEGIN {
        na = split(have, A, "."); nb = split(min, B, ".")
        n = na > nb ? na : nb
        for (i = 1; i <= n; i++) {
            x = (i <= na ? A[i] : 0) + 0
            y = (i <= nb ? B[i] : 0) + 0
            if (x > y) exit 0
            if (x < y) exit 1
        }
        exit 0
    }'
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

ui_section "Agent workflow (optional)"
# gh — below GH_MIN plain `gh issue view` / `gh pr view` FAIL hard: their
# templates query the deprecated GraphQL projectCards field, GitHub rejects
# the query and gh exits 1 with no output (issue #335, cli/cli#11992).
# Warning only, never blocking: the suite does not need gh, and the CI
# image may not carry it. The output names GH_MIN as INFORMATION (plain
# view recovers from GH_MIN) but carries no install instructions — the host
# upgrade belongs to the maintainer, a session must not grow a second gh
# next to the maintainer's old one. Maintainer fix (comment only, never
# printed): official cli.github.com apt repo + an /etc/apt/preferences.d
# pin (Priority 1001) to outrank Ubuntu ESM's gh 2.45.0.
GH_MIN="2.87"
if command -v gh >/dev/null 2>&1; then
    _gh_v="$(gh --version 2>/dev/null | sed -n '1s/^gh version \([0-9][0-9.]*\).*/\1/p')"
    if [ -n "$_gh_v" ] && gh_version_ge "$_gh_v" "$GH_MIN"; then
        ui_have "gh" "agent issue/PR workflow ($_gh_v >= $GH_MIN)"
    else
        ui_atten "gh" "old version ${_gh_v:-unknown} — plain 'gh issue/pr view' fails (issue #335)"
        ui_detail "agents: use gh issue view N --json number,title,body,comments"
        ui_detail "        or gh api repos/OWNER/REPO/issues/N — plain view stays"
        ui_detail "        broken below gh $GH_MIN; upgrading gh is the maintainer's"
        ui_detail "        task, not the session's (no self-install)"
    fi
else
    ui_atten "gh" "not installed — agent issue/PR workflow (optional)"
    ui_detail "install: https://cli.github.com (Ubuntu universe ships only 2.45.0)"
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
