#!/bin/sh
# Unit tests for the project-path policy (sh/path-sane.sh, sourced by
# install.sh and config.sh since issue #216): system paths must be
# rejected as project roots — the group baseline runs chgrp -R +
# setfacl -R over every root, so "/", "/usr", ... must never be
# accepted (interactive prompt, --projects flag, custom input,
# config.sh projects add all share the policy).
#
# Static extraction of project_path_sane() from the shipped lib, then
# table-driven checks; structural pins keep the policy in exactly ONE
# copy (the old verbatim install.sh+config.sh duplication, #216). No
# root required.
# Run: sh tests/unit/test-project-paths.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
PATH_SANE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/path-sane.sh"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

extract_fn() {
    # print a project_path_sane() { ... } block from a script or lib —
    # indent-tolerant: the lib's real definition sits at indent 0, the
    # callers' fail-closed stubs (issue #216) at +4. Deliberately NOT
    # the harness extract_func (#396): that helper is col-0-strict by
    # contract (over-capture guard); this suite needs the +4 stubs, so
    # the local indent-tolerant shape stays (the #396 boundary case).
    sed -n '/^[[:space:]]*project_path_sane() {/,/^[[:space:]]*}/p' "$1" |
        sed 's/^[[:space:]]*//'
}

# --- issue #216: exactly ONE policy copy, in sh/path-sane.sh ---------------------
# Structure before behavior: the old test compared two verbatim copies
# for identity; the wave moved the policy into a leaf lib, so the pins
# flip — the copy must exist in the lib, the callers must source it and
# must NOT carry their own (only their fail-closed stub).

if [ -n "$(extract_fn "$PATH_SANE")" ]; then
    pass "project_path_sane defined in sh/path-sane.sh (the single copy)"
else
    fail "project_path_sane defined in sh/path-sane.sh (the single copy)"
fi

# Exactly ONE project_path_sane() { block per caller — the fail-closed
# stub. A re-added second (full) copy and a deleted stub both redden.
# Exact count, deliberately NO comment-strip rider (agent/conventions.md
# "Source-counting pins" rides presence pins and count floors, not
# exact counts). What this pin does NOT guard is stub LIVENESS: a
# commented-out stub still counts 1 here — liveness is the extraction
# pins' job just below (extract_fn cannot match a `#` line, so the
# identity pin and the executed stub cell go red on a dead stub)
# (#338 a M1, execution-verified).
for f in "$INSTALL" "$CONFIG"; do
    _stub_n=$(grep -c 'project_path_sane() {' "$f" || true)
    if [ "$_stub_n" -eq 1 ]; then
        pass "only the fail-closed stub defines project_path_sane in ${f##*/} (issue #216)"
    else
        fail "${f##*/} must define project_path_sane exactly once (the fail-closed stub; got $_stub_n) (issue #216)"
    fi
done

# Wiring: install.sh kit_source's the lib (aborts loud when missing);
# config.sh carries both lookup legs (checkout copy first, deployed
# LIBDIR fallback).
grep -q 'kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/path-sane.sh"' "$INSTALL" &&
    pass "install.sh sources sh/path-sane.sh via kit_source (issue #216)" ||
    fail "install.sh sources sh/path-sane.sh via kit_source (issue #216)"
if grep -q '"$SCRIPT_DIR/../sh/path-sane.sh"' "$CONFIG" &&
    grep -q '"$LIBDIR/sh/path-sane.sh"' "$CONFIG"; then
    pass "config.sh sources sh/path-sane.sh (checkout first, LIBDIR fallback) (issue #216)"
else
    fail "config.sh sources sh/path-sane.sh (checkout first, LIBDIR fallback) (issue #216)"
fi

# The two stubs must stay identical — the drift guard the old two-copy
# comparison provided, narrowed to the stubs.
_stub_i="$(extract_fn "$INSTALL")"
_stub_c="$(extract_fn "$CONFIG")"
if [ -n "$_stub_i" ] && [ "$_stub_i" = "$_stub_c" ]; then
    pass "install.sh and config.sh fail-closed stubs identical (issue #216)"
else
    fail "install.sh and config.sh fail-closed stubs drifted or missing (issue #216)"
fi

