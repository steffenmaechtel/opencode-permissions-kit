#!/bin/sh
# e2e/run.sh — End-to-end test in Docker container
# Builds an Ubuntu image, installs opencode + our kit, verifies protection.
# Run from repo root: ./tests/e2e/run.sh
# Shares its build/cache/check scaffolding with run-docker-rootless.sh (lib.sh).
set -e

E2E_IMAGE="opencode-e2e"
E2E_CONTAINER="opencode-e2e-test"
. "$(dirname "$(readlink -f "$0")")/lib.sh"

echo ""
echo "${CYAN}=============================================${NC}"
echo "${CYAN}  opencode permissions kit — E2E Test${NC}"
echo "${CYAN}=============================================${NC}"
echo ""

echo "--- opencode binary cache (version-keyed) ---"
e2e_resolve_cache
e2e_fetch_old

e2e_prepare_project

e2e_start_container

# Detect the OUTER docker layout (rootful vs rootless). Only the podman-rootless
# section (12i) uses it: on a rootless host the e2e container runs in a nested
# user namespace and needs an in-range subuid seed; a rootful host (CI) takes
# the kit's true default path. See lib.sh e2e_detect_host_layout.
e2e_detect_host_layout

echo ""
echo "--- 1. Install opencode (from cache) ---"
E 'bash /opencode-cache/install.sh --binary /opencode-cache/opencode-'"$OC_VERSION"'/opencode' || {
    echo "  ${RED}FAIL${NC}  opencode installer failed (network issue?)"
    if E 'test -x /home/dev/.opencode/bin/opencode'; then
        echo "  ${GREEN}OK${NC}  opencode binary already present"
    else
        failures=1; passed=0
        echo ""
        echo "${RED}E2E aborted — cannot install opencode.${NC}"
        sudo rm -rf "$TMP_PROJECT"
        exit 1
    fi
}

echo ""
echo "--- 1b. status.sh before install (not-installed state) ---"
check "status.sh (not installed) reports hardening NOT active" \
    E 'cd /tmp && sh /home/dev/repo/files/status.sh 2>&1 | grep -q "NOT active"'

echo ""
echo "--- 1c. ddev stub (fake /usr/bin/ddev for delegation tests) ---"
# The e2e container has no real ddev. Install a stub that records the invoking
# user + args, so we can prove the kit shim delegates opencode's `ddev` to the
# developer (DEFAULT_USER). Must exist BEFORE install.sh detects DDEV_BIN.
E 'sudo tee /usr/bin/ddev > /dev/null <<'\''EOF'\''
#!/bin/sh
id -un > /tmp/ddev-stub.out
printf "%s " "$@" >> /tmp/ddev-stub.out
echo "" >> /tmp/ddev-stub.out
# Record whether the invoking user can read the (deny-protected) project .env.
# delegated mode -> runs as dev -> readable; sandbox mode -> runs as opencode
# -> denied (the transaction window never opens the .env pattern).
cat /var/www/vhosts/test-project/.env >/dev/null 2>&1 && echo "env-readable" >> /tmp/ddev-stub.out || echo "env-denied" >> /tmp/ddev-stub.out
EOF'
E 'sudo chmod 755 /usr/bin/ddev'
check "ddev stub installed at /usr/bin/ddev" E 'test -x /usr/bin/ddev'

echo ""
echo "--- 2. Run install (from local repo checkout) ---"
# Pre-create a default-user config so install.sh must back it up and
# install the deny-all config (--yes auto-answers the backup prompt).
E 'mkdir -p /home/dev/.config/opencode && printf "%s\n" "{\"model\":\"dummy\"}" > /home/dev/.config/opencode/opencode.jsonc'
E 'sudo bash /home/dev/repo/files/install.sh --yes --projects /var/www/vhosts'
echo "  Install complete."

echo ""
echo "--- 3. Wrapper & binary ---"
check "Wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "Binary at /usr/local/lib/opencode-permissions-kit/bin/opencode" \
    E 'sudo test -x /usr/local/lib/opencode-permissions-kit/bin/opencode'
check "Binary owned root:opencode (not world-executable)" \
    E 'test "$(stat -c %U:%G:%a /usr/local/lib/opencode-permissions-kit/bin/opencode)" = "root:opencode:750"'
check_fail "Default user cannot execute the binary by absolute path" \
    E '/usr/local/lib/opencode-permissions-kit/bin/opencode --version'
check "opencode sandbox user can execute the binary" \
    E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/opencode --version'
check "Wrapper is first in PATH" \
    E 'test "$(which opencode)" = "/usr/local/bin/opencode"'
check "Uninstall script deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/uninstall.sh'
check "config.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/config.sh'
check "update.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check "status.sh deployed" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/status.sh'
check "install.conf written" \
    E 'test -f /etc/opencode-permissions-kit/install.conf'
check "install.conf records DDEV_BIN" \
    E 'grep -q "^DDEV_BIN=/usr/bin/ddev" /etc/opencode-permissions-kit/install.conf'
check "ddev shim deployed to library" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/bin/ddev'
check "ddev shim shadowed at /usr/local/bin/ddev" \
    E 'test -L /usr/local/bin/ddev'
check "ddev shim symlink points at the kit shim" \
    E 'test "$(readlink /usr/local/bin/ddev)" = "/usr/local/lib/opencode-permissions-kit/bin/ddev"'
check "sudoers grants opencode -> DEFAULT_USER ddev delegation" \
    E 'sudo grep -Eq "^opencode[[:space:]]+ALL=\(dev\)[[:space:]]+NOPASSWD: /usr/bin/ddev$" /etc/opencode-permissions-kit/sudoers'
check "status.sh reports hardened" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "hardened"'

echo ""
echo "--- 4. User & group ---"
check "User opencode exists" \
    E 'id opencode'
check "opencode is in www-data" \
    E 'id opencode | grep -q www-data'
check "www-data group exists" \
    E 'getent group www-data'

echo ""
echo "--- 5. File protection (ACL deny for opencode) ---"
check_fail ".env blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check_fail "settings.php blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/settings.php'
check_fail "auth.json blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/auth.json'
check_fail "README.md blocked" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.md'
check "README.txt readable (ddev compat)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.txt'
check "index.php readable" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/index.php'

echo ""
echo "--- 6. Config & agents ---"
check "Config deployed" \
    E 'sudo test -f /home/opencode/.config/opencode/opencode.jsonc'
check "Agents dir exists" \
    E 'sudo test -d /home/opencode/.agents/'
check "default user can cd into opencode home" \
    E 'cd /home/opencode'
check "default user can read opencode.jsonc" \
    E 'test -r /home/opencode/.config/opencode/opencode.jsonc'
check "default user can write opencode.jsonc" \
    E 'test -w /home/opencode/.config/opencode/opencode.jsonc'

echo ""
echo "--- 6b. Default-user deny-all config (self-update bypass protection) ---"
check "default-user deny-all config deployed" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "pre-existing default-user config backed up" \
    E 'ls /home/dev/.config/opencode/ | grep -q "opencode.jsonc_BAK_"'
