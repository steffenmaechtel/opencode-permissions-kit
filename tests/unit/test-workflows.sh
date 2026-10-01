#!/bin/sh
# Unit tests for CI workflow consistency (AGENTS.md rule: every executable
# goes into the chmod +x list of ALL workflow files that run it):
#   1. every ./path a workflow chmods must exist in the repo (renames and
#      typos otherwise fail silently — CI chmods a ghost and loses the bit)
#   2. every executable CI needs (unit tests, e2e scripts, check-host,
#      shipped scripts under files/) must be chmodded in ALL workflow
#      files that run it: test-unit.yml, test-e2e.yml, test-e2e-ddev.yml
#   3. the e2e workflows must keep their opencode 2.x pin jobs (issue #80)
#
# Git checkouts lose the exec bit, so a missing entry means the affected
# suite breaks only in CI — exactly the drift this test trips on.
# Run: sh tests/unit/test-workflows.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WF_TEST="$REPO/.github/workflows/test-unit.yml"
WF_E2E="$REPO/.github/workflows/test-e2e.yml"
WF_DDEV_E2E="$REPO/.github/workflows/test-e2e-ddev.yml"

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

for wf in "$WF_TEST" "$WF_E2E" "$WF_DDEV_E2E"; do
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

# --- 2. required executables in ALL workflow files -----------------------------

# Canonical set: everything CI executes by path. Derived from disk so a new
# test-*.sh automatically enforces its own workflow entries. Exceptions are
# files never executed directly:
#   files/etc/umask.sh                     sourced via /etc/profile.d
#   jsonc-parser.py                    invoked via python3
#   *.jsonc, sudoers.template          data, not code
required=""
for f in "$REPO"/tests/unit/test-*.sh \
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
        umask.sh|jsonc-parser.py|tui-register.py|*.jsonc|sudoers.template) continue ;;
    esac
    required="$required ./${f#"$REPO"/}"
done

for wf in "$WF_TEST" "$WF_E2E" "$WF_DDEV_E2E"; do
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

# --- 2b. every chmodded unit suite is actually RUN (0.0.39a D20) ----------------

# test-update-flags.sh and test-release.sh sat on the chmod line of
# test-unit.yml with no run: step — the chmod list only proves the path
# exists, so the orphaned suites were invisible to every check. Every
# unit suite chmodded in test-unit.yml must appear in one of its run:
# lines (local `make test` runs them all; CI must not silently skip any).
run_tokens() {
    grep -E '^[[:space:]]+run: ' "$1" | grep -oE '\./[A-Za-z0-9_./-]+\.sh' | sort -u
}

TMP_RUNS="$(mktemp)"
trap 'rm -f "$TMP_TOKENS" "$TMP_RUNS"' EXIT INT TERM
run_tokens "$WF_TEST" > "$TMP_RUNS"
orphans=""
# word splitting is safe: repo paths never contain whitespace
# shellcheck disable=SC2046
for tok in $(chmod_tokens "$WF_TEST" | grep -E '^\./tests/unit/test-'); do
    grep -qxF "$tok" "$TMP_RUNS" || orphans="$orphans $tok"
done
if [ -z "$orphans" ]; then
    pass "test-unit.yml: every chmodded unit suite has a run step"
else
    fail "test-unit.yml: chmodded but never run:$orphans"
fi

# --- 2b. scripts/ executables in test-unit.yml (0.0.39a D21) --------------------

# The required set above derives from tests/ + files/ only, so
# scripts/release.sh and scripts/advisory-watch.sh were never enforced.
# Only test-unit.yml chmods both (the e2e workflows never execute them);
# the bit matters there because test-release.sh and the advisory suite
# run them by path.
_smissing=""
for _s in ./scripts/release.sh ./scripts/advisory-watch.sh; do
    chmod_tokens "$WF_TEST" | grep -qxF "$_s" || _smissing="$_smissing $_s"
