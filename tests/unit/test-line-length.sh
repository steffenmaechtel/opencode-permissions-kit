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
# machine-generated INDEX exemption. The strip applies ONLY when the
# block actually closes: a leading --- that never closes is not
# frontmatter (a horizontal rule, or a broken fence) — the file then
# counts IN FULL, fail-loud (#235 a S1: the unclosed direction used
# to exempt the whole file silently).
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
# so the metric stays consistent everywhere; each metric switch
# re-checked the baseline via --regen (deliberate, diff-reviewed --
# entries can only shrink or vanish, never grow; the frontmatter-strip
# switch of the skills pilot measured a no-op: no scoped file carried
# >120 frontmatter lines).
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

# Shared harness (issue #444 adoption, trap-only class): the ratchet's
# own verdict lines and its baseline mechanics stay suite-local --
# adoption covers the three scratch receivers, which register with the
# work registry (issue #395); the two local traps are gone (a local trap
# would disarm the central registry trap).
. "$REPO_ROOT/tests/unit/lib/harness.sh"

LIMIT=120
TREND=100
BASELINE="$(dirname "$0")/line-length-baseline.txt"

# Docs scope (structure wave 2026-10, E4 = 120): house-written markdown —
# agent/, internal/ (living parts), docs/, root README/AGENTS/CONTRIBUTING,
# and .agents/skills/ (house-written living text — issue #178).
# Exempt: frozen history (archived records) and machine-generated files
# (INDEX, legacy-index — the immutable review snapshots moved to tag
# review-corpus with the corpus archive, issue #290).
# Exempt: internal/reviews-meta/*/data/ — MACHINE-MADE run artifacts
# (#300, option B): future meta runs regenerate these files with
# machine-width lines nobody wraps by hand, which would redden the
# ratchet as "new offending files" for content no human edit touches.
# Narrowest fix that removes the churn: exclude the data/ folders only;
# the human-written statistics/further-analyses stay pinned (exclusion
# means those files can grow unbounded — accepted for machine output).
docs_scope() {
    for f in README.md CONTRIBUTING.md AGENTS.md; do
        [ -e "$f" ] && printf '%s\n' "$f"
    done
    find agent internal docs .agents -name '*.md' -type f \
        ! -path 'internal/records/_archive/*' \
        ! -path 'internal/reviews-meta/*/data/*' \
        ! -name 'INDEX.md' \
        ! -name 'legacy-index.md'
}

# scope_files -- the ratchet's full scope, one path per line.
scope_files() {
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
    find files/opencode-permissions-kit-lib/git-heal -type f
    find .github/workflows -name '*.yml' -type f
    docs_scope
}

# measure_file <file> <limit> -- the ONE metric every measurement uses
# (regen, growth check, trend, self-probe): strips leading whitespace
# (content, not structure) and, for markdown files only, the leading
# YAML frontmatter block (data, not prose -- see header). The strip is
# conditional on the block CLOSING: an unclosed leading --- counts in
# full (#235 a S1). "Closing" means the next --- line anywhere in the
# file -- YAML validity is not assessed, so a prose file opening with
# a --- rule and containing another --- line has that span stripped;
# pinned as documented behavior by probe4 (#235 b B3). Prints
# "<file> <sum-beyond-limit> <offending-line-count>" when there is
# excess, nothing when clean.
measure_file() {
    _mf="$1"
    _ml="$2"
    # Readability guard (#818 a T1, the fail-loud detector-sweep
    # discipline): an unreadable scope file used to die inside awk
    # with a stderr-only diagnostic and NO row — the growth loop
    # greened over it (a false-green growth channel: the file simply
    # stopped being measured) and --regen silently dropped its
    # baseline row. Die loud with the name, keep stdout the data
    # channel, carry the failure in the rc.
    [ -r "$_mf" ] || {
        printf 'line length ratchet: unreadable scope file: %s\n' "$_mf" >&2
        return 1
    }
    case "$_mf" in
        *.md) _mfm=1 ;;
        *) _mfm=0 ;;
    esac
    _strip=0
    if [ "$_mfm" -eq 1 ]; then
        # frontmatter counts as frontmatter only when it closes
        awk 'NR == 1 { ok = ($0 == "---"); next }
             ok && $0 == "---" { found = 1; exit }
             END { exit !found }' "$_mf" && _strip=1
    fi
    awk -v lim="$_ml" -v f="$_mf" -v fm="$_strip" '
        FNR == 1 && fm && $0 == "---" { infm = 1; next }
        fm && infm { if ($0 == "---") infm = 0; next }
        { sub(/^[[:space:]]+/, "") }
        length > lim { s += length - lim; c++ }
        END { if (s > 0) printf "%s %d %d\n", f, s, c }' "$_mf" || {
        printf 'line length ratchet: awk failed on %s (mid-read error?)\n' "$_mf" >&2
        return 1
    }
}

