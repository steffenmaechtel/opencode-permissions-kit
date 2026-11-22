#!/bin/sh
# e2e/run-docker-rootless.sh — docker-rootless daemon end-to-end test
# Run from repo root: ./tests/e2e/run-docker-rootless.sh
#
# Phase 3 of internal/records/rootless-backend.md. Unlike the podman-rootless suite
# (run.sh section 12i), docker-rootless cannot run in the plain e2e container:
# the kit's provisioning (setup-container-backend) hard-requires a working
# systemd --user manager (dockerd-rootless-setuptool.sh + `systemctl --user`).
# This suite therefore uses a SEPARATE systemd-based container
# (Dockerfile.rootless) and exercises the REAL provisioning path end-to-end:
#
#   RL1  install the kit (podman-rootless baseline), assert systemd is PID 1
#   RL2  config.sh container-backend docker-rootless -> REAL provisioning
#        (get.docker.com -> docker-ce-rootless-extras, subuid/subgid,
#        dockerd-rootless-setuptool.sh as opencode, systemctl --user, linger)
#   RL3  wrapper dispatch + the socket-check.sh sudoers fallback (the exact
#        regression fixed in ab19025): /run/user/<uid> is 0700 opencode, so the
#        developer-running wrapper must probe via `sudo -u opencode`
#   RL4  §9.1 proof with REAL dockerd (soft-only model): containers run as the
#        opencode host UID — not real root — and CAN read the project files
#        (the ddev-working goal)
#   RL5  status.sh + config.sh container-backend status report the backend
#   RL6  rootless runtime teardown + uninstall verification
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
        --help | -h)
            sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^Usage:/,$p'
            exit 0
            ;;
        *)
            echo "unknown argument: $_arg (see --help)" >&2
            exit 1
            ;;
    esac
done

E2E_IMAGE="opencode-e2e-rootless"
# Env-overridable; lib.sh appends the checkout-path suffix (issue #366) so
# parallel same-suite runs from another worktree cannot collide on the name.
E2E_CONTAINER="${E2E_CONTAINER:-opencode-e2e-rootless-test}"
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

# Hermetic wrapper banner AND status rows (issue #358): today's verdict
# is stamped "current" so the wrapper starts below replay the cache, and
# every container command via E() exports OPK_UPDATE_CHECK=0 — so the
# status.sh live row never asks the mirror from inside the container.
E 'mkdir -p /home/dev/.cache/opencode-permissions-kit && printf "DATE=%s\nSTATE=current\nVER=\n" "$(date +%F)" > /home/dev/.cache/opencode-permissions-kit/update-check'

check "install.conf records CONTAINER_BACKEND=podman-rootless" \
    E 'grep -q "^CONTAINER_BACKEND=podman-rootless" /etc/opencode-permissions-kit/install.conf'
check "wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "opencode user exists" \
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
#     setup-container-backend's allocate_range() KEEPS an existing entry.
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
# Full Phase 3 path: config.sh -> setup-container-backend -> get.docker.com,
# subuid/subgid, dockerd-rootless-setuptool.sh as opencode, systemctl --user
# enable+start docker.service, linger. Run the REPO checkout so we test the
# local code, not a potentially stale installed copy.
if ! E 'sudo bash /home/dev/repo/files/opencode-permissions-kit-lib/management/config.sh --yes container-backend docker-rootless >/tmp/config-drl.log 2>&1'; then
    # No announcing SKIP echo (#494 a F2): skip() at the arm's end prints
    # the same verdict — the dump block between is diagnostic context.
    echo "  --- /tmp/config-drl.log (full) ---"
    E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/config-drl.log 2>/dev/null' || true
    if [ "$E2E_DEBUG" = "1" ]; then
        echo "  --- opencode systemd --user journal (docker.service) ---"
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' journalctl --user -n 40 --no-pager --unit docker.service 2>/dev/null"' | sed 's/\x1b\[[0-9;]*m//g' || true
        echo "  --- subuid/subgid + docker daemon config ---"
        E 'printf "subuid: "; cat /etc/subuid; printf "subgid: "; cat /etc/subgid; printf "daemon.json: "; cat /home/opencode/.config/docker/daemon.json 2>/dev/null' || true
    fi
    _rootless_ok=false
    skip "RL2: docker-rootless provisioning failed"
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
        # No announcing SKIP echo (#494 a F2) — skip() closes the arm.
        echo "  --- /tmp/config-drl.log (last 40 lines) ---"
        E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/config-drl.log 2>/dev/null | tail -40' || true
        echo "  --- docker.service status (as opencode) ---"
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' systemctl --user status docker.service --no-pager 2>&1 | head -15"' | sed 's/\x1b\[[0-9;]*m//g' || true
        _rootless_ok=false
        skip "RL2: docker-rootless daemon socket never appeared"
    fi
