#!/bin/sh
# e2e/run.sh — End-to-end test in Docker container
# Builds an Ubuntu image, installs opencode + our kit, verifies protection.
# Run from repo root: ./tests/e2e/run.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

IMAGE="opencode-e2e"
CONTAINER="opencode-e2e-test"

failures=0
passed=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        failures=$((failures + 1))
    fi
}

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${RED}FAIL${NC}  $desc (expected failure, got success)"
        failures=$((failures + 1))
    else
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    fi
}

cleanup() {
    docker rm -f "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "${CYAN}=============================================${NC}"
echo "${CYAN}  opencode permissions kit — E2E Test${NC}"
echo "${CYAN}=============================================${NC}"
echo ""

echo "--- opencode binary cache (version-keyed) ---"
# The official installer fetches the opencode binary from the internet on every
# run. To avoid re-downloading the (large) binary each time, we download it once
# per opencode version on the HOST and mount it into the container read-only
# (the installer supports --binary <path>, which skips the download but keeps
# the PATH-modification behavior the kit's install.sh depends on).
OC_CACHE_DIR="$SCRIPT_DIR/cache"
mkdir -p "$OC_CACHE_DIR"

# Resolve the current opencode version from GitHub releases (tiny request). If
# the endpoint is unreachable, fall back to the newest cached version so repeat
# runs work offline.
OC_VERSION=""
OC_VERSION=$(curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 30 \
    https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
if [ -z "$OC_VERSION" ]; then
    OC_VERSION=$(ls -1d "$OC_CACHE_DIR"/opencode-* 2>/dev/null | sed 's|.*/opencode-||' | sort -V | tail -1)
    if [ -n "$OC_VERSION" ]; then
        echo "  ${YELLOW}WARNING: version endpoint unreachable - using cached opencode $OC_VERSION${NC}"
    else
        echo "  ${RED}FAIL${NC}  cannot resolve opencode version and no cached version available."
        exit 1
    fi
fi

# Detect the release asset name for this host (mirrors the official installer).
os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
    darwin*) os="darwin" ;;
    linux*) os="linux" ;;
    *) echo "  ${RED}FAIL${NC}  unsupported OS: $os"; exit 1 ;;
esac
arch=$(uname -m)
if [ "$arch" = "aarch64" ]; then arch="arm64"; fi
if [ "$arch" = "x86_64" ]; then arch="x64"; fi
target="$os-$arch"
if [ "$arch" = "x64" ] && [ "$os" = "linux" ] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
    target="$target-baseline"