check "deny-all config owned by dev" \
    E 'test "$(stat -c %U /home/dev/.config/opencode/opencode.jsonc)" = "dev"'
check "deny-all config denies everything" \
    E 'grep -q '\''"\*"'\'' /home/dev/.config/opencode/opencode.jsonc'

echo ""
echo "--- 6c. Wrapper bypass guard (self-install + absolute path) ---"
check "shell-warn.sh deployed to library" \
    E 'test -f /usr/local/lib/opencode-permissions-kit/shell-warn.sh'
check "shell-warn.sh sourced by umask profile" \
    E 'grep -q shell-warn.sh /etc/profile.d/opencode-permissions-kit-umask.sh'
check "interactive-shell warning hooked into .bashrc" \
    E 'grep -q "opencode-permissions-kit/shell-warn.sh" /home/dev/.bashrc'
# Simulate a self-reinstall: the official installer drops a real binary into
# ~/.opencode/bin. The guard must report it.
E 'sudo mkdir -p /home/dev/.opencode/bin && sudo cp /usr/local/lib/opencode-permissions-kit/bin/opencode /home/dev/.opencode/bin/opencode'
E 'sudo chmod 755 /home/dev/.opencode/bin/opencode && sudo chown dev:dev /home/dev/.opencode/bin/opencode'
check "shell-warn.sh warns about shadow binary" \
    E 'sh -c '\''HOME=/home/dev . /usr/local/lib/opencode-permissions-kit/shell-warn.sh'\'' 2>&1 | grep -q "wrapper bypass"'
check "wrapper start warns about shadow binary" \
    E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode --help 2>&1 | grep -q "self-installed opencode detected"'
# Cleaning the shadow directory restores the quiet state.
E 'rm -rf /home/dev/.opencode'
check "shell-warn.sh quiet after cleanup" \
    E 'test -z "$(sh -c '\''HOME=/home/dev . /usr/local/lib/opencode-permissions-kit/shell-warn.sh'\'' 2>&1)"'

echo ""
echo "--- 7. Git hooks ---"
check "core.hooksPath set" \
    E 'git config --global core.hooksPath | grep -q /usr/local/lib/opencode-permissions-kit/hooks'
check "Hooks directory exists" \
    E 'test -d /usr/local/lib/opencode-permissions-kit/hooks'

echo ""
echo "--- 7b. Hook applies project-level config (--cwd) ---"
E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "read": { "deploy-key.pem": "deny", "**/deploy-key.pem": "deny" },
        "edit": { "deploy-key.pem": "deny", "**/deploy-key.pem": "deny" }
    }
}
EOF'
E 'sudo touch /var/www/vhosts/test-project/deploy-key.pem'
E 'cd /var/www/vhosts/test-project && sudo /usr/local/lib/opencode-permissions-kit/hooks/post-commit' && \
    echo "  ${GREEN}OK${NC}  post-commit hook completed"
check_fail "post-commit applied project deny via --cwd" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/deploy-key.pem'
check "other project files still protected" \
    E '! sudo -u opencode test -r /var/www/vhosts/test-project/.env'

echo ""
echo "--- 7c. Hook prefers OPENCODE_LAUNCH_CWD over the git worktree root ---"
# subdir (created host-side, so the host cleanup can remove the test files) has
# its own config with an ALLOW for launch-key.pem. Its allow override only
# applies when the hook passes the launch dir as --cwd, which it does when the
# wrapper stamped OPENCODE_LAUNCH_CWD into the env.
E 'sudo tee /var/www/vhosts/test-project/subdir/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "read": { "launch-key.pem": "allow" },
        "edit": { "launch-key.pem": "allow" }
    }
}
EOF'
E 'sudo touch /var/www/vhosts/test-project/subdir/launch-key.pem'
# Without the env var the hook falls back to the worktree root: allow NOT applied.
E 'cd /var/www/vhosts/test-project && sudo /usr/local/lib/opencode-permissions-kit/hooks/post-commit' && \
    echo "  ${GREEN}OK${NC}  fallback run (no OPENCODE_LAUNCH_CWD) completed"
check_fail "fallback keeps launch-dir allow inactive" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/subdir/launch-key.pem'
# With the env var the hook uses the launch dir: allow applied.
E 'cd /var/www/vhosts/test-project && sudo OPENCODE_LAUNCH_CWD=/var/www/vhosts/test-project/subdir /usr/local/lib/opencode-permissions-kit/hooks/post-commit' && \
    echo "  ${GREEN}OK${NC}  launch-cwd run completed"
check "OPENCODE_LAUNCH_CWD activated launch-dir allow" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/subdir/launch-key.pem'

echo ""
echo "--- 8. Umask ---"
check "umask script deployed" \
    E 'test -f /etc/profile.d/opencode-permissions-kit-umask.sh'

echo ""
echo "--- 9. protect-projects idempotent ---"
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force' && \
    echo "  ${GREEN}OK${NC}  protect-projects.sh runs without error"

echo ""
echo "--- 10. Sensitive file created after install ---"
E 'echo "new-secret" | sudo tee /var/www/vhosts/test-project/.env.local > /dev/null'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check_fail ".env.local blocked after protect run" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env.local'

echo ""
echo "--- 10b. protect-projects cache (second run without --force) ---"
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh' && \
    echo "  ${GREEN}OK${NC}  protect-projects.sh (no --force) exits 0"

echo ""
echo "--- 10c. protect-projects chown step ---"
# .env is on the deny list; protect-projects.sh chowns opencode-owned files
# back to DEFAULT_USER:www-data
E 'sudo chown opencode:www-data /var/www/vhosts/test-project/.env' && \
    E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check "chown: .env re-owned to dev:www-data" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.env)" = "dev"'

echo ""
echo "--- 10d. protect-projects remove_acls (project allow override) ---"
E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "read": { "README.md": "allow", "**/README.md": "allow" },
        "edit": { "README.md": "allow", "**/README.md": "allow" }
    }
}
EOF'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force --cwd /var/www/vhosts/test-project'
check "allow-override: README.md readable for opencode" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.md'

echo ""
echo "--- 10e. protect-projects clears stale ACLs ---"
# Simulate a deny pattern that was removed from the config (README.txt is
# "ask" now): a leftover hard ACL deny must be cleared on the next run.
E 'sudo setfacl -m u:opencode:--- /var/www/vhosts/test-project/README.txt'
check_fail "stale ACL present before refresh" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.txt'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check "stale ACL cleared after refresh" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/README.txt'