fi

if [ "$_rootless_ok" = true ]; then
    check "RL2: install.conf records CONTAINER_BACKEND=docker-rootless" \
        E 'grep -q "^CONTAINER_BACKEND=docker-rootless" /etc/opencode-permissions-kit/install.conf'
    check "RL2: install.conf stamps the opencode major (issue #80)" \
        E 'grep -qE "^OPENCODE_MAJOR=[12]$" /etc/opencode-permissions-kit/install.conf'
    check "RL2: install.conf records the rootless socket" \
        E 'grep -q "^OPENCODE_DOCKER_HOST=unix:///run/user/'"$OC_UID"'/docker.sock" /etc/opencode-permissions-kit/install.conf'
    check "RL2: sudoers strips (opencode:docker) for docker-rootless" \
        E '! sudo grep -q "opencode:docker" /etc/sudoers.d/opencode-permissions-kit'
    check "RL2: sudoers keeps the base (opencode) RunAs" \
        E 'sudo grep -q "(opencode) NOPASSWD" /etc/sudoers.d/opencode-permissions-kit'
    check "RL2: sudoers keeps the socket-check NOPASSWD rule" \
        E 'sudo grep -q "bin/socket-check \*" /etc/sudoers.d/opencode-permissions-kit'
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
echo "--- RL2b. Git heal hooks (#671) ---"
# A dev-owned repo under the managed root, baselined like a real
# project add: the full lockout -> opt-in -> hook-heal cycle.
E 'sudo git init -q /var/www/vhosts/rl-gh && sudo sh -c "cd /var/www/vhosts/rl-gh && git -c user.email=dev@example.com -c user.name=dev commit -q --allow-empty -m init" && sudo chown -R dev:dev /var/www/vhosts/rl-gh'
E 'sudo opk config projects add /var/www/vhosts/rl-gh'
check "RL2b: git-heal pieces deployed (heal script + four hooks, #671)" \
    E 'test -x /usr/local/lib/opencode-permissions-kit/git-heal/heal-index-head && test -x /usr/local/lib/opencode-permissions-kit/git-heal/hooks/post-index-change'
check "RL2b: sudoers carries the heal grant (dev -> root -> exact script, #671)" \
    E 'sudo grep -q "^dev ALL=(root) NOPASSWD: /usr/local/lib/opencode-permissions-kit/git-heal/heal-index-head \*$" /etc/sudoers.d/opencode-permissions-kit'
check "RL2b: developer checkout flips index+HEAD dev-owned (lockout state, #671)" \
    E 'cd /var/www/vhosts/rl-gh && git checkout -q -b rl671-flip && test "$(stat -c %U .git/index)" = "dev" && test "$(stat -c %U .git/HEAD)" = "dev"'
check_fail "RL2b: agent git add DIES on the dev-owned index (sticky .git, #671)" \
    E 'sudo -u opencode -H sh -c "echo x > /var/www/vhosts/rl-gh/agent-file.txt && git -C /var/www/vhosts/rl-gh add agent-file.txt"'
# #678 rides the same pre-on window: dev merge flips ORIG_HEAD, the
# agent merge dies on it (the live-incident shape, two-uid in-container).
# mkdir follows EVERY checkout — switching to a master-based branch
# prunes sub/rl678 (the other branch's tracked files vanish with the
# empty dir).
check "RL2b: developer merge flips ORIG_HEAD dev-owned (pre-heal, #678)" \
    E 'cd /var/www/vhosts/rl-gh && git checkout -q -B rl678-a master && mkdir -p sub/rl678 && echo a >sub/rl678/a.txt && git add sub/rl678/a.txt && git -c user.email=dev@example.com -c user.name=dev commit -qm rl678a && git checkout -q -B rl678-b master && mkdir -p sub/rl678 && echo b >sub/rl678/b.txt && git add sub/rl678/b.txt && git -c user.email=dev@example.com -c user.name=dev commit -qm rl678b && git checkout -q rl678-a && git -c user.email=dev@example.com -c user.name=dev merge -q --no-ff -m rl678merge rl678-b && test "$(stat -c %U .git/ORIG_HEAD)" = "dev" && git checkout -q master'
