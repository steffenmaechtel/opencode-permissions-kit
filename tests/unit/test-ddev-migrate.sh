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
# Run: sh tests/unit/test-ddev-migrate.sh
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
DEPLOYLIB="$FILES/opencode-permissions-kit-lib/sh/deploy-lib.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"

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
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
  beta:
    approot: "/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta"
  outside:
    approot: /var/tmp/opencode-ddev-mig-roots/srv/other/outside
webimage: ddev/ddev-webserver
YML

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome/.ddev")
assert_eq "registry parser reads name|approot pairs (quoted + unquoted)" \
    "alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside" "$RESULT"

# --- 2. root filter --------------------------------------------------------------

# Fixtures are written sandboxed at the source (maintainer directive
# 2026-10-04, 0.0.42f C3): unit suites never carry real-tree literals —
# not even inert ones an earlier sed would have rewritten.
mkdir -p /var/tmp/opencode-ddev-mig-roots/vhosts/alpha /var/tmp/opencode-ddev-mig-roots/vhosts/client/beta /var/tmp/opencode-ddev-mig-roots/srv/other/outside 2>/dev/null || true

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
client07-test-260605:
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
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside" "$RESULT"

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome123/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts")
assert_eq "root filter applies to project_list.yaml projects too" \
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
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
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
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

rm -rf "${WORK:?}/devhome123" "${WORK:?}/ochome"

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
# Stdin eater (regression: real ddev reads stdin — prompt/TUI probing —
# and silently consumed the export loop's project list: ONE dump per
# run, resume picked the next each time). Enabled explicitly so local
# runs with a terminal don't hang on it.
[ -n "${DDEV_EAT_STDIN:-}" ] && cat > /dev/null
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
    DDEV_MIG_DEV_HOME="$WORK/devhome" DDEV_FAKE_BROKEN=1 DDEV_EAT_STDIN=1 \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null)
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

# --- 4c. planted symlinks in the agent-writable dump dir (0.0.44a V3) ---------------
# The dump dir is group-writable by design until finalize — the agent can
# plant entries during the minutes-long export loop. Root-side writes
# must never act THROUGH a planted link: manifest mutations ride staging +
# rename (a link at manifest.conf at export START is now REFUSED — the
# seed never reads through it, 0.0.44b W2), err captures live in the
# root-owned .root-stage, and the chmod pass rides find ! -type l.
echo "VICTIM-ERR-CONTENT" > "$WORK/victim-err.conf"
echo "VICTIM-DUMP-CONTENT" > "$WORK/victim-dump.conf"
chmod 755 "$WORK/victim-dump.conf"
ln -s "$WORK/victim-err.conf" "$DUMP_DIR/.export-alpha.err"
ln -s "$WORK/victim-dump.conf" "$DUMP_DIR/evil.sql.gz"
OUT3=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null)
check "planted .export-*.err link is never touched (captures live in .root-stage)" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-ERR-CONTENT" _ "$WORK/victim-err.conf"
check "chmod pass skips symlink operands (victim keeps its mode)" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 755" _ "$WORK/victim-dump.conf"
check "manifest stays a regular file through the run" \
    sh -c "test -f \"\$1\" && test ! -L \"\$1\"" _ "$DUMP_DIR/manifest.conf"
# Sticky + stage mode act DURING the run (finalize re-modes the dir to
# 750) — pinned statically on the mechanisms (W1): chmod 3770 at setup
# AND on resume, mkdir -m 700 for the stage.
_grep_n=$(grep -c 'chmod 3770 "\$DD_MIG_DUMP_DIR"' "$MIG" || true)
[ "$_grep_n" -ge 1 ] \
    && check "dump dir is set sticky (3770) — group rename of root entries blocked (W1)" true \
    || check "dump dir is set sticky (3770) — group rename of root entries blocked (W1)" false
grep -q 'mkdir -m 700 "\$DM_STAGE"' "$MIG" \
    && check "stage is created mode 700 in one step (no default-mode window, W1)" true \
    || check "stage is created mode 700 in one step (no default-mode window, W1)" false