# And the stub fails CLOSED, executed (L1: the failure path runs, not
# just greps): a missing gate must REFUSE every path loudly (rc 1 +
# stderr), never allow and never be silent. The subshell keeps the
# eval'd stub from leaking into the suite shell — the real policy is
# only loaded further down, AFTER this cell (#338 a Q3). /var/tmp
# input = sanctioned prefix.
# The group redirect must sit INSIDE the substitution — a `) 2>&1"`
# spelling makes the redirect literal string content and stderr escapes
# the capture (the bug this pin's first version shipped).
_stub_out="$(
    {
        eval "$_stub_c"
        if project_path_sane "/var/tmp/any"; then
            echo "ALLOWED"
        else
            echo "refused rc=$?"
        fi
        echo "cell-done"
    } 2>&1
)"
case "$_stub_out" in
    *"project_path_sane unavailable"*"refused rc=1"*"cell-done"*)
        pass "stub refuses loudly: rc 1 + stderr error, never silent (fail closed, issue #216)"
        ;;
    *)
        fail "stub must refuse loudly with rc 1 (fail closed, issue #216; got: $_stub_out)"
        ;;
esac

# Load the policy from the lib (the single copy)
eval "$(extract_fn "$PATH_SANE")"

# must REJECT (system paths and direct children of them)
REJECT="/ /usr /etc /home /root /var /tmp /tmp/build-dir /bin /sbin /lib /lib64 /libx32 /opt /srv \
/mnt /mnt/c /media /media/usb /proc /sys /dev /run /boot /var/tmp \
/var/log /var/log/nginx /var/lib /var/lib/docker /var/spool /var/spool/cron \
/var/cache /var/mail /var/mail/root \
/usr/share /etc/nginx /root/projects /home/../etc /./etc /etc/ /usr/ \
relative/path ../etc ./here subdir \
/home/opencode"

# must ACCEPT (dedicated project folders)
ACCEPT="/var/www/vhosts /var/www /var/www/vhosts/client1 /home/dev/projects \
/home/dev/projects/shop ~/projects ~/dev /srv-not-sys /opt-projects \
/data/projects /var/www/vhosts/ /home/opencode/work"

for p in $REJECT; do
    if project_path_sane "$p"; then
        fail "rejects system path: $p"
    else
        pass "rejects system path: $p"
    fi
done

for p in $ACCEPT; do
    if project_path_sane "$p"; then
        pass "accepts project path: $p"
    else
        fail "accepts project path: $p"
    fi
done

# --- issue #245: a root entry that IS a symlink is refused -----------
# Measured (issue #245 comment, ext4 + overlayfs): every consumer of a
# symlinked conf root operates on the wrong object — the find-based
# baseline passes visit NOTHING (a silent no-op under the callers'
# "baseline applied" lines), chmod g-s / setfacl -R -x dereference onto
# the TARGET. The writer refuses links outright. The fixture lives in
# scratch (blocklisted /tmp): the REASON line discriminates the symlink
# arm from the blocklist, which fires either way — and must NOT fire
# for the real directory next to the link.
_pp245w="$(mktemp -d)"
# widened later by the #357 a C1 trap chain; this narrow one covers the
# window until then (the #280 c C1 leak class)
trap 'rm -rf "$_pp245w"' EXIT INT TERM
mkdir -p "$_pp245w/realroot"
ln -s "$_pp245w/realroot" "$_pp245w/linkroot"
_pp245_err=$(project_path_sane "$_pp245w/linkroot" 2>&1 >/dev/null) && _pp245_rc=0 || _pp245_rc=$?
if [ "$_pp245_rc" -ne 0 ] &&
    printf '%s' "$_pp245_err" | grep -qF "is a symlink — project roots must be real directories"; then
    pass "refuses a symlinked root, with the symlink reason on stderr (#245)"
else
    fail "refuses a symlinked root with reason (rc=$_pp245_rc err=$_pp245_err) (#245)"
fi
# The trailing-slash spelling must hit the SAME arm: the entry-time
# ${1%/} strip normalizes before the [ -L ] — a lexical gate keyed on
# the raw input would dodge it ([ -L "path/" ] is false, measured).
_pp245_err=$(project_path_sane "$_pp245w/linkroot/" 2>&1 >/dev/null) && _pp245_rc=0 || _pp245_rc=$?
if [ "$_pp245_rc" -ne 0 ] &&
    printf '%s' "$_pp245_err" | grep -qF "is a symlink — project roots must be real directories"; then
    pass "trailing-slash spelling of the link: same refusal (#245)"
