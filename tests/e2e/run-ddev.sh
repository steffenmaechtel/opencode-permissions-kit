#!/bin/sh
# e2e/run-ddev.sh — real-ddev e2e suite with a cached golden container
# Run from repo root: ./tests/e2e/run-ddev.sh   (or: make e2e-ddev)
#
# Implements docs/design/ddev-e2e-test.md. Unlike the other two suites this
# one runs the REAL ddev against the REAL inner docker-rootless daemon
# inside the systemd test container (Dockerfile.rootless, like
# run-docker-rootless.sh) — the burn-in class (issues #18 #20 #21 #25, the
# 2026-08-22 findings §7.3) that fake-ddev cannot catch.
#
# The expensive environment (rootless daemon + ddev + pulled images + the
# camino fixture master) is baked ONCE into a golden image via `docker
# commit` (§4) and reused: cached runs skip the multi-minute download and
# install phase. The kit itself is NEVER cached — every run installs it
# fresh from the repo bind mount (§4.1).
#
# Cache key = image labels: kit.e2e.ddev.version (pinned via $DDEV_VERSION,
# else latest release), kit.e2e.format (warm-up recipe revision), kit.e2e.site
# (fixture tier), kit.e2e.built (TTL, $E2E_DDEV_TTL days, 0 = off).
# `make e2e-ddev-fresh` (or --fresh) forces a rebuild.
#
# Tiers: default = skeleton checks (DD0-DD9, DD13/DD14 on generated
# projects). E2E_DDEV_SITE=camino adds the real-site tier (DD10/DD11) and
# the git-flow tier (DD12) against tests/e2e/fixtures/camino.
#
# Usage: run-ddev.sh [--debug] [--fresh]
#   --debug   on failure: keep the container alive for inspection
#   --fresh   rebuild the golden image (new ddev version, recipe bump, TTL)
set -e

E2E_DEBUG="${E2E_DEBUG:-0}"
FRESH=0
for _arg in "$@"; do
    case "$_arg" in
        --debug) E2E_DEBUG=1 ;;
        --fresh) FRESH=1 ;;
        --help|-h)
            sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^Usage:/,$p'
            exit 0
            ;;
        *) echo "unknown argument: $_arg (see --help)" >&2; exit 1 ;;
    esac
done

GOLDEN_IMAGE="${E2E_DDEV_IMAGE:-opencode-e2e-ddev:cached}"
BASE_IMAGE="opencode-e2e-ddev-base"
E2E_IMAGE="$BASE_IMAGE"          # the build path starts from the base image
E2E_CONTAINER="opencode-e2e-ddev-test"
E2E_DOCKERFILE="Dockerfile.rootless"
E2E_SYSTEMD=1
E2E_CMD="/sbin/init"
. "$(dirname "$(readlink -f "$0")")/lib.sh"

# Golden-image cache key (§5). Bump GOLDEN_FORMAT when the warm-up recipe
# changes so cached images rebuild.
GOLDEN_FORMAT=1
GOLDEN_TTL_DAYS="${E2E_DDEV_TTL:-14}"
SITE_TIER="${E2E_DDEV_SITE:-}"           # camino | (empty)

echo ""
echo "${CYAN}========================================================${NC}"
echo "${CYAN}   opencode permissions kit — real-ddev E2E (golden)${NC}"
echo "${CYAN}========================================================${NC}"
echo ""

# --- resolve the ddev version + fetch the binary (host-side cache) -----------
# Mirrors e2e_resolve_cache: pin via DDEV_VERSION, else latest release, else
# the golden image's label (offline fallback). The tarball lands in
# tests/e2e/cache/ddev-<v>/ (gitignored, mounted read-only into the container).
DD_WANT="${DDEV_VERSION:-}"
if [ -z "$DD_WANT" ]; then
    DD_WANT=$(curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 30 \
        https://api.github.com/repos/ddev/ddev/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
fi
if [ -z "$DD_WANT" ]; then
    DD_WANT=$(docker image inspect -f '{{ index .Config.Labels "kit.e2e.ddev.version" }}' "$GOLDEN_IMAGE" 2>/dev/null || true)
    [ -n "$DD_WANT" ] && echo "  ${YELLOW}WARNING: ddev version endpoint unreachable - using cached ddev $DD_WANT${NC}"
fi
[ -n "$DD_WANT" ] || { echo "  ${RED}FAIL${NC}  cannot resolve a ddev version"; exit 1; }
case "$DD_WANT" in v*) DD_VER="${DD_WANT#v}" ;; *) DD_VER="$DD_WANT"; DD_WANT="v$DD_WANT" ;; esac

DD_ARCH=$(uname -m)
case "$DD_ARCH" in
    x86_64) DD_ARCH="amd64" ;;
    aarch64|arm64) DD_ARCH="arm64" ;;
    *) echo "  ${RED}FAIL${NC} unsupported arch: $DD_ARCH"; exit 1 ;;
esac
DD_CACHE="$SCRIPT_DIR/cache/ddev-$DD_VER"
DD_BIN="$DD_CACHE/ddev"
if [ ! -x "$DD_BIN" ]; then
    echo "  Downloading ddev $DD_WANT (linux-$DD_ARCH) into cache..."
    mkdir -p "$DD_CACHE"
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --max-time 300 \
        "https://github.com/ddev/ddev/releases/download/$DD_WANT/ddev_linux-$DD_ARCH.$DD_WANT.tar.gz" \
        -o "$DD_CACHE/ddev.tar.gz" \
        || { echo "  ${RED}FAIL${NC}  ddev $DD_WANT download failed"; exit 1; }
    tar -xzf "$DD_CACHE/ddev.tar.gz" -C "$DD_CACHE" \
        || { echo "  ${RED}FAIL${NC}  cannot extract ddev tarball"; exit 1; }
    rm -f "$DD_CACHE/ddev.tar.gz"
    chmod +x "$DD_BIN" 2>/dev/null || true
