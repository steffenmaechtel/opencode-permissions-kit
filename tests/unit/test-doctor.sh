#!/bin/sh
# Unit tests for doctor.sh (issue #313, stage 1) — no root, no kit
# install needed. Three layers:
#   1. pure functions extracted from doctor.sh (uid_map shape filter,
#      the uid classifier, the opk.json validator) run against
#      controlled inputs (fixture /proc tree, synthetic find streams,
#      fixture policy files)
#   2. end-to-end runs of the script with OPK_INSTALL_CONF +
#      OPK_DOCTOR_PROC_ROOT fixtures: verdict rows, fix hints and the
#      rc contract (0 healthy / 1 at-risk / 2 warnings only / 64 usage)
#   3. failure paths: missing kit, missing user, unreadable subtrees
#      (the scan must warn, not shrink silently)
# Run: sh tests/unit/test-doctor.sh
set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCTOR="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh"

failures=0
passed=0
pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:-}"' EXIT INT TERM

PROCFIX="$WORK/proc"
CONF="$WORK/install.conf"
PROJ="$WORK/proj"
mkdir -p "$PROCFIX" "$PROJ"
CURUID="$(id -u)"

# root exists everywhere and is never the test user: daemon uid 0 makes
# the scratch files (owned by the test user) at-risk unless a fixture
# range maps them — exactly the two verdicts the suite needs.
printf 'OPENCODE_USER=root\nVERSION=9.9.9\n' >"$CONF"

# mkmap <pid> <uid_map-row>...  — fixture process with a uid_map
mkmap() {
    _mk_pid="$1"
    shift
    mkdir -p "$PROCFIX/$_mk_pid"
    printf '%s\n' "$@" >"$PROCFIX/$_mk_pid/uid_map"
}

# run_doctor <project-root> [args...] — output on stdout, rc in $?
run_doctor() {
    OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" NO_COLOR=1 \
        sh "$DOCTOR" "$@" 2>&1
}

# rc_doctor <desc> <expected-rc> <args...> — runs doctor, asserts rc,
# keeps output in _rd_out for the grep_last_out pins that follow
rc_doctor() {
    _rd_desc="$1" _rd_want="$2"
    shift 2
    _rd_rc=0
    _rd_out="$(run_doctor "$@")" || _rd_rc=$?
    if [ "$_rd_rc" = "$_rd_want" ]; then
        pass "$_rd_desc (rc $_rd_want)"
    else
        fail "$_rd_desc (rc $_rd_want, got $_rd_rc)"
        echo "        output: $_rd_out"
    fi
}

# grep_last_out <desc> <grep-args...> — asserts the last _rd_out matches
grep_last_out() {
    _gd_desc="$1"
    shift
    if printf '%s' "$_rd_out" | "$@" >/dev/null; then
        pass "$_gd_desc"
    else
        fail "$_gd_desc"
        echo "        output: $_rd_out"
    fi
}

extract_fn() {
    sed -n "/^$1()/,/^}/p" "$DOCTOR"
}

echo "=== doctor.sh unit tests ==="

# --- 1. doctor_userns_ranges: the live-map shape filter (#313) --------------------
RANGES_FN="$WORK/userns-fn.sh"
extract_fn doctor_userns_ranges >"$RANGES_FN"
[ -s "$RANGES_FN" ] &&
    pass "doctor_userns_ranges extractable" ||
    fail "doctor_userns_ranges extractable"

usrng() { # <daemon-uid> -> sorted range lines from the fixture tree
    (
        # the extracted block is builtins only — this subshell adds
        # nothing to PATH on purpose (the test-sandbox rule in
        # agent/conventions.md: extracted code runs on a controlled PATH)
        . "$RANGES_FN"
        doctor_userns_ranges "$PROCFIX" "$1" 2>/dev/null | sort -u
    )
}

# the fixture /proc tree:
#   10  the daemon userns (zero row -> daemon, plus a subuid row)
#   11  the init namespace (full map — must not count as a daemon userns)
#   12  a FOREIGN user's namespace (zero row -> 1234, not the daemon)
#   13  garbage (not a map at all)
#   14  valid rows, then a malformed row (the whole file must be voided)
#   15  valid row with an extra column (voided)
#   16  a second daemon namespace (union across namespaces)
mkmap 10 "0 0 1" "1 200000 65536"
mkmap 11 "0 0 4294967295"
mkmap 12 "0 1234 1" "1 5000 10"
mkmap 13 "not a map"
mkmap 14 "0 0 1" "999999 5" "x 9 9"
mkmap 15 "0 0 1" "1 777777 1 9"
mkmap 16 "0 0 1" "1 300000 1"

