#!/bin/sh
# Unit tests for the ddev database migration (issue #15):
# opencode-permissions-kit-lib/sh/ddev-migrate.sh + its install.sh wiring.
# Runs against the repo files as the CURRENT user — no root, no real ddev
# required (a fake ddev on PATH records the command sequence). Verifies:
#   - the registry parser (project_list.yaml for ddev >= 1.23 AND the
#     legacy global_config.yaml project_info/approot block)
#   - the root filter (only projects under registered roots)
#   - the omit_containers detection (inline + block YAML, project + global)
#   - the export loop: project NAME arguments (never paths), start ->
#     export-db -> stop per project (one at a time), final poweroff,
#     manifest OK/FAIL/SKIP bookkeeping, dump dir permissions
#   - the import loop: runs as opencode with backend DOCKER_HOST env
#   - install.sh wiring: flag, plan line, Step 4b BEFORE the .ddev
#     handover (order is the whole point — see issue #15), stamp
#   - status.sh / update.sh / Makefile / CI wiring
# Run: sh tests/test-ddev-migrate.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../../files"
MIG="$FILES/opencode-permissions-kit-lib/sh/ddev-migrate.sh"
BIN_MIG="$FILES/opencode-permissions-kit-lib/bin/ddev-migrate"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/opencode-permissions-kit-lib/management/update.sh"
STATUS="$FILES/opencode-permissions-kit-lib/management/status.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"
E2E_CI="$SCRIPT_DIR/../../.github/workflows/test-e2e.yml"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        fail "$desc (expected absence, got a match)"
    else
        pass "$desc"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc (expected [$expected] got [$actual])"
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo ""
echo "ddev database migration Tests (issue #15)"
echo "========================================"
echo ""

# --- 1. registry parser --------------------------------------------------------

mkdir -p "$WORK/devhome/.ddev"
cat > "$WORK/devhome/.ddev/global_config.yaml" <<'YML'
last_used_version: v1.24.1
project_info:
  alpha:
    approot: /var/www/vhosts/alpha
  beta:
    approot: "/var/www/vhosts/client/beta"
  outside:
    approot: /srv/other/outside
webimage: ddev/ddev-webserver
YML

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome/.ddev")
assert_eq "registry parser reads name|approot pairs (quoted + unquoted)" \
    "alpha|/var/www/vhosts/alpha
beta|/var/www/vhosts/client/beta
outside|/srv/other/outside" "$RESULT"

# --- 2. root filter --------------------------------------------------------------

mkdir -p /var/tmp/opencode-ddev-mig-roots/vhosts/alpha /var/tmp/opencode-ddev-mig-roots/vhosts/client/beta /srv/other/outside 2>/dev/null || true
sed -i "s|/var/www/vhosts/|/var/tmp/opencode-ddev-mig-roots/vhosts/|g; s|/srv/other/outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside|" "$WORK/devhome/.ddev/global_config.yaml"
mkdir -p "$WORK/devhome/.ddev"  # sed rewrote the file in place; keep dir

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts")
assert_eq "root filter keeps only projects under the registered roots" \
    "alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta" "$RESULT"

# Nonexistent approots are dropped (stale registry entries).
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome/.ddev" "/does/not/exist")
assert_eq "root filter with no matching dirs yields nothing" "" "$RESULT"

# --- 2b. ddev >= 1.23 registry: standalone project_list.yaml -----------------------
# ddev >= 1.23.0 (commit 94d77509a) keeps the project list in its own
# project_list.yaml — top-level name map, 4-space indent as written by
# ddev's yaml.Marshal — and clears the legacy project_info: block in
# global_config.yaml on first run. The parser must read BOTH layouts.
mkdir -p "$WORK/devhome123/.ddev"
cat > "$WORK/devhome123/.ddev/project_list.yaml" <<'YML'
shopware-test-260605:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
    used_host_ports: []
beta:
    approot: "/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta"
outside:
    approot: /var/tmp/opencode-ddev-mig-roots/srv/other/outside
YML
printf 'last_started_version: v1.25.2\nwebimage: ddev/ddev-webserver\n' > "$WORK/devhome123/.ddev/global_config.yaml"

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome123/.ddev")
assert_eq "registry parser reads the ddev >= 1.23 project_list.yaml (quoted + unquoted)" \
    "shopware-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside" "$RESULT"

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome123/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts")
assert_eq "root filter applies to project_list.yaml projects too" \
    "shopware-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta" "$RESULT"

