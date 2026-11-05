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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCTOR="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

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
# setsid + </dev/null on purpose: doctor must never hang on a controlling
# tty (an accidental prompt EOFs to its default instead), and fix-mode
# tests below drive prompts through stdin (run_doctor_ans). RD_OPK wires
# the OPK_DOCTOR_OPK test seam — every fix-mode call MUST set it (the
# default would resolve the REAL dispatcher next to doctor.sh).
run_doctor() {
    OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="${RD_OPK:-}" \
        NO_COLOR=1 setsid sh "$DOCTOR" "$@" </dev/null 2>&1
}

# run_doctor_ans <answers-file> [args...] — like run_doctor, stdin fed
# from a prepared answer file (one line per [y/N] prompt; no tty exists
# under setsid, so ui_confirm falls back to stdin)
run_doctor_ans() {
    _ra_ans="$1"
    shift
    OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="${RD_OPK:-}" \
        NO_COLOR=1 setsid sh "$DOCTOR" "$@" <"$_ra_ans" 2>&1
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

# rc_doctor_ans <desc> <expected-rc> <answers-file> <args...> — the
# rc_doctor shape for prompt-driven runs
rc_doctor_ans() {
    _rd_desc="$1" _rd_want="$2" _ra_file="$3"
    shift 3
    _rd_rc=0
    _rd_out="$(run_doctor_ans "$_ra_file" "$@")" || _rd_rc=$?
    if [ "$_rd_rc" = "$_rd_want" ]; then
        pass "$_rd_desc (rc $_rd_want)"
    else
        fail "$_rd_desc (rc $_rd_want, got $_rd_rc)"
        echo "        output: $_rd_out"
    fi
}

# run_doctor_in <dir> [args...] — run_doctor, but invoked from inside
# <dir>: walk-up discovery (#353) starts at the INVOCATION dir, so the
# cd must happen before exec (a subshell keeps the suite's own cwd)
run_doctor_in() {
    _rin_dir="$1"
    shift
    (
        cd "$_rin_dir" || exit 99
        OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="${RD_OPK:-}" \
            NO_COLOR=1 setsid sh "$DOCTOR" "$@" </dev/null 2>&1
    )
}

# rc_doctor_in <desc> <expected-rc> <dir> [args...] — rc_doctor from a dir
rc_doctor_in() {
    _rdi_desc="$1" _rdi_want="$2" _rdi_dir="$3"
    shift 3
    _rd_rc=0
    _rd_out="$(run_doctor_in "$_rdi_dir" "$@")" || _rd_rc=$?
    if [ "$_rd_rc" = "$_rdi_want" ]; then
        pass "$_rdi_desc (rc $_rdi_want)"
    else
        fail "$_rdi_desc (rc $_rdi_want, got $_rd_rc)"
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
grep_last_out "fix hint names the guided remedy" grep -qF "fix: opk doctor fix"
grep_last_out "result row names the guided remedy" grep -qF "fix with 'opk doctor fix'"
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
grep_last_out "no-policy row suggests detect" grep -qF "or run 'opk doctor detect'"

# --- 4b. walk-up opk.json discovery (#353 / #313 phase 4) ---------------------------
# Without a positional (a plain '.' counts as none) the root is
# discovered upward from the invocation dir, nearest opk.json wins,
# and the used root is REPORTED. An explicit positional stays strict.
# Environment assumption (marked, L4): the no-hit pins walk through the
# mktemp ancestor chain and assert no opk.json lives there — the suite
# scratch sits under /tmp, and an opk.json at /tmp or / would flip them.
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
mkdir -p "$PROJ/sub/deep"
policy '{"containerTrees":["tree"]}'
rc_doctor_in "walk-up from deep inside -> rc 0" 0 "$PROJ/sub/deep"
grep_last_out "discovered root named in header" grep -qF "project root   $PROJ"
grep_last_out "root via row names the start dir" \
    grep -qF "root via       walk-up from $PROJ/sub/deep (nearest opk.json)"
grep_last_out "trees resolve against the discovered root" \
    grep -qF "tree -- 3 entries mapped-safe"

# invocation AT the root: found at depth 0 -- no discovery row (v1
# output unchanged for the workspace-root workflow, #313's primary UX)
rc_doctor_in "invocation at the root -> rc 0" 0 "$PROJ"
if printf '%s' "$_rd_out" | grep -q "root via"; then
    fail "no root-via row when the invocation dir IS the root"
else
    pass "no root-via row when the invocation dir IS the root"
fi

# nearest wins: a nested opk.json shadows the parent's (like nested
# git repos) -- the discrimination pin (delete the walker's stop at
# first hit and the parent's 'tree' declaration reappears in the rows).
# The NESTED policy declares 'deep', the parent's 'tree': from deep/
# the verdict must answer the nested one only.
printf '{"containerTrees":["deep"]}\n' >"$PROJ/sub/opk.json"
rc_doctor_in "nearest opk.json wins -> rc 0" 0 "$PROJ/sub/deep"
grep_last_out "nested root named in header" grep -qF "project root   $PROJ/sub"
grep_last_out "nested policy governs the verdict" grep -qF "deep -- 1 entries mapped-safe"
if printf '%s' "$_rd_out" | grep -qF "tree --"; then
    fail "parent policy is not read when a nearer opk.json exists"
else
    pass "parent policy is not read when a nearer opk.json exists"
fi

# no hit anywhere: the root stays the invocation dir (v1 strict shape)
# and the warning says what was searched -- 'strict-cwd' would be a lie.
# Own scratch OUTSIDE the suite's $WORK on purpose: section 3's pol()
# helper leaves a stale $WORK/opk.json behind, and this pin asserts a
# chain with NO opk.json at all (env assumption: none at /tmp or /)
rm -f "${PROJ:?}/sub/opk.json"
WALKNONE="$(mktemp -d)"
mkdir -p "$WALKNONE/inner"
rc_doctor_in "no hit anywhere -> rc 2" 2 "$WALKNONE/inner"
grep_last_out "root stays the invocation dir" grep -qF "project root   $WALKNONE/inner"
grep_last_out "warning names the searched scope" \
    grep -qF "no opk.json found in $WALKNONE/inner (searched upward to /) -- nothing to check"
rm -rf "${WALKNONE:?}"

# explicit positional stays authoritative: no discovery, no scope note
policy '{"containerTrees":["tree"]}'
rc_doctor "explicit root without policy: v1 warn, rc 2" 2 "$PROJ/sub"
grep_last_out "plain v1 warn text" grep -qF "no opk.json found in $PROJ/sub -- nothing to check"
if printf '%s' "$_rd_out" | grep -qF "searched upward"; then
    fail "explicit root claims a search it never ran"
else
    pass "explicit root claims no search"
fi

# a plain '.' counts as no positional (walk-up applies to it)
rc_doctor_in "plain '.' walks up -> rc 0" 0 "$PROJ/sub/deep" .
grep_last_out "dot invocation discovers the root" grep -qF "root via       walk-up from $PROJ/sub/deep"

# the spelling contract (#357 a A2): './' shares the default arm;
# './.' does NOT -- it is an explicit root and gets strict v1 behavior.
# Pinned so the split is contract, not accident
rc_doctor_in "'./' walks up like the bare dot -> rc 0" 0 "$PROJ/sub/deep" ./
grep_last_out "slash-dot invocation discovers the root" grep -qF "root via       walk-up from $PROJ/sub/deep"
rc_doctor_in "'./.' is an explicit root: strict, rc 2" 2 "$PROJ/sub/deep" ./.
grep_last_out "dot-dot-slash keeps the plain v1 warn" \
    grep -qF "no opk.json found in $PROJ/sub/deep -- nothing to check"

# realpath absent (#357 a A1, the fallback arm's class): the fallback
# re-feeds the raw arg -- the cd+pwd normalization must turn "." into
# the absolute invocation dir so the walk still finds the project root.
# A failing realpath stub shadows the real binary via PATH; timeout is
# the discriminator (pre-fix this HUNG: the walker looped on the
# slash-less input)
A1BIN="$WORK/a1-bin"
mkdir -p "$A1BIN"
for _a1t in dirname sed tail id mktemp awk sort find python3 grep wc; do
    ln -s "$(command -v "$_a1t")" "$A1BIN/$_a1t"
done
printf '#!/bin/sh\nexit 1\n' >"$A1BIN/realpath"
chmod +x "$A1BIN/realpath"
_rd_rc=0
_rd_out="$(
    cd "$PROJ/sub/deep" &&
        PATH="$A1BIN:$PATH" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
            OPK_DOCTOR_OPK="" NO_COLOR=1 timeout 30 sh "$DOCTOR" </dev/null 2>&1
)" || _rd_rc=$?
[ "$_rd_rc" = 0 ] &&
    pass "realpath absent: cd+pwd normalizes, walk-up still finds the root (A1)" ||
    {
        fail "realpath absent: cd+pwd normalizes, walk-up still finds the root (A1, rc $_rd_rc)"
        echo "        output: $_rd_out"
    }
printf '%s' "$_rd_out" | grep -qF "root via       walk-up from $PROJ/sub/deep" &&
    pass "A1 arm: header still reports the discovered root" ||
    fail "A1 arm: header still reports the discovered root"
rm -rf "${A1BIN:?}"

# static order pin (stripped source, the B1 precedent): the walk-up
# must sit BEFORE the detect gates -- a discovered root of '/' must hit
# the detect refusal, not slip past a gate that ran on the start dir
_wu_block=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -nF 'case "$DOCTOR_ROOT_ARG" in' | head -1 | cut -d: -f1)
_wu_gate=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -nF "refusing to walk the whole filesystem" | head -1 | cut -d: -f1)
if [ -n "$_wu_block" ] && [ -n "$_wu_gate" ] && [ "$_wu_block" -lt "$_wu_gate" ]; then
    pass "walk-up resolves before the detect '/' gate (static order)"
