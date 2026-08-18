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
        # Everything inside: PATH (with the shims below), set -u (the B1
        # regression needs it), and the install.conf variables status.sh
        # would have sourced by now.
        PATH="$WORK:$PATH"
        export PATH
        # Mirror status.sh's own shell flags: set -u yes (that is the B1
        # regression), but NOT set -e — the subshell inherits errexit from
        # this test script, and the extracted block legitimately ends in
        # `[ -n "$linger" ] && ui_kv ...` whose false status would abort
        # the subshell on linger-less hosts (CI runners) — the exact
        # false failure this guard prevents.
        set -u
        set +e
        . "$UI_LIB"
        CONTAINER_BACKEND="$1"
        OPENCODE_DOCKER_HOST="${2:-}"
        OPENCODE_PODMAN_SOCKET="${3:-}"
        # status.sh sources install.conf before this block — OPENCODE_USER
        # is always set there (the linger probe uses it). Mirror that.
        OPENCODE_USER="${OPENCODE_USER:-opencode}"
        eval "$(extract_backend_case)"
        # Do NOT rely on the case block's trailing status: it legitimately
        # ends in `[ -n "$linger" ] && ui_kv ...`, whose status depends on
        # the host's loginctl (dev host with linger: 0 / CI runner: 1) — and
        # the caller runs under set -e. exit 0 only normalizes that benign
        # trailing status; a set -u crash aborts the subshell EARLY, long
        # before this line, and stays non-zero.
        exit 0
    ) 2>&1
}

# a) unknown backend value: must print unknown('...') and NOT crash
# || true on every capture: when the extracted block aborts (the B1 bug —
# unset var under set -u), the subshell exits non-zero and this script's
# own set -e would kill the TEST instead of reporting FAIL. The output is
# what the assertions judge; the status is discarded by design.
out=$(run_case "kubernetes" "" "" || true)
if printf '%s' "$out" | grep -q "unknown ('kubernetes')" \
   && ! printf '%s' "$out" | grep -q "parameter not set"; then
    pass "unknown backend reports unknown('kubernetes') without crashing (set -u)"
else
    fail "unknown backend reports unknown('kubernetes') without crashing (out=$out)"
fi

# b) empty backend: reports unknown('none')
out=$(run_case "" "" "" || true)
if printf '%s' "$out" | grep -q "unknown ('none')" \
   && ! printf '%s' "$out" | grep -q "parameter not set"; then
    pass "empty backend reports unknown('none') without crashing (set -u)"
else
    fail "empty backend reports unknown('none') without crashing (out=$out)"
fi

# c) docker-rootless with a configured socket that does not exist: NOT
#    reachable, and the probe must not prompt (sudo -n). A prompting sudo
#    shim fails the test. NOTE: the shim must actually be IN the PATH of
#    run_case's subshell (see run_case) — a `PATH=... cmd; f` prefix would
#    apply the assignment only to `cmd`, never to f.
cat > "$WORK/sudo" <<'EOF'
#!/bin/sh
# fail on any interactive sudo attempt: -n must already be in the args
case " $* " in
    *" -n "*) exit 1 ;;
    *) echo "PROMPT-ATTEMPT" >&2; exit 42 ;;
esac
EOF
chmod +x "$WORK/sudo"
out=$(run_case "docker-rootless" "unix:///run/user/99999/docker.sock" "" || true)
if printf '%s' "$out" | grep -q "NOT reachable" \
   && ! printf '%s' "$out" | grep -qE 'PROMPT-ATTEMPT|parameter not set'; then
    pass "docker-rootless: unreachable socket reported without sudo prompt"
else
    fail "docker-rootless: unreachable socket reported without sudo prompt (out=$out)"
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