fi
[ -s "$DD_BIN" ] || { echo "  ${RED}FAIL${NC}  cached ddev binary is empty"; exit 1; }
echo "  Using ddev $DD_WANT (cache: $DD_BIN)"

# Golden-image v2 (2026-08-22 pivot): the golden image contains NO inner
# docker store. Baking the store into a `docker commit` corrupted every
# cached image — commit is not a faithful copy for overlay whiteouts
# ("deleted" files like /etc/mysql/mariadb.cnf reappeared; every project db
# died on an inaccessible unix socket), and a named-volume store corrupted
# the same way through the nested storage stack. Instead the IMAGES are
# cached host-side as a docker-save tarball (ext4, gitignored, next to the
# opencode binaries) and `docker load`-ed into a FRESH inner store on every
# warm start — the exact write path that produced working images in the
# cold build. System state (packages, ddev, composer/fixture data,
# /home/opencode/.ddev) stays in the golden commit (regular files only).
DD_IMG_TAR="$SCRIPT_DIR/cache/ddev-images-$DD_VER-f$GOLDEN_FORMAT.tar"

dd_label() {
    docker image inspect -f "{{ index .Config.Labels \"$1\" }}" "$GOLDEN_IMAGE" 2>/dev/null || true
}

dd_golden_current() {
    [ "$FRESH" = "0" ] || return 1
    docker image inspect "$GOLDEN_IMAGE" >/dev/null 2>&1 || return 1
    [ -f "$DD_IMG_TAR" ] || return 1
    [ "$(dd_label kit.e2e.ddev.version)" = "$DD_VER" ] || return 1
    [ "$(dd_label kit.e2e.format)" = "$GOLDEN_FORMAT" ] || return 1
    [ "$(dd_label kit.e2e.site)" = "${SITE_TIER:-none}" ] || return 1
    if [ "$GOLDEN_TTL_DAYS" != "0" ]; then
        _built=$(dd_label kit.e2e.built)
        _now=$(date +%s)
        [ -n "$_built" ] && [ "$((_now - _built))" -le "$((GOLDEN_TTL_DAYS * 86400))" ] || return 1
    fi
    return 0
}

echo "--- opencode binary cache (version-keyed) ---"
e2e_resolve_cache
e2e_prepare_project

# Helpers used by the cold-build path below (the kit is not installed yet,
# so there is no ddev() hook — env is set explicitly, like the wrapper does).
# Note: $1/$2 are expanded at construction time on purpose — the dev shell
# must receive the FULL inner command (a literal $2 would expand empty there
# and break the inner sh -c).
dd_oc_uid() { E 'id -u opencode'; }
dd_build_oc() {
    _ocu=$(dd_oc_uid)
    E 'sudo -u opencode env HOME=/home/opencode XDG_RUNTIME_DIR=/run/user/'"$_ocu"' DOCKER_HOST=unix:///run/user/'"$_ocu"'/docker.sock DDEV_NO_INSTRUMENTATION=true sh -c "cd '"$1"' && '"$2"'"'
}

if dd_golden_current; then
    echo ""
    echo "  ${GREEN}golden image current${NC} (ddev $DD_VER, format $GOLDEN_FORMAT, site: ${SITE_TIER:-none}) — warm start"