# Both layouts side by side (mid-migration home): entries from both
# files are emitted — duplicates are tolerated downstream (the export
# resume logic skips projects already in the manifest).
mkdir -p /var/tmp/opencode-ddev-mig-roots/vhosts/gamma
cat > "$WORK/devhome123/.ddev/global_config.yaml" <<'YML'
project_info:
  legacy-only:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/gamma
YML
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome123/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts")
assert_eq "legacy and modern registry files are BOTH scanned" \
    "shopware-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
legacy-only|/var/tmp/opencode-ddev-mig-roots/vhosts/gamma" "$RESULT"

# ddev creates an EMPTY project_list.yaml on fresh homes — no projects.
printf 'last_started_version: v1.25.2\n' > "$WORK/devhome123/.ddev/global_config.yaml"
: > "$WORK/devhome123/.ddev/project_list.yaml"
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome123/.ddev")
assert_eq "empty project_list.yaml + bare global config yields nothing" "" "$RESULT"

# --- 2c. ddev_migrate_done: both registry layouts count ----------------------------
# DDEV_MIG_OC_HOME pins the check to the fixture (real path is always
# /home/<opencode-user>).
done_check() { sh -c ". \"\$1\" && if DDEV_MIG_OC_HOME=\"\$2\" ddev_migrate_done oc; then echo yes; else echo no; fi" _ "$MIG" "$1"; }
mkdir -p "$WORK/ochome/.ddev"

printf 'last_started_version: v1.25.2\n' > "$WORK/ochome/.ddev/global_config.yaml"
: > "$WORK/ochome/.ddev/project_list.yaml"
assert_eq "done: bare modern home (empty list) is NOT done" "no" "$(done_check "$WORK/ochome")"

printf 'shopware:\n    approot: /tmp/shopware\n' > "$WORK/ochome/.ddev/project_list.yaml"
assert_eq "done: project_list.yaml entries count" "yes" "$(done_check "$WORK/ochome")"

rm -f "$WORK/ochome/.ddev/project_list.yaml"
printf 'project_info:\n  p:\n    approot: /tmp/p\n' > "$WORK/ochome/.ddev/global_config.yaml"
assert_eq "done: legacy project_info block counts" "yes" "$(done_check "$WORK/ochome")"

rm -rf "$WORK/devhome123" "$WORK/ochome"

# --- 3. omit_containers detection -------------------------------------------------

has_db() { sh -c ". \"\$1\" && if ddev_migrate_has_db \"\$2\" \"\$3\"; then echo yes; else echo no; fi" _ "$MIG" "$1" "$WORK/devhome/.ddev"; }

mkproj() {
    mkdir -p "$WORK/$1/.ddev"
    printf '%s\n' "$2" > "$WORK/$1/.ddev/config.yaml"
}

mkproj p1 'name: p1
type: typo3'
assert_eq "project without omit_containers HAS a db" "yes" "$(has_db "$WORK/p1")"

mkproj p2 'omit_containers: [db, ddev-ssh-agent]'
assert_eq "inline omit_containers [db] has NO db" "no" "$(has_db "$WORK/p2")"

mkproj p3 'omit_containers:
  - db
  - ddev-ssh-agent'
assert_eq "block omit_containers (- db) has NO db" "no" "$(has_db "$WORK/p3")"

mkproj p4 'omit_containers: [ddev-ssh-agent]'
assert_eq "omit_containers without db keeps the db" "yes" "$(has_db "$WORK/p4")"

mkproj p5 'omit_containers: []
docroot: public'
assert_eq "empty inline list keeps the db" "yes" "$(has_db "$WORK/p5")"

mkproj p6 'omit_containers:
  - ddev-ssh-agent'
assert_eq "block list without db keeps the db" "yes" "$(has_db "$WORK/p6")"

printf 'omit_containers_global: [db]\n' > "$WORK/devhome/.ddev/global_config.yaml"
assert_eq "global omit_containers_global [db] has NO db" "no" "$(has_db "$WORK/p1")"
printf 'omit_containers_global:\n  - db\n' > "$WORK/devhome/.ddev/global_config.yaml"
assert_eq "global block omit has NO db" "no" "$(has_db "$WORK/p1")"
rm -f "$WORK/devhome/.ddev/global_config.yaml"
assert_eq "missing global config keeps the db" "yes" "$(has_db "$WORK/p1")"

