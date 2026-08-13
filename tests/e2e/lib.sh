#!/bin/sh
# tests/e2e/lib.sh — shared scaffolding for the e2e suites.
# Sourced (not executed) by run.sh and run-docker-rootless.sh. The runners set
# the E2E_* knobs, then call the helpers below. Kept in one file so the two
# suites cannot drift apart in their build/cache/check plumbing.
#
# Knobs (set BEFORE sourcing):
#   E2E_IMAGE        docker image tag           (default: opencode-e2e)
#   E2E_CONTAINER    container name             (default: opencode-e2e-test)
#   E2E_DOCKERFILE   Dockerfile name            (default: Dockerfile)
#   E2E_RUN_ARGS     extra `docker run` args    (default: none)
#   E2E_CMD          command for `docker run`   (default: sleep infinity)
#   E2E_SYSTEMD      1 = systemd-as-PID1 container (rootless suite). e2e_start_container
#                    then auto-detects the OUTER docker layout (rootful vs
#                    rootless) and builds the cgroup args accordingly.
#   E2E_DEBUG        1 = keep the container on failure for inspection
#   E2E_OLD_VERSION  pinned old opencode for the upgrade test
#                    (default: 1.18.15; only fetched if e2e_fetch_old is called)
#
# Exports used by the runner after the helpers run:
#   OC_VERSION, OC_BIN, OC_CACHE_DIR, OC_INSTALLER, OLD_VERSION, OLD_BIN,
#   TMP_PROJECT, E (docker exec helper), E2E_HOST_LAYOUT (rootful|rootless)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

E2E_IMAGE="${E2E_IMAGE:-opencode-e2e}"
E2E_CONTAINER="${E2E_CONTAINER:-opencode-e2e-test}"
E2E_DOCKERFILE="${E2E_DOCKERFILE:-Dockerfile}"
E2E_RUN_ARGS="${E2E_RUN_ARGS:-}"
E2E_CMD="${E2E_CMD:-sleep infinity}"
E2E_SYSTEMD="${E2E_SYSTEMD:-0}"
E2E_DEBUG="${E2E_DEBUG:-0}"
E2E_OLD_VERSION="${E2E_OLD_VERSION:-1.18.15}"
E2E_HOST_LAYOUT="unknown"

failures=0
passed=0
skipped=0

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

# Counted-skip: mark a check as skipped (not failed) when its premise cannot be
# established in this environment (e.g. no nested user namespaces / no systemd).
# Keeps CI green on hosts that lack the capability, while still surfacing that
# the check did not run.
skip() {
    echo "  ${YELLOW}SKIP${NC}  $1"
    skipped=$((skipped + 1))
}

# --- opencode binary cache (version-keyed) -----------------------------------
# The official installer fetches the opencode binary from the internet on every
# run. To avoid re-downloading the (large) binary each time, we download it once
# per opencode version on the HOST and mount it into the container read-only
# (the installer supports --binary <path>, which skips the download but keeps
# the PATH-modification behavior the kit's install.sh depends on).
e2e_resolve_cache() {
    OC_CACHE_DIR="$SCRIPT_DIR/cache"
    mkdir -p "$OC_CACHE_DIR"

    # Resolve the current opencode version from GitHub releases (tiny request).
    # If the endpoint is unreachable, fall back to the newest cached version so
    # repeat runs work offline.
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
    _OC_FRESH=false
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
        _OC_FRESH=true
    fi
    if [ ! -s "$OC_BIN" ]; then
        echo "  ${RED}FAIL${NC}  cached opencode binary is empty"; exit 1
    fi

    # Cache the installer script too, so the container needs no network for it.
    OC_INSTALLER="$OC_CACHE_DIR/install.sh"
    if [ ! -f "$OC_INSTALLER" ]; then
        curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 60 \
            https://opencode.ai/install -o "$OC_INSTALLER" \
            || { echo "  ${RED}FAIL${NC}  cannot fetch opencode installer"; exit 1; }
    fi

    echo "  Using opencode $OC_VERSION (cache: $OC_BIN)"
}

# Pin an OLD opencode version to test the binary upgrade path (old -> latest).
# Release assets stay on GitHub permanently, so this is a one-time download per
# version, cached exactly like the primary binary. Only the run.sh suite needs
# this (its update/binary-upgrade sections); the rootless runner skips it.
e2e_fetch_old() {
    OLD_VERSION="$E2E_OLD_VERSION"
    OLD_BIN="$OC_CACHE_DIR/opencode-$OLD_VERSION/opencode"
    if [ ! -x "$OLD_BIN" ]; then
        # If the primary binary was just fetched, pause briefly before the second
        # consecutive release-asset request. GitHub's CDN sometimes rate-limits
        # or returns a transient 503 when two downloads hit it back-to-back.
        if [ "$_OC_FRESH" = true ]; then
            echo "  Pausing 10s before the OLD-version download (back-to-back CDN courtesy)..."
            sleep 10
        fi
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
}