check_fail "the root staging dir is removed before finalize hands the tree over" \
    test -e "$DUMP_DIR/.root-stage"

# --- 4d. a linked manifest at export START is refused, never read (0.0.44b W2) -------
# The authoritative copy seeds from the dump-dir manifest only when it is
# not a symlink — a planted link there means tampering: loud refuse, the
# link's target is never opened (no read-through disclosure).
echo "VICTIM-MANIFEST-CONTENT" > "$WORK/victim-manifest.conf"
rm -f "$DUMP_DIR/manifest.conf"
ln -s "$WORK/victim-manifest.conf" "$DUMP_DIR/manifest.conf"
OUT4=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run4.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1 || true)
check "export refuses a symlinked manifest.conf at start (tamper, W2)" \
    sh -c "printf '%s' \"\$1\" | grep -q REFUSED" _ "$OUT4"
check "manifest link target was never opened (content intact, W2)" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-MANIFEST-CONTENT" _ "$WORK/victim-manifest.conf"
check_fail "the refused run leaves no staging dir behind" \
    test -e "$DUMP_DIR/.root-stage"
# restore a regular manifest for the suites below
rm -f "$DUMP_DIR/manifest.conf"
printf 'OK|alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha|alpha.sql.gz\n' > "$DUMP_DIR/manifest.conf"

# --- 4e. fixed-string resume: sh.p must not cross-match shop (0.0.44b W13) -------------
# The resume check and the stale-rewrite are grep -F since 0.0.44a V23 —
# but nothing pinned it: all fixtures were metacharacter-free, so the old
# BRE ("sh.p" cross-matches "shop") was indistinguishable. A hand-edited
# registry (ddev itself enforces [a-z0-9-]) carries both names; the OK
# line for shop must NOT satisfy sh.p's resume check.
cat >> "$WORK/devhome/.ddev/project_list.yaml" <<YML
  shop:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
  sh.p:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
YML
printf 'dump\n' > "$DUMP_DIR/shop.sql.gz"
printf 'dump\n' > "$DUMP_DIR/sh.p.sql.gz"
printf 'OK|shop|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha|shop.sql.gz\n' >> "$DUMP_DIR/manifest.conf"
OUT5=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run5.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1 || true)
check "dot-name project sh.p is NOT skipped via shop's OK line (W13)" \
    sh -c "grep -q 'ddev:start sh.p' \"\$1\"" _ "$WORK/ddev-run5.log"
check "shop itself IS skipped (its own OK line matches, both engines)" \
    sh -c "grep -q 'ddev:start shop' \"\$1\" && exit 1 || exit 0" _ "$WORK/ddev-run5.log"
check "the published manifest keeps exactly one OK line per project (W13)" \
    sh -c "test \"\$(grep -c '^OK|' \"\$1\")\" -eq 5" _ "$DUMP_DIR/manifest.conf"

# --- 4f. the seed's owner arm refuses a manifest the dev does not own (0.0.44d F4/C3) --
# The manifest in $DUMP_DIR is owned by the CURRENT user; running the
# export with dm_dev=nobody (an existing unrelated user) must hit the
# seed's owner check (owner ∉ {root, dm_dev}) and REFUSE before the loop.
# Root guard (0.0.44e E4): as root everything is root-owned — the seed
# would CORRECTLY accept; the pin only means something unprivileged.
if [ "$(id -u)" = 0 ]; then
    echo "  SKIP  owner-arm pin needs an unprivileged user (root owns the fixture here)"
else
    OUT6=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run6.log" \
        DDEV_MIG_DEV_HOME="$WORK/devhome" \
        PATH="$WORK/bin:$PATH" \
        sh "$WORK/run-export.sh" "$MIG" nobody root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1 || true)
    check "seed refuses a manifest owned by neither root nor the dev (C3 owner arm, F4)" \
        sh -c "printf '%s' \"\$1\" | grep -q 'not root/dev-owned'" _ "$OUT6"
fi

