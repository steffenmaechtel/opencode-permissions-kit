#!/bin/sh
# Unit tests for CI workflow consistency (issue #123):
#   1. exec bits live in the GIT INDEX, not in workflow chmod lists:
#      100755 <=> executed by path, 100644 <=> sourced lib / interpreter
#      call / data. actions/checkout preserves tracked modes, so CI needs
#      no chmod at all — the chmod lists this file used to enforce
#      compensated index drift and masked it at the same time (a 100644
#      file with a chmod entry looked healthy while every fresh checkout
#      without that workaround was broken).
#   2. no workflow carries chmod lines anymore (regression guard)
#   3. every unit suite on disk has a run: step in test-unit.yml (0.0.39a D20)
#   4. tsx syntax gate wiring (issue #114)
#   5. opencode 2.x pin jobs (issue #80)
#   6. YAML structure guards (one env block per step; run: block literals)
# Run: sh tests/unit/test-workflows.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WF_TEST="$REPO/.github/workflows/test-unit.yml"
WF_E2E="$REPO/.github/workflows/test-e2e.yml"
WF_DDEV_E2E="$REPO/.github/workflows/test-e2e-ddev.yml"
WF_ADVISORY="$REPO/.github/workflows/advisory-watch.yml"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

TMP_REQ="$(mktemp)"
TMP_755="$(mktemp)"
TMP_RUNS="$(mktemp)"
trap 'rm -f "$TMP_REQ" "$TMP_755" "$TMP_RUNS"' EXIT INT TERM

# --- 1. exec bits in the git index ---------------------------------------------

# The must-be-755 set: everything CI, make targets, or the kit invoke by
# path (shebang entry points). Derived from disk globs so the growth
# axes — new unit tests, new bin/ commands, new scripts/ helpers — are
# enforced automatically. Everything else (sourced sh/ libs, py/ called
# via python3, umask.sh via profile.d, ux demos and e2e fixtures run
# via `sh`, data templates) must stay 100644 — enforced by the inverse
# check below: a tracked file may only be 100755 if it is in this set.
collect_required_755() {
    for f in "$REPO"/tests/unit/test-*.sh \
             "$REPO"/tests/check-host.sh \
             "$REPO"/tests/tsx-syntax-gate.sh \
             "$REPO"/tests/e2e/run.sh \
             "$REPO"/tests/e2e/run-docker-rootless.sh \
             "$REPO"/tests/e2e/run-ddev.sh \
             "$REPO"/scripts/*.sh \
             "$REPO"/files/install.sh \
             "$REPO"/files/opencode-permissions-kit-lib/bin/* \
             "$REPO"/files/opencode-permissions-kit-lib/management/*.sh; do
        [ -f "$f" ] || continue
        printf '%s\n' "${f#"$REPO"/}"
    done | sort -u
}
collect_required_755 > "$TMP_REQ"

_missing=""
while IFS= read -r rel; do
    mode="$(git -C "$REPO" ls-files -s -- "./$rel" | awk '{print $1}')"
    if [ -z "$mode" ]; then
        _missing="$_missing $rel(not-tracked)"
    elif [ "$mode" != "100755" ]; then
        _missing="$_missing $rel($mode)"
    fi
done < "$TMP_REQ"
if [ -z "$_missing" ]; then
    pass "every executed-by-path file is 100755 in the git index"
else
    fail "exec-bit drift (git update-index --chmod=+x needed):$_missing"
fi

# Inverse: no tracked file may be 100755 unless it is executed by path.
git -C "$REPO" ls-files -s | awk '$1 == "100755" { print $4 }' | sort -u > "$TMP_755"
_stray="$(comm -13 "$TMP_REQ" "$TMP_755")"
if [ -z "$_stray" ]; then
    pass "no sourced/data file carries the exec bit (755 <=> executed by path)"
else
    fail "100755 on non-executable file(s) — flip with git update-index --chmod=-x:"
    echo "$_stray" | sed 's/^/         /'
fi

# --- 2. workflows carry no chmod lines ------------------------------------------

_chmodhits=""
for _wf in "$WF_TEST" "$WF_E2E" "$WF_DDEV_E2E" "$WF_ADVISORY"; do
    _hit="$(grep -n 'chmod' "$_wf")"
    [ -n "$_hit" ] && _chmodhits="$_chmodhits
${_wf##*/}: $_hit"
done
if [ -z "$_chmodhits" ]; then
    pass "no workflow chmods anything (exec bits come from the git index)"