# --regen: rewrite the baseline from the current tree (deliberate
# exception path -- review the diff, never regenerate to silence a fail).
# Atomic since #818 a T1: rows land in scratch, the baseline is replaced
# only after the whole walk succeeded — a partial regen (an unreadable
# scope file aborts the loop mid-way) must never leave a half-written
# baseline behind. Empty output refuses loud too (agent/conventions.md
# "Fail-loud detector sweeps": zero measured files is not a clean
# verdict — it would silently wipe the baseline and
# green every later check over nothing).
if [ "${1:-}" = "--regen" ]; then
    _regen_tmp="$(work_new_file)" || {
        echo "line length ratchet: FAILED (scratch creation failed, TMPDIR=${TMPDIR:-unset})" >&2
        exit 1
    }
    _regen_rc=0
    scope_files | sort -u | while IFS= read -r f; do
        measure_file "$f" "$LIMIT" || exit 1
    done >"$_regen_tmp" || _regen_rc=$?
    if [ "$_regen_rc" -ne 0 ]; then
        echo "line length ratchet: FAILED (--regen aborted: a scope file was unreadable — named on stderr above)" >&2
        exit 1
    fi
    if [ ! -s "$_regen_tmp" ]; then
        echo "line length ratchet: FAILED (--regen measured no files — scope walk broken, or the tree hit zero deliberately: re-baseline by hand)" >&2
        exit 1
    fi
    mv "$_regen_tmp" "$BASELINE"
    echo "baseline regenerated: $(wc -l <"$BASELINE" | tr -d ' ') entries -> $BASELINE"
    exit 0
fi

