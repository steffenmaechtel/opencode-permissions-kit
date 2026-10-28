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
pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

WORK="$(mktemp -d)"
# Widen the trap to every bare receiver of the suite (#283): W3,
# _gap_work, _c1dir, _d1dir, F25P, F25 and _f2bW lived outside $WORK
# with only inline rm on their normal paths — a set -e abort inside the
# window leaked them. The receivers anchored under $WORK (the *165
# dirs) are covered by $WORK itself. The list is a function (eight
# receivers do not fit one line); unset-safe operands skip cleanly.
# w2_run's _w2_dir is subshell-contained and cleaned inside w2_run.
_trap_cleanup() {
    rm -rf "${WORK:-}" "${W3:-}" "${_gap_work:-}" "${_c1dir:-}" \
        "${_d1dir:-}" "${F25P:-}" "${F25:-}" "${_f2bW:-}"
}
trap _trap_cleanup EXIT INT TERM

# --- 0. dev-owned mode line (internal/records/ddev-dev-owned-projects.md) -------------
if grep -q 'ui_kv "ddev settings"' "$STATUS" &&
    grep -q 'dev-owned — kit writes disable_settings_management' "$STATUS" &&
    grep -qF 'DDEV_DEV_OWNED=' "$STATUS"; then
    pass "status.sh reports the ddev settings mode (stamp-driven)"
else
    fail "status.sh reports the ddev settings mode (stamp-driven)"
fi

# --- 0b. git row (issue #118): the Core section shows the host git against
# the soft tested floor, from the shared helper. Missing-lib behavior since
# #199 a W3: a missing or outdated helper renders the counted warn row at
# the call site (section g2 pins it); the old fail-soft contract
# ("a missing helper just drops the row") is retired.
if grep -q 'git_status_row' "$STATUS" &&
    grep -q 'sh/git-check.sh' "$STATUS" &&
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

# Live-scan helpers (issue #210): extracted once here — the #165 control
# harnesses below eval the real scan sites (which call _st_ddev_scan
# since #210) and the issue-210 pins exercise both helpers directly.
SCAN_HELPERS="$(sed -n '/^_st_progress_tee()/,/^}/p;/^_st_ddev_scan()/,/^}/p' "$STATUS")"

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
if printf '%s' "$out" | grep -q "unknown ('kubernetes')" &&
    ! printf '%s' "$out" | grep -q "parameter not set"; then
    pass "unknown backend reports unknown('kubernetes') without crashing (set -u)"
else
    fail "unknown backend reports unknown('kubernetes') without crashing (out=$out)"
fi

# b) empty backend: reports unknown('none')
out=$(run_case "" "" "" || true)
if printf '%s' "$out" | grep -q "unknown ('none')" &&
    ! printf '%s' "$out" | grep -q "parameter not set"; then
    pass "empty backend reports unknown('none') without crashing (set -u)"
else
    fail "empty backend reports unknown('none') without crashing (out=$out)"
fi

# c) docker-rootless with a configured socket that does not exist: NOT
#    reachable, and the probe must not prompt (sudo -n). A prompting sudo
#    shim fails the test. NOTE: the shim must actually be IN the PATH of
#    run_case's subshell (see run_case) — a `PATH=... cmd; f` prefix would
#    apply the assignment only to `cmd`, never to f.
cat >"$WORK/sudo" <<'EOF'
#!/bin/sh
# fail on any interactive sudo attempt: -n must already be in the args
case " $* " in
    *" -n "*) exit 1 ;;
    *) echo "PROMPT-ATTEMPT" >&2; exit 42 ;;
esac
EOF
chmod +x "$WORK/sudo"
out=$(run_case "docker-rootless" "unix:///run/user/99999/docker.sock" "" || true)
if printf '%s' "$out" | grep -q "NOT reachable" &&
    ! printf '%s' "$out" | grep -qE 'PROMPT-ATTEMPT|parameter not set'; then
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
chmod 700 "$WORK/locked-runtime" # 700 of a nonexistent other user is untestable; 000 works for everyone
chmod 000 "$WORK/locked-runtime"
out=$(run_case "docker-rootless" "unix://$WORK/locked-runtime/docker.sock" "" || true)
if printf '%s' "$out" | grep -q "unknown — needs root to check" &&
    ! printf '%s' "$out" | grep -q "NOT reachable" &&
    ! printf '%s' "$out" | grep -qE 'PROMPT-ATTEMPT|parameter not set'; then
    pass "docker-rootless: socket in inaccessible runtime dir reports unknown (needs root)"
else
    fail "docker-rootless: socket in inaccessible runtime dir reports unknown (needs root) (out=$out)"
fi
chmod 755 "$WORK/locked-runtime" 2>/dev/null || true

# --- 1b. root-equivalent access audit (issue #37) --------------------------------
# The audit ships two pure helpers (stat math only); they are extracted and
# unit-tested directly, plus static assertions on the section wiring.
if grep -q 'ui_section "Root-equivalent access' "$STATUS" &&
    grep -q 'ROOT_EQUIV_SOCKS' "$STATUS" &&
    grep -q '/mnt/wsl' "$STATUS"; then
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
    status_sock_agent_reachable "$_sock" "" && echo SOCK-WORLDW-OK
    chmod 660 "$_sock"
    chgrp "$_grp" "$_sock"
    status_sock_agent_reachable "$_sock" "$_grp" && echo SOCK-GROUPW-OK
    status_sock_agent_reachable "$_sock" "othergrp" || echo SOCK-GROUPW-DENY-OK
    chmod 660 "$_sock"
    chgrp "$_grp" "$_sock"
    status_sock_agent_reachable "$_sock" "" || echo SOCK-NOOTHER-OK
    status_sock_agent_reachable "$WORK/absent.sock" "" || echo SOCK-ABSENT-OK
) >"$WORK/audit.out" 2>&1
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
[ -n "$AUDIT_SECTION" ] || {
    echo "  ${RED}audit section not extractable${NC}"
    exit 1
}
_sock2="$WORK/fake-agent-sock"
python3 - "$_sock2" <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
PYEOF
audit_out=$(
    (
        set -u
        set +e
        . "$UI_LIB"
        OPENCODE_USER="root"            # exists everywhere; id -nG works
        ROOT_EQUIV_SOCKS="$_sock2"      # the fake socket, world-writable
        chmod 666 "$_sock2" 2>/dev/null # bind honors umask: force 666
        eval "$AUDIT_SECTION"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$audit_out" | grep -q "Root-equivalent access" &&
    printf '%s' "$audit_out" | grep -q "AGENT-REACHABLE" &&
    ! printf '%s' "$audit_out" | grep -q "parameter not set"; then
    pass "audit section body runs (fake world-writable socket flagged red)"
else
    fail "audit section body runs (out=$(printf '%s' "$audit_out" | head -3))"
fi
# The same socket at 660 with a group the agent user is NOT in must NOT be
# flagged reachable (perm-math negative inside the section body).
audit_out2=$(
    (
        set -u
        set +e
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
printf '#!/bin/sh\necho "ddev version v1.25.4"\n' >"$WORK/ddev"
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
if printf '%s' "$probe_out" | grep -q "1.25.4" &&
    ! printf '%s' "$probe_out" | grep -q "1.25.3"; then
    pass "ddev version: live probe wins over the install-time stamp (issue #56)"
else
    fail "ddev version: live probe wins over the stamp (out=$probe_out)"
fi

# the < 1.25 gate must judge the LIVE version too
printf '#!/bin/sh\necho "ddev version v1.24.2"\n' >"$WORK/ddev"
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
printf '#!/bin/sh\nexit 1\n' >"$WORK/fakekit/bin/ddev-as-opencode"
chmod +x "$WORK/fakekit/bin/ddev-as-opencode"
printf '#!/bin/sh\necho "ddev version v1.26.0"\n' >"$WORK/sudo"
chmod +x "$WORK/sudo"
printf '#!/bin/sh\nexit 1\n' >"$WORK/quiet/ddev"
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
if printf '%s' "$probe_helper" | grep -q "1.26.0" &&
    ! printf '%s' "$probe_helper" | grep -q "1.25.3"; then
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
        set -u
        set +e
        . "$UI_LIB"
        KIT_CHANNEL="stable"
        eval "$(sed -n '/^# Channel stamp (issue #38)/,/^fi$/p' "$STATUS")"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$channel_out" | grep -q "stable" &&
    ! printf '%s' "$channel_out" | grep -q "unstamped"; then
    pass "channel: stamped value shown"
else
    fail "channel: stamped value shown (out=$channel_out)"
fi
channel_out=$(
    (
        set -u
        set +e
        . "$UI_LIB"
        unset KIT_CHANNEL
        eval "$(sed -n '/^# Channel stamp (issue #38)/,/^fi$/p' "$STATUS")"
        exit 0
    ) 2>&1
) || true
if printf '%s' "$channel_out" | grep -q "unstamped" &&
    ! printf '%s' "$channel_out" | grep -q "parameter not set"; then
    pass "channel: unstamped install reports master (unstamped) without crashing"
else
    fail "channel: unstamped install reports master (unstamped) without crashing (out=$channel_out)"
fi

# --- 1f. management footer uses the opk shorthand (issue #62) ---------------------
# The footer is the hint users copy-paste; it must print the short CLI
# commands, not the library paths behind them.
if grep -qF 'ui_detail "sudo opk config' "$STATUS" &&
    grep -qF 'ui_detail "sudo opk update' "$STATUS" &&
    grep -qF 'ui_detail "opk uninstall' "$STATUS" &&
    ! grep -q 'management/config\.sh.*change settings' "$STATUS" &&
    ! grep -q 'management/update\.sh.*re-deploy' "$STATUS" &&
    ! grep -q 'management/uninstall\.sh.*remove the kit' "$STATUS"; then
    pass "management footer prints opk shorthand, not library paths (issue #62)"
else
    fail "management footer prints opk shorthand, not library paths (issue #62)"
fi

# --- 2. not-installed state: exit 0 + install hint ------------------------------

if ! id opencode >/dev/null 2>&1; then
    out=$(sh "$STATUS" 2>&1)
    rc=$?
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
sed -n '/^_st_pc=/,/^ui_section "Projects/p' "$STATUS" >"$WORK/pc-block.sh"
if [ -s "$WORK/pc-block.sh" ] && grep -q 'ui_section "Projects' "$WORK/pc-block.sh"; then
    pass "the projects-count block is extractable from status.sh"
else
    fail "the projects-count block is extractable from status.sh"
fi
: >"$WORK/empty-projects.conf"
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
printf '/var/tmp/one\n/var/tmp/two\n' >"$WORK/two-projects.conf"
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
    printf '/var/tmp/root-one\n/var/tmp/my projects\n' >"$_gap_work/projects.conf"
    _gap_args=""
    _gap_rc=0
    (
        PROJECTS_CONF="$_gap_work/projects.conf"
        _mig_root=""
        _mig_dir=""
        # the stubs write to files: _st_dbdump_gap runs inside the pipe's
        # subshell, variables would not propagate out
        ddev_migrate_gap() {
            shift
            printf '%s\n' "$#" >"$_gap_work/argc"
            printf '%s\n' "$*" >"$_gap_work/args"
            return 1
        }
        ddev_migrate_projects() { printf ''; }
        ddev_migrate_home() { printf '/home/x'; }
        ui_kv_warn() { :; }
        ui_detail() { :; }
        eval "$_gap_fn"
        grep -v '^[[:space:]]*$' "$PROJECTS_CONF" | _st_dbdump_gap devuser || true
    ) >"$_gap_work/out" 2>/dev/null || _gap_rc=$?
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
if printf '%s\n' "$_sra_pat" | grep -qF 'may run the following commands' &&
    printf '%s\n' "$_sra_pat" | grep -qF '\([^)]+\)'; then
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
if grep -q 'secured via policy pin' "$STATUS" &&
    grep -q 'BYPASSED' "$STATUS" &&
    grep -q "sudo opk openchamber-secure" "$STATUS"; then
    pass "status shows the OpenChamber state (secured/bypassed/advice)"
else
    fail "status lost the OpenChamber state line"
fi
# detection reuses the wrapper's semantics: a pin on the kit wrapper itself
# is not a bypass, an empty pin counts as unset
if grep -q '_oc_secured=true' "$STATUS" &&
    grep -qF '[ "$_oc_pin" = "/usr/local/bin/opencode" ]' "$STATUS"; then
    pass "status pin detection matches the wrapper semantics"
else
    fail "status pin detection diverges from the wrapper"
fi
# home resolution via getent with /home/<user> fallback (0.0.47b W2, the
# 0.0.43a F12 class): relocated homes must not blank the verdicts.
# Literals updated for #211 a F9: the default chain deepened to
# ${USER:-} so set -u survives both-unset (cron env) — same getent
# resolution, same fallback shape, one level deeper.
if grep -q 'getent passwd "${DEFAULT_USER:-${USER:-}}"' "$STATUS" &&
    grep -qF '_oc_home="${_oc_home:-/home/${DEFAULT_USER:-${USER:-}}}"' "$STATUS"; then
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
OCV_HOME_SRC="$(awk '/^_oc_policy=/{_ocv=1} _ocv{ if ($0 ~ /^f="\/home/) exit; print }' "$STATUS" |
    grep '^_oc_home=' || true)"
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
: >"$OCV_WRAPPER"
: >"$OCV_KITBIN"
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
OCV_BLOCK="$(awk '/^_oc_policy=/{_ocv=1} _ocv{ if ($0 ~ /^f="\/home/) exit; print }' "$STATUS" |
    sed -e "s|/etc/openchamber/policy.json|$OCV_POLICY|g" \
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
echo fake >"$OCV_HOME/.opencode/bin/opencode"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'not installed' &&
    ! printf '%s' "$out" | grep -q 'BYPASSED'; then
    pass "verdict matrix: shadow binary without OpenChamber is not BYPASSED (0.0.47a F4)"