check_fail "RL2b: agent merge DIES on the dev-flipped .git metadata (sticky .git, #678)" \
    E 'sudo -u opencode -H git -c user.email=agent@example.com -c user.name=agent -C /var/www/vhosts/rl-gh merge --no-ff -m rl678agent rl678-a'
# The dying merge leaves its worktree additions behind — clear them as
# the directory owner so the post-on arms start clean (sub/ is purely
# this arm's topology in this repo). Death-point note: this PRE-on
# state has index+ORIG_HEAD both dev-owned and the in-container death
# fires at the index write first; with a healed index (the shipped
# #674 world) the same merge dies at ORIG_HEAD (rc 128, zero partial
# state — the #678 live incident).
E 'rm -rf /var/www/vhosts/rl-gh/sub'
check "RL2b: opk git-heal on (sudo, dev gitconfig + heal sweep)" \
    E 'sudo opk git-heal on | grep -q "git heal hooks active"'
check "RL2b: the on-sweep healed the lockout (index+HEAD agent-owned)" \
    E 'test "$(stat -c %U /var/www/vhosts/rl-gh/.git/index)" = "opencode" && test "$(stat -c %U /var/www/vhosts/rl-gh/.git/HEAD)" = "opencode"'
check "RL2b: agent git add is green again after the heal" \
    E 'sudo -u opencode -H git -C /var/www/vhosts/rl-gh add agent-file.txt'
check "RL2b: the post-checkout hook re-heals the NEXT developer git op" \
    E 'cd /var/www/vhosts/rl-gh && git checkout -q master && test "$(stat -c %U .git/index)" = "opencode" && test "$(stat -c %U .git/HEAD)" = "opencode"'
check "RL2b: the on-sweep healed ORIG_HEAD too (widened set, #678)" \
    E 'test "$(stat -c %U /var/www/vhosts/rl-gh/.git/ORIG_HEAD)" = "opencode"'
# The #671 arm left agent-file.txt STAGED (this suite has no unstaging
# roundtrip arm like run.sh's) — git merge refuses over staged changes,
# so the fixture file is returned to untracked-absent before the merge
# closure arm (it has served its purpose in the arms above).
E 'sudo -u opencode -H sh -c "git -C /var/www/vhosts/rl-gh reset -q HEAD -- agent-file.txt && rm -f /var/www/vhosts/rl-gh/agent-file.txt"'
check "RL2b: agent merge is green over the healed ORIG_HEAD (#678 closure)" \
    E 'sudo -u opencode -H git -c user.email=agent@example.com -c user.name=agent -C /var/www/vhosts/rl-gh merge --no-ff -m rl678agent rl678-a && test "$(stat -c %U /var/www/vhosts/rl-gh/.git/ORIG_HEAD)" = "opencode"'
check "RL2b: opk git-heal status reports ON" \
    E 'sudo opk git-heal status | grep -q "git-heal: ON"'

echo ""
echo "--- RL2c/#704: git-protection pointer layout (migrate, status, revert) ---"
# The run.sh 12q twin on the rootless lane: real git, real dispatch.
# Overlayfs containers cannot chattr — the nail row is branched on the
# filesystem's actual answer (nailed -> rc 0; degraded -> rc 1 + row);
# the nail's kernel mechanics are Phase A's domain (issue #704).
E 'opk git-protection status >/tmp/gp-status-before.log 2>&1; test $? -eq 1'
check "RL2c: status (unconfigured) shows the classic row + rc 1" \
    E 'grep -qF "classic .git (unprotected -- the mv .git arm)" /tmp/gp-status-before.log'
E 'sudo opk git-protection on >/tmp/gp-on.log 2>&1' &&
    echo "  ${GREEN}OK${NC}  opk git-protection on completed"
check "RL2c: storage created + persisted" \
    E 'test "$(stat -c %U /var/www/gitdirs)" = "dev" && grep -qx "GITDIR_STORAGE=/var/www/gitdirs" /etc/opencode-permissions-kit/install.conf'
check "RL2c: rl-gh migrated — pointer file + agent git green" \
    E 'test -f /var/www/vhosts/rl-gh/.git && grep -qF "gitdir: /var/www/gitdirs/rl-gh.git" /var/www/vhosts/rl-gh/.git && sudo -u opencode -H git -C /var/www/vhosts/rl-gh status --porcelain >/dev/null'
