#!/bin/sh
# test-docs.sh -- documentation link checker (no external dependencies)
#
# Fails when any Markdown file under docs/, .agents/, plus README.md,
# CONTRIBUTING.md and AGENTS.md, contains a broken relative link or a
# dangling in-page anchor. HTTP(S)/mailto links are skipped (no network
# access).
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
        internal/reviews/*/pr-*/review-*.md) return 0 ;;
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
                # review case folders link to the listing itself: lint
                # forbids any extra file inside a case (no README.md can
                # ever exist there)
                case "$base" in
                    internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-[0-9][0-9][0-9][0-9][0-9]) continue ;;
                esac
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
# areas live at agent/ and internal/ (process/records/reviews/reviews-meta),
# agent skills at .agents/skills/ (issue #178).
for dir in docs agent internal .agents; do
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

# --- F36: cli.md's install flag table tracks the parser (#211 a F36) --------------
# Claim-drift guard: every flag install.sh's parse_args accepts must
# appear in docs/reference/cli.md (the table F23 filled). Sabotage:
# delete a row or add a parser flag — this goes red.
# #211 b W28: tripwire — a drifted parse_args anchor must not silently
# iterate zero flags and pass.
# #211 b W30: reverse direction — every flag documented in cli.md's
# install table must exist in the parser. The original one-directional
# pin shipped W2 exactly this way: a documented `-y` the parser
# rejected was invisible to it.
_cli_md="$REPO_ROOT/docs/reference/cli.md"
_f36_flags="$(sed -n '/^parse_args()/,/^}/p' "$REPO_ROOT/files/install.sh" \
    | grep -oE '\-\-[a-z0-9-]+' | sort -u)"
if [ -z "$_f36_flags" ]; then
    echo "FAIL cli.md: parse_args extraction empty — anchor drift? (#211 b W28)" >> "$TMP"
fi
for _f36_flag in $_f36_flags; do
    if ! grep -qF -e "$_f36_flag" "$_cli_md"; then
        echo "FAIL cli.md: install flag '$_f36_flag' missing from the reference" >> "$TMP"
    fi
done
# Reverse: the install table sits under '## install.sh' (## section,
# table rows `| \`--flag\`, \`-y\` | ...`).
_f36_docflags="$(sed -n '/^## install.sh/,/^## /p' "$_cli_md" \
    | grep '^| ' | grep -v '^| Flag' \
    | sed -n 's/^| \([^|]*\) |.*/\1/p' | tr -d '`,' | tr -s ' ' '\n' | grep -E '^-.-?' | sort -u)"
# Tripwire (#211 c W4 — the W28 class on the reverse direction): a
# drifted '## install.sh' heading must not silently iterate zero flags
# and pass.
if [ -z "$_f36_docflags" ]; then
    echo "FAIL cli.md: install-table extraction empty — '## install.sh' anchor drift? (#211 c W4)" >> "$TMP"
fi
for _f36_df in $_f36_docflags; do
    case "$_f36_df" in
        --*)
            printf '%s\n' "$_f36_flags" | grep -qxF -- "$_f36_df" \
                || echo "FAIL cli.md: documented install flag '$_f36_df' not in the parser (#211 b W30)" >> "$TMP"
            ;;
        -?)
            sed -n '/^parse_args()/,/^}/p' "$REPO_ROOT/files/install.sh" \
                | grep -qF -- "|$_f36_df)" \
                || echo "FAIL cli.md: documented alias '$_f36_df' not in the parser (#211 b W30)" >> "$TMP"
            ;;
    esac
done

if [ -s "$TMP" ]; then
    echo "docs link check: FAILED"
    cat "$TMP"
    exit 1
fi

echo "docs link check: OK"
