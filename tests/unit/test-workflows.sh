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
# widen to the late _FAKEWF/TMP_FAKE receivers (#283) — created far
# below inside the command-position pin; unset-safe until then. Arms on
# this physical line: the trap-coverage guard reads line-based.
trap 'rm -f "${TMP_REQ:-}" "${TMP_755:-}" "${TMP_RUNS:-}" "${_FAKEWF:-}" "${TMP_FAKE:-}"' EXIT INT TERM

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

# --- 5. e2e version lanes (issues #80 + #197) ----------------------------------
#
# Since the 2026-10 flip (issue #197) the 2x lanes run the CURRENT
# opencode 2.x from the npm dist-tag latest (2.x ships no GitHub
# release assets; releases/latest stays 1.x), and the -1x twins
# keep 1.x an explicit lane from GitHub releases/latest. Job names
# are major-explicit (lane-naming wave 2026-10-23): no bare default
# name survives, and the core suite's git dimension is a pair of
# explicit jobs (e2e-2x-git-distro / e2e-2x-git-latest) instead of a
# matrix. Both resolutions are anchored-validated against their lane's
# major and fail the job loudly on a mismatch (the upstream flip
# signals); the 1x pin reaches the runner as an env value, never
# interpolated into a run: shell. Silent removal, a re-swap of the
# lanes, or one lane drifting onto the wrong registry trips these
# checks. File-level greps cannot tell WHICH job carries which
# resolution — the checks run against the per-job block instead.

job_block() {  # $1 = workflow file, $2 = job id -> the job's lines on stdout
    awk -v hdr="  $2:" '
        index($0, hdr) == 1 { p = 1; next }
        p && /^  [A-Za-z0-9_-]+:/ { exit }
        p { print }
    ' "$1"
}

check_job_lane() {  # wf label job ere-pattern...
    _wf="$1"; _label="$2"; _job="$3"; shift 3
    _blk="$(job_block "$_wf" "$_job")"
    if [ -z "$_blk" ]; then
        fail "$_label (job '$_job' not found)"
        return
    fi
    _missing=""
    for _pat in "$@"; do
        printf '%s\n' "$_blk" | grep -qE -- "$_pat" || _missing="$_missing [$_pat]"
    done
    if [ -z "$_missing" ]; then
        pass "$_label"
    else
        fail "$_label:$_missing"
    fi
}

# 2x lanes: npm dist-tag latest, anchored 2.x guard, the former
# 2x-lane cache keys (adopted byte-identical with the flip so the warm
# caches carried over). The 2x jobs run the suite UNPINNED — lib.sh
# resolves the same npm channel itself at run time; the step resolution
# exists for the cache key and the flip signal.
for _job in e2e-2x-git-distro e2e-2x-git-latest e2e-rootless-2x; do
    check_job_lane "$WF_E2E" "test-e2e.yml: '$_job' resolves npm 2.x (guard + 2x cache key)" "$_job" \
        'registry\.npmjs\.org/@opencode/cli-linux-x64/latest' \
        '\^2\\\.\[0' \
        '::error::npm dist-tag latest' \
        'key: opencode-e2e-2x-'
done
check_job_lane "$WF_DDEV_E2E" "test-e2e-ddev.yml: 'e2e-ddev-2x' resolves npm 2.x (guard + 2x cache key)" e2e-ddev-2x \
    'registry\.npmjs\.org/@opencode/cli-linux-x64/latest' \
    '\^2\\\.\[0' \
    '::error::npm dist-tag latest' \
    'key: opencode-e2e-2x-npm' \
    'OPK_GH_TOKEN: \$\{\{ github\.token \}\}'

# The git pair must stay explicit and complete (issue #118 / #116):
# the PPA leg is the only lane that can see new-git breakage — a lost
# env value would silently collapse it onto the distro channel. Both
# halves NAME their channel (convention: no git suffix = git-distro).
check_job_lane "$WF_E2E" "test-e2e.yml: 'e2e-2x-git-latest' runs the PPA git leg (E2E_GIT_CHANNEL)" e2e-2x-git-latest \
    'E2E_GIT_CHANNEL: latest'
check_job_lane "$WF_E2E" "test-e2e.yml: 'e2e-2x-git-distro' names the distro channel (E2E_GIT_CHANNEL)" e2e-2x-git-distro \
    'E2E_GIT_CHANNEL: distro'
# Comment-strip riders (#261, the #244 g W1 class): a commented-out
# lane value stops counting; full-line comments only (#244 h W6
# residual).
_n_latest=$(sed 's/^[[:space:]]*#.*$//' "$WF_E2E" | grep -c 'E2E_GIT_CHANNEL: latest' || true)
_n_distro=$(sed 's/^[[:space:]]*#.*$//' "$WF_E2E" | grep -c 'E2E_GIT_CHANNEL: distro' || true)
if [ "$_n_latest" = 1 ] && [ "$_n_distro" = 1 ]; then
    pass "git channel values appear exactly once each (latest + distro, git pair only)"
