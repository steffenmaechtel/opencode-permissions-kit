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

# --- 0. dev-owned mode line (docs/design/ddev-dev-owned-projects.md) -------------
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

# --- OpenChamber verdict matrix — functional (0.0.47a F3/F4) ---------------------
# Extract the verdict block, rewrite the absolute paths (policy file, kit
# wrapper, kit bin, default-user home) to fixtures, eval it with a stubbed
# ui_kv, and drive every state — including the kit-symlink exemption (F3:
# wrapper guard semantics) and the shadow-binary-without-OpenChamber
# verdict (F4: BYPASSED only when OpenChamber is actually installed).
OCV_ROOT="$WORK/ocv"
OCV_POLICY="$OCV_ROOT/policy.json"
OCV_HOME="$OCV_ROOT/home"
OCV_WRAPPER="$OCV_ROOT/kit-wrapper"
OCV_KITBIN="$OCV_ROOT/kit-bin"
OCV_BINDIR="$OCV_ROOT/bin"
mkdir -p "$OCV_HOME" "$OCV_BINDIR"
: > "$OCV_WRAPPER"
: > "$OCV_KITBIN"
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
# ocv_run <with|without> — eval the block; "with" puts a fake openchamber
# command on PATH, "without" leaves it absent. Prints the ui_kv lines.
ocv_run() {
    (
        [ "$1" = with ] && PATH="$OCV_BINDIR:$PATH"
        ui_kv() { printf '%s %s\n' "$1" "$2"; }
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

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All status tests passed.${NC}"
exit 0