echo ""
echo "--- 10f. protect-projects ddev compat (.ddev group/mask) ---"
# ddev recreates .ddev subdirs as the launching developer user with chmod 755,
# which collapses the ACL mask to r-x and blocks the opencode user (www-data).
# protect-projects must restore group www-data + rwx mask so ddev works.
E 'sudo mkdir -p /var/www/vhosts/test-project/.ddev/.homeadditions'
E 'echo "alias ll" > /var/www/vhosts/test-project/.ddev/.homeadditions/bash_aliases.example'
E 'sudo chown dev:dev /var/www/vhosts/test-project/.ddev /var/www/vhosts/test-project/.ddev/.homeadditions'
E 'sudo chmod 755 /var/www/vhosts/test-project/.ddev/.homeadditions /var/www/vhosts/test-project/.ddev/.homeadditions/bash_aliases.example'
E 'sudo setfacl -m g:www-data:rwx /var/www/vhosts/test-project/.ddev/.homeadditions /var/www/vhosts/test-project/.ddev/.homeadditions/bash_aliases.example'
E 'sudo setfacl -m mask::r-x /var/www/vhosts/test-project/.ddev/.homeadditions /var/www/vhosts/test-project/.ddev/.homeadditions/bash_aliases.example'
check_fail "ddev compat: .homeadditions blocked for opencode before fix" \
    E 'sudo -u opencode test -w /var/www/vhosts/test-project/.ddev/.homeadditions'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check "ddev compat: .homeadditions writable for opencode after fix" \
    E 'sudo -u opencode test -w /var/www/vhosts/test-project/.ddev/.homeadditions'
check "ddev compat: .ddev dir in www-data group" \
    E 'test "$(stat -c %G /var/www/vhosts/test-project/.ddev/.homeadditions)" = "www-data"'

echo ""
echo "--- 10g. protect-projects CWD config from ancestor (nested git worktree) ---"
# The governing opencode.jsonc sits at the project root, but git commands run
# in a nested worktree (repo/). The hook passes the worktree root as --cwd;
# protect-projects must find the ANCESTOR config, else the global *README.md
# deny wins and the project allow override is lost. (test-project/opencode.jsonc
# with the README.md allow was created in 10d.)
E 'sudo mkdir -p /var/www/vhosts/test-project/nested/repo'
E 'echo "readme" | sudo tee /var/www/vhosts/test-project/nested/repo/README.md > /dev/null'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force --cwd /var/www/vhosts/test-project/nested/repo'
check "ancestor config: README.md readable for opencode in nested worktree" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/nested/repo/README.md'

echo ""
echo "--- 11. update.sh re-deploys kit + preservation contract ---"
# Snapshot files that update.sh must NOT touch (use sudo to be independent of perms)
E 'sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1 > /tmp/sha-opencode-jsonc.before'
E 'sudo sha256sum /usr/local/lib/opencode-permissions-kit/bin/opencode | cut -d" " -f1 > /tmp/sha-binary.before'
E 'cat /etc/opencode-permissions-kit/projects.conf > /tmp/projects.conf.before'
# Create a copy of the repo files with a sentinel VERSION so we can observe the bump.
# We can't overwrite the bind-mounted VERSION reliably, so we copy update.sh + a
# sentinel VERSION into a temp dir and run it from there.
E 'rm -rf /tmp/update-test && mkdir -p /tmp/update-test/files && cp -r /home/dev/repo/files/* /tmp/update-test/files/ && echo "9.9.9-sentinel" > /tmp/update-test/VERSION'
E 'sudo bash /tmp/update-test/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh completed without prompts"
check "Wrapper still present after update" E 'test -x /usr/local/bin/opencode'
check "config.sh still present"            E 'test -x /usr/local/lib/opencode-permissions-kit/config.sh'
check "update.sh still present"            E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check "install.conf still present"         E 'test -f /etc/opencode-permissions-kit/install.conf'
check "projects.conf untouched"           E 'test -f /etc/opencode-permissions-kit/projects.conf'
check_fail ".env still blocked after update" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check "opencode.jsonc byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /home/opencode/.config/opencode/opencode.jsonc | cut -d" " -f1)" = "$(cat /tmp/sha-opencode-jsonc.before)"'
check "default-user deny-all config survives update" \
    E 'test -f /home/dev/.config/opencode/opencode.jsonc'
check "binary byte-identical (sha256 unchanged)" \
    E 'test "$(sudo sha256sum /usr/local/lib/opencode-permissions-kit/bin/opencode | cut -d" " -f1)" = "$(cat /tmp/sha-binary.before)"'
check "projects.conf content unchanged" \
    E 'test "$(cat /etc/opencode-permissions-kit/projects.conf)" = "$(cat /tmp/projects.conf.before)"'
check "install.conf VERSION bumped to sentinel" \
    E 'grep -q "VERSION=9.9.9-sentinel" /etc/opencode-permissions-kit/install.conf'
E 'rm -rf /tmp/update-test'

echo ""
echo "--- 11b. setup.conf -> install.conf legacy migration ---"
E 'sudo cp /etc/opencode-permissions-kit/install.conf /etc/opencode-permissions-kit/setup.conf' && \
    E 'sudo rm -f /etc/opencode-permissions-kit/install.conf'
check "legacy setup.conf created" E 'test -f /etc/opencode-permissions-kit/setup.conf'
check "install.conf removed for migration test" E '! test -f /etc/opencode-permissions-kit/install.conf'
E 'sudo bash /home/dev/repo/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh migrated setup.conf -> install.conf"
check "setup.conf removed after update" E '! test -f /etc/opencode-permissions-kit/setup.conf'
check "install.conf created by update" E 'test -f /etc/opencode-permissions-kit/install.conf'
check "install.conf contains DEFAULT_USER" \
    E 'grep -q "DEFAULT_USER=" /etc/opencode-permissions-kit/install.conf'

echo ""
echo "--- 11c. opencode binary upgrade (old -> new via update.sh --binary-path) ---"
# Downgrade the system binary to a pinned OLD version, then upgrade it back to
# the (cached) latest with update.sh --binary-path. This is the kit's upgrade
# entry point — `opencode upgrade` cannot work behind the wrapper.
E 'sudo cp /opencode-cache/opencode-'"$OLD_VERSION"'/opencode /usr/local/lib/opencode-permissions-kit/bin/opencode' && \
    echo "  ${GREEN}OK${NC}  system binary downgraded to $OLD_VERSION"
check "downgrade: system binary is $OLD_VERSION" \
    E 'test "$(sudo /usr/local/lib/opencode-permissions-kit/bin/opencode --version)" = "'"$OLD_VERSION"'"'
E 'sudo bash /home/dev/repo/files/update.sh --yes --binary-path /opencode-cache/opencode-'"$OC_VERSION"'/opencode' && \
    echo "  ${GREEN}OK${NC}  update.sh --binary-path completed"
check "upgrade: system binary is latest ($OC_VERSION)" \
    E 'test "$(sudo /usr/local/lib/opencode-permissions-kit/bin/opencode --version)" = "'"$OC_VERSION"'"'
check "upgrade: version actually changed" \
    E 'test "'"$OLD_VERSION"'" != "'"$OC_VERSION"'"'
