#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode-permissions-kit/management/status.sh
# or from a checkout:
#   files/opencode-permissions-kit-lib/management/status.sh
# Deliberately set -u ONLY (no -e/pipefail): status is a read-only report —
# one failing probe must not kill the remaining sections; failures render
# as "unknown" rows instead (same fail-soft class as uninstall.sh).
#
# CLI (issue #158): --short/-s prints only the final verdict line and
# carries it in the exit code (0 all green, 1 alert(s), 2 warning(s)
# only, 64 usage error) — cron/timer friendly.
set -u

# --- CLI (issue #158) ------------------------------------------------------------
# --short/-s: one verdict line. UI_SILENT mutes the ui.sh printers while
# the severity counters keep counting; the verdict line prints at the
# very end (UI_SILENT off again). Usage errors exit 64 (EX_USAGE) so
# they never collide with the verdict codes 1/2.
STATUS_SHORT=false
for _st_arg in "$@"; do
    case "$_st_arg" in
        --short | -s) STATUS_SHORT=true ;;
        *)
            echo "usage: sh $(basename "$0") [--short]" >&2
            exit 64
            ;;
    esac
done
if [ "$STATUS_SHORT" = true ]; then
    UI_SILENT=1
fi

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"

# Shared UI helpers (checkout-first, 0.0.46a F4 pattern like ddev-handover
# below): the checkout's status.sh needs its OWN ui.sh — the deployed one
# can predate ui_kv_ok/ui_kv_bad (issue #158) and would drop those rows.
# A deployed run resolves to the identical file anyway.
UI_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/ui.sh"
[ -f "$UI_LIB" ] || UI_LIB="/usr/local/lib/opencode-permissions-kit/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error: ui.sh not found (expected $LIBDIR/sh/ui.sh or next to status.sh in a checkout)" >&2
    exit 1
fi

# Shared git check (issue #118): the soft tested floor for the Core row.
# Checkout-first for the same reason as ui.sh above: an older deployed
# git-check.sh would render its row via plain ui_kv and the summary
# (issue #158) would not count it.
# Missing-lib behavior (issue #165, #199 a W3): the old fail-soft
# contract ("a missing helper just drops the row") is retired — on a
# deployed run both resolution candidates are the same path, so a
# missing file is a broken kit; the call site below renders a counted
# warn row instead of silently dropping the Core git row.
GIT_CHECK_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/git-check.sh"
[ -f "$GIT_CHECK_LIB" ] || GIT_CHECK_LIB="$LIBDIR/sh/git-check.sh"
if [ -f "$GIT_CHECK_LIB" ]; then
    # shellcheck disable=SC1090
    . "$GIT_CHECK_LIB"
fi

VERSION="0.0.0"
DEFAULT_USER=""
OPENCODE_USER="opencode"
OPENCODE_GROUP=""
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi
# Shape-gate the sourced value (#243 e X1 mirror, pr-00263 a F2b): a
# shape-invalid value feeds id -gn and the report rows below — fall
# back to the canonical literal, loudly; sanitized WARN (a F9 class).
case "$OPENCODE_USER" in
    '' | *[!A-Za-z0-9_.-]* | [.-]* | *[.])
        _ou_bad="$(printf '%s' "$OPENCODE_USER" | tr -c 'A-Za-z0-9_.-' '?')"
        echo "WARN: invalid OPENCODE_USER value in install.conf ('$_ou_bad') — falling back to 'opencode'" >&2
        OPENCODE_USER=opencode
        ;;
esac
# Sharing group: the opencode user's own usergroup; prefer the live value.
OPENCODE_GROUP="${OPENCODE_GROUP:-opencode}"
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
[ -n "$LIVE_GROUP" ] && OPENCODE_GROUP="$LIVE_GROUP"

# installed = the wrapper is active (user + wrapper + library present)
installed=false
if id "$OPENCODE_USER" >/dev/null 2>&1 && [ -x "$LIBDIR/bin/opencode-as-opencode" ] &&
    [ -L /usr/local/bin/opencode ]; then
    installed=true
