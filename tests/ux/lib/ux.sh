# opencode permissions kit — DEMO UI helpers (tests/ux/ playground)
#
# Candidate for files/opencode-permissions-kit-lib/ui.sh (see
# docs/design/UX-IMPROVEMENT.md). POSIX sh, zero dependencies.
#
# Rules:
#   - Colors off when NO_COLOR is set or stdout is not a tty.
#   - UI_ASCII=1 forces plain ASCII fallbacks for broken locales.
#   - Nothing here executes anything; callers only print (and may sleep).
#
# Usage: . "$(dirname "$0")/lib/ux.sh"

# --- colors & symbols ---------------------------------------------------------
# The escape sequences must be resolved to REAL bytes once at load time
# (printf only interprets \033 in the format string, never in %s arguments),
# otherwise terminals print a literal "\033[0;33m".
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    UI_GREEN=''; UI_RED=''; UI_YELLOW=''; UI_CYAN=''; UI_BLUE=''
    UI_DIM=''; UI_BOLD=''; UI_NC=''
else
    UI_GREEN=$(printf '\033[0;32m'); UI_RED=$(printf '\033[0;31m')
    UI_YELLOW=$(printf '\033[0;33m'); UI_CYAN=$(printf '\033[0;36m')
    UI_BLUE=$(printf '\033[0;34m')
    UI_DIM=$(printf '\033[2m'); UI_BOLD=$(printf '\033[1m'); UI_NC=$(printf '\033[0m')
fi

if [ -n "${UI_ASCII:-}" ]; then
    UI_SYM_OK='ok'; UI_SYM_BAD='x'; UI_SYM_WARN='!'; UI_SYM_INFO='-'
    UI_SYM_ADD='+'; UI_SYM_ARROW='->'; UI_SYM_RULE='-'
else
    UI_SYM_OK='✔'; UI_SYM_BAD='✖'; UI_SYM_WARN='⚠'; UI_SYM_INFO='ℹ'
    UI_SYM_ADD='+'; UI_SYM_ARROW='→'; UI_SYM_RULE='─'
fi

# --- process log lines (openchamber-style labels) ------------------------------

_ui_label() {
    # _ui_label <color> <label> <message...>
    printf '  %s%s%s  %s\n' "$1" "$2" "${UI_NC}" "$3"
}

ui_info()    { _ui_label "$UI_BLUE"  'info   ' "$1"; }
ui_success() { _ui_label "$UI_GREEN" 'success' "$1"; }
ui_warn()    { _ui_label "$UI_YELLOW" 'warn   ' "$1"; }
ui_error()   { _ui_label "$UI_RED"   'error  ' "$1"; }

# Indented, dimmed detail line (belongs to the previous ui_* line).
ui_detail()  { printf '     %s%s%s\n' "$UI_DIM" "$1" "$UI_NC"; }

# Shows a command that would run (dimmed, prefixed with $).
ui_cmd()     { printf '  %s\$ %s%s\n' "$UI_DIM" "$1" "$UI_NC"; }

# --- sections & banners ---------------------------------------------------------

