#!/bin/sh
# opencode permissions kit -- release-sums.sh
#
# Rewrites the entry-checksum marker blocks in README.md and
# docs/getting-started.md with the sha256 of files/install.sh
# (issue #492: Composer-style verified install for the stable channel).
#
# RELEASE-FLOW ONLY. The hash describes the bytes the Pages entry serves
# from the `stable` mirror; a mid-cycle regeneration would publish a
# hash for bytes stable does not serve yet -- users' verification would
# fail falsely until the release lands. Mid-cycle waves never owe this
# target (AGENTS.md, Testing); `make release` pre-flights freshness via
# --check and refuses to cut a release from a stale block.
#
# Modes:
#   sh scripts/release-sums.sh          rewrite the blocks (make release-sums)
#   sh scripts/release-sums.sh --check  verify freshness, write nothing,
#                                       rc 1 + instruction on drift
#
# Idempotent: a fresh tree rewrites nothing.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY="$REPO/files/install.sh"
BLOCK_FILES="README.md docs/getting-started.md"
CHECK=0
if [ "${1:-}" = "--check" ]; then
    CHECK=1
elif [ -n "${1:-}" ]; then
    echo "release-sums: unknown argument: $1 (expected --check or none)" >&2
    exit 1
fi

if [ ! -f "$ENTRY" ]; then
    echo "release-sums: $ENTRY missing -- run from a kit checkout" >&2
    exit 1
fi
entry_sha="$(sha256sum "$ENTRY" | cut -d' ' -f1)"

rc=0
for f in $BLOCK_FILES; do
    path="$REPO/$f"
    if [ ! -f "$path" ]; then
        echo "release-sums: $path missing" >&2
        exit 1
    fi
    starts=$(grep -c '^<!-- opk-checksum:start -->$' "$path" || true)
    ends=$(grep -c '^<!-- opk-checksum:end -->$' "$path" || true)
    if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then
        echo "release-sums: $f needs exactly one opk-checksum marker pair (start=$starts end=$ends)" >&2
        exit 1
    fi
    block_hash="$(sed -n '/^<!-- opk-checksum:start -->$/,/^<!-- opk-checksum:end -->$/p' "$path" |
        sed -n 's/^echo "\([0-9a-f]\{64\}\)  \/tmp\/opk-install.sh" | sha256sum -c -$/\1/p')"
    if [ -z "$block_hash" ]; then
        echo "release-sums: $f marker block lacks the echo \"<sha256>  /tmp/opk-install.sh\" line" >&2
        exit 1
    fi
    if [ "$block_hash" = "$entry_sha" ]; then
        if [ "$CHECK" -eq 0 ]; then
            echo "release-sums: $f entry checksum already fresh"
        fi
        continue
    fi
    if [ "$CHECK" -eq 1 ]; then
        echo "release-sums: $f entry checksum stale: block has $block_hash, tree install.sh is $entry_sha" >&2
        rc=1
    else
        # Temp+mv on purpose (the make sums pattern): a failed rewrite
        # must never truncate the committed page in the working tree.
        _rs_tmp="${path}.release-sums.$$"
        if ! awk -v sha="$entry_sha" '
            /^<!-- opk-checksum:start -->$/ { print; inblock = 1; next }
            /^<!-- opk-checksum:end -->$/ { inblock = 0; print; next }
            inblock && /^echo "[0-9a-f][0-9a-f]*  \/tmp\/opk-install.sh" \| sha256sum -c -$/ {
                print "echo \"" sha "  /tmp/opk-install.sh\" | sha256sum -c -"
                next
            }
            { print }
        ' "$path" >"$_rs_tmp"; then
            echo "release-sums: rewriting $f failed" >&2
            rm -f "$_rs_tmp"
            exit 1
        fi
        mv "$_rs_tmp" "$path"
        echo "release-sums: $f entry checksum -> $entry_sha"
    fi
done

if [ "$CHECK" -eq 1 ] && [ "$rc" -ne 0 ]; then
    echo "release-sums: regenerate in the release PR:  make release-sums" >&2
fi
exit $rc