# --- 4g. accounting and installer ride the authoritative path (0.0.44d F1/F4) -----------
check "export accounting reads the stage copy, not the dump-dir manifest (C2/F4)" \
    sh -c "grep -q 'manifest.auth' \"\$1\" && ! sed -n '/^    DD_MIG_OK=/,/DD_MIG_FAIL=/p' \"\$1\" | grep -q 'manifest.conf'" _ "$MIG"
check "finalize keeps the manifest root-owned for the resume seed (F2)" \
    sh -c "grep -q 'chown \"root:' \"\$1\"" _ "$MIG"
check "install.sh prints the FAIL list from the function state, never a re-grep (F1)" \
    sh -c "grep -q 'DD_MIG_FAILLIST' \"\$1\" && ! grep -q \"grep -c '^OK|' \\\"\\\$DD_MIG_DUMP_DIR/manifest.conf\\\"\" \"\$1\"" _ "$INSTALL"
check "export return state starts EMPTY — counters signal completion (E1)" \
    sh -c "grep -qF 'DD_MIG_DUMP_DIR=\"\"; DD_MIG_OK=\"\"; DD_MIG_FAIL=\"\"; DD_MIG_FAILLIST=\"\"' \"\$1\"" _ "$MIG"

# --- 4h. refused vs completed: only the accounting fills the counters (0.0.44e E1) -------
cat > "$WORK/run-export-state.sh" <<'WRAP'
#!/bin/sh
. "$1"
_ddev_migrate_run_as() {
    shift 1
    "$@"
}
ddev_migrate_export "$2" "$3" "$4" "$5" >/dev/null 2>&1 || true
printf 'DUMP=[%s] OK=[%s] FAIL=[%s]\n' "${DD_MIG_DUMP_DIR:-}" "${DD_MIG_OK:-}" "${DD_MIG_FAIL:-}"
WRAP
if [ "$(id -u)" != 0 ]; then
    _st_ref=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run7.log" \
        DDEV_MIG_DEV_HOME="$WORK/devhome" \
        PATH="$WORK/bin:$PATH" \
        sh "$WORK/run-export-state.sh" "$MIG" nobody root "$(id -gn)" \
        /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>/dev/null || true)
    check "a REFUSED export leaves DD_MIG_OK/FAIL empty (E1)" \
        sh -c "printf '%s' \"\$1\" | grep -q 'OK=\[\] FAIL=\[\]' && printf '%s' \"\$1\" | grep -q 'DUMP=\[.'" _ "$_st_ref"
else
    # Visible like the 4f guard's (0.0.44f F5): a silent skip reads as a
    # gap when a root-run suite log is audited.
    echo "  SKIP  refused-state pin needs an unprivileged user (root skips the seed refusal)"
fi
_st_ok=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run8.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export-state.sh" "$MIG" "$(id -un)" root "$(id -gn)" \
    /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>/dev/null || true)
# OK is anchored to >=1 (0.0.44f F2): the fixture exports at least one
# project, so an honest completed run never prints OK=[0] — a zero here
# can only mean the fill never ran (entry zeroing restored + dead
# accounting stayed green under the old [0-9] regex).
check "a COMPLETED export returns numeric counts (E1)" \
    sh -c "printf '%s' \"\$1\" | grep -q 'OK=\[[1-9][0-9]*\] FAIL=\[[0-9][0-9]*\]'" _ "$_st_ok"

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
# 0.0.44d F1: the counts now come from the export function's return
# state (set from the authoritative stage copy BEFORE the finalize hands
# the tree to the agent). A re-grep of the dump-dir manifest here would
# read an agent-owned file as root — the old pin demanded exactly that.
check "install.sh uses the propagated DD_MIG_* counts, never a manifest re-grep (F1)" \
    sh -c "grep -qF '[ -n \"\${DD_MIG_OK:-}\${DD_MIG_FAIL:-}\" ]' \"\$1\" && ! grep -qF 'grep -c \"^OK|\"' \"\$1\"" _ "$INSTALL"
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
# (HOME rides DEV_HOME since 0.0.44a V14 — getent-resolved, /home/<name>
# only the fallback.)
check "install.sh probes the ddev version as the DEFAULT user too" \
    sh -c "grep -q 'DDEV_BIN_DEV' \"\$1\" && grep -q 'sudo -u \"\$DEFAULT_USER\" env HOME=\"\$DEV_HOME\"' \"\$1\"" _ "$INSTALL"
