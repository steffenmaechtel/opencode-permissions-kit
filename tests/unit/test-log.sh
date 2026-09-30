#!/bin/sh
# Unit tests for sh/log.sh — the shared audit log (review 0.0.39a C3: it
# had zero direct coverage). Verifies init modes (750 dir / 640 file), the
# one-line-per-event format, the 1 MB x 5 self-rotation, the keep bound,
# and the best-effort contract (an unwritable location never breaks the
# caller). Runs unprivileged: LOG_DIR/LOG_FILE are overridden after
# sourcing — the functions read the globals at call time.
# Run: sh tests/unit/test-log.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_SH="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/log.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Source the lib once per scenario (log() re-inits every call, but a
# fresh shell keeps the scenarios independent and the assertions local).
# log.sh assigns the defaults at SOURCE time, so the scenario values are
# saved before sourcing and restored right after — the functions read the
# globals at call time.
run_lib() {
    _d="$1/log" _f="$1/log/kit.log" _k=5
    if [ "$#" -ge 3 ]; then _m="$2" _c="$3"; else _m=1048576 _c="$2"; fi
    LOG_DIR="$_d" LOG_FILE="$_f" LOG_MAX_BYTES="$_m" LOG_KEEP="$_k" \
    sh -c '_d="$LOG_DIR" _f="$LOG_FILE" _m="$LOG_MAX_BYTES" _k="$LOG_KEEP"
        . "$1"
        LOG_DIR="$_d"; LOG_FILE="$_f"; LOG_MAX_BYTES="$_m"; LOG_KEEP="$_k"
        eval "$2"' x "$LOG_SH" "$_c"
}

echo ""
echo "Audit Log (log.sh) Tests"
echo "========================"
echo ""

# --- 1. init: dir 750, file 640, idempotent -------------------------------------

run_lib "$WORK" 'log "first"'
dir_mode=$(stat -c %a "$WORK/log" 2>/dev/null || echo "missing")
file_mode=$(stat -c %a "$WORK/log/kit.log" 2>/dev/null || echo "missing")
if [ "$dir_mode" = "750" ]; then
    pass "log_init creates the directory with mode 750"
else
    fail "log_init creates the directory with mode 750 (got ${dir_mode})"
fi
if [ "$file_mode" = "640" ]; then
    pass "log_init creates the file with mode 640"
else
    fail "log_init creates the file with mode 640 (got ${file_mode})"
fi

run_lib "$WORK" 'log "second"'
if [ "$(wc -l < "$WORK/log/kit.log")" = "2" ]; then
    pass "log() appends one line per event (idempotent init)"
else
    fail "log() appends one line per event (got $(wc -l < "$WORK/log/kit.log" 2>/dev/null || echo none) lines)"
fi

# --- 2. line format: <ISO-timestamp> [<script>] <message> -----------------------

line=$(tail -1 "$WORK/log/kit.log")
case "$line" in
    *[[]*[]]*"second") fmt=ok ;;
    *) fmt=bad ;;
esac
ts=$(printf '%s\n' "$line" | cut -d' ' -f1)
if [ "$fmt" = ok ] && printf '%s' "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$'; then
    pass "line format: ISO timestamp + [tag] + message"
else
    fail "line format: ISO timestamp + [tag] + message (got: $line)"
fi

# --- 3. rotation: size threshold creates .1, chain capped at LOG_KEEP -----------

run_lib "$WORK" 10 >/dev/null 2>&1 'log "big one"'
# the FIRST write creates a file already >= the tiny threshold (LOG_MAX_BYTES=10);
# the SECOND write's log_rotate sees size >= 10 and moves the old content to .1
run_lib "$WORK" 10 >/dev/null 2>&1 'log "overflow"'
if [ -f "$WORK/log/kit.log.1" ] && grep -q "big one" "$WORK/log/kit.log.1"; then
    pass "rotation: oversized file moves to .1 with content intact"
else
    fail "rotation: oversized file moves to .1 with content intact"
fi
if grep -q "overflow" "$WORK/log/kit.log" && ! grep -q "overflow" "$WORK/log/kit.log.1"; then
    pass "rotation: the new event lands in the fresh file"
else
    fail "rotation: the new event lands in the fresh file"
fi

# Seed .1 .. .4, force one more rotation: the chain must reach .5 (keep
# bound) and the freshest generation must be the previous .1.
for i in 1 2 3 4; do
    printf 'gen%s\n' "$i" > "$WORK/log/kit.log.$i"
done
run_lib "$WORK" 10 >/dev/null 2>&1 'log "chain"'
if [ -f "$WORK/log/kit.log.5" ] && [ ! -f "$WORK/log/kit.log.6" ]; then
    pass "rotation: chain capped at LOG_KEEP=5 (no .6 escapes)"
else
    fail "rotation: chain capped at LOG_KEEP=5 (no .6 escapes)"
fi
if grep -q "gen4" "$WORK/log/kit.log.5" && grep -q "gen1" "$WORK/log/kit.log.2"; then
    pass "rotation: generations shift by one (.4->.5, .1->.2)"
else
    fail "rotation: generations shift by one (.4->.5, .1->.2)"
fi

# Below the threshold: no rotation artifacts at all.
WORK2="$(mktemp -d)"
run_lib "$WORK2" 1048576 >/dev/null 2>&1 'log "small"'
if [ -f "$WORK2/log/kit.log" ] && [ ! -f "$WORK2/log/kit.log.1" ]; then
    pass "no rotation below the size threshold"
else
    fail "no rotation below the size threshold"
fi
rm -rf "$WORK2"

# --- 4. best-effort: unwritable location never breaks the caller ----------------

rc=0
out=$(LOG_DIR="/proc/definitely/not/writable" LOG_FILE="/proc/definitely/not/writable/x.log" \
    sh -c '. "$1"; LOG_DIR="$LOG_DIR"; LOG_FILE="$LOG_FILE"; log "unwritable" || echo "LOG-FAILED"' \
    x "$LOG_SH" 2>&1) || rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then
    pass "best-effort: unwritable location is silent and non-fatal"
else
    fail "best-effort: unwritable location is silent and non-fatal (rc=$rc out=$out)"
fi

# --- Summary ---------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
