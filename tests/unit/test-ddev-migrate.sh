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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../../files"
MIG="$FILES/opencode-permissions-kit-lib/sh/ddev-migrate.sh"
BIN_MIG="$FILES/opencode-permissions-kit-lib/bin/ddev-migrate"
INSTALL="$FILES/install.sh"
# Phase literals (export wave, stamps, handover ordering) live in install-core.sh since #346 wave 3.
INSTALL_CORE="$FILES/opencode-permissions-kit-lib/sh/install-core.sh"
UPDATE="$FILES/opencode-permissions-kit-lib/management/update.sh"
UPDATE_CORE="$FILES/opencode-permissions-kit-lib/sh/update-core.sh"
STATUS="$FILES/opencode-permissions-kit-lib/management/status.sh"
STATUS_CORE="$FILES/opencode-permissions-kit-lib/sh/status-core.sh"
DEPLOYLIB="$FILES/opencode-permissions-kit-lib/sh/deploy-lib.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"

# Shared harness (issue #394 adoption): pass/fail, colors, counters
# and the summary gate live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        fail "$desc (expected absence, got a match)"
    else
        pass "$desc"
    fi
}

WORK=$(work_new)

echo ""
echo "ddev database migration Tests (issue #15)"
echo "========================================"
echo ""

# --- 1. registry parser --------------------------------------------------------

mkdir -p "$WORK/devhome/.ddev"
cat >"$WORK/devhome/.ddev/global_config.yaml" <<'YML'
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

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome/.ddev") || true
assert_eq "registry parser reads name|approot pairs (quoted + unquoted)" \
    "alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside" "$RESULT"

# --- 2. root filter --------------------------------------------------------------

# Fixtures are written sandboxed at the source (maintainer directive
# 2026-10-04, 0.0.42f C3): unit suites never carry real-tree literals —
# not even inert ones an earlier sed would have rewritten.
mkdir -p /var/tmp/opencode-ddev-mig-roots/vhosts/alpha /var/tmp/opencode-ddev-mig-roots/vhosts/client/beta /var/tmp/opencode-ddev-mig-roots/srv/other/outside 2>/dev/null || true

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts") || true
assert_eq "root filter keeps only projects under the registered roots" \
    "alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta" "$RESULT"

# Nonexistent approots are dropped (stale registry entries).
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome/.ddev" "/does/not/exist") || true
assert_eq "root filter with no matching dirs yields nothing" "" "$RESULT"

# --- 2b. ddev >= 1.23 registry: standalone project_list.yaml -----------------------
# ddev >= 1.23.0 (commit 94d77509a) keeps the project list in its own
# project_list.yaml — top-level name map, 4-space indent as written by
# ddev's yaml.Marshal — and clears the legacy project_info: block in
# global_config.yaml on first run. The parser must read BOTH layouts.
mkdir -p "$WORK/devhome123/.ddev"
cat >"$WORK/devhome123/.ddev/project_list.yaml" <<'YML'
client07-test-260605:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
    used_host_ports: []
beta:
    approot: "/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta"
outside:
    approot: /var/tmp/opencode-ddev-mig-roots/srv/other/outside
YML
printf 'last_started_version: v1.25.2\nwebimage: ddev/ddev-webserver\n' >"$WORK/devhome123/.ddev/global_config.yaml"

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome123/.ddev") || true
assert_eq "registry parser reads the ddev >= 1.23 project_list.yaml (quoted + unquoted)" \
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
outside|/var/tmp/opencode-ddev-mig-roots/srv/other/outside" "$RESULT"

RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome123/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts") || true
assert_eq "root filter applies to project_list.yaml projects too" \
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta" "$RESULT"

# Both layouts side by side (mid-migration home): entries from both
# files are emitted — duplicates are tolerated downstream (the export
# resume logic skips projects already in the manifest).
mkdir -p /var/tmp/opencode-ddev-mig-roots/vhosts/gamma
cat >"$WORK/devhome123/.ddev/global_config.yaml" <<'YML'
project_info:
  legacy-only:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/gamma
YML
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_projects \"\$2\" \"\$3\"" _ "$MIG" "$WORK/devhome123/.ddev" "/var/tmp/opencode-ddev-mig-roots/vhosts") || true
assert_eq "legacy and modern registry files are BOTH scanned" \
    "client07-test-260605|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha
beta|/var/tmp/opencode-ddev-mig-roots/vhosts/client/beta
legacy-only|/var/tmp/opencode-ddev-mig-roots/vhosts/gamma" "$RESULT"

# ddev creates an EMPTY project_list.yaml on fresh homes — no projects.
printf 'last_started_version: v1.25.2\n' >"$WORK/devhome123/.ddev/global_config.yaml"
: >"$WORK/devhome123/.ddev/project_list.yaml"
RESULT=$(sh -c ". \"\$1\" && ddev_migrate_registry \"\$2\"" _ "$MIG" "$WORK/devhome123/.ddev") || true
assert_eq "empty project_list.yaml + bare global config yields nothing" "" "$RESULT"

# --- 2c. ddev_migrate_done: both registry layouts count ----------------------------
# DDEV_MIG_OC_HOME pins the check to the fixture (real path is always
# /home/<opencode-user>).
done_check() { sh -c ". \"\$1\" && if DDEV_MIG_OC_HOME=\"\$2\" ddev_migrate_done oc; then echo yes; else echo no; fi" _ "$MIG" "$1"; }
mkdir -p "$WORK/ochome/.ddev"

printf 'last_started_version: v1.25.2\n' >"$WORK/ochome/.ddev/global_config.yaml"
: >"$WORK/ochome/.ddev/project_list.yaml"
assert_eq "done: bare modern home (empty list) is NOT done" "no" "$(done_check "$WORK/ochome")"

printf 'shopware:\n    approot: /tmp/shopware\n' >"$WORK/ochome/.ddev/project_list.yaml"
assert_eq "done: project_list.yaml entries count" "yes" "$(done_check "$WORK/ochome")"

rm -f "${WORK:?}/ochome/.ddev/project_list.yaml"
printf 'project_info:\n  p:\n    approot: /tmp/p\n' >"$WORK/ochome/.ddev/global_config.yaml"
assert_eq "done: legacy project_info block counts" "yes" "$(done_check "$WORK/ochome")"

rm -rf "${WORK:?}/devhome123" "${WORK:?}/ochome"

# --- 3. omit_containers detection -------------------------------------------------

