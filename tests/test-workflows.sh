#!/bin/sh
# Unit tests for CI workflow consistency (AGENTS.md rule: every executable
# goes into the chmod +x list of BOTH workflow files):
#   1. every ./path a workflow chmods must exist in the repo (renames and
#      typos otherwise fail silently — CI chmods a ghost and loses the bit)
#   2. every executable CI needs (unit tests, e2e scripts, check-host,
#      shipped scripts under files/) must be chmodded in BOTH
#      .github/workflows/test.yml and .github/workflows/e2e.yml
#
# Git checkouts lose the exec bit, so a missing entry means the affected
# suite breaks only in CI — exactly the drift this test trips on.
# Run: sh tests/test-workflows.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WF_TEST="$REPO/.github/workflows/test.yml"
WF_E2E="$REPO/.github/workflows/e2e.yml"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

# Extract all ./tokens from every chmod line of a workflow file. Joins
# backslash line continuations first (the lists span multiple lines).
chmod_tokens() {
    sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$1" \
        | grep -oE 'chmod \+x .*' \
        | tr ' ' '\n' \
        | grep -E '^\./' \
        | sort -u
}

TMP_TOKENS="$(mktemp)"
trap 'rm -f "$TMP_TOKENS"' EXIT INT TERM

# --- 1. every chmodded path exists ------------------------------------------

for wf in "$WF_TEST" "$WF_E2E"; do
    name="${wf##*/}"
    chmod_tokens "$wf" > "$TMP_TOKENS"
    ghosts=""
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        [ -e "$REPO/$tok" ] || ghosts="$ghosts $tok"
    done < "$TMP_TOKENS"
    if [ -z "$ghosts" ]; then
        pass "$name: every chmodded path exists"
    else
        fail "$name: chmodded paths missing in repo:$ghosts"
    fi
done

# --- 2. required executables in BOTH workflow files --------------------------

# Canonical set: everything CI executes by path. Derived from disk so a new
# test-*.sh automatically enforces its own workflow entries. Exceptions are
# files never executed directly:
#   files/umask.sh                     sourced by /etc/profile.d
#   jsonc-parser.py                    invoked via python3
#   migrate-denies.sh                  fetch-only compat stub
#   *.jsonc, sudoers.template          data, not code
required=""
for f in "$REPO"/tests/test-*.sh \
         "$REPO"/tests/check-host.sh \
         "$REPO"/tests/e2e/run.sh \
         "$REPO"/tests/e2e/run-docker-rootless.sh \
         "$REPO"/tests/e2e/run-ddev.sh \
         "$REPO"/tests/e2e/lib.sh; do
    required="$required ./${f#"$REPO"/}"
done
for f in $(find "$REPO/files" -type f | sort); do
    base="${f##*/}"
    case "$base" in
        umask.sh|jsonc-parser.py|migrate-denies.sh|*.jsonc|sudoers.template) continue ;;
    esac
    required="$required ./${f#"$REPO"/}"
done

for wf in "$WF_TEST" "$WF_E2E"; do
    name="${wf##*/}"
    chmod_tokens "$wf" > "$TMP_TOKENS"
    missing=""
    for req in $required; do
        grep -qxF "$req" "$TMP_TOKENS" || missing="$missing $req"
    done
    if [ -z "$missing" ]; then
        pass "$name: all required executables chmodded"
    else
        fail "$name: missing chmod entries:$missing"
    fi
done

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All workflow consistency tests passed.$NC"
exit 0
