#!/bin/sh
# Quote-strip class gate (issue #786): every install.conf VALUE reader
# in shipped files/** strips surrounding quotes at extraction.
#
# The class recurred through three review rounds (PR #785 a B5 fixed
# doctor's DEFAULT_USER; b A1 found the sweep enumeration false and
# fixed the three extraction helpers; c A1-c A3 found the remaining
# readers and the loop's scope brake channeled them into issue #786).
# Every wave fixed the sites its own sweep key found and missed the
# rest -- the literal-key greps missed helper-wrapped sites and
# continuation-wrapped operands. This suite is the learnings.md "When a
# rule fails" escalation: the invariant itself fails the suite, so the
# next unstripped reader reddens the unit lane instead of a review
# round.
#
# The scanner is tests/unit/lib/conf_strip_detect.py (the
# rider_detect/trap_detect house shape); this driver proves it
# discriminates BOTH directions on scratch copies of the real shapes
# (unstripped flagged, stripped clean, continuation join, tsx bare
# read, stale allowlist) before trusting its verdict over the shipped
# corpus, and pins the corpus clean.
# Run: sh tests/unit/test-conf-reader-strip.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
DETECT="$SCRIPT_DIR/lib/conf_strip_detect.py"
LIB="$REPO/files/opencode-permissions-kit-lib"

# Shared harness (issue #394): pass/fail + counters + the work registry
# (issue #395) -- the harness owns cleanup, no trap of our own.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)" || {
    echo "conf-strip gate: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

echo ""
echo "Conf Reader Quote-Strip Gate (issue #786)"
echo "========================================"
echo ""

# --- 1. the scanner discriminates both directions (executed, not inferred) ----
# Scratch copies of the REAL extraction shapes; the same code path the
# corpus scan runs decides each. Sabotage shape: the strip DELETED,
# never commented out (agent/gates.md -- an un-ridden grep would keep
# counting a comment).

cat >"$WORK/probe-unstripped.sh" <<'EOF'
_v=$(sed -n 's/^KIT_CHANNEL=//p' "$conf" 2>/dev/null | tail -1 || true)
EOF
_rows=$(python3 "$DETECT" "$WORK/probe-unstripped.sh")
if printf '%s' "$_rows" | grep -q 'unstripped conf extraction'; then
    pass "scanner: an unstripped extraction is flagged (red direction)"
else
    fail "scanner: unstripped probe not flagged (rows=$_rows)"
fi

cat >"$WORK/probe-stripped.sh" <<'EOF'
_v=$(sed -n 's/^KIT_CHANNEL=//p' "$conf" 2>/dev/null | tail -1 | sed 's/^"//;s/"$//' || true)
EOF
_rows=$(python3 "$DETECT" "$WORK/probe-stripped.sh")
if [ -z "$_rows" ]; then
    pass "scanner: a stripped extraction stays clean (green direction)"
else
    fail "scanner: stripped probe flagged (rows=$_rows)"
fi

cat >"$WORK/probe-wrap.sh" <<'EOF'
_v=$(sed -n 's/^GITDIR_STORAGE=//p' \
    "$conf" 2>/dev/null | tail -n 1)}
EOF
_rows=$(python3 "$DETECT" "$WORK/probe-wrap.sh")
if printf '%s' "$_rows" | grep -q 'unstripped conf extraction'; then
    pass "scanner: continuation-wrapped extractions join before matching"
else
    fail "scanner: wrapped probe not flagged (rows=$_rows)"
fi

cat >"$WORK/probe.tsx" <<'EOF'
backend = /^CONTAINER_BACKEND=(.+)$/m.exec(conf)?.[1]?.trim() ?? ""
EOF
_rows=$(python3 "$DETECT" "$WORK/probe.tsx")
if printf '%s' "$_rows" | grep -q 'unstripped conf regex read'; then
    pass "scanner: a bare tsx regex read is flagged"
else
    fail "scanner: bare tsx probe not flagged (rows=$_rows)"
fi

cat >"$WORK/probe-ok.tsx" <<'EOF'
const val = (re: RegExp) => re.exec(conf)?.[1]?.trim()?.replace(/^"|"$/g, "") ?? ""
EOF
_rows=$(python3 "$DETECT" "$WORK/probe-ok.tsx")
if [ -z "$_rows" ]; then
    pass "scanner: the strip-helper tsx read stays clean"
else
    fail "scanner: strip-helper tsx flagged (rows=$_rows)"
fi

# A stale allowlist entry must red, not pass silently: a file wearing
# an allowlisted basename WITHOUT its allowlisted site leaves the entry
# stale (the allowlist must not outlive its sites).
mkdir -p "$WORK/stale"
cat >"$WORK/stale/install-core.sh" <<'EOF'
echo "no os-release reads here"
EOF
_rows=$(python3 "$DETECT" "$WORK/stale/install-core.sh")
if printf '%s' "$_rows" | grep -q 'stale allowlist entry'; then
    pass "scanner: a stale allowlist entry is reported"
else
    fail "scanner: stale allowlist not reported (rows=$_rows)"
fi

# The empty scan set is not a clean verdict (trap_detect's reference
# shape): no files given -> rc 1, message on stderr, stdout empty.
_rc=0
_rows=$(python3 "$DETECT" 2>"$WORK/nofiles.err") || _rc=$?
if [ "$_rc" -eq 1 ] && [ -z "$_rows" ] && grep -q 'no files given' "$WORK/nofiles.err"; then
    pass "scanner: the empty scan set fails loud (rc 1, stderr message)"
else
    fail "scanner: empty scan set (rc=$_rc rows=$_rows err=$(cat "$WORK/nofiles.err"))"
fi

# --- 2. the shipped corpus: clean ---------------------------------------------
# The scan set is every shipped shell surface (entry, umask.sh, bin/,
# management/, sh/, git-heal scripts and hooks) plus the two tui TSX
# regex readers. set -- keeps every path quoted (no unquoted
# expansion); the detector sees the list as arguments.
set --
for f in "$REPO/files/install.sh" "$REPO/files/etc/umask.sh" \
    "$LIB"/bin/* \
    "$LIB"/management/*.sh \
    "$LIB"/sh/*.sh \
    "$LIB"/git-heal/heal-index-head \
    "$LIB"/git-heal/hooks/* \
    "$LIB"/tui/kit-mode.tsx \
    "$LIB"/tui/kit-mode-2x.tsx; do
    [ -f "$f" ] && set -- "$@" "$f"
done

_rows=$(python3 "$DETECT" "$@")
if [ -z "$_rows" ]; then
    pass "corpus: every shipped conf extraction carries the quote-strip"
else
    fail "corpus: unstripped conf extraction(s) remain ($(printf '%s' "$_rows" | tr '\n' ';'))"
fi

# Non-vacuity floors (not rosters): the corpus must still CONTAIN
# extraction sites and a sane file count -- a repo reorg that empties
# the scan set or the reader class must redden here, not pass green
# over zero sites.
_stats=$(python3 "$DETECT" --stats "$@")
_nfiles=$(printf '%s' "$_stats" | sed -n 's/^files //p')
_nsites=$(printf '%s' "$_stats" | sed -n 's/^sites //p')
if [ "${_nsites:-0}" -ge 1 ] && [ "${_nfiles:-0}" -ge 10 ]; then
    pass "corpus: scan is non-vacuous (${_nsites} sites over ${_nfiles} files)"
else
    fail "corpus: scan set collapsed (sites=${_nsites:-0} files=${_nfiles:-0})"
fi

suite_done "tests"