has_db() { sh -c ". \"\$1\" && if ddev_migrate_has_db \"\$2\" \"\$3\"; then echo yes; else echo no; fi" _ "$MIG" "$1" "$WORK/devhome/.ddev"; }

mkproj() {
    mkdir -p "$WORK/$1/.ddev"
    printf '%s\n' "$2" >"$WORK/$1/.ddev/config.yaml"
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

printf 'omit_containers_global: [db]\n' >"$WORK/devhome/.ddev/global_config.yaml"
assert_eq "global omit_containers_global [db] has NO db" "no" "$(has_db "$WORK/p1")"
printf 'omit_containers_global:\n  - db\n' >"$WORK/devhome/.ddev/global_config.yaml"
assert_eq "global block omit has NO db" "no" "$(has_db "$WORK/p1")"
rm -f "${WORK:?}/devhome/.ddev/global_config.yaml"
assert_eq "missing global config keeps the db" "yes" "$(has_db "$WORK/p1")"

# --- 4. export loop with a fake ddev ----------------------------------------------
# The fake ddev logs every invocation; export-db writes the dump to the
# --file= path it receives. ddev commands must address projects by NAME
# (registry key), never by path.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/ddev" <<'FAKE'
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
# DDEV_FAKE_SWAP=<project>:<target> (#264): simulates a mid-export
# operand swap in the gate->export window — export-db writes the dump
# FIRST, then the operand is replaced by a symlink to <target> (what a
# live agent can do between the loop-top gate and ddev opening the
# file). The victim is never written through: only the dump the stub
# just wrote is unlinked.
if [ -n "${DDEV_FAKE_SWAP:-}" ] && [ "$1" = "export-db" ] &&
    [ "$2" = "${DDEV_FAKE_SWAP%%:*}" ]; then
    _sw_tgt=${DDEV_FAKE_SWAP#*:}
    for a in "$@"; do
        case "$a" in
            --file=*) rm -f "${a#--file=}"; ln -s "$_sw_tgt" "${a#--file=}" ;;
        esac
    done
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
cat >"$WORK/devhome/.ddev/global_config.yaml" <<'YML'
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
printf 'name: alpha\ntype: typo3\n' >/var/tmp/opencode-ddev-mig-roots/vhosts/alpha/.ddev/config.yaml
printf 'name: gamma\ntype: php\n' >/var/tmp/opencode-ddev-mig-roots/vhosts/gamma/.ddev/config.yaml
printf 'omit_containers: [db]\n' >/var/tmp/opencode-ddev-mig-roots/vhosts/nodb/.ddev/config.yaml
printf 'name: broken\ntype: typo3\n' >/var/tmp/opencode-ddev-mig-roots/vhosts/broken/.ddev/config.yaml
printf 'name: nodbrt\ntype: typo3\n' >/var/tmp/opencode-ddev-mig-roots/vhosts/nodbrt/.ddev/config.yaml

# Run the library export directly with a controlled backup root; the sudo
# detour is shimmed (CI runs unprivileged) by overriding the run-as helper
# after sourcing. DDEV_MIG_DEV_HOME pins the registry to the fixture (the
# current user may BE "opencode" with a real registry on kit workspaces).
# The "opencode user" argument is root so the handed-over guard (stat
# owner == oc user) never fires for the current-user fixtures.
cat >"$WORK/run-export.sh" <<'WRAP'
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
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null) || true
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
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts) || true

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
echo "VICTIM-ERR-CONTENT" >"$WORK/victim-err.conf"
echo "VICTIM-DUMP-CONTENT" >"$WORK/victim-dump.conf"
chmod 755 "$WORK/victim-dump.conf"
ln -s "$WORK/victim-err.conf" "$DUMP_DIR/.export-alpha.err"
ln -s "$WORK/victim-dump.conf" "$DUMP_DIR/evil.sql.gz"
OUT3=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null) || true
check "planted .export-*.err link is never touched (captures live in .root-stage)" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-ERR-CONTENT" _ "$WORK/victim-err.conf"
check "chmod pass skips symlink operands (victim keeps its mode)" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 755" _ "$WORK/victim-dump.conf"
check "manifest stays a regular file through the run" \
    sh -c "test -f \"\$1\" && test ! -L \"\$1\"" _ "$DUMP_DIR/manifest.conf"
# Sticky + stage mode act DURING the run (finalize re-modes the dir to
# 750) — pinned statically on the mechanisms (W1): chmod 3770 at setup
# AND on resume, mkdir -m 700 for the stage. Comment-strip rider (#261,
# the #244 g W1 class): a commented-out chmod stops counting.
_grep_n=$(live_src "$MIG" | grep -c 'chmod 3770 "\$DD_MIG_DUMP_DIR"' || true)
[ "$_grep_n" -ge 1 ] &&
    check "dump dir is set sticky (3770) — group rename of root entries blocked (W1)" true ||
    check "dump dir is set sticky (3770) — group rename of root entries blocked (W1; chmod 3770 sites: $_grep_n, need >=1)" false
grep -q 'mkdir -m 700 "\$DM_STAGE"' "$MIG" &&
    check "stage is created mode 700 in one step (no default-mode window, W1)" true ||
    check "stage is created mode 700 in one step (no default-mode window, W1)" false
check_fail "the root staging dir is removed before finalize hands the tree over" \
    test -e "$DUMP_DIR/.root-stage"

# --- 4c2. the dump operand itself: a planted link at the loop top is REFUSED (#264) ----
# The dump dir is agent-group-writable for the whole wave; ddev
# export-db opens --file for WRITING as the dev user, and the resume
# probe's [ -s ] FOLLOWS a link — a planted non-empty alpha.sql.gz plus
# the OK line run 4b left behind would resume-mark the project off the
# plant. The gate must refuse BEFORE the resume probe: no start, no
# export-db, victim intact, FAIL entry, the stale OK line replaced
# (single entry), and the remaining projects still processed
# (per-project refusal, no abort).
mv "$WORK/ddev.log" "$WORK/ddev-4c2-pre.log"
printf 'VICTIM-GATE-CONTENT\n' >"$WORK/victim-gate.conf"
rm -f "${DUMP_DIR:?}/alpha.sql.gz"
ln -s "$WORK/victim-gate.conf" "$DUMP_DIR/alpha.sql.gz"
# A8 discriminator (#420 a): alpha is FIRST in the registry — a
# `continue` must still reach the LATER projects in the SAME run.
# gamma's dump is removed so gamma must actually EXPORT in this run
# (resumed projects log nothing); a break at alpha's refusal leaves the
# log without gamma's export and this pin red.
rm -f "${DUMP_DIR:?}/gamma.sql.gz"
OUTG=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1) || true
case "$OUTG" in
    *"REFUSED: $DUMP_DIR/alpha.sql.gz is a symlink"*)
        pass "planted dump operand refused loudly, before the resume probe (#264)"
        ;;
    *) fail "planted dump operand must be refused loudly (got: $OUTG) (#264)" ;;