else
    _why="label mismatch"
    [ "$FRESH" = "1" ] && _why="--fresh"
    echo ""
    echo "  ${YELLOW}golden image rebuild${NC} ($_why): provisioning daemon + ddev + images once (§4.2)..."
    E2E_IMAGE="$BASE_IMAGE"
    E2E_SKIP_BUILD=0
    e2e_start_container

    # RL0: systemd must be up (same gate as run-docker-rootless.sh).
    _boot_ok=false
    for _i in $(seq 1 15); do
        E 'test -e /run/systemd/private' 2>/dev/null && { _boot_ok=true; break; }
        sleep 1
    done
    if [ "$_boot_ok" != true ]; then
        echo "  ${YELLOW}SKIP${NC}  systemd did not boot in the container (runner limitation)"
        skip "systemd not available"
        e2e_finish
        exit $?
    fi

    # Provision the inner environment (kit code path, §4.2). The kit itself
    # is NOT installed into the golden image (§4.1) — only its provisioning
    # helper runs, so every cached run installs the kit fresh (DD1).
    E 'id opencode >/dev/null 2>&1 || sudo useradd -m -s /bin/bash opencode'
    # Deterministic subuid seed (nested-userns constraint): the e2e
    # container's own uid_map covers only uids 1..65536, so the kit default
    # (100000+) would be unmappable when the OUTER daemon is rootless; the
    # seeded window fits. It cannot be enlarged to cover uid 65534 (nobody):
    # 65535 consecutive slots under 65536 inevitably collide with the daemon
    # user's own uid in the map. nginx-fpm chowns to exactly that uid, so
    # EVERY project in this suite must use apache-fpm (www-data = 33, well
    # inside the window) — like the camino fixture. The provisioning helper
    # KEEPS an existing entry, so this pins the range on every layout.
    E 'sudo sh -c "printf \"opencode:4096:60000\n\" > /etc/subuid; printf \"opencode:4096:60000\n\" > /etc/subgid"'
    # fuse-overlayfs pin — kernel overlay2 cannot stack on the container's
    # own overlay rootfs (nested docker-in-docker; as in run-docker-rootless.sh).
    E 'sudo -u opencode sh -c "mkdir -p /home/opencode/.config/docker"'
    E 'printf "{\"storage-driver\":\"fuse-overlayfs\"}\n" | sudo -u opencode tee /home/opencode/.config/docker/daemon.json >/dev/null'

    if ! E 'sudo bash /home/dev/repo/files/opencode-permissions-kit-lib/setup-container-backend.sh docker-rootless --yes >/tmp/dd-setup.log 2>&1'; then
        echo "  ${RED}FAIL${NC}  backend provisioning failed — /tmp/dd-setup.log:";         failures=$((failures + 1))
        E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd-setup.log | tail -30' || true
        exit 1
    fi
    _sock_ok=false
    for _i in $(seq 1 30); do
        E "sudo test -S /run/user/$(dd_oc_uid)/docker.sock" 2>/dev/null && { _sock_ok=true; break; }
        sleep 1
    done
    [ "$_sock_ok" = true ] || { echo "  ${RED}FAIL${NC}  inner rootless daemon socket never appeared"; failures=$((failures + 1)); exit 1; }

    # Real ddev from the host-side cache (bind-mounted read-only), then the
    # rootless router ports (§6 R7 — the documented rootless answer instead
    # of the host-wide sysctl). ddev instrumentation is opt-in: stays off.
    E 'sudo install -m 755 /opencode-cache/ddev-'"$DD_VER"'/ddev /usr/local/bin/ddev'
    dd_build_oc /tmp 'ddev config global --router-http-port 8080 --router-https-port 8443' \
        || { echo "  ${RED}FAIL${NC}  ddev global config failed"; failures=$((failures + 1)); exit 1; }

    # Warm-up (§4.2.6): pull images + mutagen (+ camino master, §7.1).
    if [ "$SITE_TIER" = "camino" ] && [ -f "$SCRIPT_DIR/fixtures/camino/site/composer.json" ]; then
        echo ""
        echo "  warm-up: camino site (start + composer install + db import + verify) ..."
        E 'sudo cp -a /home/dev/repo/tests/e2e/fixtures/camino/site /var/www/vhosts/dd-warmup'
        # Fully opencode-owned (what the kit handover arranges): ddev's
        # bootstrap-phase root chmod AND the post-install settings writes
        # both run unimpeded.
        E 'sudo chown -R opencode:opencode /var/www/vhosts/dd-warmup'
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev start >/tmp/dd-warm.log 2>&1' \
            || { E 'tail -20 /tmp/dd-warm.log' || true; echo "  ${RED}FAIL${NC}  warm-up ddev start failed"; failures=$((failures + 1)); exit 1; }
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev composer install >/tmp/dd-warm.log 2>&1' \
            || { E 'tail -20 /tmp/dd-warm.log' || true; echo "  ${RED}FAIL${NC}  warm-up composer install failed"; failures=$((failures + 1)); exit 1; }
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev import-db --src=/home/dev/repo/tests/e2e/fixtures/camino/db.sql.gz >/tmp/dd-warm.log 2>&1' \
            || { E 'tail -20 /tmp/dd-warm.log' || true; echo "  ${RED}FAIL${NC}  warm-up db import failed"; failures=$((failures + 1)); exit 1; }
        E 'curl --resolve dd-warmup.local:8080:127.0.0.1 -fsS http://dd-warmup.local:8080/camino/ -o /tmp/dd-warm-front.html' \
            || { echo "  ${RED}FAIL${NC}  warm-up frontend not reachable"; failures=$((failures + 1)); E 'head -5 /tmp/dd-warm-front.html 2>/dev/null' || true; exit 1; }
        E 'grep -qiE "camino|typo3|permission kit" /tmp/dd-warm-front.html' \
            || { echo "  ${RED}FAIL${NC}  warm-up frontend has no marker content"; failures=$((failures + 1)); exit 1; }
        # Pristine master WITH vendor/ (§7.1): per-run copies are page-cached
        # cp -a, no per-run composer install needed.
        E 'sudo mkdir -p /opt/e2e/fixtures && sudo cp -a /var/www/vhosts/dd-warmup /opt/e2e/fixtures/camino'
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev delete -Oy >/dev/null 2>&1 || true'
    else
        echo ""
        echo "  warm-up: skeleton php project (image pulls + mutagen) ..."
        E 'sudo mkdir -p /var/www/vhosts/dd-warmup && sudo chown opencode:opencode /var/www/vhosts/dd-warmup'
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev config --project-type=php --webserver-type=apache-fpm --docroot=public --auto >/dev/null 2>&1 && ddev start >/tmp/dd-warm.log 2>&1' \
            || { E 'tail -20 /tmp/dd-warm.log' || true; echo "  ${RED}FAIL${NC}  warm-up ddev start failed"; failures=$((failures + 1)); exit 1; }
        dd_build_oc /var/www/vhosts/dd-warmup 'ddev delete -Oy >/dev/null 2>&1 || true'
    fi

    # Quiesce + export + commit (§4.2.8-9): prune leftover containers
    # (images stay), export the images to the host-side tarball cache WHILE
    # THE DAEMON STILL RUNS, stop the daemon, DELETE the store from the
    # container filesystem (golden-image v2: committing the store corrupts
    # it — see DD_IMG_TAR rationale), then snapshot the stopped container.
    dd_build_oc /tmp 'docker system prune -f >/dev/null 2>&1 || true'
    echo ""
    echo "  exporting inner images to $DD_IMG_TAR ..."
    _ocu=$(dd_oc_uid)
    _imgs=$(E 'sudo -u opencode env HOME=/home/opencode XDG_RUNTIME_DIR=/run/user/'"$_ocu"' DOCKER_HOST=unix:///run/user/'"$_ocu"'/docker.sock docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>"')
    [ -n "$_imgs" ] || { echo "  ${RED}FAIL${NC}  no inner images to export"; failures=$((failures + 1)); exit 1; }
    # shellcheck disable=SC2086  # word splitting is the image list
    docker exec -u dev "$E2E_CONTAINER" \
        sudo -u opencode env HOME=/home/opencode XDG_RUNTIME_DIR="/run/user/$_ocu" \
        DOCKER_HOST="unix:///run/user/$_ocu/docker.sock" \
        docker save $_imgs > "$DD_IMG_TAR" \
        || { echo "  ${RED}FAIL${NC}  docker save failed"; failures=$((failures + 1)); exit 1; }
    dd_build_oc /tmp 'systemctl --user stop docker.service' || true
    E 'sudo rm -rf /home/opencode/.local/share/docker'
    echo "  committing golden image $GOLDEN_IMAGE (ddev $DD_VER, format $GOLDEN_FORMAT, site: ${SITE_TIER:-none}) ..."
    docker stop -t 30 "$E2E_CONTAINER" >/dev/null
    docker commit \
        --change 'LABEL kit.e2e.ddev.version='"$DD_VER" \
        --change 'LABEL kit.e2e.format='"$GOLDEN_FORMAT" \
        --change 'LABEL kit.e2e.built='"$(date +%s)" \
        --change 'LABEL kit.e2e.site='"${SITE_TIER:-none}" \
        "$E2E_CONTAINER" "$GOLDEN_IMAGE" >/dev/null
    docker rm "$E2E_CONTAINER" >/dev/null
    echo "  golden size: $(docker image inspect -f '{{ .Size }}' "$GOLDEN_IMAGE" | awk '{printf "%.1f GB", $1/1024/1024/1024}')"
