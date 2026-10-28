#!/bin/sh
# test-rules-index-parity.sh -- generated rules INDEX <-> rule metas
#
#   1. regenerating internal/rules-meta/INDEX.md reproduces the file
#      byte-for-byte — a hand edit drifts and fails
#   2. every meta file has exactly one INDEX row and vice versa
#
# Run: sh tests/unit/test-rules-index-parity.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP" "${TMP:?}.gen"' EXIT INT TERM

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

if [ -s "$TMP" ]; then
    echo "rules index parity: FAILED"
    cat "$TMP"
    exit 1
fi
echo "rules index parity: OK ($(wc -l <"$TMP.rows" | tr -d ' ') index rows)"