ui_section() {
    # Section rule:  ── Pre-flight ─────────────────
    _t="$1"
    printf '\n  %s%s── %s ──' "$UI_BOLD" "$UI_CYAN" "$_t"
    _i=$(( 40 - ${#_t} ))
    while [ "$_i" -gt 0 ]; do printf '%s' "$UI_SYM_RULE"; _i=$((_i - 1)); done
    printf '%s\n\n' "$UI_NC"
}

ui_banner() {
    # Slim banner (default variant).
    printf '\n  %s%s opencode permissions kit%s  %sv%s\n\n' \
        "$UI_BOLD" "$UI_CYAN" "$UI_NC" "$UI_DIM" "${1:-0.0.0}"
    printf '  %s%s%s\n\n' "$UI_DIM" "${2:-UID-separated agent hardening}" "$UI_NC"
}

ui_banner_box() {
    # Boxed banner (variant B).
    printf '\n  %s╭──────────────────────────────────────────╮%s\n' "$UI_CYAN" "$UI_NC"
    printf '  %s│%s  %sopencode permissions kit%s   %sv%s  %s│%s\n' \
        "$UI_CYAN" "$UI_NC" "$UI_BOLD" "$UI_NC" "$UI_DIM" "${1:-0.0.0}" "$UI_CYAN" "$UI_NC"
    printf '  %s│%s  %-40s%s%s│%s\n' \
        "$UI_CYAN" "$UI_NC" "${2:-UID-separated agent hardening}" "$UI_NC" "$UI_CYAN" "$UI_NC"
    printf '  %s╰──────────────────────────────────────────╯%s\n\n' "$UI_CYAN" "$UI_NC"
}

# --- inventory / checklist ------------------------------------------------------

_ui_item() {
    # _ui_item <color> <symbol> <label> <note>
    printf '  %s%s%s  %-30s %s\n' "$1" "$2" "$UI_NC" "$3" "$4"
}

ui_have()  { _ui_item "$UI_GREEN"  "$UI_SYM_OK"   "$1" "$2"; }  # present/ready
ui_add()   { _ui_item "$UI_CYAN"   "$UI_SYM_ADD"  "$1" "$2"; }  # will be added
ui_atten() { _ui_item "$UI_YELLOW" "$UI_SYM_WARN" "$1" "$2"; }  # needs attention
ui_miss()  { _ui_item "$UI_RED"    "$UI_SYM_BAD"  "$1" "$2"; }  # missing/blocked

# --- aligned key/value panels (status, summaries) -------------------------------

ui_kv() {
    # ui_kv <key> <value> [color-for-value]
    printf '  %-14s %s%s%s\n' "$1" "${3:-$UI_NC}" "$2" "$UI_NC"
}

ui_kv_warn() {
    # Like ui_kv, but with a warn symbol — value column aligns with ui_kv
    # (2 + 1 sym + 2 + 11 label + 1 space = same offset as 2 + 14 + 1).
    printf '  %s%s%s  %-11s %s%s%s\n' \
        "$UI_YELLOW" "$UI_SYM_WARN" "$UI_NC" "$1" "$UI_YELLOW" "$2" "$UI_NC"
}

# --- plan list (numbered) --------------------------------------------------------

ui_plan() {
    # ui_plan <n> <text> [note]
    printf '    %s%d%s  %-42s %s\n' "$UI_DIM" "$1" "$UI_NC" "$2" "${3:-}"
}

# --- questions --------------------------------------------------------------------

ui_ask() {
    # ui_ask "Question?" "default"  -> prints the answer on stdout.
    # The prompt goes to stderr so $(...) capture stays clean.
    # Reads stdin; EOF/empty -> default. Demo-safe (never blocks on pipes).
    _q="$1"; _d="${2:-}"
    if [ -n "$_d" ]; then
        printf '  %s [%s] > ' "$_q" "$_d" >&2
    else
        printf '  %s > ' "$_q" >&2
    fi
    IFS= read -r _ans || _ans=''
    [ -z "$_ans" ] && _ans="$_d"
    printf '%s\n' "$_ans"
}

ui_menu() {
    # ui_menu "Question?" <default-key> <"key|description"...> -> prints the chosen KEY.
    # The menu goes to stderr so $(...) capture stays clean.
    # Reads stdin; EOF/empty/unknown -> default. Demo-safe (never blocks on pipes).
    _q="$1"; _d="$2"; shift 2
    printf '  %s\n' "$_q" >&2
    for _opt in "$@"; do
        _k=${_opt%%|*}; _desc=${_opt#*|}
        if [ "$_k" = "$_d" ]; then
            printf '    %s[%s]%s  %s\n' "$UI_CYAN" "$_k" "$UI_NC" "$_desc" >&2
        else
            printf '     %s  %s\n' "$_k" "$_desc" >&2
        fi
    done
    printf '  > ' >&2
    IFS= read -r _ans || _ans=''
    _found=''
    for _opt in "$@"; do
        _k=${_opt%%|*}
        [ "$_ans" = "$_k" ] && _found=1
    done
    [ -z "$_found" ] && _ans="$_d"
    printf '%s\n' "$_ans"
}

# --- demo plumbing ----------------------------------------------------------------

ui_demo_notice() {
    printf '  %s%s DEMO — simulated output, nothing is executed.%s\n\n' \
        "$UI_YELLOW" "$UI_SYM_WARN" "$UI_NC"
}

sim() { sleep "${1:-0.3}"; }   # pretend to work
