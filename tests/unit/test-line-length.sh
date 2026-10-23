#!/bin/sh
# test-line-length.sh -- line-length ratchet over the shipped scripts,
# the CI workflows, and the house-written markdown.
#
# Target limit: 120 CONTENT columns (pragmatic shell upper bound -- 80 is
# artificially narrow with long flags, paths and --option=value
# constructs). The metric strips leading whitespace first (0.0.41a F4):
# indentation is structure, not content -- punishing nesting depth with
# reflows puts pressure on exactly the wrapped-string spots that have a
# documented bug history (0.0.39o C1: spaces lost at adjacent-string
# wraps when lines were re-broken for width). Content-width keeps the
# ratchet's growth guarantee while making (re-)indentation free.
# For markdown files the metric ALSO strips the YAML frontmatter block
# (a leading --- ... --- pair, issue #178 wave): frontmatter is machine-
# parsed DATA, not prose to wrap — a skill description changes length
# with every legitimate edit, and baselining such a line buys churn
# without protection (the description bound lives where the data is
# validated: tests/unit/test-skills-lint.sh). Same spirit as the
# machine-generated INDEX exemption.
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
# only ever compares like with like. The leading-whitespace strip and
# the markdown frontmatter strip are applied in ALL three measurements
# (baseline regen, growth check, trend) via the shared measure() helper
# so the metric stays consistent everywhere; the baseline was
# regenerated for the metric switches (deliberate, diff-reviewed --
# entries can only shrink or vanish, never grow).
#
# Scope: TWO halves, one baseline. Shell/yml half: files/**/*.sh (incl.
# files/etc/umask.sh and files/install.sh), the extensionless shell
# under files/opencode-permissions-kit-lib/bin/, and
# .github/workflows/*.yml (their long config lines are exactly the
# hidden growth this guard exists to surface). Markdown half
# (docs_scope below, structure wave 2026-10 E4): agent/, internal/,
# docs/ and the root README/CONTRIBUTING/AGENTS *.md -- living text,
# and that INCLUDES review resolutions (only frozen history is
# exempt). NOT in scope: py/, tui/, tests/ themselves, scripts/ (dev
# tooling).
#
# Run: sh tests/unit/test-line-length.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

LIMIT=120
TREND=100
BASELINE="$(dirname "$0")/line-length-baseline.txt"

# Docs scope (structure wave 2026-10, E4 = 120): house-written markdown —
# agent/, internal/ (living parts), docs/, root README/AGENTS/CONTRIBUTING.
# Exempt: frozen history (archived records, immutable review snapshots —
# verbatim > wrap) and machine-generated files (INDEX, legacy-index).
docs_scope() {
    for f in README.md CONTRIBUTING.md AGENTS.md; do
        [ -e "$f" ] && printf '%s\n' "$f"
    done
    find agent internal docs -name '*.md' -type f \
        ! -path 'internal/records/_archive/*' \
        ! -path 'internal/reviews/*/pr-*/review-*' \
        ! -name 'INDEX.md' \
        ! -name 'legacy-index.md'
}

# scope_files -- the ratchet's full scope, one path per line.
scope_files() {
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
    find .github/workflows -name '*.yml' -type f
    docs_scope
}

# measure_file <file> <limit> -- the ONE metric every measurement uses
# (regen, growth check, trend, self-probe): strips leading whitespace
# (content, not structure) and, for markdown files only, the leading
# YAML frontmatter block (data, not prose -- see header). Prints
# "<file> <sum-beyond-limit> <offending-line-count>" when there is
# excess, nothing when clean.
measure_file() {
    _mf="$1"; _ml="$2"
    case "$_mf" in
        *.md) _mfm=1 ;;
        *) _mfm=0 ;;
    esac
    awk -v lim="$_ml" -v f="$_mf" -v fm="$_mfm" '
        FNR == 1 && fm && $0 == "---" { infm = 1; next }
        fm && infm { if ($0 == "---") infm = 0; next }
        { sub(/^[[:space:]]+/, "") }
        length > lim { s += length - lim; c++ }
        END { if (s > 0) printf "%s %d %d\n", f, s, c }' "$_mf"
}