check "RL2c: status rows are nail-state honest (branched)" \
    E 'if lsattr /var/www/vhosts/rl-gh/.git 2>/dev/null | awk "{print \$1}" | grep -q i; then opk git-protection status >/tmp/gp-status.log 2>&1; test $? -eq 0 && grep -qF "pointer + nailed" /tmp/gp-status.log; else opk git-protection status >/tmp/gp-status.log 2>&1; test $? -eq 1 && grep -qF "pointer, NOT nailed" /tmp/gp-status.log; fi'
check "RL2c: the adopt hint fires on a fresh classic tree (hooks on)" \
    E 'git -C /var/www/vhosts init -q rl-gp2 && cd /var/www/vhosts/rl-gp2 && git -c user.email=t@e -c user.name=t commit -q --allow-empty -m x && git checkout -q -b hint 2>/tmp/gp-hint.log; grep -q "opk git-protection" /tmp/gp-hint.log'
check "RL2c: no adopt hint on the adopted tree (self-silencing)" \
    E 'cd /var/www/vhosts/rl-gh && git checkout -q -b gp-post 2>/tmp/gp-hint2.log; ! grep -q "opk git-protection" /tmp/gp-hint2.log'
E 'sudo opk git-protection revert --all >/tmp/gp-revert.log 2>&1' &&
    echo "  ${GREEN}OK${NC}  opk git-protection revert --all completed"
check "RL2c: revert walks rl-gh back to the classic layout" \
    E 'test -d /var/www/vhosts/rl-gh/.git && git -C /var/www/vhosts/rl-gh status --porcelain >/dev/null'
E 'rm -rf /var/www/vhosts/rl-gp2 /tmp/gp-*.log'

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
        E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check '"$SOCK"
    check "RL3: socket-check.sh reachable as developer via sudoers (path form)" \
        E 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/socket-check '"$SOCKPATH"
    check "RL3: socket-check.sh also works as the opencode user itself" \
        E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' /usr/local/lib/opencode-permissions-kit/bin/socket-check '"$SOCK"'"'
    check "RL3: sudoers preserves DOCKER_HOST/XDG_RUNTIME_DIR/OPENCODE_SERVER_PASSWORD across sudo (command-scoped, #679)" \
        E 'sudo grep -q "^Defaults!OPK_ENV_CMNDS env_keep += \"DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME\"$" /etc/sudoers.d/opencode-permissions-kit'
    check "RL3: installed wrapper exports DOCKER_HOST for the rootless backend" \
        E 'grep -q "export DOCKER_HOST" /usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode'

    # Project explicitly enables docker -> wrapper auto-detects (no prompt
    # since 0.0.21 — the TUI mode row carries the state).
    E 'sudo tee /var/www/vhosts/test-project/opencode.jsonc > /dev/null <<EOF
{
    "permission": {
        "bash": { "docker *": "allow" }
    }
}
EOF'
    # Probe note: the banner checks drive the REAL interactive start (no args,
    # stdin closed) under `timeout 20` — what a user runs in a project directory.
    # --version/--help exec banner-free since issue #91 and are no probes. The
    # trailing grep -q ends the probe when the expected line has flushed
    # (SIGPIPE) — opencode 2.x may cold-start its background session service
    # inside the wrapper's container probe, which the early exit absorbs.
    E 'cd /var/www/vhosts/test-project && timeout 20 /usr/local/bin/opencode </dev/null 2>&1 | tee /tmp/wrapper-drl.txt | { grep -q "will run with" || true; }' &&
        echo "  ${GREEN}OK${NC}  wrapper docker-rootless auto-detection ran"
    check "RL3: wrapper auto-detect: container tools advisory" \
        E 'grep -q "Container tools enabled by this project" /tmp/wrapper-drl.txt'
    check "RL3: wrapper auto-detect: no [Y/n] question (removed 0.0.21)" \
        E '! grep -q "? \[Y/n\]" /tmp/wrapper-drl.txt'
    check "RL3: wrapper auto-detect: docker-rootless exec message" \
        E 'grep -q "opencode will run with the docker-rootless backend" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT mention the docker group" \
        E 'grep -q "opencode will run with the docker group" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT warn about an absent docker group" \
        E 'grep -q "does not exist — running without container group" /tmp/wrapper-drl.txt'
    check_fail "RL3: wrapper does NOT warn that the rootless socket is unreachable" \
        E 'grep -q "docker-rootless socket not reachable" /tmp/wrapper-drl.txt'
fi