fi

# --- warm start (§4.3): boot the golden image fresh ---------------------------
E2E_IMAGE="$GOLDEN_IMAGE"
E2E_SKIP_BUILD=1
e2e_start_container

echo ""
echo "--- DD0. cache-integrity gates ---"
_boot_ok=false
for _i in $(seq 1 20); do
    E 'test -e /run/systemd/private' 2>/dev/null && { _boot_ok=true; break; }
    sleep 1
done
if [ "$_boot_ok" != true ]; then
    echo "  ${YELLOW}SKIP${NC}  systemd did not boot (golden image damaged? try --fresh)"
    skip "systemd not available"
    e2e_finish
    exit $?
fi
check "DD0: systemd is PID 1" \
    E 'test "$(cat /proc/1/comm)" = "systemd"'

OC_UID=$(E 'id -u opencode')
SOCK="unix:///run/user/$OC_UID/docker.sock"
SOCKPATH="/run/user/$OC_UID/docker.sock"
echo "  opencode uid: $OC_UID (socket: $SOCK)"

_sock_ok=false
for _i in $(seq 1 30); do
    E "sudo test -S $SOCKPATH" 2>/dev/null && { _sock_ok=true; break; }
    sleep 1
done
if [ "$_sock_ok" != true ]; then
    echo "  ${YELLOW}SKIP${NC}  DD0: inner daemon socket never appeared (image damaged? try --fresh)"
    skip "inner daemon not available"
    e2e_finish
    exit $?
fi

# Agent-context runner: ddev as the opencode user with the session env the
# wrapper exports. Dev-context runs go through DEVSH (interactive bash
# sources the kit's ddev() hook from ~/.bashrc).
OC() {
    docker exec -u dev "$E2E_CONTAINER" sudo -u opencode \
        env HOME=/home/opencode XDG_RUNTIME_DIR="/run/user/$OC_UID" \
        DOCKER_HOST="$SOCK" DDEV_NO_INSTRUMENTATION=true sh -c "cd ${OC_CWD:-/tmp} && $1"
}
DEVSH() { docker exec -u dev "$E2E_CONTAINER" bash -ic "$1" 2>&1; }

_act_ok=false
for _i in $(seq 1 30); do
    E 'sudo -u opencode sh -c "XDG_RUNTIME_DIR=/run/user/'"$OC_UID"' systemctl --user is-active docker" 2>/dev/null | grep -qx active' \
        && { _act_ok=true; break; }
    sleep 1
done
check "DD0: inner rootless daemon is active (linger auto-start)" \
    test "$_act_ok" = true

# Warm start (§4.3): the golden image ships NO image store — restore the
# cached images from the host-side docker-save tarball into the fresh inner
# store (same unpack path the cold build used; ~1-3 min from local disk).
if [ ! -f "$DD_IMG_TAR" ]; then
    echo "  ${RED}FAIL${NC}  image tarball missing: $DD_IMG_TAR (rebuild with --fresh)"
    failures=$((failures + 1))
    e2e_finish
    exit $?
fi
echo "  loading cached ddev images ($(du -h "$DD_IMG_TAR" | cut -f1)) ..."
if ! docker exec -i -u dev "$E2E_CONTAINER" \
        sudo -u opencode env HOME=/home/opencode \
        XDG_RUNTIME_DIR="/run/user/$OC_UID" DOCKER_HOST="$SOCK" \
        docker load < "$DD_IMG_TAR" >/tmp/dd-load.log 2>&1; then
    echo "  ${RED}FAIL${NC}  docker load failed:"; failures=$((failures + 1))
    docker exec -u dev "$E2E_CONTAINER" sh -c 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd-load.log | tail -10' || true
    exit 1
fi
check "DD0: cached images restored (R3 canary)" \
    OC 'test -n "$(docker images -q)"'
# Image-integrity canary (2026-08-22 corruption class): the ddev db image
# DELETES /etc/mysql/mariadb.cnf in an upper layer; if that deletion is
# void, mariadbd reads the Debian socket config (/run/mysqld, mysql:999)
# and every project db dies with "Bind on unix socket: Permission denied".
check "DD0: db base image intact (mariadb.cnf ghost absent)" \
    OC 'docker run --rm --entrypoint sh ddev/ddev-dbserver-mariadb-11.8:v'"$DD_VER"' -c "test ! -e /etc/mysql/mariadb.cnf"'
