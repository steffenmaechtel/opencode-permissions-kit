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
#   5. install-shfmt (B1/B2 + review b D1/D2/D5/D7): fails loud on a
#      modeled broken transfer (partial bytes written, then rc 22),
#      downloads atomically (an existing install survives), lands in
#      SHFMT_BIN_DIR positively (a succeeding stub install reaches the
#      override dir, version-probed, stale temp swept), and the
#      scratch dir joins the trap.
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

# Derived at run time (review a B3/C8 + b E1, #301): flags and scope
# come from the Makefile, the single source the gate itself uses. An
# extraction failure reddens below; the documented fallback keeps the
# remaining pins runnable (the drift itself is the recorded failure,
# never a silent pass).
SHFMT_FLAGS="$(sed -n 's/^SHFMT_FLAGS = //p' Makefile | head -1)"
if [ -n "$SHFMT_FLAGS" ]; then
    pass "gate flags derived from the Makefile (SHFMT_FLAGS)"
else
    fail "SHFMT_FLAGS literal not extractable from Makefile"
    SHFMT_FLAGS="-ln dash -i 4 -ci"
fi
_gs_rc=0
GATE_SCOPE="$(make -s fmt-scope)" || _gs_rc=$?
if [ "$_gs_rc" -eq 0 ] && [ -n "$GATE_SCOPE" ]; then
    pass "gate scope derived from the Makefile (make fmt-scope)"
else
    fail "make fmt-scope failed (rc=$_gs_rc) or returned an empty scope"
fi
# git-less halving (review b D9): a checkout without .git makes
# git ls-files return empty inside the Makefile -- the scope must
# still carry its tests half.
if printf '%s\n' "$GATE_SCOPE" | grep -q 'tests/'; then
    pass "gate scope carries the tests half (not git-less-halved)"
else
    fail "gate scope lost its tests half (git-less checkout shape?)"
fi

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
if [ ! -d "$_scratch" ]; then
    echo "  error  scratch setup failed (mktemp) -- aborting (D4 guard)"
    exit 1
fi
trap 'rm -rf "${_scratch:-}" "${_isf:-}"' EXIT INT TERM

# The probe violates every gate dimension (review a C8, #301 — carry
# the axes a flags/editorconfig drift would change): tab indent,
# unindented case arms, compact case-pattern pipes, semicolon-joined
# statements, and a spaced redirect (`> f` — sensitive to
# space_redirects).
printf '#!/bin/sh\ncase "$1" in\na|b) echo one; echo two ;;\nesac\n\tif [ -n "$1" ]; then X=1; Y=2; fi\necho hi > probe.out\n' >"$_scratch/probe.sh"

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

# --- 5. install-shfmt fails loud, atomically, and into the override dir
# (B1/B2 + review b D1/D2/D5/D7, #301) -------------------------------------------
# The failure stub MODELS the broken transfer (review b D1: writing
# garbage to the -o target before failing -- a non-atomic recipe that
# writes the destination directly must break the survival rider), the
# success stub proves the SHFMT_BIN_DIR destination redirect positively
# (review b D2: failure-path assertions alone cannot), a stale
# .shfmt.tmp.* orphan is swept by a successful run (review b D7), and
# the scratch dir joins the trap (review b D5). No network anywhere.
_isf="$(mktemp -d)"
if [ -d "$_isf" ]; then
    mkdir -p "$_isf/bin"
    # failing curl: `curl -fsSL -o <path> <url>` -> $3 is the -o target
    printf '#!/bin/sh\nprintf garbage >"$3"\nexit 22\n' >"$_isf/curl"
    chmod +x "$_isf/curl"
    # a pre-existing "install" for the B2 rider -- it must survive untouched
    printf '#!/bin/sh\necho v3.14.1\n' >"$_isf/bin/shfmt"
    chmod +x "$_isf/bin/shfmt"
    PATH="$_isf:$PATH" SHFMT_BIN_DIR="$_isf/bin" make install-shfmt >/dev/null 2>&1
    _isf_rc=$?
    if [ "$_isf_rc" -ne 0 ]; then
        pass "install-shfmt exits non-zero when the download fails (fail-loud)"
    else
        fail "install-shfmt swallowed the download failure (rc 0)"
    fi
    _isf_tmp="$(find "$_isf/bin" -name '.shfmt.tmp.*' 2>/dev/null || true)"
    if [ -z "$_isf_tmp" ]; then
        pass "failed install leaves no temp garbage behind"
    else
        fail "failed install left temp file(s): $_isf_tmp"
    fi
    if [ "$("$_isf/bin/shfmt" 2>/dev/null)" = "v3.14.1" ]; then
        pass "existing install survives a failed re-download (atomic, B2)"
    else
        fail "failed re-download damaged the existing shfmt (non-atomic recipe?)"
    fi
    # positive arm (review b D2): a succeeding stub (its own PATH dir --
    # the recipe resolves plain `curl`) downloads a working "shfmt"; the
    # recipe must run it through the --version probe and install it INTO
    # the override dir; a stale .shfmt.tmp.* orphan there must be swept
    # (review b D7).
    mkdir -p "$_isf/okstub" "$_isf/okbin"
    cat >"$_isf/okstub/curl" <<'OKSTUB'
#!/bin/sh
printf '#!/bin/sh\necho v9.9.9-stub\n' >"$3"
exit 0
OKSTUB
    chmod +x "$_isf/okstub/curl"
    printf 'orphan\n' >"$_isf/okbin/.shfmt.tmp.99999"
    PATH="$_isf/okstub:$PATH" SHFMT_BIN_DIR="$_isf/okbin" make install-shfmt >/dev/null 2>&1
    _ok_rc=$?
    if [ "$_ok_rc" -eq 0 ] &&
        [ "$("$_isf/okbin/shfmt" 2>/dev/null)" = "v9.9.9-stub" ] &&
        [ ! -e "$_isf/okbin/.shfmt.tmp.99999" ]; then
        pass "successful install lands in SHFMT_BIN_DIR, version-probed, orphan swept"
    else
        fail "destination redirect/probe/sweep broken (rc=$_ok_rc bin=$("$_isf/okbin/shfmt" 2>/dev/null))"
    fi
else
    fail "scratch setup failed (mktemp) -- install-shfmt pins not run (D4 guard)"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  $failures test(s) failed."
    exit 1
fi
echo "  All format-gate pins passed."
exit 0