check "wrapper still present after binary upgrade" E 'test -x /usr/local/bin/opencode'
check "binary still root:opencode after binary upgrade" \
    E 'test "$(stat -c %U:%G /usr/local/lib/opencode-permissions-kit/bin/opencode)" = "root:opencode"'
check "kit scripts still deployed after binary upgrade" E 'test -x /usr/local/lib/opencode-permissions-kit/update.sh'
check_fail ".env still blocked after binary upgrade" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'
check_fail "new binary writable by opencode user" \
    E 'sudo -u opencode sh -c "test -w /usr/local/lib/opencode-permissions-kit/bin/opencode"'

echo ""
echo "--- 11d. pre-0.0.10 layout -> renamed layout migration ---"
# Simulate a 0.0.9-style install: move the new library + config dir to the
# old names, re-create the old sudoers symlink, then run update.sh from the
# repo checkout and assert it migrates everything back to the renamed layout
# (binary moved, configs preserved, old dirs removed, symlinks re-pointed).
E 'sudo cp -r /etc/opencode-permissions-kit /etc/opencode' && \
    E 'sudo cp -r /usr/local/lib/opencode-permissions-kit /usr/local/lib/opencode' && \
    E 'sudo rm -rf /etc/opencode-permissions-kit /usr/local/lib/opencode-permissions-kit' && \
    E 'sudo ln -sf /etc/opencode/sudoers /etc/sudoers.d/opencode' && \
    E 'sudo cp /etc/profile.d/opencode-permissions-kit-umask.sh /etc/profile.d/opencode-umask.sh'
check "migration: old /etc/opencode present"      E 'test -d /etc/opencode'
check "migration: old lib present"                E 'test -d /usr/local/lib/opencode'
E 'sudo bash /home/dev/repo/files/update.sh --yes' && \
    echo "  ${GREEN}OK${NC}  update.sh migrated old layout -> renamed layout"
check "migration: install.conf at new path"       E 'test -f /etc/opencode-permissions-kit/install.conf'
check "migration: projects.conf at new path"      E 'test -f /etc/opencode-permissions-kit/projects.conf'
check "migration: projects.conf content preserved" \
    E 'test "$(cat /etc/opencode-permissions-kit/projects.conf)" = "$(cat /tmp/projects.conf.before)"'
check "migration: old /etc/opencode removed"      E '! test -e /etc/opencode'
check "migration: old lib removed"                E '! test -e /usr/local/lib/opencode'
check "migration: binary moved to new path"       E 'sudo test -x /usr/local/lib/opencode-permissions-kit/bin/opencode'
check "migration: binary still runs" \
    E 'test "$(sudo /usr/local/lib/opencode-permissions-kit/bin/opencode --version)" = "'"$OC_VERSION"'"'
check "migration: wrapper -> new lib" \
    E 'test "$(readlink /usr/local/bin/opencode)" = "/usr/local/lib/opencode-permissions-kit/wrapper"'
check "migration: ddev shim -> new lib" \
    E 'test "$(readlink /usr/local/bin/ddev)" = "/usr/local/lib/opencode-permissions-kit/bin/ddev"'
check "migration: old sudoers symlink removed"    E '! test -e /etc/sudoers.d/opencode'
check "migration: new sudoers symlink present"     E 'test -L /etc/sudoers.d/opencode-permissions-kit'
check "migration: old umask profile removed"      E '! test -e /etc/profile.d/opencode-umask.sh'
check "migration: new umask profile present"      E 'test -f /etc/profile.d/opencode-permissions-kit-umask.sh'
check "migration: hooksPath -> new lib" \
    E 'git config --global core.hooksPath | grep -q /usr/local/lib/opencode-permissions-kit/hooks'
check_fail ".env still blocked after migration" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'

echo ""
echo "--- 12. config.sh adds a project non-interactively ---"
E 'sudo mkdir -p /var/www/vhosts/extra-project' && \
    E 'sudo touch /var/www/vhosts/extra-project/.env'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes projects add /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh add completed"
check "extra-project in projects.conf" \
    E 'grep -q /var/www/vhosts/extra-project /etc/opencode-permissions-kit/projects.conf'
check_fail "extra-project .env blocked after config add" \
    E 'sudo -u opencode test -r /var/www/vhosts/extra-project/.env'

echo ""
echo "--- 12b. config.sh projects remove ---"
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes projects remove /var/www/vhosts/extra-project' && \
    echo "  ${GREEN}OK${NC}  config.sh remove completed"
check "extra-project removed from projects.conf" \
    E '! grep -q /var/www/vhosts/extra-project /etc/opencode-permissions-kit/projects.conf'

echo ""
echo "--- 12c. config.sh git-config toggle ---"
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes git-config on' && \
    echo "  ${GREEN}OK${NC}  git-config on completed"
check "git-config ON: .git/config deny rule active" \
    E 'sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config ON: status reports ON" \
    E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status 2>&1 | grep -q "ON"'
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes git-config off' && \
    echo "  ${GREEN}OK${NC}  git-config off completed"
check "git-config OFF: no active .git/config rule" \
    E '! sudo grep -qE "^[[:space:]]*\"\.git/config\"" /home/opencode/.config/opencode/opencode.jsonc'
check "git-config OFF: status reports OFF" \
    E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status 2>&1 | grep -q "OFF"'

echo ""
echo "--- 12d. config.sh interactive menu (displays) ---"
E 'sudo mkdir -p /var/www/vhosts/menu-project' && \
    E 'sudo touch /var/www/vhosts/menu-project/.env'
# The interactive menu uses read </dev/tty which blocks in a non-TTY
# environment. We capture whatever output appears within 3 seconds before
# timeout kills the process. At minimum the banner + current settings +
# projects list should print. The full menu options ([2], [3], [q]) may
# or may not appear depending on buffering and how far the script gets
# before the read blocks.
E 'timeout 3 sudo bash /usr/local/lib/opencode-permissions-kit/config.sh < /dev/null > /tmp/menu-out.txt 2>&1 || true'
E 'sudo chown dev /tmp/menu-out.txt'
check "menu: banner shown" \
    E 'grep -q "opencode permissions kit" /tmp/menu-out.txt'
check "menu: shows current settings" \
    E 'grep -q "Current settings" /tmp/menu-out.txt'
check "menu: project list shown" \
    E 'grep -q "\[1\]" /tmp/menu-out.txt'

echo ""
echo "--- 12e. wrapper actual invocation ---"
# Valid CWD: wrapper should show SECURED banner
E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-valid.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper ran from valid CWD"
check "wrapper: SECURED banner from valid CWD" \
    E 'grep -q "SECURED BY opencode permissions kit" /tmp/wrapper-valid.txt'
# Invalid CWD: wrapper should refuse
E 'cd /tmp && /usr/local/bin/opencode 2>&1 | tee /tmp/wrapper-invalid.txt; test $? -ne 0' && \
    echo "  ${GREEN}OK${NC}  wrapper refused from invalid CWD"
