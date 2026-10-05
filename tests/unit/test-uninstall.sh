#!/bin/sh
# Unit tests for uninstall.sh (no root, no install needed):
#   - the run() wrapper echoes in dry-run mode instead of executing
#   - root / opencode invocations are refused
#   - project-path screening: system paths from projects.conf are never
#     passed to setfacl/chmod (protects against a tampered conf)
#   - the manual-cleanup hints match what install.sh actually leaves
#     behind (rc lines, deny-all config)
#
# Static extraction where possible; behavioural checks run the script
# with --dry-run against a fake sudo that only logs.
# Run: sh tests/unit/test-uninstall.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Fake sudo: logs the command line, always succeeds. Keeps the test
# unprivileged while letting uninstall.sh build its full command list.
cat > "$WORK/sudo" <<'EOF'
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
cat > "$WORK/id" <<'EOF'
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
    _user="$1"; shift
    # whoami is hardcoded via a PATH shim; the script reads no other
    # user context before the guard.
    printf '#!/bin/sh\necho %s\n' "$_user" > "$WORK/whoami"
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

printf '#!/bin/sh\necho devuser\n' > "$WORK/whoami"; chmod +x "$WORK/whoami"
rm -f "$WORK/log"
if PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes --dry-run >/dev/null 2>&1 \
   && [ ! -e "$WORK/log" ]; then
    pass "--dry-run executes no sudo command (log stayed empty)"
else
    # The credential probe (sudo -n true) is expected and harmless; any
    # OTHER sudo command in dry-run mode is a bug.
    _destructive="$(grep -vE '^sudo -n true( |$)' "$WORK/log" 2>/dev/null || true)"
    if [ -z "$_destructive" ]; then
        pass "--dry-run executes no destructive sudo command (only the -n true probe)"
    else
        fail "--dry-run executed commands: $_destructive"
    fi
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
    '/etc/sudoers.d/opencode' \
    'case "$_un_leg_link" in' \
    '/etc/opencode/*)' \
    'for _un_leg in sudoers install.conf projects.conf setup.conf' \
    '/usr/local/lib/opencode/wrapper' \
    '/usr/local/lib/opencode/protect-projects.sh' \
    'case "$_un_pp_link" in'; do
    if grep -qF -- "$_pin" "$UNINSTALL"; then
        pass "legacy removal pinned: $_pin"
    else
        fail "legacy removal pinned: $_pin"
    fi
done
# The generic legacy names must stay MARKER-GATED, never blanket-removed:
# anything else living at /etc/sudoers.d/opencode or /usr/local/lib/opencode
# is not kit-owned.
if grep -qF 'not kit-owned — left untouched' "$UNINSTALL" \
   && ! grep -Eq 'rm -rf /etc/opencode($|[^-])' "$UNINSTALL"; then
    pass "legacy names are marker-gated (foreign content survives)"
else
    fail "legacy names are marker-gated (foreign content survives)"
fi

# --- 4. system paths in projects.conf are never ACL-cleaned --------------------
# uninstall.sh hardcodes /etc/opencode-permissions-kit/projects.conf (no
# env override), so this is checked by STATIC extraction: pull the pattern
# lines out of the screening case, splice them into a fresh case, and run
# it against representative paths. The real patterns are tested, without
# executing the script against the host's real projects.conf.

SCREEN_PATTERNS="$(sed -n '/case "\$root" in/,/^        esac/p' "$UNINSTALL" \
    | grep -E '^[[:space:]]*/' | sed -e 's/\\$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/)$//' | tr '\n' ' ' | sed -e 's/ $//')"
if [ -n "$SCREEN_PATTERNS" ]; then
    pass "screening patterns extractable from uninstall.sh"
else
    fail "screening patterns extractable from uninstall.sh"
fi

# screen <path>: 0 = screened (system path, skipped), 1 = allowed.
# eval is required: `|` alternation in case patterns is parsed at parse
# time, NOT re-parsed from a variable expansion — a literal $SCREEN_PATTERNS
# would be one big never-matching pattern.
screen() {
    eval "case \"\$1\" in
        $SCREEN_PATTERNS) return 0 ;;
        *) return 1 ;;
    esac"
}