esac
check "refused operand: the project is never started" \
    sh -c "! grep -q 'ddev:start alpha' \"\$1\"" _ "$WORK/ddev.log"
check "refused operand: export-db never opens the link" \
    sh -c "! grep -q 'ddev:export-db alpha' \"\$1\"" _ "$WORK/ddev.log"
check "refused operand: the victim behind the link keeps its content" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-GATE-CONTENT" _ "$WORK/victim-gate.conf"
check "refused operand: FAIL entry lands in the manifest" \
    sh -c "grep -q '^FAIL|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check_fail "the stale OK line is replaced by the refusal (single entry)" \
    sh -c "grep -q '^OK|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
assert_eq "refused run: SKIP projects still processed after the refusal" \
    "2" "$(grep -c '^SKIP|' "$DUMP_DIR/manifest.conf")"
check "refused run: the loop CONTINUES past the refused project (gamma exports, #420 a A8)" \
    sh -c "grep -q 'ddev:export-db gamma' \"\$1\"" _ "$WORK/ddev.log"
check "refused run: the wave still finishes (poweroff ran, no abort)" \
    sh -c "grep -q 'ddev:poweroff' \"\$1\"" _ "$WORK/ddev.log"
check "the refused link stays in place — it is evidence for the operator (#420 a A9)" \
    sh -c "test -L \"\$1\"" _ "$DUMP_DIR/alpha.sql.gz"
# Operator path: remove the tampering link, re-run — the refused
# project exports again and the manifest returns to single OK entries
# (sections 4d+ see the pre-4c2 state).
rm -f "${DUMP_DIR:?}/alpha.sql.gz"
OUTG2=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run-g2.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1) || true
check "after link removal the refused project exports again" \
    sh -c "grep -q 'ddev:export-db alpha' \"\$1\"" _ "$WORK/ddev-run-g2.log"
check "manifest back to one OK line for the project, FAIL gone" \
    sh -c "grep -q '^OK|alpha|' \"\$1\" && ! grep -q '^FAIL|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"

# --- 4c2b. a FIFO at the dump operand is refused too (#420 a A6) ---------------------
# [ -L ] alone admits a FIFO or device node — and ddev export-db's
# open/write on a FIFO blocks indefinitely (verified from the ddev
# source: open-blocks at ddev HEAD, write-blocks after the pipe buffer
# at v1.25.3), hanging the dev-side export the root installer waits on.
# The manifest path closed this class with find -type f (0.0.44c C2);
# the operand gate now refuses every NOT-REGULAR entry the same way.
if command -v mkfifo >/dev/null 2>&1; then
    mv "$WORK/ddev.log" "$WORK/ddev-4c2b-pre.log"
    rm -f "${DUMP_DIR:?}/alpha.sql.gz"
    mkfifo "$DUMP_DIR/alpha.sql.gz"
    OUTGF=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev.log" \
        DDEV_MIG_DEV_HOME="$WORK/devhome" \
        PATH="$WORK/bin:$PATH" \
        sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1) || true
    case "$OUTGF" in
        *"REFUSED: $DUMP_DIR/alpha.sql.gz is not a regular file"*)
            pass "FIFO dump operand refused loudly as not-regular (#420 a A6)"
            ;;
        *) fail "FIFO dump operand must be refused as not-regular (got: $OUTGF) (#420 a A6)" ;;
    esac
    check "FIFO operand: export-db never opens it (no hang)" \
        sh -c "test -f \"\$1\" && ! grep -q 'ddev:export-db alpha' \"\$1\"" _ "$WORK/ddev.log"
    check "FIFO operand counts FAIL like the symlink refusal" \
        sh -c "grep -q '^FAIL|alpha|' \"\$1\" && ! grep -q '^OK|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
    # restore: remove the FIFO (rm never blocks on a fifo inode), alpha
    # re-exports on the next section's runs (4c3 rm's the operand again
    # anyway — state converges regardless).
    rm -f "${DUMP_DIR:?}/alpha.sql.gz"
else
    echo "SKIP  4c2b FIFO operand refusal (mkfifo unavailable on this host)"
fi

# --- 4c3. a swap INSIDE the gate->export window fails the export, never OKs (#264) -----
# The loop-top gate re-checks the operand, but the window until ddev
# opens the file stays agent-writable: the fake ddev (DDEV_FAKE_SWAP)
# writes the dump, then replaces the operand with a symlink — the
# success probe must refuse the LINK ([ -s ] alone follows it; with an
# OK line the resume would skip the project forever). The failure arm
# unlinks the LINK only; the victim is never written through.
rm -f "${DUMP_DIR:?}/alpha.sql.gz"
printf 'VICTIM-SWAP-CONTENT\n' >"$WORK/victim-swap.conf"
OUTGS=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run-gs.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" DDEV_FAKE_SWAP="alpha:$WORK/victim-swap.conf" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1) || true
check "swapped operand: the export counts as FAILED, never OK" \
    sh -c "grep -q '^FAIL|alpha|' \"\$1\" && ! grep -q '^OK|alpha|' \"\$1\"" _ "$DUMP_DIR/manifest.conf"
check "swapped operand: the failure arm unlinks the planted link" \
    sh -c "test ! -e \"\$1\" && test ! -L \"\$1\"" _ "$DUMP_DIR/alpha.sql.gz"
# Seam-sanity leg, NOT gate evidence (#420 a A10): the fake ddev writes
# the dump FIRST and swaps after — nothing in the stub ever writes
# through the link, so this pin stays green under ANY mutation of the
# [ ! -L ] recheck. It guards the stub contract (the rm -f arm never
# follows the link) only; the gate's discriminators are the FAIL-never-
# OK and link-unlinked legs above.
check "swapped operand: stub sanity — the victim's content is untouched by the arm's rm -f" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-SWAP-CONTENT" _ "$WORK/victim-swap.conf"
case "$OUTGS" in
    *"FAILED: ddev export-db — no dump for alpha"*)
        pass "swapped operand: the FAILED line names the project (#264)"
        ;;
    *) fail "swapped operand: expected the FAILED export line (got: $OUTGS) (#264)" ;;