fi

ui_banner "$VERSION" "protection status"

if [ "$installed" = false ]; then
    if [ "$STATUS_SHORT" = true ]; then
        # Machine mode: one line, verdict in the exit code — "not
        # installed" is the loudest not-green state there is.
        echo "not installed — hardening NOT active (run 'opk status' for the full report)"
        exit 1
    fi
    ui_warn "Hardening NOT active."
    echo ""
    ui_info "Install it with:"
    ui_detail "curl -fsSL https://raw.githubusercontent.com/steffenmaechtel""\
/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash"
    echo ""
    # Full mode keeps exit 0 here on purpose: status.sh is a diagnostic
    # that must not "fail" for reporting absence (the summary's exit
    # codes apply to installed reports; --short reports this state as 1).
    exit 0
fi

# --- section logic: sh/status-core.sh (issue #346, wave 1) ---------------------
# Every report section below lives in the sourced lib — checkout-first
# like ui.sh above (a checkout status.sh must render its own sections; an
# older deployed lib could predate a row). A deployed run resolves both
# candidates to the same path, so a missing lib is a broken kit (issue
# #165 class): loud error, no silent section drops.
STATUS_CORE="$(cd "$(dirname "$0")" && pwd)/../sh/status-core.sh"
[ -f "$STATUS_CORE" ] || STATUS_CORE="$LIBDIR/sh/status-core.sh"
if [ -f "$STATUS_CORE" ]; then
    # shellcheck disable=SC1090
    . "$STATUS_CORE"
else
    echo "error: status-core.sh not found (expected $LIBDIR/sh/status-core.sh or next to status.sh in a checkout)" >&2
    exit 1
fi

# --- sections, in report order (output order is user-visible) -----------------
status_section_core
status_section_advisories
status_section_projects
status_section_backend
status_section_ddev
status_section_wsl2
status_section_root_equiv
status_section_leak_scan
status_section_management

# === Summary (issue #158) ========================================================
# One verdict line at the end: instead of scrolling the whole report, the
# eye (and cron) gets "All green" or the alert/warning tally. Severities
# are counted BY CALL in the semantic ui helpers (ui_kv_ok/ui_kv_warn/
# ui_kv_bad, ui_have/ui_atten/ui_miss, ui_warn/ui_error) — color bytes
# are empty under NO_COLOR/piping and could not be counted. The tally
# only sees MAIN-shell rows: the scans above feed their reporting loops
# from temp files for exactly that reason (a `cmd | while` pipeline
# bumps counters in a subshell, where they die). The counts snapshot
# BEFORE the verdict row prints, so the row itself never counts.
# NOT counted by design (0.0.48b W3): rows the caller cannot judge at
# their own privilege ("unknown — needs root") and optional-feature rows
# ("missing (optional …") — unknown ≠ finding, and a permanent warn for
# every unprivileged or HTTPS-less host would make green unattainable
# and the cron alert worthless. They stay visible as plain ui_kv rows.
# Exit code carries the verdict for callers and cron:
#   0 all green · 1 alert(s) · 2 warning(s) only · 64 usage error.
_st_alerts=$UI_ROWS_BAD
_st_warns=$UI_ROWS_WARN
_st_passes=$UI_ROWS_OK
if [ "$STATUS_SHORT" = true ]; then
    UI_SILENT=0
    _st_tail="— run 'opk status' for the full report"
else
    ui_section "Summary"
    _st_tail="— see the sections above"
fi
if [ "$_st_alerts" -gt 0 ]; then
    ui_kv_bad "result" "$_st_alerts alert(s), $_st_warns warning(s) $_st_tail"
    _st_rc=1
elif [ "$_st_warns" -gt 0 ]; then
    ui_kv_warn "result" "$_st_warns warning(s) $_st_tail"
    _st_rc=2
else
    ui_kv_ok "result" "All green — $_st_passes checks passed, no alerts, no warnings"
    _st_rc=0
fi
exit "$_st_rc"
