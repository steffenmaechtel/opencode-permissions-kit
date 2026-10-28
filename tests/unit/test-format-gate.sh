#!/bin/sh
# test-format-gate.sh -- pins for the shfmt format gate (issue #255
# stage 0a). The gate itself lives in `make lint`; this suite pins its
# load-bearing properties so regressions fail loud:
#
#   1. Version pin consistency: the Makefile SHFMT_VERSION and the
#      check-host.sh SHFMT_PINNED literal must be the same version --
#      two literals drift silently otherwise. The HOST's shfmt must
#      match too (the gate refuses other versions; this suite runs
#      under the same pin).
#   2. EditorConfig equivalence: .editorconfig and the gate flags
#      (-ln dash -i 4 -ci) must produce byte-identical formatting.
#      Pinned by formatting the same misformatted probe twice (once
#      bare/editorconfig-driven, once flags-driven) and comparing.
#      This is the class that bit during adoption: a brace glob
#      ([*.{sh}]) silently matched nothing and bare shfmt fell back
#      to tabs.
#   3. Gate discrimination: a deliberately misformatted probe IS
#      listed by `shfmt -l` under both configuration paths -- a gate
#      that cannot go red protects nothing.
#   4. The committed tree is clean under both paths (bare -l and
#      flags -l over the gate scope list are empty) -- the same
#      assertion `make lint` makes, executed the way the suite
#      observes it.
#
# Run: sh tests/unit/test-format-gate.sh

set -u
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

pass() { echo "  PASS  $1"; }
fail() {
    echo "  FAIL  $1"
    failures=$((failures + 1))
}
failures=0

if ! command -v shfmt >/dev/null 2>&1; then
    echo "  error  shfmt is not installed -- run tests/check-host.sh"
    exit 1
fi

SHFMT_FLAGS="-ln dash -i 4 -ci"

# Same scope the Makefile gate uses: shipped shell (shebang/directive
# first line under files/ + scripts/) plus every TRACKED .sh under
# tests/ -- tracked-only, because warm checkouts carry untracked
# foreign shell (e2e camino share-providers, cache dumps).
GATE_SCOPE="$(
    {
        find files scripts -type f -exec \
            awk 'FNR == 1 && (/^[#]!\/bin\/sh/ || /^[#] shellcheck shell=/) {print FILENAME}' {} +
        git ls-files -- 'tests/*.sh'
    } | sort -u
)"

# --- 1. version pin consistency ------------------------------------------------
_ver_make="$(sed -n 's/^SHFMT_VERSION = //p' Makefile | head -1)"
_ver_hostpin="$(sed -n 's/^SHFMT_PINNED="//p' tests/check-host.sh | head -1 | sed 's/"$//')"
_ver_running="$(shfmt --version 2>/dev/null)"

if [ -n "$_ver_make" ] && [ -n "$_ver_hostpin" ] &&
    [ "v$_ver_make" = "$_ver_hostpin" ]; then
    pass "Makefile SHFMT_VERSION and check-host.sh pin agree (v$_ver_make)"
else
    fail "version pin drift: Makefile='$_ver_make' check-host='$_ver_hostpin'"
fi
if [ "$_ver_running" = "v$_ver_make" ]; then
    pass "installed shfmt is the pinned version ($_ver_running)"
else
    fail "installed shfmt is '$_ver_running', pin is 'v$_ver_make' (make install-shfmt)"
fi

# --- 2+3. editorconfig equivalence + discrimination (scratch probe) -------------
_scratch="$(mktemp -d)"
trap 'rm -rf "$_scratch"' EXIT INT TERM

# The probe violates every gate dimension: tab indent, unindented
# case arms, compact case-pattern pipes, semicolon-joined statements.
printf '#!/bin/sh\ncase "$1" in\na|b) echo one; echo two ;;\nesac\nif [ -n "$1" ]; then X=1; Y=2; fi\n' >"$_scratch/probe.sh"

# the repo .editorconfig must reach the probe: a copy sits next to it
# (root=true keeps parent lookups out of the scratch dir)
cp .editorconfig "$_scratch/.editorconfig"