# --- test project (host side, bind-mounted into the container) ---------------
e2e_prepare_project() {
    TMP_PROJECT=$(mktemp -d)
    mkdir -p "$TMP_PROJECT/test-project/subdir"
    echo "DB_PASS=secret123"    > "$TMP_PROJECT/test-project/.env"
    echo "API_KEY=hunter2"       > "$TMP_PROJECT/test-project/settings.php"
    echo '{"token":"abc"}'       > "$TMP_PROJECT/test-project/auth.json"
    echo "# README"               > "$TMP_PROJECT/test-project/README.md"
    echo "# command docs"          > "$TMP_PROJECT/test-project/README.txt"
    echo "normal source code"    > "$TMP_PROJECT/test-project/index.php"
}

# --- container lifecycle -----------------------------------------------------
# Detect whether the OUTER docker daemon is rootless. A rootless daemon runs
# every container in a user namespace, so a container's /proc/self/uid_map
# shows a restricted map (`0 <uid> 1 ...`) instead of the full `0 0 4294967295`.
# This decides the cgroup strategy for the systemd container (E2E_SYSTEMD=1):
# under a rootful daemon the container can mount and write host-root cgroup
# paths (cgroupns=host + host /sys/fs/cgroup bind, the documented
# systemd-in-docker recipe); under a rootless daemon the container's "root" is
# not host root, so it can never touch host-root cgroup dirs and must rely on
# Docker's private cgroup namespace (cgroupns=private, no bind) where the
# container's own delegated subtree IS the cgroup root.
e2e_detect_host_layout() {
    local umap
    umap=$(docker run --rm "$E2E_IMAGE" sh -c 'grep -m1 "^0 " /proc/self/uid_map' 2>/dev/null || true)
    if [ "$umap" = "0 0 4294967295" ]; then
        E2E_HOST_LAYOUT="rootful"
    else
        E2E_HOST_LAYOUT="rootless"
    fi
    echo "  Host docker layout: ${E2E_HOST_LAYOUT} (container uid_map: ${umap:-unreadable})"
}

e2e_start_container() {
    echo ""
    echo "--- Building Docker image ($E2E_DOCKERFILE) ---"
    docker build -t "$E2E_IMAGE" -f "$SCRIPT_DIR/$E2E_DOCKERFILE" "$SCRIPT_DIR"

    if [ "$E2E_SYSTEMD" = "1" ]; then
        e2e_detect_host_layout
        # systemd-as-PID1 needs fresh runtime dirs on tmpfs.
        E2E_RUN_ARGS="$E2E_RUN_ARGS --tmpfs /run:rw,mode=755 --tmpfs /run/lock --tmpfs /tmp:rw"
        if [ "$E2E_HOST_LAYOUT" = "rootful" ]; then
            E2E_RUN_ARGS="$E2E_RUN_ARGS --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
        else
            E2E_RUN_ARGS="$E2E_RUN_ARGS --cgroupns=private"
        fi
    fi

    echo ""
    echo "--- Running E2E container ---"
    # shellcheck disable=SC2086  # E2E_RUN_ARGS / E2E_CMD are intentional word splits
    docker run -d --name "$E2E_CONTAINER" \
        -v "$REPO_DIR:/home/dev/repo" \
        -v "$TMP_PROJECT/test-project:/var/www/vhosts/test-project" \
        -v "$OC_CACHE_DIR:/opencode-cache:ro" \
        --privileged $E2E_RUN_ARGS \
        "$E2E_IMAGE" $E2E_CMD
}

E() { docker exec -u dev "$E2E_CONTAINER" sh -c "$@"; }

e2e_cleanup() {
    if [ "$E2E_DEBUG" = "1" ] && [ "$failures" -gt 0 ]; then
        echo ""
        echo "  ${YELLOW}--debug: keeping container '$E2E_CONTAINER' for inspection${NC}"
        echo "    docker exec -it $E2E_CONTAINER bash"
        echo "    (remove it afterwards with: docker rm -f $E2E_CONTAINER)"
        return
    fi
    docker rm -f "$E2E_CONTAINER" 2>/dev/null || true
    # Section 10g creates a root-owned README.md inside the bind mount, so a
    # plain rm can fail; best-effort, never mask a real test failure.
    rm -rf "${TMP_PROJECT:-/nonexistent-e2e-project}" 2>/dev/null || true
    sudo rm -rf "${TMP_PROJECT:-/nonexistent-e2e-project}" 2>/dev/null || true
}
trap e2e_cleanup EXIT

e2e_finish() {
    echo ""
    echo "=============================================="
    echo "  ${GREEN}Passed: $passed${NC}"
    if [ "$skipped" -gt 0 ]; then
        echo "  ${YELLOW}Skipped: $skipped${NC}"
    fi
    if [ "$failures" -gt 0 ]; then
        echo "  ${RED}Failed: $failures${NC}"
    fi
    echo ""
    [ "$failures" -eq 0 ]
}
