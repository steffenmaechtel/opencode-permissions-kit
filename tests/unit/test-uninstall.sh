#!/bin/sh
# Unit tests for uninstall.sh (no root, no install needed):
#   - the dry-run arms echo [DRY] + the success lines, nothing executes
#   - root / opencode invocations are refused
#   - project-path screening: system paths from projects.conf are never
#     passed to setfacl/chmod (protects against a tampered conf)
#   - the manual-cleanup hints match what install.sh actually leaves
#     behind (rc lines, deny-all config)
#
# Static extraction where possible; behavioural checks run the script
# with --dry-run against a fake sudo that only logs.
# Since #346 wave 4 the removal sections live in sh/uninstall-core.sh
# (sourced by the entry); lib-level pins live in
# tests/unit/test-uninstall-core.sh, statics below reference both files
# via UNINSTALL/UNINSTALL_CORE (agent/conventions.md, unit-suite path
# variables).
# Run: sh tests/unit/test-uninstall.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"
UNINSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/uninstall-core.sh" # uninstall section lib since #346 wave 4
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh" # install phase lib since #346 wave 3
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

WORK="$(work_new)"

# Fake sudo: logs the command line, always succeeds. Keeps the test
# unprivileged while letting uninstall.sh build its full command list.
cat >"$WORK/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "${FAKE_SUDO_LOG:?}"
exit 0
EOF
chmod +x "$WORK/sudo"

# Fake id: the userdel branch is only entered when the opencode user
# exists — true on a dev host with the kit installed, false on a CI
# runner. Pretend it always exists so the removal plan is complete (and
# the test hermetic) on every host. -u/-g also feed the ownership-revert
# capture (issue #74): uid 60000 must flow into the find; the gids stay
# DISTINCT per user (opencode 60002, dev 60001 — 0.0.42h C2) so
# full-script runs never reshape UN_OC_GID == UN_DEV_GID.
cat >"$WORK/id" <<'EOF'
#!/bin/sh
case "$1" in
    -u)  echo 60000 ;;
    -g)  case "$2" in opencode) echo 60002 ;; *) echo 60001 ;; esac ;;
    -gn) case "$2" in opencode) echo opencodegroup ;; *) echo devgroup ;; esac ;;
    *)   exit 0 ;;
esac
EOF
chmod +x "$WORK/id"

# --- 1. guards: refuses root / opencode --------------------------------------

run_uninstall_as() {
    _user="$1"
    shift
    # whoami is hardcoded via a PATH shim; the script reads no other
    # user context before the guard.
    printf '#!/bin/sh\necho %s\n' "$_user" >"$WORK/whoami"
    chmod +x "$WORK/whoami"
    PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes "$@" >/dev/null 2>&1
}

if run_uninstall_as root; then
    fail "refuses to run as root"
else
    pass "refuses to run as root"
fi
if run_uninstall_as opencode; then
    fail "refuses to run as the opencode user"
else
    pass "refuses to run as the opencode user"
fi

# --- 2. dry-run executes nothing ----------------------------------------------

printf '#!/bin/sh\necho devuser\n' >"$WORK/whoami"
chmod +x "$WORK/whoami"
rm -f "${WORK:?}/log"
if PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes --dry-run >/dev/null 2>&1 &&
    [ ! -e "$WORK/log" ]; then
    pass "--dry-run executes no sudo command (log stayed empty)"
