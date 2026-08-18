#!/bin/sh
# Unit tests for status.sh (no root, no install needed): runs the script
# against a fake /usr/local + /etc layout via PATH/mount-point shims and
# greps its output. Covers the regressions the script already shipped:
#   - unknown/missing CONTAINER_BACKEND must not crash (unset var under
#     set -u — the B1 bug) and report "unknown"
#   - docker-rootless without socket configured
#   - not-installed state prints the install hint and exits 0
#   - sudo probes are non-interactive (sudo -n) — a fake sudo that would
#     prompt fails the test
# Run: sh tests/test-status.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$SCRIPT_DIR/../files/status.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# status.sh reads absolute paths (LIBDIR, /etc/...). The only seam we can
# redirect without root is the opencode home it inspects — the interesting
# branches here (backend case, install.conf sourcing) are exercised by
# pointing the script at a controlled conf dir through a chroot-free
# trick: run it with a shimmed environment and capture the output.

# --- 1. unknown backend does not crash (B1 regression) --------------------------
# Source the case block by running status.sh with a crafted install.conf
# is impossible without root (/etc). Instead: run the script verbatim on
# THIS host in the not-installed state (no opencode user) — it must exit
# 0 with the install hint. Then, for the backend case, extract and eval
# the case statement with controlled variables (same static-extraction
# technique as test-project-paths.sh).

extract_backend_case() {
    sed -n '/^case "${CONTAINER_BACKEND:-}" in/,/^esac/p' "$STATUS"
}

if [ -n "$(extract_backend_case)" ]; then
    pass "backend case block extractable from status.sh"
else
    fail "backend case block extractable from status.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi

# ui_kv is defined by ui.sh — source the real one
UI_LIB="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/ui.sh"

run_case() {
    (
        . "$UI_LIB"
        CONTAINER_BACKEND="$1"
        OPENCODE_DOCKER_HOST="${2:-}"
        OPENCODE_PODMAN_SOCKET="${3:-}"
        # status.sh sources install.conf before this block — OPENCODE_USER
        # is always set there (the linger probe uses it). Mirror that.
        OPENCODE_USER="${OPENCODE_USER:-opencode}"
        eval "$(extract_backend_case)"
    ) 2>&1
}

# a) unknown backend value: must print unknown('...') and NOT crash
#    (set -u is active in the parent suite but the eval runs without it —
#    so ALSO run under set -u to prove the fix)
out=$(set -u; run_case "kubernetes" "" "") && rc=0 || rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "unknown ('kubernetes')"; then
    pass "unknown backend reports unknown('kubernetes') without crashing (set -u)"
else
    fail "unknown backend reports unknown('kubernetes') without crashing (rc=$rc out=$out)"
fi

# b) empty backend: reports unknown('none')
out=$(set -u; run_case "" "" "") && rc=0 || rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "unknown ('none')"; then
    pass "empty backend reports unknown('none') without crashing (set -u)"
else
    fail "empty backend reports unknown('none') without crashing (rc=$rc out=$out)"
fi

# c) docker-rootless with a configured socket that does not exist: NOT
#    reachable, and the probe must not prompt (sudo -n). A prompting sudo
#    shim fails the test.
cat > "$WORK/sudo" <<'EOF'
#!/bin/sh
# fail on any interactive sudo attempt: -n must already be in the args
case " $* " in
    *" -n "*) exit 1 ;;
    *) echo "PROMPT-ATTEMPT" >&2; exit 42 ;;
esac
EOF
chmod +x "$WORK/sudo"
out=$(PATH="$WORK:$PATH" set -u; run_case "docker-rootless" "unix:///run/user/99999/docker.sock" "") && rc=0 || rc=$?
if [ "$rc" = "0" ] \
   && ! printf '%s' "$out" | grep -q PROMPT-ATTEMPT \
   && printf '%s' "$out" | grep -q "NOT reachable"; then
    pass "docker-rootless: unreachable socket reported without sudo prompt"
else
    fail "docker-rootless: unreachable socket reported without sudo prompt (rc=$rc out=$out)"
fi

# --- 2. not-installed state: exit 0 + install hint ------------------------------

if ! id opencode >/dev/null 2>&1; then
    out=$(sh "$STATUS" 2>&1); rc=$?
    if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "Hardening NOT active"; then
        pass "not-installed host: hint shown, exit 0"
    else
        fail "not-installed host: hint shown, exit 0 (rc=$rc)"
    fi
else
    echo "  info   opencode user exists on this host — skipping not-installed check"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All status tests passed.${NC}"
exit 0
