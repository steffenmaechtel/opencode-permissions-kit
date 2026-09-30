#!/bin/sh
# test-docs.sh -- documentation link checker (no external dependencies)
#
# Fails when any Markdown file under docs/, plus README.md, CONTRIBUTING.md
# and AGENTS.md, contains a broken relative link or a dangling in-page
# anchor. HTTP(S)/mailto links are skipped (no network access).
#
# Run: sh tests/unit/test-docs.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# GitHub anchor normalization: lowercase; remove anything that is not a
# letter, number, space, or hyphen; spaces -> hyphens; trim edge hyphens.
github_anchor() {
    printf '%s\n' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d "!\"#\$%&'()*+,./:;<=>?@[\\]^_\`{|}~" \
        | sed -e 's/[[:space:]][[:space:]]*/-/g' -e 's/^-//' -e 's/-$//'
}

# Strip fenced code blocks so links inside them are ignored.
strip_fences() {
    awk '/^```/ { infence = !infence; next } !infence { print }'
}

# headings of a file -> normalized anchors
file_anchors() {
    strip_fences < "$1" | grep -E '^#{1,6} ' | sed -E 's/^#{1,6} //'
}

check_file() {
    f="$1"
    strip_fences < "$f" | grep -oE '\]\([^)]+\)' | sed -e 's/^](//' -e 's/)$//' | while IFS= read -r target; do
        # strip optional link title after the path
        target="${target%% *}"
        case "$target" in
            http://*|https://*|mailto:*|tel:*) continue ;;
        esac

        fragment=""
        case "$target" in
            *\#*) fragment="${target#*#}"; path="${target%%#*}" ;;
            *)    path="$target" ;;
        esac

        if [ -z "$path" ]; then
            base="$f"
        else
            case "$path" in
                /*) base="${path#/}" ;;
                *)  base="$(dirname "$f")/$path" ;;
            esac
            if [ ! -e "$base" ]; then
                echo "FAIL $f -> $target (file missing)" >> "$TMP"
                continue
            fi
            if [ -d "$base" ]; then
                # directory link: GitHub renders its README.md
                if [ ! -e "$base/README.md" ]; then
                    echo "FAIL $f -> $target (directory has no README.md)" >> "$TMP"
                fi
                continue
            fi
        fi

        if [ -n "$fragment" ]; then
            want="$(github_anchor "$fragment")"
            found=0
            while IFS= read -r h; do
                [ -n "$h" ] || continue
                if [ "$(github_anchor "$h")" = "$want" ]; then
                    found=1
                    break
                fi
            done <<EOF
$(file_anchors "$base")
EOF
            if [ "$found" -ne 1 ]; then
                echo "FAIL $f -> $target (anchor '##$want' not found)" >> "$TMP"
            fi
        fi
    done
}

for f in README.md CONTRIBUTING.md AGENTS.md; do
    [ -e "$f" ] || continue
    check_file "$f"
done
find docs -name '*.md' -type f | sort | while IFS= read -r f; do
    check_file "$f"
done

# Snapshot <-> resolution pointer integrity (docs/design/review/README.md
# rule 2): every snapshot whose README index row lists a resolution carries
# EXACTLY ONE "> Resolution:" pointer; rows without one ("— …") must not
# carry a pointer. History: the class bit twice in a row (snapshot g, then
# snapshot l, then this very check's trigger — snapshot m, 0.0.39m D1).
review_pointer_check() {
    for snap in docs/design/review/[0-9]*-v*.md; do
        [ -e "$snap" ] || continue
        case "$snap" in
            *-resolution.md|*/template.md) continue ;;
        esac
        stem=$(basename "$snap" .md)
        row=$(grep -F "]($stem.md)" docs/design/review/README.md | head -n 1)
        if [ -z "$row" ]; then
            echo "FAIL $stem: no README index row" >> "$TMP"
            continue
        fi
        # 4th table cell ($5 under awk -F'|', cells are 2..6) = resolution column
        has_res=$(printf '%s\n' "$row" | awk -F'|' '{ gsub(/ /, "", $5); print ($5 ~ /resolution\.md\]/) ? 1 : 0 }')
        ptr=$(grep -c '^> Resolution:' "$snap")
        if [ "$has_res" = 1 ] && [ "$ptr" -ne 1 ]; then
            echo "FAIL $stem: index lists a resolution but the snapshot has $ptr pointer line(s) (README rule 2)" >> "$TMP"
        elif [ "$has_res" = 0 ] && [ "$ptr" -ne 0 ]; then
            echo "FAIL $stem: index lists no resolution yet but the snapshot carries a pointer" >> "$TMP"
        fi
    done
}
review_pointer_check

if [ -s "$TMP" ]; then
    echo "docs link check: FAILED"
    cat "$TMP"
    exit 1
fi

echo "docs link check: OK"
