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
# Run: sh tests/test-uninstall.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL="$SCRIPT_DIR/../files/uninstall.sh"

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
# the test hermetic) on every host.
cat > "$WORK/id" <<'EOF'
#!/bin/sh
case "$1" in
    -u) echo 60000 ;;
    *)  exit 0 ;;
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

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All uninstall tests passed.${NC}"
exit 0
