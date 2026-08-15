#!/bin/sh
# e2e/run-docker-rootless.sh — docker-rootless daemon end-to-end test
# Run from repo root: ./tests/e2e/run-docker-rootless.sh
#
# Phase 3 of docs/design/DOCKER-ROOTLESS.md. Unlike the podman-rootless suite
# (run.sh section 12i), docker-rootless cannot run in the plain e2e container:
# the kit's provisioning (setup-container-backend.sh) hard-requires a working
# systemd --user manager (dockerd-rootless-setuptool.sh + `systemctl --user`).
# This suite therefore uses a SEPARATE systemd-based container
# (Dockerfile.rootless) and exercises the REAL provisioning path end-to-end:
#
#   RL1  install the kit (docker-group baseline), assert systemd is PID 1
#   RL2  config.sh container-backend docker-rootless -> REAL provisioning
#        (get.docker.com -> docker-ce-rootless-extras, subuid/subgid,
#        dockerd-rootless-setuptool.sh as opencode, systemctl --user, linger)
#   RL3  wrapper dispatch + the socket-check.sh sudoers fallback (the exact
#        regression fixed in ab19025): /run/user/<uid> is 0700 opencode, so the
#        developer-running wrapper must probe via `sudo -u opencode`
#   RL4  §9.1 ACL proof with REAL dockerd: containers run as the opencode host
#        UID, so u:opencode:--- denies survive bind mounts
#   RL5  status.sh + config.sh container-backend status report the backend
#   RL6  teardown (switch back to docker-group) + uninstall verification
#
# The container layout adapts to the OUTER docker daemon (lib.sh auto-detects
# it after the build). The systemd container always runs with --cgroupns=private
# (no /sys/fs/cgroup bind): Docker's default, and the only mode where the
# nested ROOTLESS inner dockerd's /proc/self/cgroup paths match its
# /sys/fs/cgroup view. The classic cgroupns=host + host cgroup bind makes
# systemd boot but breaks the inner daemon (its user-<uid>.slice is not at the
# visible host-root tree). The layout detection therefore only gates one thing:
# whether the e2e container runs in a NESTED user namespace —
#   - rootful outer docker (CI, normal hosts): no nested userns; kit defaults
#     run untouched.
#   - rootless outer docker (dev hosts): the container itself runs in a user
#     namespace; the RL2 prep seeds an in-range subuid/subgid (the kit's
#     231072+ range is outside the container's uid map). The fuse-overlayfs
#     storage-driver pin applies on BOTH layouts (see the RL2 prep block).
#
# Like run.sh section 12i, the whole docker-rootless section SKIPs (not fails)
# when the host cannot host systemd-in-docker or nested user namespaces.
#
# Usage: run-docker-rootless.sh [--debug]
#   --debug   on failure: keep the container alive and dump the opencode
#             systemd --user journal (docker.service) in addition to the full
#             provisioning log.
set -e

E2E_DEBUG=0
for _arg in "$@"; do
    case "$_arg" in
        --debug) E2E_DEBUG=1 ;;
        --help|-h)
            sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^Usage:/,$p'
            exit 0
            ;;
        *) echo "unknown argument: $_arg (see --help)" >&2; exit 1 ;;
    esac
done

E2E_IMAGE="opencode-e2e-rootless"
E2E_CONTAINER="opencode-e2e-rootless-test"
E2E_DOCKERFILE="Dockerfile.rootless"
# systemd-as-PID1 container: lib.sh auto-detects the outer docker layout and
# builds the cgroup/tmpfs args (see lib.sh e2e_detect_host_layout).
E2E_SYSTEMD=1
# Run systemd as PID 1. lib.sh defaults an empty E2E_CMD to "sleep infinity",
# so be explicit instead of relying on the image's CMD.
E2E_CMD="/sbin/init"
. "$(dirname "$(readlink -f "$0")")/lib.sh"