esac
# restore: alpha exports normally again (state identical to pre-4c2)
OUTG3=$(DDEV_MIG_BACKUP_ROOT="$WORK/backups" DDEV_LOG="$WORK/ddev-run-g3.log" \
    DDEV_MIG_DEV_HOME="$WORK/devhome" \
    PATH="$WORK/bin:$PATH" \
    sh "$WORK/run-export.sh" "$MIG" "$(id -un)" root "$(id -gn)" /var/tmp/opencode-ddev-mig-roots/vhosts </dev/null 2>&1) || true
check "after the failed swap export the project exports cleanly" \
    sh -c "grep -q 'ddev:export-db alpha' \"\$1\" && grep -q '^OK|alpha|' \"\$2\"" \
    _ "$WORK/ddev-run-g3.log" "$DUMP_DIR/manifest.conf"

# --- 4d. a linked manifest at export START is refused, never read (0.0.44b W2) -------
# The authoritative copy seeds from the dump-dir manifest only when it is
# not a symlink — a planted link there means tampering: loud refuse, the
# link's target is never opened (no read-through disclosure).
echo "VICTIM-MANIFEST-CONTENT" >"$WORK/victim-manifest.conf"
rm -f "${DUMP_DIR:?}/manifest.conf"
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
rm -f "${DUMP_DIR:?}/manifest.conf"
printf 'OK|alpha|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha|alpha.sql.gz\n' >"$DUMP_DIR/manifest.conf"

# --- 4e. fixed-string resume: sh.p must not cross-match shop (0.0.44b W13) -------------
# The resume check and the stale-rewrite are grep -F since 0.0.44a V23 —
# but nothing pinned it: all fixtures were metacharacter-free, so the old
# BRE ("sh.p" cross-matches "shop") was indistinguishable. A hand-edited
# registry (ddev itself enforces [a-z0-9-]) carries both names; the OK
# line for shop must NOT satisfy sh.p's resume check.
cat >>"$WORK/devhome/.ddev/project_list.yaml" <<YML
  shop:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
  sh.p:
    approot: /var/tmp/opencode-ddev-mig-roots/vhosts/alpha
YML
printf 'dump\n' >"$DUMP_DIR/shop.sql.gz"
printf 'dump\n' >"$DUMP_DIR/sh.p.sql.gz"
printf 'OK|shop|/var/tmp/opencode-ddev-mig-roots/vhosts/alpha|shop.sql.gz\n' >>"$DUMP_DIR/manifest.conf"
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
    sh -c "grep -q 'DD_MIG_FAILLIST' \"\$1\" && ! grep -q \"grep -c '^OK|' \\\"\\\$DD_MIG_DUMP_DIR/manifest.conf\\\"\" \"\$1\"" _ "$INSTALL_CORE"
check "export return state starts EMPTY — counters signal completion (E1)" \
    sh -c "grep -A3 -F 'DD_MIG_DUMP_DIR=\"\"' \"\$1\" | tr -s '[:space:]' ' ' | grep -qF 'DD_MIG_DUMP_DIR=\"\" DD_MIG_OK=\"\" DD_MIG_FAIL=\"\" DD_MIG_FAILLIST=\"\"' " _ "$MIG"

# --- 4h. refused vs completed: only the accounting fills the counters (0.0.44e E1) -------
cat >"$WORK/run-export-state.sh" <<'WRAP'
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

# --- 4i. finalize: root-side ops BEFORE the hand-over (0.0.45c S2/S5) --------------
# The swap race itself is not unit-pinnable — the pins are (a) ORDER
# statics on the extracted finalize block (the old order: chown -R first,
# operand chmod/chown after — the trailing `chown root:` dereferenced a
# planted manifest link (S2, arbitrary chgrp) and the find-chmods raced
# swapped dumps (S5, arbitrary mode strip)) and (b) the behavioral end
# state on a fixture with planted links. Restoring any chown -R over the
# dump dir, the bare `chown root:… manifest.conf` operand, or an operand
# op after the hand-over chown fails these pins (sabotage duty).
sed -n '/^    rm -rf "\$DM_STAGE" 2>\/dev\/null || true$/,/^    \[ "\${DD_MIG_OK:-0}" -gt 0 \]$/p' \
    "$MIG" >"$WORK/finblock"