# --- 4. export loop with a fake ddev ----------------------------------------------
# The fake ddev logs every invocation; export-db writes the dump to the
# --file= path it receives. ddev commands must address projects by NAME
# (registry key), never by path.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/ddev" <<'FAKE'
#!/bin/sh
echo "ddev:$*" >> "$DDEV_LOG"
if [ "$1" = "export-db" ]; then
    for a in "$@"; do
        case "$a" in
            --file=*) printf 'FAKEDUMP\n' > "${a#--file=}" ;;
        esac
    done
fi
# "broken" simulates an old production project that no longer starts —
# but only while the DDEV_FAKE_BROKEN marker exists (so a second run can
# simulate "user fixed the project and re-ran install.sh).
if [ "$1" = "start" ] && [ "$2" = "broken" ] && [ -n "${DDEV_FAKE_BROKEN:-}" ]; then
    echo "Failed to start broken: fixture failure" >&2
    exit 1
fi
# "nodbrt" has a db-less runtime (no omit_containers entry, but the db
# service never existed — ddev fails export-db with a classifiable error).
if [ "$1" = "export-db" ] && [ "$2" = "nodbrt" ]; then
    echo "Error: failed to export database for nodbrt: unable to export db: service db does not exist in project nodbrt (state=doesnotexist)" >&2
    exit 1
fi
exit 0
FAKE
chmod +x "$WORK/bin/ddev"

# Two exportable projects + one db-less project + one BROKEN project
# (start fails — the loop must continue with the others) + one project
# whose db service does not exist at runtime (export-db fails with
# ddev's "service db does not exist" — classified SKIP, not FAIL).
rm -rf /var/tmp/opencode-ddev-mig-roots
for _p in alpha gamma nodb broken nodbrt; do
    mkdir -p "/var/tmp/opencode-ddev-mig-roots/vhosts/$_p/.ddev"
done
mkdir -p "$WORK/devhome/.ddev"
cat > "$WORK/devhome/.ddev/global_config.yaml" <<'YML'
project_info:
  alpha:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
  gamma:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/gamma
  nodb:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/nodb
  broken:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/broken
  nodbrt:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/nodbrt
YML
printf 'name: alpha\ntype: typo3\n' > /var/tmp/opencode-ddev-mig-roots/vhosts/alpha/.ddev/config.yaml
printf 'name: gamma\ntype: php\n' > /var/tmp/opencode-ddev-mig-roots/vhosts/gamma/.ddev/config.yaml
printf 'omit_containers: [db]\n' > /var/tmp/opencode-ddev-mig-roots/vhosts/nodb/.ddev/config.yaml
printf 'name: broken\ntype: typo3\n' > /var/tmp/opencode-ddev-mig-roots/vhosts/broken/.ddev/config.yaml
printf 'name: nodbrt\ntype: typo3\n' > /var/tmp/opencode-ddev-mig-roots/vhosts/nodbrt/.ddev/config.yaml

# Run the library export directly with a controlled backup root; the sudo
# detour is shimmed (CI runs unprivileged) by overriding the run-as helper
# after sourcing. DDEV_MIG_DEV_HOME pins the registry to the fixture (the
# current user may BE "opencode" with a real registry on kit workspaces).
# The "opencode user" argument is root so the handed-over guard (stat
# owner == oc user) never fires for the current-user fixtures.
cat > "$WORK/run-export.sh" <<'WRAP'
#!/bin/sh
. "$1"
_ddev_migrate_run_as() {
    shift 1
    "$@"
}
ddev_migrate_export "$2" "$3" "$4" "$5"
WRAP

OUT=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" DDEV_FAKE_BROKEN=1 \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts)
DUMP_DIR=$(ls -1d "$WORK/backups"/ddev-migration-* 2>/dev/null | tail -1)

check "export produced a dump directory" test -n "$DUMP_DIR"
check "dump for project alpha exists" test -s "$DUMP_DIR/alpha.sql.gz"
check "dump for project gamma exists" test -s "$DUMP_DIR/gamma.sql.gz"
check_fail "no dump for the db-less project nodb" test -e "$DUMP_DIR/nodb.sql.gz"