_bad_flags="$(shfmt -l $SHFMT_FLAGS "$_scratch/probe.sh" 2>&1)"
_bad_bare="$(shfmt -l "$_scratch/probe.sh" 2>&1)"
if [ -n "$_bad_flags" ] && [ -n "$_bad_bare" ]; then
    pass "gate discriminates: misformatted probe listed (flags AND editorconfig)"
else
    fail "gate blind: probe not listed (flags='$_bad_flags' bare='$_bad_bare')"
fi

mkdir "$_scratch/a" "$_scratch/b"
cp "$_scratch/probe.sh" "$_scratch/a/probe.sh"
cp "$_scratch/probe.sh" "$_scratch/b/probe.sh"
cp .editorconfig "$_scratch/a/.editorconfig"
cp .editorconfig "$_scratch/b/.editorconfig"
shfmt -w $SHFMT_FLAGS "$_scratch/a/probe.sh"
shfmt -w "$_scratch/b/probe.sh"
if cmp -s "$_scratch/a/probe.sh" "$_scratch/b/probe.sh"; then
    pass "editorconfig and gate flags format byte-identically"
else
    fail "editorconfig/flags formatting differs:"
    diff -u "$_scratch/a/probe.sh" "$_scratch/b/probe.sh" | sed 's/^/        /'
fi

# --- 4. the committed tree is clean under both paths ------------------------------
# Parse errors surface on STDERR with an empty stdout list (rc 1 either
# way -- the stream is the only discriminator); the gate keys on that,
# so this suite does too: stderr non-empty in scope = fail, not pass.
# shellcheck disable=SC2086 -- GATE_SCOPE is a newline list of
# space-free repo paths, word-split on purpose.
_err_flags="$(shfmt -l $SHFMT_FLAGS $GATE_SCOPE 2>&1 >/dev/null)"
if [ -z "$_err_flags" ]; then
    pass "gate scope parses clean (no shfmt stderr)"
else
    fail "shfmt parse error(s) in scope:"
    printf '%s\n' "$_err_flags" | sed 's/^/        /'
fi
# The parse-error arm itself discriminates (L1: a broken file must not
# pass the gate silently -- probed on a scratch file, never the tree).
printf '#!/bin/sh\necho "unterminated\n' >"$_scratch/broken.sh"
_pe_err="$(shfmt -l $SHFMT_FLAGS "$_scratch/broken.sh" 2>&1 >/dev/null)"
_pe_out="$(shfmt -l $SHFMT_FLAGS "$_scratch/broken.sh" 2>/dev/null)"
if [ -n "$_pe_err" ] && [ -z "$_pe_out" ]; then
    pass "parse errors land on stderr with an empty list (gate goes red)"
else
    fail "parse-error observability drifted (stderr='$_pe_err' stdout='$_pe_out')"
fi
# shellcheck disable=SC2086
_err_bare="$(shfmt -l $GATE_SCOPE 2>&1 >/dev/null)"
if [ -z "$_err_bare" ]; then
    pass "gate scope parses clean under bare shfmt too"
else
    fail "bare shfmt parse error(s) in scope:"
    printf '%s\n' "$_err_bare" | sed 's/^/        /'
fi
# shellcheck disable=SC2086
_dirty_flags="$(shfmt -l $SHFMT_FLAGS $GATE_SCOPE 2>/dev/null)"
if [ -z "$_dirty_flags" ]; then
    pass "gate scope is canonically formatted (flags run clean)"
else
    fail "files differ from canonical format:"
    printf '%s\n' "$_dirty_flags" | sed 's/^/        /'
fi
# shellcheck disable=SC2086
_dirty_bare="$(shfmt -l $GATE_SCOPE 2>/dev/null)"
if [ -z "$_dirty_bare" ]; then
    pass "gate scope is clean under bare shfmt too (editorconfig agrees)"
else
    fail "bare shfmt lists files (.editorconfig vs flags drift):"
    printf '%s\n' "$_dirty_bare" | sed 's/^/        /'
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  $failures test(s) failed."
    exit 1
fi
echo "  All format-gate pins passed."
exit 0
