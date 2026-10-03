#!/bin/sh
# test-line-length.sh -- line-length ratchet over the shipped scripts and
# the CI workflows.
#
# Target limit: 120 CONTENT columns (pragmatic shell upper bound -- 80 is
# artificially narrow with long flags, paths and --option=value
# constructs). The metric strips leading whitespace first (0.0.41a F4):
# indentation is structure, not content -- punishing nesting depth with
# reflows puts pressure on exactly the wrapped-string spots that have a
# documented bug history (0.0.39o C1: spaces lost at adjacent-string
# wraps when lines were re-broken for width). Content-width keeps the
# ratchet's growth guarantee while making (re-)indentation free.
# The tree is NOT at zero either way: at adoption (2026-10-01) the
# shipped files carried ~207 lines over 120 in 18 files, and the
# workflow chmod inventory lines of that era were 2k+ chars single
# lines (those lists are gone since issue #123 — exec bits live in the
# git index). A hard limit
# would fail on the spot, so this is a RATCHET:
#
#   - the baseline file next to this test records, per file, the SUM of
#     characters beyond the limit and the COUNT of offending lines,
#   - any GROWTH fails: a new long line, a new offending file, or an
#     existing long line getting longer (the sum is monotone -- counting
#     lines alone would let a monster line grow freely),
#   - shrinking passes and prints a "can tighten" hint; burning the
#     baseline down (shorten lines, regenerate, commit) is deliberate
#     work,
#   - the trend counter (lines > 100 across the scope) is printed but
#     never fails -- visibility without CI breakage.
#
# Metric note: awk's length() counts bytes in the C locale -- em-dashes
# and friends count their UTF-8 bytes. That is fine here: the ratchet
# only ever compares like with like. The leading-whitespace strip is
# applied in ALL three measurements (baseline regen, growth check,
# trend) so the metric is consistent everywhere; the baseline was
# regenerated for the metric switch (deliberate, diff-reviewed --
# entries can only shrink or vanish, never grow).
#
# Scope: files/**/*.sh (incl. files/etc/umask.sh and files/install.sh),
# the extensionless shell under files/opencode-permissions-kit-lib/bin/,
# and .github/workflows/*.yml (their long config lines are exactly the
# hidden growth this guard exists to surface). NOT in scope: py/, tui/,
# docs/, tests/ themselves, scripts/ (dev tooling).
#
# Run: sh tests/unit/test-line-length.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

LIMIT=120
TREND=100
BASELINE="$(dirname "$0")/line-length-baseline.txt"

# --regen: rewrite the baseline from the current tree (deliberate
# exception path -- review the diff, never regenerate to silence a fail).
if [ "${1:-}" = "--regen" ]; then
    {
        find files -name '*.sh' -type f
        find files/opencode-permissions-kit-lib/bin -type f
        find .github/workflows -name '*.yml' -type f
    } | sort -u | while IFS= read -r f; do
        awk -v lim="$LIMIT" -v f="$f" \
            '{ sub(/^[[:space:]]+/, "") }
             length > lim { s += length - lim; c++ }
             END { if (s > 0) printf "%s %d %d\n", f, s, c }' "$f"
    done > "$BASELINE"
    echo "baseline regenerated: $(wc -l < "$BASELINE" | tr -d ' ') entries -> $BASELINE"
    exit 0
fi

TMP_CUR="$(mktemp)"
trap 'rm -f "$TMP_CUR"' EXIT

[ -f "$BASELINE" ] || { echo "line length ratchet: FAILED (baseline missing)"; exit 1; }

# Current state: "path sum count" for every scope file with excess > 0.
# Paths in this repo contain no spaces (word-splitting over find is safe).
{
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
    find .github/workflows -name '*.yml' -type f
} | sort -u | while IFS= read -r f; do
    awk -v lim="$LIMIT" -v f="$f" \
        '{ sub(/^[[:space:]]+/, "") }
         length > lim { s += length - lim; c++ }
         END { if (s > 0) printf "%s %d %d\n", f, s, c }' "$f"
done > "$TMP_CUR"

rc=0

# 1. growth check: every current entry must exist in the baseline and
#    not exceed its sum.
hints=""
while read -r path cur_sum cur_cnt; do
    base_sum=$(awk -v p="$path" '$1 == p { print $2 }' "$BASELINE")
    if [ -z "$base_sum" ]; then
        echo "FAIL $path: $cur_cnt new line(s) over $LIMIT chars (not in the baseline)"
        rc=1
    elif [ "$cur_sum" -gt "$base_sum" ]; then
        echo "FAIL $path: long lines grew (excess $cur_sum > baseline $base_sum)"
        rc=1
    elif [ "$cur_sum" -lt "$base_sum" ]; then
        hints="$hints $path"
    fi
done < "$TMP_CUR"

# 2. stale-baseline check: entries whose file vanished or got clean must
#    be regenerated (a stale baseline hides growth behind wrong sums).
while read -r b_path b_sum b_cnt; do
    if ! awk -v p="$b_path" '$1 == p { found = 1 } END { exit !found }' "$TMP_CUR"; then
        echo "FAIL $b_path: stale baseline entry (file gone or now clean) -- regenerate"
        rc=1
    fi
done < "$BASELINE"

# 3. trend: lines over the warning threshold, never fatal.
trend=$({
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
    find .github/workflows -name '*.yml' -type f
} | sort -u | xargs awk -v lim="$TREND" \
    '{ sub(/^[[:space:]]+/, "") } length > lim { c++ } END { print c + 0 }')
over=$(awk '{ n += $3 } END { print n + 0 }' "$TMP_CUR")

if [ "$rc" -ne 0 ]; then
    echo "line length ratchet: FAILED"
    echo "  fix the lines above, or (deliberate exception, review the diff):"
    echo "    sh tests/unit/test-line-length.sh --regen"
    exit 1
fi

echo "line length ratchet: OK ($over lines over $LIMIT, all at baseline; trend: $trend lines over $TREND)"
[ -z "$hints" ] || echo "  can tighten the baseline (excess shrank):$hints"
exit 0