else
    fail "verdict matrix: shadow binary without OpenChamber is not BYPASSED (0.0.47a F4) (got: $out)"
fi

# 4. settings pin (config dir present) -> BYPASSED
mkdir -p "$OCV_HOME/.config/openchamber"
printf '{ "opencodeBinary": "/tmp/evil-opencode" }\n' \
    >"$OCV_HOME/.config/openchamber/settings.json"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'BYPASSED'; then
    pass "verdict matrix: settings pin without policy -> BYPASSED"
else
    fail "verdict matrix: settings pin without policy -> BYPASSED (got: $out)"
fi

# 5. policy pins the kit bin -> secured, leftovers noted as inert
printf '{ "opencodeBinary": "%s" }\n' "$OCV_KITBIN" >"$OCV_POLICY"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'secured via policy pin' &&
    printf '%s' "$out" | grep -q 'leftover bypass files present'; then
    pass "verdict matrix: policy secures, leftovers called inert"
else
    fail "verdict matrix: policy secures, leftovers called inert (got: $out)"
fi

# 6. F3 under policy: only the kit symlink remains (plain binary and
#    settings pin removed) -> secured without a leftover note
rm -f "${OCV_HOME:?}/.opencode/bin/opencode" "${OCV_HOME:?}/.config/openchamber/settings.json"
ln -s "$OCV_WRAPPER" "$OCV_HOME/.opencode/bin/opencode"
out="$(ocv_run without)"
if printf '%s' "$out" | grep -q 'secured via policy pin' &&
    ! printf '%s' "$out" | grep -q 'leftover'; then
    pass "verdict matrix: kit symlink under policy is not a leftover (0.0.47a F3)"
else
    fail "verdict matrix: kit symlink under policy is not a leftover (0.0.47a F3) (got: $out)"
fi

# 7. advice state via the command marker (no files, fake openchamber on PATH)
rm -f "${OCV_HOME:?}/.opencode/bin/opencode" "${OCV_POLICY:?}" \
    "${OCV_HOME:?}/.config/openchamber/settings.json"
printf '#!/bin/sh\n' >"$OCV_BINDIR/openchamber"
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
if grep -qF 'ui_kv_ok ".git/config" "protected (soft-only — agent tools blocked)"' "$STATUS" &&
    grep -qF 'ui_kv ".git/config" "access allowed (agent tools may edit git config)"' "$STATUS" &&
    ! grep -qF '"ON (soft-only' "$STATUS" &&
    ! grep -qF 'ui_kv ".git/config" "OFF"' "$STATUS"; then
    pass ".git/config row reads protected / access allowed (issue #158)"
else
    fail ".git/config row wording regressed to ON/OFF"
fi

# Sweep invariant: status.sh carries NO raw color-argument ui_kv rows
# anymore — every verdict row goes through the semantic helpers, so the
# summary cannot miss one (class sweep of the 62 sites, 0.0.46a F2 style).
if ! grep -qE '"\$UI_(GREEN|YELLOW|RED)"' "$STATUS" &&
    grep -q 'ui_kv_ok ' "$STATUS" && grep -q 'ui_kv_bad ' "$STATUS"; then
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
if grep -qF 'done <"$_st_share_list"' "$STATUS" &&
    grep -qF 'done <"$_st_hosts_list"' "$STATUS" &&
    grep -qF '_st_dbdump_gap "$DEFAULT_USER" <"$_st_gap_roots"' "$STATUS"; then
    pass "scan loops run in the main shell (redirect, not pipe)"
else
    fail "a scan loop prints its findings from a pipe subshell again"
fi

# One-line mode must be exactly one line: no raw echo/printf leaks past
# UI_SILENT (the hosts-scan add-lines and the leak-scan hit list are the
# two raw-print sites; both are guarded/converted).
if grep -qF 'ui_detail "add: opk ddev-hosts-add' "$STATUS" &&
    ! grep -qF 'echo "     add' "$STATUS"; then
    pass "--short: raw-print sites converted/guarded (one-line discipline)"
else
    fail "a raw print site can leak past UI_SILENT"
fi

# Checkout-first lib resolution (0.0.46a F4 pattern): a checkout run must
# source ITS OWN ui.sh/git-check.sh — a deployed pre-#158 copy would drop
# every ui_kv_ok/ui_kv_bad row (command not found) and the verdict.
if grep -qF 'UI_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/ui.sh"' "$STATUS" &&
    grep -qF 'GIT_CHECK_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/git-check.sh"' "$STATUS"; then
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
                set -u
                set +e
                . "$UI_LIB"
                UI_ROWS_BAD=$1
                UI_ROWS_WARN=$2
                UI_ROWS_OK=$3
                STATUS_SHORT=$4
                if [ "$STATUS_SHORT" = true ]; then UI_SILENT=1; else UI_SILENT=0; fi
                ui_section() { printf 'SECTION:%s\n' "$1"; }
                eval "$SUMMARY_BLOCK"
            ) 2>&1
        ) || _rs_rc=$?
        printf '%s\nrc=%s\n' "$_rs_out" "$_rs_rc"
    }
    _sum=$(run_summary 1 2 5 false)
    if printf '%s' "$_sum" | grep -q '1 alert(s), 2 warning(s)' &&
        printf '%s' "$_sum" | grep -q 'see the sections above' &&
        printf '%s' "$_sum" | grep -q 'SECTION:Summary' &&
        printf '%s' "$_sum" | grep -q 'rc=1'; then
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
    if printf '%s' "$_sum" | grep -q '1 warning(s)' &&
        printf '%s' "$_sum" | grep -q 'rc=2'; then
        pass "verdict: warnings only, exit 2"
    else
        fail "verdict warning case broken (got: $_sum)"
    fi
    _sum=$(run_summary 0 0 7 false)
    if printf '%s' "$_sum" | grep -q 'All green' &&
        printf '%s' "$_sum" | grep -q '7 checks passed' &&
        printf '%s' "$_sum" | grep -q 'rc=0'; then
        pass "verdict: all green with the pass count, exit 0"
    else
        fail "verdict green case broken (got: $_sum)"
    fi
    _sum=$(run_summary 1 2 5 true)
    if printf '%s' "$_sum" | grep -q "run 'opk status' for the full report" &&
        ! printf '%s' "$_sum" | grep -q 'SECTION:Summary' &&
        printf '%s' "$_sum" | grep -q 'rc=1'; then
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
    if [ "$ni_rc" = "1" ] && printf '%s' "$ni_out" | grep -q 'not installed — hardening NOT active' &&
        [ "$(printf '%s\n' "$ni_out" | grep -c .)" = "1" ]; then
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
            # the subshell trap owns _w2_dir on every path: abort and
            # signal included (#283; the pre-wave end-of-body cleanup ran
            # on the normal path only). command rm because rm() is
            # stubbed below at fire time.
            trap 'command rm -rf "${_w2_dir:-}"' EXIT INT TERM
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
        # no inline tail rm: the subshell trap above owns _w2_dir on
        # every path now (normal, abort, signal — #287 a Q6 removed the
        # redundant double cleanup)
    )
}