else
    fail "walk-up resolves before the detect '/' gate (static order, walk=$_wu_block gate=$_wu_gate)"
fi

# missing leaf lib: behavioral pin not fixture-able cheaply -- the
# checkout-first resolution falls back to the DEPLOYED lib, which
# exists on every kit-managed host (the same class as the unpinned
# ui.sh hard-fail; accepted residual, pin-cost budget). Structural pin
# instead: the PS_LIB block must sit AFTER the ui.sh sourcing -- the
# error path needs ui_error, which only exists once ui.sh loaded
_nl_src=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR")
_nl_uilib=$(printf '%s\n' "$_nl_src" | grep -nF 'UI_LIB=' | head -1 | cut -d: -f1)
_nl_pslib=$(printf '%s\n' "$_nl_src" | grep -nF 'PS_LIB=' | head -1 | cut -d: -f1)
if [ -n "$_nl_uilib" ] && [ -n "$_nl_pslib" ] && [ "$_nl_uilib" -lt "$_nl_pslib" ]; then
    pass "path-sane sourcing sits after ui.sh (its error row needs ui_error)"
else
    fail "path-sane sourcing sits after ui.sh (ui=$_nl_uilib ps=$_nl_pslib)"
fi

# invalid opk.json end-to-end (python stderr passes through, rc 1)
policy '{"containerTrees":[]}extra'
rc_doctor "invalid JSON -> rc 1" 1 "$PROJ"
grep_last_out "reject message shown" grep -qF "not valid JSON"
grep_last_out "policy rejected error row" grep -qF "policy file was rejected"

# usage errors -> 64
rc_doctor "two args -> rc 64" 64 "$PROJ" "$PROJ"
rc_doctor "flag arg -> rc 64" 64 --short
rc_doctor "nonexistent dir -> rc 64" 64 "$WORK/no-such-project"

# --- 4c. multi-project marker scan (#354 / #313 phase 5) -----------------------------
# 'doctor all': opk.json markers DISCOVER the projects (find -maxdepth 3
# below a scan root), one FRESH doctor child per project (each prints its
# own section header -- the count is the re-entrance discriminator), and
# the aggregate rc is worst-of (alert 1 > warning 2 > green 0; nothing
# scanned = 2). Every no-positional arm wires the OPK_DOCTOR_SCAN_ROOTS
# seam: no pin ever scans the real /var/www/vhosts or projects.conf
# (sandbox policy + determinism). The chmod-000 arms assume a non-root
# suite user (CI), the same sensitivity the §4 unreadable-subtree pins
# carry.
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
ALLSCAN="$WORK/allscan"
mkdir -p "$ALLSCAN/org/good/tree" "$ALLSCAN/org/broke" "$ALLSCAN/org/warn" \
    "$ALLSCAN/toodeep/a/b"
echo g >"$ALLSCAN/org/good/tree/file"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLSCAN/org/good/opk.json"
printf '%s\n' '{ broken json' >"$ALLSCAN/org/broke/opk.json"
printf '%s\n' '{"containerTrees":["not/cloned/yet"]}' >"$ALLSCAN/org/warn/opk.json"
# depth 4 below the scan root: NOT a project for the marker scan
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLSCAN/toodeep/a/b/opk.json"
ALLROOTS="$WORK/all-roots.txt"
printf '%s\n' "$ALLSCAN" >"$ALLROOTS"

# run_doctor_roots <roots-file> [args...] / rc_doctor_roots -- the
# run_doctor/rc_doctor shapes plus the scan-roots seam (always set here;
# set-but-empty would fall back to the REAL default roots, which no pin
# may touch)
run_doctor_roots() {
    _rrr_roots="$1"
    shift
    OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="${RD_OPK:-}" \
        OPK_DOCTOR_SCAN_ROOTS="$_rrr_roots" NO_COLOR=1 setsid sh "$DOCTOR" "$@" </dev/null 2>&1
}
rc_doctor_roots() {
    _rrd_desc="$1" _rrd_want="$2" _rrd_roots="$3"
    shift 3
    _rd_rc=0
    _rd_out="$(run_doctor_roots "$_rrd_roots" "$@")" || _rd_rc=$?
    if [ "$_rd_rc" = "$_rrd_want" ]; then
        pass "$_rrd_desc (rc $_rrd_want)"
    else
        fail "$_rrd_desc (rc $_rrd_want, got $_rd_rc)"
        echo "        output: $_rd_out"
    fi
}

# mixed fleet via the seam: green + error + warning -> worst-of rc 1
rc_doctor_roots "all: mixed fleet -> rc 1" 1 "$ALLROOTS" all
grep_last_out "project row names the green root" grep -qF "project        $ALLSCAN/org/good"
grep_last_out "child verdict row from the green project" grep -qF "tree -- 2 entries mapped-safe"
grep_last_out "broken policy reported by its own child" grep -qF "policy file was rejected"
grep_last_out "summary projects row" grep -qF "projects       3 scanned under 1 scan root(s)"
grep_last_out "summary findings row" grep -qF "findings       1 project(s) with at-risk findings"
grep_last_out "summary warnings row" grep -qF "warnings    1 project(s) warnings only"
grep_last_out "summary healthy row" grep -qF "healthy        1 project(s) all green"
if printf '%s' "$_rd_out" | grep -q toodeep; then
    fail "a marker 4 levels deep is no project"
else
    pass "a marker 4 levels deep is no project"
fi
_n_child="$(printf '%s' "$_rd_out" | grep -c 'Doctor -- container-tree ownership')"
if [ "$_n_child" = 3 ]; then
    pass "one fresh doctor section per project (3 children)"
else
    fail "one fresh doctor section per project (got $_n_child)"
fi

# warnings-only fleet (positional arm): no alert -> rc 2
ALLWARN="$WORK/allwarn"
mkdir -p "$ALLWARN/proj"
printf '%s\n' '{"containerTrees":["not/cloned/yet"]}' >"$ALLWARN/proj/opk.json"
rc_doctor "all: warnings-only fleet -> rc 2" 2 all "$ALLWARN"
grep_last_out "warnings row present" grep -qF "warnings    1 project(s) warnings only"
if printf '%s' "$_rd_out" | grep -qF "findings       1"; then
    fail "no findings row in a warnings-only fleet"
else
    pass "no findings row in a warnings-only fleet"
fi