check "wrapper: ERROR banner from invalid CWD" \
    E 'grep -q "ERROR: opencode cannot be started here" /tmp/wrapper-invalid.txt'
check "wrapper stamps OPENCODE_LAUNCH_CWD" \
    E 'grep -q OPENCODE_LAUNCH_CWD /usr/local/lib/opencode-permissions-kit/wrapper'

echo ""
echo "--- 12e2. Container tools: docker group escalation ---"
check "sudoers grants (opencode : docker) RunAs" \
    E 'sudo -l | grep -q "opencode : docker"'
check "wrapper uses sudo -u opencode -g for container group" \
    E 'grep -q "sudo -u opencode -g" /usr/local/lib/opencode-permissions-kit/wrapper'
check "status.sh reports docker group" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "docker group"'
# The e2e container has no docker group yet → wrapper must warn + fall back.
E 'cd /var/www/vhosts/test-project && echo "" | /usr/local/bin/opencode -g docker --help 2>&1 | tee /tmp/wrapper-g.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper -g docker ran without a docker group"
check "wrapper -g docker: banner shown" \
    E 'grep -q "SECURED BY opencode permissions kit" /tmp/wrapper-g.txt'
check "wrapper -g docker: absent-group warning" \
    E 'grep -q "does not exist — running without container group" /tmp/wrapper-g.txt'
# Create the docker group so the escalation path is real.
E 'sudo groupadd docker' && \
    echo "  ${GREEN}OK${NC}  docker group created"
check "sudo -u opencode -g docker runs the binary (RunAs granted)" \
    E 'sudo -u opencode -g docker /usr/local/lib/opencode-permissions-kit/bin/opencode --version'
check "opencode user NOT in docker group directly (escalation only)" \
    E '! id -nG opencode | grep -q docker'
# Project explicitly enables docker → wrapper auto-detects and asks.
E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "bash": { "docker *": "allow" }
    }
}
EOF'
E 'cd /var/www/vhosts/test-project && printf "Y\n" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-auto.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper auto-detection (accepted) ran"
check "wrapper auto-detect: container tools advisory" \
    E 'grep -q "Container tools enabled by this project" /tmp/wrapper-auto.txt'
check "wrapper auto-detect: docker group prompt" \
    E 'grep -q "Run opencode with the docker group" /tmp/wrapper-auto.txt'
check "wrapper auto-detect: accepted → docker group exec" \
    E 'grep -q "opencode will run with the docker group" /tmp/wrapper-auto.txt'
E 'cd /var/www/vhosts/test-project && printf "n\n" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-auto-n.txt' && \
    echo "  ${GREEN}OK${NC}  wrapper auto-detection (declined) ran"
check_fail "wrapper auto-detect: declined → no docker group exec" \
    E 'grep -q "opencode will run with the docker group" /tmp/wrapper-auto-n.txt'

echo ""
echo "--- 12f. uninstall.sh --dry-run (no-op) ---"
E 'bash /usr/local/lib/opencode-permissions-kit/uninstall.sh --yes --dry-run' && \
    echo "  ${GREEN}OK${NC}  uninstall --dry-run completed"
check "dry-run: wrapper still exists"   E 'test -e /usr/local/bin/opencode'
check "dry-run: library still exists"   E 'test -e /usr/local/lib/opencode-permissions-kit'
check "dry-run: /etc/opencode-permissions-kit intact"  E 'test -e /etc/opencode-permissions-kit'
check "dry-run: user still exists"      E 'id opencode'

echo ""
echo "--- 12g. Audit log ---"
check "log dir exists" \
    E 'sudo test -d /var/log/opencode-permissions-kit'
check "log file exists" \
    E 'sudo test -f /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "log is root-owned mode 640" \
    E 'test "$(sudo stat -c %U:%a /var/log/opencode-permissions-kit/opencode-permissions-kit.log)" = "root:640"'
check "log dir is root-owned mode 750" \
    E 'test "$(sudo stat -c %U:%a /var/log/opencode-permissions-kit)" = "root:750"'
check "default user can read log file" \
    E 'test -r /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "install events logged" \
    E 'sudo grep -q "install complete" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "protect-projects events logged" \
    E 'sudo grep -q "protect-projects run complete" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "ACL batch events logged" \
    E 'sudo grep -q "setfacl deny" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "update events logged" \
    E 'sudo grep -q "update complete" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check "binary upgrade events logged" \
    E 'sudo grep -q "opencode binary upgraded" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check_fail "opencode user cannot read log file" \
    E 'sudo -u opencode test -r /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
check_fail "opencode user cannot enter log dir" \
    E 'sudo -u opencode test -x /var/log/opencode-permissions-kit'

echo ""
echo "--- 12h. ddev delegation shim ---"
# The kit shim (/usr/local/bin/ddev) re-execs every `ddev` the opencode agent
# invokes as the DEFAULT_USER (dev) via sudoers. The stub at /usr/bin/ddev
# records who actually ran it. Contrast:
#   - opencode runs the REAL ddev directly  -> stub records "opencode"
#   - opencode runs the SHIM (via /usr/local/bin/ddev) -> stub records "dev"
#   - dev runs the SHIM (passthrough)        -> stub records "dev"
# The opencode->dev flip proves delegation; the dev passthrough proves the shim
# does not loop or error for the developer themselves.
#
# The shim gates on `id -un = opencode` (NOT on the docker group), so we run the
# opencode cases with plain `sudo -u opencode` (no -g) — the kit's sudoers only
# grants dev the (opencode:docker) RunAs for the opencode binary itself, not for
# arbitrary commands, and -g docker is irrelevant to the shim logic anyway.
E 'sudo rm -f /tmp/ddev-stub.out'
E 'sudo -u opencode /usr/bin/ddev direct-opencode' && \
    echo "  ${GREEN}OK${NC}  opencode ran the real ddev directly"
check "direct: stub records opencode as the invoking user" \
    E 'test "$(cat /tmp/ddev-stub.out | head -1)" = "opencode"'
check "direct: stub received args" \
    E 'grep -q "direct-opencode" /tmp/ddev-stub.out'

E 'sudo rm -f /tmp/ddev-stub.out'
E 'sudo -u opencode /usr/local/bin/ddev delegated-start' && \
    echo "  ${GREEN}OK${NC}  opencode ran the kit shim (delegated)"
check "delegated: stub records dev (not opencode) as the invoking user" \
    E 'test "$(cat /tmp/ddev-stub.out | head -1)" = "dev"'
check "delegated: stub received args" \
    E 'grep -q "delegated-start" /tmp/ddev-stub.out'
check_fail "delegated: opencode did NOT run ddev directly" \
    E 'grep -q "^opencode$" /tmp/ddev-stub.out'

# Passthrough: the developer keeps their own ddev — the shim must not loop.
E 'sudo rm -f /tmp/ddev-stub.out'
E '/usr/local/bin/ddev passthrough-dev' && \
    echo "  ${GREEN}OK${NC}  dev ran the shim (passthrough)"