if [ -n "$W2_BLOCK_SHARE" ]; then
    _w2out=$(w2_run "$W2_BLOCK_SHARE" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|ddev share|scan skipped for /var/www/w2-proj' &&
        ! printf '%s' "$_w2out" | grep -q 'FIND-CALLED' &&
        ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 share scan: mktemp failure warns loudly, no find, no rm"
    else
        fail "W2 share scan: mktemp failure must warn and skip (got: $_w2out)"
    fi
    _w2out=$(w2_run "$W2_BLOCK_SHARE" true || true)
    if ! printf '%s' "$_w2out" | grep -q 'scan skipped' &&
        printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 share scan: working mktemp flows find→report→cleanup (control)"
    else
        fail "W2 share scan control broken (got: $_w2out)"
    fi
fi
if [ -n "$W2_BLOCK_HOSTS" ]; then
    _w2out=$(w2_run "$W2_BLOCK_HOSTS" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|hosts (win)|scan skipped for /var/www/w2-proj' &&
        ! printf '%s' "$_w2out" | grep -q 'FIND-CALLED' &&
        ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 hosts scan: mktemp failure warns loudly, no find, no rm"
    else
        fail "W2 hosts scan: mktemp failure must warn and skip (got: $_w2out)"
    fi
fi
if [ -n "$W2_BLOCK_GAP" ]; then
    _w2out=$(w2_run "$W2_BLOCK_GAP" false || true)
    if printf '%s' "$_w2out" | grep -q '^WARN|db dumps|gap scan skipped' &&
        ! printf '%s' "$_w2out" | grep -q 'GAP-CALLED' &&
        ! printf '%s' "$_w2out" | grep -q 'RM-CALLED'; then
        pass "W2 dbdump gap: mktemp failure warns loudly, scan skipped"
    else
        fail "W2 dbdump gap: mktemp failure must warn and skip (got: $_w2out)"
    fi
fi
# class sweep (L2, widened per issue #168): no mktemp whose failure falls
# back to a FIXED PATH survives in any shipped script — pattern-based, not
# var-name-based (the pre-#168 sweep knew only the three 0.0.48b W2 names
# in status.sh; a fresh name anywhere else sailed past it). Shapes covered
# (single-line, the historical W2 form):
#   (a) assignment fallback: X=$(mktemp ...) || X=/dev/null — any
#       /dev/null, /tmp, /var/tmp literal, quoted or not ([^/]? eats one
#       leading quote); an optional prefix (sudo mktemp) is allowed
#   (b) fallback inside the substitution: X=$(mktemp ... || echo /dev/null),
#       with 2>/dev/null muffling before the || included
# Sanctioned fallbacks do not match (|| return 1 / || exit 1, || X="",
# warn-only || { ... } braces). A brace that ASSIGNS a fixed path
# (X=$(mktemp) || { X=/dev/null; }) DOES match shape (a) — by design:
# that is the dangerous form (#202 a W2).
# Deliberately NOT swept (scope decision, #168): a bare 2>/dev/null
# swallowing into a fixed file with no || fallback (stderr redirects are
# ubiquitous in sanctioned code; a line-blind grep false-positives) and
# multi-line fallbacks (grep is line-scoped). Class history (0.0.48b W2):
# the /dev/null fallback silently killed the tally and its cleanup rm -f'd
# the device node when root ran it.
W2_FIXPATH_A='\$\(([^)|]*[[:space:]])?mktemp[^)]*\)[^|]*\|\|[^|]*=[[:space:]]*[^/]?/(dev/null|tmp|var/tmp)'
W2_FIXPATH_B='\$\(([^)|]*[[:space:]])?mktemp[^|)]*\|\|[^)]*echo[[:space:]]+[^/]?/(dev/null|tmp|var/tmp)'
_w2_fall_hits="$(grep -rnE "$W2_FIXPATH_A|$W2_FIXPATH_B" "$SCRIPT_DIR/../../files" || true)"
if [ -z "$_w2_fall_hits" ]; then
    pass "W2 class sweep: no mktemp fixed-path fallback in any shipped script (#168)"
else
    fail "W2 class sweep: mktemp fixed-path fallback survived (got: $_w2_fall_hits)"
fi
# canary (#202 a W1, extended #202 b W1, #202 c W1): the sweep above
# greps real files/ and finds nothing by design — its FAIL branch never
# runs in-suite, so a broken regex would stay green while blind. Pin
# every discrimination claim the comment above makes: six offending
# lines (assignment, muffled in-substitution, brace-assign fixed path,
# quoted /tmp literal, sudo-prefixed /var/tmp, un-muffled echo /tmp)
# must match; every must-not-match claim (return/exit, X="", warn-only
# brace, bare 2>/dev/null without ||, the three-line multi-line
# fallback) must not — SAME expression (test-kit-files §4 class: a
# guard that cannot fail is decoration).
_w2_can_file="$WORK/w2-canary.sh"
{
    echo '_w2_can_a=$(mktemp) || _w2_can_a=/dev/null'
    echo '_w2_can_b=$(mktemp 2>/dev/null || echo /dev/null)'
    echo '_w2_can_c=$(mktemp) || { _w2_can_c=/dev/null; }'
    echo '_w2_can_ok=$(mktemp) || return 1'
    echo '_w2_can_ok2=$(mktemp) || exit 1'
    echo '_w2_can_ok3=$(mktemp) || _w2_can_ok3=""'
    echo '_w2_can_ok4=$(mktemp) || { echo warn >&2; }'
    echo '_w2_can_d=$(mktemp) || _w2_can_d="/tmp"'
    echo '_w2_can_e=$(sudo mktemp) || _w2_can_e=/var/tmp'
    echo '_w2_can_ok5=$(mktemp 2>/dev/null)'
    echo '_w2_can_f=$(mktemp || echo /tmp)'
    echo '_w2_can_g=$(mktemp) || {'
    echo '    _w2_can_g=/dev/null'
    echo '}'
} >"$_w2_can_file"
_w2_can_hits="$(grep -nE "$W2_FIXPATH_A|$W2_FIXPATH_B" "$_w2_can_file" || true)"
if printf '%s' "$_w2_can_hits" | grep -q '^1:' &&
    printf '%s' "$_w2_can_hits" | grep -q '^2:' &&
    printf '%s' "$_w2_can_hits" | grep -q '^3:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^4:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^5:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^6:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^7:' &&
    printf '%s' "$_w2_can_hits" | grep -q '^8:' &&
    printf '%s' "$_w2_can_hits" | grep -q '^9:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^10:' &&
    printf '%s' "$_w2_can_hits" | grep -q '^11:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^12:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^13:' &&
    ! printf '%s' "$_w2_can_hits" | grep -q '^14:'; then
    pass "W2 sweep canary: catches all six offending lines (incl. quoted, prefixed, un-muffled), spares all eight non-match lines"
else
    fail "W2 sweep canary: pattern is blind or over-broad (got: $_w2_can_hits)"
fi

# --- 0.0.48b W3: privilege-unknown and optional rows never count -------------
# The verdict counts findings, not unknowns: "unknown — needs root" and
# "missing (optional …" rows are plain ui_kv (uncounted) — otherwise every
# unprivileged or HTTPS-less host would be permanently non-green and the
# cron alert worthless. Pins the five converted rows incl. both socket
# twins, plus the negative sweep (no unknown/optional row via ui_kv_warn).
# Comment-strip rider (#261, the #244 g W1 class) on the socket-twin
# count: commented-out rows stop counting; full-line comments only
# (#244 h W6 residual).
if grep -qF 'ui_kv "opencode version" "unknown — probe failed' "$STATUS" &&
    [ "$(sed 's/^[[:space:]]*#.*$//' "$STATUS" |
        grep -cF 'ui_kv "socket" "unknown — needs root to check' || true)" = "2" ] &&
    grep -qF 'ui_kv "mkcert CA" "unknown — needs root to check' "$STATUS" &&
    grep -qF 'ui_kv "mkcert CA" "missing (optional' "$STATUS" &&
    ! grep -qE 'ui_kv_warn "[^"]*" "unknown — (needs root|probe failed)' "$STATUS" &&
    ! grep -qF 'ui_kv_warn "mkcert CA" "missing (optional' "$STATUS"; then
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
if printf '%s' "$W48C_BLOCK_ADV" | grep -q 'ui_kv_warn "opencode binary"' &&
    printf '%s' "$W48C_BLOCK_ADV" | grep -q 'elif command -v sudo'; then
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
        timeout() {
            shift 1
            "$@"
        }
        sudo() {
            shift 3
            "$@"
        }
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
    if printf '%s' "$_c1out" | grep -q '^WARN|opencode binary|missing or not executable' &&
        printf '%s' "$_c1out" | grep -q '^ADV_VER=unset$'; then
        pass "C1: missing binary warns (counted), probe never runs"
    else
        fail "C1: missing binary must warn loudly (got: $_c1out)"
    fi
    # control: executable fake binary -> probe path runs, no warn
    mkdir -p "$_c1dir/bin"
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' >"$_c1dir/bin/opencode"
    chmod +x "$_c1dir/bin/opencode"
    _c1out=$(w48c_run "$_c1dir" "$W48C_BLOCK_ADV" || true)
    if ! printf '%s' "$_c1out" | grep -q '^WARN|' &&
        printf '%s' "$_c1out" | grep -q '^ADV_VER=9.9.9$'; then
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
# Issue #201: the capture block is a third extracted region — the
# harness below evals gate + capture + render; a construct placed
# outside all three would be untested here and drift silently.
W201_BLOCK_CAPTURE="$(sed -n '/^    ADV_DIRECT_OUT=""$/,/^    fi$/p' "$STATUS")"
if printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'elif [ -n "${ADV_DIRECT_RC:-}" ]' &&
    printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'ui_kv "opencode version" "unknown — probe failed'; then
    pass "D1 render block extractable (elif-gated unknown row)"
else
    fail "D1 render block not extractable (anchor drift?)"
fi
# Issue #163/#201: the classifier now lives in the capture block and
# feeds ADV_VER/ADV_DIRECT_RC into the render — pin both halves.
if [ -n "$W201_BLOCK_CAPTURE" ] &&
    printf '%s' "$W201_BLOCK_CAPTURE" | grep -qF 'ADV_DIRECT_RC=$?' &&
    printf '%s' "$W201_BLOCK_CAPTURE" | grep -qF 'grep -m1 -oE' &&
    printf '%s' "$W48D_BLOCK_RENDER" | grep -qF 'present but broken'; then
    pass "#201/#163: capture block extractable (rc + version extract), render keeps the broken arm"
else
    fail "#201/#163: capture block not extractable (anchor drift?)"
fi
# Issue #201: the dead-end advice lives ONLY in the #166 cell now —
# exactly one literal (a second occurrence would mean a healthy-direct
# or unparsable cell advising sudo again).
if [ "$(sed 's/^[[:space:]]*#.*$//' "$STATUS" | grep -cF 'unknown — probe failed (run: sudo opk status)' ||
    true)" = "1" ]; then
    pass "#201: the sudo-opk-status advice is #166-cell only (one literal)"
else
    fail "#201: the sudo-advice literal count drifted (expected exactly 1)"
fi
# Issue #201 claim audit: the direct capture stays timeout-bounded
# (issue #80) like the sudo probe it complements.
if printf '%s' "$W201_BLOCK_CAPTURE" | grep -qF 'timeout 10 "$LIBDIR/bin/opencode"'; then
    pass "#201: direct capture probe is timeout-bounded (issue #80)"
else
    fail "#201: direct capture probe lost its timeout envelope"
fi
# Issue #201 claim audit: the direct capture strengthens ADV_VER consumers
# too — the browser-bridge verdict keys on ADV_VER (status.sh's WSL
# section). Behavioral pin: the extracted guard block with the REAL
# advisories.sh comparator (not a stub) discriminates every shape the
# verdict names — both eq boundaries (1.18.33, 2.0.18) asserted on
# their own arm, above (1.19.0, 2.0.19) and below (1.18.32, 2.0.17)
# per arm, and unknown — so neither the comparator direction nor a
# boundary constant can drift silently (#209 a W1, b W1).
ADV_SRC="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/advisories.sh"
W201_BLOCK_BRIDGE="$(sed -n '/^        _st_bridge_unneeded=0$/,/^        fi$/p' "$STATUS")"
if [ -f "$ADV_SRC" ] && [ -n "$W201_BLOCK_BRIDGE" ]; then
    w201_bridge() {
        (
            # shellcheck disable=SC1090
            . "$ADV_SRC"
            ADV_VER="$1"
            eval "$W201_BLOCK_BRIDGE"
            printf '%s\n' "$_st_bridge_unneeded"
        )
    }
    if [ "$(w201_bridge 1.19.0)" = 1 ] && [ "$(w201_bridge 1.18.33)" = 1 ] &&
        [ "$(w201_bridge 2.0.19)" = 1 ] && [ "$(w201_bridge 2.0.18)" = 1 ] &&
        [ "$(w201_bridge 2.0.17)" = 0 ] && [ "$(w201_bridge 1.18.32)" = 0 ] &&
        [ "$(w201_bridge "")" = 0 ]; then
        pass "#201: bridge verdict keys on ADV_VER (1.18.33+/2.0.18+ unneeded, older/unknown keep the carrier)"
    else
        fail "#201: bridge ADV_VER keying drifted (extract: $W201_BLOCK_BRIDGE)"
    fi
    # #209 b W2: the comparator-availability guard is load-bearing, not
    # decorative — without it, a broken kit (advisories.sh missing) plus
    # a successful version probe renders a false "not needed" row (an
    # empty command substitution satisfies `!= lt`). Pin: the same
    # block, eval'd with NO comparator available — function unset, PATH
    # emptied so a host binary of the same name cannot satisfy the
    # guard either (0.0.46a F2 class) — keeps the carrier verdict on
    # both arms and unknown.
    w201_bridge_nocmp() {
        (
            unset -f advisories_version_cmp
            PATH=
            ADV_VER="$1"
            eval "$W201_BLOCK_BRIDGE"
            printf '%s\n' "$_st_bridge_unneeded"
        )
    }
    if [ "$(w201_bridge_nocmp 1.19.0)" = 0 ] && [ "$(w201_bridge_nocmp 2.0.18)" = 0 ] &&
        [ "$(w201_bridge_nocmp "")" = 0 ]; then
        pass "#201: missing comparator keeps the carrier (guard fails safe)"
    else
        fail "#201: bridge guard lost its fail-safe (extract: $W201_BLOCK_BRIDGE)"
    fi
else
    fail "#201: bridge guard block not extractable (anchor drift?)"
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
        timeout() {
            shift 1
            "$@"
        }
        # "refuse-sudo": mirror sudo -n's password refusal (rc 1, empty
        # output) — the W3 privilege shape. Otherwise the working-sudo
        # stub (strip the -n -u <user> prefix, exec as-is).
        if [ "$2" = "refuse-sudo" ]; then
            sudo() { return 1; }
        else
            sudo() {
                shift 3
                "$@"
            }
        fi
        LIBDIR="$1"
        OPENCODE_USER=opencode
        VERSION=0.0.0
        ADV_VER=""
        eval "$W48C_BLOCK_ADV"
        eval "${W201_BLOCK_CAPTURE:-}"
        eval "$W48D_BLOCK_RENDER"
    )
}
if [ -n "$W48C_BLOCK_ADV" ] && [ -n "$W48D_BLOCK_RENDER" ] && [ -n "$W201_BLOCK_CAPTURE" ]; then
    _d1dir=$(mktemp -d)
    # missing binary: warn row, NO unknown row (the D1 property); the
    # advice must name the working repair — upgrade-opencode, not plain
    # update (0.0.49a W1: a plain update never touches the binary).
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|' &&
        printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|.*fix: sudo opk upgrade-opencode' &&
        ! printf '%s' "$_d1out" | grep -q 'fix: sudo opk update)' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1: missing binary warns, naming the working repair (0.0.49a W1)"
    else
        fail "D1: missing binary warn must name upgrade-opencode, not plain update (got: $_d1out)"
    fi
    # working binary: probe renders the OK row, no unknown row
    mkdir -p "$_d1dir/bin"
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' >"$_d1dir/bin/opencode"
    chmod +x "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^OK|opencode 9.9.9|' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1: working binary renders the OK row, no unknown row"
    else
        fail "D1: working binary must render via ADV_VER (got: $_d1out)"
    fi
    # present but BROKEN binary (issue #163): the recorded reachability
    # was a cp killed mid-write — a truncated binary with intact mode
    # bits. The direct probe classifies it (rc != 0, caller-independent)
    # into a COUNTED warn; the "sudo opk status" advice must not print
    # because no privilege resolves this shape.
    printf '\177ELFbroken-fixture' >"$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|present but broken' &&
        printf '%s' "$_d1out" | grep -q 'fix: sudo opk upgrade-opencode' &&
        ! printf '%s' "$_d1out" | grep -q 'fix: sudo opk update)' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "D1/#163: corrupt binary counts a warn with the working repair (0.0.49a W1)"
    else
        fail "D1/#163: corrupt binary must warn (counted) naming upgrade-opencode, not plain update (got: $_d1out)"
    fi
    # issue #201 (was the 0.0.48b W3 shape under #163): sudo refuses,
    # the binary itself is healthy — the capture now USES the stdout
    # #163 used to discard: the caller gets the real advisory verdict
    # at their own privilege, never the dead-end "sudo opk status"
    # advice they cannot act on. The 007 pins below keep the genuinely
    # privilege-bound shapes uncounted (W3 survives there).
    printf '#!/bin/sh\necho "opencode 9.9.9"\n' >"$_d1dir/bin/opencode"
    chmod +x "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" refuse-sudo || true)
    if printf '%s' "$_d1out" | grep -q '^OK|opencode 9.9.9|' &&
        ! printf '%s' "$_d1out" | grep -q '^WARN|' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed' &&
        ! printf '%s' "$_d1out" | grep -q 'sudo opk status'; then
        pass "#201: sudo-refused + healthy binary renders the real verdict, no dead-end advice"
    else
        fail "#201: healthy binary at a sudo-less caller must answer, not advise (got: $_d1out)"
    fi
    # issue #201 residual cell: rc 0 but --version carries no parsable
    # semver (a dev build) — informational unknown WITHOUT the sudo
    # advice: this caller may hold no sudo rights, and sudo would exec
    # the same binary to the same unparsable answer.
    printf '#!/bin/sh\necho "opencode dev-custom-build"\n' >"$_d1dir/bin/opencode"
    chmod +x "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" refuse-sudo || true)
    if printf '%s' "$_d1out" | grep -q '^KV|opencode version|unknown — binary runs for this caller' &&
        ! printf '%s' "$_d1out" | grep -q '^WARN|' &&
        ! printf '%s' "$_d1out" | grep -q 'sudo opk status'; then
        pass "#201: rc 0 without a parsable version stays informational, no dead-end advice"
    else
        fail "#201: unparsable --version must not advise sudo (got: $_d1out)"
    fi
    # issue #166: the C1 gate reads the MODE BITS, not the caller's [ -x ]
    # (the deployed binary is 750 root:opencode — a caller outside that
    # audience must not read a counted warn over a healthy kit). The
    # simulation is real, not a stub: this fixture is owned by the suite
    # user with mode 007 — the owner class carries --- (the caller's
    # [ -x ] fails), other carries rwx (stat reports any-x). A root-run
    # suite cannot produce the shape (root execs anything with an x
    # bit); that environment notes the skip instead of counting vacuous
    # passes (the 0.0.46a F2 class).
    chmod 007 "$_d1dir/bin/opencode"
    if [ -x "$_d1dir/bin/opencode" ]; then
        echo "  info   suite runs as root — 007 fixture cannot simulate a caller outside the audience (issue #166)"
    else
        _d1out=$(w48d_run "$_d1dir" refuse-sudo || true)
        if ! printf '%s' "$_d1out" | grep -q '^WARN|' &&
            printf '%s' "$_d1out" | grep -q '^KV|opencode version|unknown — probe failed'; then
            pass "#166: binary executable only by its audience (007, caller denied) renders the unknown row, no warn"
        else
            fail "#166: caller-denied binary must not count a warn over a healthy kit (got: $_d1out)"
        fi
        # #200 a W2: the compound shape — corrupt CONTENT behind the
        # caller-denied mode — must render the SAME unknown row: the
        # #163 classifier is [ -x ]-gated, so content cannot change this
        # arm's verdict (the corrupt-vs-healthy split stays root's to
        # judge, the elif's documented contract).
        chmod 700 "$_d1dir/bin/opencode"
        printf '\177ELFbroken-fixture' >"$_d1dir/bin/opencode"
        chmod 007 "$_d1dir/bin/opencode"
        _d1out=$(w48d_run "$_d1dir" refuse-sudo || true)
        if ! printf '%s' "$_d1out" | grep -q '^WARN|' &&
            printf '%s' "$_d1out" | grep -q '^KV|opencode version|unknown — probe failed'; then
            pass "#200 a W2: corrupt content behind a caller-denied mode keeps the unknown row (content-independent)"
        else
            fail "#200 a W2: caller-denied arm must not observe content (got: $_d1out)"
        fi
    fi
    # the re-scoped warn shape: present but NO execute bit for anyone —
    # broken kit, counted warn. Mode bits only, caller-independent, so
    # this pin holds under a root-run suite too.
    chmod 644 "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|missing or not executable' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "#166: no-execute-bit binary keeps the counted warn (broken kit)"
    else
        fail "#166: no-execute-bit binary must stay a counted warn (got: $_d1out)"
    fi
    # #200 a W2: the special digit grants nothing — setuid with no x
    # bit for anyone is still a counted warn (the comment's claim,
    # pinned; caller-independent, so root-run suites hold too).
    chmod 4400 "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|missing or not executable' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "#200 a W2: setuid with no x bit (4400) keeps the counted warn"
    else
        fail "#200 a W2: special digit must not fake any-x (got: $_d1out)"
    fi
    # #200 a W1: stat must DEREFERENCE. A symlink's own mode is always
    # 777 — without -L a dangling link or a no-x target reads any-x and
    # downgrades the counted warn to the uncounted unknown row (dead-end
    # advice: even root cannot exec these shapes). Both pins judge the
    # TARGET's bits and fail for every caller equally — they hold under
    # a root-run suite too.
    ln -sf /nonexistent-opk-166 "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|missing or not executable' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "#200 a W1: dangling symlink counts the warn (broken kit)"
    else
        fail "#200 a W1: dangling symlink must stay a counted warn (got: $_d1out)"
    fi
    printf 'x' >"$_d1dir/nox-target"
    chmod 644 "$_d1dir/nox-target"
    ln -sf "$_d1dir/nox-target" "$_d1dir/bin/opencode"
    _d1out=$(w48d_run "$_d1dir" || true)
    if printf '%s' "$_d1out" | grep -q '^WARN|opencode binary|missing or not executable' &&
        ! printf '%s' "$_d1out" | grep -q 'unknown — probe failed'; then
        pass "#200 a W1: symlink judged by its TARGET's bits (no-x target counts the warn)"
    else
        fail "#200 a W1: symlink must be judged by its target, not the link's 777 (got: $_d1out)"
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
    : >"$WORK/libkit/sh/ddev-terminal.sh"
    # _hk_run <user> <uid|empty=id-fails> <home|empty-for-getent-miss>:
    # prints the row output; stubs decide id/getent so no arm depends on
    # host users. An EMPTY uid makes id fail, executing the probe's
    # `|| echo 1` fallback arm (#196 a T2).
    _hk_run() {
        (
            HK_USER="$1"
            HK_UID="$2"
            HK_HOME="$3"
            export HK_USER HK_UID HK_HOME DEFAULT_USER LIBDIR
            DEFAULT_USER="$HK_USER"
            LIBDIR="$WORK/libkit"
            id() {
                [ "${1:-}" = "-u" ] || return 1
                [ -n "$HK_UID" ] &&
                    printf '%s\n' "$HK_UID" || return 1
            }
            getent() {
                [ "${1:-}" = passwd ] && [ "${2:-}" = "$HK_USER" ] && [ -n "$HK_HOME" ] &&
                    printf 'x:x:1000:1000::%s:/bin/sh\n' "$HK_HOME"
            }
            ui_kv_ok() { echo "OK|$1|$2"; }
            ui_kv_warn() { echo "WARN|$1|$2"; }
            ui_detail() { echo "DETAIL|$1"; }
            eval "$_hk_block"
        ) 2>&1
    }
    # root developer: the loud install-defect row, never "not hooked"
    _rc=0
    _out=$(_hk_run root 0 "$WORK/anywhere") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q "WARN|ddev() hook|install broken — developer 'root' has uid 0" &&
        printf '%s' "$_out" | grep -q 'opk update cannot fix this' &&
        ! printf '%s' "$_out" | grep -q 'not hooked'; then
        pass "uid-0 developer reports the broken install + reinstall fix"
    else
        fail "uid-0 developer reports the broken install + reinstall fix (rc=$_rc out=$_out)"
    fi
    # relocated home with the hook line: active, via the getent home
    mkdir -p "$WORK/hk-homeA"
    printf '[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh\n' \
        >"$WORK/hk-homeA/.bashrc"
    _rc=0
    _out=$(_hk_run hk-dev 1000 "$WORK/hk-homeA") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF "OK|ddev() hook|active — $WORK/hk-homeA/.bashrc"; then
        pass "relocated home: hook found active via getent home"
    else
        fail "relocated home: hook found active via getent home (rc=$_rc out=$_out)"
    fi
    # home exists, no hook line: the classic repairable warning stays
    mkdir -p "$WORK/hk-homeB"
    printf '# plain rc without kit hooks\n' >"$WORK/hk-homeB/.bashrc"
    _rc=0
    _out=$(_hk_run hk-dev 1000 "$WORK/hk-homeB") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'WARN|ddev() hook|not hooked — run opk update'; then
        pass "existing home without hook keeps the repairable warning"
    else
        fail "existing home without hook keeps the repairable warning (rc=$_rc out=$_out)"
    fi
    # home missing: honest "cannot check" instead of unfulfillable advice
    _rc=0
    _out=$(_hk_run hk-dev 1000 "$WORK/hk-missing") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'WARN|ddev() hook|cannot check — home' &&
        ! printf '%s' "$_out" | grep -q 'run opk update'; then
        pass "missing home: cannot-check row, no unfulfillable update advice"
    else
        fail "missing home: cannot-check row, no unfulfillable update advice (rc=$_rc out=$_out)"
    fi
    # getent miss: falls back to /home/<name> (never exists here — the
    # user name is suite-unique) — same honest cannot-check row
    _rc=0
    _out=$(_hk_run rug-nouser-x 1000 "") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'cannot check — home'; then
        pass "getent miss: fallback path still reports cannot-check"
    else
        fail "getent miss: fallback path still reports cannot-check (rc=$_rc out=$_out)"
    fi
    # id-probe failure arm (#196 a T2): id fails -> `|| echo 1` sentinel ->
    # NOT the uid-0 defect row; the hook is still read via the real home.
    mkdir -p "$WORK/hk-idfail"
    printf '[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh\n' \
        >"$WORK/hk-idfail/.bashrc"
    _rc=0
    _out=$(_hk_run hk-idfail "" "$WORK/hk-idfail") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF "OK|ddev() hook|active — $WORK/hk-idfail/.bashrc" &&
        ! printf '%s' "$_out" | grep -q 'install broken'; then
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
if printf '%s' "$_a165" | grep -qF 'if [ ! -f "$LIBDIR/sh/advisories.sh" ]' &&
    printf '%s' "$_a165" | grep -qF 'ui_kv_warn "advisories database" "missing — security checks skipped (fix: sudo opk update)"'; then
    pass "#165: advisories fallback block extractable (negated guard + counted row)"