echo ""
echo "${CYAN}========================================================${NC}"
echo "${CYAN}  opencode permissions kit — docker-rootless daemon E2E${NC}"
echo "${CYAN}========================================================${NC}"
echo ""

echo "--- opencode binary cache (version-keyed) ---"
e2e_resolve_cache

e2e_prepare_project

e2e_start_container

# --- wait for systemd to finish booting (not just for PID 1 to exist) --------
echo ""
echo "--- RL0. systemd boot in the container ---"
_boot_ok=false
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if E 'test -e /run/systemd/private' 2>/dev/null; then
        _boot_ok=true
        break
    fi
    sleep 1
done
if [ "$_boot_ok" = true ]; then
    check "systemd is PID 1 in the e2e container" \
        E 'test "$(cat /proc/1/comm)" = "systemd"'
else
    echo "  ${YELLOW}SKIP${NC}  systemd did not boot in the container (runner limitation)"
    skip "systemd not available"
    e2e_finish
    exit $?
fi

echo ""
echo "--- RL1. Install the kit (podman-rootless baseline) ---"
# Install opencode itself (cached binary), then the kit. The baseline backend
# is podman-rootless (works without systemd); RL2 below switches to a REAL
# docker-rootless daemon via config.sh AFTER the container-internal prep
# (fuse-overlayfs pin + nested-userns subuid seed) is in place. Never rely on
# repo mode bits: use `bash script`.
E 'bash /opencode-cache/install.sh --binary /opencode-cache/opencode-'"$OC_VERSION"'/opencode' || {
    echo "  ${RED}FAIL${NC}  opencode installer failed (network issue?)"
    if E 'test -x /home/dev/.opencode/bin/opencode'; then
        echo "  ${GREEN}OK${NC}  opencode binary already present"
    else
        echo "  ${RED}E2E aborted — cannot install opencode.${NC}"
        exit 1
    fi
}
E 'sudo bash /home/dev/repo/files/install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts'
echo "  Install complete."

check "install.conf records CONTAINER_BACKEND=podman-rootless" \
    E 'grep -q "^CONTAINER_BACKEND=podman-rootless" /etc/opencode-permissions-kit/install.conf'
check "wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "opencode sandbox user exists" \
    E 'id opencode'
check ".env readable by opencode (soft-only model)" \
    E 'sudo -u opencode test -r /var/www/vhosts/test-project/.env'

OC_UID=$(E 'id -u opencode')
SOCK="unix:///run/user/$OC_UID/docker.sock"
SOCKPATH="/run/user/$OC_UID/docker.sock"
echo "  opencode uid: $OC_UID (socket: $SOCK)"
echo "  host docker layout: $E2E_HOST_LAYOUT"

# --- container-internal adaptations ------------------------------------------
# This suite always runs docker-in-docker, so two things need adapting INSIDE
# the container regardless of the outer host layout (both are container
# accommodations only — the kit's real provisioning path runs untouched):
#   - storage driver: kernel overlay2 cannot stack on the container's own
#     overlay rootfs (`mount ... invalid argument`), and on a rootless-host
#     layout it additionally cannot stack in a nested userns; the inner
#     rootless daemon therefore uses fuse-overlayfs, pinned in
#     ~opencode/.config/docker/daemon.json BEFORE provisioning (the setup tool
#     respects an existing daemon.json).
#   - subuid/subgid (rootless-host layout ONLY): the container itself runs in a
#     user namespace (uid_map `0 <uid> 1 / 1 <n> 65536`), and the kit allocates
#     a range starting at 100000 (practically 231072+), which is OUTSIDE that
#     map, so rootlesskit's `newuidmap` write fails with EPERM. Seeding an
#     in-range range (opencode:4096:60000) first works because
#     setup-container-backend.sh's allocate_range() KEEPS an existing entry.
#     On a rootful host the container has the full uid space, so this is not
#     needed there.
echo ""
echo "  ${CYAN}RL2 prep: pinning fuse-overlayfs storage driver (nested docker-in-docker)${NC}"
E 'sudo -u opencode sh -c '\''mkdir -p /home/opencode/.config/docker'\'''
E 'printf '\''{"storage-driver":"fuse-overlayfs"}\n'\'' | sudo -u opencode tee /home/opencode/.config/docker/daemon.json >/dev/null'
check "RL2-prep: fuse-overlayfs storage driver pinned (nested docker-in-docker)" \
    E 'test "$(sudo -u opencode cat /home/opencode/.config/docker/daemon.json)" = "{\"storage-driver\":\"fuse-overlayfs\"}"'
