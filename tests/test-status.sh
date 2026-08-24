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

# --- 0. dev-owned mode line (docs/design/ddev-dev-owned-projects.md) -------------
if grep -q 'ui_kv "ddev settings"' "$STATUS" && \
   grep -q 'dev-owned — kit writes disable_settings_management' "$STATUS" && \
   grep -qF 'DDEV_DEV_OWNED=' "$STATUS"; then
    pass "status.sh reports the ddev settings mode (stamp-driven)"
else
    fail "status.sh reports the ddev settings mode (stamp-driven)"
fi

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

# d) docker-rootless with the socket inside a NON-TRAVERSABLE runtime dir
#    (production finding: /run/user/<uid> is 700 opencode:opencode — a
#    non-root caller cannot stat inside, sudo -n has no cached credentials;
#    the old output said red "NOT reachable" and users thought the daemon
#    was down). Must report "unknown — needs root", never red.
mkdir -p "$WORK/locked-runtime"
chmod 700 "$WORK/locked-runtime"   # 700 of a nonexistent other user is untestable; 000 works for everyone
chmod 000 "$WORK/locked-runtime"
out=$(run_case "docker-rootless" "unix://$WORK/locked-runtime/docker.sock" "" || true)
if printf '%s' "$out" | grep -q "unknown — needs root to check" \
   && ! printf '%s' "$out" | grep -q "NOT reachable" \
   && ! printf '%s' "$out" | grep -qE 'PROMPT-ATTEMPT|parameter not set'; then
    pass "docker-rootless: socket in inaccessible runtime dir reports unknown (needs root)"
else
    fail "docker-rootless: socket in inaccessible runtime dir reports unknown (needs root) (out=$out)"
fi
chmod 755 "$WORK/locked-runtime" 2>/dev/null || true

# --- 1b. root-equivalent access audit (issue #37) --------------------------------
# The audit ships two pure helpers (stat math only); they are extracted and
# unit-tested directly, plus static assertions on the section wiring.
if grep -q 'ui_section "Root-equivalent access' "$STATUS" \
   && grep -q 'ROOT_EQUIV_SOCKS' "$STATUS" \
   && grep -q '/mnt/wsl' "$STATUS"; then
    pass "status.sh carries the root-equivalent access section (issue #37)"
else
    fail "status.sh carries the root-equivalent access section (issue #37)"
fi

(
    . "$UI_LIB"
    eval "$(sed -n '/^status_groups_hits()/,/^}/p' "$STATUS")"
    eval "$(sed -n '/^status_sock_agent_reachable()/,/^}/p' "$STATUS")"

    # groups: word match, no substring false positives (adm vs admin)
    _out=$(status_groups_hits "opencode www-data" "docker sudo admin adm wheel")
    [ "$_out" = "" ] && echo GROUPS-CLEAN-OK
    _out=$(status_groups_hits "opencode docker adm" "docker sudo admin adm wheel" | tr '\n' ' ')
    [ "$_out" = "docker adm " ] && echo GROUPS-HIT-OK

    # socket reachability: real unix socket, perm math without root
    _sock="$WORK/fake-daemon.sock"
    python3 - "$_sock" <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
PYEOF
    _grp=$(id -gn)
    chmod 666 "$_sock"
    status_sock_agent_reachable "$_sock" ""          && echo SOCK-WORLDW-OK
    chmod 660 "$_sock"; chgrp "$_grp" "$_sock"
    status_sock_agent_reachable "$_sock" "$_grp"     && echo SOCK-GROUPW-OK
    status_sock_agent_reachable "$_sock" "othergrp"  || echo SOCK-GROUPW-DENY-OK
    chmod 660 "$_sock"; chgrp "$_grp" "$_sock"
    status_sock_agent_reachable "$_sock" ""          || echo SOCK-NOOTHER-OK
    status_sock_agent_reachable "$WORK/absent.sock" "" || echo SOCK-ABSENT-OK
) > "$WORK/audit.out" 2>&1
_audit_ok=0
for _want in GROUPS-CLEAN-OK GROUPS-HIT-OK SOCK-WORLDW-OK SOCK-GROUPW-OK SOCK-GROUPW-DENY-OK SOCK-NOOTHER-OK SOCK-ABSENT-OK; do
    if grep -q "$_want" "$WORK/audit.out"; then
        _audit_ok=$((_audit_ok + 1))
    else
        fail "audit helper: missing $_want ($(cat "$WORK/audit.out"))"
    fi
done
[ "$_audit_ok" -eq 7 ] && pass "root-equivalent audit helpers (groups + socket math)"

# --- 1c. audit section body executes without crashing (review 0.0.22) -----------
# The helper units above cover the math; this runs the WHOLE section body
# (extraction like the backend case) against a fake agent user + a real
# fake socket, under set -u — a crash here would otherwise only surface on
# an installed host (the e2e grep hits an earlier line and passes anyway).
# || true on the captures: the subshell deliberately runs under set -u and
# its exit status must not kill this script (same pattern as run_case).
AUDIT_SECTION="$(sed -n '/^# === Root-equivalent access audit/,/^# === Sensitive-file leak scan/p' "$STATUS" | sed '$d')"
[ -n "$AUDIT_SECTION" ] || { echo "  ${RED}audit section not extractable${NC}"; exit 1; }
_sock2="$WORK/fake-agent-sock"
python3 - "$_sock2" <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
PYEOF
audit_out=$(
    (
        set -u; set +e
        . "$UI_LIB"
        OPENCODE_USER="root"                 # exists everywhere; id -nG works
        ROOT_EQUIV_SOCKS="$_sock2"           # the fake socket, world-writable
        chmod 666 "$_sock2" 2>/dev/null      # bind honors umask: force 666
        eval "$AUDIT_SECTION"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$audit_out" | grep -q "Root-equivalent access" \
   && printf '%s' "$audit_out" | grep -q "AGENT-REACHABLE" \
   && ! printf '%s' "$audit_out" | grep -q "parameter not set"; then
    pass "audit section body runs (fake world-writable socket flagged red)"
else
    fail "audit section body runs (out=$(printf '%s' "$audit_out" | head -3))"
fi
# The same socket at 660 with a group the agent user is NOT in must NOT be
# flagged reachable (perm-math negative inside the section body).
audit_out2=$(
    (
        set -u; set +e
        . "$UI_LIB"
        OPENCODE_USER="root"
        ROOT_EQUIV_SOCKS="$_sock2"
        chmod 660 "$_sock2" 2>/dev/null
        eval "$AUDIT_SECTION"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$audit_out2" | grep -q "not agent-reachable"; then
    pass "audit section body: group-w socket with foreign group stays green"
else
    fail "audit section body: foreign-group socket flagged or crashed (out=$(printf '%s' "$audit_out2" | head -3))"
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