_out="$(usrng 0)"
_want="$(printf '0:1\n200000:65536\n300000:1')"
[ "$_out" = "$_want" ] &&
    pass "shape filter: daemon rows kept, everything else dropped" ||
    {
        fail "shape filter: daemon rows kept, everything else dropped"
        echo "        got: $(printf '%s' "$_out" | tr '\n' ' ') (want: $_want)"
    }
# name the individual causes against the same run (a failure names itself)
printf '%s\n' "$_out" | grep -qx '0:1' &&
    pass "daemon zero row collected" ||
    fail "daemon zero row collected"
printf '%s\n' "$_out" | grep -qx '200000:65536' &&
    pass "subuid range collected" ||
    fail "subuid range collected"
if printf '%s\n' "$_out" | grep -q 4294967295; then
    fail "full init map excluded"
else
    pass "full init map excluded"
fi
if printf '%s\n' "$_out" | grep -qE '^(1234|5000):'; then
    fail "foreign-user userns excluded"
else
    pass "foreign-user userns excluded"
fi
if printf '%s\n' "$_out" | grep -qE '^(999999|777777):'; then
    fail "voided files leak no partial rows (buffer discipline)"
else
    pass "voided files leak no partial rows (buffer discipline)"
fi

# --- 2. doctor_classify / doctor_examples: uid classification ---------------------
CLS_FN="$WORK/cls-fn.sh"
extract_fn doctor_classify >"$CLS_FN"
extract_fn doctor_examples >>"$CLS_FN"
[ -s "$CLS_FN" ] &&
    pass "doctor_classify/doctor_examples extractable" ||
    fail "doctor_classify/doctor_examples extractable"

# controlled PATH with the block's one external (awk) — the test-sandbox
# rule in agent/conventions.md (extracted code, controlled PATH)
SCRATCHBIN="$WORK/bin"
mkdir -p "$SCRATCHBIN"
ln -s "$(command -v awk)" "$SCRATCHBIN/awk"

# synthetic uid stream (one numeric line per find entry): daemon uid,
# range boundaries, unmapped uids (#344 a S1: uid-only, newline-safe)
printf '1000\n1001\n165536\n231071\n231072\n0\n1000\n' >"$WORK/uids"
_cls_run() {
    (
        PATH="$SCRATCHBIN"
        export PATH
        . "$CLS_FN"
        doctor_classify "$1" "$2" "$3" 2>/dev/null
    )
}
_ex_run() {
    (
        PATH="$SCRATCHBIN"
        export PATH
        . "$CLS_FN"
        doctor_examples "$1" "$2" "$3" 2>/dev/null
    )
}
_out="$(_cls_run "$WORK/uids" 1001 "1001 1 165536 65536" | grep '^SUM' | cut -f2,3)"
[ "$_out" = "$(printf '3\t4')" ] &&
    pass "classify counts safe/risk (daemon + range boundaries)" ||
    {
        fail "classify counts safe/risk (daemon + range boundaries)"
        echo "        SUM got: $_out (want 3/4)"
    }
# boundary discrimination: start and last of a range are safe, +1 is not
# (daemon 99999 is absent from the stream — only the range can match)
_out="$(_cls_run "$WORK/uids" 99999 "165536 65536" | grep '^SUM' | cut -f2,3)"
[ "$_out" = "$(printf '2\t5')" ] &&
    pass "range boundaries discriminate (165536..231071 in, 231072 out)" ||
    {
        fail "range boundaries discriminate (165536..231071 in, 231072 out)"
        echo "        SUM got: $_out (want 2/5)"
    }
# unmapped uids tallied per uid (daemon 1001 is safe; 231072 falls out)
_out="$(_cls_run "$WORK/uids" 1001 "165536 65536" | grep '^UID' | sort | tr '\n' ' ')"
[ "$_out" = "$(printf 'UID\t0\t1 UID\t1000\t2 UID\t231072\t1 ')" ] &&
    pass "unmapped uids tallied per uid" ||
    {
        fail "unmapped uids tallied per uid"
        echo "        got: $_out"
    }