check "passthrough: stub records dev (no delegation for the developer)" \
    E 'test "$(cat /tmp/ddev-stub.out | head -1)" = "dev"'
check "passthrough: stub received args" \
    E 'grep -q "passthrough-dev" /tmp/ddev-stub.out'

# status.sh reports the shim.
check "status.sh reports ddev shim active" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "ddev delegation shim"'
check "status.sh reports the real ddev path" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "/usr/bin/ddev"'

echo ""
echo "--- 12i. Rootless container backend (podman) — Phase 2 provisioning ---"
# This is the real-rootless environment test (docs/design/DOCKER-ROOTLESS.md §9.1).
# It proves the core value proposition: a rootless container started by the
# opencode user accesses bind-mounted files as the opencode host UID, so the
# kit's hard ACL deny (u:opencode:--- on .env) holds INSIDE the container.
# It also exercises Phase 2: config.sh container-backend podman-rootless
# provisions the backend (installs packages via setup-container-backend.sh,
# allocates subuid/subgid, re-renders the sudoers, updates install.conf).
#
# Rootless podman needs nested user namespaces + uidmap. The e2e container runs
# --privileged, which usually suffices, but some runner kernels disallow it.
# If provisioning fails or `podman info` fails as the opencode user, every
# check in this section is SKIPped (not failed) so CI stays green.

_rootless_ok=true

# Nested-userns adaptation (only when the OUTER docker is rootless). On such a
# host this container itself runs in a user namespace (uid_map `0 <uid> 1 /
# 1 <n> 65536`), so the kit's default subuid allocation (231072+) is OUTSIDE
# the container's uid map and podman-rootless provisioning's `newuidmap` write
# fails with EPERM. Seeding an in-range range first works because
# setup-container-backend.sh's allocate_range() KEEPS an existing entry. No-op
# on a rootful host, which keeps CI on the kit's true default path.
if [ "$E2E_HOST_LAYOUT" = "rootless" ]; then
    echo "  ${CYAN}Nested userns (rootless host docker) — seeding in-range subuid/subgid${NC}"
    E 'sudo sh -c '\''printf "opencode:4096:60000\n" > /etc/subuid; printf "opencode:4096:60000\n" > /etc/subgid'\'''
    check "12i: in-range subuid/subgid seeded for opencode (nested layout)" \
        E 'grep -q "^opencode:4096:60000$" /etc/subuid && grep -q "^opencode:4096:60000$" /etc/subgid'
fi

# 12i.1 switch to podman-rootless via config.sh (Phase 2 provisioning).
# This installs podman+uidmap+slirp4netns, allocates subuid/subgid, updates
# install.conf, and re-renders the sudoers — all via setup-container-backend.sh.
# Run config.sh from the REPO checkout so we test the local Phase 2 code, not
# a potentially stale installed copy.
if ! E 'sudo bash /home/dev/repo/files/config.sh --yes container-backend podman-rootless >/tmp/config-backend.log 2>&1'; then
    echo "  ${YELLOW}SKIP${NC}  12i: backend provisioning failed ($(E 'tail -1 /tmp/config-backend.log' 2>/dev/null || echo unknown))"
    _rootless_ok=false
    skipped=$((skipped + 1))
fi

# 12i.2 verify install.conf + sudoers were updated by config.sh.
if [ "$_rootless_ok" = true ]; then
    check "12i: install.conf records CONTAINER_BACKEND=podman-rootless" \
        E 'grep -q "^CONTAINER_BACKEND=podman-rootless" /etc/opencode-permissions-kit/install.conf'
    check "12i: sudoers strips (opencode:docker) for the podman-rootless backend" \
        E '! sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit'
    check "12i: sudoers keeps the base (opencode) RunAs" \
        E 'sudo grep -q "(opencode) NOPASSWD" /etc/sudoers.d/opencode-permissions-kit'
    check "12i: sudoers still has the ddev delegation rule" \
        E 'sudo grep -q "NOPASSWD: /usr/bin/ddev" /etc/sudoers.d/opencode-permissions-kit'
fi

# 12i.3 verify podman + subuid/subgid were provisioned by the setup helper.
if [ "$_rootless_ok" = true ]; then
    check "12i: podman installed by setup helper" \
        E 'command -v podman && podman --version'
    check "12i: subuid range allocated for opencode" \
        E 'grep -q "^opencode:" /etc/subuid'
    check "12i: subgid range allocated for opencode" \
        E 'grep -q "^opencode:" /etc/subgid'
fi

# 12i.4 rootless podman usable as the opencode user (nested userns check).
if [ "$_rootless_ok" = true ]; then
    E 'sudo mkdir -p /run/user/$(id -u opencode) && sudo chown opencode:opencode /run/user/$(id -u opencode) && sudo chmod 700 /run/user/$(id -u opencode)'
    if E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman info >/tmp/podman-info.out 2>&1"'; then
        check "12i: rootless podman works as the opencode user (nested userns)" \
            E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman info >/dev/null 2>&1"'
    else
        echo "  ${YELLOW}SKIP${NC}  12i: nested user namespaces not available ($(E 'tail -1 /tmp/podman-info.out' 2>/dev/null || echo unknown))"
        _rootless_ok=false
        skipped=$((skipped + 1))
    fi
fi

# 12i.5 the §9.1 proof — ACL deny survives a rootless bind mount.
if [ "$_rootless_ok" = true ]; then
    check "12i: .env still carries the u:opencode:--- ACL deny" \
        E 'sudo getfacl -p /var/www/vhosts/test-project/.env 2>/dev/null | grep -q "user:opencode:---"'
    if E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman pull alpine:latest >/tmp/podman-pull.out 2>&1"'; then
        check_fail "12i §9.1: rootless container CANNOT read ACL-denied .env via bind mount" \
            E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman run --rm -v /var/www/vhosts/test-project:/app alpine:latest cat /app/.env"'
        check "12i §9.1: rootless container CAN read non-denied index.php via bind mount" \
            E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman run --rm -v /var/www/vhosts/test-project:/app alpine:latest cat /app/index.php" | grep -q "normal source code"'
        check_fail "12i §9.1: host-side opencode also denied .env (confirms ACL, not missing file)" \
            E 'sudo -u opencode cat /var/www/vhosts/test-project/.env'
    else
        echo "  ${YELLOW}SKIP${NC}  12i §9.1: could not pull alpine (no network?) — $(sudo tail -1 /tmp/podman-pull.out 2>/dev/null || echo unknown)"
        skipped=$((skipped + 2))
    fi
fi

# 12i.6 status.sh reports the provisioned podman-rootless backend.
if [ "$_rootless_ok" = true ]; then
    check "12i: status.sh reports the podman-rootless backend" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "backend:    podman-rootless"'
    check "12i: status.sh reports the podman CLI as installed" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "podman CLI:.*installed"'
fi