else
    fail "trailing-slash spelling of the link must refuse the same way (rc=$_pp245_rc) (#245)"
fi
# Discrimination: a REAL directory under the same scratch prefix is
# rejected by the blocklist (scratch is /tmp), NOT by the symlink arm —
# the symlink reason must stay absent (over-firing would break plan-time
# validation of real directories everywhere).
_pp245_err=$(project_path_sane "$_pp245w/realroot" 2>&1 >/dev/null) && _pp245_rc=0 || _pp245_rc=$?
if [ "$_pp245_rc" -ne 0 ] &&
    ! printf '%s' "$_pp245_err" | grep -qF "is a symlink"; then
    pass "real directory: blocklist refusal, symlink arm silent (#245)"
else
    fail "real directory must not trip the symlink arm (rc=$_pp245_rc err=$_pp245_err) (#245)"
fi

# --- review a Q1: caller refusal messages must not misname the cause ------
# project_path_sane returns 1 for system paths, symlinks, relative and
# dot forms alike; each caller prints ONE message for every refusal —
# the old "is a system path" wording was factually false for the new
# symlink arm (learnings L2: a fix that adds a rejection cause sweeps
# every message that enumerates causes). Presence counts carry the
# comment-strip rider; the absence pin needs none (conventions
# "Source-counting pins").
# #346 wave 3: install's three refusal sites moved to install-core.sh;
# the count keeps its || true guard (grep -c aborts on zero under set -e).
_q1i=$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" |
    grep -cF 'is not a valid project root (system path, symlink, or malformed form)' || true)
_q1c=$(sed 's/^[[:space:]]*#.*$//' "$CONFIG" |
    grep -cF 'is not a valid project root (system path, symlink, or malformed form)' || true)
if [ "$_q1i" -eq 3 ] && [ "$_q1c" -eq 2 ]; then
    pass "caller refusal messages enumerate the real causes at all five sites (a Q1)"
else
    fail "caller refusal messages must enumerate the real causes (install=$_q1i/3 config=$_q1c/2) (a Q1)"
fi
if grep -qF 'is a system path' "$INSTALL" "$INSTALL_CORE" "$CONFIG"; then
    fail "no caller message may claim 'is a system path' for every refusal (a Q1)"
else
    pass "no caller message claims 'is a system path' anymore (a Q1)"
fi

# ~ expansion lands in _PP_NORM as an absolute path
if project_path_sane "~/dev" && [ "${_PP_NORM#${HOME}/}" = "dev" ] && [ "${#_PP_NORM}" -gt "${#HOME}" ]; then
    pass "~ expands to \$HOME path (got $_PP_NORM)"
else
    fail "~ expands to \$HOME path (got ${_PP_NORM:-nothing})"
fi
if project_path_sane "~someone/x"; then
    fail "~<name> rejected (no user lookup)"
else
    pass "~<name> rejected (no user lookup)"
fi

# ~ under sudo expands against PROJECT_TILDE_HOME, NOT $HOME: install.sh /
# config.sh run via `sudo bash` where $HOME=/root — "~/dev" must resolve to
# the developer's home, not be rejected as a /root system path.
_save_home="$HOME"
HOME="/root"
PROJECT_TILDE_HOME="/home/dev"
if project_path_sane "~/dev" && [ "$_PP_NORM" = "/home/dev/dev" ]; then
    pass "~ expands against PROJECT_TILDE_HOME under sudo (got $_PP_NORM)"
else
    fail "~ expands against PROJECT_TILDE_HOME under sudo (got ${_PP_NORM:-nothing})"
fi
if project_path_sane "~"; then
    pass "bare ~ accepted via PROJECT_TILDE_HOME (got $_PP_NORM)"
else
    fail "bare ~ accepted via PROJECT_TILDE_HOME"
fi
# Without PROJECT_TILDE_HOME the old behavior holds (=$HOME) — callers
# that never set it keep working.
unset PROJECT_TILDE_HOME
HOME="/home/tester"
if project_path_sane "~/dev" && [ "$_PP_NORM" = "/home/tester/dev" ]; then
    pass "~ falls back to \$HOME when PROJECT_TILDE_HOME unset"
else
    fail "~ falls back to \$HOME when PROJECT_TILDE_HOME unset (got ${_PP_NORM:-nothing})"
