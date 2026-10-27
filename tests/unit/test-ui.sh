#!/bin/sh
# Unit tests for the shared UI helpers (files/opencode-permissions-kit-lib/sh/ui.sh).
# Covers: syntax, NO_COLOR / non-tty color suppression, UI_ASCII fallback,
# symbol defaults, output formats, alignment, and the ui_ask/ui_menu defaults.
# No root required. Run: sh tests/unit/test-ui.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UI="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# ui_ask/ui_menu/ui_confirm read /dev/tty FIRST (design: prompts survive
# `curl | bash` installs with redirected stdin). On an interactive terminal
# that makes these tests read the developer's keyboard instead of the piped
# input (invisible hangs, wrong results). setsid detaches the controlling
# tty, so the helpers fall back to stdin exactly as in CI.
command -v setsid >/dev/null 2>&1 || {
    echo "test-ui: setsid (util-linux) is required for hermetic runs" >&2
    exit 1
}

# Runs a snippet with the lib sourced; stdout captured, stdin /dev/null,
# no controlling tty (colors off, reads hit EOF).
run_ui() {
    setsid sh -c '. "$1"; eval "$2"' x "$UI" "$1" </dev/null 2>/dev/null
}

echo ""
echo "UI Helper Tests"
echo "==============="
echo ""

# --- syntax --------------------------------------------------------------------
check "ui.sh passes sh -n" sh -n "$UI"

# --- color suppression ------------------------------------------------------------
# Piped stdout (no tty) and NO_COLOR must both yield zero ESC bytes.
ESC=$(printf '\033')
out=$(run_ui 'ui_info x; ui_success y; ui_warn z; ui_error e')
if printf '%s' "$out" | LC_ALL=C grep -q "$ESC"; then
    fail "non-tty stdout: no ESC byte in output"
else
    pass "non-tty stdout: no ESC byte in output"
fi

out=$(NO_COLOR=1 run_ui 'ui_info x')
if printf '%s' "$out" | LC_ALL=C grep -q "$ESC"; then
    fail "NO_COLOR: no ESC byte in output"
else
    pass "NO_COLOR: no ESC byte in output"
fi

# tty path (real colors) — only testable with a pty; use script(1) when present.
if command -v script >/dev/null 2>&1; then
    if script -qec "sh -c '. $UI; ui_info x'" /dev/null 2>/dev/null | LC_ALL=C grep -q "$ESC"; then
        pass "tty stdout: ESC sequences present (script(1))"
    else
        fail "tty stdout: ESC sequences present (script(1))"
    fi
else
    echo "  (skip) tty test needs script(1)"
fi

# --- symbols -----------------------------------------------------------------------
out=$(run_ui 'printf "%s\n" "$UI_SYM_OK $UI_SYM_WARN $UI_SYM_BAD"')
check "default symbols are Unicode" \
    sh -c "printf %s \"\$1\" | grep -q '✔'" _ "$out"

out=$(UI_ASCII=1 run_ui 'printf "%s\n" "$UI_SYM_OK $UI_SYM_WARN $UI_SYM_BAD"')
check "UI_ASCII=1 forces ASCII fallback" \
    sh -c "printf %s \"\$1\" | grep -q 'ok' && ! printf %s \"\$1\" | grep -q '✔'" _ "$out"

# --- log line format ------------------------------------------------------------------
out=$(run_ui 'ui_info "hello"; ui_success "done"; ui_warn "careful"; ui_error "broke"')
check "labeled lines carry the labels" \
    sh -c "printf %s \"\$1\" | grep -q 'info' && printf %s \"\$1\" | grep -q 'success' && printf %s \"\$1\" | grep -q 'warn' && printf %s \"\$1\" | grep -q 'error'" _ "$out"

out=$(run_ui 'ui_detail "note"')
check "detail line is indented under the label column" \
    sh -c "printf %s \"\$1\" | grep -q '^     note\$'" _ "$out"

# --- inventory/checklist ------------------------------------------------------------------
out=$(run_ui 'ui_have "curl" "present"; ui_add "user" "will be created"; ui_atten "/mnt/c" "world-readable"; ui_miss "ddev" "not installed"')
check "inventory: have line"  sh -c "printf %s \"\$1\" | grep -q '  ✔  curl'" _ "$out"
check "inventory: add line"   sh -c "printf %s \"\$1\" | grep -q '  +  user'" _ "$out"
check "inventory: warn line"  sh -c "printf %s \"\$1\" | grep -q '  ⚠  /mnt/c'" _ "$out"
check "inventory: miss line"  sh -c "printf %s \"\$1\" | grep -q '  ✖  ddev'" _ "$out"

# --- key/value alignment -----------------------------------------------------------------------
# ASCII mode makes byte position == display column (the warn symbol is
# multi-byte UTF-8 but one column wide).
out=$(UI_ASCII=1 run_ui 'ui_kv "Backend" "docker-rootless"; ui_kv_warn "WSL2" "pending wsl --shutdown"')
p1=$(printf '%s\n' "$out" | sed -n '1s/^\(  Backend *\).*/\1/p' | wc -c)
p2=$(printf '%s\n' "$out" | sed -n '2s/^\(  !  WSL2 *\).*/\1/p' | wc -c)
check "ui_kv and ui_kv_warn value columns align" \
    sh -c "[ \"\$(($p1 - $p2))\" -eq 0 ]"