# all-green fleet (positional): rc 0, and the positional scans EXACTLY
# that tree -- markers outside it never run
ALLGREEN="$WORK/allgreen"
mkdir -p "$ALLGREEN/proj/tree"
echo g >"$ALLGREEN/proj/tree/file"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLGREEN/proj/opk.json"
rc_doctor "all: all-green fleet -> rc 0" 0 all "$ALLGREEN"
grep_last_out "healthy row present" grep -qF "healthy        1 project(s) all green"
if printf '%s' "$_rd_out" | grep -qF "$ALLSCAN"; then
    fail "a positional stays inside its own tree"
else
    pass "a positional stays inside its own tree"
fi

# at-risk fleet: no range maps the test user -> children really classify
rm -rf "$PROCFIX"
mkmap 42 "0 0 1"
rc_doctor "all: at-risk fleet -> rc 1" 1 all "$ALLGREEN"
grep_last_out "at-risk verdict row from the child" grep -qF "entries at-risk (unmapped owners)"
grep_last_out "guided remedy hint from the child" grep -qF "fix: opk doctor fix"
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"

# zero markers under an existing root -> rc 2 (the nothing-to-check class)
ALLEMPTY="$WORK/allempty"
mkdir -p "$ALLEMPTY"
rc_doctor "all: no markers -> rc 2" 2 all "$ALLEMPTY"
grep_last_out "zero-marker warn" \
    grep -qF "no opk.json markers found under the scanned root(s) -- nothing to check"

# no scan roots at all (seam file without a single line) -> rc 2
ALLNONE="$WORK/all-none.txt"
: >"$ALLNONE"
rc_doctor_roots "all: no scan roots -> rc 2" 2 "$ALLNONE" all
grep_last_out "no-roots warn" grep -qF "no scan roots available"

# seam set but unreadable -> loud rc 1, never a silent real-tree fallback
chmod 000 "$ALLROOTS"
rc_doctor_roots "all: unreadable seam -> rc 1" 1 "$ALLROOTS" all
grep_last_out "seam error row" grep -qF "OPK_DOCTOR_SCAN_ROOTS is set but not a readable file"
chmod 644 "$ALLROOTS"

# missing scan root in the seam: warn + skip; nothing was scanned, so
# the summary names THAT state (#360 a F10 -- not a markers message)
ALLGONE="$WORK/all-gone.txt"
printf '%s\n' "$WORK/all-gone-dir" >"$ALLGONE"
rc_doctor_roots "all: missing scan root skipped -> rc 2" 2 "$ALLGONE" all
grep_last_out "missing-root warn row" grep -qF "is missing -- skipped"
grep_last_out "names the nothing-scanned state" \
    grep -qF "no scan root could be scanned -- every listed root is missing or unusable"

# control-char marker: skipped loudly; the siblings' children unaffected
ALLCT="$ALLSCAN/we$(printf '\t')ird"
mkdir -p "$ALLCT"
printf '%s\n' '{"containerTrees":[]}' >"$ALLCT/opk.json"
rc_doctor_roots "all: control-char marker skipped, fleet rc 1" 1 "$ALLROOTS" all
grep_last_out "charset skip warn" \
    grep -qF "skipped -- control characters or backslashes in the path"
_n_child="$(printf '%s' "$_rd_out" | grep -c 'Doctor -- container-tree ownership')"
if [ "$_n_child" = 3 ]; then
    pass "the skipped marker runs no child"
else
    fail "the skipped marker runs no child (got $_n_child children)"
fi
rm -rf "${ALLCT:?}"

# unreadable subtree under a scan root: the marker list warns incomplete
mkdir -p "$ALLSCAN/locked/sub"
chmod 000 "$ALLSCAN/locked"
rc_doctor_roots "all: unreadable subtree -> warn, fleet rc 1" 1 "$ALLROOTS" all
grep_last_out "incomplete-walk warn row" grep -qF "marker list may be incomplete"
chmod 755 "$ALLSCAN/locked"

# usage errors: --dry-run is fix-only, grammar stays strict
rc_doctor "all: --dry-run rejected -> rc 64" 64 all --dry-run
grep_last_out "dry-run error names 'all'" grep -qF "the scan and 'all' are read-only"
rc_doctor "all: two positionals -> rc 64" 64 all "$ALLSCAN" "$ALLSCAN"
rc_doctor "all: unknown flag -> rc 64" 64 all --foo

# degraded install: ONE loud pre-flight error before any scanning
_rd_rc=0
_rd_out="$(
    OPK_INSTALL_CONF="$WORK/all-nope.conf" OPK_DOCTOR_SCAN_ROOTS="$ALLROOTS" \
        NO_COLOR=1 setsid sh "$DOCTOR" all </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ] &&
    printf '%s' "$_rd_out" | grep -qF "not found -- is the kit installed?" &&
    ! printf '%s' "$_rd_out" | grep -q "Doctor all"; then
    pass "degraded install: one pre-flight error, no scanning"
else
    fail "degraded install: one pre-flight error, no scanning (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# --- 4d. round-a fix-wave pins (#360 a) ----------------------------------------------
# One pin per fixed finding: F1 fragment integrity, F4 error-arm seam,
# F5 mktemp guard, F6 set-but-empty seam, F7 directory-valued seam,
# F8 root-line charset gate, F10 used-root count + messages, F11 symlink
# pass + -H root, F12 marker type, F13 wording, F16 all-skipped message.

# F1: a newline inside a name splits the find output -- the fragments
# must never become children (this reproduced phantom + cwd-relative
# scans before the fix)
ALLNL="$WORK/all-nl"
NLDIR="$(printf 'we\nird')"
mkdir -p "$ALLNL/$NLDIR" "$ALLNL/real/tree"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLNL/$NLDIR/opk.json"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLNL/real/opk.json"
echo f >"$ALLNL/real/tree/f"
rc_doctor "a F1: newline-named marker dir -> real fleet stays rc 0" 0 all "$ALLNL"
_n_child="$(printf '%s' "$_rd_out" | grep -c 'corrupted marker path')"
if [ "$_n_child" = 2 ]; then
    pass "a F1: both split fragments warned as corrupt"
else
    fail "a F1: both split fragments warned as corrupt (got $_n_child)"
fi
_n_proj="$(printf '%s' "$_rd_out" | grep -cF 'project        ')"
if [ "$_n_proj" = 1 ]; then
    pass "a F1: no phantom project row -- only the real project ran"
else
    fail "a F1: no phantom project row (got $_n_proj rows)"
fi
if printf '%s' "$_rd_out" | grep -qF 'counted as an alert'; then
    fail "a F1: no false fleet alert from a fragment"
else
    pass "a F1: no false fleet alert from a fragment"
fi

# F12: a directory and a dangling symlink named opk.json are not markers
# (the walk-up rule); the healthy fleet stays rc 0
ALLDT="$WORK/all-dirmark"
mkdir -p "$ALLDT/dirp/opk.json" "$ALLDT/dangp" "$ALLDT/real/tree"
ln -s /nonexistent-opk-target "$ALLDT/dangp/opk.json"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLDT/real/opk.json"
echo f >"$ALLDT/real/tree/f"
rc_doctor "a F12: dir/dangling opk.json no markers -> rc 0" 0 all "$ALLDT"
grep_last_out "a F12: non-regular marker warned" \
    grep -qF "is not a regular file through symlinks -- not a marker (the walk-up rule)"
_n_proj="$(printf '%s' "$_rd_out" | grep -cF 'project        ')"
if [ "$_n_proj" = 1 ]; then
    pass "a F12: only the real project ran (2 non-markers skipped)"
else
    fail "a F12: only the real project ran (got $_n_proj rows)"
fi

# F6: set-but-EMPTY seam owns the list -- an empty value is an empty
# list, never a fall-back to the real default roots
_rd_rc=0
_rd_out="$(
    OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_SCAN_ROOTS="" \
        NO_COLOR=1 setsid sh "$DOCTOR" all </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 2 ] &&
    printf '%s' "$_rd_out" | grep -qF "no scan roots available" &&
    ! printf '%s' "$_rd_out" | grep -qF "no opk.json markers found"; then
    pass "a F6: set-but-empty seam -> empty list, no real-tree fallback"