else
    fail "workflow chmod lines — bits belong in the git index (issue #123):$_chmodhits"
fi

# --- 3. every unit suite on disk is actually RUN (0.0.39a D20) -------------------

# test-update-flags.sh and test-release.sh once sat on a chmod line with
# no run: step — invisible to every check. Every unit suite must appear
# in one of test-unit.yml's run: lines (local `make test` runs them all;
# CI must not silently skip any).
#
# Command-position only (0.0.42e C2): a .sh path that is an ARGUMENT on
# a run: line (test-kit-files.sh once carried test-tui-mode.sh that way)
# does not execute — the extraction below takes the first token of each
# command segment, so argument tokens never count as coverage.
run_tokens() {
    grep -E '^[[:space:]]+run: ' "$1" | sed 's/^[[:space:]]*run: *//' | awk '
        {
            gsub(/&&/, "\n"); gsub(/\|\|/, "\n"); gsub(/;/, "\n"); gsub(/\|/, "\n")
            n = split($0, seg, /\n/)
            for (i = 1; i <= n; i++) {
                m = split(seg[i], w, /[ \t]+/)
                for (j = 1; j <= m; j++) if (w[j] != "") { print w[j]; break }
            }
        }
    ' | grep -E '^\./[A-Za-z0-9_./-]+\.sh$' | sort -u
}

run_tokens "$WF_TEST" > "$TMP_RUNS"
_orphans=""
for _t in "$REPO"/tests/unit/test-*.sh; do
    _rel="./${_t#"$REPO"/}"
    grep -qxF "$_rel" "$TMP_RUNS" || _orphans="$_orphans $_rel"
done
if [ -z "$_orphans" ]; then
    pass "test-unit.yml: every unit suite on disk has a run step"
else
    fail "test-unit.yml: unit suite(s) without a run step:$_orphans"
fi

# Behavioral pin of the command-position rule itself (0.0.42e C2): an
# argument-position .sh on a run: line must NOT count as executed.
_FAKEWF="$(mktemp)"
TMP_FAKE="$(mktemp)"
printf '%s\n' \
    '      - name: one' \
    '        run: ./tests/unit/test-a.sh ./tests/unit/test-arg-only.sh' \
    '      - name: two' \
    '        run: cd x && ./tests/unit/test-b.sh' > "$_FAKEWF"
run_tokens "$_FAKEWF" > "$TMP_FAKE"
if grep -qxF './tests/unit/test-a.sh' "$TMP_FAKE" \
    && grep -qxF './tests/unit/test-b.sh' "$TMP_FAKE" \
    && ! grep -qxF './tests/unit/test-arg-only.sh' "$TMP_FAKE"; then
    pass "run_tokens: argument-position .sh paths do not count as executed"
else
    fail "run_tokens: command-position extraction is broken (argument counted or command missed)"
fi
rm -f "$_FAKEWF" "$TMP_FAKE"

# --- 4. tsx syntax gate wiring (issue #114) --------------------------------------

# The parse-only gate for the shipped tui/*.tsx assets lives in
# tests/tsx-syntax-gate.sh and runs ONLY in test-unit.yml (CI-only:
# node is not a contributor-host requirement). Silent removal would
# reopen the gap the gate closes (tsx syntax errors shipping green);
# these checks trip on it: run step present, the gate covers the whole
# tui tsx glob instead of a hand-maintained file list, installs via
# npm ci from the committed lockfile (integrity-verified — an
# `npm install` regression would drop that), and the pin/lockfile
# pair in tests/fixtures/tsx-gate/ is exact and in sync (no dist-tags
# or ranges; lockfile version == package.json version).
GATE_SCRIPT="$REPO/tests/tsx-syntax-gate.sh"
GATE_FIXTURE="$REPO/tests/fixtures/tsx-gate"
if [ ! -f "$GATE_SCRIPT" ]; then
    fail "tests/tsx-syntax-gate.sh missing (issue #114 gate)"
