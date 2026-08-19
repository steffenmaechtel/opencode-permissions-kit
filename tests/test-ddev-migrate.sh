#!/bin/sh
# Unit tests for the ddev database migration (issue #15):
# opencode-permissions-kit-lib/ddev-migrate.sh + its install.sh wiring.
# Runs against the repo files as the CURRENT user — no root, no real ddev
# required (a fake ddev on PATH records the command sequence). Verifies:
#   - the registry parser (global_config.yaml project_info/approot)
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
FILES="$SCRIPT_DIR/../files"
MIG="$FILES/opencode-permissions-kit-lib/ddev-migrate.sh"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/update.sh"
STATUS="$FILES/status.sh"
MAKEFILE="$SCRIPT_DIR/../Makefile"
TEST_CI="$SCRIPT_DIR/../.github/workflows/test.yml"
E2E_CI="$SCRIPT_DIR/../.github/workflows/e2e.yml"

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
check "standalone list mode exists" \
    sh -c "grep -q 'ddev-migrate.sh' \"\$1\" && grep -q 'list)' \"\$1\"" _ "$MIG"

# --- 6. install.sh wiring ----------------------------------------------------------

check "install.sh documents --skip-ddev-migration in the header" \
    sh -c "grep -q -- '--skip-ddev-migration' \"\$1\"" _ "$INSTALL"
check "install.sh parses --skip-ddev-migration" \
    sh -c "grep -q -- '--skip-ddev-migration) SKIP_DDEV_MIGRATION=true' \"\$1\"" _ "$INSTALL"
check "install.sh sources ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\"" _ "$INSTALL"
check "install.sh fetch list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\"" _ "$INSTALL"
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
    sh -c "grep -q 'Ddev dumps' \"\$1\" && grep -q 'ddev-migrate.sh import' \"\$1\"" _ "$INSTALL"
check "install.sh inventory counts the dev user's ddev projects" \
    sh -c "grep -q 'ddev projects' \"\$1\" && grep -q 'ddev_migrate_registry' \"\$1\"" _ "$INSTALL"
check "install.sh plan mentions the database export when projects exist" \
    sh -c "grep -q 'export ddev databases' \"\$1\"" _ "$INSTALL"
check "install.sh deploys ddev-migrate.sh to the library" \
    sh -c "grep -q '\"\$LIBDIR/ddev-migrate.sh\"' \"\$1\"" _ "$INSTALL"

# --- 7. update.sh / status.sh wiring ------------------------------------------------

check "update.sh KIT_FILES includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys ddev-migrate.sh" \
    sh -c "grep -q '\"\$LIBDIR/ddev-migrate.sh\"' \"\$1\"" _ "$UPDATE"
check "status.sh reports dumps waiting for import" \
    sh -c "grep -q 'db dumps' \"\$1\" && grep -q 'ddev-migrate.sh import' \"\$1\"" _ "$STATUS"

# --- 8. Makefile + CI wiring --------------------------------------------------------

check "Makefile lint list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\"" _ "$MAKEFILE"
check "Makefile has a test-ddev-migrate target in the test: list" \
    sh -c "grep -q 'test: .*test-ddev-migrate' \"\$1\"" _ "$MAKEFILE"
check "test.yml chmod list + run step mention the new test" \
    sh -c "grep -q 'test-ddev-migrate.sh' \"\$1\"" _ "$TEST_CI"
check "test.yml chmod list includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\"" _ "$TEST_CI"
check "e2e.yml chmod lists include ddev-migrate.sh" \
    sh -c "grep -c 'opencode-permissions-kit-lib/ddev-migrate.sh' \"\$1\" | grep -q '^2\$'" _ "$E2E_CI"

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