fi
# And a /root fallback (sudo without the override) is correctly rejected
# as a system path rather than silently used.
HOME="/root"
if project_path_sane "~/dev"; then
    fail "~/dev under HOME=/root without override rejected by blocklist"
else
    pass "~/dev under HOME=/root without override rejected by blocklist"
fi
HOME="$_save_home"

# --- issue #340: the tilde-home setup is ONE leaf helper, driven -----------------
# path_sane_tilde_home replaces the near-identical inline blocks that
# lived in install.sh (do_plan_phase) and config.sh. Behavioral drive
# with stubbed id/getent — the suite never runs as root, and local
# users must not decide the outcome (the 0.0.46a F2 class). Arms: root
# + resolvable SUDO_USER -> developer home; root + stale SUDO_USER
# (getent empty) -> $HOME (the || true arm); non-root -> $HOME.
_tth=""
_tth="$(sh -c '
    . "$1"
    HOME=/root
    SUDO_USER=dev
    id() { [ "$1" = "-u" ] && printf "0\n"; }
    getent() { [ "$1" = "passwd" ] && [ "$2" = "dev" ] && printf "x:x:1000:1000::/home/dev:/bin/sh\n"; }
    path_sane_tilde_home && printf "%s" "$PROJECT_TILDE_HOME"
' _ "$PATH_SANE" 2>/dev/null)" || true
[ "$_tth" = "/home/dev" ] &&
    pass "tilde-home helper: root + SUDO_USER resolves the developer home (#340)" ||
    fail "tilde-home helper: root + SUDO_USER arm (#340; got ${_tth:-nothing})"
_tth=""
_tth="$(sh -c '
    . "$1"
    HOME=/root
    SUDO_USER=ghost-user
    id() { [ "$1" = "-u" ] && printf "0\n"; }
    getent() { return 2; }
    path_sane_tilde_home && printf "%s" "$PROJECT_TILDE_HOME"
' _ "$PATH_SANE" 2>/dev/null)" || true
[ "$_tth" = "/root" ] &&
    pass "tilde-home helper: stale SUDO_USER keeps \$HOME (#340, the || true arm)" ||
    fail "tilde-home helper: stale SUDO_USER arm (#340; got ${_tth:-nothing})"
_tth=""
_tth="$(sh -c '
    . "$1"
    HOME=/home/tester
    id() { [ "$1" = "-u" ] && printf "1000\n"; }
    path_sane_tilde_home && printf "%s" "$PROJECT_TILDE_HOME"
' _ "$PATH_SANE" 2>/dev/null)" || true
[ "$_tth" = "/home/tester" ] &&
    pass "tilde-home helper: non-root keeps \$HOME (#340)" ||
    fail "tilde-home helper: non-root arm (#340; got ${_tth:-nothing})"

# Wiring: the lib defines the helper; both entry scripts CALL it and
# carry no inline copy (whole-line absence — the fail-safe stubs put
# the assignment inside a one-line function body and do not match);
# config.sh calls it only AFTER sourcing the lib (the helper lives
# there), and both callers keep their fail-safe stubs for a damaged
# lib (the gate's own stub stays fail-closed — its arms are pinned
# above, issue #216).
if grep -q '^path_sane_tilde_home() {' "$PATH_SANE" &&
    ! grep -qE '^[[:space:]]*PROJECT_TILDE_HOME="\$HOME"$' "$INSTALL_CORE" &&
    ! grep -qE '^[[:space:]]*PROJECT_TILDE_HOME="\$HOME"$' "$CONFIG" &&
    ! grep -qE '^[[:space:]]*PROJECT_TILDE_HOME="\$HOME"$' "$INSTALL" &&
    sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -qE '^[[:space:]]*path_sane_tilde_home$' &&
    grep -qF 'path_sane_tilde_home() { PROJECT_TILDE_HOME="$HOME"; }' "$INSTALL" &&
    grep -qF 'path_sane_tilde_home() { PROJECT_TILDE_HOME="$HOME"; }' "$CONFIG"; then
    pass "tilde-home setup: one lib implementation, callers delegate + fail-safe stubs (#340)"
else
    fail "tilde-home setup wiring incomplete (#340)"