# Loud scratch guards (#441 a B1 class swept to the adopted suites): no
# set -e here, so a failed work_new_file would leave TMP_CUR empty and
# every redirect would degenerate to a root-level literal. Abort loud.
TMP_CUR="$(work_new_file)" || {
    echo "line length ratchet: FAILED (scratch creation failed, TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
TMP_PROBE="$(work_new_file)" || {
    echo "line length ratchet: FAILED (scratch creation failed, TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

[ -f "$BASELINE" ] || {
    echo "line length ratchet: FAILED (baseline missing)"
    exit 1
}

# --- metric self-probe (the strip must discriminate, L4) ----------------
# The frontmatter strip is a fail-soft spot in these directions:
# "strips too little" (frontmatter counted as prose), "strips too
# much" (prose silently exempt -- the unclosed-block case, #235 a S1),
# and the pseudo-close variant of "too much": the span between a
# leading --- and a LATER --- line is stripped as frontmatter even
# when the file is prose with horizontal rules (#235 b B3). The probe
# runs the REAL measure_file helper on scratch fixtures: frontmatter
# lines not counted, prose counted, non-markdown files never stripped
# (a YAML --- document start is content there), an UNCLOSED leading
# --- counted in full, and a pseudo-close span stripped with only
# post-close prose counted — the two probe4 long lines differ in
# length (130 in-span, 131 post-close) so the asserted sum pins
# WHICH line was counted, not just how many (#235 c S2).
PROBE_DIR="$(work_new)" || {
    echo "line length ratchet: FAILED (scratch creation failed, TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
printf -- '---\nname: probe\ndescription: %s\n---\nshort prose line\n' \
    "$(printf 'x%.0s' $(seq 1 130))" >"$PROBE_DIR/probe.md"
printf -- '---\nshort frontmatter line\n---\n%s\n' \
    "$(printf 'y%.0s' $(seq 1 130))" >"$PROBE_DIR/probe2.md"
printf -- '---\n%s\n' \
    "$(printf 'z%.0s' $(seq 1 130))" >"$PROBE_DIR/probe.yml"
printf -- '---\nunclosed block, prose must count: %s\n' \
    "$(printf 'w%.0s' $(seq 1 130))" >"$PROBE_DIR/probe3.md"
printf -- '---\n%s\n---\n%s\n' \
    "$(printf 'p%.0s' $(seq 1 130))" \
    "$(printf 'q%.0s' $(seq 1 131))" >"$PROBE_DIR/probe4.md"
_p1=$(measure_file "$PROBE_DIR/probe.md" "$LIMIT")  # frontmatter only
_p2=$(measure_file "$PROBE_DIR/probe2.md" "$LIMIT") # prose long line
_p3=$(measure_file "$PROBE_DIR/probe.yml" "$LIMIT") # non-md: not stripped
_p4=$(measure_file "$PROBE_DIR/probe3.md" "$LIMIT") # unclosed md: counts
_p5=$(measure_file "$PROBE_DIR/probe4.md" "$LIMIT") # pseudo-close span
if [ -z "$_p1" ] && [ "${_p2#*probe2.md }" != "$_p2" ] &&
    [ "${_p3#*probe.yml }" != "$_p3" ] &&
    [ "${_p4#*probe3.md }" != "$_p4" ] &&
    [ "${_p5#*probe4.md }" = "11 1" ]; then
    echo "  probe ok: closed fm stripped, prose and non-md counted, unclosed counts, pseudo-close span stripped (sum pins the counted line)"
else
    echo "  PROBE BROKEN: fm-only='$_p1' prose='$_p2' non-md='$_p3' unclosed='$_p4' pseudo='$_p5'" >>"$TMP_PROBE"
fi

# #818 a T1, the readability guard: an unreadable scope file must die
# loud with its name (rc 1, stderr row, no stdout row) — it used to
# contribute no row at all, greening the growth channel and silently
# dropping its baseline row on --regen. chmod 000 cannot block a root
# reader (disclosed skip, the #318 a B3 root gate).
if [ "$(id -u)" -eq 0 ]; then
    echo "  pin skipped: readability leg needs a non-root uid (root reads through 000) (#818 a T1)"
else
    printf 'short\n' >"$PROBE_DIR/probe6.md"
    chmod 000 "$PROBE_DIR/probe6.md"
    _p6rc=0
    _p6err=$(measure_file "$PROBE_DIR/probe6.md" "$LIMIT" 2>&1) || _p6rc=$?
    if [ "$_p6rc" -eq 1 ] &&
        printf '%s' "$_p6err" | grep -qF "unreadable scope file: $PROBE_DIR/probe6.md"; then
        echo "  probe ok: unreadable scope file dies loud with its name (#818 a T1)"
    else
        echo "  PROBE BROKEN: readability guard rc=$_p6rc err='$_p6err' (#818 a T1)" >>"$TMP_PROBE"
    fi
    chmod 644 "$PROBE_DIR/probe6.md"
fi

# #818 a T1, the --regen mirror: the regen path refuses an unreadable
# scope file (rc 1) AND leaves the baseline untouched — rows land in
# scratch and the move happens only after a fully successful walk; an
# EMPTY scope refuses too (zero measured files would silently wipe the
# baseline and green every later check over nothing). Runs a mirrored
# copy of this suite (harness + baseline) in a scratch tree, cwd inside
# it — scope_files() walks the cwd's files/ tree.
T1M="$(work_new)" || {
    echo "line length ratchet: FAILED (scratch creation failed, TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
_t1_dir="$(dirname "$0")"
mkdir -p "$T1M/tests/unit/lib" "$T1M/files/x"
cp "$_t1_dir/test-line-length.sh" "$T1M/tests/unit/"
cp "$_t1_dir/lib/harness.sh" "$T1M/tests/unit/lib/"
cp "$BASELINE" "$T1M/tests/unit/line-length-baseline.txt"
cp "$BASELINE" "$T1M/baseline-orig.txt"
_longline="$(printf 'a%.0s' $(seq 1 130))"
printf 'printf "%%s" "%s"\n' "$_longline" >"$T1M/files/x/long.sh"
printf 'printf "%%s" "%s"\n' "$_longline" >"$T1M/files/x/long2.sh"
_reg_out=""
if [ "$(id -u)" -eq 0 ]; then
    echo "  pin skipped: regen-refusal leg needs a non-root uid (root reads through 000) (#818 a T1)"
else
    chmod 000 "$T1M/files/x/long2.sh"
    _reg_rc=0
    _reg_out=$(cd "$T1M" && sh tests/unit/test-line-length.sh --regen 2>&1) || _reg_rc=$?
    if [ "$_reg_rc" -eq 1 ] &&
        printf '%s' "$_reg_out" | grep -qF 'unreadable scope file' &&
        printf '%s' "$_reg_out" | grep -qF 'regen aborted' &&
        cmp -s "$T1M/tests/unit/line-length-baseline.txt" "$T1M/baseline-orig.txt"; then
        echo "  probe ok: --regen refuses an unreadable scope file, baseline untouched (#818 a T1)"
    else
        echo "  PROBE BROKEN: regen refusal rc=$_reg_rc baseline-kept=$(cmp -s "$T1M/tests/unit/line-length-baseline.txt" "$T1M/baseline-orig.txt" && echo y || echo n) out='$(printf '%s' "$_reg_out" | tail -2)' (#818 a T1)" >>"$TMP_PROBE"
    fi
    chmod 644 "$T1M/files/x/long2.sh"
fi
# the empty-scope refusal (any uid): no files/ tree at all → the regen
# must refuse loud instead of wiping the baseline to zero rows.
rm -rf "${T1M:?}/files"
_reg_rc=0
_reg_out=$(cd "$T1M" && sh tests/unit/test-line-length.sh --regen 2>&1) || _reg_rc=$?
if [ "$_reg_rc" -eq 1 ] &&
    printf '%s' "$_reg_out" | grep -qF 'measured no files' &&
    cmp -s "$T1M/tests/unit/line-length-baseline.txt" "$T1M/baseline-orig.txt"; then
    echo "  probe ok: --regen refuses an empty scope, baseline untouched (#818 a T1)"
else
    echo "  PROBE BROKEN: empty-scope refusal rc=$_reg_rc out='$(printf '%s' "$_reg_out" | tail -2)' (#818 a T1)" >>"$TMP_PROBE"
fi
rm -rf "${T1M:?}"

# Current state: "path sum count" for every scope file with excess > 0.
# Paths in this repo contain no spaces (word-splitting over find is safe).
# #818 a T1: an unreadable scope file aborts the walk loud (the rc of
# the pipeline carries the loop's exit) instead of greening over a
# file that stopped being measured. An empty TMP_CUR with a non-empty
# baseline is already caught by the stale-baseline check below; empty
# plus empty is the legitimate zero-tree state.
_cur_rc=0
scope_files | sort -u | while IFS= read -r f; do
    measure_file "$f" "$LIMIT" || exit 1
done >"$TMP_CUR" || _cur_rc=$?
if [ "$_cur_rc" -ne 0 ]; then
    echo "line length ratchet: FAILED (a scope file was unreadable — named on stderr above)"
    exit 1
fi

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
done <"$TMP_CUR"

# 2. stale-baseline check: entries whose file vanished or got clean must
#    be regenerated (a stale baseline hides growth behind wrong sums).
while read -r b_path b_sum b_cnt; do
    if ! awk -v p="$b_path" '$1 == p { found = 1 } END { exit !found }' "$TMP_CUR"; then
        echo "FAIL $b_path: stale baseline entry (file gone or now clean) -- regenerate"
        rc=1
    fi
done <"$BASELINE"

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
