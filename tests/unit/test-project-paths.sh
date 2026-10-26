#!/bin/sh
# Unit tests for the project-path policy (install.sh + config.sh):
# system paths must be rejected as project roots — the group baseline
# runs chgrp -R + setfacl -R over every root, so "/", "/usr", ... must
# never be accepted (interactive prompt, --projects flag, custom input,
# config.sh projects add all share the policy).
#
# Static extraction of project_path_sane() from the shipped scripts, then
# table-driven checks. No root required.
# Run: sh tests/unit/test-project-paths.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

extract_fn() {
    # print project_path_sane() { ... } from a script — indent-tolerant
    # since 0.0.41g (install.sh's copy is nested in do_plan_phase at +4)
    sed -n '/^[[:space:]]*project_path_sane() {/,/^[[:space:]]*}/p' "$1" \
        | sed 's/^[[:space:]]*//'
}

# Sanity: the function exists in BOTH scripts (policy drift = test failure)
for f in "$INSTALL" "$CONFIG"; do
    if [ -n "$(extract_fn "$f")" ]; then
        pass "project_path_sane defined in $f"
    else
        fail "project_path_sane defined in $f"
    fi
done

# The two copies must stay content-identical (compared indent-normalized
# since 0.0.41g): the duplication is deliberate (install.sh cannot source
# config.sh's copy — streamed installs have no siblings yet), so drift
# must be caught here, not on a user's machine.
if [ "$(extract_fn "$INSTALL")" = "$(extract_fn "$CONFIG")" ]; then
    pass "project_path_sane identical in install.sh and config.sh"
else
    fail "project_path_sane drifted between install.sh and config.sh (keep the copies content-identical)"
fi

# Load the policy from install.sh
eval "$(extract_fn "$INSTALL")"

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
# both entry points — a literal ~/dev in projects.conf is silently skipped
# by every consumer (review 0.0.39b C1). The standard prompt (line ~593)
# always did; --projects and the custom-path dialog must match it.
INSTALL="$SCRIPT_DIR/../../files/install.sh"
# Guarded count (#260, the #244 f W1 class): grep -c prints 0 AND exits
# 1 on zero matches — under set -e the bare assignment aborted the suite
# before the -ge 4 check could record its FAIL (#244 h W2).
_norm_sites=$(grep -c '_PP_NORM' "$INSTALL" || true)
if [ "$_norm_sites" -ge 4 ]; then
    pass "install.sh uses _PP_NORM in all project entry points ($_norm_sites sites)"
else
    fail "install.sh uses _PP_NORM in all project entry points (only $_norm_sites sites)"
fi
if grep -q '_fp_norm="$_fp_norm \$_PP_NORM"' "$INSTALL" \
   && grep -q '_custom="$_custom \$_PP_NORM"' "$INSTALL"; then
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
# same idiom (test-fs-baseline.sh:42, test-ddev-migrate.sh:71).
# Re-registered at the _f2bW block below to cover that dir too.
trap 'rm -rf "$_pin_dir"' EXIT INT TERM
sed '/_PP_NORM/d' "$INSTALL" > "$_pin_dir/install-no-norm"
_pin_bare=$(sh -c 'set -e; _pn=$(grep -c "$1" "$2"); echo reached' \
    _ '_PP_NORM' "$_pin_dir/install-no-norm") || true
_pin_guarded=$(sh -c 'set -e; _pn=$(grep -c "$1" "$2" || true); echo "reached count=$_pn"' \
    _ '_PP_NORM' "$_pin_dir/install-no-norm") || true
if [ -z "$_pin_bare" ] && [ "$_pin_guarded" = "reached count=0" ]; then
    pass "zero-match count: bare assignment aborts, guarded records 0 for the FAIL (#260 pin)"
else
    fail "zero-match count pin: bare='$_pin_bare' guarded='$_pin_guarded' (#260 pin)"
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
trap 'rm -rf "$_pin_dir" "$_f2bW"' EXIT INT TERM
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
if [ "$_f2b_new" = "untest-agent" ] && [ "$_f2b_canon" = "opencode" ] \
    && [ ! -s "$_f2bW/ok.log" ] && [ "$_f2b_bad" = "opencode" ] \
    && grep -q 'WARN: invalid OPENCODE_USER value in install.conf' "$_f2bW/bad.log" \
    && [ "$_f2b_nl" = "opencode" ] \
    && [ "$(grep -c . "$_f2bW/nl.log")" = 1 ] \
    && grep -q 'oco?d' "$_f2bW/nl.log"; then
    pass "config.sh gate arms: passthrough silent, fallback loud, newline sanitized (pr-00263 a F2b)"
else
    fail "config.sh gate arms (pr-00263 a F2b)"
fi

# --- pr-00263 a F10: agent-home refusals take getent alongside the literal
# spelling — a relocated agent home refuses too (config.sh + uninstall.sh
# twins; the opk/status.sh pattern).
grep -q '_pp_agent_home' "$CONFIG" \
    && pass "config.sh agent-home refusal getent-aware (pr-00263 a F10)" \
    || fail "config.sh agent-home refusal literal-only (pr-00263 a F10)"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All project path policy tests passed.${NC}"
exit 0