echo ""
echo "--- RL3b. Global-config container detection (issue #81) ---"
# Broad allows in the opencode user's GLOBAL config must be detected: the
# wrapper evaluates the session's final merged config (`opencode debug
# config`, as the opencode user from the cwd), not just the project file.
# Flip the global template's denies in place (positions kept, credential
# gates stay after the allows), drop the project opt-in.
if [ "$_rootless_ok" = true ]; then
    E 'sudo cp /home/opencode/.config/opencode/opencode.jsonc /tmp/global-jsonc.bak'
    E 'sudo sed -i "s/\"docker \*\": \"deny\"/\"docker *\": \"allow\"/; s/\"ddev \*\": \"deny\"/\"ddev *\": \"allow\"/" /home/opencode/.config/opencode/opencode.jsonc'
    E 'sudo rm -f /var/www/vhosts/test-project/opencode.jsonc'
    E 'cd /var/www/vhosts/test-project && timeout 20 /usr/local/bin/opencode </dev/null 2>&1 | tee /tmp/wrapper-drl-global.txt | { grep -q "will run with" || true; }' &&
        echo "  ${GREEN}OK${NC}  wrapper global-config detection ran"
    check "RL3b: global-config allow detected (banner)" \
        E 'grep -q "Container tools enabled by this project" /tmp/wrapper-drl-global.txt'
    check "RL3b: global-config allow lists docker" \
        E 'grep -q "^    - docker$" /tmp/wrapper-drl-global.txt'
    check "RL3b: global-config allow lists ddev" \
        E 'grep -q "^    - ddev$" /tmp/wrapper-drl-global.txt'
    check "RL3b: global-config allow -> docker-rootless exec message" \
        E 'grep -q "opencode will run with the docker-rootless backend" /tmp/wrapper-drl-global.txt'
    # restore the stock global config
    E 'sudo cp /tmp/global-jsonc.bak /home/opencode/.config/opencode/opencode.jsonc'
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
        # The label names the count (#494 a F1): the tally counts skip
        # EVENTS (1), not the 3 userns/read checks behind this site.
        skip "RL4: alpine pull failed — 3 container userns/read checks not run ($(E 'tail -1 /tmp/docker-pull.out' 2>/dev/null || echo unknown))"
    fi
fi

echo ""
echo "--- RL5. status.sh + config.sh report the docker-rootless backend ---"
if [ "$_rootless_ok" = true ]; then
    check "RL5: status.sh reports the docker-rootless backend" \
        E '/usr/local/lib/opencode-permissions-kit/management/status.sh 2>&1 | grep -Eq "backend +docker-rootless"'
    check "RL5: status.sh reports the socket as reachable" \
        E '/usr/local/lib/opencode-permissions-kit/management/status.sh 2>&1 | grep -Eq "socket +reachable"'
    check "RL5: config.sh container-backend status reports docker-rootless" \
        E 'sudo bash /home/dev/repo/files/opencode-permissions-kit-lib/management/config.sh container-backend status 2>&1 | grep -q "docker-rootless"'
    check "RL5: config.sh container-backend status reports the socket reachable" \
        E 'sudo bash /home/dev/repo/files/opencode-permissions-kit-lib/management/config.sh container-backend status 2>&1 | grep -Eq "socket +reachable"'
fi

echo ""
echo "--- RL6. Uninstall (rootless runtime teardown built in) ---"
# uninstall.sh itself disables linger, stops user@<uid> and resets rootless podman storage so
# userdel -r can remove the opencode user.
OC_UID2=$(E 'id -u opencode')
E 'cd /tmp && sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID2"' docker system prune -af >/dev/null 2>&1" || true'
E 'bash /usr/local/lib/opencode-permissions-kit/management/uninstall.sh --yes' &&
    echo "  ${GREEN}OK${NC}  uninstall.sh completed"
check_fail "Wrapper removed" E 'test -e /usr/local/bin/opencode'
# #681 site 4: the cli loop's own row (the run.sh twin).
check_fail "CLI dispatcher (opk) removed" E 'test -e /usr/local/bin/opk'
check_fail "Library removed" E 'test -e /usr/local/lib/opencode-permissions-kit'
check_fail "Sudoers removed" E 'test -e /etc/sudoers.d/opencode-permissions-kit'
check_fail "/etc/opencode-permissions-kit removed" E 'test -e /etc/opencode-permissions-kit'
check_fail "opencode user removed" E 'id opencode'
check_fail "Audit log removed" E 'test -e /var/log/opencode-permissions-kit'
# #704: the uninstall's default-yes offer dropped the storage config
# (nothing left adopted after RL2c's revert) and the storage directory
# stays as the documented manual-cleanup leftover.
check "RL6: the git-protection storage dir stays (documented leftover)" \
    E 'test -d /var/www/gitdirs'

e2e_finish
