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
# target (agent/gates.md, Checksums and generated indexes); `make
# release` pre-flights freshness via --check and refuses to cut a
# release from a stale block.
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
# No pipefail in POSIX sh: the pipeline's rc is cut's, and cut succeeds
# on empty input -- a failing sha256sum would yield an EMPTY hash that
# rewrite mode would write into both pages (pr-00600 a A3). Validate the
# shape before anything uses it.
entry_sha="$(sha256sum "$ENTRY" | cut -d' ' -f1)"
if ! printf '%s' "$entry_sha" | grep -q '^[0-9a-f]\{64\}$'; then
    echo "release-sums: could not derive a sha256 for $ENTRY (got '${entry_sha:-empty}') -- aborting" >&2
    exit 1
fi

# Temp hygiene (pr-00600 a A2): a predictable $$ name in this
# group-writable checkout is a symlink-plant target (the redirect
# follows it), and an interrupted run must not leak the temp into the
# tree (release.sh arms the same traps, #493 a B4). mktemp makes the
# name unguessable; the traps clean up on every exit path.
_rs_tmp=""
trap 'rm -f "${_rs_tmp:-}"' EXIT
trap 'rm -f "${_rs_tmp:-}"; exit 130' INT
trap 'rm -f "${_rs_tmp:-}"; exit 143' TERM

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
        sed -n 's/^echo "\([0-9a-f]\{64\}\)  \/tmp\/opk-install.sh" | sha256sum -c - &&$/\1/p')"
    if [ -z "$block_hash" ]; then
        echo "release-sums: $f marker block lacks the echo \"<sha256>  /tmp/opk-install.sh\" | sha256sum -c - && line" >&2
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
        _rs_tmp="$(mktemp "${path}.release-sums.XXXXXX")" || {
            echo "release-sums: mktemp failed for $f" >&2
            exit 1
        }
        if ! awk -v sha="$entry_sha" '
            /^<!-- opk-checksum:start -->$/ { print; inblock = 1; next }
            /^<!-- opk-checksum:end -->$/ { inblock = 0; print; next }
            inblock && /^echo "[0-9a-f][0-9a-f]*  \/tmp\/opk-install.sh" \| sha256sum -c - &&$/ {
                print "echo \"" sha "  /tmp/opk-install.sh\" | sha256sum -c - &&"
                next
            }
            { print }
        ' "$path" >"$_rs_tmp"; then
            echo "release-sums: rewriting $f failed" >&2
            rm -f "$_rs_tmp"
            exit 1
        fi
        mv "$_rs_tmp" "$path"
        _rs_tmp=""
        # Post-rewrite verification (pr-00600 a A4): the guard above
        # counts marker pairs, not echo lines -- a duplicated echo line
        # would have been "rewritten" to duplicated canonical lines with
        # a success message. Re-extract and demand exactly one line
        # equal to the entry hash before reporting success.
        _new_hash="$(sed -n '/^<!-- opk-checksum:start -->$/,/^<!-- opk-checksum:end -->$/p' "$path" |
            sed -n 's/^echo "\([0-9a-f]\{64\}\)  \/tmp\/opk-install.sh" | sha256sum -c - &&$/\1/p')"
        if [ "$(printf '%s\n' "$_new_hash" | grep -c .)" -ne 1 ] ||
            [ "$_new_hash" != "$entry_sha" ]; then
            echo "release-sums: $f rewrite verification failed (expected exactly one '$entry_sha' line) -- fix the marker block by hand" >&2
            exit 1
        fi
        echo "release-sums: $f entry checksum -> $entry_sha"
    fi
done

if [ "$CHECK" -eq 1 ] && [ "$rc" -ne 0 ]; then
    echo "release-sums: regenerate in the release PR:  make release-sums" >&2
fi
exit $rc