fi
# config.sh ordering: the call sits after the path-sane sourcing loop
# (a call before the sourcing would die on the undefined function).
_cfg_src_ln=$(grep -n 'for cand in "$SCRIPT_DIR/../sh/path-sane.sh"' "$CONFIG" | cut -d: -f1)
_cfg_call_ln=$(grep -n '^path_sane_tilde_home$' "$CONFIG" | cut -d: -f1)
if [ -n "$_cfg_src_ln" ] && [ -n "$_cfg_call_ln" ] && [ "$_cfg_src_ln" -lt "$_cfg_call_ln" ]; then
    pass "config.sh calls the tilde-home helper after sourcing path-sane.sh (#340)"
else
    fail "config.sh tilde-home call ordering (#340; src=$_cfg_src_ln call=$_cfg_call_ln)"
fi

# empty is rejected (no accidental defaults)
if project_path_sane ""; then
    fail "rejects empty path"
else
    pass "rejects empty path"
fi

# Paths containing whitespace are rejected: projects.conf is line-based
# and the install-side writer splits on spaces (0.0.39b C3).
if project_path_sane "/home/dev/my projects"; then
    fail "rejects paths containing spaces (storage format is space-free)"
else
    pass "rejects paths containing spaces (storage format is space-free)"
fi
if project_path_sane "/var/www/vhosts/client site"; then
    fail "rejects paths containing tabs/spaces anywhere"
else
    pass "rejects paths containing tabs/spaces anywhere"
fi

# Trailing-/. and empty-segment forms (0.0.45c S1): a trailing "/." matched
# none of the old interior-dot arms and — with no /var/*, /home/* catch-all
# in the blocklist — put the ROOT-SIDE recursive group baseline over /,
# /var or every home; "/home/opencode/." additionally defeated the
# agent-home exclusion. Leading "//x" bypassed the blocklist the same way
# (bin/opk's form filter refused it all along).
for p in "/." "/var/." "/home/." "/home/opencode/." "//x" "//" "/srv/x/." "/home/dev/."; do
    if project_path_sane "$p"; then
        fail "rejects trailing-/. or empty-segment form: $p"
    else
        pass "rejects trailing-/. or empty-segment form: $p"
    fi
done
# and the same forms behind a trailing slash ("x/./" and "x//" normalize
# via ${1%/} to "x/." and "x/" before the arms — both stay refused)
for p in "/var/./" "//x/" "/./"; do
    if project_path_sane "$p"; then
        fail "rejects dot/empty-segment form behind a trailing slash: $p"
    else
        pass "rejects dot/empty-segment form behind a trailing slash: $p"
    fi
done

# install.sh must store the NORMALIZED path, not the raw tilde input, in
# all entry points — a literal ~/dev in projects.conf is silently skipped
# by every consumer (review 0.0.39b C1). The standard prompt always did;
# --projects and the custom-path dialog must match it. Floor 3 = the
# three entry-point sites; the fourth _PP_NORM site the old floor of 4
# counted was the policy DEFINITION, which moved to sh/path-sane.sh with
# issue #216 (its normalization is pinned behaviorally by the ~ arms
# above) — count install.sh's own sites only.
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
# Guarded count (#260, the #244 f W1 class): grep -c prints 0 AND exits
# 1 on zero matches — under set -e the bare assignment aborted the suite
# before the -ge 4 check could record its FAIL (#244 h W2). Comment-strip
# rider (#261, the #244 g W1 class): commented-out lines stop counting —
# full-line comments only (#244 h W6 residual).
_norm_sites=$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -c '_PP_NORM' || true)
if [ "$_norm_sites" -ge 3 ]; then
    pass "install.sh uses _PP_NORM in all project entry points ($_norm_sites sites)"
else
    fail "install.sh uses _PP_NORM in all project entry points (only $_norm_sites sites)"
fi
if grep -q '_fp_norm="$_fp_norm \$_PP_NORM"' "$INSTALL_CORE" &&
    grep -q '_custom="$_custom \$_PP_NORM"' "$INSTALL_CORE"; then
    pass "install.sh: --projects and custom dialog store the expanded path"
else
    fail "install.sh: --projects and custom dialog store the expanded path"
fi

