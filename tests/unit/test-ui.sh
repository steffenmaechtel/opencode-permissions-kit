#!/bin/sh
# Unit tests for the shared UI helpers (files/opencode-permissions-kit-lib/sh/ui.sh).
# Covers: syntax, NO_COLOR / non-tty color suppression, UI_ASCII fallback,
# symbol defaults, output formats, alignment, and the ui_ask/ui_menu defaults.
# No root required. Run: sh tests/unit/test-ui.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UI="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"

# Shared harness (issue #394 adoption): pass/fail, colors, counters
# and the summary gate live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

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
check "inventory: have line" sh -c "printf %s \"\$1\" | grep -q '  ✔  curl'" _ "$out"
check "inventory: add line" sh -c "printf %s \"\$1\" | grep -q '  +  user'" _ "$out"
check "inventory: warn line" sh -c "printf %s \"\$1\" | grep -q '  ⚠  /mnt/c'" _ "$out"
check "inventory: miss line" sh -c "printf %s \"\$1\" | grep -q '  ✖  ddev'" _ "$out"

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
_uc_err=$(work_new_file) || {
    echo "ui tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
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
if printf %s "$menu_err" | grep -q 'Mode?'; then
    pass "ui_menu prints the menu to stderr"
else
    fail "ui_menu prints the menu to stderr"
fi

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

# --- consumer used-set guards (issue #456) -----------------------------------------
# Every ui.sh consumer guards the functions it (and its phase core, if
# any) actually calls, right after resolving ui.sh — a PRESENT-but-older
# ui.sh (the #158 shape: deployed lib predating ui_kv_ok/ui_kv_bad)
# must refuse loud instead of silently dropping rows / rc-127ing
# mid-run. Riders per consumer, both directions over comment-stripped
# sources (conventions.md "Source-counting pins"), BOUNDARY-ANCHORED
# like the #452 core riders; plus the behavioral pair (real lib passes,
# truncated lib refuses) driven in fresh children. Every consumer that
# has a phase core names it in the third field — an empty core field
# silently blinds the used direction to the core's calls (#461 a S10),
# and the guard-removal awk matches by plain STRING PREFIX (index==1):
# an -v-carried regex like "\\(\\) \\{" loses its backslashes to -v
# escape processing and never matches the def line, leaving the guard
# body in the token stream — the stale direction goes vacuous (#461 a
# S8, same failure family as the tr -d '[:space:]()' concatenation).
LIBDIR_FILES="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib"
_ui_consumers="install:$SCRIPT_DIR/../../files/install.sh:$LIBDIR_FILES/sh/install-core.sh \
status:$LIBDIR_FILES/management/status.sh:$LIBDIR_FILES/sh/status-core.sh \
update:$LIBDIR_FILES/management/update.sh:$LIBDIR_FILES/sh/update-core.sh \
config:$LIBDIR_FILES/management/config.sh: \
doctor:$LIBDIR_FILES/management/doctor.sh:$LIBDIR_FILES/sh/doctor-core.sh"

# ui tokens referenced by an entry (+ optional core), comment-stripped,
# with the consumer's OWN guard function removed so the rider cannot
# match the guard list against itself.
_ui_used_tokens() {
    _ut_entry="$1"
    _ut_core="$2"
    _ut_guard="$3"
    {
        live_src "$_ut_entry" |
            awk -v d="${_ut_guard}() {" '
                index($0, d) == 1 { infn = 1 }
                infn && /^}/ { infn = 0; next }
                !infn { print }
            '
        if [ -n "$_ut_core" ]; then
            live_src "$_ut_core"
        fi
    } | grep -oE '(^|[^a-zA-Z0-9_])ui_[a-z_0-9]+' | grep -oE 'ui_[a-z_0-9]+$' | sort -u
}