# Per project: start -> export-db -> stop (one at a time); ONE poweroff at
# the end. ddev is called with project NAMES, never paths.
assert_eq "exactly one final poweroff" \
    "1" "$(grep -c 'ddev:poweroff' "$WORK/ddev.log")"
assert_eq "alpha sequence is start -> export-db -> stop (by name)" \
    "ddev:start alpha ddev:export-db alpha --file=$DUMP_DIR/alpha.sql.gz ddev:stop alpha" \
    "$(grep -E 'ddev:(start|export-db|stop) alpha' "$WORK/ddev.log" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "gamma sequence is start -> export-db -> stop (by name)" \
    "ddev:start gamma ddev:export-db gamma --file=$DUMP_DIR/gamma.sql.gz ddev:stop gamma" \
    "$(grep -E 'ddev:(start|export-db|stop) gamma' "$WORK/ddev.log" | tr '\n' ' ' | sed 's/ $//')"
check_fail "ddev is never called with a project PATH" \
    sh -c "grep -q 'start /var/tmp' \"\$1\"" _ "$WORK/ddev.log"

check "manifest records OK for alpha" sh -c "grep -q '^OK|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "manifest records OK for gamma" sh -c "grep -q '^OK|gamma|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "manifest records SKIP for the db-less project" sh -c "grep -q '^SKIP|nodb|.*no-db-container' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "manifest records FAIL for the unstartable project" sh -c "grep -q '^FAIL|broken|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "runtime-db-less project is classified SKIP (not FAIL)" \
    sh -c "grep -q '^SKIP|nodbrt|.*no-db-service' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "a failed start does not abort the remaining exports" \
    sh -c "grep -q 'export-db gamma' \"\$1\"" _ "$WORK/ddev.log"
check_fail "no stop is issued for the failed project (it never started)" \
    sh -c "grep -q 'ddev:stop broken' \"\$1\"" _ "$WORK/ddev.log"

# --- 4b. resume: an aborted install re-runs the export --------------------------------
# Run 1 above left FAIL|broken (the failed-projects abort path: stamp NOT
# set). Run 2 = user fixed the project and re-ran install.sh: the SAME dump
# directory must be reused, already-exported projects skipped, broken
# retried, stale FAIL entries replaced.
mv "$WORK/ddev.log" "$WORK/ddev-run1.log"
OUT2=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts)

assert_eq "resume reuses the SAME dump directory (no second wave)" \
    "1" "$(ls -1d "$WORK/backups"/ddev-migration-* 2>/dev/null | wc -l | tr -d ' ')"
check_fail "already-exported project alpha is NOT started again" \
    sh -c "grep -q 'ddev:start alpha' \"\$1\"" _ "$WORK/ddev.log"
check_fail "already-exported project gamma is NOT started again" \
    sh -c "grep -q 'ddev:start gamma' \"\$1\"" _ "$WORK/ddev.log"
check "fixed project broken IS retried" \
    sh -c "grep -q 'ddev:start broken' \"\$1\"" _ "$WORK/ddev.log"
check "retried project now has a dump" test -s "$DUMP_DIR/broken.sql.gz"
check "manifest records OK for the retried project" \
    sh -c "grep -q '^OK|broken|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check_fail "stale FAIL entry is gone after the successful retry" \
    sh -c "grep -q '^FAIL|broken|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
assert_eq "no FAIL entries remain (installer would not re-ask the abort question)" \
    "0" "$(grep -c '^FAIL|' "$DUMP_DIR/manifest.conf")"
assert_eq "manifest has exactly one OK line per project (no duplicates)" \
    "3" "$(grep -c '^OK|' "$DUMP_DIR/manifest.conf")"
assert_eq "SKIP lines stay single too (nodb + nodbrt)" \
    "2" "$(grep -c '^SKIP|' "$DUMP_DIR/manifest.conf")"
check_fail "no leftover .export-*.err capture files in the dump directory" \
    sh -c "ls \"\$1\"/.export-*.err >/dev/null 2>&1" _ "$DUMP_DIR"

# --- 5. import loop (static wiring) ---------------------------------------------

check "import reads the manifest and runs as the opencode user" \
    sh -c "grep -q 'ddev_migrate_import' \"\$1\" && grep -q 'sudo -u \"\$dm_oc\" env' \"\$1\"" _ "$MIG"
