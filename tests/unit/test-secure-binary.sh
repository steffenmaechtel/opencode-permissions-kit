#!/bin/sh
# Unit tests for sh/secure-binary.sh (0.0.41c wave): the shared binary
# hardening that replaced install.sh's secure_binary, update.sh's silent
# re-assert pair and the pair inside install_binary.
#   - happy path: mode 750 applied, rc=0
#   - chown is best-effort: a failing chown (non-root, foreign group)
#     does NOT block the chmod
#   - failing chmod fails LOUD: rc=1 + stderr message + audit-log line
#     when the caller has a log() (the 0.0.39e C4 contract — a silent
#     best-effort chmod reported the binary as secured while it was not)
# Runs as the CURRENT user (SB_SUDO="") — no root.
# Run: sh tests/unit/test-secure-binary.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/secure-binary.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    _d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/opencode"
echo '#!/bin/sh' > "$BIN"
chmod 755 "$BIN"

# --- 1. happy path ----------------------------------------------------------

_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    secure_binary "$BIN" somegroup; echo "rc=$?"
)
case "$_sd_out" in *rc=0*) pass "happy: rc=0" ;; *) fail "happy: rc (got [$_sd_out])" ;; esac
check "happy: mode 750 applied" sh -c "[ \"\$(stat -c %a \"$BIN\")\" = 750 ]"

# --- 2. failing chown is best-effort ---------------------------------------

# chown root:<group> as the current (non-root) user fails — the chmod
# must still run and succeed.
chmod 755 "$BIN"
_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    secure_binary "$BIN" somegroup; echo "rc=$?"
)
case "$_sd_out" in *rc=0*) pass "chown best-effort: rc=0 despite failing chown" ;; *) fail "chown best-effort: rc (got [$_sd_out])" ;; esac
check "chown best-effort: chmod still applied" sh -c "[ \"\$(stat -c %a \"$BIN\")\" = 750 ]"

# --- 3. failing chmod fails loud + logs ------------------------------------

LOGS="$WORK/logs"
mkdir -p "$LOGS"
_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    log() { echo "log: $*" >> "$LOGS/audit"; }
    # shellcheck disable=SC2030
    . "$LIB"
    secure_binary "$WORK/does-not-exist" somegroup 2>&1; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "chmod fail: rc=1" ;; *) fail "chmod fail: rc (got [$_sd_out])" ;; esac
case "$_sd_out" in *"cannot chmod 750"*) pass "chmod fail: loud stderr message" ;; *) fail "chmod fail: message" ;; esac
check "chmod fail: audit log written" grep -q "secure_binary FAILED: chmod 750 on $WORK/does-not-exist" "$LOGS/audit"

# --- 4. no log() in scope stays silent-safe ---------------------------------

_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    secure_binary "$WORK/does-not-exist" somegroup 2>&1; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "no log(): still rc=1, no crash" ;; *) fail "no log(): rc (got [$_sd_out])" ;; esac

# --- 5. copy_binary_atomic: a cp killed mid-write leaves the target intact ----
# Issue #163's recorded reachability: update.sh replaced the managed
# binary with a plain in-place cp — a copy killed mid-write left a
# truncated binary with intact mode bits, dead at the first agent
# session. The atomic deploy (sibling temp + mv) must keep the OLD
# bytes whenever the copy leg dies, and must clean up its temp.

CBA_SRC="$WORK/cba-candidate"
CBA_DST="$WORK/cba-installed"
printf 'NEW-CANDIDATE-BYTES' > "$CBA_SRC"

# 5a. happy path: temp+mv lands the new bytes, no temp litter
printf 'OLD-BINARY-BYTES' > "$CBA_DST"
_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    copy_binary_atomic "$CBA_SRC" "$CBA_DST" 2>&1; echo "rc=$?"
)
case "$_sd_out" in *rc=0*) pass "atomic: happy path rc=0" ;; *) fail "atomic: happy path rc (got [$_sd_out])" ;; esac
check "atomic: new bytes in place after the mv" cmp -s "$CBA_DST" "$CBA_SRC"
check "atomic: no temp litter next to the target" \
    sh -c '[ -z "$(find "$1" -maxdepth 1 -name "cba-installed.tmp.*" -print)" ]' _ "$WORK"

# 5b. killed cp: the copy leg writes partial bytes and dies — the old
# binary must survive byte-identical (the mv never ran) and the temp
# must be gone. Simulates SIGKILL-mid-copy through a PATH cp stub.
mkdir -p "$WORK/killing-bin"
cat > "$WORK/killing-bin/cp" <<'KILLCP'
#!/bin/sh
# a cp that writes a prefix of the source, then dies like a killed copy
[ "$#" -ge 2 ] || exit 1
_src=$1; _dst=$2
head -c 4 "$_src" > "$_dst" || exit 1
exit 1
KILLCP
chmod +x "$WORK/killing-bin/cp"
printf 'OLD-BINARY-BYTES' > "$CBA_DST"
_sd_out=$(
    SB_SUDO=""
    export SB_SUDO
    PATH="$WORK/killing-bin:$PATH"
    export SB_SUDO PATH
    # shellcheck disable=SC2030
    . "$LIB"
    copy_binary_atomic "$CBA_SRC" "$CBA_DST" 2>&1; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "atomic: killed cp fails the deploy rc=1" ;; *) fail "atomic: killed cp rc (got [$_sd_out])" ;; esac
check "atomic: killed cp leaves the OLD binary byte-identical (issue #163)" \
    sh -c '[ "$(cat "$1")" = "OLD-BINARY-BYTES" ]' _ "$CBA_DST"
check "atomic: killed cp leaves no temp behind" \
    sh -c '[ -z "$(find "$1" -maxdepth 1 -name "cba-installed.tmp.*" -print)" ]' _ "$WORK"

# --- summary ----------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