# --- banner & section ----------------------------------------------------------------------------
out=$(run_ui 'ui_banner "9.9.9" "subtitle"')
check "banner prints kit name + version + subtitle" \
    sh -c "printf %s \"\$1\" | grep -q 'opencode permissions kit' && printf %s \"\$1\" | grep -q 'v9.9.9' && printf %s \"\$1\" | grep -q 'subtitle'" _ "$out"

out=$(run_ui 'ui_section "Pre-flight"')
check "section rule contains the title" \
    sh -c "printf %s \"\$1\" | grep -q -- '── Pre-flight ──'" _ "$out"

# --- questions ------------------------------------------------------------------------------------
ans=$(run_ui 'ui_ask "Proceed?" "yes"')
check "ui_ask returns the default on EOF" [ "$ans" = "yes" ]

ans=$(printf 'no\n' | setsid sh -c ". \"\$1\"; ui_ask \"Proceed?\" \"yes\"" _ "$UI" 2>/dev/null)
check "ui_ask returns typed input" [ "$ans" = "no" ]

ans=$(printf ' name \n' | setsid sh -c ". \"\$1\"; ui_ask \"Proceed?\" \"yes\"" _ "$UI" 2>/dev/null)
check "ui_ask: edge whitespace trimmed from typed input (#189 a W2)" [ "$ans" = "name" ]

ans=$(run_ui 'ui_menu "Mode?" "1" "1|Standard" "2|Advanced"')
check "ui_menu returns the default key on EOF" [ "$ans" = "1" ]

ans=$(printf '2\n' | setsid sh -c ". \"\$1\"; ui_menu \"Mode?\" \"1\" \"1|Standard\" \"2|Advanced\"" _ "$UI" 2>/dev/null)
check "ui_menu returns the chosen key" [ "$ans" = "2" ]

ans=$(printf ' 2\n' | setsid sh -c ". \"\$1\"; ui_menu \"Mode?\" \"1\" \"1|Standard\" \"2|Advanced\"" _ "$UI" 2>/dev/null)
check "ui_menu: padded key ' 2' trimmed to the chosen key (#189 a W2)" [ "$ans" = "2" ]

ans=$(printf 'zzz\n' | setsid sh -c ". \"\$1\"; ui_menu \"Mode?\" \"1\" \"1|Standard\" \"2|Advanced\"" _ "$UI" 2>/dev/null)
check "ui_menu falls back to default on unknown input" [ "$ans" = "1" ]

# ui_confirm: unknown input falls back to the DEFAULT (0.0.44a V17) —
# the case used to return "no" even when the default was y, so a stray
# trailing space after "y" declined what the prompt's own default
# promised (conventions.md: "unknown input falls back to the default").
# Since #189 a W2 the trailing space no longer reaches the arms: answers
# are edge-trimmed in _ui_read, so 'y ' is EXPLICIT input (pin below).
_uc_rc=0
printf 'y \n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"y\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: trailing-space 'y ' trimmed to an explicit yes (#189 a W2)" [ "$_uc_rc" -eq 0 ]
_uc_rc=0
printf 'garbage\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"y\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: unknown input falls back to a y default (V17)" [ "$_uc_rc" -eq 0 ]
_uc_rc=0
printf 'garbage\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"n\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: unknown input falls back to an n default (V17)" [ "$_uc_rc" -ne 0 ]
_uc_rc=0
printf 'n\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"y\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: explicit no still declines under a y default" [ "$_uc_rc" -ne 0 ]

# Padded answers are explicit answers (#189 a W2): _ui_read trims edge
# whitespace, so ' y' accepts under an n default and 'no ' declines
# under a y default — both used to fall to the default instead (the
# stdin-fallback read is exercised here; the pty paths of opk's
# fallback and prompt_yn are pinned in their own suites).
_uc_rc=0
printf ' y\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"n\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: padded ' y' accepted under an n default (#189 a W2)" [ "$_uc_rc" -eq 0 ]
_uc_rc=0
printf 'no \n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"y\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: padded 'no ' declines under a y default (#189 a W2)" [ "$_uc_rc" -ne 0 ]

# ui_confirm shape + case-insensitivity (issue #187 B/C): the prompt
# renders `  <question> [Y/n] ` (output-style indent, NO extra marker,
# trailing space before the cursor) — same shape as uninstall's
# prompt_yn and opk's fallback; mixed-case answers must be honored,
# not silently mapped to the default (the opk fallback bug class).
_uc_rc=0
printf 'Yes\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"n\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: mixed-case Yes accepted under an n default (issue #187 C class)" [ "$_uc_rc" -eq 0 ]
_uc_rc=0
printf 'No\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"y\"" _ "$UI" >/dev/null 2>&1 || _uc_rc=$?
check "ui_confirm: mixed-case No declines under a y default (issue #187 C class)" [ "$_uc_rc" -ne 0 ]
_uc_err=$(mktemp)
# Trap the receiver on exit and signals (#283): no set -e here, but the
# suite had no trap at all — a signal between creation and the inline
# rm -f leaked the scratch file.
trap 'rm -f "${_uc_err:-}"' EXIT INT TERM
printf 'n\n' | setsid sh -c ". \"\$1\"; ui_confirm \"Proceed?\" \"n\"" _ "$UI" 2>"$_uc_err" >/dev/null || :
if grep -qF '  Proceed? [y/N] ' "$_uc_err" && ! grep -qF '[?]' "$_uc_err"; then
    pass "ui_confirm prompt shape: '  <question> [y/N] ' — no marker (issue #187 B)"