else
    fail "#165: advisories fallback block not extractable (anchor drift?)"
fi
_a165_run() {
    (
        ui_section() { printf 'SECTION|%s\n' "$1"; }
        ui_kv_warn() { printf 'WARN|%s|%s\n' "$1" "$2"; }
        LIBDIR="$1"
        eval "$_a165"
    )
}
_a165_dir=$(mktemp -d "$WORK/a165.XXXXXX")
_a165_out=$(_a165_run "$_a165_dir" || true)
if printf '%s' "$_a165_out" | grep -q '^SECTION|Security advisories$' &&
    printf '%s' "$_a165_out" | grep -q '^WARN|advisories database|missing — security checks skipped'; then
    pass "#165: missing advisories lib renders the counted row, section named"
else
    fail "#165: missing advisories lib must warn loudly (got: $_a165_out)"
fi
# control: lib present -> fallback silent; then through the REAL guard
# head (shipped guard + shipped sourcing + shipped section header; the
# harness appends only the closing fi) the section still renders.
mkdir -p "$_a165_dir/sh"
: >"$_a165_dir/sh/advisories.sh"
_a165_out=$(_a165_run "$_a165_dir" || true)
if [ -z "$_a165_out" ]; then
    pass "#165: present advisories lib keeps the fallback silent (control)"
else
    fail "#165: present advisories lib must not fire the fallback (got: $_a165_out)"
fi
_a165_head="$(sed -n '/^if \[ -f "\$LIBDIR\/sh\/advisories.sh" \]; then$/,/ui_section "Security advisories"/p' "$STATUS")"
if [ -n "$_a165_head" ]; then
    _a165_out=$(
        (
            ui_section() { printf 'SECTION|%s\n' "$1"; }
            ui_kv_warn() { printf 'WARN|%s|%s\n' "$1" "$2"; }
            LIBDIR="$_a165_dir"
            eval "$(printf '%s\nfi\n' "$_a165_head")"
        ) 2>&1
    ) || true
    if printf '%s' "$_a165_out" | grep -q '^SECTION|Security advisories$' &&
        ! printf '%s' "$_a165_out" | grep -q '^WARN|'; then
        pass "#165: present advisories lib renders the section via the real guard (control)"
    else
        fail "#165: advisories real-guard control broken (got: $_a165_out)"
    fi
else
    fail "#165: advisories guard head not extractable (anchor drift?)"
fi

# b) ddev-terminal: compound guard + elif — complete block
_t165="$(sed -n '/^if \[ -n "\$DEFAULT_USER" \] && \[ -f "\$LIBDIR\/sh\/ddev-terminal.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_t165" | grep -qF 'elif [ -n "$DEFAULT_USER" ]; then' &&
    printf '%s' "$_t165" | grep -qF 'ui_kv_warn "ddev() hook" "not checked — kit file sh/ddev-terminal.sh missing (fix: sudo opk update)"'; then
    pass "#165: ddev-terminal block extractable (compound guard + elif row)"
else
    fail "#165: ddev-terminal block not extractable (anchor drift?)"