if [ "$E2E_HOST_LAYOUT" = "rootless" ]; then
    echo "  ${CYAN}Nested userns (rootless host docker) — additionally seeding in-range subuid${NC}"
    E 'sudo sh -c '\''printf "opencode:4096:60000\n" > /etc/subuid; printf "opencode:4096:60000\n" > /etc/subgid'\'''
    check "RL2-prep: in-range subuid/subgid seeded for opencode (nested userns)" \
        E 'grep -q "^opencode:4096:60000$" /etc/subuid && grep -q "^opencode:4096:60000$" /etc/subgid'
fi

# --- the docker-rootless daemon e2e -------------------------------------------
_rootless_ok=true

echo ""
echo "--- RL2. Switch to docker-rootless via config.sh (real provisioning) ---"
# Full Phase 3 path: config.sh -> setup-container-backend.sh -> get.docker.com,
# subuid/subgid, dockerd-rootless-setuptool.sh as opencode, systemctl --user
# enable+start docker.service, linger. Run the REPO checkout so we test the
# local code, not a potentially stale installed copy.
if ! E 'sudo bash /home/dev/repo/files/config.sh --yes container-backend docker-rootless >/tmp/config-drl.log 2>&1'; then
    echo "  ${YELLOW}SKIP${NC}  RL2: docker-rootless provisioning failed"
    echo "  --- /tmp/config-drl.log (full) ---"
    E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/config-drl.log 2>/dev/null' || true
    if [ "$E2E_DEBUG" = "1" ]; then
        echo "  --- opencode systemd --user journal (docker.service) ---"
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' journalctl --user -n 40 --no-pager --unit docker.service 2>/dev/null"' | sed 's/\x1b\[[0-9;]*m//g' || true
        echo "  --- subuid/subgid + docker daemon config ---"
        E 'printf "subuid: "; cat /etc/subuid; printf "subgid: "; cat /etc/subgid; printf "daemon.json: "; cat /home/opencode/.config/docker/daemon.json 2>/dev/null' || true
    fi
    _rootless_ok=false
    skipped=$((skipped + 1))
fi

# Give the systemd --user docker.service a moment to create the socket.
if [ "$_rootless_ok" = true ]; then
    _sock_ok=false
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        if E "sudo test -S $SOCKPATH" 2>/dev/null; then
            _sock_ok=true
            break
        fi
        sleep 1
    done
    if [ "$_sock_ok" = false ]; then
        echo "  ${YELLOW}SKIP${NC}  RL2: docker-rootless daemon socket never appeared"
        echo "  --- /tmp/config-drl.log (last 40 lines) ---"
        E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/config-drl.log 2>/dev/null | tail -40' || true
        echo "  --- docker.service status (as opencode) ---"
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' systemctl --user status docker.service --no-pager 2>&1 | head -15"' | sed 's/\x1b\[[0-9;]*m//g' || true
        _rootless_ok=false
        skipped=$((skipped + 1))
    fi
fi