else
    fail "ui_confirm prompt shape: '  <question> [y/N] ' — no marker (issue #187 B)"
fi
rm -f "$_uc_err"

# --- no-tty gate (streamed installs, 0.0.39b C6 / 0.0.39e C8) ----------------------
# UI_NO_STDIN_FALLBACK=1 + no controlling tty: the read must HARD-EXIT
# with guidance instead of consuming piped stdin (which, in a streamed
# install, is the script body itself). Without the env var the pipe-fed
# fallback keeps working (tests above).
gate_rc=0
gate_out=$(printf 'yes\n' | UI_NO_STDIN_FALLBACK=1 setsid sh -c ". \"\$1\"; ui_ask \"Proceed?\" \"no\"" _ "$UI" 2>&1) || gate_rc=$?
check "no-tty gate: UI_NO_STDIN_FALLBACK hard-exits with guidance" \
    sh -c "[ \"\$1\" -ne 0 ] && printf '%s' \"\$2\" | grep -q 'no terminal available'" _ "$gate_rc" "$gate_out"

menu_err=$(setsid sh -c ". \"\$1\"; ui_menu \"Mode?\" \"1\" \"1|Standard\"" _ "$UI" 2>&1 >/dev/null </dev/null)
check "ui_menu prints the menu to stderr" \
    sh -c "printf %s \"\$1\" | grep -q 'Mode?'" _ "$menu_err"

# --- plan list ----------------------------------------------------------------------------------------
out=$(run_ui 'ui_plan 3 "Apply ACLs" "group rwx"')
check "plan line is numbered and carries the note" \
    sh -c "printf %s \"\$1\" | grep -q '^    3  Apply ACLs'" _ "$out"

# --- severity counters (issue #158) ---------------------------------------------------------------
# Counting must be color-blind: these run in $(...) (non-tty => colors
# resolve to empty strings) — if the helpers counted color bytes, every
# count here would come out 0.
out=$(run_ui 'ui_kv_ok "a" "x"; ui_kv_warn "b" "y"; ui_kv_bad "c" "z"; ui_have "d" "1"; ui_atten "e" "2"; ui_miss "f" "3"; ui_warn "w"; ui_error "E"; printf "OK=%s WARN=%s BAD=%s" "$UI_ROWS_OK" "$UI_ROWS_WARN" "$UI_ROWS_BAD"')
check "counters bump per severity helper (colors off)" \
    sh -c "printf %s \"\$1\" | grep -q 'OK=2 WARN=3 BAD=3'" _ "$out"

# UI_SILENT=1: every printer is a no-op, the counters keep counting. The
# warn row is the trap: its silent guard sits AFTER the increment — a
# muted row is still a finding (status.sh --short builds on exactly
# that).
out=$(UI_SILENT=1 run_ui 'ui_kv_ok "a" "x"; ui_kv_warn "b" "y"; ui_kv_bad "c" "z"; ui_have "d" "1"; ui_atten "e" "2"; ui_miss "f" "3"; ui_warn "w"; ui_error "E"; ui_section "S"; ui_banner; ui_detail "d"; printf "OK=%s WARN=%s BAD=%s" "$UI_ROWS_OK" "$UI_ROWS_WARN" "$UI_ROWS_BAD"')
check "UI_SILENT: no output, counters still advance" \
    sh -c "printf %s \"\$1\" | grep -q 'OK=2 WARN=3 BAD=3'" _ "$out"
check "UI_SILENT: printers stay mute (only the printf survives)" \
    sh -c "[ \"\$(printf %s \"\$1\" | grep -c .)\" -eq 1 ]" _ "$out"

# plain ui_kv is an informational row — never counted (not a finding)
out=$(run_ui 'ui_kv "k" "v"; printf "OK=%s WARN=%s BAD=%s" "$UI_ROWS_OK" "$UI_ROWS_WARN" "$UI_ROWS_BAD"')
check "plain ui_kv rows stay uncounted" \
    sh -c "printf %s \"\$1\" | grep -q 'OK=0 WARN=0 BAD=0'" _ "$out"

# NO_COLOR must not disable counting either (same class, explicit env)
out=$(NO_COLOR=1 run_ui 'ui_kv_warn "b" "y"; printf "WARN=%s" "$UI_ROWS_WARN"')
check "NO_COLOR=1 keeps counting" \
    sh -c "printf %s \"\$1\" | grep -q 'WARN=1'" _ "$out"

# --- Summary --------------------------------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