fi
if [ "$os" = "linux" ] && { [ -f /etc/alpine-release ] || { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; }; then
    target="$target-musl"
fi
filename="opencode-$target.tar.gz"

OC_BIN="$OC_CACHE_DIR/opencode-$OC_VERSION/opencode"
if [ ! -x "$OC_BIN" ]; then
    echo "  Downloading opencode $OC_VERSION ($filename) into cache..."
    mkdir -p "$(dirname "$OC_BIN")"
    # Retry: GitHub's release-asset CDN occasionally returns transient 503/502
    # (outage or rate-limit), which must not fail the whole e2e suite.
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 240 \
        "https://github.com/anomalyco/opencode/releases/download/v$OC_VERSION/$filename" \
        -o "$OC_CACHE_DIR/opencode.tar.gz" \
        || { echo "  ${RED}FAIL${NC}  opencode $OC_VERSION download failed"; exit 1; }
    tar -xzf "$OC_CACHE_DIR/opencode.tar.gz" -C "$(dirname "$OC_BIN")" \
        || { echo "  ${RED}FAIL${NC}  cannot extract opencode tarball"; exit 1; }
    rm -f "$OC_CACHE_DIR/opencode.tar.gz"
    chmod +x "$OC_BIN"
fi
if [ ! -s "$OC_BIN" ]; then
    echo "  ${RED}FAIL${NC}  cached opencode binary is empty"; exit 1
fi

# Pin an OLD opencode version to test the binary upgrade path (old -> latest)
# in section 11c. Release assets stay on GitHub permanently, so this is a
# one-time download per version, cached exactly like the primary binary.
OLD_VERSION="1.18.15"
OLD_BIN="$OC_CACHE_DIR/opencode-$OLD_VERSION/opencode"
if [ ! -x "$OLD_BIN" ]; then
    echo "  Downloading opencode $OLD_VERSION ($filename) into cache..."
    mkdir -p "$(dirname "$OLD_BIN")"
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 240 \
        "https://github.com/anomalyco/opencode/releases/download/v$OLD_VERSION/$filename" \
        -o "$OC_CACHE_DIR/opencode-old.tar.gz" \
        || { echo "  ${RED}FAIL${NC}  opencode $OLD_VERSION download failed"; exit 1; }
    tar -xzf "$OC_CACHE_DIR/opencode-old.tar.gz" -C "$(dirname "$OLD_BIN")" \
        || { echo "  ${RED}FAIL${NC}  cannot extract opencode $OLD_VERSION tarball"; exit 1; }
    rm -f "$OC_CACHE_DIR/opencode-old.tar.gz"
    chmod +x "$OLD_BIN"
fi
if [ ! -s "$OLD_BIN" ]; then
    echo "  ${RED}FAIL${NC}  cached opencode $OLD_VERSION binary is empty"; exit 1
fi
echo "  Using opencode $OLD_VERSION for the upgrade test (cache: $OLD_BIN)"

# Cache the installer script too, so the container needs no network for it.
if [ ! -f "$OC_CACHE_DIR/install.sh" ]; then
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 60 \
        https://opencode.ai/install -o "$OC_CACHE_DIR/install.sh" \
        || { echo "  ${RED}FAIL${NC}  cannot fetch opencode installer"; exit 1; }
fi

echo "  Using opencode $OC_VERSION (cache: $OC_BIN)"

echo ""
echo "--- Building Docker image ---"
docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

echo ""
echo "--- Preparing test project ---"
TMP_PROJECT=$(mktemp -d)
mkdir -p "$TMP_PROJECT/test-project/subdir"
echo "DB_PASS=secret123"    > "$TMP_PROJECT/test-project/.env"
echo "API_KEY=hunter2"       > "$TMP_PROJECT/test-project/settings.php"
echo '{"token":"abc"}'       > "$TMP_PROJECT/test-project/auth.json"
echo "# README"               > "$TMP_PROJECT/test-project/README.md"
echo "# command docs"          > "$TMP_PROJECT/test-project/README.txt"
echo "normal source code"    > "$TMP_PROJECT/test-project/index.php"

echo ""
echo "--- Running E2E container ---"
docker run -d --name "$CONTAINER" \
    -v "$REPO_DIR:/home/dev/repo" \
    -v "$TMP_PROJECT/test-project:/var/www/vhosts/test-project" \
    -v "$OC_CACHE_DIR:/opencode-cache:ro" \
    --privileged \
    "$IMAGE" sleep infinity

E() { docker exec -u dev "$CONTAINER" sh -c "$@"; }

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
    E 'test -x /usr/local/lib/opencode-permissions-kit/bin/opencode'
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
check "binary still root-owned" \
    E 'test "$(stat -c %U:%G /usr/local/lib/opencode-permissions-kit/bin/opencode)" = "root:root"'
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
check "migration: binary moved to new path"       E 'test -x /usr/local/lib/opencode-permissions-kit/bin/opencode'
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

echo ""
echo "=============================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
fi
echo ""

# Section 10g creates a root-owned README.md inside the bind mount, so the
# cleanup needs root; best-effort, never mask a real test failure.
rm -rf "$TMP_PROJECT" 2>/dev/null || true
sudo rm -rf "$TMP_PROJECT" 2>/dev/null || true

[ "$failures" -eq 0 ] || exit 1