# 12i.7 wrapper auto-detect on the podman-CLI path.
if [ "$_rootless_ok" = true ]; then
    E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "bash": { "docker *": "allow" }
    }
}
EOF'
    E 'cd /var/www/vhosts/test-project && printf "Y\n" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-podman.txt' && \
        echo "  ${GREEN}OK${NC}  wrapper podman auto-detection (accepted) ran"
    check "12i: wrapper podman auto-detect: container tools advisory" \
        E 'grep -q "Container tools enabled by this project" /tmp/wrapper-podman.txt'
    check "12i: wrapper podman auto-detect: podman-rootless prompt" \
        E 'grep -q "Run opencode with the podman-rootless backend" /tmp/wrapper-podman.txt'
    check "12i: wrapper podman auto-detect: accepted -> podman-rootless exec message" \
        E 'grep -q "opencode will run with the podman-rootless backend" /tmp/wrapper-podman.txt'
    check_fail "12i: wrapper podman path does NOT mention the docker group" \
        E 'grep -q "opencode will run with the docker group" /tmp/wrapper-podman.txt'
    check_fail "12i: wrapper podman path does NOT warn about an absent docker group" \
        E 'grep -q "does not exist — running without container group" /tmp/wrapper-podman.txt'
    check "12i: opencode user NOT in the docker group (rootless grants no group)" \
        E '! id -nG opencode | tr " " "\n" | grep -qx docker'
fi

# 12i.8 config.sh container-backend status subcommand.
if [ "$_rootless_ok" = true ]; then
    check "12i: config.sh container-backend status reports podman-rootless" \
        E 'sudo bash /home/dev/repo/files/config.sh container-backend status 2>&1 | grep -q "podman-rootless"'
fi

# 12i.9 teardown the rootless runtime so section 13's uninstall can remove
# the opencode user. Switch back to docker-group + manual podman storage cleanup.
if [ "$_rootless_ok" = true ]; then
    E 'sudo bash /home/dev/repo/files/config.sh --yes container-backend docker-group >/tmp/config-teardown.log 2>&1' || true
    check "12i: config.sh switches back to docker-group" \
        E 'grep -q "^CONTAINER_BACKEND=docker-group" /etc/opencode-permissions-kit/install.conf'
    # Manual podman storage cleanup (userdel -r fails while storage is live).
    E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/$(id -u opencode) podman system reset --force >/dev/null 2>&1" || true'
    E 'sudo pkill -u opencode 2>/dev/null || true'
    E 'sudo rm -rf /run/user/$(id -u opencode) /home/opencode/.local 2>/dev/null || true'
fi

echo ""
echo "--- 12j. status.sh leak scan (report-only, PROOF-3 H2) ---"
# Scratch copies matching the deny patterns must be reported; a renamed copy
# must stay invisible; and the scan must never touch files outside the
# project roots (no ACL, no delete — report-only).
E 'mkdir -p /tmp/leak-e2e/sub /tmp/leak-e2e-clean && printf "SECRET=1\n" > /tmp/leak-e2e/.env && printf "key\n" > /tmp/leak-e2e/sub/backup.pem && printf "<?php\n" > /tmp/leak-e2e/settings.php && printf "renamed copy\n" > /tmp/leak-e2e/notes.txt'
check "12j: leak scan section is printed" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "Leak scan"'
check "12j: deny-pattern copy in /tmp is reported" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/.env"'
check "12j: nested deny-pattern copy is reported" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/sub/backup.pem"'
check "12j: hit counter is shown" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -Eq "[0-9]+ match\(es\)"'
check_fail "12j: renamed copy stays invisible (name tripwire, no DLP)" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/notes.txt"'
check_fail "12j: report-only — no ACL is applied outside the roots" \
    E 'getfacl -p /tmp/leak-e2e/.env 2>/dev/null | grep -q "user:opencode"'
check "12j: LEAK_SCAN_DIRS override narrows the scan (clean dir -> no matches)" \
    E 'LEAK_SCAN_DIRS=/tmp/leak-e2e-clean /usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "no matches"'
check_fail "12j: LEAK_SCAN_DIRS override — hits outside the override are not reported" \
    E 'LEAK_SCAN_DIRS=/tmp/leak-e2e-clean /usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "leak-e2e/.env"'
check "12j: root run logs the finding to the audit log" \
    E 'sudo /usr/local/lib/opencode-permissions-kit/status.sh >/dev/null 2>&1; sudo grep -q "leak scan" /var/log/opencode-permissions-kit/opencode-permissions-kit.log'
E 'rm -rf /tmp/leak-e2e /tmp/leak-e2e-clean'

echo ""
echo "--- 12k. ddev sandbox mode (transactional, DDEV-SANDBOX design doc / PROOF-3 H3) ---"
# 12k.0 the installed config.sh needs the sudoers template next to it.
check "12k: sudoers.template deployed to the library" \
    E 'sudo test -f /usr/local/lib/opencode-permissions-kit/sudoers.template'
# 12k.1 switching to sandbox is REFUSED on the docker-group backend (hard gate).
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes ddev-mode sandbox >/tmp/ddev-mode-refuse.log 2>&1' || true
check "12k: sandbox refused on docker-group backend" \
    E 'grep -q "requires a rootless container backend" /tmp/ddev-mode-refuse.log'
check_fail "12k: install.conf has no DDEV_MODE=sandbox after refusal" \
    E 'grep -q "^DDEV_MODE=sandbox" /etc/opencode-permissions-kit/install.conf'
check "12k: delegated sudoers rule still present after refusal" \
    E 'sudo grep -q "^opencode[[:space:]]*ALL=(dev)" /etc/opencode-permissions-kit/sudoers'

# 12k.2 fake a rootless backend (no daemon needed for the stub) and switch.
E "sudo sed -i 's/^CONTAINER_BACKEND=.*/CONTAINER_BACKEND=docker-rootless/' /etc/opencode-permissions-kit/install.conf"
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes ddev-mode sandbox >/tmp/ddev-mode-apply.log 2>&1' || true
check "12k: ddev-mode sandbox applied" \
    E 'grep -q "ddev mode switched to .sandbox." /tmp/ddev-mode-apply.log'
check "12k: install.conf records DDEV_MODE=sandbox" \
    E 'grep -q "^DDEV_MODE=sandbox" /etc/opencode-permissions-kit/install.conf'
check "12k: sudoers grants the transaction helper" \
    E 'sudo grep -q "ddev-transaction.sh" /etc/opencode-permissions-kit/sudoers'
check_fail "12k: sudoers delegation rule (RunAs dev) removed in sandbox mode" \
    E 'sudo grep -Eq "^opencode[[:space:]]+ALL=\(dev\)" /etc/opencode-permissions-kit/sudoers'
check "12k: sandbox ddev home provisioned" \
    E 'sudo test -d /home/opencode/.ddev'
check "12k: rewrite list deployed" \
    E 'test -f /etc/opencode-permissions-kit/ddev-rewrites.conf'