fi
_t165_run() {
    (
        _t165_user="$1"
        _t165_lib="$2"
        _t165_home="$3"
        DEFAULT_USER="$_t165_user"
        LIBDIR="$_t165_lib"
        id() {
            [ "${1:-}" = "-u" ] || return 1
            printf '%s\n' 1000
        }
        getent() {
            [ "${1:-}" = passwd ] && [ "${2:-}" = "$_t165_user" ] && [ -n "$_t165_home" ] &&
                printf 'x:x:1000:1000::%s:/bin/sh\n' "$_t165_home"
        }
        ui_kv_ok() { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail() { echo "DETAIL|$1"; }
        eval "$_t165"
        exit 0
    ) 2>&1
}
_t165_dir=$(mktemp -d "$WORK/t165.XXXXXX")
mkdir -p "$_t165_dir/hooked"
printf '# kit hook line: opencode-permissions-kit/sh/ddev-terminal.sh\n' >"$_t165_dir/hooked/.bashrc"
if [ -n "$_t165" ]; then
    _t165_out=$(_t165_run dev "$_t165_dir" "" || true)
    if printf '%s' "$_t165_out" | grep -q '^WARN|ddev() hook|not checked — kit file sh/ddev-terminal.sh missing'; then
        pass "#165: missing ddev-terminal lib warns (counted), row not silently dropped"
    else
        fail "#165: missing ddev-terminal lib must warn (got: $_t165_out)"
    fi
    _t165_out=$(_t165_run "" "$_t165_dir" "" || true)
    if [ -z "$_t165_out" ]; then
        pass "#165: unstamped install stays row-free (compound guard holds)"
    else
        fail "#165: unstamped install must not fire the row (got: $_t165_out)"
    fi
    # control: lib present -> the hook row renders through the real body
    mkdir -p "$_t165_dir/sh"
    : >"$_t165_dir/sh/ddev-terminal.sh"
    _t165_out=$(_t165_run dev "$_t165_dir" "$_t165_dir/hooked" || true)
    if printf '%s' "$_t165_out" | grep -qF "OK|ddev() hook|active — $_t165_dir/hooked/.bashrc" &&
        ! printf '%s' "$_t165_out" | grep -q '^WARN|'; then
        pass "#165: present ddev-terminal lib renders the hook row (control)"
    else
        fail "#165: ddev-terminal control broken (got: $_t165_out)"
    fi
fi

# c) ddev-migrate: compound guard + elif — complete block
_m165="$(sed -n '/^if \[ -n "\$DEFAULT_USER" \] && \[ -f "\$LIBDIR\/sh\/ddev-migrate.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_m165" | grep -qF 'ui_kv_warn "db dumps" "not checked — kit file sh/ddev-migrate.sh missing (fix: sudo opk update)"'; then
    pass "#165: ddev-migrate block extractable (elif row present)"
else
    fail "#165: ddev-migrate block not extractable (anchor drift?)"
fi
_m165_dir=$(mktemp -d "$WORK/m165.XXXXXX")
_m165_run() {
    (
        _m165_user="$1"
        _m165_lib="$2"
        _m165_conf="$3"
        set -u
        set +e
        DEFAULT_USER="$_m165_user"
        LIBDIR="$_m165_lib"
        PROJECTS_CONF="$_m165_conf"
        _mig_root="$_m165_dir"
        _mig_dir="$_m165_dir"
        ui_kv_ok() { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail() { echo "DETAIL|$1"; }
        eval "$_m165"
        exit 0
    ) 2>&1
}
if [ -n "$_m165" ]; then
    _m165_out=$(_m165_run dev "$_m165_dir" "$_m165_dir/no-projects.conf" || true)
    if printf '%s' "$_m165_out" | grep -q '^WARN|db dumps|not checked — kit file sh/ddev-migrate.sh missing'; then
        pass "#165: missing ddev-migrate lib warns (counted)"
    else
        fail "#165: missing ddev-migrate lib must warn (got: $_m165_out)"
    fi
    _m165_out=$(_m165_run "" "$_m165_dir" "$_m165_dir/no-projects.conf" || true)
    if [ -z "$_m165_out" ]; then
        pass "#165: unstamped install stays row-free (migrate guard holds)"
    else
        fail "#165: unstamped install must not fire the migrate row (got: $_m165_out)"
    fi
    # control: lib present, its gap stub answers -> the guarded body
    # renders the real INCOMPLETE row (proves the check family ran)
    mkdir -p "$_m165_dir/sh"
    printf 'ddev_migrate_gap() { echo "1 2"; }\nddev_migrate_projects() { echo p1; echo p2; }\nddev_migrate_home() { echo "$1"; }\n' >"$_m165_dir/sh/ddev-migrate.sh"
    printf '%s/root-a\n' "$_m165_dir" >"$_m165_dir/projects.conf"
    _m165_out=$(_m165_run dev "$_m165_dir" "$_m165_dir/projects.conf" || true)
    if printf '%s' "$_m165_out" | grep -q '^WARN|db dumps|INCOMPLETE — registry lists 2 project(s), only 1 dump(s) recorded$' &&
        ! printf '%s' "$_m165_out" | grep -q 'not checked'; then
        pass "#165: present ddev-migrate lib renders the gap check (control)"
    else
        fail "#165: ddev-migrate control broken (got: $_m165_out)"
    fi
fi

# d) ddev-hosts: readiness flag split + lib guard + elif
_h165pre="$(sed -n '/^# Readiness split (issue #165):/,/^fi$/p' "$STATUS")"
if printf '%s' "$_h165pre" | grep -qF '[ -d /mnt/c ]' &&
    printf '%s' "$_h165pre" | grep -qF '[ -f /mnt/c/Windows/System32/drivers/etc/hosts ]' &&
    printf '%s' "$_h165pre" | grep -qF '[ -n "${DEFAULT_USER:-}" ]' &&
    printf '%s' "$_h165pre" | grep -qF 'id -u "$OPENCODE_USER"'; then
    pass "#165: hosts readiness block extractable, preconditions preserved verbatim"
else
    fail "#165: hosts readiness block not extractable (anchor drift?)"
fi
_h165="$(sed -n '/^if \[ "\$_st_hosts_ready" = true \] && \[ -f "\$LIBDIR\/sh\/ddev-hosts.sh" \]; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_h165" | grep -qF 'ui_kv_warn "hosts (win)" "not checked — kit file sh/ddev-hosts.sh missing (fix: sudo opk update)"'; then
    pass "#165: hosts guard block extractable (flag + lib + elif row)"
else
    fail "#165: hosts guard block not extractable (anchor drift?)"
fi
_h165_dir=$(mktemp -d "$WORK/h165.XXXXXX")
_h165_run() {
    (
        _h165_ready="$1"
        _h165_lib="$2"
        _h165_conf="$3"
        set -u
        set +e
        _st_hosts_ready="$_h165_ready"
        LIBDIR="$_h165_lib"
        PROJECTS_CONF="$_h165_conf"
        ui_kv_ok() { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail() { echo "DETAIL|$1"; }
        eval "$SCAN_HELPERS"
        eval "$_h165"
        exit 0
    ) 2>&1
}
if [ -n "$_h165" ]; then
    _h165_out=$(_h165_run true "$_h165_dir" "$_h165_dir/no-projects.conf" || true)
    if printf '%s' "$_h165_out" | grep -q '^WARN|hosts (win)|not checked — kit file sh/ddev-hosts.sh missing'; then
        pass "#165: ready host + missing ddev-hosts lib warns (counted)"
    else
        fail "#165: ready host + missing ddev-hosts lib must warn (got: $_h165_out)"
    fi
    _h165_out=$(_h165_run false "$_h165_dir" "$_h165_dir/no-projects.conf" || true)
    if [ -z "$_h165_out" ]; then
        pass "#165: unready host stays row-free (readiness split holds)"
    else
        fail "#165: unready host must not fire the hosts row (got: $_h165_out)"
    fi
    # control: lib present, project root with .ddev, stub answers ->
    # the guarded body renders its real missing-hosts row
    mkdir -p "$_h165_dir/sh" "$_h165_dir/root/p1/.ddev"
    printf 'ddev_hosts_missing() { echo "tld.example"; }\n' >"$_h165_dir/sh/ddev-hosts.sh"
    printf '%s/root\n' "$_h165_dir" >"$_h165_dir/projects.conf"
    _h165_out=$(_h165_run true "$_h165_dir" "$_h165_dir/projects.conf" || true)
    if printf '%s' "$_h165_out" | grep -qF "WARN|hosts (win)|$_h165_dir/root/p1: missing tld.example" &&
        printf '%s' "$_h165_out" | grep -q '^DETAIL|add: opk ddev-hosts-add tld.example$' &&
        ! printf '%s' "$_h165_out" | grep -q 'not checked'; then
        pass "#165: present ddev-hosts lib renders the hosts check (control)"
    else
        fail "#165: ddev-hosts control broken (got: $_h165_out)"
    fi
fi

# d3) hosts readiness CHAIN semantics (#199 a W2): the arms in d)
# inject _st_hosts_ready directly, and the /mnt/c file tests are
# host-fixed, so the chain's operator/sentinel semantics are pinned by
# EXECUTING the real uid condition — carved out of the real readiness
# line (the #196 sentinel-pin pattern), run with id stubs: flipping !=
# to = or dropping the || echo 1 sentinel turns arms red. The full
# chain is additionally executed once (any host): it must yield a
# boolean, never an error.
_h165r_cond="$(sed -n 's/^    \[ -n "${DEFAULT_USER:-}" \] && \(.*\); then$/\1/p' "$STATUS")"
if [ -n "$_h165r_cond" ] &&
    printf '%s' "$_h165r_cond" | grep -qF '[ "$(id -u)" != "$(id -u "$OPENCODE_USER" 2>/dev/null || echo 1)" ]'; then
    pass "#165: readiness uid condition extractable from the real chain line"
else
    fail "#165: readiness uid condition not extractable (anchor drift?)"
fi
_h165r_run() {
    (
        _h165r_myuid="$1"
        _h165r_ocuid="$2"
        set -u
        set +e
        OPENCODE_USER=opencode
        id() {
            [ "${1:-}" = "-u" ] || return 1
            if [ "$#" -eq 1 ]; then
                printf '%s\n' "$_h165r_myuid"
                return 0
            fi
            if [ "${2:-}" = "$OPENCODE_USER" ] && [ -n "$_h165r_ocuid" ]; then
                printf '%s\n' "$_h165r_ocuid"
                return 0
            fi
            return 1
        }
        if eval "$_h165r_cond"; then echo ready; else echo unready; fi
    ) 2>&1
}
if [ -n "$_h165r_cond" ]; then
    # operator pin: caller uid == agent uid (agent-side run) must NOT be
    # ready — a flipped != to = in status.sh fails exactly here.
    _h165r_out=$(_h165r_run 1000 1000 || true)
    if [ "$_h165r_out" = "unready" ]; then
        pass "#165: readiness uid condition: agent-uid run stays unready (!= executed)"
    else
        fail "#165: readiness uid condition: agent-uid must stay unready — != drifted? (got: $_h165r_out)"
    fi
    _h165r_out=$(_h165r_run 1000 1500 || true)
    if [ "$_h165r_out" = "ready" ]; then
        pass "#165: readiness uid condition: developer-uid run is ready (!= executed)"
    else
        fail "#165: readiness uid condition: developer-uid must be ready (got: $_h165r_out)"
    fi
    # sentinel pin: an unresolvable agent user resolves to uid 1, and a
    # developer-uid caller is ready — dropping || echo 1 fails here (the
    # half-empty test errors and reads as unready).
    _h165r_out=$(_h165r_run 1000 "" || true)
    if [ "$_h165r_out" = "ready" ]; then
        pass "#165: readiness uid condition: unresolvable agent user -> sentinel 1, developer ready"
    else
        fail "#165: readiness uid condition sentinel drifted (got: $_h165r_out)"
    fi
fi
# full-chain execution smoke (host-independent by design): the /mnt/c
# file tests answer whatever THIS host answers; the pin only asserts
# the chain still executes to a boolean under set -u.
_h165r_chain=$(
    (
        set -u
        set +e
        DEFAULT_USER=dev
        OPENCODE_USER=opencode
        eval "$_h165pre"
        printf '%s\n' "$_st_hosts_ready"
    ) 2>&1
) || true
case "$_h165r_chain" in
    true | false) pass "#165: readiness chain executes to a boolean (real block, set -u)" ;;
    *) fail "#165: readiness chain no longer executes cleanly (got: $_h165r_chain)" ;;
esac

# g) ddev-handover (#199 a W1): the resharde scan's lib guard is the
# same broken-kit class — developer-uid run + missing lib renders the
# counted row, agent-uid runs stay row-free, and a present lib runs the
# real scan (control). The harness runs from tests/, so the checkout-first
# candidate never exists and the deployed LIBDIR fixture decides.
_s165="$(sed -n '/^_st_dhl=/,/^fi$/p' "$STATUS")"
if printf '%s' "$_s165" | grep -qF 'ui_kv_warn "ddev share" "not checked — kit file sh/ddev-handover.sh missing (fix: sudo opk update)"'; then
    pass "#165: ddev-handover block extractable (elif row present)"
else
    fail "#165: ddev-handover block not extractable (anchor drift?)"
fi
_s165_dir=$(mktemp -d "$WORK/s165.XXXXXX")
_s165_run() {
    (
        _s165_myuid="$1"
        _s165_ocuid="$2"
        _s165_lib="$3"
        _s165_conf="$4"
        set -u
        set +e
        OPENCODE_USER=opencode
        LIBDIR="$_s165_lib"
        PROJECTS_CONF="$_s165_conf"
        id() {
            [ "${1:-}" = "-u" ] || return 1
            if [ "$#" -eq 1 ]; then
                printf '%s\n' "$_s165_myuid"
                return 0
            fi
            if [ "${2:-}" = "$OPENCODE_USER" ] && [ -n "$_s165_ocuid" ]; then
                printf '%s\n' "$_s165_ocuid"
                return 0
            fi
            return 1
        }
        ui_kv_ok() { echo "OK|$1|$2"; }
        ui_kv_warn() { echo "WARN|$1|$2"; }
        ui_detail() { echo "DETAIL|$1"; }
        eval "$SCAN_HELPERS"
        eval "$_s165"
        exit 0
    ) 2>&1
}
if [ -n "$_s165" ]; then
    _s165_out=$(_s165_run 1000 1500 "$_s165_dir" "$_s165_dir/no-projects.conf" || true)
    if printf '%s' "$_s165_out" | grep -q '^WARN|ddev share|not checked — kit file sh/ddev-handover.sh missing'; then
        pass "#165: missing ddev-handover lib warns on developer-uid runs (counted)"
    else
        fail "#165: missing ddev-handover lib must warn (got: $_s165_out)"
    fi
    _s165_out=$(_s165_run 1000 1000 "$_s165_dir" "$_s165_dir/no-projects.conf" || true)
    if [ -z "$_s165_out" ]; then
        pass "#165: agent-uid run stays row-free (handover guard holds)"
    else
        fail "#165: agent-uid run must not fire the handover row (got: $_s165_out)"
    fi
    # control: lib present + a project root with .ddev, stub flags a gap
    # -> the guarded body renders the real share row (family ran)
    mkdir -p "$_s165_dir/sh" "$_s165_dir/root/proj/.ddev"
    printf 'ddev_reshare_needed() { return 0; }\n' >"$_s165_dir/sh/ddev-handover.sh"
    printf '%s/root\n' "$_s165_dir" >"$_s165_dir/projects.conf"
    _s165_out=$(_s165_run 1000 1500 "$_s165_dir" "$_s165_dir/projects.conf" || true)
    if printf '%s' "$_s165_out" | grep -qF "WARN|ddev share|$_s165_dir/root/proj/.ddev: group-write missing" &&
        ! printf '%s' "$_s165_out" | grep -q 'not checked'; then
        pass "#165: present ddev-handover lib renders the share scan (control)"
    else
        fail "#165: ddev-handover control broken (got: $_s165_out)"
    fi
fi

# g2) git floor row (#199 a W3): the Core git row must not vanish
# silently when neither resolution candidate delivers git_status_row —
# counted warn row at the call site; control with the helper defined
# renders its row and stays row-free.
_g165="$(sed -n '/^if command -v git_status_row >\/dev\/null 2>&1; then$/,/^fi$/p' "$STATUS")"
if printf '%s' "$_g165" | grep -qF 'ui_kv_warn "git" "not checked — kit file sh/git-check.sh missing or outdated (fix: sudo opk update)"'; then
    pass "#165: git-floor fallback block extractable (helper check + counted row)"
else
    fail "#165: git-floor fallback block not extractable (anchor drift?)"
fi
if [ -n "$_g165" ]; then
    _g165_out=$(
        (
            set -u
            set +e
            ui_kv_warn() { echo "WARN|$1|$2"; }
            ui_kv_ok() { echo "OK|$1|$2"; }
            eval "$_g165"
            exit 0
        ) 2>&1
    ) || true
    if printf '%s' "$_g165_out" | grep -q '^WARN|git|not checked — kit file sh/git-check.sh missing'; then
        pass "#165: undefined git_status_row renders the counted fallback row"
    else
        fail "#165: undefined git_status_row must warn (got: $_g165_out)"
    fi
    _g165_out=$(
        (
            set -u
            set +e
            git_status_row() { echo "OK|git|2.39.0 — ok (>= 2.30 tested floor)"; }
            ui_kv_warn() { echo "WARN|$1|$2"; }
            ui_kv_ok() { echo "OK|$1|$2"; }
            eval "$_g165"
            exit 0
        ) 2>&1
    ) || true
    if printf '%s' "$_g165_out" | grep -q '^OK|git|' &&
        ! printf '%s' "$_g165_out" | grep -q '^WARN|'; then
        pass "#165: defined git_status_row renders its row, no fallback (control)"
    else
        fail "#165: git-floor control broken (got: $_g165_out)"
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
        set -u
        set +e
        . "$UI_LIB"
        STATUS_SHORT=false
        LIBDIR="$_a165v_dir"
        eval "$_a165"
        eval "$SUMMARY_BLOCK"
    ) 2>&1
) || _a165v_rc=$?
if [ "$_a165v_rc" = "2" ] &&
    printf '%s' "$_a165v_out" | grep -q 'advisories database' &&
    printf '%s' "$_a165v_out" | grep -q '1 warning(s)'; then
    pass "#165: full mode counts the row (warning verdict, exit 2)"