# --- #260 class pin (representative for the count guards swept this wave):
# the zero-match path must reach its comparison — a recorded FAIL carrying
# the count — never abort the suite under set -e (#244 h W2 probe shape).
# Fixture: a scratch copy of install.sh with every _PP_NORM line deleted
# (the accident the count guards: the marker vanished from the source).
# The bare leg must abort mid-run; the guarded leg must reach the echo
# with count=0. Both legs run as `sh -c` child processes carrying their
# own set -e: a child shell honors errexit regardless of the caller's ||
# context — an in-substitution `set -e` is ignored under bash when the
# substitution sits in an || list (#280 a Q1), so the pin must not rely
# on it. Needle and file reach the child as arguments, never interpolated.
_pin_dir=$(mktemp -d)
# Trap the scratch dir on EXIT/INT/TERM (#280 c C1 abort leak; #280 d S2
# signal arms): the suite registered no trap, so an abort inside the
# window below leaked the mktemp dir in /tmp; sibling suites use the
# same idiom (the scratch traps in test-fs-baseline.sh and
# test-ddev-migrate.sh; the house-wide sweep is #283).
# Re-registered at the _f2bW block below to cover that dir too.
trap 'rm -rf "$_pin_dir" "$_pp245w"' EXIT INT TERM
sed '/_PP_NORM/d' "$INSTALL" >"$_pin_dir/install-no-norm"
_pin_bare=$(sh -c 'set -e; _pn=$(grep -c "$1" "$2"); echo reached' \
    _ '_PP_NORM' "$_pin_dir/install-no-norm") || true
_pin_guarded=$(sh -c 'set -e; _pn=$(grep -c "$1" "$2" || true); echo "reached count=$_pn"' \
    _ '_PP_NORM' "$_pin_dir/install-no-norm") || true
if [ -z "$_pin_bare" ] && [ "$_pin_guarded" = "reached count=0" ]; then
    pass "zero-match count: bare assignment aborts, guarded records 0 for the FAIL (#260 pin)"
else
    fail "zero-match count pin: bare='$_pin_bare' guarded='$_pin_guarded' (#260 pin)"
fi
# --- #261 rider pin (representative for the comment-strip riders swept
# this wave): comment out every _PP_NORM line in a scratch copy — the
# ridden count must drop to zero (no commented survivor), while the
# bare grep -c still sees the full total (the trap this class fixes:
# commented-out lines keep counting, #244 g W1). The expectations are
# derived from the real tree, not hard-coded, so legitimate _PP_NORM
# growth cannot false-red the pin.
sed '/_PP_NORM/s/^\([[:space:]]*\)/\1# /' "$INSTALL" >"$_pin_dir/install-norm-commented"
_norm_ridden=$(sed 's/^[[:space:]]*#.*$//' "$_pin_dir/install-norm-commented" | grep -c '_PP_NORM' || true)
_norm_total=$(grep -c '_PP_NORM' "$INSTALL" || true)
_norm_bare=$(grep -c '_PP_NORM' "$_pin_dir/install-norm-commented" || true)
if [ "$_norm_ridden" = 0 ] && [ "$_norm_bare" = "$_norm_total" ]; then
    pass "comment-strip rider: commented-out _PP_NORM lines stop counting (#261 pin)"
else
    fail "comment-strip rider pin: ridden=$_norm_ridden bare=$_norm_bare total=$_norm_total (#261 pin)"
fi
rm -rf "$_pin_dir"

# --- pr-00263 a F2(b): OPENCODE_USER shape gate in config.sh (#243 e X1 mirror) -
# Extract and drive REAL (the uninstall-suite idiom): valid custom name
# and canonical literal pass through silently; the trailing-slash
# spelling that defangs the agent-home refusal falls back loudly; a
# newline-bearing value cannot forge a second transcript line (the WARN
# echo is sanitized — the pr-00263 a F9 class: exactly one WARN line, sanitized
# form present).
_f2bW="$(mktemp -d)"
# widen the (#280 c C1 / #280 d S2) EXIT/INT/TERM trap to this scratch
# dir (replaces the pin-block registration — both variables are set
# from here on)
trap 'rm -rf "$_pin_dir" "$_f2bW" "$_pp245w"' EXIT INT TERM
_f2bG="$(sed -n '/^case "$OPENCODE_USER" in$/,/^esac$/p' "$CONFIG")"
if [ -n "$_f2bG" ] && printf '%s' "$_f2bG" | grep -q 'falling back'; then
    pass "config.sh OPENCODE_USER shape gate extractable (pr-00263 a F2b)"
else
    fail "config.sh OPENCODE_USER shape gate extractable (pr-00263 a F2b)"
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
    pass "config.sh gate arms: passthrough silent, fallback loud, newline sanitized (pr-00263 a F2b)"
else
    fail "config.sh gate arms (pr-00263 a F2b)"