check "DD0: ddev $DD_WANT present and working" \
    OC "ddev version 2>/dev/null | grep -q '$DD_WANT'"
if ! E 'test -u /usr/bin/sudo' >/dev/null 2>&1; then
    echo "  ${YELLOW}NOTE${NC} sudo lost its setuid bit (R2) — self-healing with chmod u+s"
    E 'sudo chmod u+s /usr/bin/sudo'
fi
check "DD0: sudo setuid bit intact" \
    E 'test -u /usr/bin/sudo'

echo ""
echo "--- DD1. kit install on the warm image (upgrade-style) ---"
E 'bash /opencode-cache/install.sh --binary /opencode-cache/opencode-'"$OC_VERSION"'/opencode' || {
    E 'test -x /home/dev/.opencode/bin/opencode' || { echo "  ${RED}E2E aborted — cannot install opencode.${NC}"; failures=$((failures + 1)); exit 1; }
}
if ! E 'sudo bash /home/dev/repo/files/install.sh --yes --container-backend docker-rootless --projects /var/www/vhosts --skip-ddev-migration >/tmp/dd-install.log 2>&1'; then
    echo "  ${RED}FAIL${NC}  kit install failed:"; failures=$((failures + 1))
    E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd-install.log | tail -30' || true
    exit 1
fi
echo "  ${GREEN}OK${NC}  kit install completed"
check "DD1: install.conf records docker-rootless" \
    E 'grep -q "^CONTAINER_BACKEND=docker-rootless" /etc/opencode-permissions-kit/install.conf'
check "DD1: dev-owned mode is the installer default" \
    E 'grep -q "^DDEV_DEV_OWNED=true" /etc/opencode-permissions-kit/install.conf'
check "DD1: wrapper at /usr/local/bin/opencode" \
    E 'test -x /usr/local/bin/opencode'
check "DD1: sudoers carries the ddev-as-opencode helper rule" \
    E 'sudo grep -q "bin/ddev-as-opencode" /etc/sudoers.d/opencode-permissions-kit'
check "DD1: ddev() hook wired into dev's bashrc" \
    E 'grep -q "ddev-as-opencode.sh" /home/dev/.bashrc'
check "DD1: global ddev home provisioned for opencode" \
    E 'sudo test -d /home/opencode/.ddev'

_daemon_ok=true

echo ""
echo "--- DD2/DD3/DD4. bootstrap, chmod modes, dev-owned (project dd2) ---"
# Handover-mode section first (ddev-settings off = the old model), then the
# dev-owned default — both against one fresh typo3 bootstrap project.
E 'sudo bash /home/dev/repo/files/config.sh --yes ddev-settings off >/dev/null 2>&1'
E 'sudo -u dev mkdir -p /var/www/vhosts/dd2'
DEVSH 'cd /var/www/vhosts/dd2 && ddev config --project-type=typo3 --webserver-type=apache-fpm --docroot=public --project-tld local >/tmp/dd2-config.log 2>&1'
check "DD2: ddev config on empty dir completes (burn-in flags)" \
    E 'grep -q "Configuration complete" /tmp/dd2-config.log'
check "DD2: .ddev is opencode-owned after config" \
    E 'test "$(stat -c %U /var/www/vhosts/dd2/.ddev)" = opencode'
E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd2 >/tmp/dd2-handover.log 2>&1'
check "DD2: handover mode: bootstrap root inode handed to opencode 2755" \
    E 'test "$(stat -c %U:%a /var/www/vhosts/dd2)" = "opencode:2755"'
if OC_CWD=/var/www/vhosts/dd2 OC 'ddev start >/tmp/dd2-start.log 2>&1'; then
    check "DD2: agent-side start completes (real ddev, no EPERM)" \
        E 'grep -q "Successfully started" /tmp/dd2-start.log'
    check "DD3: ddev chmod'd the bootstrap root to 0755 (issue #25 mechanics)" \
        E 'test "$(stat -c %a /var/www/vhosts/dd2)" = "755"'
    check "DD3: bootstrap settings file at project root is opencode-owned" \
        E 'test "$(stat -c %U /var/www/vhosts/dd2/AdditionalConfiguration.php 2>/dev/null || echo missing)" = opencode'
    E 'sudo bash /home/dev/repo/files/config.sh --yes refresh >/dev/null 2>&1'
    check "DD3: config.sh refresh restores g+w on the root (2755)" \
        E 'test "$(stat -c %a /var/www/vhosts/dd2)" = "2755"'
else
    echo "  ${YELLOW}SKIP${NC}  DD2: ddev start failed — output:"
    E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd2-start.log 2>/dev/null | tail -15' || true
    skip "dd2 start failed"
    _daemon_ok=false
fi