# empty ranges string: only the daemon uid is safe (the fallback floor)
_out="$(_cls_run "$WORK/uids" 1001 "" | grep '^SUM' | cut -f2,3)"
[ "$_out" = "$(printf '1\t6')" ] &&
    pass "empty range list -> daemon-uid-only matching" ||
    {
        fail "empty range list -> daemon-uid-only matching"
        echo "        SUM got: $_out (want 1/6)"
    }
# examples pass (TSV stream): capped at three, display-only truncation
# at the first whitespace run (#344 a S1/S2 — the documented contract)
printf '1000\tweb assets/x\n1000\tsecond\n165536\tsafe\n0\tthird\n1000\tfourth\n' \
    >"$WORK/extsv"
_out="$(_ex_run "$WORK/extsv" 1001 "165536 65536" | tr '\n' ' ')"
[ "$_out" = "$(printf 'web second third ')" ] &&
    pass "examples: three max, truncated at whitespace (documented)" ||
    {
        fail "examples: three max, truncated at whitespace (documented)"
        echo "        got: $_out"
    }

# --- 3. doctor_load_policy: opk.json validation (strict JSON) ---------------------
POL_FN="$WORK/pol-fn.sh"
extract_fn doctor_load_policy >"$POL_FN"
[ -s "$POL_FN" ] &&
    pass "doctor_load_policy extractable" ||
    fail "doctor_load_policy extractable"
ln -s "$(command -v python3)" "$SCRATCHBIN/python3"

pol() { # <json-string> -> TSV on stdout; stderr lands in $WORK/pol.err
    printf '%s\n' "$1" >"$WORK/opk.json"
    (
        PATH="$SCRATCHBIN"
        export PATH
        . "$POL_FN"
        doctor_load_policy "$WORK" 2>"$WORK/pol.err"
    )
}

_out="$(pol '{"version":1,"containerTrees":[{"path":"web/assets","note":"build outputs"}]}')"
[ "$_out" = "$(printf 'web/assets\tbuild outputs')" ] &&
    pass "object entries parse (path + note)" ||
    fail "object entries parse (path + note) (got: $_out)"
_out="$(pol '{"containerTrees":["pkgs/x"]}')"
[ "$_out" = "$(printf 'pkgs/x\t')" ] &&
    pass "bare string entries parse (note optional, version defaults)" ||
    fail "bare string entries parse (note optional, version defaults) (got: $_out)"
_out="$(pol '{"containerTrees":[{"path":"a","note":"x\ty\tz"}]}')"
[ "$_out" = "$(printf 'a\tx y z')" ] &&
    pass "tabs in notes collapse to spaces (TSV round-trip)" ||
    fail "tabs in notes collapse to spaces (TSV round-trip) (got: $_out)"
_out="$(pol '{"version":1,"futureKey":true,"containerTrees":[{"path":"a","role":"new"}]}')"
[ "$_out" = "$(printf 'a\t')" ] &&
    pass "unknown keys ignored (forward compatibility)" ||
    fail "unknown keys ignored (forward compatibility) (got: $_out)"

# every rejection branch: non-zero rc AND a stderr message
for _bad in \
    '{bad json' \
    '{"version":2,"containerTrees":[]}' \
    '{"version":true,"containerTrees":[]}' \
    '{"version":1.0,"containerTrees":[]}' \
    '[]' \
    '{"containerTrees":{"path":"a"}}' \
    '{"containerTrees":[42]}' \
    '{"containerTrees":[{"note":"no path"}]}' \
    '{"containerTrees":[{"path":42}]}' \
    '{"containerTrees":[{"path":""}]}' \
    '{"containerTrees":["."]}' \
    '{"containerTrees":["a//b"]}' \
    '{"containerTrees":[{"path":"/etc/passwd"}]}' \
    '{"containerTrees":[{"path":"a/../../etc"}]}' \
    '{"containerTrees":[{"path":"a\u0001b"}]}' \
    '{"containerTrees":[{"path":"pkgs/*/Public"}]}' \
    '{"containerTrees":[{"path":"a\\b"}]}' \
    '{"containerTrees":[{"path":"a;whoami"}]}' \
    '{"containerTrees":[{"path":"a$b"}]}' \
    '{"containerTrees":[{"path":"a`id`b"}]}' \
    '{"containerTrees":[{"path":"a\"b"}]}' \
    '{"containerTrees":[{"path":"a\u0027b"}]}' \
    '{"containerTrees":[{"path":"a","note":7}]}' \
    '{"containerTrees":[{"path":"a","note":"x\u001by"}]}'; do
    _pol_rc=0
    pol "$_bad" >/dev/null || _pol_rc=$?
    _pol_msg="$(cat "$WORK/pol.err" 2>/dev/null || true)"
    if [ "$_pol_rc" -ne 0 ] && [ -n "$_pol_msg" ]; then
        pass "rejects: $_bad"
    else
        fail "rejects: $_bad (rc $_pol_rc, stderr '$_pol_msg')"
    fi
