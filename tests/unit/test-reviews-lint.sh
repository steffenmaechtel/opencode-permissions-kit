#!/bin/sh
# test-reviews-lint.sh -- structural lint over internal/reviews/
#
# Rules (internal/reviews/README.md):
#   - case folders are named pr-NNNNN (5-digit zero-padded PR number)
#   - shard rule: pr-ABCDE lives at internal/reviews/A/B/C/D/ — four
#     one-digit levels, at most 10 entries per node (10 digit dirs per
#     shard node, 10 case folders per leaf shard)
#   - snapshots are review-<letter>.md with letters contiguous from "a"
#     (z is followed by aa)
#   - at most one resolution.md per case
#   - no stray files at the reviews/ root, in shard dirs, or in case
#     folders
#   - new-style cases (review-meta header present): the header ID
#     matches the folder and the Snapshot field matches the file name
#     (legacy cases predate headers; their identity lives in
#     legacy-index.md)
#
# Run: sh tests/unit/test-reviews-lint.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

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

# 1. root level: only the three house files + one-digit shard dirs
for entry in internal/reviews/*; do
    case "$entry" in
        internal/reviews/README.md|internal/reviews/INDEX.md|internal/reviews/legacy-index.md) ;;
        internal/reviews/[0-9]) ;;
        *) echo "FAIL stray entry: $entry" >> "$TMP" ;;
    esac
done

# 2. shard tree: levels 1-3 hold only digit dirs, level 4 only cases
for p in internal/reviews/[0-9]/* \
         internal/reviews/[0-9]/[0-9]/* \
         internal/reviews/[0-9]/[0-9]/[0-9]/*; do
    [ -e "$p" ] || continue
    case "$p" in
        internal/reviews/[0-9]/[0-9]|internal/reviews/[0-9]/[0-9]/[0-9]|internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]) ;;
        *) echo "FAIL stray shard entry: $p" >> "$TMP" ;;
    esac
done
for p in internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/*; do
    [ -e "$p" ] || continue
    case "$p" in
        internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-[0-9][0-9][0-9][0-9][0-9]) ;;
        *) echo "FAIL stray leaf-shard entry: $p" >> "$TMP" ;;
    esac
done

for d in internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-*; do
    [ -d "$d" ] || continue
    key=$(basename "$d")
    # 3. shard rule: the case sits under its own first four digits
    digs=${key#pr-}
    rest=$digs
    a=${rest%????}; rest=${rest#?}
    b=${rest%???};  rest=${rest#?}
    c=${rest%??};   rest=${rest#?}
    e=${rest%?}
    want="internal/reviews/$a/$b/$c/$e"
    [ "$(dirname "$d")" = "$want" ] || \
        echo "FAIL $key: shard $(dirname "$d") != expected $want" >> "$TMP"
    # 4. snapshot letters contiguous from a
    ls "$d"/review-*.md 2>/dev/null | sed 's|.*/review-||; s|\.md$||' > "$TMP.letters"
    expected_letters "$(wc -l < "$TMP.letters" | tr -d ' ')" > "$TMP.expected"
    if ! cmp -s "$TMP.letters" "$TMP.expected"; then
        echo "FAIL $key: snapshot letters not contiguous from a ($(paste -sd, "$TMP.letters"))" >> "$TMP"
    fi
    # 5. at most one resolution
    n=$(ls "$d"/resolution.md 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -le 1 ] || echo "FAIL $key: $n resolution files" >> "$TMP"
    # 6. no stray files inside the case folder
    for f in "$d"/*; do
        case "$(basename "$f")" in
            review-*.md|resolution.md) ;;
            *) echo "FAIL stray file: $f" >> "$TMP" ;;
        esac
    done
    # 7. header consistency for new-style cases
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
rm -f "${TMP:?}.letters" "${TMP:?}.expected"

if [ -s "$TMP" ]; then
    echo "reviews lint: FAILED"
    cat "$TMP"
    exit 1
fi
echo "reviews lint: OK ($(find internal/reviews -type d -name 'pr-[0-9][0-9][0-9][0-9][0-9]' | wc -l | tr -d ' ') cases)"