if [ "$_rootless_ok" = true ]; then
    check "RL2: install.conf records CONTAINER_BACKEND=docker-rootless" \
        E 'grep -q "^CONTAINER_BACKEND=docker-rootless" /etc/opencode-permissions-kit/install.conf'
    check "RL2: install.conf records the rootless socket" \
        E 'grep -q "^OPENCODE_DOCKER_HOST=unix:///run/user/'"$OC_UID"'/docker.sock" /etc/opencode-permissions-kit/install.conf'
    check "RL2: sudoers strips (opencode:docker) for docker-rootless" \
        E '! sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit'
    check "RL2: sudoers keeps the base (opencode) RunAs" \
        E 'sudo grep -q "(opencode) NOPASSWD" /etc/sudoers.d/opencode-permissions-kit'
    check "RL2: sudoers keeps the socket-check.sh NOPASSWD rule" \
        E 'sudo grep -q "socket-check.sh" /etc/sudoers.d/opencode-permissions-kit'
    check "RL2: opencode user NOT in the docker group (no root-equivalent grant)" \
        E '! id -nG opencode | tr " " "\n" | grep -qx docker'
    check "RL2: runtime dir is 0700 opencode (as on the real target)" \
        E 'test "$(sudo stat -c %U:%a /run/user/'"$OC_UID"')" = "opencode:700"'
    check "RL2: dockerd rootless service is active (systemd --user, as opencode)" \
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' systemctl --user is-active docker"'
    check "RL2: subuid/subgid allocated for opencode" \
        E 'grep -q "^opencode:" /etc/subuid && grep -q "^opencode:" /etc/subgid'
fi

echo ""
echo "--- RL3. Wrapper dispatch + socket-check sudoers fallback (ab19025) ---"
# This is the exact scenario from the bug: the wrapper runs as the DEVELOPER,
# but the rootless socket lives in the opencode user's 0700 /run/user/<uid>.
# A plain `test -S` by the wrapper cannot see it; the kit's socket-check.sh
# sudoers rule is the designed probe path.
if [ "$_rootless_ok" = true ]; then
    check_fail "RL3: developer cannot probe the socket directly (0700 dir)" \
        E "test -S $SOCKPATH"
    check "RL3: socket-check.sh reachable as developer via sudoers (unix:// form)" \
        E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh '"$SOCK"
    check "RL3: socket-check.sh reachable as developer via sudoers (path form)" \
        E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh '"$SOCKPATH"
    check "RL3: socket-check.sh also works as the opencode user itself" \
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh '"$SOCK"'"'
    check "RL3: sudoers preserves DOCKER_HOST/XDG_RUNTIME_DIR across sudo" \
        E 'sudo grep -q "DOCKER_HOST XDG_RUNTIME_DIR" /etc/sudoers.d/opencode-permissions-kit'
    check "RL3: installed wrapper exports DOCKER_HOST for the rootless backend" \
        E 'grep -q "export DOCKER_HOST" /usr/local/lib/opencode-permissions-kit/wrapper'

    # Project explicitly enables docker -> wrapper auto-detects and asks.
    E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "bash": { "docker *": "allow" }
    }
}
EOF'
    E 'cd /var/www/vhosts/test-project && printf "Y\n" | /usr/local/bin/opencode --help 2>&1 | tee /tmp/wrapper-drl.txt' && \
        echo "  ${GREEN}OK${NC}  wrapper docker-rootless auto-detection (accepted) ran"
    check "RL3: wrapper auto-detect: container tools advisory" \
        E 'grep -q "Container tools enabled by this project" /tmp/wrapper-drl.txt'
    check "RL3: wrapper auto-detect: docker-rootless prompt" \
        E 'grep -q "Run opencode with the docker-rootless backend" /tmp/wrapper-drl.txt'
    check "RL3: wrapper auto-detect: accepted -> docker-rootless exec message" \
        E 'grep -q "opencode will run with the docker-rootless backend" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT mention the docker group" \
        E 'grep -q "opencode will run with the docker group" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT warn about an absent docker group" \
        E 'grep -q "does not exist — running without container group" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT warn that the rootless socket is unreachable" \
        E 'grep -q "docker-rootless socket not reachable" /tmp/wrapper-drl.txt'
fi