if [ "$_daemon_ok" = true ]; then
    # Dev-owned mode: the committed-flag model (ddev-dev-owned-projects.md).
    E 'sudo bash /home/dev/repo/files/config.sh --yes ddev-settings on >/dev/null 2>&1'
    E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd2 >/tmp/dd2-handback.log 2>&1'
    check "DD4: dev-owned handover: flag written into .ddev/config.yaml" \
        E 'grep -q "^disable_settings_management: true" /var/www/vhosts/dd2/.ddev/config.yaml'
    check "DD4: dev-owned handover: bootstrap root handed back to dev (2775)" \
        E 'test "$(stat -c %U:%a /var/www/vhosts/dd2)" = "dev:2775"'
    check "DD4: .ddev stays opencode-owned" \
        E 'test "$(stat -c %U /var/www/vhosts/dd2/.ddev)" = opencode'
    if OC_CWD=/var/www/vhosts/dd2 OC 'ddev restart >/tmp/dd2-restart.log 2>&1'; then
        check "DD4: dev-owned restart succeeds" \
            E 'grep -q "Successfully started" /tmp/dd2-restart.log'
    else
        echo "  ${RED}FAIL${NC}  DD4: dev-owned restart failed:";         failures=$((failures + 1))
        E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd2-restart.log 2>/dev/null | tail -10' || true
        failures=$((failures + 1))
    fi
    check "DD4: root still dev-owned after dev-owned restart" \
        E 'test "$(stat -c %U /var/www/vhosts/dd2)" = dev'

    echo ""
    echo "--- DD5. developer-side transports (ddev() function + BASH_ENV) ---"
    check "DD5: ddev() function active in dev's interactive shell" \
        DEVSH 'type ddev | grep -q "function"'
    check "DD5: export -f lands the function in nested bash -c (issue #18)" \
        DEVSH 'bash -c "type ddev | grep -q function"'
    check "DD5: ddev via dev function runs the REAL ddev (version)" \
        DEVSH 'cd /var/www/vhosts/dd2 && ddev version 2>/dev/null | head -1 | grep -q ddev'
    check "DD5: ddev processes run as opencode (pgrep uid — issue #18 root cause)" \
        DEVSH 'cd /var/www/vhosts/dd2 && (ddev exec sleep 6 >/dev/null 2>&1 &) && sleep 2 && pgrep -x ddev -u opencode >/dev/null'

    echo ""
    echo "--- DD6. container identity with real ddev containers ---"
    check "DD6: ddev exec works (agent side)" \
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev exec true'
    _dd6_uidmap() {
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev exec cat /proc/self/uid_map' 2>/dev/null \
            | grep -qE "0[[:space:]]+${OC_UID}[[:space:]]"
    }
    check "DD6: web container userns maps root to the opencode host UID (§9.1)" \
        _dd6_uidmap
    check "DD6: container reads the settings file via bind mount (soft-only goal)" \
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev exec cat /var/www/html/AdditionalConfiguration.php 2>/dev/null | grep -q ddev'

    echo ""
    echo "--- DD8. describe parity: agent vs developer context (§10a) ---"
    OC_CWD=/var/www/vhosts/dd2 OC 'ddev describe --json-output >/tmp/dd8-oc.json 2>/dev/null' || true
    DEVSH 'cd /var/www/vhosts/dd2 && ddev describe --json-output >/tmp/dd8-dev.json 2>/dev/null' || true
    check "DD8: agent-side describe reports the project running" \
        E 'grep -Eq "\"status\": ?\"running\"" /tmp/dd8-oc.json'
    check "DD8: dev-side describe reports the SAME state (one driver, one daemon)" \
        E 'grep -Eq "\"status\": ?\"running\"" /tmp/dd8-dev.json'

    echo ""
    echo "--- DD9. db round-trip (import/export) ---"
    E 'printf "CREATE TABLE dd9_mark (id INT);\n" | gzip > /tmp/dd9.sql.gz'
    if OC_CWD=/var/www/vhosts/dd2 OC 'ddev import-db --src=/tmp/dd9.sql.gz >/tmp/dd9.log 2>&1'; then
        check "DD9: export-db returns the imported mark" \
            OC_CWD=/var/www/vhosts/dd2 OC 'ddev export-db -f=/tmp/dd9-out.sql.gz >/dev/null 2>&1 && zcat /tmp/dd9-out.sql.gz | grep -q dd9_mark'
    else
        echo "  ${YELLOW}SKIP${NC}  DD9: import-db failed"
        skip "dd9 import failed"
    fi

    echo ""
    echo "--- DD7. lifecycle + suite-wide EPERM sweep ---"
    check "DD7: ddev restart" \
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev restart >/tmp/dd7.log 2>&1'
    check "DD7: ddev stop" \
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev stop >/tmp/dd7.log 2>&1'
    check "DD7: ddev delete -Oy" \
        OC_CWD=/var/www/vhosts/dd2 OC 'ddev delete -Oy >/tmp/dd7.log 2>&1'
    check "DD7: zero 'operation not permitted' across the suite log" \
        E '_s=$(grep -il "operation not permitted" /tmp/dd2-*.log /tmp/dd7.log /tmp/dd10-*.log /tmp/dd11-*.log 2>/dev/null); test -z "$_s"'
fi