else
    fail "a F6: set-but-empty seam -> empty list, no real-tree fallback (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# F7: a directory-valued seam is refused loudly before any grep
SEAMDIR="$WORK/all-seam-dir"
mkdir -p "$SEAMDIR"
rc_doctor_roots "a F7: directory-valued seam -> rc 1" 1 "$SEAMDIR" all
grep_last_out "a F7: not-a-readable-file error" grep -qF "not a readable file"

# F5: a dead workspace (mktemp fails) exits loud with rc 1
_rd_rc=0
_rd_out="$(
    TMPDIR="$WORK/all-no-tmpdir" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
        NO_COLOR=1 setsid sh "$DOCTOR" all "$ALLGREEN" </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "cannot create a temp dir"; then
    pass "a F5: mktemp failure -> loud rc 1"
else
    fail "a F5: mktemp failure -> loud rc 1 (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# F4: a child rc outside 0/1/2 counts as an alert (OPK_DOCTOR_SELF stub)
STUB="$WORK/all-stub.sh"
printf '#!/bin/sh\nexit 3\n' >"$STUB"
chmod +x "$STUB"
_rd_rc=0
_rd_out="$(
    OPK_DOCTOR_SELF="$STUB" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
        NO_COLOR=1 setsid sh "$DOCTOR" all "$ALLGREEN" </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ] &&
    printf '%s' "$_rd_out" | grep -qF "doctor exited 3 -- counted as an alert" &&
    printf '%s' "$_rd_out" | grep -qF "failed         1 scan(s) exited unexpectedly (counted as alerts)"; then
    pass "a F4: child rc 3 -> alert row, failed row, fleet rc 1"
else
    fail "a F4: child rc 3 -> alert row, failed row, fleet rc 1 (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# F10: skipped roots leave the USED count (M counts walked roots only)
ALLMIX="$WORK/all-mix-roots.txt"
printf '%s\n' "$ALLGREEN" "$WORK/all-gone-dir2" >"$ALLMIX"
rc_doctor_roots "a F10: used+missing roots -> green fleet rc 0" 0 "$ALLMIX" all
grep_last_out "a F10: count row names USED roots only" \
    grep -qF "projects       1 scanned under 1 scan root(s)"

# F16: markers found but every one skipped -> its own message
ALLSK="$WORK/all-skip"
mkdir -p "$ALLSK/we$(printf '\t')ird"
printf '%s\n' '{"containerTrees":[]}' >"$ALLSK/we$(printf '\t')ird/opk.json"
rc_doctor "a F16: all markers skipped -> rc 2 with the skip message" 2 all "$ALLSK"
grep_last_out "a F16: all-skipped message" grep -qF "all 1 marker(s) skipped -- nothing to check"

# F11: a symlinked project dir is warned (not silently dropped); a
# symlinked SCAN ROOT is followed (-H) and works
ALLSYM="$WORK/all-sym"
mkdir -p "$ALLSYM/realproj/tree"
printf '%s\n' '{"containerTrees":["tree"]}' >"$ALLSYM/realproj/opk.json"
echo f >"$ALLSYM/realproj/tree/f"
ln -s "$ALLSYM/realproj" "$ALLSYM/linkproj"
rc_doctor "a F11: symlinked project warned, real scanned -> rc 0" 0 all "$ALLSYM"
grep_last_out "a F11: symlink warn row" grep -qF "symlinked project"
grep_last_out "a F11: the real project still ran" grep -qF "tree -- 2 entries mapped-safe"
ln -s "$ALLGREEN" "$ALLSYM/rootlink"
rc_doctor "a F11: symlinked scan root followed (-H) -> rc 0" 0 all "$ALLSYM/rootlink"
grep_last_out "a F11: marker found through the root link" grep -qF "tree -- 2 entries mapped-safe"

# F8: a control-character root line (CRLF-edited seam) is skipped with a
# sanitized warn row
ALLCRLF="$WORK/all-crlf.txt"
printf '%s\r\n' "$ALLGREEN" >"$ALLCRLF"
rc_doctor_roots "a F8: CRLF root line skipped -> rc 2" 2 "$ALLCRLF" all
grep_last_out "a F8: charset skip warn names the sanitized root" \
    grep -qF "carries control characters or backslashes -- skipped"
if printf '%s' "$_rd_out" | LC_ALL=C grep -q "$(printf '\r')"; then
    fail "a F8: the warn row carries no raw CR"
else
    pass "a F8: the warn row carries no raw CR"
fi

# usage: a scan root of '/' is refused like detect's whole-fs walk
rc_doctor "all: scan root '/' -> rc 64" 64 all /

# --- 4e. round-b fix-wave pins (#360 b) ----------------------------------------------
# S1: '//' and '/./' list lines normalize onto the '/' belt; S2: a
# relative list line is refused (keeps the fragment gate's absolute-
# prefix assumption airtight); S3: with realpath absent, -H follows a
# symlinked list root (the belt the b-comment documents).

# S1: seam lines spelling the filesystem root variants
ALLFS="$WORK/all-fs.txt"
printf '//\n/./\n' >"$ALLFS"
rc_doctor_roots "b S1: '//' and '/./' refused via normalization -> rc 2" 2 "$ALLFS" all
grep_last_out "b S1: refusal row names the belt" \
    grep -qF "refused -- doctor all does not walk the whole filesystem"

# S2: a relative seam line is NORMALIZED against the cwd (realpath) --
# it lands absolute, so the fragment gate's absolute-prefix assumption
# holds; the absolute-only warn is the realpath-absent fallback (below)
ALLREL="$WORK/all-rel.txt"
printf '%s\n' "relative-root" >"$ALLREL"
rc_doctor_roots "b S2: relative root line normalized -> rc 2" 2 "$ALLREL" all
grep_last_out "b S2: the warn names the RESOLVED absolute path" \
    grep -qF "'$PWD/relative-root' is missing -- skipped"

# S3: symlinked seam root + failing realpath (the A1 stub pattern) --
# -H is what follows the link then; the marker must be found. The same
# stub pins S2's fallback arm: relative stays relative -> absolute warn
S3BIN="$WORK/b3-bin"
mkdir -p "$S3BIN"
for _b3t in dirname sed tail id mktemp awk sort find python3 grep wc tr; do
    ln -s "$(command -v "$_b3t")" "$S3BIN/$_b3t"
done
printf '#!/bin/sh\nexit 1\n' >"$S3BIN/realpath"
chmod +x "$S3BIN/realpath"
_rd_rc=0
_rd_out="$(
    PATH="$S3BIN:$PATH" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
        OPK_DOCTOR_SCAN_ROOTS="$ALLREL" NO_COLOR=1 setsid sh "$DOCTOR" all </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 2 ] &&
    printf '%s' "$_rd_out" | grep -qF "is not an absolute path -- skipped"; then
    pass "b S2 fallback: realpath absent -- relative line refused loudly"
else
    fail "b S2 fallback: realpath absent -- relative line refused loudly (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi
ALLLINK="$WORK/all-rootlink.txt"
ln -s "$ALLGREEN" "$WORK/all-green-link"
printf '%s\n' "$WORK/all-green-link" >"$ALLLINK"
_rd_rc=0
_rd_out="$(
    PATH="$S3BIN:$PATH" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
        OPK_DOCTOR_SCAN_ROOTS="$ALLLINK" NO_COLOR=1 setsid sh "$DOCTOR" all </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 0 ] && printf '%s' "$_rd_out" | grep -qF "tree -- 2 entries mapped-safe"; then
    pass "b S3: realpath absent -- -H follows the symlinked list root"
else
    fail "b S3: realpath absent -- -H follows the symlinked list root (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi
rm -rf "${S3BIN:?}"

# S1: the cntrl gate must see the NORMALIZED root -- a clean seam line
# resolving through a symlink to a control-char target is caught too
# (pre-reorder the gate screened only the raw line)
ALLCTGT="$WORK/all-cn-target"
mkdir -p "$ALLCTGT/we$(printf '\t')ird"
ln -s "$ALLCTGT/we$(printf '\t')ird" "$WORK/all-clean-link"
ALLCLN="$WORK/all-clean.txt"
printf '%s\n' "$WORK/all-clean-link" >"$ALLCLN"
rc_doctor_roots "c S1: cntrl target behind a clean symlink skipped -> rc 2" 2 "$ALLCLN" all
grep_last_out "c S1: the normalized value is gated" \
    grep -qF "carries control characters or backslashes -- skipped"