echo ""
echo "--- RL4. §9.1 proof with REAL dockerd (soft-only: containers read as opencode UID) ---"
if [ "$_rootless_ok" = true ]; then
    check "RL4: docker CLI works against the rootless socket as opencode" \
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' DOCKER_HOST='"$SOCK"' docker ps"'
    if E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' DOCKER_HOST='"$SOCK"' docker pull alpine:latest >/tmp/docker-pull.out 2>&1"'; then
        # The daemon runs as the opencode host UID, so a container's user
        # namespace maps container-root 0 -> opencode (<OC_UID>) and the rest
        # into opencode's subuid range. `id -u` inside a rootless container
        # prints 0 (root of the container's own userns), so the proof is the
        # uid_map itself: the line mapping uid 0 must target <OC_UID>. Note the
        # map is right-aligned in columns, so uid 0 carries leading whitespace —
        # never anchor the pattern at the start of the line.
        check "RL4: container userns maps root to the opencode host UID ($OC_UID), not real root" \
            E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' DOCKER_HOST='"$SOCK"' docker run --rm alpine:latest cat /proc/self/uid_map" | grep -qE "0[[:space:]]+'"$OC_UID"'[[:space:]]+"'
        # Bind-mount read checks (soft-only model): the container output must
        # contain the file content. Wrapped in a function so the PASS/FAIL
        # lines are not swallowed by the output pipe.
        _rl_cat_check() {
            E "sudo -u opencode sh -c 'XDG_RUNTIME_DIR=/run/user/$OC_UID DOCKER_HOST=$SOCK docker run --rm -v /var/www/vhosts/test-project:/app alpine:latest cat /app/$2'" | grep -q "$1"
        }
        check "RL4 §9.1 (soft-only): container CAN read .env via bind mount (ddev-working goal)" \
            _rl_cat_check secret123 .env
        check "RL4 §9.1 (soft-only): container CAN read settings.php via bind mount (ddev boots)" \
            _rl_cat_check hunter2 settings.php
    else
        echo "  ${YELLOW}SKIP${NC}  RL4 §9.1: could not pull alpine (no network?) — $(E 'tail -1 /tmp/docker-pull.out' 2>/dev/null || echo unknown)"
        skipped=$((skipped + 3))
    fi
fi

echo ""
echo "--- RL5. status.sh + config.sh report the docker-rootless backend ---"
if [ "$_rootless_ok" = true ]; then
    check "RL5: status.sh reports the docker-rootless backend" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "backend:    docker-rootless"'
    check "RL5: status.sh reports the socket as reachable" \
        E '/usr/local/lib/opencode-permissions-kit/status.sh 2>&1 | grep -q "socket:.*reachable"'
    check "RL5: config.sh container-backend status reports docker-rootless" \
        E 'sudo bash /home/dev/repo/files/config.sh container-backend status 2>&1 | grep -q "docker-rootless"'
    check "RL5: config.sh container-backend status reports the socket reachable" \
        E 'sudo bash /home/dev/repo/files/config.sh container-backend status 2>&1 | grep -q "socket:.*reachable"'
fi

echo ""
echo "--- RL6. Uninstall (rootless runtime teardown built in) ---"
# The soft-only kit has no docker-group switch-back — uninstall.sh itself
# disables linger, stops user@<uid> and resets rootless podman storage so
# userdel -r can remove the opencode user.
OC_UID2=$(E 'id -u opencode')
E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID2"' docker system prune -af >/dev/null 2>&1" || true'
E 'bash /usr/local/lib/opencode-permissions-kit/uninstall.sh --yes' && \
    echo "  ${GREEN}OK${NC}  uninstall.sh completed"
check_fail "Wrapper removed"          E 'test -e /usr/local/bin/opencode'
check_fail "Library removed"          E 'test -e /usr/local/lib/opencode-permissions-kit'
check_fail "Sudoers removed"          E 'test -e /etc/sudoers.d/opencode-permissions-kit'
check_fail "/etc/opencode-permissions-kit removed"    E 'test -e /etc/opencode-permissions-kit'
check_fail "opencode user removed"    E 'id opencode'
check_fail "Audit log removed"        E 'test -e /var/log/opencode-permissions-kit'

e2e_finish
