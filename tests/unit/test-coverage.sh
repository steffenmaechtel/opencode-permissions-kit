#!/bin/sh
# test-coverage.sh -- pins for the kcov coverage runner (issue #255, stage
# 0b). The runner lives in scripts/coverage.sh (invoked via `make
# coverage`, CI job `coverage`); this suite pins its load-bearing
# properties so the report cannot silently degrade to plausible garbage:
#
#   1. Wiring: Makefile target + CI job + artifact upload + this suite's
#      own CI run step exist (a dropped wiring makes the report vanish).
#   2. Image pin: the kcov image is digest-pinned (sha256, 64 hex) --
#      report reproducibility rides on it.
#   3. Method contract: NO --bash-method override in the runner. The
#      default PS4 method traces child `sh` processes; the DEBUG-trap
#      method does not (its helper unsets BASH_ENV -- children go dark;
#      measured as the 11-file/41.8% illusion vs the real 27-file/52.7%).
#   4. The PS4 collision shields in test-install-args.sh: every
#      `bash -c 'set -eu'` block carries `PS4="+ "` as its first line --
#      without it, coverage runs abort those blocks on PS4's
#      ${BASH_SOURCE} expansion under set -u (issue #255 stage 0b).
#   5. Exclusion discipline: the runner's exclusion list is empty —
#      every entry needs an open issue naming the delta (#342, the last
#      entry, closed).
#   6. Runner mechanics: relative suite paths (absolute argv = empty
#      report), the quoted-heredoc sh->bash shim, the include surface
#      (files/ + scripts/), and the :? guards on scratch cleanup.
#
# No docker needed here -- these are structure pins; the runner itself is
# exercised by the CI coverage job (and locally via `make coverage`).
# Run: sh tests/unit/test-coverage.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1
RUNNER="scripts/coverage.sh"
IA="tests/unit/test-install-args.sh"
WF=".github/workflows/test-unit.yml"

pass() { echo "  PASS  $1"; }
fail() {
    echo "  FAIL  $1"
    failures=$((failures + 1))
}
failures=0

_strip() { sed 's/^[[:space:]]*#.*$//' "$1"; }

# --- 1. wiring ----------------------------------------------------------------
if [ -f "$RUNNER" ] && _strip Makefile | grep -qE '^coverage:' &&
    _strip Makefile | grep -qF './scripts/coverage.sh'; then
    pass "runner exists and is wired as \`make coverage\`"
else
    fail "runner or Makefile coverage target missing"
fi
if _strip "$WF" | grep -qE '^  coverage:' &&
    _strip "$WF" | grep -qF 'actions/upload-artifact@'; then
    pass "CI: coverage job present and uploads an artifact"
else
    fail "test-unit.yml lost the coverage job or its artifact upload"
fi
if _strip "$WF" | grep -qF './tests/unit/test-coverage.sh'; then
    pass "CI: this pin suite has its own run step"
else
    fail "test-unit.yml has no run step for test-coverage.sh"
fi

# --- 2. image digest pin --------------------------------------------------------
_img="$(sed -n 's/^KCOV_IMAGE="\(.*\)"$/\1/p' "$RUNNER" | head -1)"
case "$_img" in
    kcov/kcov:latest@sha256:[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
        _hex="${_img##*sha256:}"
        if [ "${#_hex}" -eq 64 ] &&
            ! printf '%s' "$_hex" | grep -qE '[^0-9a-f]'; then
            pass "kcov image digest-pinned (64-hex sha256)"
        else
            fail "KCOV_IMAGE digest is not 64 hex chars: $_img"
        fi
        ;;
    *) fail "KCOV_IMAGE not digest-pinned (got: ${_img:-none})" ;;
esac

# --- 3. method contract (absence pin: a commented override still counts) -------
if ! grep -q -- '--bash-method' "$RUNNER"; then
    pass "runner uses kcov's default PS4 method (children traced)"
else
    fail "runner overrides --bash-method -- DEBUG leaves child shells untraced (see the record)"
fi

# --- 4. PS4 shields in test-install-args.sh -------------------------------------
_shields=$(_strip "$IA" | grep -cF 'PS4="+ "' || true)
_blocks=$(_strip "$IA" | grep -cF "bash -c '" || true)
if [ "$_blocks" -gt 0 ] && [ "$_shields" -eq "$_blocks" ]; then
    pass "every bash -c block in test-install-args.sh carries the PS4 shield ($_shields/$_blocks)"
else
    fail "PS4 shield coverage drifted (shields=$_shields bash-c blocks=$_blocks)"
fi

# --- 5. exclusion discipline ----------------------------------------------------
# The list must be EMPTY: every entry needs an open issue naming the
# delta and tracking the fix — the last entry (#342, the dash-only stamp
# pin) was lifted when it closed. The assignment count proves EXCLUSIVITY
# (a second EXCLUDED= line would drift the list while the literal pin
# stayed green — #343 a C3); the literal proves emptiness.
_excl_n=$(_strip "$RUNNER" | grep -c 'EXCLUDED=' || true)
if [ "$_excl_n" = 1 ] &&
    _strip "$RUNNER" | grep -qF 'EXCLUDED=""'; then
    pass "exclusion list is empty (no open-issue deltas left)"
else
    fail "exclusion list drifted (assignments=$_excl_n, expected exactly one empty list)"
fi

# --- 6. runner mechanics ---------------------------------------------------------
if _strip "$RUNNER" | grep -qF 'for suite in tests/unit/test-*.sh; do'; then
    pass "suites are passed to kcov as RELATIVE paths"
else
    fail "relative-path contract gone (absolute argv yields an empty report)"
fi
if _strip "$RUNNER" | grep -qF "cat >\"\$OUT/shim/sh\" <<'EOF'" &&
    _strip "$RUNNER" | grep -qF 'exec /usr/bin/bash "$@"'; then
    pass "sh->bash shim written via quoted heredoc (survives shell layers)"
else
    fail "shim construction drifted off the quoted-heredoc form"
fi
if _strip "$RUNNER" | grep -qF -- '--include-pattern="$REPO/files/,$REPO/scripts/"'; then
    pass "report surface = files/ + scripts/ (the review surface)"
else
    fail "include-pattern no longer covers files/ + scripts/"
fi
if _strip "$RUNNER" | grep -qF 'rm -rf "${OUT:?}'; then
    pass "scratch cleanup carries :? empty-variable guards"
else
    fail "rm on \$OUT lost its :? guard"
fi
# Stamp-guard + absolute-OUT contract (#343 a A1/A2): the cleanup must be
# refused under a foreign non-empty OUT, and OUT must never resolve inside
# the repo.
if _strip "$RUNNER" | grep -qF 'refusing to clean' &&
    _strip "$RUNNER" | grep -qF '.opk-kcov-out' &&
    _strip "$RUNNER" | grep -qF 'must live outside the repo'; then
    pass "scratch cleanup is stamp-guarded; OUT refuses the repo tree"
else
    fail "OUT/cleanup guards drifted (absolute OUT, stamp, repo refusal)"
fi
if _strip "$RUNNER" | grep -qF '[ "$count" -eq 1 ]'; then
    pass "single-suite runs skip the merge (single-source merge emits nothing)"
else
    fail "single-source merge guard gone (filtered runs would report empty)"
fi

# Summary gate LAST (agent/conventions.md L4)
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  $failures test(s) failed."
    exit 1
fi
echo "  All coverage-runner pins passed."
exit 0