check "install.sh inventory distinguishes found-but-unreadable from missing" \
    sh -c "grep -q 'version could not be read' \"\$1\" && grep -q 'not installed (optional' \"\$1\"" _ "$INSTALL"
check "migration detection is gated on the registry, not the binary" \
    sh -c "grep -qF 'if [ -d \"\$DEV_HOME/.ddev\" ]; then' \"\$1\"" _ "$INSTALL"
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
check "install.sh deploys ddev-migrate.sh to the library (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh 644' \"\$2\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-migrate 755' \"\$2\" && grep -q 'lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"' \"\$1\"" _ "$INSTALL" "$DEPLOYLIB"

# --- 7. update.sh / status.sh wiring ------------------------------------------------

check "update.sh KIT_FILES includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys ddev-migrate.sh (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh 644' \"\$2\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-migrate 755' \"\$2\" && grep -q 'lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"' \"\$1\"" _ "$UPDATE" "$DEPLOYLIB"
check "status.sh reports dumps waiting for import" \
    sh -c "grep -q 'db dumps' \"\$1\" && grep -q 'bin/ddev-migrate import' \"\$1\"" _ "$STATUS"
check "status.sh import detection knows the ddev >= 1.23 project_list.yaml" \
    sh -c "grep -q 'project_list.yaml' \"\$1\" && grep -q 'approot:' \"\$1\"" _ "$STATUS"

# --- 8. Makefile + CI wiring --------------------------------------------------------

check "make lint covers ddev-migrate.sh (disk-derived list, 0.0.42d C4)" \
    sh -c "make -C \"\$2/../..\" -n lint 2>/dev/null | grep -q 'ddev-migrate.sh' && grep -qF 'shellcheck shell=' \"\$1\"" _ "$MAKEFILE" "$SCRIPT_DIR"
check "Makefile has a test-ddev-migrate target in the test: list" \
    sh -c "grep -q 'test: .*test-ddev-migrate' \"\$1\"" _ "$MAKEFILE"
check "test-unit.yml run step mentions the new test" \
    sh -c "grep -q 'test-ddev-migrate.sh' \"\$1\"" _ "$TEST_CI"
# ddev-migrate.sh is a sourced lib (bin/ddev-migrate dispatcher, status.sh)
# — per the repo invariant (755 <=> executed by path) it must be 100644.
check "ddev-migrate.sh is a sourced lib (git 100644, not executed by path)" \
    sh -c '[ "$(git -C "$2" ls-files -s -- files/opencode-permissions-kit-lib/sh/ddev-migrate.sh | cut -d" " -f1)" = "100644" ]' _ x "$SCRIPT_DIR/../.."

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
# Registry fixture preserving the SHAPES of a real-world production
# report (mixed case, digits, dashes, underscores, dotted domain names,
# all approots under one root) with fully synthetic names — no real
# client identifiers in the repo (maintainer directive 2026-10-04).
mkdir -p "$WORK/maxmustermann/.ddev"
cat > "$WORK/maxmustermann/.ddev/project_list.yaml" <<'YML'
shopone:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/shopone
client24-SW6:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client24-SW6
client03-shopware-sw6:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client03-shopware-sw6
client04-sap:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client04-sap
client05-multi-store:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client05-multi-store
client06-advent-calendar:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client06-advent-calendar
client07-test-260605:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client07-test-260605
client08-6-7-0-1:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client08_6_7_0_1
client09-hub:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client09-hub
client10-vinum:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client10-vinum
client11-xmas:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/client11-xmas
www.client12-example.test:
    approot: /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/www.client12-example.test
YML
assert_eq "real-world registry: all 12 projects parsed (case + dots)" "12" \
    "$(sh -c '. "$1" && ddev_migrate_registry "$2"' _ "$MIG" "$WORK/maxmustermann/.ddev" | grep -c .)"