if [ -s "$WORK/finblock" ]; then
    check "finalize block scoping: compact, no EOF over-run (4i)" \
        sh -c "[ \"\$(wc -l < \"\$1\")\" -le 45 ]" _ "$WORK/finblock"
    check "finalize never chown -R's the dump dir — per-entry hand-over only (S2)" \
        sh -c "! grep -q 'chown -R' \"\$1\"" _ "$WORK/finblock"
    check "finalize: the bare manifest operand chown (the S2 dereference shape) is gone" \
        sh -c "! grep -qF 'chown \"root:\$dm_ocg\" \"\$DD_MIG_DUMP_DIR/manifest.conf\"' \"\$1\"" _ "$WORK/finblock"
    check "finalize: the manifest re-take rides the find gate (S2)" \
        sh -c "grep -qF -- '-exec chown \"root:\$dm_ocg\" {} +' \"\$1\"" _ "$WORK/finblock"
    _fm_fin_src=$(live_src "$WORK/finblock")
    check "finalize: dir lock (root takes the dir) precedes every operand op (S2/S5)" \
        sh -c 'lock_ln=$(printf "%s\n" "$1" | grep -n "^    chown \"root:\$dm_ocg\" \"\$DD_MIG_DUMP_DIR\" " | head -1 | cut -d: -f1);
            op_ln=$(printf "%s\n" "$1" | grep -n "chmod 640" | head -1 | cut -d: -f1);
            [ -n "$lock_ln" ] && [ -n "$op_ln" ] && [ "$lock_ln" -lt "$op_ln" ]' _ "$_fm_fin_src"
    check "finalize: NO operand mutation after the first agent hand-over (S2/S5)" \
        sh -c 'last_mut=$(printf "%s\n" "$1" | grep -n "chmod" | tail -1 | cut -d: -f1);
            first_ho=$(printf "%s\n" "$1" | grep -n "chown \"\$dm_oc:" | head -1 | cut -d: -f1);
            [ -n "$last_mut" ] && [ -n "$first_ho" ] && [ "$last_mut" -lt "$first_ho" ]' _ "$_fm_fin_src"
    # behavioral end state: planted links survive untouched, dumps and
    # manifest end 640, the dir 750, the stage is gone (unprivileged:
    # chowns fail EPERM into || true — the end STATE is still exactly
    # the contract; the order statics above are the discriminators).
    _fbd="$WORK/fin-fixture"
    mkdir -p "$_fbd/.root-stage"
    : >"$_fbd/.root-stage/stale"
    printf 'dump\n' >"$_fbd/alpha.sql.gz"
    chmod 644 "$_fbd/alpha.sql.gz"
    printf 'manifest\n' >"$_fbd/manifest.conf"
    chmod 644 "$_fbd/manifest.conf"
    printf 'VICTIM-DUMP\n' >"$WORK/fin-victim"
    chmod 755 "$WORK/fin-victim"
    ln -s "$WORK/fin-victim" "$_fbd/evil.sql.gz"
    DD_MIG_DUMP_DIR="$_fbd" DM_STAGE="$_fbd/.root-stage" DD_MIG_OK=1 \
        dm_oc="$(id -un)" dm_ocg="$(id -gn)" \
        sh -c 'eval "$(cat "$1")" >/dev/null 2>&1 || true' _ "$WORK/finblock" || true
    assert_eq "finalize end state: dump dir is 750" "750" "$(stat -c %a "$_fbd")"
    assert_eq "finalize end state: dump is 640" "640" "$(stat -c %a "$_fbd/alpha.sql.gz")"
    assert_eq "finalize end state: manifest is 640" "640" "$(stat -c %a "$_fbd/manifest.conf")"
    check "finalize end state: planted dump link is skipped, victim keeps 755" \
        sh -c "test -L \"\$1/evil.sql.gz\" && test \"\$(stat -c %a \"\$2\")\" = 755" _ "$_fbd" "$WORK/fin-victim"
    check_fail "finalize end state: the root stage is removed" test -e "$_fbd/.root-stage"
else
    fail "finalize block extractable (4i)"
fi

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
_fm_exp_src=$(live_src "$INSTALL_CORE")
check "install.sh runs the export in Step 4b (before the Step 5 handover)" \
    sh -c 'export_ln=$(printf "%s\n" "$1" | grep -n "ddev_migrate_export \"" | head -1 | cut -d: -f1);
        hand_ln=$(printf "%s\n" "$1" | grep -n "ddev_handover_root \"" | head -1 | cut -d: -f1);
        [ -n "$export_ln" ] && [ -n "$hand_ln" ] && [ "$export_ln" -lt "$hand_ln" ]' _ "$_fm_exp_src"
check "install.sh stamps DDEV_EXPORTED=1 after a successful export" \
    sh -c "grep -q 'DDEV_EXPORTED=1' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh gates the DDEV_EXPORTED stamp on zero failures" \
    sh -c "grep -qF '[ \"\$DD_MIG_FAIL\" -eq 0 ]' \"\$1\"" _ "$INSTALL_CORE"
# 0.0.44d F1: the counts now come from the export function's return
# state (set from the authoritative stage copy BEFORE the finalize hands
# the tree to the agent). A re-grep of the dump-dir manifest here would
# read an agent-owned file as root — the old pin demanded exactly that.
check "install.sh uses the propagated DD_MIG_* counts, never a manifest re-grep (F1)" \
    sh -c "grep -qF '[ -n \"\${DD_MIG_OK:-}\${DD_MIG_FAIL:-}\" ]' \"\$1\" && ! grep -qF 'grep -c \"^OK|\"' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh lists failed projects before continuing" \
    sh -c "grep -q 'could NOT be exported' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh asks before continuing with failed exports (default: abort)" \
    sh -c "grep -q 'ui_confirm \"Continue the install anyway?' \"\$1\" && grep -q '\"n\"' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh aborts BEFORE the handover when the user declines" \
    sh -c "grep -q 'the .ddev handover did NOT run' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh keeps exporting the remaining projects on failure (non-fatal loop)" \
    sh -c "grep -qF 'continue' \"\$1\"" _ "$MIG"
check "install.sh skips the export when already stamped" \
    sh -c "grep -q 'DDEV_EXPORTED_PRE' \"\$1\"" _ "$INSTALL_CORE"

# --- 6b. production-WSL findings (nb-laptop burn-in; workspace notes deleted) ----

# ddev detection: version probe falls back to the DEFAULT user — `ddev
# version` can come up empty as root while working as the actual user.
# (HOME rides DEV_HOME since 0.0.44a V14 — getent-resolved, /home/<name>
# only the fallback.)
check "install.sh probes the ddev version as the DEFAULT user too" \
    sh -c "grep -q 'DDEV_BIN_DEV' \"\$1\" && grep -q 'sudo -u \"\$DEFAULT_USER\" env HOME=\"\$DEV_HOME\"' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh inventory distinguishes found-but-unreadable from missing" \
    sh -c "grep -q 'version could not be read' \"\$1\" && grep -q 'not installed (optional' \"\$1\"" _ "$INSTALL_CORE"
check "migration detection is gated on the registry, not the binary" \
    sh -c "grep -qF 'if [ -d \"\$DEV_HOME/.ddev\" ]; then' \"\$1\"" _ "$INSTALL_CORE"
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
    sh -c "grep -q 'ddev projects' \"\$1\" && grep -q 'ddev_migrate_registry' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh plan mentions the database export when projects exist" \
    sh -c "grep -q 'export ddev databases' \"\$1\"" _ "$INSTALL_CORE"
check "install.sh deploys ddev-migrate.sh to the library (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh 644' \"\$2\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-migrate 755' \"\$2\" && grep -q 'lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"' \"\$1\"" _ "$INSTALL_CORE" "$DEPLOYLIB"

# --- 7. update.sh / status.sh wiring ------------------------------------------------

