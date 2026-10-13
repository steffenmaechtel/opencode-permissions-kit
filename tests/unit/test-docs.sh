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

# Frozen-history exemption (structure wave 2026-10): immutable review
# snapshots and archived records may reference paths that later moved —
# history is not rewritten for link hygiene. Living docs (resolutions,
# READMEs, records, user docs) must stay fully linked.
is_frozen() {
    case "$1" in
        internal/reviews/pr-*/review-*.md) return 0 ;;
        internal/records/_archive/*) return 0 ;;
    esac
    return 1
}

check_file() {
    f="$1"
    is_frozen "$f" && return 0
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
# Docs scope (structure wave 2026-10): user docs stay under docs/, internal
# areas live at agent/ and internal/ (process/records/reviews/reviews-meta).
for dir in docs agent internal; do
    find "$dir" -name '*.md' -type f
done | sort | while IFS= read -r f; do
    check_file "$f"
done

# Records status consistency (structure wave 2026-10, PR 3): every
# internal/records/*.md carries a "> Status: **WORD**" line (corpus
# vocabulary IMPLEMENTED | CURRENT | SUPERSEDED) and the records index
# README shows the same word in that record's table row.
records_status_check() {
    for f in internal/records/*.md; do
        case "$f" in */README.md) continue ;; esac
        base=$(basename "$f")
        word=$(sed -n 's/^> Status: \*\*\([A-Z][A-Z]*\).*/\1/p' "$f" | head -n 1)
        if [ -z "$word" ]; then
            echo "FAIL $base: no '> Status: **WORD**' line" >> "$TMP"
            continue
        fi
        case "$word" in
            IMPLEMENTED|CURRENT|SUPERSEDED) ;;
            *) echo "FAIL $base: status word '$word' outside the vocabulary" >> "$TMP" ;;
        esac
        row=$(grep -F "]($base)" internal/records/README.md)
        if [ -z "$row" ]; then
            echo "FAIL $base: no records/README index row" >> "$TMP"
        elif ! printf '%s\n' "$row" | grep -Fq "| $word |"; then
            echo "FAIL $base: file says $word, README row differs" >> "$TMP"
        fi
    done
}
records_status_check

if [ -s "$TMP" ]; then
    echo "docs link check: FAILED"
    cat "$TMP"
    exit 1
fi

echo "docs link check: OK"