# static source pins (comment-strip rider, the canonical shape): the
# default roots are the vhosts layout plus the kit's own registry, at
# the design's depth -- hermetic execution of the DEFAULT arm would scan
# the host's real tree, so the claim is source-pinned instead
_nl_src="$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR")"
if printf '%s' "$_nl_src" | grep -qF '[ -d /var/www/vhosts ]' &&
    printf '%s' "$_nl_src" | grep -qF 'projects.conf' &&
    printf '%s' "$_nl_src" | grep -qF -- '-maxdepth 3'; then
    pass "source pin: default roots /var/www/vhosts + projects.conf, maxdepth 3"
else
    fail "source pin: default roots /var/www/vhosts + projects.conf, maxdepth 3"
fi

# --- 5. kit-state failure paths ----------------------------------------------------
_rd_rc=0
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

# --- 6. fix mode (issue #313, increment b) ------------------------------------------
# Orchestration pins against a stub dispatcher (OPK_DOCTOR_OPK seam).
# Sandbox limit, deliberate: a "fix healed the tree -> rc 0" pin needs a
# REAL ownership transition to the daemon uid -- non-root cannot chown
# to it, and re-mapping the fixture uid_map does not reach doctor (the
# mapped-range set is resolved once, before the scan). The heal path is
# therefore e2e-pinned (privileged container, real handover); here the
# stub-rm variant pins the re-check itself via the rc 1 -> 2 flip.
STUB="$WORK/stub-opk"
STUB_RM="$WORK/stub-opk-rm"
STUB_FAIL="$WORK/stub-opk-fail"
CALLS="$WORK/handover-calls"
{
    echo '#!/bin/sh'
    echo "printf '%s\\n' \"\$*\" >>'$CALLS'"
    echo 'echo "stub handover ran: $*"'
    echo 'exit 0'
} >"$STUB"
{
    echo '#!/bin/sh'
    echo "printf '%s\\n' \"\$*\" >>'$CALLS'"
    echo 'rm -rf "$3"'
    echo 'echo "stub handover ran: $*"'
    echo 'exit 0'
} >"$STUB_RM"
{
    echo '#!/bin/sh'
    echo "printf '%s\\n' \"\$*\" >>'$CALLS'"
    echo 'echo "stub handover: simulated failure" >&2'
    echo 'exit 1'
} >"$STUB_FAIL"

atrisk_setup() { # daemon-only namespace: the test uid is unmapped
    rm -rf "$PROCFIX"
    mkmap 42 "0 0 1"
    mkproj
    policy '{"containerTrees":["tree"]}'
}

# grammar: --dry-run is fix-only; unknown flags and extra positionals 64
rc_doctor "--dry-run without fix -> rc 64" 64 --dry-run
rc_doctor "unknown flag in fix mode -> rc 64" 64 fix --bogus
rc_doctor "two positionals in fix mode -> rc 64" 64 fix "$PROJ" extra

# control bytes in the project root: fix mode rejects loudly (the
# candidate TSV round-trip would truncate the handover operand away
# from the tree the prompt named, #348 a C3); scan mode has no OPERAND
# round-trip (its examples pass is display-only) and must keep working
# on such a root. Own fixture state:
# the daemon-only map makes the scratch tree at-risk deterministically
# (the preceding section leaves the 0-65535 map in place).
rm -rf "$PROCFIX"
mkmap 42 "0 0 1"
CTRL_PROJ="$WORK/ta$(printf '\t')b"
mkdir -p "$CTRL_PROJ/tree"
echo x >"$CTRL_PROJ/tree/one"
printf '%s\n' '{"containerTrees":["tree"]}' >"$CTRL_PROJ/opk.json"
RD_OPK="$STUB"
: >"$CALLS"
printf 'y\n' >"$WORK/ans"
# answer file on purpose (#348 b B2): under gate deletion the prompt
# would read this y and invoke the stub -- the CALLS pin can only
# discriminate when a yes is actually on offer
rc_doctor_ans "fix on a root with a control byte -> rc 64" 64 "$WORK/ans" fix "$CTRL_PROJ"
grep_last_out "control-char rejection row" grep -qF "contains control characters"
[ ! -s "$CALLS" ] &&
    pass "control-byte root: gate rejects before the prompt (y on offer)" ||
    fail "control-byte root: gate rejects before the prompt (y on offer)"
rc_doctor "scan on the same root still runs (no fix gate there)" 1 "$CTRL_PROJ"
grep_last_out "scan on ctrl root still classifies" grep -qF "entries at-risk"

# --dry-run passthrough: handover receives the flag, no prompt, rc stays
# the scan verdict (findings remain)
atrisk_setup
RD_OPK="$STUB"
: >"$CALLS"
rc_doctor "fix --dry-run: findings keep rc 1" 1 fix "$PROJ" --dry-run
grep_last_out "dry-run section shown" grep -qF "dry run (nothing is changed)"
grep_last_out "would-run row names the command" grep -qF "would run: opk handover opencode"
grep_last_out "handover dry plan passed through" grep -qF "stub handover ran: handover opencode $PROJ/tree --dry-run"
if printf '%s' "$_rd_out" | grep -qF "? [y/N]"; then
    fail "dry run prompts nothing"
else
    pass "dry run prompts nothing"
fi
grep -qxF "handover opencode $PROJ/tree --dry-run" "$CALLS" &&
    pass "stub argv carries --dry-run" ||
    fail "stub argv carries --dry-run ($(cat "$CALLS" 2>/dev/null))"

# walk-up in fix mode (#353): candidate row, prompt and the handover
# OPERAND must all answer the DISCOVERED root -- invoked from a subdir,
# the stub argv carries the project root's absolute tree path, never an
# invocation-dir-relative one (the discrimination: $PROJ/sub/tree would
# mean the tree paths resolved against the wrong root)
atrisk_setup
mkdir -p "$PROJ/sub"
: >"$CALLS"
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(
    cd "$PROJ/sub" &&
        OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="$STUB" \
            NO_COLOR=1 setsid sh "$DOCTOR" fix <"$WORK/ans" 2>&1
)" || _rd_rc=$?
[ "$_rd_rc" = 1 ] &&
    pass "fix via walk-up runs the stub (rc 1: tree stays at-risk)" ||
    fail "fix via walk-up runs the stub (rc 1: tree stays at-risk, rc $_rd_rc)"
printf '%s' "$_rd_out" | grep -qF "root via       walk-up from $PROJ/sub" &&
    pass "fix header reports the discovered root" ||
    fail "fix header reports the discovered root"
printf '%s' "$_rd_out" | grep -qF "running: opk handover opencode '$PROJ/tree'" &&
    pass "running row names the discovered-root tree" ||
    fail "running row names the discovered-root tree"
grep -qxF "handover opencode $PROJ/tree" "$CALLS" &&
    pass "handover operand built from the discovered root" ||
    fail "handover operand built from the discovered root ($(cat "$CALLS" 2>/dev/null))"

# fail-loud pin (L1): a handover whose dry run fails must be SEEN
RD_OPK="$STUB_FAIL"
rc_doctor "fix --dry-run, failing handover -> rc 1 with error row" 1 fix "$PROJ" --dry-run
grep_last_out "dry-run failure row" grep -qF "dry run failed for 'tree'"

# interactive: answer y -> stub runs, re-check happens, honest rc (the
# noop stub heals nothing, so the tree stays at-risk)
atrisk_setup
RD_OPK="$STUB"
: >"$CALLS"
printf 'y\n' >"$WORK/ans"
rc_doctor_ans "fix, answer y, noop stub: honest rc 1" 1 "$WORK/ans" fix "$PROJ"
grep_last_out "prompt shape [y/N] (default n)" grep -qF "? [y/N]"
grep_last_out "running row" grep -qF "running: opk handover opencode"
grep_last_out "re-check section after executed fix" grep -qF "re-check after handover"
grep -qxF "handover opencode $PROJ/tree" "$CALLS" &&
    pass "confirmed answer runs handover (no --dry-run)" ||
    fail "confirmed answer runs handover (no --dry-run) ($(cat "$CALLS" 2>/dev/null))"