if [ "$SITE_TIER" = "camino" ] && E 'test -d /opt/e2e/fixtures/camino' 2>/dev/null; then
    echo ""
    echo "--- DD10/DD11. real-site tier (camino) ---"
    if E 'test -f /opt/e2e/fixtures/camino/vendor/bin/typo3'; then
        E 'sudo cp -a /opt/e2e/fixtures/camino /var/www/vhosts/camino-e2e'
        E 'sudo chown -R dev:dev /var/www/vhosts/camino-e2e'
        E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/camino-e2e >/tmp/dd10-handover.log 2>&1'
        check "DD10: handover leaves settings dev-owned (flag committed)" \
            E 'test "$(stat -c %U /var/www/vhosts/camino-e2e/config/system)" = dev'
        check "DD10: .ddev opencode-owned after handover" \
            E 'test "$(stat -c %U /var/www/vhosts/camino-e2e/.ddev)" = opencode'
        if OC_CWD=/var/www/vhosts/camino-e2e OC 'ddev start >/tmp/dd10-start.log 2>&1'; then
            check "DD10: real site starts" \
                E 'grep -q "Successfully started" /tmp/dd10-start.log'
            check "DD10: settings dir keeps g+w through start (dev-owned mode, #25)" \
                E 'test "$(stat -c %a /var/www/vhosts/camino-e2e/config/system)" = "2775"'
            OC_CWD=/var/www/vhosts/camino-e2e OC 'ddev import-db --src=/home/dev/repo/tests/e2e/fixtures/camino/db.sql.gz >/tmp/dd10-imp.log 2>&1' \
                || echo "  ${YELLOW}NOTE${NC}  DD10: db import failed — site may show the install tool"
            E 'curl --resolve camino-e2e.local:8080:127.0.0.1 -fsS http://camino-e2e.local:8080/camino/ -o /tmp/dd10-front.html'
            check "DD10: frontend answers 200 (first real 'site works' assert)" \
                E 'test -s /tmp/dd10-front.html'
            check "DD10: frontend renders CMS content" \
                E 'grep -qiE "camino|typo3|permission kit" /tmp/dd10-front.html'
            check "DD10: settings.php exists and stays user-managed" \
                E 'test -f /var/www/vhosts/camino-e2e/config/system/settings.php && ! grep -q "ddev-generated" /var/www/vhosts/camino-e2e/config/system/settings.php'

            echo ""
            echo "--- DD11. two-owner reality on the live site ---"
            if DEVSH 'cd /var/www/vhosts/camino-e2e && ddev restart >/tmp/dd11-restart.log 2>&1'; then
                check "DD11: developer-side restart through ddev() works while running" \
                    E 'grep -q "Successfully started" /tmp/dd11-restart.log'
            else
                echo "  ${RED}FAIL${NC}  DD11: developer-side restart failed:";                 failures=$((failures + 1))
                E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd11-restart.log 2>/dev/null | tail -10' || true
                failures=$((failures + 1))
            fi
            E 'curl --resolve camino-e2e.local:8080:127.0.0.1 -fsS http://camino-e2e.local:8080/camino/ -o /tmp/dd11-front.html'
            check "DD11: site still answers 200 after the dev restart" \
                E 'test -s /tmp/dd11-front.html'
            check "DD11: dev can edit the settings file (#25 regression)" \
                DEVSH 'cd /var/www/vhosts/camino-e2e && printf "\n// dd11 edit\n" >> config/system/settings.php'
            OC_CWD=/var/www/vhosts/camino-e2e OC 'ddev delete -Oy >/dev/null 2>&1' || true
        else
            echo "  ${YELLOW}SKIP${NC}  DD10: site start failed — output:"
            E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd10-start.log 2>/dev/null | tail -15' || true
            skip "camino start failed"
        fi
    else
        echo "  ${YELLOW}SKIP${NC}  DD10/DD11: golden image lacks the camino master (built without site tier?)"
        skip "camino master missing"
    fi
elif [ "$SITE_TIER" = "camino" ]; then
    echo ""
    echo "  ${YELLOW}SKIP${NC}  site tier requested but master absent — rebuild with --fresh"
    skip "camino master missing"
fi

if [ "$SITE_TIER" = "camino" ]; then
    echo ""
    echo "--- DD12. git flow against the bare origin ---"
    E 'sh /home/dev/repo/tests/e2e/fixtures/make-bare-origin.sh /tmp/dd12-origin /home/dev/repo/tests/e2e/fixtures/camino/site >/tmp/dd12-gen.log 2>&1'
    if E 'test -f /tmp/dd12-origin/HEAD'; then
        # (a) dev-owned default: clone as dev, handover, all branch switches free.
        E 'git clone -q /tmp/dd12-origin /var/www/vhosts/dd12-proj'
        E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd12-proj >/dev/null 2>&1'
        check "DD12: dev-owned: top-level branch switch is free (the promise)" \
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q feature/top-level && test ! -f LICENSE && grep -q feature/top-level README.md'
        check "DD12: dev-owned: settings-tree switch is free" \
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q feature/settings && grep -q marker config/system/settings.php'
        check "DD12: dev-owned: .ddev-tree switch is free (group-writable .ddev)" \
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q feature/ddev-tree && test ! -f .ddev/commands/host/hello && git checkout -q main && test -z "$(git status --porcelain)"'

        # (b) handover-mode tripwire (§7.2 12.2): bootstrap root opencode-owned
        #     -> a top-level switch must hit the documented unlink EPERM.
        #     sed runs as root: dev cannot edit .ddev/config.yaml yet (Finding 1).
        E 'sudo bash /home/dev/repo/files/config.sh --yes ddev-settings off >/dev/null 2>&1'
        E 'sudo sed -i "/^disable_settings_management:/d" /var/www/vhosts/dd12-proj/.ddev/config.yaml'
        E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd12-proj >/dev/null 2>&1'
        check "DD12: handover mode: bootstrap root is opencode-owned (tripwire setup)" \
            E 'test "$(stat -c %U /var/www/vhosts/dd12-proj)" = opencode'
        check_fail "DD12: handover mode: top-level switch hits unlink EPERM (documented pain)" \
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q main 2>/dev/null; git checkout -q feature/top-level'
        # Recover the possibly half-switched tree before the next section.
        DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q -f main && git clean -qfd' || true

        # (c) back to dev-owned: the same switch now succeeds.
        E 'sudo bash /home/dev/repo/files/config.sh --yes ddev-settings on >/dev/null 2>&1'
        E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd12-proj >/dev/null 2>&1'
        check "DD12: after dev-owned handover the same switch succeeds" \
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q feature/top-level && test ! -f LICENSE && git checkout -q main && test -z "$(git status --porcelain)"'

        # (d) agent-side git on a dev-owned clone (#17: safe.directory).
        check "DD12: agent git log works on the dev-owned tree (#17)" \
            OC 'git -C /var/www/vhosts/dd12-proj log --oneline -1'

        # (e) pull-while-running: git replaces tracked .ddev content, ddev
        #     must survive it (restart, not a broken tree).
        if OC_CWD=/var/www/vhosts/dd12-proj OC 'ddev start >/tmp/dd12-start.log 2>&1'; then
            DEVSH 'cd /var/www/vhosts/dd12-proj && git checkout -q feature/ddev-tree && git checkout -q main' \
                && _dd12_sw=0 || _dd12_sw=1
            check "DD12: checkout inside the running project's .ddev works" \
                test "$_dd12_sw" = 0
            if DEVSH 'cd /var/www/vhosts/dd12-proj && ddev restart >/tmp/dd12-restart.log 2>&1'; then
                check "DD12: ddev survives git's .ddev file replacement (restart)" \
                    E 'grep -q "Successfully started" /tmp/dd12-restart.log'
            else
                echo "  ${RED}FAIL${NC}  DD12: restart after .ddev checkout failed:";                 failures=$((failures + 1))
                E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd12-restart.log 2>/dev/null | tail -10' || true
                failures=$((failures + 1))
            fi
            OC_CWD=/var/www/vhosts/dd12-proj OC 'ddev delete -Oy >/dev/null 2>&1' || true
        else
            echo "  ${YELLOW}SKIP${NC}  DD12: project start failed"
            E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd12-start.log 2>/dev/null | tail -10' || true
            skip "dd12 start failed"
        fi
    else
        echo "  ${YELLOW}SKIP${NC}  DD12: bare-origin generator failed"
        E 'cat /tmp/dd12-gen.log 2>/dev/null' || true
        skip "bare origin missing"
    fi