else
    # The credential probe (sudo -n true) is expected and harmless; so are
    # the agents-backup probes (0.0.45c C6 + 0.0.45d W2: sudo ls -A and
    # sudo test -d — read-only, the gate must fail safe in dry-run too),
    # the issue #164 openchamber presence/content probes (sudo test -f +
    # sudo grep -q — read-only, and deliberately unwrapped so they
    # see the file at the rm's authority), and the #198 a W1 legacy
    # sudoers probes (sudo test -L + sudo readlink — same read-only
    # gate-at-the-write's-authority class); any OTHER sudo command in
    # dry-run mode is a bug.
    _destructive="$(grep -vE '^sudo -n true( |$)|^sudo ls -A /home/[^ ]*/\.(agents|claude)$|^sudo test -d /home/[^ ]*/\.(agents|claude)$|^sudo test -f /etc/openchamber/policy\.json$|^sudo grep -q .* /etc/openchamber/policy\.json$|^sudo test -L /etc/sudoers\.d/opencode$|^sudo readlink /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null || true)"
    if [ -z "$_destructive" ]; then
        pass "--dry-run executes no destructive sudo command (only read-only probes)"
    else
        fail "--dry-run executed commands: $_destructive"
    fi
fi

# Issue #164 behavioral: uninstall.sh runs as the developer (root is
# refused above), so the openchamber gate MUST probe through sudo — an
# admin 0700 /etc/openchamber would otherwise hide a kit pin from
# removal. The fake sudo logs the probe in the real call sequence.
if grep -q '^sudo test -f /etc/openchamber/policy\.json$' "$WORK/log" 2>/dev/null &&
    grep -q '^sudo grep -q .* /etc/openchamber/policy\.json$' "$WORK/log" 2>/dev/null; then
    pass "openchamber gate probes via sudo in the real call sequence (issue #164)"
else
    fail "openchamber gate must probe via sudo, not at developer authority (issue #164)"
fi

# #198 a W1 behavioral: the legacy sudoers gate must probe at the rm's
# authority too — /etc/sudoers.d is 0750 on hardened hosts, and a
# developer-blind dir would hide an ACTIVE kit grant from removal. The
# fake sudo exits 0, so both the -L probe and the readlink fire in the
# real call sequence (a plain [ -L ] re-plant drops them from the log).
if grep -q '^sudo test -L /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null &&
    grep -q '^sudo readlink /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null; then
    pass "legacy sudoers gate probes via sudo in the real call sequence (#198 a W1)"
else
    fail "legacy sudoers gate must probe via sudo, not at developer authority (#198 a W1)"
fi

# --- 3. dry-run plans the removals --------------------------------------------

PLAN="$(PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes --dry-run 2>/dev/null || true)"
for want in \
    "/etc/sudoers.d/opencode-permissions-kit" \
    "/usr/local/bin/opencode" \
    "/usr/local/bin/opk" \
    "/usr/local/lib/opencode-permissions-kit" \
    "/etc/profile.d/opencode-permissions-kit-umask.sh" \
    "/etc/opencode-permissions-kit"; do
    if printf '%s' "$PLAN" | grep -qF -- "$want"; then
        pass "dry-run plans removal of $want"
    else
        fail "dry-run plans removal of $want"
    fi
done
if printf '%s' "$PLAN" | grep -qF 'userdel -r'; then
    pass "dry-run plans user removal (userdel -r)"
else
    fail "dry-run plans user removal (userdel -r)"
fi

# --- 3b. legacy pre-0.0.10 artifacts (0.0.43a F5) --------------------------------
# Kits before v0.0.10 wrote /etc/sudoers.d/opencode -> /etc/opencode/sudoers,
# /etc/profile.d/opencode-umask.sh and /usr/local/lib/opencode (with the
# root-runnable protect-projects.sh + its /usr/local/sbin symlink). `opk
# update` refuses pre-0.0.14, so this cohort never migrated names — the
# uninstall must take the legacy names down with the current ones.
if printf '%s' "$PLAN" | grep -qF -- "/etc/profile.d/opencode-umask.sh"; then
    pass "dry-run plans removal of the legacy umask profile"
else
    fail "dry-run plans removal of the legacy umask profile"