done

# --- 4. end-to-end: verdicts, fix hints, rc contract ------------------------------
mkproj() { # fresh project with one tree of two files
    rm -rf "$PROJ"
    mkdir -p "$PROJ/tree"
    echo x >"$PROJ/tree/one"
    echo y >"$PROJ/tree/two"
}
policy() { printf '%s\n' "$1" >"$PROJ/opk.json"; }

# healthy: the fixture namespace maps the test user's uid
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
policy '{"version":1,"containerTrees":[{"path":"tree","note":"build outputs"}]}'
rc_doctor "healthy tree -> rc 0" 0 "$PROJ"
grep_last_out "healthy verdict row" grep -qF "tree -- 3 entries mapped-safe"
grep_last_out "summary says all mapped-safe" grep -qF "all declared container trees mapped-safe"
grep_last_out "policy note displayed" grep -qF "declared: build outputs"
if printf '%s' "$_rd_out" | grep -q "at-risk"; then
    fail "healthy run mentions no at-risk rows"
else
    pass "healthy run mentions no at-risk rows"
fi

# at-risk: no range covers the test user (only the daemon-uid row maps)
rm -rf "$PROCFIX"
mkmap 42 "0 0 1"
mkproj
policy '{"containerTrees":["tree"]}'
rc_doctor "at-risk tree -> rc 1" 1 "$PROJ"
grep_last_out "at-risk verdict row" grep -qF "entries at-risk (unmapped owners)"
grep_last_out "at-risk owner tallied" grep -qF "uid $CURUID (3)"
grep_last_out "fix hint names handover" grep -qF "fix: sudo opk handover opencode"
grep_last_out "examples listed" grep -qF "examples:"

# multi-tree project: every declared tree gets its own verdict row
mkproj
mkdir -p "$PROJ/second"
echo z >"$PROJ/second/file"
policy '{"containerTrees":["tree","second"]}'
rc_doctor "multi-tree project with findings -> rc 1" 1 "$PROJ"
grep_last_out "first tree reported" grep -qF "tree -- 3 of 3 entries at-risk"
grep_last_out "second tree reported" grep -qF "second -- 2 of 2 entries at-risk"

# fallback: no namespace at all -> unverified warn + daemon-uid floor
rm -rf "$PROCFIX"
mkdir -p "$PROCFIX"
mkproj
policy '{"containerTrees":["tree"]}'
rc_doctor "no namespace found -> rc 1 with at-risk files" 1 "$PROJ"
grep_last_out "range-unverified warn shown" grep -qF "unverified -- no user namespace"
grep_last_out "unverified consequence told" grep -qF "may classify at-risk"

# warnings only: declared but missing tree -> rc 2
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
policy '{"containerTrees":["not/cloned/yet"]}'
rc_doctor "missing declared tree -> rc 2" 2 "$PROJ"
grep_last_out "missing-tree warn row" grep -qF "declared but missing"

# symlinked tree root: skipped with a warn (declare the real tree)
mkproj
mkdir -p "$PROJ/real"
ln -s real "$PROJ/link"
policy '{"containerTrees":["link"]}'
rc_doctor "symlink tree root -> rc 2 (skipped)" 2 "$PROJ"
grep_last_out "symlink skip warn" grep -qF "a symlink, skipped"

# path with a space works end-to-end (TSV round-trip, quoted find)
mkproj
mkdir -p "$PROJ/web assets"
echo s >"$PROJ/web assets/app.css"
policy '{"containerTrees":["web assets"]}'
rc_doctor "tree path with a space -> rc 0" 0 "$PROJ"
grep_last_out "space-tree verdict" grep -qF "web assets -- 2 entries mapped-safe"

# empty declaration: valid, nothing to flag
mkproj
policy '{"version":1,"containerTrees":[]}'
rc_doctor "empty containerTrees -> rc 0" 0 "$PROJ"

# no opk.json at all
mkproj
rm -f "${PROJ:?}/opk.json"
rc_doctor "no opk.json -> rc 2" 2 "$PROJ"
grep_last_out "no-policy warn" grep -qF "no opk.json found"