assert_eq "real-world registry: nothing outside the root" "" \
    "$(sh -c '. "$1" && ddev_migrate_outside "$2" /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts' _ "$MIG" "$WORK/maxmustermann/.ddev")"
assert_eq "narrow root: the other 11 are reported outside" "11" \
    "$(sh -c '. "$1" && ddev_migrate_outside "$2" /var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts/shopone' _ "$MIG" "$WORK/maxmustermann/.ddev" | grep -c .)"

# The gap detector needs the approots to EXIST (ddev_migrate_projects
# drops stale entries) — mirror the registry into the fixture tree.
mkdir -p "$WORK/maxmustermann2/.ddev"
sed "s|/var/tmp/opencode-ddev-mig-roots/home/maxmustermann/www/vhosts|$WORK/maxmustermann-vhosts|g" "$WORK/maxmustermann/.ddev/project_list.yaml" \
    > "$WORK/maxmustermann2/.ddev/project_list.yaml"
sh -c '. "$1" && ddev_migrate_registry "$2"' _ "$MIG" "$WORK/maxmustermann2/.ddev" \
    | while IFS='|' read -r _gn _ga; do mkdir -p "$_ga"; done
mkdir -p "$WORK/gapbackups/ddev-migration-20260909-232704"
printf 'OK|shopone|%s/maxmustermann-vhosts/shopone|shopone.sql.gz\n' "$WORK" \
    > "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