check "update.sh KIT_FILES includes ddev-migrate.sh" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys ddev-migrate.sh (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-migrate.sh 644' \"\$2\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-migrate 755' \"\$2\" && grep -q 'lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"' \"\$1\"" _ "$UPDATE_CORE" "$DEPLOYLIB"
check "status.sh reports dumps waiting for import" \
    sh -c "grep -q 'db dumps' \"\$1\" && grep -q 'bin/ddev-migrate import' \"\$1\"" _ "$STATUS_CORE"
check "status.sh import detection knows the ddev >= 1.23 project_list.yaml" \
    sh -c "grep -q 'project_list.yaml' \"\$1\" && grep -q 'approot:' \"\$1\"" _ "$STATUS_CORE"

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
: >"$WORK/ddev-bm.log"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run docker-rootless 1.25.2 "$WORK/bin/ddev")
check "ddev 1.25.2 on docker-rootless sets the switch" \
    sh -c "printf '%s' \"\$2\" | grep -q 'rc=0' && grep -q 'ddev:config global --no-bind-mounts' \"\$1\"" _ "$WORK/ddev-bm.log" "$OUT"
OUT=$(DDEV_LOG="$WORK/ddev-bm.log" PATH="$WORK/bin:$PATH" bm_run docker-rootless 1.25.0 "$WORK/bin/ddev")
check "ddev 1.25.0 on docker-rootless sets the switch" \
    sh -c "printf '%s' \"\$2\" | grep -q 'rc=0'" _ "$WORK/ddev-bm.log" "$OUT"
_n=$(wc -l <"$WORK/ddev-bm.log" | tr -d ' ')
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
    sh -c "grep -q 'ddev_rootless_bindmounts \"\$OPENCODE_USER\"' \"\$1\" && grep -qF '[ -n \"\$DDEV_BIN\" ] && [ -n \"\$DDEV_VERSION\" ]' \"\$1\"" _ "$INSTALL_CORE"
check "config.sh wires the bind-mounts switch on backend changes" \
    sh -c "grep -q 'ddev_rootless_bindmounts \"\$OPENCODE_USER\"' \"\$1\"" _ "$CONFIG_SH"

# --- 10. partial-export hardening (production finding: 1 of 12) --------------------
# Registry fixture preserving the SHAPES of a real-world production
# report (mixed case, digits, dashes, underscores, dotted domain names,
# all approots under one root) with fully synthetic names — no real
# client identifiers in the repo (maintainer directive 2026-10-04).
mkdir -p "$WORK/maxmustermann/.ddev"
cat >"$WORK/maxmustermann/.ddev/project_list.yaml" <<'YML'
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
    >"$WORK/maxmustermann2/.ddev/project_list.yaml"
sh -c '. "$1" && ddev_migrate_registry "$2"' _ "$MIG" "$WORK/maxmustermann2/.ddev" |
    while IFS='|' read -r _gn _ga; do mkdir -p "$_ga"; done
mkdir -p "$WORK/gapbackups/ddev-migration-20260909-232704"
printf 'OK|shopone|%s/maxmustermann-vhosts/shopone|shopone.sql.gz\n' "$WORK" \
    >"$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
