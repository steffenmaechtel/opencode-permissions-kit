#!/bin/sh
# opencode permissions kit -- scripts/gen-sums.sh
# Generates the SHA256SUMS integrity manifest (issue #478): one
# `<sha256>  <repo-relative-path>` line per streamed kit file, coreutils
# sha256sum format (two-space separator, `sha256sum -c` reads it back),
# LC_ALL=C-sorted by path so reordering the fetch list never flickers the
# file. The covered set is exactly update.sh's KIT_FILES -- the single
# source of truth both fetchers stream (tests/unit/test-kit-files.sh
# pins install.sh's list equal to it).
#
# The manifest lives at the repo root next to VERSION, so fetchers
# resolve it from the same ref they stream files from:
#   https://raw.githubusercontent.com/<repo>/<ref>/SHA256SUMS
#
# Usage (writes the manifest to stdout; `make sums` redirects it):
#   make sums     # regenerate + commit SHA256SUMS with your PR
#
# Deliberately NOT covered: SHA256SUMS itself (a manifest cannot carry
# its own digest -- chicken and egg; fetchers shape-gate it instead of
# hash-pinning it) and everything outside KIT_FILES (docs, tests are
# never streamed to install targets).
#
# Drift is gated twice: tests/unit/test-fetch-integrity.sh regenerates
# and diffs on every `make test`, and scripts/release.sh refuses to cut
# a release from a stale manifest.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"

if [ ! -f "$UPDATE" ]; then
    echo "error: $UPDATE not found -- run from a kit checkout" >&2
    exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
    echo "error: sha256sum is required (coreutils)" >&2
    exit 1
fi

# KIT_FILES extraction -- the same normalize idiom as
# tests/unit/test-kit-files.sh (the one-file-per-line backslash-continued
# list layout is convention, agent/conventions.md "Script output style").
_names="$(sed -n '/^KIT_FILES="/,/"$/p' "$UPDATE" |
    sed -e 's/^KIT_FILES="//' -e 's/"$//' -e 's/\\$//' |
    tr '\n' ' ')"
if [ -z "$_names" ]; then
    echo "error: KIT_FILES extraction came up empty -- update.sh layout drifted?" >&2
    exit 1
fi

# Pass 1 validates every listed file BEFORE any output leaves the
# script: a red run never emits a partial manifest (a caller's redirect
# must not truncate into garbage on failure).
# word splitting intended: the list is whitespace-separated by contract
# shellcheck disable=SC2086
for _n in $(printf '%s\n' $_names | LC_ALL=C sort); do
    case "$_n" in
        SHA256SUMS)
            echo "error: SHA256SUMS must not be a KIT_FILES entry (a manifest cannot carry its own digest)" >&2
            exit 1
            ;;
    esac
    if [ "$_n" = "VERSION" ]; then
        _path="$REPO/VERSION"
    else
        _path="$REPO/files/$_n"
    fi
    if [ ! -f "$_path" ]; then
        echo "error: listed kit file missing from the checkout: $_n" >&2
        exit 1
    fi
done
# Pass 2 emits the manifest (LC_ALL=C path order — stable diffs when the
# fetch list is reordered). Paths are REPO-ROOT-relative (`files/<name>`
# and `VERSION`): the fetch tree mirrors the repo root exactly, so the
# whole-tree check is a plain `sha256sum -c` from the staging root.
# shellcheck disable=SC2086
for _n in $(printf '%s\n' $_names | LC_ALL=C sort); do
    if [ "$_n" = "VERSION" ]; then
        _path="$REPO/VERSION"
        _mname="VERSION"
    else
        _path="$REPO/files/$_n"
        _mname="files/$_n"
    fi
    _sum="$(sha256sum "$_path")"
    printf '%s  %s\n' "${_sum%% *}" "$_mname"
done
