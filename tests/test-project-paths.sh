#!/bin/sh
# Unit tests for the project-path policy (install.sh + config.sh):
# system paths must be rejected as project roots — the group baseline
# runs chgrp -R + setfacl -R over every root, so "/", "/usr", ... must
# never be accepted (interactive prompt, --projects flag, custom input,
# config.sh projects add all share the policy).
#
# Static extraction of project_path_sane() from the shipped scripts, then
# table-driven checks. No root required.
# Run: sh tests/test-project-paths.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../files/install.sh"
CONFIG="$SCRIPT_DIR/../files/config.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

extract_fn() {
    # print project_path_sane() { ... } from a script
    sed -n '/^project_path_sane() {/,/^}/p' "$1"
}

# Sanity: the function exists in BOTH scripts (policy drift = test failure)
for f in "$INSTALL" "$CONFIG"; do
    if [ -n "$(extract_fn "$f")" ]; then
        pass "project_path_sane defined in $f"
    else
        fail "project_path_sane defined in $f"
    fi
done

# Load the policy from install.sh
eval "$(extract_fn "$INSTALL")"

# must REJECT (system paths and direct children of them)
REJECT="/ /usr /etc /home /root /var /tmp /bin /sbin /lib /lib64 /libx32 /opt /srv \
/mnt /mnt/c /media /media/usb /proc /sys /dev /run /boot /var/tmp \
/usr/share /etc/nginx /root/projects /home/../etc /./etc /etc/ /usr/ \
relative/path ../etc ./here subdir"

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

# ~ expansion lands in _PP_NORM as an absolute $HOME path
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

# empty is rejected (no accidental defaults)
if project_path_sane ""; then
    fail "rejects empty path"
else
    pass "rejects empty path"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All project path policy tests passed.${NC}"
exit 0