for syspath in / /etc /etc/nginx /usr /usr/share /bin /boot /root /root/x /proc /sys /dev /run /run/x /lib64; do
    if screen "$syspath"; then
        pass "screening rejects $syspath"
    else
        fail "screening rejects $syspath"
    fi
done
if printf '%s' "$SCREEN_PATTERNS" | grep -q '/var/www'; then
    fail "screening patterns must not contain /var/www (legit project area)"
else
    pass "screening patterns must not contain /var/www (legit project area)"
fi
for projpath in /var/www/vhosts /var/www /home/dev/x; do
    if screen "$projpath"; then
        fail "screening allows $projpath"
    else
        pass "screening allows $projpath"
    fi
done

# --- 4b. ownership revert (issue #74) ---------------------------------------------
# The kit hands .ddev/ trees, settings dirs and typo3 bootstrap roots to
# the opencode user; the agent/ddev create opencode-owned files on top.
# Uninstall must give ALL of it back to the developer — matched by
# uid/gid, because the user removal above may already have orphaned the
# ids. Functional: the project loop is extracted verbatim (it hardcodes
# the conf path, so it is fed a fake root via stdin) and run with a
# logging run() stub; the captured uid 60000 and the DISTINCT gids
# (oc 60002 / dev 60001) must land inside the find and the ACL removal,
# with chown to DEFAULT_USER:<dev-group>. The loop
# is extracted verbatim except for its stdin redirect (the conf path is
# hardcoded) — the fake roots are piped in instead.
PROJECT_LOOP="$(sed -n '/while IFS= read -r root; do/,/done < /p' "$UNINSTALL" | sed 's|done < "$UNINSTALL_PROJECTS_CONF"|done|')"
if [ -n "$PROJECT_LOOP" ] && printf '%s' "$PROJECT_LOOP" | grep -q 'find'; then
    pass "project loop with ownership revert extractable from uninstall.sh"
else
    fail "project loop with ownership revert extractable from uninstall.sh"
fi
LOOP_OUT=$(mkdir -p "$WORK/fakeproj" && printf '%s\n/etc\n' "$WORK/fakeproj" | (
    run() { echo "RUN: $*"; }
    run_q() { echo "RUN: $*"; }
    log() { :; }
    # Distinct ids (0.0.42g Q2): UN_OC_GID and UN_DEV_GID must differ so
    # the ACL pin below can prove BOTH principals are removed — the
    # identical-ids fixture was the blindness that let the opencode-group
    # entries survive the dev-gid-only removal (0.0.42g S1).
    UN_OC_UID=60000
    UN_OC_GID=60002
    UN_DEV_GROUP=devgroup
    UN_DEV_GID=60001
    DEFAULT_USER=devuser
    eval "$PROJECT_LOOP"
) 2>&1 || true)
if printf '%s' "$LOOP_OUT" | grep -qF "find $WORK/fakeproj" \
   && ! printf '%s' "$LOOP_OUT" | grep -qF ' -xdev ' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-uid 60000' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-gid 60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-exec chown devuser:devgroup {} +' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '! -type l'; then
    pass "ownership revert: uid/gid-matched chown to the developer per root (issue #74)"
else
    fail "ownership revert loop (out=$(printf '%s' "$LOOP_OUT" | head -5))"
fi
# ! -type l (0.0.42e S1): chown follows a symlink operand — without the
# exclusion, an opencode-planted link inside a project makes the root-run
# revert chown an arbitrary file OUTSIDE the project to the developer.
if printf '%s' "$LOOP_OUT" | grep -qF -- '! -type l'; then
    pass "ownership revert: symlinks excluded from the chown find (0.0.42e S1)"
else
    fail "ownership revert: chown find must exclude symlinks (0.0.42e S1)"
fi
# -xdev would stop at mount boundaries — project roots are regularly
# separate mounts (bind mounts, NFS): the revert must follow, like the
# setfacl -R calls in the same loop (checked above via the -xdev grep).
if printf '%s' "$LOOP_OUT" | grep -qF "find \"/etc\""; then
    fail "ownership revert: system paths are never chowned (screened)"