# --regen: rewrite the baseline from the current tree (deliberate
# exception path -- review the diff, never regenerate to silence a fail).
if [ "${1:-}" = "--regen" ]; then
    scope_files | sort -u | while IFS= read -r f; do
        measure_file "$f" "$LIMIT"
    done > "$BASELINE"
    echo "baseline regenerated: $(wc -l < "$BASELINE" | tr -d ' ') entries -> $BASELINE"
    exit 0
fi

TMP_CUR="$(mktemp)"
TMP_PROBE="$(mktemp)"
trap 'rm -f "$TMP_CUR" "$TMP_PROBE"' EXIT

[ -f "$BASELINE" ] || { echo "line length ratchet: FAILED (baseline missing)"; exit 1; }

# --- metric self-probe (the strip must discriminate, L4) ----------------
# The frontmatter strip is a new fail-soft spot in the "strips too
# much" direction (an over-eager strip would silently exempt prose).
# The probe runs the REAL measure_file helper on scratch fixtures:
# frontmatter lines not counted, prose counted, non-markdown files
# never stripped (a YAML --- document start is content there).
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf "${PROBE_DIR:?}" "$TMP_CUR" "$TMP_PROBE"' EXIT
mkdir -p "$PROBE_DIR"
printf -- '---\nname: probe\ndescription: %s\n---\nshort prose line\n' \
    "$(printf 'x%.0s' $(seq 1 130))" > "$PROBE_DIR/probe.md"
printf -- '---\nshort frontmatter line\n---\n%s\n' \
    "$(printf 'y%.0s' $(seq 1 130))" > "$PROBE_DIR/probe2.md"
printf -- '---\n%s\n' \
    "$(printf 'z%.0s' $(seq 1 130))" > "$PROBE_DIR/probe.yml"
_p1=$(measure_file "$PROBE_DIR/probe.md" "$LIMIT")   # frontmatter only
_p2=$(measure_file "$PROBE_DIR/probe2.md" "$LIMIT")  # prose long line
_p3=$(measure_file "$PROBE_DIR/probe.yml" "$LIMIT")  # non-md: not stripped
if [ -z "$_p1" ] && [ "${_p2#*probe2.md }" != "$_p2" ] && [ "${_p3#*probe.yml }" != "$_p3" ]; then
    echo "  probe ok: frontmatter stripped (md), prose and non-md counted"
else
    echo "  PROBE BROKEN: fm-only='$_p1' prose='$_p2' non-md='$_p3'" >> "$TMP_PROBE"
fi

# Current state: "path sum count" for every scope file with excess > 0.
# Paths in this repo contain no spaces (word-splitting over find is safe).
scope_files | sort -u | while IFS= read -r f; do
    measure_file "$f" "$LIMIT"
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
_trend_files="$(scope_files | sort -u)"
trend=0
for f in $_trend_files; do
    _t=$(measure_file "$f" "$TREND")
    [ -n "$_t" ] && trend=$((trend + ${_t##* }))
done
over=$(awk '{ n += $3 } END { print n + 0 }' "$TMP_CUR")

if [ -s "$TMP_PROBE" ]; then
    echo "line length ratchet: FAILED"
    cat "$TMP_PROBE"
    exit 1
fi
if [ "$rc" -ne 0 ]; then
    echo "line length ratchet: FAILED"
    echo "  fix the lines above, or (deliberate exception, review the diff):"
    echo "    sh tests/unit/test-line-length.sh --regen"
    exit 1
fi

echo "line length ratchet: OK ($over lines over $LIMIT, all at baseline; trend: $trend lines over $TREND)"
[ -z "$hints" ] || echo "  can tighten the baseline (excess shrank):$hints"
exit 0
