#!/bin/sh
# test-reviews-lint.sh -- structural lint over internal/reviews/
#
# Rules (internal/reviews/README.md):
#   - vorgang folders are named pr-NNNNN (5-digit zero-padded PR number)
#   - snapshots are review-<letter>.md with letters contiguous from "a"
#     (z is followed by aa)
#   - at most one resolution.md per vorgang
#   - no stray files at the reviews/ root or inside vorgang folders
#   - new-style vorgänge (review-meta header present): the header ID
#     matches the folder and the Snapshot field matches the file name
#     (legacy vorgänge predate headers; their identity lives in
#     legacy-index.md)
#
# Run: sh tests/unit/test-reviews-lint.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# expected letter sequence a, b, ..., z, aa, ab ... for n slots
expected_letters() {
    awk -v n="$1" 'BEGIN {
        for (i = 0; i < n; i++) {
            l = ""; j = i
            do { l = sprintf("%c", 97 + (j % 26)) l; j = int(j / 26) - 1 } while (j >= 0)
            print l
        }
    }'
}

# 1. root level: only the three house files + pr-* folders
for entry in internal/reviews/*; do
    case "$entry" in
        internal/reviews/README.md|internal/reviews/INDEX.md|internal/reviews/legacy-index.md) ;;
        internal/reviews/pr-[0-9][0-9][0-9][0-9][0-9]) ;;
        *) echo "FAIL stray entry: $entry" >> "$TMP" ;;
    esac
done

for d in internal/reviews/pr-*; do
    [ -d "$d" ] || continue
    key=$(basename "$d")
    # 2. snapshot letters contiguous from a
    ls "$d"/review-*.md 2>/dev/null | sed 's|.*/review-||; s|\.md$||' > "$TMP.letters"
    expected_letters "$(wc -l < "$TMP.letters" | tr -d ' ')" > "$TMP.expected"
    if ! cmp -s "$TMP.letters" "$TMP.expected"; then
        echo "FAIL $key: snapshot letters not contiguous from a ($(paste -sd, "$TMP.letters"))" >> "$TMP"
    fi
    # 3. at most one resolution
    n=$(ls "$d"/resolution.md 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -le 1 ] || echo "FAIL $key: $n resolution files" >> "$TMP"
    # 4. no stray files inside the vorgang folder
    for f in "$d"/*; do
        case "$(basename "$f")" in
            review-*.md|resolution.md) ;;
            *) echo "FAIL stray file: $f" >> "$TMP" ;;
        esac
    done
    # 5. header consistency for new-style vorgänge
    for f in "$d"/review-*.md; do
        [ -e "$f" ] || continue
        if grep -q '<!-- review-meta' "$f"; then
            letter=$(basename "$f" .md); letter=${letter#review-}
            id=$(sed -n 's/^ID:[[:space:]]*//p' "$f" | head -n 1)
            snap=$(sed -n 's/^Snapshot:[[:space:]]*//p' "$f" | head -n 1)
            [ "$id" = "$key" ] || echo "FAIL $f: header ID '$id' != folder '$key'" >> "$TMP"
            [ "$snap" = "$letter" ] || echo "FAIL $f: Snapshot '$snap' != letter '$letter'" >> "$TMP"
        fi
    done
done
rm -f "$TMP.letters" "$TMP.expected"

if [ -s "$TMP" ]; then
    echo "reviews lint: FAILED"
    cat "$TMP"
    exit 1
fi
echo "reviews lint: OK ($(ls -d internal/reviews/pr-* | wc -l | tr -d ' ') vorgänge)"