check "import addresses projects by NAME, not path" \
    sh -c "grep -qF 'start \"\$dm_n\"' \"\$1\" && grep -qF 'import-db \"\$dm_n\"' \"\$1\"" _ "$MIG"
check "import builds DOCKER_HOST from the configured backend" \
    sh -c "grep -q 'OPENCODE_DOCKER_HOST' \"\$1\" && grep -q 'OPENCODE_PODMAN_SOCKET' \"\$1\"" _ "$MIG"
check "import never deletes dumps on failure" \
    sh -c "! grep -q 'rm -rf.*DDEV_MIG_BACKUP_ROOT' \"\$1\"" _ "$MIG"
check "standalone list mode exists (bin dispatcher)" \
    sh -c "grep -q 'list)' \"\$1\"" _ "$BIN_MIG"

# --- 6. install.sh wiring ----------------------------------------------------------

check "install.sh documents --skip-ddev-migration in the header" \
    sh -c "grep -q -- '--skip-ddev-migration' \"\$1\"" _ "$INSTALL"
check "install.sh parses --skip-ddev-migration" \
    sh -c "grep -q -- '--skip-ddev-migration) SKIP_DDEV_MIGRATION=true' \"\$1\"" _ "$INSTALL"
check "install.sh sources ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$INSTALL"
check "install.sh fetch list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$INSTALL"
check "install.sh runs the export in Step 4b (before the Step 5 handover)" \
    sh -c 'export_ln=$(grep -n "ddev_migrate_export \"" "$1" | head -1 | cut -d: -f1); hand_ln=$(grep -n "ddev_handover_root \"" "$1" | head -1 | cut -d: -f1); [ -n "$export_ln" ] && [ -n "$hand_ln" ] && [ "$export_ln" -lt "$hand_ln" ]' _ "$INSTALL"
check "install.sh stamps DDEV_EXPORTED=1 after a successful export" \
    sh -c "grep -q 'DDEV_EXPORTED=1' \"\$1\"" _ "$INSTALL"
check "install.sh gates the DDEV_EXPORTED stamp on zero failures" \
    sh -c "grep -qF '[ \"\$DD_MIG_FAIL\" -eq 0 ]' \"\$1\"" _ "$INSTALL"
check "install.sh re-reads ok/fail counts from the manifest (subshell-safe)" \
    sh -c "grep -q 'grep -c .\\^OK|.' \"\$1\" || grep -qF 'grep -c \"^OK|\"' \"\$1\"" _ "$INSTALL"
check "install.sh lists failed projects before continuing" \
    sh -c "grep -q 'could NOT be exported' \"\$1\"" _ "$INSTALL"
check "install.sh asks before continuing with failed exports (default: abort)" \
    sh -c "grep -q 'ui_confirm \"Continue the install anyway?' \"\$1\" && grep -q '\"n\"' \"\$1\"" _ "$INSTALL"
check "install.sh aborts BEFORE the handover when the user declines" \
    sh -c "grep -q 'the .ddev handover did NOT run' \"\$1\"" _ "$INSTALL"
check "install.sh keeps exporting the remaining projects on failure (non-fatal loop)" \
    sh -c "grep -qF 'continue' \"\$1\"" _ "$MIG"
check "install.sh skips the export when already stamped" \
    sh -c "grep -q 'DDEV_EXPORTED_PRE' \"\$1\"" _ "$INSTALL"

# --- 6b. production-WSL findings (local/nb-laptop-output) -----------------------

# ddev detection: version probe falls back to the DEFAULT user — `ddev
# version` can come up empty as root while working as the actual user.
check "install.sh probes the ddev version as the DEFAULT user too" \
    sh -c "grep -q 'DDEV_BIN_DEV' \"\$1\" && grep -q 'sudo -u \"\$DEFAULT_USER\" env HOME=\"/home/\$DEFAULT_USER\"' \"\$1\"" _ "$INSTALL"
check "install.sh inventory distinguishes found-but-unreadable from missing" \
    sh -c "grep -q 'version could not be read' \"\$1\" && grep -q 'not installed (optional' \"\$1\"" _ "$INSTALL"
check "migration detection is gated on the registry, not the binary" \
    sh -c "grep -qF 'if [ -d \"/home/\$DEFAULT_USER/.ddev\" ]; then' \"\$1\"" _ "$INSTALL"