# interactive: Enter declines (default n) -- nothing runs
: >"$CALLS"
printf '\n' >"$WORK/ans"
rc_doctor_ans "fix, Enter (default n): rc 1, nothing runs" 1 "$WORK/ans" fix "$PROJ"
grep_last_out "skipped row" grep -qF "skipped 'tree'"
[ ! -s "$CALLS" ] &&
    pass "declined: handover never invoked" ||
    fail "declined: handover never invoked ($(cat "$CALLS" 2>/dev/null))"

# interactive: padded ' y' is an explicit yes (ui_confirm trims)
: >"$CALLS"
printf ' y\n' >"$WORK/ans"
rc_doctor_ans "fix, padded ' y': explicit yes" 1 "$WORK/ans" fix "$PROJ"
grep -qxF "handover opencode $PROJ/tree" "$CALLS" &&
    pass "padded y runs the handover" ||
    fail "padded y runs the handover"

# re-check + counter reset: the stub REMOVES the tree (the one heal a
# non-root sandbox can perform) -> the re-check reports it missing and
# the verdict flips rc 1 -> 2. Without the reset the first pass's alert
# would survive and keep rc 1 -- this pin discriminates both.
: >"$CALLS"
printf 'y\n' >"$WORK/ans"
RD_OPK="$STUB_RM"
rc_doctor_ans "fix, answer y, healing stub: re-check flips rc 1 -> 2" 2 "$WORK/ans" fix "$PROJ"
grep_last_out "re-check reports the removed tree" grep -qF "declared but missing"
if printf '%s' "$_rd_out" | grep -qF "nothing to fix"; then
    fail "post-fix run does not claim 'nothing to fix'"
else
    pass "post-fix run does not claim 'nothing to fix'"
fi

# failing handover: error row + re-check + rc 1
atrisk_setup
RD_OPK="$STUB_FAIL"
printf 'y\n' >"$WORK/ans"
rc_doctor_ans "fix, answer y, failing handover -> rc 1" 1 "$WORK/ans" fix "$PROJ"
grep_last_out "handover failure row" grep -qF "handover failed for 'tree'"
grep_last_out "re-check runs after failure too" grep -qF "re-check after handover"

# two candidates, y then n: fd-3 loop discipline (a loop reading stdin
# would eat the answer lines as candidates) and per-tree prompts
atrisk_setup
mkdir -p "$PROJ/second"
echo z >"$PROJ/second/file"
policy '{"containerTrees":["tree","second"]}'
RD_OPK="$STUB"
: >"$CALLS"
printf 'y\nn\n' >"$WORK/ans"
rc_doctor_ans "two candidates, y then n: rc 1" 1 "$WORK/ans" fix "$PROJ"
grep -qxF "handover opencode $PROJ/tree" "$CALLS" &&
    pass "first candidate handed over" ||
    fail "first candidate handed over ($(cat "$CALLS" 2>/dev/null))"
if grep -qF "$PROJ/second" "$CALLS"; then
    fail "declined candidate not handed over"
else
    pass "declined candidate not handed over"
fi
grep_last_out "second candidate's skip row" grep -qF "skipped 'second'"

# healthy project: nothing to fix, rc 0, stub never called
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
mkproj
policy '{"containerTrees":["tree"]}'
RD_OPK="$STUB"
: >"$CALLS"
rc_doctor "healthy project, fix: rc 0" 0 fix "$PROJ"
grep_last_out "nothing-to-fix row" grep -qF "nothing to fix"
[ ! -s "$CALLS" ] &&
    pass "healthy: handover never invoked" ||
    fail "healthy: handover never invoked"

# warnings-only finding (missing tree): no unambiguous remedy, no offer
policy '{"containerTrees":["not/cloned/yet"]}'
rc_doctor "missing tree, fix: rc 2, nothing offered" 2 fix "$PROJ"
grep_last_out "nothing-to-fix row (warn class has no remedy)" grep -qF "nothing to fix"
if printf '%s' "$_rd_out" | grep -qF "? [y/N]"; then
    fail "warn class never prompts"
else
    pass "warn class never prompts"
fi

# dispatcher resolution failure: loud, rc 1 (L1 probe pin)
RD_OPK="$WORK/no-such-opk"
rc_doctor "fix without a dispatcher -> rc 1" 1 fix "$PROJ"
grep_last_out "dispatcher error row" grep -qF "cannot find the opk dispatcher"
RD_OPK=""

# source-shape pins (comment-strip rider per conventions.md, "Source-
# counting pins"): the C1 trap and the S5 belt are defense-in-depth
# shapes whose failure paths a unit fixture cannot reach cheaply (the
# python gate fires first; a deterministic mid-scan SIGINT fixture is
# the pin-cost-budget class) — pinned stripped so commented-out
# constructs cannot satisfy them. The belt conjuncts pin three
# distinctive fragments spanning the case line START-to-END, so every
# arm is covered (#344 b R1: the former `grep -qF '.'` was vacuous —
# any period matched; #344 c Q1: the b-wave fragments left the
# absolute and backslash arms unpinned — mutation-verified in the
# round-b/c reviews, records on this PR's timeline)
sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF "trap '_doctor_cleanup; exit 1' INT TERM" &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF 'trap _doctor_cleanup EXIT' &&
    pass "signal handlers exit (#344 a C1 house shape, stripped source)" ||
    fail "signal handlers exit (#344 a C1 house shape, stripped source)"
sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '/* | */ | . | ./* | .. | ../* | ' &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '*/. | */./* | */.. | */../* | ' &&
    sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -qF '*//* | *\\*)' &&
    pass "belt case pinned end-to-end: absolute, trailing/dot/dotdot/empty forms, backslash (#344 a S5 + b R1 + c Q1)" ||
    fail "belt case pinned end-to-end: absolute, trailing/dot/dotdot/empty forms, backslash (#344 a S5 + b R1 + c Q1)"

# --- 7. detect mode (issue #352 / #313 phase 3) -------------------------------------
# Two fixture classes cover both evidence arms without root:
#   A  daemon=root, the test uid mapped as subuid -> every test-owned
#      entry is S-class (subuid twin) evidence, wherever it sits
#   B  daemon=the test user -> test-owned entries are D-class and count
#      ONLY on git-ignored paths (git repo fixture, check-ignore live);
#      the S arm is empty (nothing else can own files in the sandbox)
# The mixed-owner class needs unmapped owners next to evidence -- only
# the privileged e2e lane can build that (same sandbox limit as the fix
# heal path, section 6).
CONF_ME="$WORK/install-me.conf"
printf 'OPENCODE_USER=%s\nVERSION=9.9.9\n' "$(id -un)" >"$CONF_ME"

detproj() { # git repo: ignored build/ with outputs, tracked src/
    rm -rf "$PROJ"
    mkdir -p "$PROJ"
    git init -q "$PROJ"
    printf 'build/\n' >"$PROJ/.gitignore"
    mkdir -p "$PROJ/build/out" "$PROJ/src"
    echo out >"$PROJ/build/out/app.min.css"
    echo s >"$PROJ/src/a.php"
}

# grammar: detect is a first-token subcommand; --dry-run is fix-only;
# the filesystem root is never a detect scan root
rc_doctor "detect --dry-run -> rc 64" 64 detect --dry-run
rc_doctor "detect with a flag -> rc 64" 64 detect --bogus
rc_doctor "detect with two roots -> rc 64" 64 detect "$PROJ" extra
rc_doctor "detect on / refused -> rc 64" 64 detect /