fi
# The gated legacy removals (sudoers symlink, /etc/opencode conf files,
# legacy lib dir, sbin helper symlink) branch on the REAL /etc state and
# cannot be staged hermetically — their names and marker gates are pinned
# statically here (the behavior ships via the e2e suites).
for _pin in \
    'sudo test -L /etc/sudoers.d/opencode' \
    '/etc/sudoers.d/opencode' \
    'case "$_un_leg_link" in' \
    '/etc/opencode/*)' \
    'for _un_leg in sudoers install.conf projects.conf setup.conf' \
    '/usr/local/lib/opencode/wrapper' \
    '/usr/local/lib/opencode/protect-projects.sh' \
    'case "$_un_pp_link" in'; do
    if live_src "$UNINSTALL_CORE" | grep -qF -- "$_pin"; then
        pass "legacy removal pinned: $_pin"
    else
        fail "legacy removal pinned: $_pin"
    fi
done
# The generic legacy names must stay MARKER-GATED, never blanket-removed:
# anything else living at /etc/sudoers.d/opencode or /usr/local/lib/opencode
# is not kit-owned.
if live_src "$UNINSTALL_CORE" | grep -qF 'not kit-owned — left untouched' &&
    ! grep -Eq 'rm -rf /etc/opencode($|[^-])' "$UNINSTALL" &&
    ! grep -Eq 'rm -rf /etc/opencode($|[^-])' "$UNINSTALL_CORE"; then
    pass "legacy names are marker-gated (foreign content survives)"
else
    fail "legacy names are marker-gated (foreign content survives)"
fi

# --- 5. cleanup hints match what install.sh leaves behind ----------------------

if live_src "$UNINSTALL" | grep -qF "still contain" && live_src "$UNINSTALL" | grep -qF 'opencode permissions kit'; then
    pass "manual-cleanup section mentions the rc lines"
else
    fail "manual-cleanup section mentions the rc lines"
fi
if live_src "$UNINSTALL" | grep -qF '.config/opencode/opencode.jsonc'; then
    pass "manual-cleanup section mentions the default-user config"
else
    fail "manual-cleanup section mentions the default-user config"
fi
# The backup path hint must match install.sh's durable backup root
# (#370 a I1): both files name /var/backups/opencode-permissions-kit/
# install-*, and neither carries the retired /tmp mktemp shape. The
# positive legs strip comments first (the source-counting rider).
if live_src "$UNINSTALL" |
    grep -qF '/var/backups/opencode-permissions-kit/install-' &&
    live_src "$INSTALL_CORE" |
    grep -qF 'BACKUP_DIR="$_bk_root/install-' &&
    ! grep -qF '/tmp/opencode-install-backup' "$UNINSTALL" &&
    ! grep -qF '/tmp/opencode-install-backup' "$INSTALL" &&
    ! grep -qF '/tmp/opencode-install-backup' "$INSTALL_CORE"; then
    pass "backup paths use the durable /var/backups root"
else
    fail "backup paths use the durable /var/backups root"
fi
# Session hint (issue #73): the running shell keeps the ddev function
# (helper deleted), PATH/umask and group membership — the uninstall must
# tell the user to restart the terminal.
if live_src "$UNINSTALL" | grep -q 'Restart your terminal'; then
    pass "final output tells the user to restart the terminal (issue #73)"
else
    fail "final output tells the user to restart the terminal (issue #73)"
fi

# Unknown options are rejected loudly (0.0.44a V7): `--dryrun --yes`
# (typo) used to silently drop --dryrun and run a REAL unprompted
# uninstall — the arg loop now dies on unknowns like every sibling.
u7_rc=0
u7_out=$(PATH="$WORK:$PATH" sh "$UNINSTALL" --dryrun --yes 2>&1 >/dev/null) || u7_rc=$?
if [ "$u7_rc" -eq 1 ] && printf '%s' "$u7_out" | grep -q 'unknown option: --dryrun'; then
    pass "unknown option aborts before anything runs (V7)"
else
    fail "unknown option aborts before anything runs (V7, rc=$u7_rc out=$u7_out)"
fi