# _ddev_migrate_bin must consider per-user install paths (sudo -u does not
# inherit the dev user's PATH).
check "ddev resolution includes the user's private install paths" \
    sh -c "grep -q '.local/bin/ddev' \"\$1\" && grep -q '.ddev/bin/ddev' \"\$1\"" _ "$MIG"
# Runtime db-less projects are SKIP, not FAIL (hotfix log: "service db
# does not exist (state=doesnotexist)").
check "runtime db-less export failure is classified no-db-service" \
    sh -c "grep -q 'no-db-service' \"\$1\"" _ "$MIG"
check "install.sh shows the dumps + import hint in the summary" \
    sh -c "grep -q 'Ddev dumps' \"\$1\" && grep -q 'bin/ddev-migrate import' \"\$1\"" _ "$INSTALL"
check "install.sh inventory counts the dev user's ddev projects" \
    sh -c "grep -q 'ddev projects' \"\$1\" && grep -q 'ddev_migrate_registry' \"\$1\"" _ "$INSTALL"
check "install.sh plan mentions the database export when projects exist" \
    sh -c "grep -q 'export ddev databases' \"\$1\"" _ "$INSTALL"
check "install.sh deploys ddev-migrate.sh to the library" \
    sh -c "grep -q '\"\$LIBDIR/sh/ddev-migrate.sh\"' \"\$1\" && grep -q '\"\$LIBDIR/bin/ddev-migrate\"' \"\$1\"" _ "$INSTALL"

# --- 7. update.sh / status.sh wiring ------------------------------------------------

check "update.sh KIT_FILES includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys ddev-migrate.sh" \
    sh -c "grep -q '\"\$LIBDIR/sh/ddev-migrate.sh\"' \"\$1\" && grep -q '\"\$LIBDIR/bin/ddev-migrate\"' \"\$1\"" _ "$UPDATE"
check "status.sh reports dumps waiting for import" \
    sh -c "grep -q 'db dumps' \"\$1\" && grep -q 'bin/ddev-migrate import' \"\$1\"" _ "$STATUS"
check "status.sh import detection knows the ddev >= 1.23 project_list.yaml" \
    sh -c "grep -q 'project_list.yaml' \"\$1\" && grep -q 'approot:' \"\$1\"" _ "$STATUS"

# --- 8. Makefile + CI wiring --------------------------------------------------------

check "Makefile lint list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$MAKEFILE"
check "Makefile has a test-ddev-migrate target in the test: list" \
    sh -c "grep -q 'test: .*test-ddev-migrate' \"\$1\"" _ "$MAKEFILE"
check "test-unit.yml chmod list + run step mention the new test" \
    sh -c "grep -q 'test-ddev-migrate.sh' \"\$1\"" _ "$TEST_CI"
check "test-unit.yml chmod list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$TEST_CI"
check "test-e2e.yml chmod lists include ddev-migrate.sh" \
    sh -c "grep -c 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\" | grep -q '^2\$'" _ "$E2E_CI"

# --- 9. rootless bind-mounts switch (ddev 1.25.0-1.25.2) ---------------------------
# ddev_rootless_bindmounts lives in ddev-handover.sh (sourced by the
# same three callers): docker-rootless + old ddev -> set the global
# no-bind-mounts switch; modern ddev (>= 1.25.3) and podman keep bind
# mounts. Uses the fake ddev from section 4 (logs every call).
HAND="$FILES/opencode-permissions-kit-lib/sh/ddev-handover.sh"
bm_run() {
    sh -c '. "$1"
        _ddev_handover_run_as() { shift 1; "$@"; }
        ddev_rootless_bindmounts oc "$2" "$3" "$4"
        echo "rc=$?"' _ "$HAND" "$1" "$2" "$3"
}
: > "$WORK/ddev-bm.log"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run docker-rootless 1.25.2 "$WORK/bin/ddev")
check "ddev 1.25.2 on docker-rootless sets the switch" \
    sh -c "printf '%s' \"\$2\" | grep -q 'rc=0' && grep -q 'ddev:config global --no-bind-mounts' \"\$1\"" _ "$WORK/ddev-bm.log" "$OUT"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run docker-rootless 1.25.0 "$WORK/bin/ddev")
check "ddev 1.25.0 on docker-rootless sets the switch" \
    sh -c "printf '%s' \"\$2\" | grep -q 'rc=0'" _ "$WORK/ddev-bm.log" "$OUT"