else
    fail "git channel value counts off (latest:$_n_latest, distro:$_n_distro — expected 1/1)"
fi

# Explicit 1x lanes (renamed from the -2x twins, issue #197): GitHub
# releases/latest, authenticated (0.0.45c C8 contract kept through the
# flip — the ephemeral token, never an anonymous call from a shared
# runner IP), anchored 1.x guard, the version as an env pin, the former
# v1-era default cache keys.
for _job in e2e-1x e2e-rootless-1x; do
    check_job_lane "$WF_E2E" "test-e2e.yml: '$_job' resolves GitHub 1.x (auth + guard + env pin + v1 cache key)" "$_job" \
        'api\.github\.com/repos/anomalyco/opencode/releases/latest' \
        '-H "Authorization: Bearer \$OPK_GH_TOKEN"' \
        '\^1\\\.\[0' \
        '::error::opencode releases/latest resolved' \
        'OC_VERSION=\$OCV' \
        'E2E_OC_VERSION: \$\{\{' \
        'key: opencode-e2e-old'
done
check_job_lane "$WF_DDEV_E2E" "test-e2e-ddev.yml: 'e2e-ddev-1x' resolves GitHub 1.x (auth + guard + env pin + v1 cache key)" e2e-ddev-1x \
    'api\.github\.com/repos/anomalyco/opencode/releases/latest' \
    '-H "Authorization: Bearer \$OPK_GH_TOKEN"' \
    '\^1\\\.\[0' \
    '::error::opencode releases/latest resolved' \
    'OC_VERSION=\$OCV' \
    'E2E_OC_VERSION: \$\{\{' \
    'key: opencode-e2e-latest'

# The implicit-default job names must stay GONE (lane-naming wave
# 2026-10-23): the bare 'e2e'/'e2e-rootless'/'e2e-ddev' names silently
# changed meaning at every major flip — a surviving or reintroduced
# bare name recreates exactly that ambiguity in branch-protection and
# status references. Names carry the major now.
_bare="$(grep -hE '^  e2e(-rootless|-ddev)?:$' "$WF_E2E" "$WF_DDEV_E2E" || true)"
if [ -z "$_bare" ]; then
    pass "no implicit-default job names (bare e2e/e2e-rootless/e2e-ddev) — names carry the major"
else
    fail "implicit-default job name(s) survive the lane-naming wave:$_bare"
fi

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

# --- 7. e2e path-filter = e2e inputs --------------------------------------------
#
# The e2e workflows' 'code' set must stay the e2e INPUTS only
# (files/**, tests/e2e/**, .github/**, Makefile, VERSION — rationale in
# the workflow headers): the suites source nothing from scripts/ or the
# non-e2e test trees, so those waves must not burn the e2e runners.
# Silent re-broadening (tests/**, scripts/**) trips these checks; a
# DELIBERATE re-widening — wiring a scripts/ helper or a new tests/
# tree into the suite — updates the lists here together with the
# workflow (and necessarily touches tests/e2e/** or the Makefile, which
# trigger the suites anyway).

filter_block() {  # print the dorny/paths-filter entry list of a workflow
    awk '/filters: \|/{f=1; next} f && /^[^[:space:]]/ {f=0} f' "$1"
}

check_e2e_filter() {
    _wf="$1"; _name="${_wf##*/}"
    _blk="$(filter_block "$_wf")"
    _missing=""
    for _pat in "- 'files/**'" "- 'tests/e2e/**'" "- '.github/**'" "- 'Makefile'" "- 'VERSION'"; do
        printf '%s\n' "$_blk" | grep -qF -- "$_pat" || _missing="$_missing [$_pat]"
    done
    _broad=""
    printf '%s\n' "$_blk" | grep -qF -- "- 'tests/**'" && _broad="$_broad [tests/**]"
    printf '%s\n' "$_blk" | grep -qF -- "- 'scripts/**'" && _broad="$_broad [scripts/**]"
    if [ -z "$_missing" ] && [ -z "$_broad" ]; then
        pass "$_name: code filter = e2e inputs (files/, tests/e2e/, .github/, Makefile, VERSION)"
    else
        fail "$_name: code filter drifted:$_missing$_broad"
    fi
}
check_e2e_filter "$WF_E2E"
check_e2e_filter "$WF_DDEV_E2E"

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

# Summary gate LAST (fail-but-green defect fixed with the e2e path-filter
# wave, the L4 class 0.0.44c C1): this block used to sit two sections
# early — everything checked after it (V13) could print FAIL and still
# exit 0, and any earlier failure skipped those checks entirely.
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All workflow consistency tests passed.$NC"
exit 0