# invalid opk.json end-to-end (python stderr passes through, rc 1)
policy '{"containerTrees":[]}extra'
rc_doctor "invalid JSON -> rc 1" 1 "$PROJ"
grep_last_out "reject message shown" grep -qF "not valid JSON"
grep_last_out "policy rejected error row" grep -qF "policy file was rejected"

# usage errors -> 64
rc_doctor "two args -> rc 64" 64 "$PROJ" "$PROJ"
rc_doctor "flag arg -> rc 64" 64 --short
rc_doctor "nonexistent dir -> rc 64" 64 "$WORK/no-such-project"

# --- 5. kit-state failure paths ----------------------------------------------------_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$WORK/nope.conf" NO_COLOR=1 sh "$DOCTOR" "$PROJ" 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "not found -- is the kit installed?" &&
    pass "missing install.conf -> rc 1 with hint" ||
    fail "missing install.conf -> rc 1 with hint (rc $_rd_rc)"
printf 'VERSION=9.9.9\n' >"$WORK/no-user.conf"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$WORK/no-user.conf" NO_COLOR=1 sh "$DOCTOR" "$PROJ" 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "has no OPENCODE_USER" &&
    pass "install.conf without OPENCODE_USER -> rc 1" ||
    fail "install.conf without OPENCODE_USER -> rc 1 (rc $_rd_rc)"
printf 'OPENCODE_USER=no-such-kit-user\n' >"$WORK/bad-user.conf"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$WORK/bad-user.conf" NO_COLOR=1 sh "$DOCTOR" "$PROJ" 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "does not exist" &&
    pass "unknown daemon user -> rc 1" ||
    fail "unknown daemon user -> rc 1 (rc $_rd_rc)"

# unreadable subtree: the scan must warn, never shrink silently (L1)
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
policy '{"containerTrees":["tree"]}'
mkdir -p "$PROJ/tree/secret"
echo h >"$PROJ/tree/secret/file"
chmod 000 "$PROJ/tree/secret"
rc_doctor "unreadable subtree -> rc 2 (warn, not silent)" 2 "$PROJ"
grep_last_out "incomplete-scan warn shown" grep -qF "scan incomplete"
chmod 755 "$PROJ/tree/secret"

# newline in a FILENAME must not corrupt the verdict (#344 a S1): the
# count stream is uid-only, so a healthy tree stays healthy
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
_nl_name="$(printf 'weird\nname')"
echo n >"$PROJ/tree/$_nl_name"
policy '{"containerTrees":["tree"]}'
rc_doctor "newline filename -> counts intact, rc 0" 0 "$PROJ"
grep_last_out "newline file counted once" grep -qF "tree -- 4 entries mapped-safe"
if printf '%s' "$_rd_out" | grep -q "at-risk"; then
    fail "newline filename invents no at-risk rows"
else
    pass "newline filename invents no at-risk rows"
fi

# daemon namespace mapping count>1 at the daemon uid: no duplicate floor
# row in the display (#344 a C5)
rm -rf "$PROCFIX"
mkmap 42 "0 0 65536"
mkproj
policy '{"containerTrees":["tree"]}'
rc_doctor "count>1 zero row covers the tree -> rc 0" 0 "$PROJ"
grep_last_out "daemon uid listed once" grep -qF "0-65535 -- live uid_map"
if printf '%s' "$_rd_out" | grep -qF "0, 0-"; then
    fail "no duplicate floor row in the display"
else
    pass "no duplicate floor row in the display"
fi

# source-shape pins (comment-strip rider per conventions.md, "Source-
# counting pins"): the C1 trap and the S5 belt are defense-in-depth
# shapes whose failure paths a unit fixture cannot reach cheaply (the
# python gate fires first; a deterministic mid-scan SIGINT fixture is
# the pin-cost-budget class) — pinned stripped so commented-out
# constructs cannot satisfy them
sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF "trap '_doctor_cleanup; exit 1' INT TERM" &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF 'trap _doctor_cleanup EXIT' &&
    pass "signal handlers exit (#344 a C1 house shape, stripped source)" ||
    fail "signal handlers exit (#344 a C1 house shape, stripped source)"
sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '*/./*' &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '*//*' &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '.' &&
    pass "belt case covers dot/dotdot/empty components (#344 a S5, stripped source)" ||
    fail "belt case covers dot/dotdot/empty components (#344 a S5, stripped source)"

# --- summary gate -----------------------------------------------------------------
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}all doctor tests passed ($passed).${NC}"
exit 0