for _uc in $_ui_consumers; do
    _uc_name=${_uc%%:*}
    _uc_rest=${_uc#*:}
    _uc_entry=${_uc_rest%%:*}
    _uc_core=${_uc_rest#*:}
    _uc_guard="${_uc_name}_ui_pairing_guard"
    _uc_gsrc="$(extract_func "$_uc_entry" "$_uc_guard")"
    if [ -n "$_uc_gsrc" ]; then
        pass "$_uc_name: ${_uc_guard} extractable (#456)"
    else
        fail "$_uc_name: ${_uc_guard} extractable from $(basename "$_uc_entry") (#456)"
        continue
    fi
    _uc_gs="$(printf '%s\n' "$_uc_gsrc" | sed 's/^[[:space:]]*#.*$//')"
    # wiring pin: a guard defined but never CALLED protects nothing —
    # the entry must invoke it right after its ui.sh resolution (the
    # shape every core pairing guard already carries).
    if live_src "$_uc_entry" | grep -qF "${_uc_guard} || exit 1"; then
        pass "$_uc_name: entry wires ${_uc_guard} after the ui.sh resolution (#456)"
    else
        fail "$_uc_name: $(basename "$_uc_entry") must call ${_uc_guard} || exit 1 (#456)"
    fi
    # rider, used direction: every ui token the run references must sit
    # in the guard list (emptiness probe per #455 a C2 — an empty
    # extraction must not pass vacuously).
    _uc_missing=""
    _uc_used="$(_ui_used_tokens "$_uc_entry" "$_uc_core" "$_uc_guard")"
    [ -n "$_uc_used" ] || _uc_missing="(used-token extraction empty)"
    for _uf in $_uc_used; do
        printf '%s\n' "$_uc_gs" | grep -qE "(^|[[:space:]])$_uf([[:space:];]|\$)" ||
            _uc_missing="$_uc_missing $_uf"
    done
    if [ -z "$_uc_missing" ]; then
        pass "$_uc_name: ui guard list covers every ui call the run makes (#456)"
    else
        fail "$_uc_name: ui functions called but absent from the guard:$_uc_missing (#456)"
    fi
    # rider, stale direction: every guard-list entry must be referenced
    # somewhere (a stale entry pins a function nothing calls).
    _uc_stale=""
    for _uf in $(printf '%s\n' "$_uc_gs" | grep -oE '(^|[^a-zA-Z0-9_])ui_[a-z_0-9]+' |
        grep -oE 'ui_[a-z_0-9]+$' | sort -u); do
        [ -n "$(printf '%s\n' "$_uc_used" | grep -xF "$_uf")" ] ||
            _uc_stale="$_uc_stale $_uf"
    done
    if [ -z "$_uc_stale" ]; then
        pass "$_uc_name: ui guard list carries no stale entry (#456)"
    else
        fail "$_uc_name: guard entries nothing calls:$_uc_stale (#456)"
    fi
    # behavioral pair in fresh children: the real lib passes.
    _uc_full=$(sh -c 'eval "$1"; . "$2"; "$3"; echo "rc=$?"' _ "$_uc_gsrc" "$UI" "$_uc_guard" 2>&1)
    if printf '%s' "$_uc_full" | grep -q 'rc=0'; then
        pass "$_uc_name: ui guard passes against the real ui.sh (#456)"
    else
        fail "$_uc_name: ui guard must pass against the real ui.sh (out=$_uc_full) (#456)"
    fi
    # ... and a truncated lib (first list entry deleted) refuses loud,
    # naming the function — the #158 shape made loud.
    _uc_trunc="$(work_new_file)"
    awk '
        $0 ~ /^ui_info\(\) \{/ { infn = 1 }
        infn && /^}/ { infn = 0; next }
        !infn { print }
    ' "$UI" >"$_uc_trunc"
    _uc_tr_rc=0
    _uc_tr_out="$(sh -c 'eval "$1"; . "$2"; "$3"' _ "$_uc_gsrc" "$_uc_trunc" "$_uc_guard" 2>&1)" ||
        _uc_tr_rc=$?
    # B2 (#461 b): the repair hint is STATUS's documented contract
    # (docs/reference/cli.md's wiring-abort row) — the other consumers'
    # guards keep their own refusal wording, no docs row promises a
    # hint there.
    if [ "$_uc_tr_rc" -eq 1 ] &&
        printf '%s' "$_uc_tr_out" | grep -qF "function 'ui_info' missing from ui.sh" &&
        { [ "$_uc_name" != status ] ||
            printf '%s' "$_uc_tr_out" | grep -qF "fix: sudo opk update"; }; then
        pass "$_uc_name: ui guard refuses a truncated ui.sh naming ui_info (#456, #461 b B2)"
    else
        fail "$_uc_name: ui guard must refuse a truncated ui.sh (status: with the repair hint) (rc=$_uc_tr_rc out=$_uc_tr_out) (#456, #461 b B2)"
    fi
done

# --- Summary --------------------------------------------------------------------------------------------
suite_done "tests"