else
    _gmissing=""
    grep -qF 'sh tests/tsx-syntax-gate.sh' "$WF_TEST" || _gmissing="$_gmissing no-run-step"
    grep -qF 'tui/*.tsx' "$GATE_SCRIPT" || _gmissing="$_gmissing no-tsx-glob"
    # Invocation signature (not prose): ci-ness AND the install-scripts
    # hardening in one literal — header comments quoting "npm ci" must
    # not satisfy this check.
    grep -qF 'npm ci --ignore-scripts' "$GATE_SCRIPT" \
        || _gmissing="$_gmissing no-npm-ci"
    # Lockfile (lockfileVersion 3): the typescript block is the only
    # place a "version" key follows the "node_modules/typescript" key
    # inside one object; the range stops at its closing brace.
    _lock="$(sed -n '/"node_modules\/typescript": {/,/^    }/s/.*"version": "\(.*\)".*/\1/p' \
        "$GATE_FIXTURE/package-lock.json" 2>/dev/null | head -1)"
    _integ="$(sed -n '/"node_modules\/typescript": {/,/^    }/s/.*"integrity": "\(.*\)".*/\1/p' \
        "$GATE_FIXTURE/package-lock.json" 2>/dev/null | head -1)"
    _pin="$(sed -n 's/.*"typescript": "\([0-9][0-9.]*\)".*/\1/p' \
        "$GATE_FIXTURE/package.json" 2>/dev/null | head -1)"
    if [ -z "$_pin" ]; then
        _gmissing="$_gmissing package.json-pin-not-exact"
    elif [ -z "$_lock" ]; then
        _gmissing="$_gmissing lockfile-version-not-found"
    elif [ "$_pin" != "$_lock" ]; then
        _gmissing="$_gmissing pin-lockfile-desync($_pin/$_lock)"
    elif [ -z "$_integ" ]; then
        _gmissing="$_gmissing lockfile-integrity-missing"
    fi
    if [ -z "$_gmissing" ]; then
        pass "test-unit.yml: tsx syntax gate wired (run + npm ci lock + exact pin + glob)"
    else
        fail "test-unit.yml: tsx gate wiring incomplete:$_gmissing"
    fi
fi

# --- 5. opencode 2.x pin jobs (issue #80) --------------------------------------

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

# 0.0.45c C8: every v1 "Resolve opencode version" step (e2e + e2e-rootless
# in test-e2e.yml, e2e-ddev in test-e2e-ddev.yml) is authenticated (the
# ephemeral token, provisioned at the step — an anonymous rate-limit 403
# from a shared runner IP used to go green with an empty OC_VERSION and a
# degraded cache key) and anchored-validated like the 2x twins: a bad
# resolution fails the step loudly instead of reaching the cache key.
check_v1_resolve() {
    # args: workflow, expected step count, label
    _wf="$1"; _want="$2"; _label="$3"
    _hdr=$(grep -c -- '-H "Authorization: Bearer $OPK_GH_TOKEN"' "$_wf" || true)
    _err=$(grep -c '::error::opencode releases/latest resolved' "$_wf" || true)
    _gate=$(grep -c 'OC_VERSION=$OCV' "$_wf" || true)
    if [ "$_hdr" = "$_want" ] && [ "$_err" = "$_want" ] && [ "$_gate" = "$_want" ]; then
        pass "$_label: v1 resolve steps authenticated + validated (C8)"
    else
        fail "$_label: v1 resolve steps authenticated + validated (C8, hdr=$_hdr err=$_err gate=$_gate want=$_want)"
    fi
}
check_v1_resolve "$WF_E2E" 2 "test-e2e.yml (e2e + e2e-rootless)"
check_v1_resolve "$WF_DDEV_E2E" 1 "test-e2e-ddev.yml (e2e-ddev)"

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
# Manual dispatches run in their own concurrency group (0.0.44a V13): a
# workflow_dispatch resolves github.ref to refs/heads/master — the push
# run's group — and cancel-in-progress killed the push run, reddening
# scripts/release.sh's CI gate on exactly the release sha.
for _wf in test-unit test-e2e test-e2e-ddev; do
    if grep -qF "(github.event_name == 'push' || github.event_name == 'pull_request') && github.ref" \
        "$REPO/.github/workflows/$_wf.yml" \
       && grep -qF "|| 'manual' }}" "$REPO/.github/workflows/$_wf.yml"; then
        pass "$_wf.yml: dispatch gets its own concurrency group (V13)"
    else
        fail "$_wf.yml: dispatch gets its own concurrency group (V13)"
    fi
done

exit 0