check "12k: --yes applied the router-port sysctl (or ports already unprivileged)" \
    E 'test -f /etc/sysctl.d/99-ddev-rootless.conf || [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)" -le 80 ]'
check "12k: mkcert provisioning was attempted (reused/new/absent — env-dependent)" \
    E 'grep -Eq "mkcert CA reused from|no existing CA found|mkcert not installed" /tmp/ddev-mode-apply.log'
check "12k: status.sh reports sandbox mode" \
    E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "sandbox"'

# 12k.3 TYPO3-layout fixture + deny baseline for the transaction tests.
E 'mkdir -p /var/www/vhosts/test-project/config/system'
E 'printf "<?php\n" > /var/www/vhosts/test-project/config/system/settings.php'
E 'printf "" > /var/www/vhosts/test-project/config/system/additional.php'
E 'mkdir -p /var/www/vhosts/test-project/.ddev'
E 'printf "apiVersion: ddev.io/v1alpha1\n" > /var/www/vhosts/test-project/.ddev/config.yaml'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check "12k: baseline — settings.php ACL-denied before the transaction" \
    E 'sudo getfacl -p /var/www/vhosts/test-project/config/system/settings.php 2>/dev/null | grep -q "user:opencode:---"'

# 12k.4 mutating subcommand goes through the transaction and runs as opencode.
E 'sudo rm -f /tmp/ddev-stub.out'
E 'sudo -u opencode sh -c "cd /var/www/vhosts/test-project && ddev start txn-test"' && \
    echo "  ${GREEN}OK${NC}  sandbox ddev start ran"
check "12k: mutating run executed as opencode (never dev)" \
    E 'test "$(cat /tmp/ddev-stub.out | head -1)" = "opencode"'
check "12k: mutating run received the subcommand + args" \
    E 'grep -q "start txn-test" /tmp/ddev-stub.out'
check "12k: .env stays UNREADABLE during the transaction (window excludes secrets)" \
    E 'grep -q "env-denied" /tmp/ddev-stub.out'
check "12k: CLOSE restored the settings.php deny" \
    E 'sudo getfacl -p /var/www/vhosts/test-project/config/system/settings.php 2>/dev/null | grep -q "user:opencode:---"'
check "12k: CLOSE handed .ddev back to the developer" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.ddev/config.yaml)" = "dev"'
check_fail "12k: no transaction stamp left open" \
    E 'ls /run/opencode-permissions-kit/ddev-txn/*.open 2>/dev/null'

# 12k.5 read-only subcommand bypasses the transaction (direct exec as opencode).
E 'sudo rm -f /tmp/ddev-stub.out'
E 'sudo -u opencode /usr/local/bin/ddev describe' && \
    echo "  ${GREEN}OK${NC}  read-only ddev describe ran"
check "12k: read-only run executed as opencode" \
    E 'test "$(cat /tmp/ddev-stub.out | head -1)" = "opencode"'
check "12k: read-only run received the subcommand" \
    E 'grep -q "describe" /tmp/ddev-stub.out'
check_fail "12k: read-only run left no stamp (no transaction)" \
    E 'ls /run/opencode-permissions-kit/ddev-txn/*.open 2>/dev/null'

# 12k.6 self-heal of a killed transaction (stranded ownership + dir ACL).
E 'sudo chown -R opencode:www-data /var/www/vhosts/test-project/.ddev'
E 'sudo setfacl -m u:opencode:rwx /var/www/vhosts/test-project/config/system'
# Stamp name mirrors the helper: printf %s "/var/www/vhosts" | tr -c 'A-Za-z0-9' '_'
# (the LEADING slash also becomes an underscore).
E 'sudo touch /run/opencode-permissions-kit/ddev-txn/_var_www_vhosts.open'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check_fail "12k: heal gated — .ddev NOT chowned back while a stamp is open" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.ddev/config.yaml)" = "dev"'
check "12k: stale dir ACL cleared even with stamp open (clear_stale_acls)" \
    E '! sudo getfacl -p /var/www/vhosts/test-project/config/system 2>/dev/null | grep -q "user:opencode:rwx"'
E 'sudo rm -f /run/opencode-permissions-kit/ddev-txn/_var_www_vhosts.open'
E 'sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force'
check "12k: heal restored .ddev ownership after the stamp cleared" \
    E 'test "$(stat -c %U /var/www/vhosts/test-project/.ddev/config.yaml)" = "dev"'

# 12k.7 switch back to delegated + restore the docker-group backend.
E 'sudo bash /usr/local/lib/opencode-permissions-kit/config.sh --yes ddev-mode delegated >/tmp/ddev-mode-back.log 2>&1' || true
check "12k: ddev-mode delegated applied" \
    E 'grep -q "ddev mode switched to .delegated." /tmp/ddev-mode-back.log'
check "12k: delegated sudoers rule restored" \
    E 'sudo grep -Eq "^opencode[[:space:]]+ALL=\(dev\)[[:space:]]+NOPASSWD: /usr/bin/ddev$" /etc/opencode-permissions-kit/sudoers'
check_fail "12k: transaction rule removed in delegated mode" \
    E 'sudo grep -q "ddev-transaction.sh" /etc/opencode-permissions-kit/sudoers'
E "sudo sed -i 's/^CONTAINER_BACKEND=.*/CONTAINER_BACKEND=docker-group/' /etc/opencode-permissions-kit/install.conf"

echo ""
echo "--- 13. Uninstall & cleanup verification ---"
E 'bash /usr/local/lib/opencode-permissions-kit/uninstall.sh --yes' && \
    echo "  ${GREEN}OK${NC}  uninstall.sh completed"
check_fail "Wrapper removed"          E 'test -e /usr/local/bin/opencode'
check_fail "ddev shim removed"       E 'test -e /usr/local/bin/ddev'
check_fail "Library removed"          E 'test -e /usr/local/lib/opencode-permissions-kit'
check_fail "legacy lib removed"       E 'test -e /usr/local/lib/opencode'
check_fail "Sudoers removed"          E 'test -e /etc/sudoers.d/opencode-permissions-kit'
check_fail "legacy sudoers removed"   E 'test -e /etc/sudoers.d/opencode'
check_fail "/etc/opencode-permissions-kit removed"    E 'test -e /etc/opencode-permissions-kit'
check_fail "legacy /etc/opencode removed"             E 'test -e /etc/opencode'
check_fail "Umask removed"            E 'test -e /etc/profile.d/opencode-permissions-kit-umask.sh'
check_fail "legacy umask removed"     E 'test -e /etc/profile.d/opencode-umask.sh'
check_fail "opencode user removed"    E 'id opencode'
check_fail "core.hooksPath unset"     E 'git config --global --get core.hooksPath'
check_fail "Project ACLs cleaned"     E 'getfacl -p /var/www/vhosts/test-project/.env 2>/dev/null | grep -q "user:opencode"'
check_fail "Audit log removed"        E 'test -e /var/log/opencode-permissions-kit'

e2e_finish