fi

# --- pr-00263 a F10: agent-home refusals take getent alongside the literal
# spelling — a relocated agent home refuses too (the path policy lives in
# sh/path-sane.sh since issue #216; uninstall.sh twin; the opk/status.sh
# pattern).
grep -q '_pp_agent_home' "$PATH_SANE" &&
    pass "path policy agent-home refusal getent-aware (pr-00263 a F10)" ||
    fail "path policy agent-home refusal literal-only (pr-00263 a F10)"

# --- #353 / #313 phase 4: opk_policy_root — walk-up opk.json discovery ----------
# Behavioral pins on the real shipped function (sourced, not extracted:
# the walker must run exactly as doctor.sh and bin/opk load it). The
# #216 structural rule extends: exactly ONE definition, and the callers
# CALL it, never re-implement it. The count runs comment-stripped per
# conventions.md "Source-counting pins" (#357 a C5 — the ^-anchored
# pattern makes the rider a no-op in effect, the letter is kept).
DOCTOR="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh"
OPK="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"
_opr_defs=$(sed 's/^[[:space:]]*#.*$//' "$PATH_SANE" "$DOCTOR" "$OPK" |
    grep -c '^opk_policy_root() {' || true)
if [ "$_opr_defs" = 1 ] &&
    grep -q 'opk_policy_root "$DOCTOR_ROOT"' "$DOCTOR" &&
    grep -q 'opk_policy_root "$_ho_policy_dir"' "$OPK" &&
    grep -q '\. "$PS_LIB"' "$DOCTOR" &&
    grep -q 'sh/path-sane.sh' "$OPK"; then
    pass "opk_policy_root defined once in the lib, called (not copied) by both consumers"
else
    fail "opk_policy_root defined once in the lib, called (not copied) by both consumers (defs=$_opr_defs)"
fi

OPRW="$(mktemp -d)"
# widen the registration (#357 a C1): a fresh trap on the same signals
# REPLACES the action -- registering only OPRW here dropped $_f2bW
# (created above) from its only cleanup path, one leaked /tmp dir per
# green run. The idiom the file documents: every scratch joins the trap
trap 'rm -rf "$_pin_dir" "$_f2bW" "$OPRW" "$_pp245w"' EXIT INT TERM
# shellcheck disable=SC1090
. "$PATH_SANE"
mkdir -p "$OPRW/proj/sub/deep" "$OPRW/other/mid"
: >"$OPRW/proj/opk.json"

# hit from depth: the project root is found upward
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/proj/sub/deep")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/proj" ]; then
    pass "walk-up finds the root from deep inside"
else
    fail "walk-up finds the root from deep inside (rc=$_opr_rc out=$_opr_out)"
fi

# hit at depth 0: the start dir itself carries the policy
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/proj")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/proj" ]; then
    pass "start dir carrying opk.json is its own root"
else
    fail "start dir carrying opk.json is its own root (rc=$_opr_rc out=$_opr_out)"
fi

# nearest wins: a nested opk.json shadows the parent's
: >"$OPRW/proj/sub/opk.json"
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/proj/sub/deep")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/proj/sub" ]; then
    pass "nearest opk.json wins over a parent's"
else
    fail "nearest opk.json wins over a parent's (rc=$_opr_rc out=$_opr_out)"
fi
rm -f "${OPRW:?}/proj/sub/opk.json"

# no hit: rc 1, no output (the caller keeps its start dir). Environment
# assumption (marked, L4): no opk.json exists at the mktemp ancestors
# (/tmp, /) — the walker runs the full chain to / here
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/other/mid")" || _opr_rc=$?
if [ "$_opr_rc" = 1 ] && [ -z "$_opr_out" ]; then
    pass "no hit anywhere: rc 1, no output"
else
    fail "no hit anywhere: rc 1, no output (rc=$_opr_rc out=$_opr_out)"
fi

# trailing slash and the root dir input stay usable (${1%/} normalizes;
# "/" walks to its own check then stops -- no opk.json at / assumed)
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/proj/sub/")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/proj" ]; then
    pass "trailing-slash start dir normalizes"
else
    fail "trailing-slash start dir normalizes (rc=$_opr_rc out=$_opr_out)"
fi
_opr_rc=0
_opr_out="$(opk_policy_root /)" || _opr_rc=$?
if [ "$_opr_rc" = 1 ] && [ -z "$_opr_out" ]; then
    pass "'/' input: walks its own check, stops (env: no /opk.json)"