GAP=$(DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' _ "$MIG" "$WORK/maxmustermann-vhosts")
assert_eq "gap: 1 dump recorded vs 12 registered -> have/now reported" \
    "1 12 $WORK/gapbackups/ddev-migration-20260909-232704" "$GAP"
for _gn in client24-SW6 client03-shopware-sw6 client04-sap client05-multi-store \
    client06-advent-calendar client07-test-260605 client08-6-7-0-1 client09-hub \
    client10-vinum client11-xmas www.client12-example.test; do
    printf 'OK|%s|%s/maxmustermann-vhosts/x|%s.sql.gz\n' "$_gn" "$WORK" "$_gn" \
        >>"$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
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
    >>"$WORK/gapbackups/ddev-migration-20260909-232704/manifest.conf"
if DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2" >/dev/null' _ "$MIG" "$WORK/maxmustermann-vhosts"; then
    fail "gap: FAIL entries count as attempted (no gap)"
else
    pass "gap: FAIL entries count as attempted (no gap)"
fi

# --- 10b. gap/import never read the dump-dir manifest as root (0.0.45c S6) --------
# After finalize the dump dir belongs to the agent — root must never OPEN
# a path inside it: the old `[ -f ]` + grep followed a planted symlink
# (root read the TARGET) and silently passed on a FIFO (warning
# suppressed). Delivery into a root-owned temp via find -type f only:
# links and FIFOs are skipped, never opened; the COPY is parsed.
_GDIR="$WORK/gapbackups/ddev-migration-20260909-232704"
mv "$_GDIR/manifest.conf" "$_GDIR/manifest.conf.keep"
printf 'no manifest lines here\n' >"$WORK/gap-victim.conf"
ln -s "$WORK/gap-victim.conf" "$_GDIR/manifest.conf"
GAP2=$(DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    timeout 10 sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' _ "$MIG" "$WORK/maxmustermann-vhosts" 2>/dev/null || true)
if [ -z "$GAP2" ]; then
    pass "gap: a symlinked manifest is refused, never read through (S6)"
else
    fail "gap: a symlinked manifest is refused, never read through (S6, got: $GAP2)"
fi
check "gap: the symlink target was never parsed as manifest content (S6)" \
    sh -c "test \"\$(cat \"\$1\")\" = 'no manifest lines here'" _ "$WORK/gap-victim.conf"
rm -f "${_GDIR:?}/manifest.conf"
mkfifo "$_GDIR/manifest.conf"
GAP3=$(DDEV_MIG_BACKUP_ROOT="$WORK/gapbackups" DDEV_MIG_DEV_HOME="$WORK/maxmustermann2" \
    timeout 10 sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' _ "$MIG" "$WORK/maxmustermann-vhosts" 2>/dev/null || true)
if [ -z "$GAP3" ]; then
    pass "gap: a FIFO manifest is skipped without hanging (S6, fail-safe no-gap)"
else
    fail "gap: a FIFO manifest is skipped without hanging (S6, got: $GAP3)"
fi
rm -f "${_GDIR:?}/manifest.conf"
mv "$_GDIR/manifest.conf.keep" "$_GDIR/manifest.conf"
check "gap: manifest delivery is find -type f into a root-owned temp (S6)" \
    sh -c 'grep -qF "dmg_found=\$(find \"\$dmg_dir\" -maxdepth 1 -type f -name manifest.conf" "$1" && ! grep -q "dmg_dir/manifest.conf" "$1"' _ "$MIG"
check "import: the read loop parses the staged copy, never the dump-dir manifest (S6)" \
    sh -c 'grep -qF "done <\"\$dm_manifest\"" "$1" && ! grep -qF "done <\"\$dm_dir/manifest.conf\"" "$1"' _ "$MIG"
check "import: manifest delivery is find -type f with a bounded cat (S6)" \
    sh -c 'grep -qF "dm_found=\$(find \"\$dm_dir\" -maxdepth 1 -type f -name manifest.conf" "$1" && grep -qF "timeout 5 cat \"\$dm_found\" >\"\$dm_manifest\"" "$1"' _ "$MIG"

# --- #322: find's stderr is kept — an unreadable dump dir never folds into
# "no manifest". Gap: skip-with-note (no gap claimed, the unreadable dir
# names itself on stderr — the caller-suppressed S6 pins above discard
# stderr, this one captures it). Import: refused by name. Root-hermetic:
# relies on the non-root suite user (same as the W5/W5i pins).
if [ "$(id -u)" != 0 ]; then
    _g322="$(work_new)"
    mkdir -p "$_g322/backups/ddev-migration-20260101-000000"
    printf 'OK|alpha|/roots/alpha|alpha.sql.gz\n' >"$_g322/backups/ddev-migration-20260101-000000/manifest.conf"
    chmod 000 "$_g322/backups/ddev-migration-20260101-000000"
    _g322_out=$(DDEV_MIG_BACKUP_ROOT="$_g322/backups" DDEV_MIG_DEV_HOME="$_g322/devhome" \
        timeout 10 sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' \
        _ "$MIG" "$_g322/roots" 2>&1) || true
    if printf '%s\n' "$_g322_out" | grep -qF 'cannot inspect' &&
        printf '%s\n' "$_g322_out" | grep -qF 'partial-export check skipped'; then
        pass "gap: unreadable dump dir notes itself instead of silent no-manifest (#322)"
    else
        fail "gap: unreadable dump dir must skip-with-note, not claim no-manifest (got: $_g322_out) (#322)"
    fi
    # UI_SILENT gate (review a B2): `opk status --short` must keep its
    # one-verdict-line contract — the note mutes under UI_SILENT=1 the
    # way the ui.sh printers do.
    _g322s_out=$(DDEV_MIG_BACKUP_ROOT="$_g322/backups" DDEV_MIG_DEV_HOME="$_g322/devhome" \
        UI_SILENT=1 timeout 10 sh -c '. "$1" && ddev_migrate_gap maxmustermann "$2"' \
        _ "$MIG" "$_g322/roots" 2>&1) || true
    if ! printf '%s\n' "$_g322s_out" | grep -qF 'partial-export check skipped'; then
        pass "gap: the skip-note is UI_SILENT-gated (status --short stays one line) (review a B2)"
    else
        fail "gap: the skip-note must mute under UI_SILENT=1 (review a B2, got: $_g322s_out)"
    fi
    chmod 755 "$_g322/backups/ddev-migration-20260101-000000"
    mkdir -p "$_g322/bin"
    printf '#!/bin/sh\necho 0\n' >"$_g322/bin/id"
    chmod +x "$_g322/bin/id"
    chmod 000 "$_g322/backups/ddev-migration-20260101-000000"
    _i322_out=$(PATH="$_g322/bin:$PATH" timeout 10 sh -c \
        '. "$1" && ddev_migrate_import "$2"' _ "$MIG" \
        "$_g322/backups/ddev-migration-20260101-000000" 2>&1) || true
    chmod 755 "$_g322/backups/ddev-migration-20260101-000000"
    if printf '%s\n' "$_i322_out" | grep -qF 'dump directory unreadable' &&
        printf '%s\n' "$_i322_out" | grep -qF 'refusing to import'; then
        pass "import: unreadable dump dir is refused by name, never 'no manifest' (#322)"
    else
        fail "import: unreadable dump dir must be refused distinctly (got: $_i322_out) (#322)"
    fi
else
    echo "  SKIP  #322 unreadable-dir pins need a non-root suite user (#322)"
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
_mig_gap_n="$(live_src "$INSTALL_CORE" | grep -c '_ddev_mig_gap_warn' || true)"
check "install.sh warns on skip branches when the registry outgrew the manifest (warn sites: $_mig_gap_n, need >=3)" \
    sh -c "grep -q '_ddev_mig_gap_warn' \"\$1\" && [ \"\$2\" -ge 3 ]" _ "$INSTALL_CORE" "$_mig_gap_n"
check "status.sh reports INCOMPLETE dumps vs the dev registry" \
    sh -c "grep -q 'INCOMPLETE — registry lists' \"\$1\" && grep -q 'ddev-migrate registry' \"\$1\"" _ "$STATUS_CORE"
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
printf '#!/bin/sh\necho real-ddev\n' >"$WORK/spaced home/.local/bin/ddev"
chmod +x "$WORK/spaced home/.local/bin/ddev"
printf '#!/bin/sh\n' >"$WORK/spaced/ddev"
# non-executable `ddev` on PATH: command -v must not find it
cat >"$WORK/getent" <<EOF
#!/bin/sh
[ "\$1" = passwd ] && { printf '%s\n' "spaced:x:\$(id -u):\$(id -g)::$WORK/spaced home:/bin/sh"; exit 0; }
exec $(command -v getent) "\$@"
EOF
chmod +x "$WORK/getent"
if [ -x /usr/local/bin/ddev ] || [ -x /usr/bin/ddev ]; then
    echo "  SKIP  spaced-home bin resolution (host has a system ddev — absolute-path candidates would win)"
else
    cat >"$WORK/binres.sh" <<'WRAP'
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
cat >"$WORK/sudo" <<'EOF'
#!/bin/sh
for _a in "$@"; do printf '%s\n' "$_a"; done
EOF
chmod +x "$WORK/sudo"
cat >"$WORK/runas.sh" <<'WRAP'
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

# --- 0.0.45d W5: import's failure paths report their real cause --------------------
# The old conflation printed "no dump directory with a manifest found"
# for every failure: a cat timeout / unreadable manifest masqueraded as
# the genuine no-manifest case, a mktemp failure returned 1 SILENTLY.
# Distinct messages now. The root guard is bypassed with an id shim —
# every path under test exits before the first sudo call.
_w5dir="$(work_new)"
mkdir -p "$_w5dir/bin" "$_w5dir/bin-mk" "$_w5dir/dump"
printf '#!/bin/sh\necho 0\n' >"$_w5dir/bin/id"
cp "$_w5dir/bin/id" "$_w5dir/bin-mk/id"
printf '#!/bin/sh\nexit 1\n' >"$_w5dir/bin-mk/mktemp"
chmod +x "$_w5dir/bin/id" "$_w5dir/bin-mk/id" "$_w5dir/bin-mk/mktemp"
_w5_import() {
    PATH="$_w5dir/$1:$PATH" sh -c '. "$1" && ddev_migrate_import "$2"' \
        _ "$MIG" "$_w5dir/dump" 2>&1 || true

}
printf 'OK|alpha|/roots/alpha|alpha.sql.gz\n' >"$_w5dir/dump/manifest.conf"
chmod 000 "$_w5dir/dump/manifest.conf"
_w5_out="$(_w5_import bin)"
case "$_w5_out" in
    *"manifest found but unreadable"*)
        pass "import: unreadable manifest reports its cause, not 'no manifest' (W5)"
        ;;
    *"no dump directory"*)
        fail "import: unreadable manifest must not claim 'no dump directory' (W5)"
        ;;
    *)
        fail "import: unreadable manifest must report the unreadable cause (W5, got: $_w5_out)"
        ;;
esac
rm -f "${_w5dir:?}/dump/manifest.conf"
_w5_out="$(_w5_import bin)"
case "$_w5_out" in
    *"no dump directory with a manifest found"*)
        pass "import: the genuine no-manifest case keeps its message (W5)"
        ;;
    *)
        fail "import: the genuine no-manifest case must keep its message (W5, got: $_w5_out)"
        ;;
