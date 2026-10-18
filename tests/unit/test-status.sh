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
# Run: sh tests/unit/test-status.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# --- 0. dev-owned mode line (internal/records/ddev-dev-owned-projects.md) -------------
if grep -q 'ui_kv "ddev settings"' "$STATUS" && \
   grep -q 'dev-owned — kit writes disable_settings_management' "$STATUS" && \
   grep -qF 'DDEV_DEV_OWNED=' "$STATUS"; then
    pass "status.sh reports the ddev settings mode (stamp-driven)"
else
    fail "status.sh reports the ddev settings mode (stamp-driven)"
fi

# --- 0b. git row (issue #118): the Core section shows the host git against
# the soft tested floor, from the shared helper (fail-soft: no helper, no row).
if grep -q 'git_status_row' "$STATUS" && \
   grep -q 'sh/git-check.sh' "$STATUS" && \
   grep -q 'command -v git_status_row' "$STATUS"; then
    pass "status.sh reports the host git via the shared git-check helper"
else
    fail "status.sh reports the host git via the shared git-check helper"
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
UI_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"

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

# --- 1d. live ddev version probe (issue #56) -------------------------------------
# DDEV_VERSION in install.conf is an install-time stamp; status.sh must
# report the LIVE binary version instead (the stale stamp showed 1.25.3
# while the terminal's `ddev --version` answered 1.25.4). Extract the
# probe block and run it with a fake ddev shim ahead on PATH — command -v
# resolves the shim first, so the host's own ddev cannot interfere.
DDEV_PROBE="$(sed -n '/^# Live ddev version/,/^# Windows hosts readiness/p' "$STATUS" | sed '$d')"
if [ -n "$DDEV_PROBE" ]; then
    pass "ddev version probe block extractable from status.sh"
else
    fail "ddev version probe block extractable from status.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