# uninstall side of the conf-user homes (0.0.44b W16)
live_src "$UNINSTALL_CORE" | grep -q '"/home/$OPENCODE_USER/.config/opencode"' &&
    pass "uninstall plugin-unregister rides the conf user (V16)" ||
    fail "uninstall plugin-unregister rides the conf user (V16)"

# OpenChamber policy pin removal (issue #154, Tier 2): kit-owned content
# only — the policy.json goes when (and only when) it pins OUR wrapper;
# any other content is admin-owned and must survive the uninstall.
# Issue #164: presence + content run at the rm's authority (sudo) — the
# script runs as the developer, an admin 0700 /etc/openchamber must not
# hide a kit pin from removal.
if live_src "$UNINSTALL_CORE" | grep -q 'grep -q .\"opencodeBinary\".*\"/usr/local/bin/opencode\"' &&
    live_src "$UNINSTALL_CORE" | grep -q 'rm -f /etc/openchamber/policy.json' &&
    live_src "$UNINSTALL_CORE" | grep -q 'rmdir /etc/openchamber' &&
    live_src "$UNINSTALL_CORE" | grep -qF 'sudo test -f /etc/openchamber/policy.json' &&
    live_src "$UNINSTALL_CORE" | grep -qF 'sudo grep -q '; then
    pass "openchamber policy removed marker-gated (kit content only)"
else
    fail "openchamber policy removal lost its marker gate"
fi

# --- developer home via getent (issue #192, V14 sibling) ---------------------------
# The plugin-cleanup loop must reach the REAL developer home: a root-shell
# install recorded root as the developer, and the hardcoded
# /home/$DEFAULT_USER dir never exists — the cleanup silently missed
# root's config dir. Shape pins (execution needs the tui-register gate).
# Negative sweep tightened (#196 a T1; braced spelling added by
# #196 b B2, survivor diagnostic by #196 b B7; survivor list completed
# by #196 c C1): flag every slash form of the literal
# /home/$DEFAULT_USER spelling, braced included — not just the
# trailing-slash form. Survivors allowed are comment lines, the
# getent-failure fallback (`|| var="/home/$DEFAULT_USER"`), and the
# braced self-default fallback (`var="${var:-/home/${DEFAULT_USER:-$USER}}"`
# — sanctioned shape, status.sh's openchamber home).
_un_bad="$(grep -e '/home/\$DEFAULT_USER' -e '/home/\${DEFAULT_USER' "$UNINSTALL_CORE" 2>/dev/null |
    grep -v '^[[:space:]]*#' |
    grep -v '|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$' |
    grep -v '[[:alnum:]_]\{1,\}="\${[[:alnum:]_]\{1,\}:-/home/\${DEFAULT_USER:-\$USER}}"$' || true)"
if live_src "$UNINSTALL_CORE" | grep -qF '_un_dev_home="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"' &&
    live_src "$UNINSTALL_CORE" | grep -qF '"$_un_dev_home/.config/opencode"' &&
    [ -z "$_un_bad" ]; then
    pass "uninstall.sh resolves the developer home via getent for the cleanup loop"
else
    fail "uninstall.sh resolves the developer home via getent for the cleanup loop (${_un_bad:-no getent})"
fi

echo ""
# --- W11: the no-markers bridge arm follows the helper's rc (#211 b W11) ----------
# The consent arm went honest in a F27; this sibling arm (no wsl.conf
# markers found — library wsl/ tree drop only) kept its unconditional
# success log. Wiring pin (F14's sites-2/3 precedent: the arm is the
# near-unreachable stub path): the call is if-wrapped and the FAILED
# log line exists.
if grep -q 'if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then' "$UNINSTALL_CORE" &&
    grep -q 'wsl browser bridge removal FAILED (no wsl.conf content found; helper or tree drop)' "$UNINSTALL_CORE"; then
    pass "no-markers bridge arm conditions its log on the rc (#211 b W11)"
else
    fail "no-markers bridge arm conditions its log on the rc (#211 b W11)"