# fixture A: S evidence everywhere -> candidates build + src, root-level
# evidence (.gitignore) warns, EOF declines everything -> snippets, rc 1
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
detproj
rc_doctor "detect, S evidence, EOF: snippets + rc 1" 1 detect "$PROJ"
grep_last_out "candidate row (build)" grep -qF "candidate      build --"
grep_last_out "candidate row (src)" grep -qF "candidate      src --"
grep_last_out "consent prompt shape [y/N]" grep -qF "? [y/N]"
grep_last_out "declined snippet prints the entry" grep -qF '{"path": "build",'
grep_last_out "undeclared result row" grep -qF "left undeclared -- snippets above"
grep_last_out "root-level evidence warns" grep -qF "sit directly in the project root"
if [ -e "$PROJ/opk.json" ]; then
    fail "declined detect writes no opk.json"
else
    pass "declined detect writes no opk.json"
fi

# fixture A, consent y for both candidates -> opk.json written, valid,
# pretty-printed; the root-level evidence warn keeps rc at 2 (family
# contract: warnings never vanish because everything was declared)
detproj
printf 'y\ny\n' >"$WORK/ans"
rc_doctor_ans "detect, S evidence, y/y: written, rc 2 (root warn)" 2 "$WORK/ans" detect "$PROJ"
grep_last_out "declared result row" grep -qF "declared in opk.json -- commit it"
grep -qF '"path": "build"' "$PROJ/opk.json" &&
    grep -qF '"path": "src"' "$PROJ/opk.json" &&
    pass "both consented candidates land in opk.json" ||
    fail "both consented candidates land in opk.json ($(cat "$PROJ/opk.json" 2>/dev/null))"
python3 -m json.tool "$PROJ/opk.json" >/dev/null 2>&1 &&
    pass "written opk.json is valid strict JSON" ||
    fail "written opk.json is valid strict JSON"
[ "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), indent=2))' "$PROJ/opk.json" 2>/dev/null)" \
    = "$(cat "$PROJ/opk.json")" ] &&
    pass "written opk.json is pretty-printed (indent 2)" ||
    fail "written opk.json is pretty-printed (indent 2)"

# fixture B: only D-on-ignored counts -- build is a candidate, the
# tracked src/ is NOT (the discrimination pin for the gitignore arm);
# the map's zero row must point at the DAEMON (the test user) or the
# unverified-range warn would color every rc in this fixture
rm -rf "$PROCFIX"
mkmap 42 "0 $CURUID 1"
detproj
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" </dev/null 2>&1)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ]; then
    pass "detect, D evidence, EOF: rc 1 (build undeclared)"
else
    fail "detect, D evidence, EOF: rc 1 (build undeclared) (rc $_rd_rc)"
fi
printf '%s' "$_rd_out" | grep -qF "candidate      build --" &&
    pass "ignored build/ is a candidate" ||
    fail "ignored build/ is a candidate"
if printf '%s' "$_rd_out" | grep -qF "candidate      src --"; then
    fail "tracked src/ is no candidate (D evidence needs the ignore answer)"
else
    pass "tracked src/ is no candidate (D evidence needs the ignore answer)"
fi

