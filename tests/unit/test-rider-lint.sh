#!/bin/sh
# test-rider-lint.sh -- invariant suite (#460): the comment-strip
# rider idiom lives in exactly one place.
#
# Rule 1 (gating): no file-operand inline strip rider in
# tests/unit/test-*.sh. Every `sed 's/^[[:space:]]*#.*$//' <operand>`
# (or its double-quoted sh -c variant) re-introduces the pre-#460
# idiom that accumulated 223 inline sites before centralization; the
# canonical rider is live_src / check_live (tests/unit/lib/harness.sh,
# conventions.md "Source-counting pins"). Sanctioned non-live_src
# shapes, not flagged:
#   - stdin/block strips: `... | sed 'STRIP'` with NO file operand --
#     stripping an extracted block (extract_func output) rides inline;
#     live_src is files-only by design
#   - full-comment lines (documentation mentions)
#   - lib/harness.sh (the helper itself) and this suite's own detector
#     definitions (self-allowlist, the same exception every invariant
#     suite grants its own machinery)
#
# Rule 2 (measured 2026-11-11, deliberately NOT gating yet): the
# strict `check "desc" grep ... "$SRCVAR"` shape over a registered
# source-path variable must be check_live -- 66 pre-existing sites
# today (the #460 census wave converts them). It becomes this suite's
# closing invariant in that wave; recorded here so the extension lands
# in the suite built for it.
#
# Discrimination arms (scratch fixtures, run BEFORE the tree sweep):
#   - a planted single-quoted file-operand rider -> flagged
#   - a planted double-quoted rider (both $ variants) -> flagged
#   - a stdin-pipe strip, a full-comment rider line, a live_src call
#     -> not flagged
# Sabotage (committed tree, then restore + re-run green): delete the
# hit arm from the awk detector -> the planted-rider arms go red while
# the sweep passes vacuously only if the arms are gone too.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/harness.sh"

# Detector: literal index() over the three historical byte forms
# (single-quoted; double-quoted \$ inside sh -c code; double-quoted
# plain $). Built from pieces so this suite's own source never
# contains the contiguous rider bytes.
_rh_core='s/^[[:space:]]*#.*'
_rh_p1="sed '"${_rh_core}'$//'"' "
_rh_p2='sed "s/^[[:space:]]*#.*\$//" '
_rh_p3='sed "s/^[[:space:]]*#.*$//" '

# _rider_hits <file>: prints "<NR>: <line>" for every file-operand
# inline rider. Full-comment lines are skipped; an operand start is
# any next byte except the command terminators (|);& ) and EOL --
# exactly the stdin/block-strip shapes. awk -v processes backslash
# escapes in assigned values, so backslashes are doubled on the way
# in (the \$ byte of the sh -c form survives as \$).
_rh_av() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }
_rider_hits() {
    awk -v p1="$(_rh_av "$_rh_p1")" -v p2="$(_rh_av "$_rh_p2")" \
        -v p3="$(_rh_av "$_rh_p3")" -v f="$1" '
        /^[[:space:]]*#/ { next }
        {
            hit = 0
            if (i = index($0, p1)) {
                c = substr($0, i + length(p1), 1)
                if (c != "" && c !~ /[|);&]/) hit = 1
            }
            if (!hit && (i = index($0, p2))) {
                c = substr($0, i + length(p2), 1)
                if (c != "" && c !~ /[|);&]/) hit = 1
            }
            if (!hit && (i = index($0, p3))) {
                c = substr($0, i + length(p3), 1)
                if (c != "" && c !~ /[|);&]/) hit = 1
            }
            if (hit) printf "%s:%d: %s\n", f, NR, $0
        }
    ' "$1"
}

echo ""
echo "Rider Lint (comment-strip idiom, issue #460)"
echo "============================================"
echo ""

# --- 1. discrimination arms (scratch fixtures) ---------------------------------
_cell="$(work_new)"
_rh_oper='$F'
printf '%s\n' "if sed '${_rh_core}\$//' \"${_rh_oper}\" | grep -q x; then :; fi" \
    >"$_cell/single.sh"
printf '%s\n' "sh -c 'sed \"s/^[[:space:]]*#.*\\\$//\" \"\$1\" | grep -qF p' _ \"\$F\"" \
    >"$_cell/doublesh.sh"
printf '%s\n' "sh -c 'sed \"s/^[[:space:]]*#.*\$//\" \"\$1\" | grep -qF p' _ \"\$F\"" \
    >"$_cell/dollar.sh"
printf '%s\n' "_blk=\$(printf '%s\n' \"\$B\" | sed '${_rh_core}\$//')" \
    >"$_cell/stdin.sh"
printf '%s\n' "# doc: sed '${_rh_core}\$//' \"\$F\" | grep -q x" \
    >"$_cell/comment.sh"
printf '%s\n' 'live_src "$F" | grep -q x' >"$_cell/livesrc.sh"

_n="$(_rider_hits "$_cell/single.sh" | wc -l | tr -d ' ')"
check "planted single-quoted rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/doublesh.sh" | wc -l | tr -d ' ')"
check "planted double-quoted \\\$ rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/dollar.sh" | wc -l | tr -d ' ')"
check "planted double-quoted \$ rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/stdin.sh" | wc -l | tr -d ' ')"
check "stdin/block strip stays unflagged" test "$_n" = 0
_n="$(_rider_hits "$_cell/comment.sh" | wc -l | tr -d ' ')"
check "full-comment rider mention stays unflagged" test "$_n" = 0
_n="$(_rider_hits "$_cell/livesrc.sh" | wc -l | tr -d ' ')"
check "a live_src call stays unflagged" test "$_n" = 0

# --- 2. tree sweep --------------------------------------------------------------
# Every suite except this one (self-allowlist, header). lib/ is not
# matched by the glob.
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(_rider_hits "$_f")"
    if [ -n "$_hits" ]; then
        fail "inline file-operand rider(s) in $(basename "$_f") -- use live_src"
        echo "$_hits" | sed 's/^/        /'
        _total=$((_total + 1))
    fi
done
if [ "$_total" -eq 0 ]; then
    pass "no inline file-operand riders in tests/unit (rule 1, #460)"
fi

suite_done "rider lint tests"