else
    pass "ownership revert: system paths are never chowned (screened)"
fi

# The uid/gid capture must happen BEFORE the user removal: after userdel
# the name no longer resolves and only the numeric ids can still match
# the orphaned files.
CAPTURE_LINE=$(grep -n 'UN_OC_UID=' "$UNINSTALL" | head -1 | cut -d: -f1)
USERDEL_LINE=$(grep -n 'sudo userdel -r' "$UNINSTALL" | head -1 | cut -d: -f1)
if [ -n "$CAPTURE_LINE" ] && [ -n "$USERDEL_LINE" ] && [ "$CAPTURE_LINE" -lt "$USERDEL_LINE" ]; then
    pass "ownership revert: ids captured before userdel (orphan-proof)"
else
    fail "ownership revert: ids must be captured before userdel (capture=$CAPTURE_LINE userdel=$USERDEL_LINE)"
fi

# ACL removal is targeted, not a wipe (0.0.42e C4): the kit baseline adds
# access entries g:<dev-group> and default entries g:<dev-group>:rwx —
# `setfacl -R -b/-k` removed EVERY extended ACL incl. pre-existing user
# entries the kit never owned. -x is a no-op rc 0 on absent entries.
# Qualifiers use the NUMERIC gid (0.0.42f C2): name qualifiers die at
# setfacl parse time when the name does not resolve, silently disabling
# the cleanup; the capture feeds a fallback branch when even the gid is
# unknown.
if printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60001' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60001' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF 'unknown' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -b' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -k'; then
    pass "ACL revert: both kit principals removed via numeric gids, no skip hints (0.0.42g S1 + 0.0.42i Q3)"
else
    fail "ACL revert must remove BOTH principals (opencode group + dev group) via numeric gids (0.0.42g S1)"
fi
if grep -qF 'UN_DEV_GID=$(id -g "$DEFAULT_USER"' "$UNINSTALL" \
   && grep -qF 'for _un_acl_pair in "opencode group:$UN_OC_GID" "dev group:$UN_DEV_GID"' "$UNINSTALL" \
   && grep -qF '_un_acl_skipped=1' "$UNINSTALL" \
   && grep -qF 'kit ACL entries PARTIALLY removed' "$UNINSTALL"; then
    pass "ACL revert: both gids captured, principal loop, loud per-principal skip + partial log (0.0.42f C2 + 0.0.42g S1 + 0.0.42h S1)"
else
    fail "ACL revert: principal loop + loud skip + partial-log branch required (0.0.42h S1)"
fi

# --- 5. cleanup hints match what install.sh leaves behind ----------------------

if grep -qF "still contain" "$UNINSTALL" && grep -qF 'opencode permissions kit' "$UNINSTALL"; then
    pass "manual-cleanup section mentions the rc lines"
else
    fail "manual-cleanup section mentions the rc lines"
fi
if grep -qF '.config/opencode/opencode.jsonc' "$UNINSTALL"; then
    pass "manual-cleanup section mentions the default-user config"
else
    fail "manual-cleanup section mentions the default-user config"
fi
# The backup path hint must match install.sh's mktemp shape
if grep -qF '/tmp/opencode-install-backup' "$UNINSTALL" \
   && ! grep -qF 'opencode-install-backup-<timestamp>' "$UNINSTALL"; then
    pass "backup hint matches the mktemp path shape"
else
    fail "backup hint matches the mktemp path shape"
fi
# Session hint (issue #73): the running shell keeps the ddev function
# (helper deleted), PATH/umask and group membership — the uninstall must
# tell the user to restart the terminal.
if grep -q 'Restart your terminal' "$UNINSTALL"; then
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
grep -q '"/home/$OPENCODE_USER/.config/opencode"' "$UNINSTALL" \
    && pass "uninstall plugin-unregister rides the conf user (V16)" \
    || fail "uninstall plugin-unregister rides the conf user (V16)"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All uninstall tests passed.${NC}"
exit 0
