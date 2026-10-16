#!/bin/sh
# test-reviews-parity.sh -- generated INDEX <-> case folders + pointer
# integrity over internal/reviews/ (supersedes the review_pointer_check
# that lived in test-docs.sh before the structure wave).
#
#   1. every sharded case folder (N/N/N/N/pr-NNNNN) has exactly one
#      INDEX row, every INDEX row has a folder (both directions)
#   2. regenerating the INDEX reproduces the file byte-for-byte — a
#      hand edit drifts and fails
#   3. every snapshot carries exactly one "> Resolution:" pointer line
#      iff its case has a resolution.md (README rule 1/2)
#
# Run: sh tests/unit/test-reviews-parity.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP" "$TMP.gen"' EXIT

INDEX=internal/reviews/INDEX.md

# 1. folder <-> row parity (rows carry linked keys: | [pr-N](N/N/N/N/pr-N) |)
find internal/reviews -type d -name 'pr-[0-9][0-9][0-9][0-9][0-9]' 2>/dev/null | sed 's|.*/||' | sort > "$TMP.folders"
grep -E '^\| \[pr-[0-9]{5}\]\([0-9](/[0-9]){3}/pr-[0-9]{5}\) \|' "$INDEX" \
    | sed 's/^| \[\(pr-[0-9]\{5\}\)\](\([^)]*\)).*/\1 \2/' > "$TMP.rows"
awk '{ print $1 }' "$TMP.rows" | sort > "$TMP.keys"
# 1b. a row's link target must be the row key's own case folder
awk '{ base = $2; sub(/.*\//, "", base)
       if ($1 != base) printf "FAIL %s: link target %s is not its own folder\n", $1, $2 }' \
    "$TMP.rows" >> "$TMP"
comm -23 "$TMP.folders" "$TMP.keys" | while IFS= read -r k; do
    echo "FAIL $k: folder without INDEX row" >> "$TMP"
done
comm -13 "$TMP.folders" "$TMP.keys" | while IFS= read -r k; do
    echo "FAIL $k: INDEX row without folder" >> "$TMP"
done

# 2. regeneration is byte-identical (hand edits drift)
cp "$INDEX" "$TMP.gen"
python3 scripts/gen-review-index.py > /dev/null 2>&1 || {
    echo "FAIL generator exited non-zero" >> "$TMP"
}
if ! cmp -s "$INDEX" "$TMP.gen"; then
    echo "FAIL INDEX.md is not what the generator produces (hand edit? regenerate)" >> "$TMP"
    cp "$TMP.gen" "$INDEX"   # restore the committed state
fi

# 3. pointer <-> resolution parity
for f in internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-*/review-*.md; do
    [ -e "$f" ] || continue
    d=$(dirname "$f")
    ptr=$(grep -c '^> Resolution:' "$f")
    if [ -e "$d/resolution.md" ]; then
        [ "$ptr" -eq 1 ] || echo "FAIL $f: resolution exists but $ptr pointer line(s)" >> "$TMP"
    else
        [ "$ptr" -eq 0 ] || echo "FAIL $f: no resolution but $ptr pointer line(s)" >> "$TMP"
    fi
done

if [ -s "$TMP" ]; then
    echo "reviews parity: FAILED"
    cat "$TMP"
    exit 1
fi
echo "reviews parity: OK ($(wc -l < "$TMP.rows" | tr -d ' ') index rows, pointers consistent)"
