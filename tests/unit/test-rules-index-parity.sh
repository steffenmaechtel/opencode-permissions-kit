#!/bin/sh
# test-rules-index-parity.sh -- generated rules INDEX <-> rule metas
#
#   1. regenerating internal/rules-meta/INDEX.md reproduces the file
#      byte-for-byte — a hand edit drifts and fails. Every
#      regeneration is STAGED through the generator's --output
#      (#572 T2): the suite never writes the real INDEX — a kill in
#      the old regen→restore window used to leave an unregistered
#      regenerated INDEX the next run reported as a hand edit. Leg 5
#      pins the never-write property.
#   2. every meta file has exactly one INDEX row and vice versa
#   3. the output is date-invariant — FORCE_TODAY must not change
#      one byte (#527: a date-honoring generator writes a variant
#      the parity gate rejects on every audit run over due metas)
#   4. the header points to the report-only overdue lane (#530)
#   5. the real INDEX is byte-unchanged by the whole run (#572 T2)
#
# Run: sh tests/unit/test-rules-index-parity.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Shared harness (issue #444 adoption, trap-only class): the FAIL-rows
# gate stays suite-local -- adoption covers the scratch receivers, which
# register with the work registry (issue #395); the local trap is gone.
# The suffixed siblings hang off the same TMP base (#443: the old
# trap listed only TMP and TMP.gen, so per-run scratch leaked) --
# registered here at their known creation points.
. "$REPO_ROOT/tests/unit/lib/harness.sh"
TMP="$(work_new_file)" || {
    echo "rules index parity: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
work_register "${TMP}.gen" "${TMP}.files" "${TMP}.rows" "${TMP}.in" "${TMP}.bare" "${TMP}.ft" "${TMP}.now"

INDEX=internal/rules-meta/INDEX.md

# incoming copy + mtime marker: leg 5 compares against both -- the run
# must leave the real INDEX byte-identical AND unwritten (#572 T2; the
# mtime arm catches an in-place regeneration of identical bytes)
cp "$INDEX" "$TMP.in"
cp "$INDEX" "$TMP.now"

# 1. regeneration is byte-identical (hand edits drift) -- staged via
#    --output, the real file is never written
python3 scripts/gen-rules-index.py --output "$TMP.gen" >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero" >>"$TMP"
}
if ! cmp -s "$INDEX" "$TMP.gen"; then
    echo "FAIL INDEX.md is not what the generator produces (hand edit? regenerate: sh scripts/rules-audit.sh)" >>"$TMP"
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
#    tree — a pinned date must not change one byte. Both runs staged
#    (#572 T2). The far-future date maximizes the arm — under a
#    date-honoring generator every active meta goes overdue at once.
python3 scripts/gen-rules-index.py --output "$TMP.bare" >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero (bare run)" >>"$TMP"
}
FORCE_TODAY=2099-01-01 python3 scripts/gen-rules-index.py --output "$TMP.ft" >/dev/null 2>&1 || {
    echo "FAIL generator exited non-zero with FORCE_TODAY set" >>"$TMP"
}
if ! cmp -s "$TMP.bare" "$TMP.ft"; then
    echo "FAIL INDEX.md output depends on FORCE_TODAY (date-variant, #527)" >>"$TMP"
fi

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

# 5. never-write pin (#572 T2): every regeneration above staged through
#    --output — the real INDEX must be byte-identical to the incoming
#    copy AND not newer than the run's start marker (a regressed
#    in-place leg rewrites the file even when the bytes do not change —
#    the exact kill-window residual T2 closes). Red restores the
#    incoming bytes; the red stands.
if ! cmp -s "$INDEX" "$TMP.in"; then
    echo "FAIL INDEX.md changed during the run — a leg wrote the real file (stage via --output, #572 T2)" >>"$TMP"
    cp "$TMP.in" "$INDEX"
elif [ "$INDEX" -nt "$TMP.now" ]; then
    echo "FAIL INDEX.md was written during the run (mtime moved; identical \
bytes) — stage via --output, #572 T2" >>"$TMP"
fi

if [ -s "$TMP" ]; then
    echo "rules index parity: FAILED"
    cat "$TMP"
    exit 1
fi
echo "rules index parity: OK ($(wc -l <"$TMP.rows" | tr -d ' ') index rows)"