else
    fail "#165: full mode must count the row into exit 2 (rc=$_a165v_rc out=$_a165v_out)"
fi
_a165v_rc=0
_a165v_out=$(
    (
        set -u
        set +e
        . "$UI_LIB"
        UI_SILENT=1
        STATUS_SHORT=true
        LIBDIR="$_a165v_dir"
        eval "$_a165"
        eval "$SUMMARY_BLOCK"
    ) 2>&1
) || _a165v_rc=$?
if [ "$_a165v_rc" = "2" ] &&
    printf '%s' "$_a165v_out" | grep -q "1 warning(s) — run 'opk status' for the full report" &&
    ! printf '%s' "$_a165v_out" | grep -q 'advisories database'; then
    pass "#165: --short mutes the row but counts it (one verdict line, exit 2)"
else
    fail "#165: --short must count silently and exit 2 (rc=$_a165v_rc out=$_a165v_out)"
fi

# f) keep-as-is sites, class-set pin (issue #165 spec, #199 a W5):
# wsl-browser-bridge degrades its own verdict to red by design and
# log.sh stays a silent best-effort audit line — neither may grow a row
# of this class (over-sweep would fire for legitimate optional states).
# Hardened from two exact strings to the full class set: the
# "kit file sh/<name>.sh missing" rows in status.sh must be EXACTLY the
# five broken-kit sites — any over-sweep with this wording, any file,
# fails with the actual set printed (a growing set is a deliberate
# ratchet edit: extend _k165_want alongside the new site).
_k165_want='kit file sh/ddev-handover.sh missing
kit file sh/ddev-hosts.sh missing
kit file sh/ddev-migrate.sh missing
kit file sh/ddev-terminal.sh missing
kit file sh/git-check.sh missing'
_k165_got="$(grep -o 'kit file sh/[a-z0-9-]*\.sh missing' "$STATUS" | LC_ALL=C sort -u)"
if [ "$_k165_got" = "$_k165_want" ]; then
    pass "#165: missing-lib rows are exactly the five broken-kit sites (bridge/log keep their design)"
else
    fail "#165: missing-lib row set drifted (got: $(printf '%s' "$_k165_got" | tr '\n' ';'))"
fi

