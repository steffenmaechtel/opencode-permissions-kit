#!/bin/sh
# test-rules-index-parity.sh -- generated rules INDEX <-> rule metas
#
#   1. regenerating internal/rules-meta/INDEX.md reproduces the file
#      byte-for-byte — a hand edit drifts and fails
#   2. every meta file has exactly one INDEX row and vice versa
#   3. the output is date-invariant — FORCE_TODAY must not change
#      one byte (#527: a date-honoring generator writes a variant
#      the parity gate rejects on every audit run over due metas)
#
# Run: sh tests/unit/test-rules-index-parity.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Shared harness (issue #444 adoption, trap-only class): the FAIL-rows
# gate stays suite-local -- adoption covers the scratch receivers, which
# register with the work registry (issue #395); the local trap is gone.
# The three suffixed siblings hang off the same TMP base (#443: the old
# trap listed only TMP and TMP.gen, so one .files and one .rows file
# leaked per run) -- registered here at their known creation points.
. "$REPO_ROOT/tests/unit/lib/harness.sh"
TMP="$(work_new_file)" || {
    echo "rules index parity: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
work_register "${TMP}.gen" "${TMP}.files" "${TMP}.rows" "${TMP}.in" "${TMP}.bare"

INDEX=internal/rules-meta/INDEX.md

# 1. regeneration is byte-identical (hand edits drift)
cp "$INDEX" "$TMP.gen"
python3 scripts/gen-rules-index.py >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero" >>"$TMP"
}
if ! cmp -s "$INDEX" "$TMP.gen"; then
    echo "FAIL INDEX.md is not what the generator produces (hand edit? regenerate)" >>"$TMP"
    cp "$TMP.gen" "$INDEX" # restore the committed state
fi

# 2. meta file <-> row parity (both directions)
find internal/rules-meta -type f -name 'RM-*.md' | sed 's|.*/||; s|\.md$||' | sort >"$TMP.files"
grep -oE '^\| \[RM-[0-9]{4}\]' "$INDEX" | sed 's/.*\[//; s/\]//' | sort >"$TMP.rows"
for k in $(comm -23 "$TMP.files" "$TMP.rows"); do
    echo "FAIL $k: meta file without INDEX row" >>"$TMP"
done
for k in $(comm -13 "$TMP.files" "$TMP.rows"); do
    echo "FAIL $k: INDEX row without meta file" >>"$TMP"
done

# 3. date-invariance (#527): the INDEX is a pure function of the meta
#    tree — a pinned date must not change one byte. The parity gate
#    compares the bare run, while the audit's regen used to pass
#    FORCE_TODAY: on an overdue tree every audit run then wrote the
#    Overdue variant, and the next make test rejected the tree as a
#    hand edit. The far-future date maximizes the arm — under a
#    date-honoring generator every active meta goes overdue at once.
#    Purely observational: the incoming file state is restored
#    unconditionally, red or green.
cp "$INDEX" "$TMP.in"
python3 scripts/gen-rules-index.py >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero (bare run)" >>"$TMP"
}
cp "$INDEX" "$TMP.bare"
FORCE_TODAY=2099-01-01 python3 scripts/gen-rules-index.py >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero with FORCE_TODAY set" >>"$TMP"
}
if ! cmp -s "$INDEX" "$TMP.bare"; then
    echo "FAIL INDEX.md output depends on FORCE_TODAY (date-variant, #527)" >>"$TMP"
fi
cp "$TMP.in" "$INDEX"

# 4. the header points to the report-only overdue lane (#530): the
#    lane moved out of the INDEX with the date-invariance redesign
#    (#527) and a browsing maintainer lands here first — the header
#    pointer is the only trace of where overdue lives now. Pinned on
#    the COMMITTED INDEX, not the generator source: removing the line
#    from the generator and regenerating keeps both parity sides
#    matching — only this presence pin holds the pointer. TWO needles:
#    the command pointer (line 1) and the inv-7 attribution (line 2) —
#    a condensed one-line rewrite keeping only the command would
#    otherwise pass (#545 a A1). Raw un-ridden grep by design
#    (markdown source, the #472 docs-pin shape).
grep -qF -- 'Overdue is report-only' "$INDEX" &&
    grep -qF -- '(inv 7)' "$INDEX" || {
    echo "FAIL INDEX header lost the report-only overdue pointer (#530)" >>"$TMP"
}

if [ -s "$TMP" ]; then
    echo "rules index parity: FAILED"
    cat "$TMP"
    exit 1
fi
echo "rules index parity: OK ($(wc -l <"$TMP.rows" | tr -d ' ') index rows)"