_n=$(wc -l < "$WORK/ddev-bm.log" | tr -d ' ')
assert_eq "modern ddev (1.25.3+) keeps bind mounts (no third call)" "2" "$_n"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run docker-rootless 1.25.3 "$WORK/bin/ddev")
check "ddev 1.25.3 on docker-rootless is a no-op (rc=1)" \
    sh -c "printf '%s' \"\$1\" | grep -q 'rc=1$'" _ "$OUT"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run podman-rootless 1.25.2 "$WORK/bin/ddev")
check "podman-rootless never touches the switch (rc=1)" \
    sh -c "printf '%s' \"\$1\" | grep -q 'rc=1$'" _ "$OUT"
OUT=$(bm_run docker-rootless 1.25.2 "/does/not/exist")
check "unknown ddev binary reports rc=2 (wanted, not possible)" \
    sh -c "printf '%s' \"\$1\" | grep -q 'rc=2$'" _ "$OUT"
# install.sh/config.sh run under set -e: the "not needed" rc=1 must be
# consumable by the if/else caller pattern without aborting (regression:
# a bare call + `case $?` killed install.sh at Step 4 on modern ddev).
OUT=$(sh -c 'set -e
    . "$1"
    _ddev_handover_run_as() { shift 1; "$@"; }
    if ddev_rootless_bindmounts oc docker-rootless 1.25.4 /bin/true; then :
    else case $? in 2) exit 9 ;; esac
    fi
    echo survived' _ "$HAND")
assert_eq "rc=1 (not needed) never trips set -e in the caller pattern" "survived" "$OUT"

CONFIG_SH="$FILES/opencode-permissions-kit-lib/management/config.sh"
check "install.sh wires the bind-mounts switch (backend + version gated)" \
    sh -c "grep -q 'ddev_rootless_bindmounts \"\$OPENCODE_USER\"' \"\$1\" && grep -qF '[ -n \"\$DDEV_BIN\" ] && [ -n \"\$DDEV_VERSION\" ]' \"\$1\"" _ "$INSTALL"
check "config.sh wires the bind-mounts switch on backend changes" \
    sh -c "grep -q 'ddev_rootless_bindmounts \"\$OPENCODE_USER\"' \"\$1\"" _ "$CONFIG_SH"

# --- 10. partial-export hardening (production finding: 1 of 12) --------------------
# Real-world registry, verbatim from the report: mixed-case and dotted
# project names, all approots under one root. The parser must yield all
# twelve and nothing may fall outside the root.
mkdir -p "$WORK/uraabe/.ddev"
cat > "$WORK/uraabe/.ddev/project_list.yaml" <<'YML'
adk:
    approot: /home/uraabe/www/vhosts/academy-dk
blackforest24-SW6:
    approot: /home/uraabe/www/vhosts/blackforest24-SW6
bruder-shopware-sw6:
    approot: /home/uraabe/www/vhosts/bruder-shopware-sw6
brudertoys-sap:
    approot: /home/uraabe/www/vhosts/brudertoys-sap
od-multi-store:
    approot: /home/uraabe/www/vhosts/od-multi-store
sascha-advent-calendar:
    approot: /home/uraabe/www/vhosts/sascha-advent-calendar
shopware-test-260605:
    approot: /home/uraabe/www/vhosts/shopware-test-260605
swdemo-6-7-0-1:
    approot: /home/uraabe/www/vhosts/swdemo_6_7_0_1
teamshub:
    approot: /home/uraabe/www/vhosts/teamshub
weindepot-vinum:
    approot: /home/uraabe/www/vhosts/weindepot-vinum
wf-xmas:
    approot: /home/uraabe/www/vhosts/wf-xmas
www.innova-vital.de:
    approot: /home/uraabe/www/vhosts/www.innova-vital.de
YML
assert_eq "real-world registry: all 12 projects parsed (case + dots)" "12" \
    "$(sh -c '. "$1" && ddev_migrate_registry "$2"' _ "$MIG" "$WORK/uraabe/.ddev" | grep -c .)"
assert_eq "real-world registry: nothing outside the root" "" \
    "$(sh -c '. "$1" && ddev_migrate_outside "$2" /home/uraabe/www/vhosts' _ "$MIG" "$WORK/uraabe/.ddev")"