GAP=$(DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' _ "$MIG" "$WORK/maxmustermann-vhosts")
assert_eq "gap: 1 dump recorded vs 12 registered -> have/now reported" \
    "1 12 $WORK/gapbackups/ddev-migration-20260909-232704" "$GAP"
for _gn in client24-SW6 client03-shopware-sw6 client04-sap client05-multi-store \
           client06-advent-calendar client07-test-260605 client08-6-7-0-1 client09-hub \
           client10-vinum client11-xmas www.client12-example.test; do
    printf 'OK|%s|%s/maxmustermann-vhosts/x|%s.sql.gz\n' "$_gn" "$WORK" "$_gn" \
        >> "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
done
if DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2" >/dev/null' _ "$MIG" "$WORK/maxmustermann-vhosts"; then
    fail "gap: complete manifest reports NO gap"
else
    pass "gap: complete manifest reports NO gap"
fi
# A FAIL entry counts as ATTEMPTED (production: a project whose database
# was never pulled must not nag the gap warning forever) — 11 OK + 1 FAIL
# = 12 attempted vs 12 registered: no gap (OK-only counting would warn).
sed -i '/^OK|client09-hub|/d' "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
printf 'FAIL|client09-hub|%s/maxmustermann-vhosts/x|client09-hub.sql.gz\n' "$WORK" \
    >> "$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
if DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2" >/dev/null' _ "$MIG" "$WORK/maxmustermann-vhosts"; then
    fail "gap: FAIL entries count as attempted (no gap)"
else
    pass "gap: FAIL entries count as attempted (no gap)"
fi

# registry subcommand (read-only, no root gate): export/outside view
OUT=$(DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" sh "$BIN_MIG" registry maxmustermann "$WORK/maxmustermann-vhosts")
assert_eq "registry cmd: all 12 under the root classified export" "12" \
    "$(printf '%s\n' "$OUT" | grep -c '^  export:')"
assert_eq "registry cmd: none outside" "0" \
    "$(printf '%s\n' "$OUT" | grep -c '^  outside:')"
OUT=$(DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" sh "$BIN_MIG" registry maxmustermann "$WORK/maxmustermann-vhosts/shopone" 2>/dev/null || true)
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

# --- 6c. spaced-home quoting (0.0.43a F6) --------------------------------------------
# A developer home with whitespace must not split the per-user ddev
# candidates (the bare directory prefix used to pass [ -x ] and was
# emitted AS the binary) and env assignments must stay single arguments.
# Hermetic: getent + sudo are PATH shims; a non-executable `ddev` shadows
# nothing (command -v only reports executables); the bin-resolution case
# is skipped on hosts with a system ddev (its absolute-path candidates
# would win by design).
mkdir -p "$WORK/spaced home/.local/bin" "$WORK/spaced"
printf '#!/bin/sh\necho real-ddev\n' > "$WORK/spaced home/.local/bin/ddev"
chmod +x "$WORK/spaced home/.local/bin/ddev"
printf '#!/bin/sh\n' > "$WORK/spaced/ddev"
# non-executable `ddev` on PATH: command -v must not find it
cat > "$WORK/getent" <<EOF
#!/bin/sh
[ "\$1" = passwd ] && { printf '%s\n' "spaced:x:\$(id -u):\$(id -g)::$WORK/spaced home:/bin/sh"; exit 0; }
exec $(command -v getent) "\$@"
EOF
chmod +x "$WORK/getent"
if [ -x /usr/local/bin/ddev ] || [ -x /usr/bin/ddev ]; then
    echo "  SKIP  spaced-home bin resolution (host has a system ddev — absolute-path candidates would win)"
else
    cat > "$WORK/binres.sh" <<'WRAP'
#!/bin/sh
. "$1"
_ddev_migrate_bin spaced
WRAP
    _bin_out="$(PATH="$WORK:$PATH" sh "$WORK/binres.sh" "$MIG" 2>/dev/null || true)"
    assert_eq "spaced home: the real binary resolves (not the directory prefix)" \
        "$WORK/spaced home/.local/bin/ddev" "$_bin_out"
    check_fail "spaced home: the searchable dir is never emitted as the binary" \
        sh -c "[ \"\$_bin_out\" = \"\$1\" ]" _ "$WORK/spaced"
fi

# run-as: each env assignment is ONE argument — a sudo shim prints argv
# one word per line, so a split HOME would show as separate lines.
cat > "$WORK/sudo" <<'EOF'
#!/bin/sh
for _a in "$@"; do printf '%s\n' "$_a"; done
EOF
chmod +x "$WORK/sudo"
cat > "$WORK/runas.sh" <<'WRAP'
#!/bin/sh
. "$1"
_ddev_migrate_run_as spaced /bin/true
WRAP
_runas_out="$(PATH="$WORK:$PATH" sh "$WORK/runas.sh" "$MIG" 2>/dev/null || true)"
check "run-as passes a spaced HOME as one single argument" \
    sh -c "printf '%s\n' \"\$2\" | grep -qxF \"HOME=\$1\"" _ "$WORK/spaced home" "$_runas_out"
# The caller's COMMAND must survive the env rebuild (e2e regression: a
# draft dropped "$@" from the set -- and every call degenerated into a
# command-less `env` print with rc 0 — start "succeeded", no dump).
check "run-as still executes the caller's command after the env words" \
    sh -c "printf '%s\n' \"\$1\" | grep -qxF '/bin/true'" _ "$_runas_out"
check "run-as never runs a command-less env" \
    sh -c "[ \"\$(printf '%s\n' \"\$1\" | tail -n +5)\" != \"\" ]" _ "$_runas_out"

# static: the import loop builds HOME via getent and rides conditional
# backend vars as single quoted arguments (0.0.43a F6/F12).
check "import resolves the agent HOME via getent (not /home/<user>)" \
    sh -c "grep -qF 'dm_oc_h=\$(getent passwd' \"\$1\"" _ "$MIG"
check "import passes HOME/XDG as single quoted arguments" \
    sh -c "grep -qF 'env \"HOME=\$dm_oc_h\" \"XDG_RUNTIME_DIR=/run/user/\$dm_oc_i\"' \"\$1\"" _ "$MIG"
check_fail "import no longer word-splits an env string" \
    sh -c "grep -q 'env \$dm_env' \"\$1\"" _ "$MIG"

# --- Summary ------------------------------------------------------------------------

# Cleanup the fixture sandbox root. Unit-test policy (0.0.42e C1): suites
# touch only their scratch and /tmp,/var/tmp -- never real project trees.
rm -rf /var/tmp/opencode-ddev-mig-roots 2>/dev/null || true

echo ""
echo "========================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