done
if [ -z "$_smissing" ]; then
    pass "test-unit.yml: scripts/release.sh + scripts/advisory-watch.sh chmodded"
else
    fail "test-unit.yml: scripts chmod entries missing:$_smissing"
fi

# --- 3. opencode 2.x pin jobs (issue #80) --------------------------------------

# The e2e workflows run the suites a second time against the CURRENT 2.x
# release (npm dist-tag latest — 2.x ships no GitHub release assets).
# Silent removal would weaken 2.x coverage with no local signal; these
# checks trip on it. Patterns per file:
#   job id           — one 2x job per suite the workflow runs
#   npm resolution   — the version comes from the npm registry, the
#                      source tests/e2e/lib.sh downloads 2.x pins from
#   E2E_OC_VERSION   — the runner receives the resolved version as a pin
#   anchored guard   — the version is validated against an anchored
#                      2.x semver regex (grep -qE '^2\.[0-9]+(\.[0-9]+)*$')
#                      before it reaches GITHUB_OUTPUT; the BRE pattern below
#                      matches the literal "^2\.[0" head of that regex

check_2x() {
    _wf="$1"; _name="${_wf##*/}"; shift
    _missing=""
    for _pat in "$@"; do
        grep -q -- "$_pat" "$_wf" || _missing="$_missing [$_pat]"
    done
    if [ -z "$_missing" ]; then
        pass "$_name: 2.x pin jobs present (npm resolution + pin + 2.* guard)"
    else
        fail "$_name: 2.x pin wiring incomplete:$_missing"
    fi
}

check_2x "$WF_E2E" \
    '^  e2e-2x:' \
    '^  e2e-rootless-2x:' \
    'registry.npmjs.org/@opencode/cli-linux-x64/latest' \
    'E2E_OC_VERSION' \
    '\^2\\\.\[0' \
    '::error::npm dist-tag latest'

check_2x "$WF_DDEV_E2E" \
    '^  e2e-ddev-2x:' \
    'registry.npmjs.org/@opencode/cli-linux-x64/latest' \
    'E2E_OC_VERSION' \
    '\^2\\\.\[0' \
    '::error::npm dist-tag latest'

# Structural YAML guard (workflow-upload breakage 2026-09-25: a second
# env: block on a step that already had one made GitHub reject the whole
# file): every step may carry at most ONE env: block.
_dups=0
for _wf in "$WF_TEST" "$WF_E2E" "$WF_DDEV_E2E"; do
    _out=$(awk '/^      - /{ if (c>1) { print FILENAME ": " prev " (" c " env blocks)" }; c=0; prev=$0 }
                /^        env:/{c++}
                END{ if (c>1) { print FILENAME ": " prev " (" c " env blocks)" } }' "$_wf")
    [ -n "$_out" ] && { echo "$_out"; _dups=1; }
done
if [ "$_dups" = 0 ]; then
    pass "no workflow step carries more than one env block"
else
    fail "no workflow step carries more than one env block"
fi

# YAML scalar guard (test-unit.yml chmod breakage 2026-10-01: a plain
# multi-line `run:` scalar folds every newline to a space, so each shell
# backslash continuation became an escaped space and chmod received
# ' ./path' with a leading blank — file not found). Multi-line run
# scripts MUST use a block literal (`run: |`), never a plain scalar.
_plain=0
for _wf in "$WF_TEST" "$WF_E2E" "$WF_DDEV_E2E"; do
    _out=$(grep -nE '^[[:space:]]+run: [^|>].*\\$' "$_wf")
    [ -n "$_out" ] && { echo "$_wf:$_out"; _plain=1; }
done
if [ "$_plain" = 0 ]; then
    pass "no plain multi-line run: scalars (block literals only)"
else
    fail "plain multi-line run: scalar(s) above must be 'run: |' block literals"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All workflow consistency tests passed.$NC"
exit 0