assert_eq "narrow root: the other 11 are reported outside" "11" \
    "$(sh -c '. "$1" && ddev_migrate_outside "$2" /home/uraabe/www/vhosts/academy-dk' _ "$MIG" "$WORK/uraabe/.ddev" | grep -c .)"

# The gap detector needs the approots to EXIST (ddev_migrate_projects
# drops stale entries) — mirror the registry into the fixture tree.
mkdir -p "$WORK/uraabe2/.ddev"
sed "s|/home/uraabe/www/vhosts|$WORK/uraabe-vhosts|g" "$WORK/uraabe/.ddev/project_list.yaml" \
    > "$WORK/uraabe2/.ddev/project_list.yaml"
sh -c '. "$1" && ddev_migrate_registry "$2"' _ "$MIG" "$WORK/uraabe2/.ddev" \
    | while IFS='|' read -r _gn _ga; do mkdir -p "$_ga"; done
mkdir -p "$WORK/gapbackups/ddev-migration-20260909-232704"
printf 'OK|adk|%s/uraabe-vhosts/academy-dk|adk.sql.gz\n' "$WORK" \
    > "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
GAP=$(DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/uraabe2" \
    sh -c '. "$1" && ddev_migrate_gap uraabe "$2"' _ "$MIG" "$WORK/uraabe-vhosts")
assert_eq "gap: 1 dump recorded vs 12 registered -> have/now reported" \
    "1 12 $WORK/gapbackups/ddev-migration-20260909-232704" "$GAP"
for _gn in blackforest24-SW6 bruder-shopware-sw6 brudertoys-sap od-multi-store \
           sascha-advent-calendar shopware-test-260605 swdemo-6-7-0-1 teamshub \
           weindepot-vinum wf-xmas www.innova-vital.de; do
    printf 'OK|%s|%s/uraabe-vhosts/x|%s.sql.gz\n' "$_gn" "$WORK" "$_gn" \
        >> "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
done
if DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/uraabe2" \
    sh -c '. "$1" && ddev_migrate_gap uraabe "$2" >/dev/null' _ "$MIG" "$WORK/uraabe-vhosts"; then
    fail "gap: complete manifest reports NO gap"
else
    pass "gap: complete manifest reports NO gap"
fi

# registry subcommand (read-only, no root gate): export/outside view
OUT=$(DDEV_MIG_DEV_HOME="$WORK/uraabe2" sh "$BIN_MIG" registry uraabe "$WORK/uraabe-vhosts")
assert_eq "registry cmd: all 12 under the root classified export" "12" \
    "$(printf '%s\n' "$OUT" | grep -c '^  export:')"
assert_eq "registry cmd: none outside" "0" \
    "$(printf '%s\n' "$OUT" | grep -c '^  outside:')"
OUT=$(DDEV_MIG_DEV_HOME="$WORK/uraabe2" sh "$BIN_MIG" registry uraabe "$WORK/uraabe-vhosts/academy-dk" 2>/dev/null || true)
assert_eq "registry cmd: narrow root -> 1 export, 11 outside" "1 11" \
    "$(printf '%s\n' "$OUT" | grep -c '^  export:') $(printf '%s\n' "$OUT" | grep -c '^  outside:')"

# wiring: the outside warning + the install/status gap detectors exist
check "export warns about registry projects outside the roots" \
    sh -c "grep -q 'OUTSIDE the given roots' \"\$1\"" _ "$MIG"
check "install.sh warns on skip branches when the registry outgrew the manifest" \
    sh -c "grep -q '_ddev_mig_gap_warn' \"\$1\" && [ \"\$(grep -c '_ddev_mig_gap_warn' \"\$1\")\" -ge 3 ]" _ "$INSTALL"
check "status.sh reports INCOMPLETE dumps vs the dev registry" \
    sh -c "grep -q 'INCOMPLETE — registry lists' \"\$1\" && grep -q 'ddev-migrate registry' \"\$1\"" _ "$STATUS"
check "bin dispatcher has the registry subcommand" \
    sh -c "grep -q 'registry)' \"\$1\"" _ "$BIN_MIG"

# --- Summary ------------------------------------------------------------------------

# Cleanup fixture roots outside WORK.
rm -rf /var/tmp/opencode-ddev-mig-roots /var/www/vhosts/alpha /var/www/vhosts/sub 2>/dev/null || true

echo ""
echo "========================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