# fixture B, consent -> written; re-run: the covered boundary is already
# declared, no candidate remains, rc 0 (no warns in this fixture)
detproj
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" <"$WORK/ans" 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 0 ] &&
    pass "detect, D evidence, y: written, rc 0" ||
    {
        fail "detect, D evidence, y: written, rc 0 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }
printf '%s' "$_rd_out" | grep -qF "no container-write evidence found" &&
    fail "consented run reports its declaration" ||
    pass "consented run reports its declaration"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" </dev/null 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 0 ] &&
    pass "re-detect after declaring: rc 0" ||
    {
        fail "re-detect after declaring: rc 0 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }
printf '%s' "$_rd_out" | grep -qF "already declared (via build)" &&
    pass "covered boundary shows as already declared" ||
    fail "covered boundary shows as already declared"

# walk-up in detect mode (#353): invoked from a SUBDIR, detect answers
# the discovered root -- the parent policy's declaration covers the
# evidence boundary. Without the walk-up the run would scan src/ alone
# and read "no container-write evidence found" (v1 shape) -- the
# already-declared row is the discrimination
rm -rf "$PROCFIX"
mkmap 42 "0 $CURUID 1"
detproj
printf '{"version":1,"containerTrees":[{"path":"build","note":"outputs"}]}\n' \
    >"$PROJ/opk.json"
_rd_rc=0
_rd_out="$(
    cd "$PROJ/src" &&
        OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
            NO_COLOR=1 setsid sh "$DOCTOR" detect </dev/null 2>&1
)" || _rd_rc=$?
[ "$_rd_rc" = 0 ] &&
    pass "detect via walk-up: covered evidence, rc 0" ||
    {
        fail "detect via walk-up: covered evidence, rc 0 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }
printf '%s' "$_rd_out" | grep -qF "root via       walk-up from $PROJ/src" &&
    pass "detect header reports the discovered root" ||
    fail "detect header reports the discovered root"
printf '%s' "$_rd_out" | grep -qF "already declared (via build)" &&
    pass "parent declarations cover the boundary from a subdir" ||
    fail "parent declarations cover the boundary from a subdir"

# detect's WRITE answers the discovered root too (#353): a candidate
# consented from a subdir lands in the PARENT's opk.json -- and never
# creates one in the invocation dir (the discrimination: v1 strict-cwd
# would write src/opk.json)
rm -rf "$PROCFIX"
mkmap 42 "0 $CURUID 1"
detproj
printf '{"version":1,"containerTrees":[{"path":"src","note":"human"}]}\n' \
    >"$PROJ/opk.json"
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(
    cd "$PROJ/src" &&
        OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
            NO_COLOR=1 setsid sh "$DOCTOR" detect <"$WORK/ans" 2>&1
)" || _rd_rc=$?
[ "$_rd_rc" = 0 ] &&
    pass "detect write via walk-up: rc 0" ||
    {
        fail "detect write via walk-up: rc 0 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }
grep -qF '"path": "build"' "$PROJ/opk.json" &&
    grep -qF '"path": "src"' "$PROJ/opk.json" &&
    pass "consented entry lands in the PARENT's opk.json" ||
    fail "consented entry lands in the PARENT's opk.json ($(cat "$PROJ/opk.json" 2>/dev/null))"
[ ! -e "$PROJ/src/opk.json" ] &&
    pass "no opk.json appears in the invocation dir" ||
    fail "no opk.json appears in the invocation dir"

# no evidence at all (fixture B, no ignored paths): rc 0
rm -rf "$PROJ"
mkdir -p "$PROJ/src"
echo s >"$PROJ/src/a.php"
git init -q "$PROJ"
rd2() { # detect run with the daemon=me fixture
    _rd_rc=0
    _rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
        NO_COLOR=1 setsid sh "$DOCTOR" "$@" </dev/null 2>&1)" || _rd_rc=$?
}
rd2 detect "$PROJ"
[ "$_rd_rc" = 0 ] && printf '%s' "$_rd_out" | grep -qF "no container-write evidence found" &&
    pass "no evidence -> rc 0, honest empty result" ||
    fail "no evidence -> rc 0, honest empty result (rc $_rd_rc)"

# append to an EXISTING policy: version, unknown keys and the existing
# entry survive, the new entry joins the array
detproj
printf '{"version":1,"futureKey":true,"containerTrees":[{"path":"legacy","note":"kept"}]}\n' \
    >"$PROJ/opk.json"
mkdir -p "$PROJ/legacy"
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" <"$WORK/ans" 2>&1)" || _rd_rc=$?
python3 - "$PROJ/opk.json" <<'PYEOF' && pass "existing policy survives an append (version, keys, entry)" ||
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["version"] == 1
assert doc["futureKey"] is True
paths = [e["path"] for e in doc["containerTrees"]]
assert paths == ["legacy", "build"], paths
PYEOF
    fail "existing policy survives an append (version, keys, entry) ($(cat "$PROJ/opk.json"))"

# symlinked opk.json: the writer refuses loudly (the 0.0.39g S2 class)
detproj
printf '{"containerTrees":[]}\n' >"$WORK/real-pol.json"
ln -s "$WORK/real-pol.json" "$PROJ/opk.json"
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" <"$WORK/ans" 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "is a symlink -- not writing" &&
    pass "symlinked opk.json -> refuse write, rc 1" ||
    {
        fail "symlinked opk.json -> refuse write, rc 1 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }

# unwritable project root: the temp file cannot be created -- loud, rc 1
detproj
chmod 555 "$PROJ"
printf 'y\n' >"$WORK/ans"
_rd_rc=0
_rd_out="$(OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" OPK_DOCTOR_OPK="" \
    NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" <"$WORK/ans" 2>&1)" || _rd_rc=$?
chmod 755 "$PROJ"
[ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "cannot create a temp file" &&
    pass "unwritable root -> loud failure, rc 1" ||
    {
        fail "unwritable root -> loud failure, rc 1 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }

# git unavailable (broken stub): the ignore answers are gone, D evidence
# cannot be verified -- warn row, not silence; S evidence would still
# work (fixture A would find its candidates without any ignore answers)
NOGIT="$WORK/nogit-bin"
mkdir -p "$NOGIT"
printf '#!/bin/sh\nexit 128\n' >"$NOGIT/git"
chmod +x "$NOGIT/git"
detproj
_rd_rc=0
_rd_out="$(PATH="$NOGIT:$PATH" OPK_INSTALL_CONF="$CONF_ME" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
    OPK_DOCTOR_OPK="" NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" </dev/null 2>&1)" || _rd_rc=$?
[ "$_rd_rc" = 2 ] && printf '%s' "$_rd_out" | grep -qF "git ignore answers unavailable" &&
    printf '%s' "$_rd_out" | grep -qF "only subuid-owner evidence is used" &&
    pass "git unavailable -> warn row + consequence, rc 2" ||
    {
        fail "git unavailable -> warn row + consequence, rc 2 (rc $_rd_rc)"
        echo "        output: $_rd_out"
    }

# unusable path forms are dropped at classify time (charset belt): a
# single-quote directory and a non-ASCII directory are evidence-class S
# (fixture A) but never a candidate; the drop count warns under the
# honest label (#356 a A1: non-ASCII is not "control/shell")
rm -rf "$PROCFIX"
mkmap 42 "0 0 1" "1 $CURUID 65536"
detproj
mkdir -p "$PROJ/qu'ote" "$PROJ/locked"
echo q >"$PROJ/qu'ote/file"
echo l >"$PROJ/locked/file"
mkdir -p "$PROJ/$(printf '\303\234ber')" # non-ASCII (UTF-8 umlaut) dir
echo u >"$PROJ/$(printf '\303\234ber')/file"
chmod 000 "$PROJ/locked"
rc_doctor "detect drops unusable paths, keeps working ones (rc 1)" 1 detect "$PROJ"
grep_last_out "drop-count warn row" grep -qF "entries dropped -- unusable path forms"
grep_last_out "drop label names non-ASCII honestly (#356 a A1)" grep -qF "non-ASCII, control or shell-significant characters"
grep_last_out "incomplete-walk warn row" grep -qF "unreadable entries -- evidence may be incomplete"
if printf '%s' "$_rd_out" | grep -qF "qu'ote"; then
    fail "quoted dir never reaches a row"
else
    pass "quoted dir never reaches a row"
fi
if printf '%s' "$_rd_out" | grep -q "$(printf '\303\234ber')"; then
    fail "non-ASCII dir never reaches a row"
else
    pass "non-ASCII dir never reaches a row"
fi
chmod 755 "$PROJ/locked"

# --- 7a. fix-wave pins (#356 a) ------------------------------------------------------
# D1: an EMPTY ignore-answer file voided the whole classification (the
# FNR==NR idiom mis-consumes dcls when file 1 is empty) -- every repo
# without ignored paths and every no-git fallback run read "no evidence"
# while S evidence existed. Two arms: nothing-ignored and broken git.
detproj
rm -f "${PROJ:?}/.gitignore" # a repo with NO ignore rules: check-ignore rc 1
rc_doctor "D1: nothing ignored, S evidence -> candidates (rc 1)" 1 detect "$PROJ"
grep_last_out "D1: candidate appears with an empty ignore set" grep -qF "candidate      build --"
grep_last_out "D1: second candidate appears too" grep -qF "candidate      src --"
# broken git + S evidence: the fallback warn row fires AND the
# subuid-evidence candidates still appear
_rd_rc=0
_rd_out="$(PATH="$NOGIT:$PATH" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
    OPK_DOCTOR_OPK="" NO_COLOR=1 setsid sh "$DOCTOR" detect "$PROJ" </dev/null 2>&1)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ] &&
    printf '%s' "$_rd_out" | grep -qF "git ignore answers unavailable" &&
    printf '%s' "$_rd_out" | grep -qF "candidate      build --"; then
    pass "D1: no-git fallback keeps S-evidence candidates + warn row"
else
    fail "D1: no-git fallback keeps S-evidence candidates + warn row (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# B4: a detect root carrying control characters classifies nothing --
# refuse it loudly (64) like fix mode does for its TSV round-trip
TAB_PROJ="$WORK/ta$(printf '\t')b2"
mkdir -p "$TAB_PROJ/tree"
echo x >"$TAB_PROJ/tree/one"
rc_doctor "B4: control-char root refused for detect (rc 64)" 64 detect "$TAB_PROJ"
grep_last_out "B4: refusal row names the class" grep -qF "control characters or backslashes"
BS_PROJ="$WORK/bs\\root"
mkdir -p "$BS_PROJ/tree"
echo x >"$BS_PROJ/tree/one"
rc_doctor "B4: backslash root refused for detect (rc 64)" 64 detect "$BS_PROJ"

# B1/B2 order pin: the [ -L ] gate must sit IMMEDIATELY before the
# chmod (the swapped-symlink window spans the python run), the mv gate
# (with the -d conjunct for the directory swap) after it -- line-order
# statics on comment-stripped source, the W1 precedent in
# test-kit-cli.sh. The mid-run swap itself is not fixture-able without
# window injection; the mechanism was mechanically verified in round a
# (verdicts-v1, reproduced by main on the verbatim awk).
_b1_gate=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -nF 'if [ -L "$_dt_tmp" ]; then' | head -1 | cut -d: -f1)
_b1_chmod=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -nF 'chmod "$_dt_mode" "$_dt_tmp"' | head -1 | cut -d: -f1)
_b1_mv=$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR" | grep -nF '[ ! -L "$_dt_tmp" ] && [ ! -L "$DOCTOR_ROOT/opk.json" ] && [ ! -d' | head -1 | cut -d: -f1)
if [ -n "$_b1_gate" ] && [ -n "$_b1_chmod" ] && [ -n "$_b1_mv" ] &&
    [ "$_b1_gate" -lt "$_b1_chmod" ] && [ "$_b1_chmod" -lt "$_b1_mv" ]; then
    pass "B1/B2: [ -L ] gate before chmod before the mv gate (with -d conjunct)"
else
    fail "B1/B2: [ -L ] gate before chmod before the mv gate (gate=$_b1_gate chmod=$_b1_chmod mv=$_b1_mv)"
fi

# --- 7b. fix-wave pins (#361) --------------------------------------------------------
# W1: the SINGLE-root workspace (scan/fix/detect) gets the same dead-
# workspace guard as the all block (#360 a F5): doctor is set -u only (no
# -e -- one failing tree must not kill the remaining verdicts), so an
# unchecked mktemp left WORK empty and every later path collapsed to a
# root-level literal (/ranges, /trees, /uids ...) instead of failing.
_rd_rc=0
_rd_out="$(
    TMPDIR="$WORK/single-no-tmpdir" OPK_INSTALL_CONF="$CONF" OPK_DOCTOR_PROC_ROOT="$PROCFIX" \
        NO_COLOR=1 setsid sh "$DOCTOR" "$PROJ" </dev/null 2>&1
)" || _rd_rc=$?
if [ "$_rd_rc" = 1 ] && printf '%s' "$_rd_out" | grep -qF "cannot create a temp dir"; then
    pass "#361: single-root mktemp failure -> loud rc 1"
else
    fail "#361: single-root mktemp failure -> loud rc 1 (rc $_rd_rc)"
    echo "        output: $_rd_out"
fi

# --- summary gate -----------------------------------------------------------------
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}all doctor tests passed ($passed).${NC}"
exit 0