# id-probe sentinel value (#196 a T2): `|| echo 1` must yield exactly "1"
# for an unresolvable developer — `|| true` (empty uid) keeps every branch
# pin above green while silently re-arming the uid-0 defect row for ghosts.
_st_line="$(grep '^ *_st_dev_uid=' "$STATUS" | head -1)"
if [ -n "$_st_line" ]; then
    _rc=0
    _out=$(
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

# --- upstream "unavailable" row is uncounted (0.0.48b W3, #211 a F8) -----------
# The row the caller cannot judge (offline/blocked/python3-less) used to
# be a counted ui_kv_warn: every air-gapped host exited 2 forever — the
# exact "green unattainable, cron alert worthless" case the file's own
# W3 rule names. Extract the real three-arm block and drive it: the
# unknown arm must render as a plain (uncounted) row; a REAL finding
# (new advisories) must still count as a warn.
_f8_block="$(sed -n '/^        if \[ -n "\$ADV_NEW" \]; then$/,/^        fi$/p' "$STATUS")"
if [ -n "$_f8_block" ]; then
    pass "upstream verdict block extractable from status.sh (#211 a F8)"
    _f8_run() {
        (
            ADV_NEW="$1"
            ADV_PARSE_OK=false
            ui_kv() { echo "kv: $*"; }
            ui_kv_ok() { echo "kvok: $*"; }
            ui_kv_warn() { echo "kvwarn: $*"; }
            ui_detail() { :; }
            eval "$_f8_block"
        ) 2>&1
    }
    _out=$(_f8_run "") || true
    if printf '%s' "$_out" | grep -q 'kv: upstream unknown' &&
        ! printf '%s' "$_out" | grep -q 'kvwarn:'; then
        pass "unavailable arm: plain uncounted row, no warn bump (#211 a F8)"
    else
        fail "unavailable arm: plain uncounted row, no warn bump (out=$_out)"
    fi
    _out=$(_f8_run "GHSA-test-1") || true
    if printf '%s' "$_out" | grep -q 'kvwarn: upstream'; then
        pass "new-advisory arm still a counted warn (#211 a F8)"
    else
        fail "new-advisory arm still a counted warn (out=$_out)"
    fi
else
    fail "upstream verdict block extractable from status.sh (#211 a F8)"
fi

# --- set -u survives unset USER + DEFAULT_USER (#211 a F9) ----------------------
# ${DEFAULT_USER:-$USER} aborted status.sh with rc 2 under set -u when
# both were unset (cron/timer env + conf without the stamp) — the rc
# the contract defines as "warnings only", printed over NO verdict at
# all. Extract the real probe lines and run them with both unset:
# rc must be 0 and the degraded /home/ fallback stands. Hermetic —
# the host's install.conf never runs (0.0.46a F2 class).
_f9_lines="$(sed -n '/^_oc_home=\$(getent passwd/,+1p' "$STATUS")"
if [ -n "$_f9_lines" ]; then
    pass "_oc_home probe lines extractable from status.sh (#211 a F9)"
    _f9_rc=0
    _f9_out=$(env -u USER sh -c 'set -u; unset DEFAULT_USER 2>/dev/null || true
        eval "$1"; printf "home=[%s]" "$_oc_home"' sh "$_f9_lines" 2>&1) || _f9_rc=$?
    if [ "$_f9_rc" -eq 0 ] && printf '%s' "$_f9_out" | grep -q 'home=\[/home/\]*\]'; then
        pass "both unset: no set -u abort, degraded /home/ fallback (#211 a F9)"
    else
        fail "both unset: no set -u abort, degraded fallback (rc=$_f9_rc out=$_f9_out)"
    fi
else
    fail "_oc_home probe lines extractable from status.sh (#211 a F9)"
fi

# --- F25: unjudgeable probes render as uncounted unknowns (#211 a F25) ------------
# Both blocks used the probe's fallback glyph ("?") inside a COUNTED
# verdict: a failed /proc read printed ui_kv_bad "(? > 80)" (false
# alarm), a failed stat printed ui_kv_ok "restricted (mode ?)" (false
# green). Extract both real blocks, drive them with failing probes.
_f25_ports="$(sed -n '/^port_start=\$(cat \/proc\/sys\/net\/ipv4\/ip_unprivileged_port_start/,/^fi$/p' "$STATUS")"
if [ -n "$_f25_ports" ]; then
    F25P=$(mktemp -d)
    mkdir -p "$F25P/bin"
    printf '#!/bin/sh\nexit 1\n' >"$F25P/bin/cat"
    chmod +x "$F25P/bin/cat"
    _f25_sh="$(command -v sh)"
    _out=$(PATH="$F25P/bin" "$_f25_sh" -c '
        ui_kv()     { echo "kv: $*"; }
        ui_kv_ok()  { echo "kvok: $*"; }
        ui_kv_bad() { echo "kvbad: $*"; }
        ui_detail() { :; }
        eval "$1"
    ' sh "$_f25_ports" 2>&1) || true
    rm -rf "$F25P"
    if printf '%s' "$_out" | grep -q 'kv: router ports unknown' &&
        ! printf '%s' "$_out" | grep -q 'kvbad:'; then
        echo "  ${GREEN}PASS${NC}  unreadable port_start: uncounted unknown, no false alarm (#211 a F25)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  unreadable port_start: uncounted unknown (out=$_out)"
        failures=$((failures + 1))
    fi
else
    echo "  ${RED}FAIL${NC}  F25 ports block extractable"
    failures=$((failures + 1))
fi
_f25_mnt="$(sed -n '/^    mnt_mode=\$(stat -c %a \/mnt\/c/,/^    fi$/p' "$STATUS")"
if [ -n "$_f25_mnt" ]; then
    F25=$(mktemp -d)
    mkdir -p "$F25/bin"
    printf '#!/bin/sh\nexit 1\n' >"$F25/bin/stat"
    chmod +x "$F25/bin/stat"
    _f25_sh="$(command -v sh)"
    _out=$(PATH="$F25/bin" "$_f25_sh" -c '
        ui_kv()     { echo "kv: $*"; }
        ui_kv_ok()  { echo "kvok: $*"; }
        ui_kv_warn(){ echo "kvwarn: $*"; }
        ui_kv_bad() { echo "kvbad: $*"; }
        ui_detail() { :; }
        eval "$1"
    ' sh "$_f25_mnt" 2>&1) || true
    if printf '%s' "$_out" | grep -q 'kv: /mnt/c unknown' &&
        ! printf '%s' "$_out" | grep -q 'kvok:.*mode ?'; then
        echo "  ${GREEN}PASS${NC}  failing /mnt/c stat: uncounted unknown, no false green (#211 a F25)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  failing /mnt/c stat: uncounted unknown (out=$_out)"
        failures=$((failures + 1))
    fi
    rm -rf "$F25"
else
    echo "  ${RED}FAIL${NC}  F25 mnt block extractable"
    failures=$((failures + 1))
fi

# --- issue #210: live progress for the project-root scans ------------------------
# The ddev share scan and the Windows hosts scan walk every registered
# root with find — minutes in complete silence on a WSL host with many
# git projects and a cold page cache (the report froze right after the
# "ddev settings" row). Both sites now run through _st_ddev_scan with
# _st_progress_tee in the pipeline — the fs-baseline live-counter
# pattern (issue #14), tuned for a report: found-count + elapsed line
# on a terminal, erased at EOF, byte-identical output everywhere else.
# Pins: tee passthrough verbatim (a progress display must never corrupt
# the scan it reports on), the three fallback paths keep the exact
# bytes of the pre-#210 bare find, a terminal sees the live line AND
# its erase, --short never does, and both scan sites call the helper.
# NOT pinned (documented): a killed find mid-walk truncates the scan
# list silently — unchecked rc is the pre-#210 behavior of the bare
# find (parity, not a new fail-soft spot).
if [ -n "$SCAN_HELPERS" ] &&
    printf '%s\n' "$SCAN_HELPERS" | grep -q '^_st_progress_tee() {' &&
    printf '%s\n' "$SCAN_HELPERS" | grep -q '^_st_ddev_scan() {'; then
    pass "#210: scan helpers extractable from status.sh"
else
    fail "#210: scan helpers not extractable (anchor drift?)"
fi
if grep -qF '_st_ddev_scan "ddev share: scanning $_st_root" "$_st_root" "$_st_share_list"' "$STATUS" &&
    grep -qF '_st_ddev_scan "win hosts: scanning $_st_root" "$_st_root" "$_st_hosts_list"' "$STATUS" &&
    ! grep -qE 'find "\$_st_root" .* -name \.ddev' "$STATUS"; then
    pass "#210: both scan sites run through the shared helper (emitter sweep)"
else
    fail "#210: a scan site bypasses _st_ddev_scan (sweep incomplete)"
fi

# Fixture: two projects plus one pruned .ddev per prune class — the
# reference file is the PRE-#210 bare find, verbatim.
T210="$WORK/t210-tree"
mkdir -p "$T210/p1/.ddev" "$T210/p1/vendor/pkg/.ddev" "$T210/p1/node_modules/x/.ddev" \
    "$T210/p1/testdata/f/.ddev" "$T210/p1/sub/.git/.ddev" "$T210/p2/.ddev" \
    "$T210/p2/deep/nested/.ddev"
find "$T210" \( -type d \( -name vendor -o -name node_modules -o -name testdata \
    -o -name .git \) \) -prune \
    -o -type d -name .ddev -prune -print 2>/dev/null >"$WORK/t210-ref.txt"
if [ "$(grep -c . "$WORK/t210-ref.txt")" = "3" ]; then
    pass "#210: fixture has exactly the 3 unpruned .ddev trees"
else
    fail "#210: fixture prune expectation broken ($(grep -c . "$WORK/t210-ref.txt") trees)"
fi

# 1) non-tty run: byte-identical scan list, zero stderr bytes
T210_ERR="$WORK/t210.err"
(
    eval "$SCAN_HELPERS"
    _st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-new.txt"
) 2>"$T210_ERR"
if cmp -s "$WORK/t210-ref.txt" "$WORK/t210-new.txt" && [ ! -s "$T210_ERR" ]; then
    pass "#210: non-tty run: scan bytes identical, stderr empty (logs/cron unchanged)"
else
    fail "#210: non-tty run must be byte-identical and silent"
fi

# 2) python3-less host (L1: the new gate must degrade to the FULL scan,
#    never to a skipped one) — hermetic bin with find/tr only
T210_BIN="$WORK/t210-bin"
mkdir -p "$T210_BIN"
for _t210_t in find tr; do
    ln -s "$(command -v "$_t210_t")" "$T210_BIN/$_t210_t"
done
(
    eval "$SCAN_HELPERS"
    PATH="$T210_BIN"
    export PATH
    _st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-nopy.txt"
) 2>"$T210_ERR"
if cmp -s "$WORK/t210-ref.txt" "$WORK/t210-nopy.txt" && [ ! -s "$T210_ERR" ]; then
    pass "#210: python3-less host: fallback scan stays complete (L1 fail-soft observed)"
else
    fail "#210: python3-less host must scan identically (L1)"
fi

# 3) tee contract: the NUL stream passes through VERBATIM — a progress
#    display must never corrupt the scan it reports on
printf 'a\0b\0c\0d' >"$WORK/t210-in.bin"
(
    eval "$SCAN_HELPERS"
    _st_progress_tee "label-t210" <"$WORK/t210-in.bin" >"$WORK/t210-out.bin"
) 2>"$T210_ERR"
if cmp -s "$WORK/t210-in.bin" "$WORK/t210-out.bin" && [ ! -s "$T210_ERR" ]; then
    pass "#210: progress tee passes scan bytes through verbatim"
else
    fail "#210: progress tee corrupted the scan stream"
fi

# 4) terminal run (pty): the live line draws (label + "found,"), the
#    erase run (76 spaces, longer than any draw pad with this label)
#    follows, the scan list stays byte-identical, and output after the
#    scan continues cleanly. The first frame is drawn synchronously
#    before any byte is pumped, so "found," is deterministic even on an
#    instant scan; later frames may carry a live count (race, not
#    asserted).
export SCAN_HELPERS
cat >"$WORK/t210-pty.sh" <<EOF
eval "\$SCAN_HELPERS"
_st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-pty.txt"
echo "SCAN-FINISHED"
EOF
script -qec "sh $WORK/t210-pty.sh" /dev/null >"$WORK/t210-pty.raw" 2>&1
if grep -aq "found," "$WORK/t210-pty.raw" &&
    grep -aq "scanning" "$WORK/t210-pty.raw" &&
    grep -aq "SCAN-FINISHED" "$WORK/t210-pty.raw" &&
    grep -aqE ' {70,}' "$WORK/t210-pty.raw" &&
    cmp -s "$WORK/t210-ref.txt" "$WORK/t210-pty.txt"; then
    pass "#210: terminal run: live line + erase, scan bytes identical"
else
    fail "#210: terminal run must show the live line and stay byte-identical"
fi
# 4b) a >76-char label truncates with a leader instead of wrapping the
#     tty line (the tail carries — the path end matters more than the
#     prefix). Separate driver: truncation drops "scanning" from the
#     drawn line, so the label assertions above cannot run against it.
cat >"$WORK/t210-trunc.sh" <<EOF
eval "\$SCAN_HELPERS"
_st_ddev_scan "ddev share: scanning $T210/p2/very/deep/nested/path/to/a/long/root" \
    "$T210" "$WORK/t210-trunc.txt"
echo "SCAN-FINISHED"
EOF
script -qec "sh $WORK/t210-trunc.sh" /dev/null >"$WORK/t210-trunc.raw" 2>&1
if grep -aq "found," "$WORK/t210-trunc.raw" &&
    grep -aq "long/root" "$WORK/t210-trunc.raw" &&
    grep -aq "$(printf '\342\200\246')" "$WORK/t210-trunc.raw" &&
    cmp -s "$WORK/t210-ref.txt" "$WORK/t210-trunc.txt"; then
    pass "#210: over-long labels truncate with a leader, keep the path tail"
else
    fail "#210: label truncation broken (>76-char label)"
fi

# 5) --short (UI_SILENT) on a terminal: no live line at all — the
#    one-line discipline holds even where drawing would be possible
cat >"$WORK/t210-silent.sh" <<EOF
eval "\$SCAN_HELPERS"
UI_SILENT=1 _st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-sil.txt"
echo "SCAN-FINISHED"
EOF
script -qec "sh $WORK/t210-silent.sh" /dev/null >"$WORK/t210-sil.raw" 2>&1
if ! grep -aq "found," "$WORK/t210-sil.raw" &&
    ! grep -aq "scanning" "$WORK/t210-sil.raw" &&
    grep -aq "SCAN-FINISHED" "$WORK/t210-sil.raw" &&
    cmp -s "$WORK/t210-ref.txt" "$WORK/t210-sil.txt"; then
    pass "#210: UI_SILENT (--short) draws nothing on a terminal either"
else
    fail "#210: UI_SILENT must never draw the progress line"
fi

# 5b) (#244 c S3) interpreter-stderr transparency on the degrade paths:
#     a present-but-broken python3 names its problem (probe, advisory
#     feed, scan parser) while every EXPECTED failure stays silent —
#     the empty/warn output contracts are untouched. Line-shape pins
#     first (re-adding a stderr discard goes red), behavior after.
if grep -qF "import sys, threading, time' >/dev/null 2>&1" "$STATUS"; then
    fail "#244 c S3: probe must not discard interpreter stderr (2>&1 found)"
else
    pass "#244 c S3: probe no longer discards interpreter stderr"
fi
if grep -qF 'or ""))'"'"' 2>/dev/null); then' "$STATUS"; then
    fail "#244 c S3: advisory parse must not discard interpreter stderr"
else
    pass "#244 c S3: advisory parse no longer discards interpreter stderr"
fi
if grep -qF 'python3 "$PARSER" "$SCAN_CFG" 2>/dev/null' "$STATUS"; then
    fail "#244 c S3: leak-scan parser must not discard its diagnostic stderr"
else
    pass "#244 c S3: leak-scan parser no longer discards its diagnostic stderr"
fi
# Probe behavior, on a real tty (the probe only runs on the tty path):
# the shim's diagnostic must appear in the terminal transcript while
# the scan output stays byte-identical to the reference — the scan
# never depends on its progress display. The diagnostic literal
# lives in a variable — consuming grep lines quoting it inline chain
# into the sandbox scanner's raw-line rm-suffix pattern (#244 c S1;
# the definition line is clean).
C244DIAG='platform independent libraries'
mkdir -p "$WORK/t244c-noisy"
printf '#!/bin/sh\necho "%s" >&2\nexit 9\n' "$C244DIAG" >"$WORK/t244c-noisy/python3"
chmod +x "$WORK/t244c-noisy/python3"
cat >"$WORK/t244c-pty.sh" <<EOF
eval "\$SCAN_HELPERS"
UI_SILENT=0 _st_ddev_scan "c244: scanning $T210" "$T210" "$WORK/t244c-out.txt"
echo "SCAN-FINISHED"
EOF
script -qec "PATH=\"$WORK/t244c-noisy:\$PATH\" sh $WORK/t244c-pty.sh" /dev/null >"$WORK/t244c.raw" 2>&1
if grep -aqF "$C244DIAG" "$WORK/t244c.raw" &&
    grep -aq "SCAN-FINISHED" "$WORK/t244c.raw" &&
    cmp -s "$WORK/t210-ref.txt" "$WORK/t244c-out.txt"; then
    pass "#244 c S3: status probe surfaces a broken interpreter's diagnostic (tty path)"
else
    fail "#244 c S3: status probe must pass interpreter stderr through on a terminal"
fi
# Advisory behavior — the shipped program, extracted, keeps its
# contract: garbage in -> rc 1, SILENT (the except path is the
# expected failure; the passthrough must not add noise to it).
C244ADVPGM="$(sed -n "/if ADV_IDS=\$(printf/,/); then\$/p" "$STATUS" |
    sed "1s/^.*python3 -c '//" | sed "\$s/'[[:space:]]*); then\$//")"
if printf 'not json' | python3 -c "$C244ADVPGM" >/dev/null 2>"$WORK/t244c-adv.err"; then
    fail "#244 c S3: advisory program must reject an unparseable feed (rc 1)"
elif [ ! -s "$WORK/t244c-adv.err" ]; then
    pass "#244 c S3: advisory parse fails SILENT on an unparseable feed (expected path)"
else
    fail "#244 c S3: advisory parse must stay silent on expected failures (err=$(cat "$WORK/t244c-adv.err"))"
fi
# Leak-scan parser behavior: a broken config surfaces the parser's own
# clean error line (not a traceback) — that is what now passes through.
C244PARSER="$(dirname "$STATUS")/../py/jsonc-parser.py"
printf 'not json at all\n' >"$WORK/t244c-bad.jsonc"
C244PRC=0
python3 "$C244PARSER" "$WORK/t244c-bad.jsonc" >/dev/null 2>"$WORK/t244c-par.err" || C244PRC=$?
if [ "$C244PRC" -ne 0 ] && grep -q 'Error' "$WORK/t244c-par.err" &&
    ! grep -q 'Traceback' "$WORK/t244c-par.err"; then
    pass "#244 c S3: leak-scan parser failure prints a clean diagnostic (no traceback)"
else
    fail "#244 c S3: parser diagnostic shape (rc=$C244PRC err=$(cat "$WORK/t244c-par.err"))"
fi

# 3b) (#221 a W11) multi-chunk verbatim passthrough: ~2.5 MB — several
#     read1 chunks with NULs inside each and a NUL-less tail. read1 must
#     forward byte-for-byte across chunk boundaries (reorder/drop reds
#     the cmp; a single-chunk 7-byte probe cannot see this class).
T210_BIG="$WORK/t210-big.bin"
python3 -c 'import sys
buf = b"".join((b"chunk%d" % i) * 70000 + b"\0" for i in range(5)) + b"tail-no-nul"
sys.stdout.buffer.write(buf)' >"$T210_BIG"
(
    eval "$SCAN_HELPERS"
    _st_progress_tee "label-big" <"$T210_BIG" >"$WORK/t210-big-out.bin"
) 2>"$T210_ERR"
if cmp -s "$T210_BIG" "$WORK/t210-big-out.bin" && [ ! -s "$T210_ERR" ]; then
    pass "#221: multi-chunk (2.5 MB) stream passes through verbatim"
else
    fail "#221: multi-chunk passthrough corrupted the scan stream"
fi

# 3c) (#221 a W1) counter timeliness: records available at t=0, EOF at
#     t=2 — the 0:01 frame must already carry "3 found". A full-buffer
#     read starves the counter (every frame "0 found" until EOF); read1
#     returns available bytes at once. 1 s of margin on both sides of
#     the 0:01 draw makes this deterministic, not a race.
cat >"$WORK/t210-w1.sh" <<EOF
eval "\$SCAN_HELPERS"
( printf 'a\0b\0c\0'; sleep 2 ) | _st_progress_tee "w1pin" > /dev/null
EOF
script -qec "sh $WORK/t210-w1.sh" /dev/null >"$WORK/t210-w1.raw" 2>&1
if grep -aq 'w1pin — 3 found, 0:01' "$WORK/t210-w1.raw"; then
    pass "#221: found-counter engages mid-stream (read1, not buffered read)"
else
    fail "#221: counter starved — frames show 0 found while records flow"
fi

# 4c) (#221 a W2) join latency: an instant scan must not pay the
#     ticker's second — Event.set wakes the wait, bool+sleep made join()
#     sit out the full sleep (>= 1 s floor, measured 1014 ms). Min of 3
#     runs vs a 700 ms bound: ~5x above a healthy pty run, 300 ms under
#     the broken floor. TIMING-SENSITIVE (L4b): the min-of-3 absorbs CI
#     load spikes; if this ever flakes, fix is a slower bound, not a
#     sleep — the broken floor scales with the tick period, not load.
T210_MIN=999999
for _t210_i in 1 2 3; do
    cat >"$WORK/t210-w2.sh" <<EOF
eval "\$SCAN_HELPERS"
_s=\$(date +%s%N)
_st_ddev_scan "w2pin" "$T210" "$WORK/t210-w2.txt"
_e=\$(date +%s%N)
echo "W2-ELAPSED-MS=\$(( (_e - _s) / 1000000 ))"
EOF
    script -qec "sh $WORK/t210-w2.sh" /dev/null >"$WORK/t210-w2.raw" 2>&1
    _t210_ms=$(grep -ao 'W2-ELAPSED-MS=[0-9]*' "$WORK/t210-w2.raw" | tail -1 | cut -d= -f2)
    [ -n "$_t210_ms" ] || _t210_ms=999999
    [ "$_t210_ms" -lt "$T210_MIN" ] && T210_MIN=$_t210_ms
done
if [ "$T210_MIN" -lt 700 ] && cmp -s "$WORK/t210-ref.txt" "$WORK/t210-w2.txt"; then
    pass "#221: instant scan joins immediately (min ${T210_MIN}ms of 3, bound 700ms)"
else
    fail "#221: join latency — instant scan took >= 700ms (min ${T210_MIN}ms)"
fi

# 6) (#221 a W4) gate drift made observable: on a non-tty run python3
#    must not be invoked AT ALL. The shim writes a marker FILE, not
#    stderr — the production probe discards its own stderr, so a
#    stderr-observing pin would prove nothing (L1). Catches a
#    dropped/inverted [ -t 2 ] (probe would start, marker appears) and
#    the pre-fix shape (command -v alone — tee runs, dies, list empties,
#    cmp reds too).
T210_PYBIN="$WORK/t210-pybin"
T210_PROBE="$WORK/t210-probe.log"
mkdir -p "$T210_PYBIN"
printf '#!/bin/sh\necho x >> "%s"\nexit 9\n' "$T210_PROBE" >"$T210_PYBIN/python3"
chmod +x "$T210_PYBIN/python3"
rm -f "$T210_PROBE"
(
    eval "$SCAN_HELPERS"
    PATH="$T210_PYBIN:$PATH"
    export PATH
    _st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-gate.txt"
) 2>"$T210_ERR"
if cmp -s "$WORK/t210-ref.txt" "$WORK/t210-gate.txt" && [ ! -f "$T210_PROBE" ]; then
    pass "#221: non-tty run never invokes python3 (gate drift observable)"
else
    fail "#221: non-tty run started python3 — gate drifted"
fi

# 7) (#221 a W3, a W12) broken-but-findable python3 on a TERMINAL: the
#    health probe fires exactly ONCE (cache across both scans), drops
#    both scans to the bare-find branch — full lists, no live line, no
#    traceback, run proceeds. Pre-fix shape: tee branch taken, tee dies
#    at startup, EMPTY list (the false-green), marker written twice.
cat >"$WORK/t210-broken.sh" <<EOF
PATH="$T210_PYBIN:\$PATH"
export PATH
eval "\$SCAN_HELPERS"
_st_ddev_scan "ddev share: scanning $T210" "$T210" "$WORK/t210-brk1.txt"
_st_ddev_scan "win hosts: scanning $T210" "$T210" "$WORK/t210-brk2.txt"
echo "SCAN-FINISHED"
EOF
rm -f "$T210_PROBE" # pin isolation: pin 6's gate-drift probe must not seed this count
script -qec "sh $WORK/t210-broken.sh" /dev/null >"$WORK/t210-brk.raw" 2>&1
if cmp -s "$WORK/t210-ref.txt" "$WORK/t210-brk1.txt" &&
    cmp -s "$WORK/t210-ref.txt" "$WORK/t210-brk2.txt" &&
    grep -aq "SCAN-FINISHED" "$WORK/t210-brk.raw" &&
    ! grep -aq "found," "$WORK/t210-brk.raw" &&
    [ -f "$T210_PROBE" ] &&
    [ "$(wc -l <"$T210_PROBE" 2>/dev/null || echo 0)" = 1 ]; then
    pass "#221: broken python3 on a tty: probe once, bare-find fallback, full scans"
else
    fail "#221: broken python3 must fall back to complete scans (probe cached)"
fi

# 8) (#221 a W8) extraction integrity beyond presence: the extracted
#    helpers must PARSE (sh -n) and carry the tee's full body — an
#    early col-0 brace truncating the range leaves def ticker/draw
#    behind; unterminated quoting fails sh -n outright.
if printf '%s\n' "$SCAN_HELPERS" | sh -n 2>/dev/null &&
    printf '%s\n' "$SCAN_HELPERS" | grep -q 'def draw' &&
    printf '%s\n' "$SCAN_HELPERS" | grep -q 'def ticker' &&
    printf '%s\n' "$SCAN_HELPERS" | grep -q 'read1'; then
    pass "#221: extracted scan helpers parse and carry the full tee body"
else
    fail "#221: SCAN_HELPERS extraction truncated or unparsable"
fi

# 9) (#221 b W1) SIGINT mid-stream: the tee's KeyboardInterrupt path
#    must stay SILENT. A pty Ctrl-C is flaky to aim (snapshot a W6:
#    the repro delivered the signal to the shell, not python), and a
#    backgrounded pipeline is NO alternative either: POSIX starts
#    async commands with SIGINT set to SIG_IGN, a non-interactive
#    shell cannot reset an ignored signal, and python keeps it — the
#    kill lands, nothing happens, the pin passes vacuously green
#    (found the hard way in this wave's own sabotage run). So the tee
#    stays FOREGROUND (default SIGINT disposition) and only the
#    SENDER is async: it polls until the record has been forwarded
#    (the tee then sits blocked in read1) and kill -INTs the pid that
#    the PATH-first wrapper recorded before exec'ing the real
#    interpreter. Green = signal delivered (sender rc), zero stderr
#    (no traceback), forwarded byte intact, exit 0. Sabotaging the
#    except tuple drops the traceback into the stderr asserted empty.
T210_SIGBIN="$WORK/t210-sigbin"
T210_SIGPID="$WORK/t210-sigpid"
mkdir -p "$T210_SIGBIN"
_t210_realpy="$(command -v python3)"
printf '#!/bin/sh\necho $$ > "%s"\nexec "%s" "$@"\n' \
    "$T210_SIGPID" "$_t210_realpy" >"$T210_SIGBIN/python3"
chmod +x "$T210_SIGBIN/python3"
# async sender: poll for the forwarded byte, then INT the tee's pid
cat >"$WORK/t210-sig-send.sh" <<EOF
_n=0
while [ ! -s "$WORK/t210-sig.out" ] && [ "\$_n" -lt 100 ]; do
    _n=\$((_n + 1))
    sleep 0.05
done
[ -s "$T210_SIGPID" ] && kill -INT "\$(cat "$T210_SIGPID")"
EOF
sh "$WORK/t210-sig-send.sh" &
_t210_sender=$!
_t210_wrc=0
(
    eval "$SCAN_HELPERS"
    PATH="$T210_SIGBIN:$PATH"
    export PATH
    (
        printf 'a\0'
        sleep 2
    ) | _st_progress_tee "sigpin" \
        >"$WORK/t210-sig.out" 2>"$WORK/t210-sig.err"
) || _t210_wrc=$?
_t210_krc=0
wait "$_t210_sender" || _t210_krc=$?
printf 'a\0' >"$WORK/t210-sig.exp"
if [ "$_t210_krc" -eq 0 ] &&
    [ "$_t210_wrc" -eq 0 ] &&
    cmp -s "$WORK/t210-sig.exp" "$WORK/t210-sig.out" &&
    [ ! -s "$WORK/t210-sig.err" ]; then
    pass "#221: SIGINT mid-stream: tee silent, bytes intact, exit 0 (b W1)"
else
    fail "#221: KeyboardInterrupt must not print a traceback (b W1)"
fi

# --- pr-00263 a F2(b): OPENCODE_USER shape gate in status.sh (#243 e X1 mirror) --
# Extract and drive REAL (the uninstall-suite idiom): valid custom name
# and canonical literal pass through silently; the trailing-slash
# spelling that feeds id -gn and the report rows falls back loudly; a
# newline-bearing value cannot forge a second transcript line
# (sanitized WARN — the a F9 class: one line, sanitized form).
_f2bW="$(mktemp -d)"
_f2bG="$(sed -n '/^case "$OPENCODE_USER" in$/,/^esac$/p' "$STATUS")"
if [ -n "$_f2bG" ] && printf '%s' "$_f2bG" | grep -q 'falling back'; then
    pass "status.sh OPENCODE_USER shape gate extractable (pr-00263 a F2b)"
else
    fail "status.sh OPENCODE_USER shape gate extractable (pr-00263 a F2b)"
fi
_f2b_new=$(
    OPENCODE_USER=untest-agent
    eval "$_f2bG" 2>"$_f2bW/ok.log"
    printf '%s' "$OPENCODE_USER"
)
_f2b_canon=$(
    OPENCODE_USER=opencode
    eval "$_f2bG" 2>>"$_f2bW/ok.log"
    printf '%s' "$OPENCODE_USER"
)
_f2b_bad=$(
    OPENCODE_USER="untest-agent/"
    eval "$_f2bG" 2>"$_f2bW/bad.log"
    printf '%s' "$OPENCODE_USER"
)
_f2b_nl=$(
    OPENCODE_USER="$(printf 'oco\nd')"
    eval "$_f2bG" 2>"$_f2bW/nl.log"
    printf '%s' "$OPENCODE_USER"
)
if [ "$_f2b_new" = "untest-agent" ] && [ "$_f2b_canon" = "opencode" ] &&
    [ ! -s "$_f2bW/ok.log" ] && [ "$_f2b_bad" = "opencode" ] &&
    grep -q 'WARN: invalid OPENCODE_USER value in install.conf' "$_f2bW/bad.log" &&
    [ "$_f2b_nl" = "opencode" ] &&
    [ "$(grep -c . "$_f2bW/nl.log")" = 1 ] &&
    grep -q 'oco?d' "$_f2bW/nl.log"; then
    pass "status.sh gate arms: passthrough silent, fallback loud, newline sanitized (pr-00263 a F2b)"
else
    fail "status.sh gate arms (pr-00263 a F2b)"
fi

# --- pr-00263 a F11: a shape-invalid advisory feed is "unavailable", never a traceback
# The embedded python is extracted and driven REAL both directions: a
# dict envelope exits 1 SILENT (the old shape raised a raw traceback on
# cron stderr); a list with null and scalar entries yields exactly the
# real ids.
ADVPY="$(sed -n "/python3 -c 'import json,sys$/,/'); then\$/p" "$STATUS" | sed -e "1s/^.*python3 -c '//" -e "\$s/'); then\$//")"
if [ -n "$ADVPY" ] && printf '%s' "$ADVPY" | grep -q 'isinstance(feed, list)'; then
    pass "advisory feed parser extractable + shape gate present (pr-00263 a F11)"
else
    fail "advisory feed parser extraction/shape gate (pr-00263 a F11)"
fi
_adv_rc1=0
_adv_rc2=0
_adv_err="$(printf '{"envelope":1}' | python3 -c "$ADVPY" 2>&1 >/dev/null)" || _adv_rc1=$?
_adv_out="$(printf '[{"ghsa_id":"GHSA-1"},{"ghsa_id":null},3]' | python3 -c "$ADVPY" 2>/dev/null)" || _adv_rc2=$?
if [ "$_adv_rc1" -ne 0 ] && [ -z "$_adv_err" ] &&
    [ "$_adv_rc2" -eq 0 ] &&
    [ "$(printf '%s' "$_adv_out" | grep -c .)" = 1 ] &&
    printf '%s' "$_adv_out" | grep -q 'GHSA-1'; then
    pass "shape-invalid feed silent-unavailable; list feed yields ids only (pr-00263 a F11)"
else
    fail "advisory feed shape arms (pr-00263 a F11, rc1=$_adv_rc1 rc2=$_adv_rc2 err=$_adv_err out=$_adv_out)"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All status tests passed.${NC}"
exit 0