esac
_w5_out="$(_w5_import bin-mk)"
case "$_w5_out" in
    *"cannot create a staging temp"*)
        pass "import: mktemp failure reports instead of exiting silently (W5)"
        ;;
    *)
        fail "import: mktemp failure must report its cause (W5, got: $_w5_out)"
        ;;
esac
rm -rf "${_w5dir:?}"

# --- #264's import twin: a symlinked dump operand is refused, never read through ------
# The finalized dump dir is agent-owned — a dump swapped for a symlink
# in the export->import gap must fail BEFORE the first sudo hop
# (import-db would pour an agent-chosen file's content into a project
# database). id shim + _ddev_migrate_bin override keep the drive
# hermetic (the run-export.sh override pattern); the gate fires before
# any ddev call, so no ddev is needed on the host.
_w5i="$(work_new)"
mkdir -p "$_w5i/bin" "$_w5i/dump"
printf '#!/bin/sh\necho 0\n' >"$_w5i/bin/id"
chmod +x "$_w5i/bin/id"
printf 'OK|alpha|/roots/alpha|alpha.sql.gz\n' >"$_w5i/dump/manifest.conf"
printf 'VICTIM-IMPORT-CONTENT\n' >"$_w5i/victim.conf"
ln -s "$_w5i/victim.conf" "$_w5i/dump/alpha.sql.gz"
_w5i_out=$(PATH="$_w5i/bin:$PATH" sh -c \
    '. "$1" && _ddev_migrate_bin() { echo /usr/bin/true; } && ddev_migrate_import "$2"' \
    _ "$MIG" "$_w5i/dump" 2>&1) || true
case "$_w5i_out" in
    *"REFUSED — dump operand is a symlink"*)
        pass "import: a symlinked dump operand is refused loudly (#264)"
        ;;
    *)
        fail "import: a symlinked dump operand must be refused (got: $_w5i_out) (#264)"
        ;;
esac
case "$_w5i_out" in
    *"failed: alpha"*)
        pass "import: the refused project lands in the failed list, rc degrades (#264)"
        ;;
    *)
        fail "import: the refused project must land in the failed list (got: $_w5i_out) (#264)"
        ;;
esac
# Seam-sanity leg, NOT gate evidence (#420 a A10): the drive's ddev is
# /usr/bin/true — nothing ever opens the link's target, with or without
# the gate. The drive's discriminators are the REFUSED and failed-list
# legs above.
check "import: stub sanity — the victim's content is untouched (#264)" \
    sh -c "test \"\$(cat \"\$1\")\" = VICTIM-IMPORT-CONTENT" _ "$_w5i/victim.conf"
rm -rf "${_w5i:?}"

# static: the import loop builds HOME via getent and rides conditional
# backend vars as single quoted arguments (0.0.43a F6/F12).
check "import resolves the agent HOME via getent (not /home/<user>)" \
    sh -c "grep -qF 'dm_oc_h=\$(getent passwd' \"\$1\"" _ "$MIG"
check "import passes HOME/XDG as single quoted arguments" \
    sh -c "grep -qF 'env \"HOME=\$dm_oc_h\" \"XDG_RUNTIME_DIR=/run/user/\$dm_oc_i\"' \"\$1\"" _ "$MIG"
check_fail "import no longer word-splits an env string" \
    sh -c "grep -q 'env \$dm_env' \"\$1\"" _ "$MIG"

# --- bin/ddev-migrate list: rc 0 means "listed fine" (#211 a F3) ------------------
# The list arm's bare `[ "$dm_found" = 0 ] && echo` tail made the arm
# exit 1 whenever dump directories EXISTED — success read as failure.
# Drive the real binary against a scratch backup root both ways.
F3ROOT=$(work_new)
mkdir -p "$F3ROOT/ddev-migration-20261020-1200"
printf 'db.sql\n' >"$F3ROOT/ddev-migration-20261020-1200/db.sql"
F3RC=0
F3OUT="$(DDEV_MIG_BACKUP_ROOT="$F3ROOT" "$BIN_MIG" list 2>&1)" || F3RC=$?
if [ "${F3RC:-0}" -eq 0 ] && printf '%s' "$F3OUT" | grep -q 'ddev-migration-20261020-1200'; then
    pass "list exits 0 with dump directories present (#211 a F3)"
else
    fail "list exits 0 with dump directories present (#211 a F3, rc ${F3RC:-0})"
fi
F3RC=0
F3OUT="$(DDEV_MIG_BACKUP_ROOT="$F3ROOT/empty" "$BIN_MIG" list 2>&1)" || F3RC=$?
if [ "$F3RC" -eq 0 ] && printf '%s' "$F3OUT" | grep -q 'no dump directories'; then
    pass "list exits 0 and reports none when empty (#211 a F3)"
else
    fail "list exits 0 and reports none when empty (#211 a F3, rc $F3RC)"
fi
rm -rf "$F3ROOT"

# --- Summary ------------------------------------------------------------------------

# Cleanup the fixture sandbox root. Unit-test policy (0.0.42e C1): suites
# touch only their scratch and /tmp,/var/tmp -- never real project trees.
rm -rf /var/tmp/opencode-ddev-mig-roots 2>/dev/null || true
suite_done "tests"