else
    fail "'/' input: walks its own check, stops (env: no /opk.json, rc=$_opr_rc out=$_opr_out)"
fi

# a symlinked opk.json counts ([ -f ] follows — the documented contract)
mkdir -p "$OPRW/slink"
printf '{"containerTrees":[]}\n' >"$OPRW/target.json"
ln -s ../target.json "$OPRW/slink/opk.json"
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/slink")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/slink" ]; then
    pass "symlinked opk.json counts as a hit"
else
    fail "symlinked opk.json counts as a hit (rc=$_opr_rc out=$_opr_out)"
fi

# broken markers are NOT markers (#357 a B3): a dangling opk.json
# symlink and a symlink-to-directory both fail [ -f ] — the walk
# continues to the next ancestor, whose policy then governs (the
# reported root is the one whose policy was read)
mkdir -p "$OPRW/brok/sub" "$OPRW/brok2/sub"
ln -s no-such-target "$OPRW/brok/sub/opk.json"
: >"$OPRW/brok/opk.json"
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/brok/sub")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/brok" ]; then
    pass "dangling opk.json symlink is no marker -- ancestor wins"
else
    fail "dangling opk.json symlink is no marker -- ancestor wins (rc=$_opr_rc out=$_opr_out)"
fi
mkdir -p "$OPRW/dirmarker"
ln -s "$OPRW/dirmarker" "$OPRW/brok2/sub/opk.json"
: >"$OPRW/brok2/opk.json"
_opr_rc=0
_opr_out="$(opk_policy_root "$OPRW/brok2/sub")" || _opr_rc=$?
if [ "$_opr_rc" = 0 ] && [ "$_opr_out" = "$OPRW/brok2" ]; then
    pass "symlink-to-dir opk.json is no marker -- ancestor wins"
else
    fail "symlink-to-dir opk.json is no marker -- ancestor wins (rc=$_opr_rc out=$_opr_out)"
fi

# out-of-contract input refuses, never hangs (#357 a A1): a slash-less
# argument cannot progress through ${var%/*} -- pre-fix that looped
# forever (timeout rc 124); the guard must answer rc 1 fast. timeout
# needs an EXECUTABLE, so the call re-sources the lib in a child shell;
# it is the discriminator: without it a regression would hang the suite
# instead of reddening it. cd into scratch first: the "." pin's first
# check reads ./opk.json at the CURRENT cwd -- an opk.json there (a kit
# dev running the suite from a project root) would flip it
_opr_rc=0
_opr_out="$(
    cd "$OPRW/other/mid" &&
        timeout 10 sh -c '. "$1"; opk_policy_root "$2"' x "$PATH_SANE" .
)" || _opr_rc=$?
if [ "$_opr_rc" = 1 ] && [ -z "$_opr_out" ]; then
    pass "slash-less input: rc 1, no output, no hang (A1)"
else
    fail "slash-less input: rc 1, no output, no hang (A1, rc=$_opr_rc out=$_opr_out)"
fi
_opr_rc=0
_opr_out="$(
    cd "$OPRW/other/mid" &&
        timeout 10 sh -c '. "$1"; opk_policy_root "$2"' x "$PATH_SANE" rel/deep
)" || _opr_rc=$?
if [ "$_opr_rc" = 1 ] && [ -z "$_opr_out" ]; then
    pass "relative input with slashes: refuses too, no hang (A1)"
else
    fail "relative input with slashes: refuses too, no hang (A1, rc=$_opr_rc out=$_opr_out)"
fi

# the widened trap survives (#357 a C1): a later trap registration
# REPLACES the action -- the LAST rm -rf trap in this file must still
# name every scratch dir created above it. Static on purpose: a
# behavioral leak pin over /tmp would race foreign processes
_opr_traps=$(grep -n "^trap 'rm -rf" "$0" | tail -1 | cut -d: -f2-)
case "$_opr_traps" in
    *'$_pin_dir'*'$_f2bW'*'$OPRW'*'$_pp245w'*)
        pass "final trap registration still covers every scratch dir (C1)"
        ;;
    *)
        fail "final trap registration still covers every scratch dir (C1, got: $_opr_traps)"
        ;;
esac
rm -rf "${OPRW:?}"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All project path policy tests passed.${NC}"
exit 0