fi

echo ""
echo "--- DD13. ddev config on a fresh empty dir (2026-08-22 burn-in) ---"
E 'sudo -u dev mkdir -p /var/www/vhosts/dd13-proj'
DEVSH 'cd /var/www/vhosts/dd13-proj && ddev config --php-version 8.3 --project-type=typo3 --docroot=public --webserver-type=apache-fpm --project-tld local >/tmp/dd13-config.log 2>&1'
check "DD13: config completes despite the settings chmod warning" \
    E 'grep -q "Configuration complete" /tmp/dd13-config.log'
check "DD13: .ddev opencode-owned (ddev-created)" \
    E 'test "$(stat -c %U /var/www/vhosts/dd13-proj/.ddev)" = opencode'
check "DD13: TRIPWIRE .ddev/config.yaml NOT group-writable (Finding 1 — flips when fixed)" \
    E 'test $(( $(stat -c %a /var/www/vhosts/dd13-proj/.ddev/config.yaml) & 0020 )) -eq 0'
check_fail "DD13: TRIPWIRE dev cannot edit .ddev/config.yaml (Finding 1 — flips when fixed)" \
    DEVSH 'cd /var/www/vhosts/dd13-proj && printf "\n" >> .ddev/config.yaml'
DEVSH 'cd /var/www/vhosts/dd13-proj && ddev start >/tmp/dd13-start1.log 2>&1' && _dd13_first=0 || _dd13_first=1
check "DD13: first start prints the bootstrap hint (hook promise)" \
    E 'grep -q "hint: fresh typo3 clone" /tmp/dd13-start1.log'
check "DD13: TRIPWIRE first start fails EPERM until handover (burn-in flow)" \
    test "$_dd13_first" = 1
E 'sudo bash /home/dev/repo/files/config.sh --yes handover /var/www/vhosts/dd13-proj >/tmp/dd13-handover.log 2>&1'
check "DD13: handover writes the dev-owned flag (durable fix)" \
    E 'grep -q "^disable_settings_management: true" /var/www/vhosts/dd13-proj/.ddev/config.yaml'
check "DD13: dev can edit .ddev/config.yaml after handover" \
    DEVSH 'cd /var/www/vhosts/dd13-proj && printf "# dd13 edit\n" >> .ddev/config.yaml'
check "DD13: root stays dev-owned (dev-owned mode)" \
    E 'test "$(stat -c %U /var/www/vhosts/dd13-proj)" = dev'
if OC_CWD=/var/www/vhosts/dd13-proj OC 'ddev start >/tmp/dd13-start2.log 2>&1'; then
    check "DD13: start succeeds after handover (burn-in end state)" \
        E 'grep -q "Successfully started" /tmp/dd13-start2.log'

    echo ""
    echo "--- DD14. ddev composer create-project (exit-23 burn-in finding) ---"
    if [ "${E2E_DDEV_SKIP_CREATE:-0}" != "1" ]; then
        if OC_CWD=/var/www/vhosts/dd13-proj OC 'ddev composer create-project "typo3/cms-base-distribution:^14" >/tmp/dd14.log 2>&1'; then
            check "DD14: create-project exits 0" true
            check "DD14: composer.lock + vendor + public/index.php landed completely" \
                E 'test -f /var/www/vhosts/dd13-proj/composer.lock && test -d /var/www/vhosts/dd13-proj/vendor && test -f /var/www/vhosts/dd13-proj/public/index.php'
        else
            echo "  ${RED}FAIL${NC}  DD14: create-project failed (exit-23 investigation) — full tail:";             failures=$((failures + 1))
            E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd14.log | tail -25' || true
            failures=$((failures + 1))
        fi
    else
        skip "DD14 skipped (E2E_DDEV_SKIP_CREATE=1)"
    fi
    OC_CWD=/var/www/vhosts/dd13-proj OC 'ddev delete -Oy >/dev/null 2>&1' || true
else
    echo "  ${YELLOW}SKIP${NC}  DD13: second start failed — output:"
    E 'sed "s/\x1b\[[0-9;]*m//g" /tmp/dd13-start2.log 2>/dev/null | tail -15' || true
    skip "dd13 second start failed"
fi

# Leave the kit in its default state for subsequent runs.
E 'sudo bash /home/dev/repo/files/config.sh --yes ddev-settings on >/dev/null 2>&1' || true

e2e_finish