printf '#!/bin/sh\necho "ddev version v1.25.4"\n' > "$WORK/ddev"
chmod +x "$WORK/ddev"
probe_out=$(
    (
        PATH="$WORK:$PATH"
        export PATH
        set -u
        set +e
        . "$UI_LIB"
        DDEV_VERSION="1.25.3"
        eval "$DDEV_PROBE"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$probe_out" | grep -q "1.25.4" \
   && ! printf '%s' "$probe_out" | grep -q "1.25.3"; then
    pass "ddev version: live probe wins over the install-time stamp (issue #56)"
else
    fail "ddev version: live probe wins over the stamp (out=$probe_out)"
fi

# the < 1.25 gate must judge the LIVE version too
printf '#!/bin/sh\necho "ddev version v1.24.2"\n' > "$WORK/ddev"
probe_low=$(
    (
        PATH="$WORK:$PATH"
        export PATH
        set -u
        set +e
        . "$UI_LIB"
        DDEV_VERSION="1.24.2"
        eval "$DDEV_PROBE"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$probe_low" | grep -q "rootless needs ddev >= 1.25"; then
    pass "ddev version: live version < 1.25 keeps the red gate"
else
    fail "ddev version: live version < 1.25 keeps the red gate (out=$probe_low)"
fi

# fallback: no binary answers -> the stamp, annotated (static assert: the
# standard locations /usr/local/bin/ddev and /usr/bin/ddev exist on real
# hosts and cannot be shadowed in-process)
if grep -q 'recorded at install time' "$STATUS"; then
    pass "ddev version: stamp fallback annotated when no binary answers"
else
    fail "ddev version: stamp fallback annotated when no binary answers"
fi

# --- 1d-2. helper probe tier (issue #72) -------------------------------------------
# ddev >= 1.25.4 refuses root ("DDEV is not designed to be run with root
# privileges", exit 1 before printing anything): a root-run `sudo opk
# status` got an EMPTY `ddev --version` and fell back to the stale
# install-time stamp. When the direct probe stays silent, the block must
# ask the kit's ddev-as-opencode helper AS THE OPENCODE USER — it runs
# ddev exactly the way the kit does (root needs no password for sudo -u,
# the developer hits the kit's NOPASSWD sudoers rule). Functional with
# stubs: a "present but silent" ddev mirrors the root failure exactly
# (binary found, no version), the fake sudo answers the helper call, and
# LIBDIR points at a stub kit with an executable helper.
mkdir -p "$WORK/fakekit/bin" "$WORK/quiet"
printf '#!/bin/sh\nexit 1\n' > "$WORK/fakekit/bin/ddev-as-opencode"
chmod +x "$WORK/fakekit/bin/ddev-as-opencode"
printf '#!/bin/sh\necho "ddev version v1.26.0"\n' > "$WORK/sudo"
chmod +x "$WORK/sudo"
printf '#!/bin/sh\nexit 1\n' > "$WORK/quiet/ddev"
chmod +x "$WORK/quiet/ddev"
probe_helper=$(
    (
        PATH="$WORK/quiet:$WORK:$PATH"
        export PATH
        set -u
        set +e
        . "$UI_LIB"
        LIBDIR="$WORK/fakekit"
        OPENCODE_USER="opencode"
        DDEV_VERSION="1.25.3"
        eval "$DDEV_PROBE"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$probe_helper" | grep -q "1.26.0" \
   && ! printf '%s' "$probe_helper" | grep -q "1.25.3"; then
    pass "ddev version: helper probe answers when root-run ddev stays silent (issue #72)"
else
    fail "ddev version: helper probe tier (out=$(printf '%s' "$probe_helper" | head -3))"
fi

# the helper tier must never prompt for a password inside a status output
if grep -q 'sudo -n -u' "$STATUS"; then
    pass "ddev version: helper probe uses sudo -n (no password prompt)"
else
    fail "ddev version: helper probe uses sudo -n (no password prompt)"
fi

# --- 1e. channel stamp display (issue #38) ----------------------------------------
# status.sh shows the KIT_CHANNEL stamp from install.conf; unstamped
# (pre-beta) installs must say so instead of crashing under set -u.
channel_out=$(
    (
        set -u; set +e
        . "$UI_LIB"
        KIT_CHANNEL="stable"
        eval "$(sed -n '/^# Channel stamp (issue #38)/,/^fi$/p' "$STATUS")"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$channel_out" | grep -q "stable" \
   && ! printf '%s' "$channel_out" | grep -q "unstamped"; then
    pass "channel: stamped value shown"
else
    fail "channel: stamped value shown (out=$channel_out)"
fi
channel_out=$(
    (
        set -u; set +e
        . "$UI_LIB"
        unset KIT_CHANNEL
        eval "$(sed -n '/^# Channel stamp (issue #38)/,/^fi$/p' "$STATUS")"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$channel_out" | grep -q "unstamped" \
   && ! printf '%s' "$channel_out" | grep -q "parameter not set"; then
    pass "channel: unstamped install reports master (unstamped) without crashing"
else
    fail "channel: unstamped install reports master (unstamped) without crashing (out=$channel_out)"
fi

# --- 1f. management footer uses the opk shorthand (issue #62) ---------------------
# The footer is the hint users copy-paste; it must print the short CLI
# commands, not the library paths behind them.
if grep -qF 'ui_detail "sudo opk config' "$STATUS" && \
   grep -qF 'ui_detail "sudo opk update' "$STATUS" && \
   grep -qF 'ui_detail "opk uninstall' "$STATUS" && \
   ! grep -q 'management/config\.sh.*change settings' "$STATUS" && \
   ! grep -q 'management/update\.sh.*re-deploy' "$STATUS" && \
   ! grep -q 'management/uninstall\.sh.*remove the kit' "$STATUS"; then
    pass "management footer prints opk shorthand, not library paths (issue #62)"
else
    fail "management footer prints opk shorthand, not library paths (issue #62)"
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

# --- 3. traversal warning helpers (ancestor chain of a root) --------------------

# Extract the two helpers verbatim from status.sh and exercise them on a
# fixture chain: W (700) / t (700) / w (755) / proj — walking up from
# proj, t is the first blocker; after a traverse-only ACL on t and W the
# chain is clean.
eval "$(sed -n '/^_st_ancestor_grants_x()/,/^}/p' "$STATUS")"
eval "$(sed -n '/^_st_root_blocker()/,/^}/p' "$STATUS")"
OPENCODE_GROUP="$(id -gn)"
W3=$(mktemp -d)
mkdir -p "$W3/t/w/proj"
chmod 700 "$W3" "$W3/t"
chmod 755 "$W3/t/w"
if [ "$(_st_root_blocker "$W3/t/w/proj")" = "$W3/t" ]; then
    pass "blocker check names the first blocking ancestor"
else
    fail "blocker check names the first blocking ancestor (got '$(_st_root_blocker "$W3/t/w/proj"))')"
fi
setfacl -m "g:$OPENCODE_GROUP:X" "$W3" "$W3/t"
if [ -z "$(_st_root_blocker "$W3/t/w/proj")" ]; then
    pass "blocker check accepts traverse-only ACL entries"
else
    fail "blocker check accepts traverse-only ACL entries (got '$(_st_root_blocker "$W3/t/w/proj"))')"
fi
rm -rf "$W3"

# --- 1c. empty projects.conf header (0.0.43a F8) ---------------------------------
# `grep -c .` on an empty file prints 0 AND exits 1 — the old `|| echo 0`
# appended a second 0 and the captured "0<newline>0" broke the "Projects"
# header across lines. The shipped counting block is extracted and run
# with a stubbed ui_section against an empty and a missing projects.conf.
sed -n '/^_st_pc=/,/^ui_section "Projects/p' "$STATUS" > "$WORK/pc-block.sh"
if [ -s "$WORK/pc-block.sh" ] && grep -q 'ui_section "Projects' "$WORK/pc-block.sh"; then
    pass "the projects-count block is extractable from status.sh"
else
    fail "the projects-count block is extractable from status.sh"
fi
: > "$WORK/empty-projects.conf"
_pc_empty="$(PROJECTS_CONF="$WORK/empty-projects.conf" sh -c '
    ui_section() { printf "%s" "$1"; }
    . "$1"
' sh "$WORK/pc-block.sh" 2>/dev/null || true)"
if [ "$_pc_empty" = "Projects (0)" ]; then
    pass "empty projects.conf renders a one-line 'Projects (0)' header"
else
    fail "empty projects.conf renders a one-line 'Projects (0)' header (got '$_pc_empty')"
fi
_pc_missing="$(PROJECTS_CONF="$WORK/nope-projects.conf" sh -c '
    ui_section() { printf "%s" "$1"; }
    . "$1"
' sh "$WORK/pc-block.sh" 2>/dev/null || true)"
if [ "$_pc_missing" = "Projects (0)" ]; then
    pass "missing projects.conf renders 'Projects (0)' too"
else
    fail "missing projects.conf renders 'Projects (0)' too (got '$_pc_missing')"
fi
printf '/var/tmp/one\n/var/tmp/two\n' > "$WORK/two-projects.conf"
_pc_two="$(PROJECTS_CONF="$WORK/two-projects.conf" sh -c '
    ui_section() { printf "%s" "$1"; }
    . "$1"
' sh "$WORK/pc-block.sh" 2>/dev/null || true)"
if [ "$_pc_two" = "Projects (2)" ]; then
    pass "populated projects.conf counts its roots"
else
    fail "populated projects.conf counts its roots (got '$_pc_two')"
fi

# --- 1d. advisory version probe is bounded (0.0.43b W3) ---------------------------
# The comment claims parity with the wrapper's check — true only with the
# timeout envelope the wrapper got in 0.0.43a F3. A wedged 2.x service can
# make even --version hang (issue #80); opk status, the diagnostic for
# exactly that state, must never hang on it.
if awk '/ADV_VER=\$\(/,/head -1 \|\| true/' "$STATUS" | grep -q 'timeout 10'; then
    pass "advisory probe is timeout-bounded (0.0.43b W3)"
else
    fail "advisory probe is timeout-bounded (0.0.43b W3)"
fi
if grep -qF 'BOUNDED pattern as the wrapper' "$STATUS"; then
    pass "the probe comment states the bounded parity truthfully"
else
    fail "the probe comment states the bounded parity truthfully"
fi

# --- 0.0.44b W12b/W15/W16: unscannable render, line-wise roots, null coercion -----------
if grep -qF 'scan_unscannable=true' "$STATUS" && grep -qF 'agent config unscannable' "$STATUS"; then
    pass "status.sh renders unscannable (never false-green) for parser rc != 0 (W12b)"
else
    fail "status.sh renders unscannable (never false-green) for parser rc != 0 (W12b)"
fi
if grep -qF 'str(entry.get("ghsa_id") or "")' "$STATUS"; then
    pass "status.sh coerces a null ghsa_id (the F7 class twin, V19)"
else
    fail "status.sh coerces a null ghsa_id (the F7 class twin, V19)"
fi
_gap_fn=$(sed -n '/^    _st_dbdump_gap() {/,/^    }$/p' "$STATUS")
if [ -n "$_gap_fn" ]; then
    pass "status.sh: gap function extractable (W15)"
    _gap_work=$(mktemp -d)
    printf '/var/tmp/root-one\n/var/tmp/my projects\n' > "$_gap_work/projects.conf"
    _gap_args=""
    _gap_rc=0
    (
        PROJECTS_CONF="$_gap_work/projects.conf"
        _mig_root=""
        _mig_dir=""
        # the stubs write to files: _st_dbdump_gap runs inside the pipe's
        # subshell, variables would not propagate out
        ddev_migrate_gap() { shift; printf '%s\n' "$#" > "$_gap_work/argc"; printf '%s\n' "$*" > "$_gap_work/args"; return 1; }
        ddev_migrate_projects() { printf '' ; }
        ddev_migrate_home() { printf '/home/x'; }
        ui_kv_warn() { :; }
        ui_detail()  { :; }
        eval "$_gap_fn"
        grep -v '^[[:space:]]*$' "$PROJECTS_CONF" | _st_dbdump_gap devuser || true
    ) > "$_gap_work/out" 2>/dev/null || _gap_rc=$?
    _got_n=$(sed -n '1p' "$_gap_work/argc")
    _got_roots=$(sed -n '1p' "$_gap_work/args")
    if [ "$_got_n" = "2" ] && [ "$_got_roots" = "/var/tmp/root-one /var/tmp/my projects" ]; then
        pass "gap check feeds roots line-wise: spaced root stays ONE argument (W15)"
    else
        fail "gap check feeds roots line-wise: spaced root stays ONE argument (W15, n=$_got_n roots=$_got_roots)"
    fi
    rm -rf "$_gap_work"
else
    fail "status.sh: gap function extractable (W15)"
fi

# --- 0.0.45c S3 / 0.0.45d W3: sudo-rules audit flags ANY listing, locale-proof --
# The old regex ('\((ALL|opencode)[^)]*\)') printed the green "none for
# opencode" for a manual `(root)` or `(dev)` grant — the exact later-
# manual-grant class the row exists to catch (S3). W3: the header grep
# alone was locale-fragile — sudo localizes the -l listing and its
# default env_keep preserves LANG/LC_*, so a translated header escaped
# the English pattern; the probe now pins LC_ALL=C and the pattern gains
# a structural runas disjunct. Verbatim pins on both, behavioral replay
# of the REAL extracted pattern against representative listings incl. a
# TRANSLATED header.
_sudo_grep="$(grep -F "LC_ALL=C sudo -n -l -U " "$STATUS" | head -1 | sed 's/^ *//')"
_sra_pat="$(grep -F "_sra_pat=" "$STATUS" | head -1 | sed -e 's/^ *//' -e "s/^_sra_pat=//" -e "s/^'//" -e "s/'\$//")"
if printf '%s\n' "$_sudo_grep" | grep -q 'grep -Eq'; then
    pass "sudo-rules audit probes with LC_ALL=C (S3+W3, verbatim pin)"
else
    fail "sudo-rules audit must pin the listing locale with LC_ALL=C (W3)"
fi
if printf '%s\n' "$_sra_pat" | grep -qF 'may run the following commands' \
   && printf '%s\n' "$_sra_pat" | grep -qF '\([^)]+\)'; then
    pass "audit pattern: listing header + structural runas disjunct (W3)"
else
    fail "audit pattern must keep the header and add the runas disjunct (W3)"
fi
if [ -n "$_sra_pat" ]; then
    _s3_flag() { printf '%s\n' "$1" | grep -Eq "$_sra_pat" >/dev/null 2>&1; }
    if _s3_flag 'User opencode may run the following commands on host:
    (root) NOPASSWD: /usr/bin/systemctl restart foo'; then
        pass "a (root) runas grant is flagged red (S3)"
    else
        fail "a (root) runas grant is flagged red (S3)"
    fi
    if _s3_flag 'User opencode may run the following commands on host:
    (dev) NOPASSWD: /bin/foo'; then
        pass "a (dev) runas grant is flagged red (S3)"
    else
        fail "a (dev) runas grant is flagged red (S3)"
    fi
    if _s3_flag 'User opencode may run the following commands on host:
    (ALL : ALL) ALL'; then
        pass "an (ALL) runas grant stays flagged (S3, old regex parity)"
    else
        fail "an (ALL) runas grant stays flagged (S3, old regex parity)"
    fi
    if _s3_flag 'Benutzer opencode darf die folgenden Befehle auf diesem Host ausfuehren:
    (root) NOPASSWD: /usr/bin/foo'; then
        pass "a TRANSLATED header with a runas grant is still flagged (W3)"
    else
        fail "a translated header with a runas grant must be flagged via the runas disjunct (W3)"
    fi
    if _s3_flag 'User opencode is not allowed to run sudo on host.'; then
        fail "the not-allowed wording stays green (S3)"
    else
        pass "the not-allowed wording stays green (S3)"
    fi
    if _s3_flag 'Benutzer opencode darf sudo auf diesem Host nicht ausfuehren.'; then
        fail "the translated not-allowed wording stays green (W3)"
    else
        pass "the translated not-allowed wording stays green (W3)"
    fi
fi

# OpenChamber state line (issue #154, Tier 3): the verdicts — secured via
# the policy pin, BYPASSED (leftover binaries/settings pin without it),
# advice when OpenChamber is present but unpinned, shadow note when only
# self-installed binaries exist without OpenChamber (0.0.47a F4). Static
# pins below; the verdict matrix itself runs functionally further down.
if grep -q 'secured via policy pin' "$STATUS" \
    && grep -q 'BYPASSED' "$STATUS" \
    && grep -q "sudo opk openchamber-secure" "$STATUS"; then
    pass "status shows the OpenChamber state (secured/bypassed/advice)"
else
    fail "status lost the OpenChamber state line"
fi
# detection reuses the wrapper's semantics: a pin on the kit wrapper itself
# is not a bypass, an empty pin counts as unset
if grep -q '_oc_secured=true' "$STATUS" \
    && grep -qF '[ "$_oc_pin" = "/usr/local/bin/opencode" ]' "$STATUS"; then
    pass "status pin detection matches the wrapper semantics"
else
    fail "status pin detection diverges from the wrapper"
fi
# home resolution via getent with /home/<user> fallback (0.0.47b W2, the
# 0.0.43a F12 class): relocated homes must not blank the verdicts
if grep -q 'getent passwd "${DEFAULT_USER:-$USER}"' "$STATUS" \
    && grep -qF '_oc_home="${_oc_home:-/home/${DEFAULT_USER:-$USER}}"' "$STATUS"; then
    pass "openchamber verdicts resolve the home via getent (0.0.47b W2)"
else
    fail "openchamber home resolution regressed to /home hardcode (0.0.47b W2)"
fi
# 0.0.47c C1: EXECUTE the real home-resolution lines (the matrix below
# rewrites them away, so neither getent nor fallback ever runs there) —
# both directions. root's passwd home (/root) differs from the
# /home/<user> fallback on every suite host, so anything that discards
# getent's result (a planted or reordered hardcode assignment keeping
# both pinned lines intact) fails the first assert; an unresolvable user
# takes the fallback without crashing (the L1 failure path).
# Environment-dependent (0.0.46a F2 class): needs getent + root's home
# at /root — true on every Linux host the suite runs on; without getent,
# status.sh itself degrades to the fallback everywhere.
OCV_HOME_SRC="$(awk '/^_oc_policy=/{_ocv=1} _ocv{ if ($0 ~ /^f="\/home/) exit; print }' "$STATUS" \
    | grep '^_oc_home=' || true)"
if [ -n "$OCV_HOME_SRC" ]; then
    pass "openchamber home-resolution lines extractable (0.0.47c C1)"
else
    fail "openchamber home-resolution lines not extractable (0.0.47c C1)"
fi
_oc_home_probe() {
    (
        DEFAULT_USER="$1"
        USER=_oc_probe_unused
        eval "$OCV_HOME_SRC"
        printf '%s\n' "$_oc_home"
    )
}
_oc_probe_root="$(_oc_home_probe root)"
if [ "$_oc_probe_root" = "/root" ]; then
    pass "openchamber home resolution: getent wins over the /home fallback (0.0.47c C1)"
else
    fail "openchamber home resolution discards getent — expected /root, got '$_oc_probe_root' (0.0.47c C1)"
fi
_oc_probe_none="$(_oc_home_probe oc-no-such-user-0.0.47c)"
if [ "$_oc_probe_none" = "/home/oc-no-such-user-0.0.47c" ]; then
    pass "openchamber home resolution: fallback taken on unresolvable user (0.0.47c C1)"
else
    fail "openchamber home resolution fallback broken — got '$_oc_probe_none' (0.0.47c C1)"
fi

# --- OpenChamber verdict matrix — functional (0.0.47a F3/F4) ---------------------
# Extract the verdict block, rewrite the absolute paths (policy file, kit
# wrapper, kit bin, default-user home) to fixtures, eval it with a stubbed
# ui_kv under a hermetic PATH, and drive every state — including the
# kit-symlink exemption (F3: wrapper guard semantics) and the
# shadow-binary-without-OpenChamber verdict (F4: BYPASSED only when
# OpenChamber is actually installed).
OCV_ROOT="$WORK/ocv"
OCV_POLICY="$OCV_ROOT/policy.json"
OCV_HOME="$OCV_ROOT/home"
OCV_WRAPPER="$OCV_ROOT/kit-wrapper"
OCV_KITBIN="$OCV_ROOT/kit-bin"
OCV_BINDIR="$OCV_ROOT/bin"
mkdir -p "$OCV_HOME" "$OCV_BINDIR"
: > "$OCV_WRAPPER"
: > "$OCV_KITBIN"
# Hermetic PATH for the eval below (0.0.48 release blocker, the 0.0.46a
# F2 environment-dependence class): the block probes `command -v
# openchamber`, so the host PATH must never be inherited — the
# maintainer machine runs a real OpenChamber (nvm install) that flipped
# the "without" verdicts and broke `make release` locally while CI
# stayed green. The scratch bin symlinks the block's only externals
# (sed, tail, readlink — getent/cut sit on the rewritten-away _oc_home
# lines); nothing else on PATH is reachable from the eval.
OCV_HBIN="$OCV_ROOT/hermit-bin"
OCV_HMISSING=""
mkdir -p "$OCV_HBIN"
for _ocvh in sed tail readlink; do
    if _ocvt="$(command -v "$_ocvh" 2>/dev/null)"; then
        ln -s "$_ocvt" "$OCV_HBIN/$_ocvh"
    else
        OCV_HMISSING="$_ocvh $OCV_HMISSING"
    fi
done
if [ -z "$OCV_HMISSING" ]; then
    pass "verdict matrix hermetic bin complete (sed/tail/readlink linked)"
else
    fail "verdict matrix hermetic bin incomplete: $OCV_HMISSING"
fi
# Extract from `_oc_policy=` up to (excluding) the `f="/home/...` line that
# follows the block — the block contains col-0 `fi` lines of its inner ifs,
# so a sed range on `^fi$` would stop early.
OCV_BLOCK="$(awk '/^_oc_policy=/{_ocv=1} _ocv{ if ($0 ~ /^f="\/home/) exit; print }' "$STATUS" \
    | sed -e "s|/etc/openchamber/policy.json|$OCV_POLICY|g" \
        -e "s|/usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode|$OCV_WRAPPER|g" \
        -e "s|/usr/local/bin/opencode|$OCV_KITBIN|g" \
        -e "s|^_oc_home=.*|_oc_home=\"$OCV_HOME\"|")"
if [ -n "$OCV_BLOCK" ]; then
    pass "openchamber verdict block extractable from status.sh"
else
    fail "openchamber verdict block not extractable from status.sh"
fi
# ocv_run <with|without> — eval the block under the hermetic PATH;
# "with" prepends the fake-openchamber bin, "without" sees no openchamber
# at all — the host's real one included. Prints the ui_kv lines. The
# semantic verdict helpers (issue #158 sweep) are stubbed to the same
# shape — the matrix judges the VERDICT TEXT, not the counting.
ocv_run() {
    (
        PATH="$OCV_HBIN"
        [ "$1" = with ] && PATH="$OCV_BINDIR:$PATH"
        ui_kv() { printf '%s %s\n' "$1" "$2"; }
        ui_kv_ok() { printf '%s %s\n' "$1" "$2"; }
        ui_kv_warn() { printf '%s %s\n' "$1" "$2"; }
        ui_kv_bad() { printf '%s %s\n' "$1" "$2"; }
        eval "$OCV_BLOCK"
    )
}

# 1. clean home, no OpenChamber -> no line at all
out="$(ocv_run without)"
if [ -z "$out" ]; then
    pass "verdict matrix: clean state prints no OpenChamber line"
else
    fail "verdict matrix: clean state prints no OpenChamber line (got: $out)"
fi

# 2. F3: a symlink to the kit wrapper is NOT a bypass binary -> still quiet
mkdir -p "$OCV_HOME/.opencode/bin"
ln -s "$OCV_WRAPPER" "$OCV_HOME/.opencode/bin/opencode"
out="$(ocv_run without)"
if [ -z "$out" ]; then
    pass "verdict matrix: kit-owned symlink ignored (0.0.47a F3)"
else
    fail "verdict matrix: kit-owned symlink ignored (0.0.47a F3) (got: $out)"
fi

# 3. F4: plain shadow binary, OpenChamber not installed -> shadow note,
#    never the red BYPASSED verdict
rm -f "${OCV_HOME:?}/.opencode/bin/opencode"
echo fake > "$OCV_HOME/.opencode/bin/opencode"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'not installed' \
    && ! printf '%s' "$out" | grep -q 'BYPASSED'; then
    pass "verdict matrix: shadow binary without OpenChamber is not BYPASSED (0.0.47a F4)"
else
    fail "verdict matrix: shadow binary without OpenChamber is not BYPASSED (0.0.47a F4) (got: $out)"
fi

# 4. settings pin (config dir present) -> BYPASSED
mkdir -p "$OCV_HOME/.config/openchamber"
printf '{ "opencodeBinary": "/tmp/evil-opencode" }\n' \
    > "$OCV_HOME/.config/openchamber/settings.json"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'BYPASSED'; then
    pass "verdict matrix: settings pin without policy -> BYPASSED"
else
    fail "verdict matrix: settings pin without policy -> BYPASSED (got: $out)"
fi

# 5. policy pins the kit bin -> secured, leftovers noted as inert
printf '{ "opencodeBinary": "%s" }\n' "$OCV_KITBIN" > "$OCV_POLICY"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'secured via policy pin' \
    && printf '%s' "$out" | grep -q 'leftover bypass files present'; then
    pass "verdict matrix: policy secures, leftovers called inert"
else
    fail "verdict matrix: policy secures, leftovers called inert (got: $out)"
fi

# 6. F3 under policy: only the kit symlink remains (plain binary and
#    settings pin removed) -> secured without a leftover note
rm -f "${OCV_HOME:?}/.opencode/bin/opencode" "${OCV_HOME:?}/.config/openchamber/settings.json"
ln -s "$OCV_WRAPPER" "$OCV_HOME/.opencode/bin/opencode"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'secured via policy pin' \
    && ! printf '%s' "$out" | grep -q 'leftover'; then
    pass "verdict matrix: kit symlink under policy is not a leftover (0.0.47a F3)"
else
    fail "verdict matrix: kit symlink under policy is not a leftover (0.0.47a F3) (got: $out)"
fi

# 7. advice state via the command marker (no files, fake openchamber on PATH)
rm -f "${OCV_HOME:?}/.opencode/bin/opencode" "${OCV_POLICY:?}" \
    "${OCV_HOME:?}/.config/openchamber/settings.json"
printf '#!/bin/sh\n' > "$OCV_BINDIR/openchamber"
chmod +x "$OCV_BINDIR/openchamber"
out="$(ocv_run with)"
if printf '%s' "$out" | grep -q 'policy pin missing'; then
    pass "verdict matrix: command marker alone -> advice line"
else
    fail "verdict matrix: command marker alone -> advice line (got: $out)"
fi

# 8. a host openchamber on the CALLER's PATH must not leak into the matrix
#    (the 0.0.48 release blocker: a real openchamber — nvm-installed on
#    the maintainer host, absent on CI — flipped cases 1-3 red only on
#    `make release` runs from that machine). The poisoned prefix is the
#    old bug's exact channel: ocv_run used to inherit the host PATH on
#    "without" runs; under the hermetic PATH the prefix dies with it.
rm -rf "${OCV_HOME:?}/.config" "${OCV_HOME:?}/.opencode"
out="$(PATH="$OCV_BINDIR:$PATH" ocv_run without)"
if [ -z "$out" ]; then
    pass "verdict matrix ignores a host openchamber on PATH (0.0.48 leak)"
else
    fail "verdict matrix leaks the host PATH into the verdicts (got: $out)"
fi

# --- issue #158: verdict summary, --short, .git/config wording --------------------
# Static pins first (wording + sweep invariants), then the extracted
# summary block driven through every verdict/exit-code combination.

# .git/config wording: "protected"/"access allowed" instead of ON/OFF;
# OFF deliberately NEUTRAL (a conscious config choice is a hint, not a
# warning — maintainer decision on the ticket).
if grep -qF 'ui_kv_ok ".git/config" "protected (soft-only — agent tools blocked)"' "$STATUS" \
   && grep -qF 'ui_kv ".git/config" "access allowed (agent tools may edit git config)"' "$STATUS" \
   && ! grep -qF '"ON (soft-only' "$STATUS" \
   && ! grep -qF 'ui_kv ".git/config" "OFF"' "$STATUS"; then
    pass ".git/config row reads protected / access allowed (issue #158)"
else
    fail ".git/config row wording regressed to ON/OFF"
fi

# Sweep invariant: status.sh carries NO raw color-argument ui_kv rows
# anymore — every verdict row goes through the semantic helpers, so the
# summary cannot miss one (class sweep of the 62 sites, 0.0.46a F2 style).
if ! grep -qE '"\$UI_(GREEN|YELLOW|RED)"' "$STATUS" \
   && grep -q 'ui_kv_ok ' "$STATUS" && grep -q 'ui_kv_bad ' "$STATUS"; then
    pass "status.sh: all colored rows use semantic helpers (countable)"
else
    fail "status.sh: raw colored ui_kv row survived the sweep"
fi
GIT_CHECK_SH="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/git-check.sh"
if ! grep -qE 'ui_kv .*"\$UI_(GREEN|YELLOW|RED)"' "$GIT_CHECK_SH"; then
    pass "git-check.sh: Core row uses semantic helpers too"
else
    fail "git-check.sh still colors rows via raw ui_kv (uncounted)"
fi

# Severity tallies only see MAIN-shell rows: the three scanning loops
# feed from temp files via redirect, never from a `cmd | while` pipe
# (counter bumps inside a pipe subshell die there). Shape pins per site.
if grep -qF 'done < "$_st_share_list"' "$STATUS" \
   && grep -qF 'done < "$_st_hosts_list"' "$STATUS" \
   && grep -qF '_st_dbdump_gap "$DEFAULT_USER" < "$_st_gap_roots"' "$STATUS"; then
    pass "scan loops run in the main shell (redirect, not pipe)"
else
    fail "a scan loop prints its findings from a pipe subshell again"
fi

# One-line mode must be exactly one line: no raw echo/printf leaks past
# UI_SILENT (the hosts-scan add-lines and the leak-scan hit list are the
# two raw-print sites; both are guarded/converted).
if grep -qF 'ui_detail "add: opk ddev-hosts-add' "$STATUS" \
   && ! grep -qF 'echo "     add' "$STATUS"; then
    pass "--short: raw-print sites converted/guarded (one-line discipline)"
else
    fail "a raw print site can leak past UI_SILENT"
fi

# Checkout-first lib resolution (0.0.46a F4 pattern): a checkout run must
# source ITS OWN ui.sh/git-check.sh — a deployed pre-#158 copy would drop
# every ui_kv_ok/ui_kv_bad row (command not found) and the verdict.
if grep -qF 'UI_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/ui.sh"' "$STATUS" \
   && grep -qF 'GIT_CHECK_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/git-check.sh"' "$STATUS"; then
    pass "status.sh resolves ui.sh/git-check.sh checkout-first"
else
    fail "status.sh resolves ui.sh/git-check.sh deployed-first (pre-#158 skew)"
fi

# usage error: unknown flag -> exit 64 + usage line, before any probing
# (deterministic on every host, installed or not). rc=0 sentinel + `|| u_rc=$?`
# — the test script runs under set -e and a bare failing capture would
# abort the whole suite here.
u_rc=0
u_out=$(sh "$STATUS" --bogus 2>&1) || u_rc=$?
if [ "$u_rc" = "64" ] && printf '%s' "$u_out" | grep -q 'usage:'; then
    pass "unknown flag: usage error, exit 64"
else
    fail "unknown flag must exit 64 with a usage line (rc=$u_rc out=$u_out)"
fi

# Summary block, functional: extract from the snapshot lines to the final
# exit and drive every verdict/exit-code combination (0.0.45d W3-style
# behavioral replay; the extraction rewrites nothing).
SUMMARY_BLOCK="$(sed -n '/^_st_alerts=/,/^exit "\$_st_rc"$/p' "$STATUS")"
if [ -n "$SUMMARY_BLOCK" ] && printf '%s\n' "$SUMMARY_BLOCK" | grep -q '^exit "\$_st_rc"$'; then
    pass "summary block extractable from status.sh"
else
    fail "summary block not extractable (anchor drift?)"
fi
if [ -n "$SUMMARY_BLOCK" ]; then
    # run_summary <bad> <warn> <ok> <short true|false> — prints the block
    # output plus its exit code. ui_section records itself so the pin can
    # prove --short suppresses the section header. The `|| _rs_rc=$?`
    # capture keeps the suite's set -e alive through the verdict exits.
    # 0.0.48b W4: the harness presets UI_SILENT exactly the way the arg
    # parser does (1 iff --short) — without that, the mute→restore
    # interplay was never simulated and deleting the block's
    # UI_SILENT=0 restore kept every pin green while real --short went
    # fully silent.
    run_summary() {
        _rs_rc=0
        _rs_out=$(
            (
                set -u; set +e
                . "$UI_LIB"
                UI_ROWS_BAD=$1; UI_ROWS_WARN=$2; UI_ROWS_OK=$3
                STATUS_SHORT=$4
                if [ "$STATUS_SHORT" = true ]; then UI_SILENT=1; else UI_SILENT=0; fi
                ui_section() { printf 'SECTION:%s\n' "$1"; }
                eval "$SUMMARY_BLOCK"
            ) 2>&1
        ) || _rs_rc=$?
        printf '%s\nrc=%s\n' "$_rs_out" "$_rs_rc"
    }
    _sum=$(run_summary 1 2 5 false)
    if printf '%s' "$_sum" | grep -q '1 alert(s), 2 warning(s)' \
       && printf '%s' "$_sum" | grep -q 'see the sections above' \
       && printf '%s' "$_sum" | grep -q 'SECTION:Summary' \
       && printf '%s' "$_sum" | grep -q 'rc=1'; then
        pass "verdict: alerts+warnings rendered, exit 1, full mode"
    else
        fail "verdict alert case broken (got: $_sum)"
    fi
    # counts snapshot BEFORE the verdict row: the alert row itself bumps
    # UI_ROWS_BAD — a snapshot after it would print 2 alert(s)
    _sum=$(run_summary 1 2 5 false)
    if ! printf '%s' "$_sum" | grep -q '2 alert(s)'; then
        pass "verdict row excluded from its own tally (snapshot first)"
    else
        fail "verdict row counts itself (snapshot sits too late)"
    fi
    _sum=$(run_summary 0 1 5 false)
    if printf '%s' "$_sum" | grep -q '1 warning(s)' \
       && printf '%s' "$_sum" | grep -q 'rc=2'; then
        pass "verdict: warnings only, exit 2"
    else
        fail "verdict warning case broken (got: $_sum)"
    fi
    _sum=$(run_summary 0 0 7 false)
    if printf '%s' "$_sum" | grep -q 'All green' \
       && printf '%s' "$_sum" | grep -q '7 checks passed' \
       && printf '%s' "$_sum" | grep -q 'rc=0'; then
        pass "verdict: all green with the pass count, exit 0"
    else
        fail "verdict green case broken (got: $_sum)"
    fi
    _sum=$(run_summary 1 2 5 true)
    if printf '%s' "$_sum" | grep -q "run 'opk status' for the full report" \
       && ! printf '%s' "$_sum" | grep -q 'SECTION:Summary' \
       && printf '%s' "$_sum" | grep -q 'rc=1'; then
        pass "verdict --short: one line, no section header, exit 1"
    else
        fail "verdict --short case broken (got: $_sum)"
    fi
fi

# not-installed + --short: one line, exit 1 (machine mode reports the
# loudest not-green state; full mode keeps exit 0 — pin below stays).
if ! id opencode >/dev/null 2>&1; then
    ni_rc=0
    ni_out=$(sh "$STATUS" --short 2>&1) || ni_rc=$?
    if [ "$ni_rc" = "1" ] && printf '%s' "$ni_out" | grep -q 'not installed — hardening NOT active' \
       && [ "$(printf '%s\n' "$ni_out" | grep -c .)" = "1" ]; then
        pass "not-installed + --short: exactly one line, exit 1"
    else
        fail "not-installed + --short broken (rc=$ni_rc out=$ni_out)"
    fi
else
    echo "  info   opencode user exists on this host — skipping not-installed --short check"
fi
# wording pin for the same path (runs everywhere)
if grep -qF 'not installed — hardening NOT active (run' "$STATUS"; then
    pass "not-installed --short line wording pinned"
else
    fail "not-installed --short line wording drifted"
fi

# --- 0.0.48b W2: mktemp failure is LOUD — never a /dev/null fallback ------
# Behavioral failure-path pins (L1): each scan site's mktemp block is
# extracted verbatim and run with a FAILING mktemp — the skip warning
# must fire (a warn row counts, so the summary reflects the dead scan),
# the scan itself must NOT run, and nothing may be rm'd (the wave's
# /dev/null fallback silently killed the tally and its cleanup rm -f'd
# the device node when root ran it). A control run with a working mktemp
# proves the harness exercises the real block (find flows, cleanup runs).
W2_BLOCK_SHARE="$(sed -n '/_st_share_list=\$(mktemp)/,/^ *rm -f "\$_st_share_list"$/p' "$STATUS")"
W2_BLOCK_HOSTS="$(sed -n '/_st_hosts_list=\$(mktemp)/,/^ *rm -f "\$_st_hosts_list"$/p' "$STATUS")"
W2_BLOCK_GAP="$(sed -n '/_st_gap_roots=\$(mktemp)/,/^ *fi$/p' "$STATUS")"
if [ -n "$W2_BLOCK_SHARE" ] && [ -n "$W2_BLOCK_HOSTS" ] && [ -n "$W2_BLOCK_GAP" ]; then
    pass "W2 scan blocks extractable from status.sh"
else
    fail "W2 scan blocks not extractable (anchor drift?)"
fi

# w2_run <block> <mktemp-works true|false> — runs an extracted scan block
# in the loop context the real script provides (`continue` is legal
# there), with the scan helpers stubbed to markers. The suite runs under
# set -e: callers capture with `|| true`.
w2_run() {
    (
        if [ "$2" = true ]; then
            _w2_dir=$(command mktemp -d)
            mktemp() { printf '%s/list\n' "$_w2_dir"; }
        else
            mktemp() { return 1; }
        fi
        find() { echo "FIND-CALLED"; }
        rm() { echo "RM-CALLED $*"; }
        grep() { echo "GREP-CALLED"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail() { :; }
        ddev_reshare_needed() { return 1; }
        ddev_hosts_missing() { echo ""; }
        _st_dbdump_gap() { echo "GAP-CALLED"; }
        OPENCODE_USER=opencode
        LIBDIR=/usr/local/lib/opencode-permissions-kit
        PROJECTS_CONF=/nonexistent-w2-projects.conf
        DEFAULT_USER=w2user
        while IFS= read -r _st_root; do
            eval "$1"
        done <<EOF
/var/www/w2-proj
EOF
        if [ "$2" = true ] && [ -n "${_w2_dir:-}" ]; then command rm -rf "$_w2_dir"; fi
    )
}

if [ -n "$W2_BLOCK_SHARE" ]; then
    _w2out=$(w2_run "$W2_BLOCK_SHARE" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|ddev share|scan skipped for /var/www/w2-proj' \
        && ! printf '%s' "$_w2out" | grep -q 'FIND-CALLED' \
        && ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 share scan: mktemp failure warns loudly, no find, no rm"
    else
        fail "W2 share scan: mktemp failure must warn and skip (got: $_w2out)"
    fi
    _w2out=$(w2_run "$W2_BLOCK_SHARE" true || true)
    if ! printf '%s' "$_w2out" | grep -q 'scan skipped' \
        && printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 share scan: working mktemp flows find→report→cleanup (control)"
    else
        fail "W2 share scan control broken (got: $_w2out)"
    fi
fi
if [ -n "$W2_BLOCK_HOSTS" ]; then
    _w2out=$(w2_run "$W2_BLOCK_HOSTS" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|hosts (win)|scan skipped for /var/www/w2-proj' \
        && ! printf '%s' "$_w2out" | grep -q 'FIND-CALLED' \
        && ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 hosts scan: mktemp failure warns loudly, no find, no rm"
    else
        fail "W2 hosts scan: mktemp failure must warn and skip (got: $_w2out)"
    fi
fi
if [ -n "$W2_BLOCK_GAP" ]; then
    _w2out=$(w2_run "$W2_BLOCK_GAP" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|db dumps|gap scan skipped' \
        && ! printf '%s' "$_w2out" | grep -q 'GAP-CALLED' \
        && ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 dbdump gap: mktemp failure warns loudly, scan skipped"
    else
        fail "W2 dbdump gap: mktemp failure must warn and skip (got: $_w2out)"
    fi
fi
# class sweep (L2): no /dev/null fallback assignment survives anywhere
if ! grep -qE '_(share_list|hosts_list|gap_roots)=/dev/null' "$STATUS"; then
    pass "W2 class sweep: no /dev/null fallback assignment remains"
else
    fail "W2 class sweep: a /dev/null fallback survived"
fi

# --- 0.0.48b W3: privilege-unknown and optional rows never count -------------
# The verdict counts findings, not unknowns: "unknown — needs root" and
# "missing (optional …" rows are plain ui_kv (uncounted) — otherwise every
# unprivileged or HTTPS-less host would be permanently non-green and the
# cron alert worthless. Pins the five converted rows incl. both socket
# twins, plus the negative sweep (no unknown/optional row via ui_kv_warn).
if grep -qF 'ui_kv "opencode version" "unknown — probe failed' "$STATUS" \
    && [ "$(grep -cF 'ui_kv "socket" "unknown — needs root to check' "$STATUS")" = "2" ] \
    && grep -qF 'ui_kv "mkcert CA" "unknown — needs root to check' "$STATUS" \
    && grep -qF 'ui_kv "mkcert CA" "missing (optional' "$STATUS" \
    && ! grep -qE 'ui_kv_warn "[^"]*" "unknown — (needs root|probe failed)' "$STATUS" \
    && ! grep -qF 'ui_kv_warn "mkcert CA" "missing (optional' "$STATUS"; then
    pass "W3: unknown/optional rows are uncounted (plain ui_kv, both socket twins)"
else
    fail "W3: an unknown/optional row still counts (or the conversion drifted)"
fi

# --- 0.0.48b W4: the --short output guards are pinned behaviorally ------------
# The static one-line pin covered only the hosts-scan echo conversion;
# the leak-scan hit-list guard and the management-block guard now run as
# extracted blocks through both STATUS_SHORT states — muted means really
# nothing prints, full mode means the content prints.
w4_run() {
    (
        head() { echo "HEAD-CALLED"; }
        sed() { cat; }
        ui_info() { echo "INFO|$1"; }
        ui_detail() { echo "DETAIL|$1"; }
        scan_hits="w4hit"
        scan_count=1
        STATUS_SHORT=$2
        eval "$1"
    )
}
W4_BLOCK_HITLIST="$(sed -n '/# Hit list prints in full mode only/,/^ *fi$/p' "$STATUS")"
W4_BLOCK_MGMT="$(sed -n '/# --short skips the block: one verdict line means one line/,/^fi$/p' "$STATUS")"
if [ -n "$W4_BLOCK_HITLIST" ] && [ -n "$W4_BLOCK_MGMT" ]; then
    pass "W4 guard blocks extractable from status.sh"
else
    fail "W4 guard blocks not extractable (anchor drift?)"
fi
if [ -n "$W4_BLOCK_HITLIST" ]; then
    _w4out=$(w4_run "$W4_BLOCK_HITLIST" true || true)
    if [ -z "$(printf '%s' "$_w4out" | grep -v '^ *$')" ]; then
        pass "W4 hit list: --short prints none of it"
    else
        fail "W4 hit list leaks into --short (got: $_w4out)"
    fi
    _w4out=$(w4_run "$W4_BLOCK_HITLIST" false || true)
    if printf '%s' "$_w4out" | grep -q 'HEAD-CALLED'; then
        pass "W4 hit list: full mode prints it (control)"
    else
        fail "W4 hit list control broken (got: $_w4out)"
    fi
fi
if [ -n "$W4_BLOCK_MGMT" ]; then
    _w4out=$(w4_run "$W4_BLOCK_MGMT" true || true)
    if ! printf '%s' "$_w4out" | grep -q 'INFO|'; then
        pass "W4 management block: --short prints none of it"
    else
        fail "W4 management block leaks into --short (got: $_w4out)"
    fi
    _w4out=$(w4_run "$W4_BLOCK_MGMT" false || true)
    if printf '%s' "$_w4out" | grep -q 'INFO|Management (run in a terminal)'; then
        pass "W4 management block: full mode prints it (control)"
    else
        fail "W4 management control broken (got: $_w4out)"
    fi
fi

# --- 0.0.48c C1: a missing/unexecutable managed binary is a FINDING ------------
# W3's uncounted "unknown" class must not swallow a broken kit: with
# $LIBDIR/bin/opencode gone, the gate warns (counted) and never reaches
# the probe; with a working binary, the probe path runs and no warn
# fires. Behavioral: the extracted gate block against fixture LIBDIRs.
W48C_BLOCK_ADV="$(sed -n '/^    ADV_VER=""$/,/^    fi$/p' "$STATUS")"
if printf '%s' "$W48C_BLOCK_ADV" | grep -q 'ui_kv_warn "opencode binary"' \
    && printf '%s' "$W48C_BLOCK_ADV" | grep -q 'elif command -v sudo'; then
    pass "C1 gate block extractable (warn + elif shape)"
else
    fail "C1 gate block not extractable (anchor drift?)"
fi
w48c_run() {
    (
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_kv() { echo "KV|$1|$2"; }
        # timeout is external — it would exec the REAL sudo, invisible to
        # the stub below; drop the duration and exec in-shell instead.
        timeout() { shift 1; "$@"; }
        sudo() { shift 3; "$@"; }
        LIBDIR="$1"
        OPENCODE_USER=opencode
        eval "$2"
        echo "ADV_VER=${ADV_VER:-unset}"
    )
}
if [ -n "$W48C_BLOCK_ADV" ]; then
    # broken kit: no bin/opencode under LIBDIR
    _c1dir=$(mktemp -d)
    _c1out=$(w48c_run "$_c1dir" "$W48C_BLOCK_ADV" || true)
    if printf '%s' "$_c1out" | grep -q '^WARN|opencode binary|missing or not executable' \
        && printf '%s' "$_c1out" | grep -q '^ADV_VER=unset$'; then
        pass "C1: missing binary warns (counted), probe never runs"
    else
        fail "C1: missing binary must warn loudly (got: $_c1out)"
    fi
    # control: executable fake binary -> probe path runs, no warn
    mkdir -p "$_c1dir/bin"
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' > "$_c1dir/bin/opencode"
    chmod +x "$_c1dir/bin/opencode"
    _c1out=$(w48c_run "$_c1dir" "$W48C_BLOCK_ADV" || true)
    if ! printf '%s' "$_c1out" | grep -q '^WARN|' \
        && printf '%s' "$_c1out" | grep -q '^ADV_VER=9.9.9$'; then
        pass "C1: working binary probes (control), no warn"
    else
        fail "C1 control broken (got: $_c1out)"
    fi
    rm -rf "$_c1dir"
fi

# --- 0.0.48d D1: the unknown row is present-binary shapes ONLY -----------------
# The 0.0.48c prescription's second leg, pinned: with the binary missing
# the stale "unknown — probe failed (run: sudo opk status)" row must NOT
# print (the counted warn above already spoke; the advice cannot work for
# that shape) — while the privilege-unknown shape keeps the W3 row
# (over-suppression would hide the legit shape). Behavioral: gate +
# render blocks against fixture LIBDIRs. Issue #163 re-specifies the
# third fixture: a present-but-failing binary is no longer one class —
# the direct classifier splits it into corrupt (rc != 0, counted warn)
# vs. privilege-gap (sudo refused, binary healthy, uncounted row).
W48D_BLOCK_RENDER="$(sed -n '/^    if \[ -n "\$ADV_VER" \]; then$/,/^    fi$/p' "$STATUS")"
if printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'elif [ -x "$LIBDIR/bin/opencode" ]' \
    && printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'ui_kv "opencode version" "unknown — probe failed'; then
    pass "D1 render block extractable (elif-gated unknown row)"
else
    fail "D1 render block not extractable (anchor drift?)"
fi
# Issue #163: the direct classifier must live INSIDE the extracted
# render block (the harness evals gate + render; a classifier placed
# outside would be untested here and drift silently).
if printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'ADV_DIRECT_RC=$?' \
    && printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'present but broken'; then
    pass "D1/#163: direct-probe classifier extractable in the render block"
else
    fail "D1/#163: classifier not extractable from the render block (anchor drift?)"
fi
w48d_run() {
    (
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_kv() { echo "KV|$1|$2"; }
        ui_kv_ok() { echo "OK|$1|$2"; }
        ui_kv_bad() { echo "BAD|$1|$2"; }
        ui_detail() { echo "DETAIL|$1"; }
        # render-only stub: no advisories database in the fixture — the
        # OK branch is the one under test, not the matching logic.
        advisories_matching() { return 1; }
        timeout() { shift 1; "$@"; }
        # "refuse-sudo": mirror sudo -n's password refusal (rc 1, empty
        # output) — the W3 privilege shape. Otherwise the working-sudo
        # stub (strip the -n -u <user> prefix, exec as-is).
        if [ "$2" = "refuse-sudo" ]; then
            sudo() { return 1; }
        else
            sudo() { shift 3; "$@"; }
        fi
        LIBDIR="$1"
        OPENCODE_USER=opencode
        VERSION=0.0.0
        ADV_VER=""
        eval "$W48C_BLOCK_ADV"
        eval "$W48D_BLOCK_RENDER"
    )
}
if [ -n "$W48C_BLOCK_ADV" ] && [ -n "$W48D_BLOCK_RENDER" ]; then
    _d1dir=$(mktemp -d)
    # missing binary: warn row, NO unknown row (the D1 property); the
    # advice must name the working repair — upgrade-opencode, not plain
    # update (0.0.49a W1: a plain update never touches the binary).
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|' \
        && printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|.*fix: sudo opk upgrade-opencode' \
        && ! printf '%s' "$_d1out" | grep -q 'fix: sudo opk update)' \
        && ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1: missing binary warns, naming the working repair (0.0.49a W1)"
    else
        fail "D1: missing binary warn must name upgrade-opencode, not plain update (got: $_d1out)"
    fi
    # working binary: probe renders the OK row, no unknown row
    mkdir -p "$_d1dir/bin"
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' > "$_d1dir/bin/opencode"
    chmod +x "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^OK|opencode 9.9.9|' \
        && ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1: working binary renders the OK row, no unknown row"
    else
        fail "D1: working binary must render via ADV_VER (got: $_d1out)"
    fi
    # present but BROKEN binary (issue #163): the recorded reachability
    # was a cp killed mid-write — a truncated binary with intact mode
    # bits. The direct probe classifies it (rc != 0, caller-independent)
    # into a COUNTED warn; the "sudo opk status" advice must not print
    # because no privilege resolves this shape.
    printf '\177ELFbroken-fixture' > "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|present but broken' \
        && printf '%s' "$_d1out" | grep -q 'fix: sudo opk upgrade-opencode' \
        && ! printf '%s' "$_d1out" | grep -q 'fix: sudo opk update)' \
        && ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1/#163: corrupt binary counts a warn with the working repair (0.0.49a W1)"
    else
        fail "D1/#163: corrupt binary must warn (counted) naming upgrade-opencode, not plain update (got: $_d1out)"
    fi
    # privilege-unknown shape (0.0.48b W3) under the #163 split: sudo
    # refuses, the binary itself is healthy — the direct classifier
    # returns 0 and the uncounted row STAYS (over-suppression would
    # hide the legit agent-user/cron shape).
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' > "$_d1dir/bin/opencode"
    chmod +x "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" refuse-sudo || true)
    if ! printf '%s' "$_d1out" | grep -q '^WARN|' \
        && printf '%s' "$_d1out" | grep -q '^KV|opencode version|unknown — probe failed'; then
        pass "D1/#163: sudo-refused + healthy binary keeps the unknown row (W3)"
    else
        fail "D1/#163: over-suppression — the privilege-unknown row is gone (got: $_d1out)"
    fi
    rm -rf "$_d1dir"
fi

# --- ddev() hook row via getent home (issue #192) --------------------------------
# The row must find the hook in the REAL home (getent), not a hardcoded
# /home/$DEFAULT_USER: on the root-shell installs the installer now
# refuses, that path was /home/root (never exists) and the row degraded
# to a permanent "not hooked — run opk update" warning that opk update
# could never heal. A uid-0 developer is reported as the install defect
# it is. Arms run the extracted block with stubbed id/getent and a fake
# LIBDIR; all homes live under $WORK.
_hk_block="$(sed -n '/^# ddev() hook row (issue #192)/,/^fi$/p' "$STATUS")"
if [ -n "$_hk_block" ]; then
    pass "ddev() hook row block extractable from status.sh (issue #192)"
    mkdir -p "$WORK/libkit/sh"
    : > "$WORK/libkit/sh/ddev-terminal.sh"
    # _hk_run <user> <uid|empty=id-fails> <home|empty-for-getent-miss>:
    # prints the row output; stubs decide id/getent so no arm depends on
    # host users. An EMPTY uid makes id fail, executing the probe's
    # `|| echo 1` fallback arm (#196 a T2).
    _hk_run() {
        (
            HK_USER="$1"; HK_UID="$2"; HK_HOME="$3"
            export HK_USER HK_UID HK_HOME DEFAULT_USER LIBDIR
            DEFAULT_USER="$HK_USER"
            LIBDIR="$WORK/libkit"
            id() { [ "${1:-}" = "-u" ] || return 1; [ -n "$HK_UID" ] \
                && printf '%s\n' "$HK_UID" || return 1; }
            getent() {
                [ "${1:-}" = passwd ] && [ "${2:-}" = "$HK_USER" ] && [ -n "$HK_HOME" ] \
                    && printf 'x:x:1000:1000::%s:/bin/sh\n' "$HK_HOME"
            }
            ui_kv_ok()   { echo "OK|$1|$2"; }
            ui_kv_warn() { echo "WARN|$1|$2"; }
            ui_detail()  { echo "DETAIL|$1"; }
            eval "$_hk_block"
        ) 2>&1
    }
    # root developer: the loud install-defect row, never "not hooked"
    _rc=0; _out=$(_hk_run root 0 "$WORK/anywhere") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q "WARN|ddev() hook|install broken — developer 'root' has uid 0" \
       && printf '%s' "$_out" | grep -q 'opk update cannot fix this' \
       && ! printf '%s' "$_out" | grep -q 'not hooked'; then
        pass "uid-0 developer reports the broken install + reinstall fix"
    else
        fail "uid-0 developer reports the broken install + reinstall fix (rc=$_rc out=$_out)"
    fi
    # relocated home with the hook line: active, via the getent home
    mkdir -p "$WORK/hk-homeA"
    printf '[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh\n' \
        > "$WORK/hk-homeA/.bashrc"
    _rc=0; _out=$(_hk_run hk-dev 1000 "$WORK/hk-homeA") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF "OK|ddev() hook|active — $WORK/hk-homeA/.bashrc"; then
        pass "relocated home: hook found active via getent home"
    else
        fail "relocated home: hook found active via getent home (rc=$_rc out=$_out)"
    fi
    # home exists, no hook line: the classic repairable warning stays
    mkdir -p "$WORK/hk-homeB"
    printf '# plain rc without kit hooks\n' > "$WORK/hk-homeB/.bashrc"
    _rc=0; _out=$(_hk_run hk-dev 1000 "$WORK/hk-homeB") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'WARN|ddev() hook|not hooked — run opk update'; then
        pass "existing home without hook keeps the repairable warning"
    else
        fail "existing home without hook keeps the repairable warning (rc=$_rc out=$_out)"
    fi
    # home missing: honest "cannot check" instead of unfulfillable advice
    _rc=0; _out=$(_hk_run hk-dev 1000 "$WORK/hk-missing") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'WARN|ddev() hook|cannot check — home' \
       && ! printf '%s' "$_out" | grep -q 'run opk update'; then
        pass "missing home: cannot-check row, no unfulfillable update advice"
    else
        fail "missing home: cannot-check row, no unfulfillable update advice (rc=$_rc out=$_out)"
    fi
    # getent miss: falls back to /home/<name> (never exists here — the
    # user name is suite-unique) — same honest cannot-check row
    _rc=0; _out=$(_hk_run rug-nouser-x 1000 "") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'cannot check — home'; then
        pass "getent miss: fallback path still reports cannot-check"
    else
        fail "getent miss: fallback path still reports cannot-check (rc=$_rc out=$_out)"
    fi
    # id-probe failure arm (#196 a T2): id fails -> `|| echo 1` sentinel ->
    # NOT the uid-0 defect row; the hook is still read via the real home.
    mkdir -p "$WORK/hk-idfail"
    printf '[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh\n' \
        > "$WORK/hk-idfail/.bashrc"
    _rc=0; _out=$(_hk_run hk-idfail "" "$WORK/hk-idfail") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF "OK|ddev() hook|active — $WORK/hk-idfail/.bashrc" \
       && ! printf '%s' "$_out" | grep -q 'install broken'; then
        pass "id-probe failure: sentinel uid reads the hook, no false uid-0 row (executed)"
    else
        fail "id-probe failure: sentinel uid reads the hook, no false uid-0 row (rc=$_rc out=$_out)"
    fi
else
    fail "ddev() hook row block extractable from status.sh (issue #192)"
fi

# --- issue #165: silently-droppable lib guards warn LOUDLY (counted) -------------
# status.sh sources its section libs behind existence guards; a damaged
# or partially deployed sh/ tree must not vanish a whole check family
# while the verdict stays green. Four sites owe a counted warn row
# (advisories, ddev-terminal, ddev-migrate, ddev-hosts); two stay as
# designed (wsl-browser-bridge degrades its own verdict to red by
# itself — no row needed; log.sh stays a silent best-effort audit
# line). Behavioral per site: the extracted block against fixture
# LIBDIRs — missing-lib arm (row fires, guarded body skipped) and
# present-lib control (body renders, no row) — plus the compound-guard
# negatives (unstamped install / unready host stay row-free) and the
# verdict/exit-code leg through the REAL ui.sh + summary block (the
# way production observes it).

# a) advisories: negated-guard fallback, complete block
_a165="$(sed -n '/^# Missing-lib fallback (issue #165):/,/^fi$/p' "$STATUS")"
if printf '%s' "$_a165" | grep -qF 'if [ ! -f "$LIBDIR/sh/advisories.sh" ]' \
    && printf '%s' "$_a165" | grep -qF 'ui_kv_warn "advisories database" "missing — security checks skipped (fix: sudo opk update)"'; then
    pass "165: advisories fallback block extractable (negated guard + counted row)"
else
    fail "165: advisories fallback block not extractable (anchor drift?)"
fi
_a165_run() {
    (
        ui_section()  { printf 'SECTION|%s\n' "$1"; }
        ui_kv_warn()  { printf 'WARN|%s|%s\n' "$1" "$2"; }
        LIBDIR="$1"
        eval "$_a165"
    )
}
_a165_dir=$(mktemp -d "$WORK/a165.XXXXXX")
_a165_out=$(_a165_run "$_a165_dir" || true)
if printf '%s' "$_a165_out" | grep -q '^SECTION|Security advisories$' \
    && printf '%s' "$_a165_out" | grep -q '^WARN|advisories database|missing — security checks skipped'; then
    pass "165: missing advisories lib renders the counted row, section named"
else
    fail "165: missing advisories lib must warn loudly (got: $_a165_out)"
fi
# control: lib present -> fallback silent; then through the REAL guard
# head (shipped guard + shipped sourcing + shipped section header; the
# harness appends only the closing fi) the section still renders.
mkdir -p "$_a165_dir/sh"
: > "$_a165_dir/sh/advisories.sh"
_a165_out=$(_a165_run "$_a165_dir" || true)
if [ -z "$_a165_out" ]; then
    pass "165: present advisories lib keeps the fallback silent (control)"
else
    fail "165: present advisories lib must not fire the fallback (got: $_a165_out)"
fi
_a165_head="$(sed -n '/^if \[ -f "\$LIBDIR\/sh\/advisories.sh" \]; then$/,/ui_section "Security advisories"/p' "$STATUS")"
if [ -n "$_a165_head" ]; then
    _a165_out=$(
        (
            ui_section()  { printf 'SECTION|%s\n' "$1"; }
            ui_kv_warn()  { printf 'WARN|%s|%s\n' "$1" "$2"; }
            LIBDIR="$_a165_dir"
            eval "$(printf '%s\nfi\n' "$_a165_head")"
        ) 2>&1
    ) || true
    if printf '%s' "$_a165_out" | grep -q '^SECTION|Security advisories$' \
        && ! printf '%s' "$_a165_out" | grep -q '^WARN|'; then
        pass "165: present advisories lib renders the section via the real guard (control)"
    else
        fail "165: advisories real-guard control broken (got: $_a165_out)"
    fi
else
    fail "165: advisories guard head not extractable (anchor drift?)"
fi

# b) ddev-terminal: compound guard + elif — complete block
_t165="$(sed -n '/^if \[ -n "\$DEFAULT_USER" \] && \[ -f "\$LIBDIR\/sh\/ddev-terminal.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_t165" | grep -qF 'elif [ -n "$DEFAULT_USER" ]; then' \
    && printf '%s' "$_t165" | grep -qF 'ui_kv_warn "ddev() hook" "not checked — kit file sh/ddev-terminal.sh missing (fix: sudo opk update)"'; then
    pass "165: ddev-terminal block extractable (compound guard + elif row)"
else
    fail "165: ddev-terminal block not extractable (anchor drift?)"
fi
_t165_run() {
    (
        _t165_user="$1"; _t165_lib="$2"; _t165_home="$3"
        DEFAULT_USER="$_t165_user"
        LIBDIR="$_t165_lib"
        id() { [ "${1:-}" = "-u" ] || return 1; printf '%s\n' 1000; }
        getent() {
            [ "${1:-}" = passwd ] && [ "${2:-}" = "$_t165_user" ] && [ -n "$_t165_home" ] \
                && printf 'x:x:1000:1000::%s:/bin/sh\n' "$_t165_home"
        }
        ui_kv_ok()   { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail()  { echo "DETAIL|$1"; }
        eval "$_t165"
        exit 0
    ) 2>&1
}
_t165_dir=$(mktemp -d "$WORK/t165.XXXXXX")
mkdir -p "$_t165_dir/hooked"
printf '# kit hook line: opencode-permissions-kit/sh/ddev-terminal.sh\n' > "$_t165_dir/hooked/.bashrc"
if [ -n "$_t165" ]; then
    _t165_out=$(_t165_run dev "$_t165_dir" "" || true)
    if printf '%s' "$_t165_out" | grep -q '^WARN|ddev() hook|not checked — kit file sh/ddev-terminal.sh missing'; then
        pass "165: missing ddev-terminal lib warns (counted), row not silently dropped"
    else
        fail "165: missing ddev-terminal lib must warn (got: $_t165_out)"
    fi
    _t165_out=$(_t165_run "" "$_t165_dir" "" || true)
    if [ -z "$_t165_out" ]; then
        pass "165: unstamped install stays row-free (compound guard holds)"
    else
        fail "165: unstamped install must not fire the row (got: $_t165_out)"
    fi
    # control: lib present -> the hook row renders through the real body
    mkdir -p "$_t165_dir/sh"
    : > "$_t165_dir/sh/ddev-terminal.sh"
    _t165_out=$(_t165_run dev "$_t165_dir" "$_t165_dir/hooked" || true)
    if printf '%s' "$_t165_out" | grep -qF "OK|ddev() hook|active — $_t165_dir/hooked/.bashrc" \
        && ! printf '%s' "$_t165_out" | grep -q '^WARN|'; then
        pass "165: present ddev-terminal lib renders the hook row (control)"
    else
        fail "165: ddev-terminal control broken (got: $_t165_out)"
    fi
fi

# c) ddev-migrate: compound guard + elif — complete block
_m165="$(sed -n '/^if \[ -n "\$DEFAULT_USER" \] && \[ -f "\$LIBDIR\/sh\/ddev-migrate.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_m165" | grep -qF 'ui_kv_warn "db dumps" "not checked — kit file sh/ddev-migrate.sh missing (fix: sudo opk update)"'; then
    pass "165: ddev-migrate block extractable (elif row present)"
else
    fail "165: ddev-migrate block not extractable (anchor drift?)"
fi
_m165_dir=$(mktemp -d "$WORK/m165.XXXXXX")
_m165_run() {
    (
        _m165_user="$1"; _m165_lib="$2"; _m165_conf="$3"
        set -u; set +e
        DEFAULT_USER="$_m165_user"
        LIBDIR="$_m165_lib"
        PROJECTS_CONF="$_m165_conf"
        _mig_root="$_m165_dir"; _mig_dir="$_m165_dir"
        ui_kv_ok()   { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail()  { echo "DETAIL|$1"; }
        eval "$_m165"
        exit 0
    ) 2>&1
}
if [ -n "$_m165" ]; then
    _m165_out=$(_m165_run dev "$_m165_dir" "$_m165_dir/no-projects.conf" || true)
    if printf '%s' "$_m165_out" | grep -q '^WARN|db dumps|not checked — kit file sh/ddev-migrate.sh missing'; then
        pass "165: missing ddev-migrate lib warns (counted)"
    else
        fail "165: missing ddev-migrate lib must warn (got: $_m165_out)"
    fi
    _m165_out=$(_m165_run "" "$_m165_dir" "$_m165_dir/no-projects.conf" || true)
    if [ -z "$_m165_out" ]; then
        pass "165: unstamped install stays row-free (migrate guard holds)"
    else
        fail "165: unstamped install must not fire the migrate row (got: $_m165_out)"
    fi
    # control: lib present, its gap stub answers -> the guarded body
    # renders the real INCOMPLETE row (proves the check family ran)
    mkdir -p "$_m165_dir/sh"
    printf 'ddev_migrate_gap() { echo "1 2"; }\nddev_migrate_projects() { echo p1; echo p2; }\nddev_migrate_home() { echo "$1"; }\n' > "$_m165_dir/sh/ddev-migrate.sh"
    printf '%s/root-a\n' "$_m165_dir" > "$_m165_dir/projects.conf"
    _m165_out=$(_m165_run dev "$_m165_dir" "$_m165_dir/projects.conf" || true)
    if printf '%s' "$_m165_out" | grep -q '^WARN|db dumps|INCOMPLETE — registry lists 2 project(s), only 1 dump(s) recorded$' \
        && ! printf '%s' "$_m165_out" | grep -q 'not checked'; then
        pass "165: present ddev-migrate lib renders the gap check (control)"
    else
        fail "165: ddev-migrate control broken (got: $_m165_out)"
    fi
fi

# d) ddev-hosts: readiness flag split + lib guard + elif
_h165pre="$(sed -n '/^# Readiness split (issue #165):/,/^fi$/p' "$STATUS")"
if printf '%s' "$_h165pre" | grep -qF '[ -d /mnt/c ]' \
    && printf '%s' "$_h165pre" | grep -qF '[ -f /mnt/c/Windows/System32/drivers/etc/hosts ]' \
    && printf '%s' "$_h165pre" | grep -qF '[ -n "${DEFAULT_USER:-}" ]' \
    && printf '%s' "$_h165pre" | grep -qF 'id -u "$OPENCODE_USER"'; then
    pass "165: hosts readiness block extractable, preconditions preserved verbatim"
else
    fail "165: hosts readiness block not extractable (anchor drift?)"
fi
_h165="$(sed -n '/^if \[ "\$_st_hosts_ready" = true \] && \[ -f "\$LIBDIR\/sh\/ddev-hosts.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_h165" | grep -qF 'ui_kv_warn "hosts (win)" "not checked — kit file sh/ddev-hosts.sh missing (fix: sudo opk update)"'; then
    pass "165: hosts guard block extractable (flag + lib + elif row)"
else
    fail "165: hosts guard block not extractable (anchor drift?)"
fi
_h165_dir=$(mktemp -d "$WORK/h165.XXXXXX")
_h165_run() {
    (
        _h165_ready="$1"; _h165_lib="$2"; _h165_conf="$3"
        set -u; set +e
        _st_hosts_ready="$_h165_ready"
        LIBDIR="$_h165_lib"
        PROJECTS_CONF="$_h165_conf"
        ui_kv_ok()   { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail()  { echo "DETAIL|$1"; }
        eval "$_h165"
        exit 0
    ) 2>&1
}
if [ -n "$_h165" ]; then
    _h165_out=$(_h165_run true "$_h165_dir" "$_h165_dir/no-projects.conf" || true)
    if printf '%s' "$_h165_out" | grep -q '^WARN|hosts (win)|not checked — kit file sh/ddev-hosts.sh missing'; then
        pass "165: ready host + missing ddev-hosts lib warns (counted)"
    else
        fail "165: ready host + missing ddev-hosts lib must warn (got: $_h165_out)"
    fi
    _h165_out=$(_h165_run false "$_h165_dir" "$_h165_dir/no-projects.conf" || true)
    if [ -z "$_h165_out" ]; then
        pass "165: unready host stays row-free (readiness split holds)"
    else
        fail "165: unready host must not fire the hosts row (got: $_h165_out)"
    fi
    # control: lib present, project root with .ddev, stub answers ->
    # the guarded body renders its real missing-hosts row
    mkdir -p "$_h165_dir/sh" "$_h165_dir/root/p1/.ddev"
    printf 'ddev_hosts_missing() { echo "tld.example"; }\n' > "$_h165_dir/sh/ddev-hosts.sh"
    printf '%s/root\n' "$_h165_dir" > "$_h165_dir/projects.conf"
    _h165_out=$(_h165_run true "$_h165_dir" "$_h165_dir/projects.conf" || true)
    if printf '%s' "$_h165_out" | grep -qF "WARN|hosts (win)|$_h165_dir/root/p1: missing tld.example" \
        && printf '%s' "$_h165_out" | grep -q '^DETAIL|add: opk ddev-hosts-add tld.example$' \
        && ! printf '%s' "$_h165_out" | grep -q 'not checked'; then
        pass "165: present ddev-hosts lib renders the hosts check (control)"
    else
        fail "165: ddev-hosts control broken (got: $_h165_out)"
    fi
fi

# e) verdict/exit leg (L1: observe the way production does) — the row
# must COUNT through the real ui.sh into the real summary block: full
# mode renders it and exits 2; --short mutes the row but keeps the
# count, printing only the verdict line, exit 2 (issue #158 contract).
_a165v_dir=$(mktemp -d "$WORK/a165v.XXXXXX")
_a165v_rc=0
_a165v_out=$(
    (
        set -u; set +e
        . "$UI_LIB"
        STATUS_SHORT=false
        LIBDIR="$_a165v_dir"
        eval "$_a165"
        eval "$SUMMARY_BLOCK"
    ) 2>&1
) || _a165v_rc=$?
if [ "$_a165v_rc" = "2" ] \
    && printf '%s' "$_a165v_out" | grep -q 'advisories database' \
    && printf '%s' "$_a165v_out" | grep -q '1 warning(s)'; then
    pass "165: full mode counts the row (warning verdict, exit 2)"
else
    fail "165: full mode must count the row into exit 2 (rc=$_a165v_rc out=$_a165v_out)"
fi
_a165v_rc=0
_a165v_out=$(
    (
        set -u; set +e
        . "$UI_LIB"
        UI_SILENT=1
        STATUS_SHORT=true
        LIBDIR="$_a165v_dir"
        eval "$_a165"
        eval "$SUMMARY_BLOCK"
    ) 2>&1
) || _a165v_rc=$?
if [ "$_a165v_rc" = "2" ] \
    && printf '%s' "$_a165v_out" | grep -q "1 warning(s) — run 'opk status' for the full report" \
    && ! printf '%s' "$_a165v_out" | grep -q 'advisories database'; then
    pass "165: --short mutes the row but counts it (one verdict line, exit 2)"
else
    fail "165: --short must count silently and exit 2 (rc=$_a165v_rc out=$_a165v_out)"
fi

# f) keep-as-is sites (issue #165 spec): wsl-browser-bridge degrades
# its own verdict to red by design and log.sh stays a silent best-effort
# audit line — neither may grow a row of this class (over-sweep would
# fire for legitimate optional states).
if ! grep -q 'kit file sh/wsl-browser-bridge.sh missing' "$STATUS" \
    && ! grep -q 'kit file sh/log.sh missing' "$STATUS"; then
    pass "165: wsl-browser-bridge/log.sh keep their designed degradation (no row)"
else
    fail "165: keep-as-is sites grew a missing-lib row (over-sweep)"
fi

# id-probe sentinel value (#196 a T2): `|| echo 1` must yield exactly "1"
# for an unresolvable developer — `|| true` (empty uid) keeps every branch
# pin above green while silently re-arming the uid-0 defect row for ghosts.
_st_line="$(grep '^ *_st_dev_uid=' "$STATUS" | head -1)"
if [ -n "$_st_line" ]; then
    _rc=0; _out=$(
        (
            DEFAULT_USER="hk-stval"
            export DEFAULT_USER
            id() { return 1; }
            eval "$_st_line"
            printf '%s\n' "${_st_dev_uid:-}"
        )
    ) || _rc=$?
    if [ "$_rc" -eq 0 ] && [ "$_out" = "1" ]; then
        pass "status.sh id probe: unresolvable developer resolves to sentinel 1 (executed)"
    else
        fail "status.sh id probe: unresolvable developer resolves to sentinel 1 (rc=$_rc out=$_out)"
    fi
else
    fail "status.sh id probe line extractable from status.sh"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All status tests passed.${NC}"
exit 0