fi

# pr-00263 a F10: uninstall twin of the config.sh agent-home refusal.
live_src "$UNINSTALL_CORE" | grep -q '_un_agent_home' &&
    pass "uninstall agent-home refusal getent-aware (pr-00263 a F10)" ||
    fail "uninstall agent-home refusal literal-only (pr-00263 a F10)"

# --- pr-00263 a F3: the six early removal sections are rc-observing (#211 c W1) --
# The #243 a S1/S2 sweep covered the config-dirs section only; six
# earlier `run` rm ops (sudoers, wrapper, cli dispatcher, xdg-open
# shim, library, umask x2) still fed unconditional success lines —
# plus the legacy-shape siblings (legacy sudoers symlink, legacy conf
# dir, legacy library, legacy helper symlink). Pins: (a) no rc-blind
# `run sudo rm` remains anywhere — the plugins loop (the last
# claim-less pair, #246 site 7) converted in the pr-00263 d round;
# (b) the sudoers section driven REAL with a failing
# sudo stub: WARN + FAILED log, no success echo; (c) a succeeding
# stub keeps the success line. The stale pre-state proves the
# section's own reset (the #243 b S2 discipline).
if [ "$(grep -c 'run sudo rm' "$UNINSTALL")" = 0 ] &&
    [ "$(grep -c 'run sudo rm' "$UNINSTALL_CORE")" = 0 ]; then
    pass "zero rc-blind 'run sudo rm' ops remain (#246 closed, pr-00263 a F3 + d)"
else
    fail "rc-blind 'run sudo rm' survived in uninstall.sh (pr-00263 a F3)"
fi
# wave 4: the loop lives in un_tui_plugins_remove (sh/uninstall-core.sh),
# one nesting level deeper (8-space for/done anchors)
PLGSEC="$(sed -n '/for _un_dir in/,/^        done$/p' "$UNINSTALL_CORE" | head -40)"
# Comment-strip rider (#261, the #244 g W1 class — sweep find beyond the
# issue list): the extracted block is stripped before counting, so a
# commented-out un_rc_q call stops counting; full-line comments only
# (#244 h W6 residual).
_unq_n="$(printf '%s' "$PLGSEC" | sed 's/^[[:space:]]*#.*$//' | grep -cF 'un_rc_q "' || true)"
if printf '%s' "$PLGSEC" | grep -qF 'un_rc_q "plugins rm"' &&
    printf '%s' "$PLGSEC" | grep -qF 'plugin removal failed' &&
    [ "$_unq_n" = 2 ]; then
    pass "plugins loop rc-observing, failure WARNs, both ops converted (#246 site 7)"
else
    fail "plugins loop not rc-observing (#246 site 7, pr-00263 d; un_rc_q calls: $_unq_n of 2)"
fi
# pr-00263 e W3: run() lost its last callers to un_rc_q (#246 site 7) and
# is removed — run_q (silenced best-effort) keeps its callers; a
# resurrected def without callers must fail loud here. pr-00263 f W1:
# the pattern counts every def spelling at line start with ANY leading
# whitespace (run() { house style, run () { spaced, indented defs) —
# the e-round draft '^run ()' caught only the spaced form, which no
# def in this file ever used; comments cannot match (after the
# indentation comes '#', never 'run').
[ "$(grep -c '^[[:space:]]*run *()' "$UNINSTALL")" = 0 ] &&
    [ "$(grep -c '^[[:space:]]*run *()' "$UNINSTALL_CORE")" = 0 ] &&
    pass "run() helper gone, no orphaned runner (pr-00263 e W3)" ||
    fail "run() def present without callers (pr-00263 e W3)"
# The F3SEC extraction + sudoers-section arms moved to
# tests/unit/test-uninstall-core.sh with the section (wave 4): they drive
# un_sudoers_remove there as a sourcing pin.

if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All uninstall tests passed.${NC}"
exit 0
