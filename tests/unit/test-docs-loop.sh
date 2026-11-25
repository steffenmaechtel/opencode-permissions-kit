#!/bin/sh
# test-docs-loop.sh -- docs-loop v2 pins (issue #755): the AGENTS.md byte
# cap and the metrics snapshot script.
#
# Subjects:
#   1. The AGENTS.md byte cap (AGENTS.md Rules, the byte-cap bullet):
#      agents_cap_check reds when the always-loaded file outgrows
#      AGENTS_MD_CAP. Every branch of the check has a fixture that
#      executes it (L4): over the cap, exactly at it, under it, and a
#      file the check cannot read -- never a silent clean.
#   2. scripts/docs-loop-metrics.py, the M1/M2 snapshot script, against
#      a SYNTHETIC opencode V2 database and a scratch git repository --
#      never the host's real opencode.db and never this repository's
#      history (unit suites are sandboxed, and CI checkouts are
#      depth-1). The fixture builder writes the four tables the script
#      reads and leaves the database in WAL mode with uncheckpointed
#      frames (os._exit, no close), so the never-write pin can tell a
#      read-only open from a read-write one: a read-write connection
#      checkpoints and deletes the WAL when it closes.
#   3. The command blocks documented in agent/docs-loop.md (the trigger
#      check and the sweep list): extracted from the page as written and
#      executed under a stubbed gh -- an edit that breaks a failure path
#      or the count arithmetic reds here. The stub answers for gh and
#      reads none of its arguments: the trigger block's jq programs and
#      its --label filter are NOT exercised (the sweep's jq program is,
#      by a separate pin when jq is installed).
#
# Run: sh tests/unit/test-docs-loop.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Shared harness (issue #394): pass/fail, colors, counters and the work
# registry (issue #395) live in lib/harness.sh now.
. "$REPO_ROOT/tests/unit/lib/harness.sh"

SCRIPT="$REPO_ROOT/scripts/docs-loop-metrics.py"
AGENTS_MD_CAP=$((14 * 1024))

WORK="$(work_new)" || {
    echo "docs-loop tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

# --- 1. AGENTS.md byte cap ----------------------------------------------------

agents_cap_check() { # $1 = file, $2 = cap in bytes -> FAIL rows on stdout (empty = clean)
    if [ ! -f "$1" ] || [ ! -r "$1" ]; then
        echo "FAIL $1: cannot read it -- the byte cap was not checked"
        return
    fi
    _ac_size=$(wc -c <"$1" | tr -d ' ')
    case $_ac_size in
        '' | *[!0-9]*)
            echo "FAIL $1: size '$_ac_size' is not a number -- the byte cap was not checked"
            return
            ;;
    esac
    if [ "$_ac_size" -gt "$2" ]; then
        echo "FAIL $1: $_ac_size bytes > cap $2 -- compress or move (AGENTS.md Rules, the byte-cap bullet)"
    fi
}

_cap_rows=$(agents_cap_check "$REPO_ROOT/AGENTS.md" "$AGENTS_MD_CAP")
if [ -z "$_cap_rows" ]; then
    pass "AGENTS.md is within its byte cap ($AGENTS_MD_CAP)"
else
    fail "AGENTS.md byte cap: $_cap_rows"
fi

# printf '%Ns\n' writes N spaces plus the newline: 101 / 100 / 99 bytes
printf '%100s\n' "" >"$WORK/over.md"
printf '%99s\n' "" >"$WORK/at.md"
printf '%98s\n' "" >"$WORK/under.md"
_cap_rows=$(agents_cap_check "$WORK/over.md" 100)
case $_cap_rows in
    "FAIL $WORK/over.md: 101 bytes > cap 100 --"*) pass "cap arm: over the cap reds with size and cap" ;;
    *) fail "cap arm: an over-cap file must red with its size (got: $_cap_rows)" ;;
esac
_cap_rows=$(agents_cap_check "$WORK/at.md" 100)
if [ -z "$_cap_rows" ]; then
    pass "cap arm: exactly at the cap is clean"
else
    fail "cap arm: an at-cap file must stay clean (got: $_cap_rows)"
fi
_cap_rows=$(agents_cap_check "$WORK/under.md" 100)
if [ -z "$_cap_rows" ]; then
    pass "cap arm: under the cap is clean"
else
    fail "cap arm: an under-cap file must stay clean (got: $_cap_rows)"
fi
_cap_rows=$(agents_cap_check "$WORK/no-such.md" 100)
case $_cap_rows in
    "FAIL $WORK/no-such.md: cannot read it"*) pass "cap arm: an unreadable file fails loud, never passes as clean" ;;
    *) fail "cap arm: a missing file must fail loud (got: $_cap_rows)" ;;
esac

# The rule text names this suite as the pin (a renamed suite is a
# dangling pointer in the always-loaded file). The literal is the
# single-line fragment: the bullet wraps right before the path.
if grep -qF -- '`tests/unit/test-docs-loop.sh`' "$REPO_ROOT/AGENTS.md"; then
    pass "AGENTS.md byte-cap bullet names this suite"
else
    fail "AGENTS.md byte-cap bullet no longer names tests/unit/test-docs-loop.sh"
fi

# --- 2. metrics script: fixture ----------------------------------------------

# build_db <path> <base> -- synthetic opencode V2 database, WAL frames left
# uncheckpointed. Session epochs sit at LOCAL NOON of their date, so the
# ISO week is the same in every timezone. Expected medians (hand-derived):
#   2026-W46  lead: L1 1500, L2 4000 -> median prompt 2750, uncached 2000,
#                         cache read 750;   subagent: S1 1000
#   2026-W47  lead: L3 5000 (its second assistant message carries 99999
#                         and must not leak into the first-message figure)
build_db() {
    python3 - "$1" "$2" <<'PY'
import datetime
import json
import os
import sqlite3
import sys

db, base = sys.argv[1], sys.argv[2]
proj = os.path.join(base, "opk-test")
other = os.path.join(base, "other")
glob = os.path.join(proj, "global", "AGENTS.md")
repo = os.path.join(proj, "repo")


def ms(month, day):
    noon = datetime.datetime(2026, month, day, 12, 0, 0)
    return int(noon.timestamp() * 1000)


def tokens(uncached, read):
    return json.dumps({"tokens": {"input": uncached, "output": 10,
                                  "cache": {"read": read, "write": 0}}})


con = sqlite3.connect(db)
con.execute("PRAGMA journal_mode=WAL")
con.executescript("""
CREATE TABLE session_v2 (id TEXT, parent_id TEXT, directory TEXT, time_created INTEGER);
CREATE TABLE session_message (session_id TEXT, type TEXT, seq INTEGER, data TEXT);
CREATE TABLE instruction_state (session_id TEXT, initial_values TEXT);
CREATE TABLE instruction_blob (hash TEXT PRIMARY KEY, value TEXT);
""")
counter = [0]


def record(session_id, cwd, entries, record=True, broken=None):
    if not record:
        return
    counter[0] += 1
    env = json.dumps("<env>\n  Working directory: %s\n</env>" % cwd)
    ins = json.dumps([{"path": p, "content": c} for p, c in entries])
    if broken == "instructions":
        ins = "{not a json list"
    con.execute("INSERT INTO instruction_blob VALUES (?,?)", ("env%d" % counter[0], env))
    con.execute("INSERT INTO instruction_blob VALUES (?,?)", ("ins%d" % counter[0], ins))
    if broken == "record":
        state = "{not a json object"
    else:
        state = json.dumps({"core/environment": "env%d" % counter[0],
                            "core/instructions": "ins%d" % counter[0]})
    con.execute("INSERT INTO instruction_state VALUES (?,?)", (session_id, state))


OWN = [(glob, "# Global rules"), (repo + "/AGENTS.md", "# AGENTS")]


def session(session_id, parent, created, cwd, kind, messages):
    con.execute("INSERT INTO session_v2 VALUES (?,?,?,?)", (session_id, parent, cwd, created))
    if kind == "repo":
        record(session_id, cwd, OWN)
    elif kind == "workspace-root":
        record(session_id, cwd, [(glob, "# Global rules"), (cwd + "/AGENTS.md", "# AGENTS (workspace)"),
                                 (cwd + "/repo/AGENTS.md", "# AGENTS")])
    elif kind == "ancestor":
        record(session_id, cwd, [(glob, "# Global rules"), (proj + "/AGENTS.md", "# AGENTS (workspace)"),
                                 (cwd + "/AGENTS.md", "# AGENTS")])
    elif kind == "no-own":
        record(session_id, cwd, [(glob, "# Global rules")])
    elif kind == "no-record":
        record(session_id, cwd, OWN, record=False)
    elif kind == "bad-record":
        record(session_id, cwd, OWN, broken="record")
    elif kind == "bad-instructions":
        record(session_id, cwd, OWN, broken="instructions")
    for seq, data in messages:
        con.execute("INSERT INTO session_message VALUES (?,?,?,?)", (session_id, "assistant", seq, data))


w46, w47 = ms(11, 11), ms(11, 18)
session("ses_L1", None, w46, repo, "repo", [(2, tokens(1000, 500))])
session("ses_L2", None, w46, repo, "repo", [(2, tokens(3000, 1000))])
session("ses_S1", "ses_L1", w46, repo, "repo", [(2, tokens(700, 300))])
# inserted out of seq order on purpose: the FIRST assistant message is
# the one with the lowest seq, not the first row written
session("ses_L3", None, w47, repo, "repo", [(5, tokens(99999, 0)), (2, tokens(5000, 0))])
session("ses_X1", None, w46, proj, "workspace-root", [(2, tokens(8000, 0))])
session("ses_X2", None, w46, repo, "ancestor", [(2, tokens(8000, 0))])
session("ses_X3", None, w46, repo, "no-own", [(2, tokens(8000, 0))])
session("ses_X4", None, w46, repo, "no-record", [(2, tokens(8000, 0))])
# the two silent-skip paths: an instruction record that is not JSON, and
# a parsable record whose instructions blob is not JSON -- both counted
session("ses_X8", None, w46, repo, "bad-record", [(2, tokens(8000, 0))])
session("ses_X9", None, w46, repo, "bad-instructions", [(2, tokens(8000, 0))])
session("ses_X5", None, w47, repo, "repo", [])
session("ses_X6", None, w46, other + "/repo", "repo", [(2, tokens(8000, 0))])
session("ses_X7", None, w46, repo, "repo", [(2, "{broken json")])
non_ascii = json.dumps({"tokens": {"input": 100, "output": 1, "cache": {}},
                        "agent": "general", "note": "Pr\u00fcfung \u2014 non-ASCII payload"})
session("ses_S2", "ses_L2", w47, repo, "repo", [(2, non_ascii)])
con.commit()
# leave the WAL uncheckpointed: no close, no interpreter shutdown hooks
os._exit(0)
PY
}

DBDIR="$WORK/db"
mkdir -p "$DBDIR"
build_db "$DBDIR/opencode.db" "$WORK"
if [ ! -f "$DBDIR/opencode.db-wal" ]; then
    fail "fixture: the synthetic database kept no WAL file -- the never-write pin cannot discriminate here"
fi

# git fixture for M2: commits at known dates, sizes chosen by hand.
#   A 2026-11-05: AGENTS.md 100, agent/a.md 50, 2 metas
#   B 2026-11-12: AGENTS.md 300, + agent/b.md 25, + 3 metas
#   C 2026-11-20: README only (must not move the weekly state)
#   S 2026-11-18 on a side branch, merged 2026-11-24: AGENTS.md 400
#      (must not move W47 either -- the merge date counts, not S's)
GR="$WORK/gitrepo"
mkdir -p "$GR/agent/sub" "$GR/internal/rules-meta/0/0/1"
git -C "$GR" init -q
git -C "$GR" remote add origin https://example.invalid/opk-test.git
printf '%99s\n' "" | tr ' ' A >"$GR/AGENTS.md"
printf '%49s\n' "" | tr ' ' a >"$GR/agent/a.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/RM-0001.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/RM-0002.md"
git -C "$GR" add -A
GIT_COMMITTER_DATE="2026-11-05 12:00:00" git -C "$GR" -c user.name=t -c user.email=t@e commit -q -m A
SHA_A=$(git -C "$GR" rev-parse --short=7 HEAD)
printf '%299s\n' "" | tr ' ' A >"$GR/AGENTS.md"
printf '%24s\n' "" | tr ' ' b >"$GR/agent/b.md"
printf '%9s\n' "" | tr ' ' s >"$GR/agent/sub/README.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/RM-0003.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/RM-0004.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/RM-0005.md"
printf 'x\n' >"$GR/internal/rules-meta/0/0/1/notes.md"
git -C "$GR" add -A
GIT_COMMITTER_DATE="2026-11-12 12:00:00" git -C "$GR" -c user.name=t -c user.email=t@e commit -q -m B
SHA_B=$(git -C "$GR" rev-parse --short=7 HEAD)
printf 'readme\n' >"$GR/README.md"
git -C "$GR" add README.md
GIT_COMMITTER_DATE="2026-11-20 12:00:00" git -C "$GR" -c user.name=t -c user.email=t@e commit -q -m C
SHA_C=$(git -C "$GR" rev-parse --short=7 HEAD)
# A side branch committed on 2026-11-18 (inside W47) and merged on
# 2026-11-24 (after the reported window): the weekly rows up to W47
# must keep the mainline state; only the HEAD row shows the merge.
DEF=$(git -C "$GR" symbolic-ref --short HEAD)
git -C "$GR" checkout -q -b feature
printf '%399s\n' "" | tr ' ' S >"$GR/AGENTS.md"
git -C "$GR" add AGENTS.md
GIT_COMMITTER_DATE="2026-11-18 12:00:00" git -C "$GR" -c user.name=t -c user.email=t@e commit -q -m S
git -C "$GR" checkout -q "$DEF"
GIT_COMMITTER_DATE="2026-11-24 12:00:00" git -C "$GR" -c user.name=t -c user.email=t@e merge -q --no-ff -m Mg feature
SHA_M=$(git -C "$GR" rev-parse --short=7 HEAD)

# --- 2a. never-write pin (runs FIRST: it needs the untouched WAL) ------------

db_untouched() { # $1 = db, $2 = marker, $3 = dir listing before -> rc 0 = untouched
    [ -f "$1-wal" ] || {
        echo "the WAL file is gone (a read-write open checkpointed and removed it)"
        return 1
    }
    if [ "$1" -nt "$2" ]; then
        echo "the database file was written"
        return 1
    fi
    return 0
}

cp "$DBDIR/opencode.db" "$WORK/db.marker"
ls "$DBDIR" >"$WORK/dbdir.before"
_ms_rc=0
python3 "$SCRIPT" --db "$DBDIR/opencode.db" --repo "$GR" --since 2026-11-02 --until 2026-11-22 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >"$WORK/out.txt" 2>"$WORK/err.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 0 ]; then
    pass "metrics script exits 0 on a well-formed database"
else
    fail "metrics script must exit 0 on a well-formed database (rc=$_ms_rc err=$(cat "$WORK/err.txt"))"
fi
ls "$DBDIR" >"$WORK/dbdir.after"
_nw=$(db_untouched "$DBDIR/opencode.db" "$WORK/db.marker")
if [ -z "$_nw" ] && cmp -s "$WORK/dbdir.before" "$WORK/dbdir.after"; then
    pass "never-write: the run left database, WAL and directory untouched (read-only open)"
else
    fail "never-write: the snapshot wrote to the database directory ($_nw; listing: $(diff "$WORK/dbdir.before" "$WORK/dbdir.after" | tr '\n' ' '))"
fi
if check_live "metrics script opens the database with mode=ro" "$SCRIPT" -qF '?mode=ro'; then :; fi

# discrimination arm: a copy of the script with the read-only URI removed
# must trip the same check -- the pin above is green for the right reason.
DBDIR2="$WORK/db2"
mkdir -p "$DBDIR2"
build_db "$DBDIR2/opencode.db" "$WORK"
sed 's/?mode=ro//' "$REPO_ROOT/scripts/docs-loop-metrics.py" >"$WORK/sabotaged.py"
cp "$DBDIR2/opencode.db" "$WORK/db2.marker"
python3 "$WORK/sabotaged.py" --db "$DBDIR2/opencode.db" --repo "$GR" --since 2026-11-09 \
    --until 2026-11-22 --global-instructions "$WORK/opk-test/global/AGENTS.md" >/dev/null 2>&1
_nw2=$(db_untouched "$DBDIR2/opencode.db" "$WORK/db2.marker" 2>&1)
if [ -n "$_nw2" ]; then
    pass "never-write arm: without mode=ro the same check reds ($_nw2)"
else
    fail "never-write arm: the read-write copy went undetected -- the never-write pin is vacuous"
fi

# --- 2b. M1 pins --------------------------------------------------------------

if grep -qF -- '| 2026-W46 | 2 | 2750 | 2000 | 750 | 1 | 1000 | 700 | 300 |' "$WORK/out.txt"; then
    pass "M1: lead median counts cache tokens (1500 and 4000 -> 2750), uncached and cache read apart"
else
    fail "M1: the 2026-W46 row must read 2 | 2750 | 2000 | 750 | 1 | 1000 | 700 | 300 (got: $(grep -F -- '| 2026-W46 |' "$WORK/out.txt" | tr '\n' ' '))"
fi
if grep -qF -- '| 2026-W47 | 1 | 5000 | 5000 | 0 | 1 | 100 | 100 | 0 |' "$WORK/out.txt"; then
    pass "M1: the FIRST assistant message only (99999 of the later message does not leak)"
else
    fail "M1: the 2026-W47 row must read 1 | 5000 | 5000 | 0 | 1 | 100 | 100 | 0 (got: $(grep -F -- '| 2026-W47 |' "$WORK/out.txt" | tr '\n' ' '))"
fi
if grep -qF -- '| 2026-W45 | 0 | - | - | - | 0 | - | - | - |' "$WORK/out.txt"; then
    pass "M1: a week without repo sessions renders an empty row, not a gap"
else
    fail "M1: the session-less 2026-W45 row must read 0 | - | - | - | 0 | - | - | -"
fi
if grep -qF -- '| 2026-W46 | 3 | 2 | 2 | 2 | 1 |' "$WORK/out.txt" &&
    grep -qF -- '| 2026-W47 | 2 | 0 | 0 | 0 | 1 |' "$WORK/out.txt"; then
    pass "excluded table: workspace-level, ancestor, no-own, no-record and broken-record sessions counted, not measured"
else
    fail "excluded table: expected | 2026-W46 | 3 | 2 | 2 | 2 | 1 | and | 2026-W47 | 2 | 0 | 0 | 0 | 1 |"
fi
if grep -qF -- '8000' "$WORK/out.txt"; then
    fail "excluded sessions: a token figure of an excluded session appeared verbatim (8000)"
else
    pass "excluded sessions: none of their token figures appears verbatim (the exact-row pins above are the discriminators)"
fi

# --- 2c. M2 pins --------------------------------------------------------------

if grep -qF -- "| 2026-W45 | 2026-11-08 | $SHA_A | 100 | 50 | 150 | 2 |" "$WORK/out.txt" &&
    grep -qF -- "| 2026-W46 | 2026-11-15 | $SHA_B | 300 | 75 | 375 | 5 |" "$WORK/out.txt" &&
    grep -qF -- "| 2026-W47 | 2026-11-22 | $SHA_B | 300 | 75 | 375 | 5 |" "$WORK/out.txt"; then
    pass "M2: weekly state from git history (subdirectory .md and non-RM files not counted)"
else
    fail "M2: expected W45=A 100|50|150|2 and W46+W47=B 300|75|375|5 (got: $(grep -E '^\| 2026-W[0-9]+ \| 2026-' "$WORK/out.txt" | tr '\n' ' '))"
fi
if grep -qF -- "| 2026-W47 | 2026-11-22 | $SHA_B | 300 | 75 | 375 | 5 |" "$WORK/out.txt" &&
    grep -qF -- "| HEAD | 2026-11-24 | $SHA_M | 400 | 75 | 475 | 5 |" "$WORK/out.txt"; then
    pass "M2: a side-branch commit merged after a week's end does not move that week (first-parent chain)"
else
    fail "M2: W47 must stay at B (300 bytes) while HEAD shows the merge (400 bytes) -- got: $(grep -E '^\| (2026-W47|HEAD) \| 2026-' "$WORK/out.txt" | tr '\n' ' ')"
fi
if grep -qF -- 'Sessions: `opk-test` in' "$WORK/out.txt"; then
    pass "default --match derives from the origin remote's repository name"
else
    fail "default --match must derive opk-test from the origin remote"
fi

# in-progress week and a week without any commit touching the paths
python3 "$SCRIPT" --db "$DBDIR/opencode.db" --repo "$GR" --since 2026-10-19 --until 2026-11-20 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >"$WORK/out2.txt" 2>/dev/null
if grep -qF -- "| 2026-W47 | 2026-11-20 (in progress) | $SHA_B | 300 | 75 | 375 | 5 |" "$WORK/out2.txt" &&
    grep -qF -- '| 2026-W43 | 2026-10-25 | none | n/a | n/a | n/a | n/a |' "$WORK/out2.txt"; then
    pass "M2: the open week is marked in progress; a week before the first commit reads n/a"
else
    fail "M2: in-progress / n/a rows missing (got: $(grep -E '^\| (2026-W4[347]|HEAD) \| 2026-' "$WORK/out2.txt" | tr '\n' ' '))"
fi

# --- 2d. table shape ----------------------------------------------------------

# GitHub renders a table only when the header row and the delimiter row
# carry the same number of cells; a ragged table degrades to one
# paragraph. (The M1 table shipped with 8 delimiter cells under a
# 9-cell header and rendered as prose on GitHub.) The content pins
# above grep rows and cannot see that -- this check reads the shape.
table_shape() { # $1 = markdown file -> FAIL rows on stdout (empty = every table is rectangular)
    awk '
        function cells(line, n) { n = split(line, parts, "|"); return n - 2 }
        /^\|/ {
            if (!intable) { intable = 1; want = cells($0); header = NR; next }
            if (cells($0) != want)
                printf "FAIL %s: table at line %d has %d header cells, line %d has %d\n", FILENAME, header, want, NR, cells($0)
            next
        }
        { intable = 0 }
    ' "$1"
}

_ts_rows=$(table_shape "$WORK/out.txt")
if [ -z "$_ts_rows" ]; then
    pass "tables: every table of the snapshot is rectangular (header, delimiter and rows share one cell count)"
else
    fail "tables: $_ts_rows"
fi
printf '%s\n' '| a | b |' '|---|---|---|' '| 1 | 2 | 3 |' '' '| x | y |' '|---|---|' '| 1 | 2 |' >"$WORK/shape.md"
_ts_arm=$(table_shape "$WORK/shape.md")
case $_ts_arm in
    "FAIL $WORK/shape.md: table at line 1 has 2 header cells, line 2 has 3"*"line 3 has 3") pass "tables arm: a ragged table is flagged, a rectangular one is not" ;;
    *) fail "tables arm: the ragged fixture must be flagged and the rectangular one left alone (got: $_ts_arm)" ;;
esac

# --- 2e. fail-loud arms -------------------------------------------------------

_ms_rc=0
python3 "$SCRIPT" --db "$WORK/no-such.db" --repo "$GR" >/dev/null 2>"$WORK/err2.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 2 ] && grep -qF -- 'database not found: ' "$WORK/err2.txt"; then
    pass "fail-loud: a missing database exits 2 and names it"
else
    fail "fail-loud: a missing database must exit 2 and name it (rc=$_ms_rc err=$(cat "$WORK/err2.txt"))"
fi

printf 'not a database\n' >"$WORK/garbage.db"
_ms_rc=0
python3 "$SCRIPT" --db "$WORK/garbage.db" --repo "$GR" --since 2026-11-09 --until 2026-11-22 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >/dev/null 2>"$WORK/err3.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 2 ] && grep -qF -- 'cannot open ' "$WORK/err3.txt"; then
    pass "fail-loud: a file that is no database exits 2 and says so"
else
    fail "fail-loud: a non-database must exit 2 (rc=$_ms_rc err=$(cat "$WORK/err3.txt"))"
fi

python3 - "$WORK/short.db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE session_v2 (id TEXT)")
con.commit()
PY
_ms_rc=0
python3 "$SCRIPT" --db "$WORK/short.db" --repo "$GR" --since 2026-11-09 --until 2026-11-22 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >/dev/null 2>"$WORK/err4.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 2 ] && grep -qF -- 'lacks the table(s) ' "$WORK/err4.txt"; then
    pass "fail-loud: a database without the session tables exits 2 and names them"
else
    fail "fail-loud: an incomplete schema must exit 2 (rc=$_ms_rc err=$(cat "$WORK/err4.txt"))"
fi

# a window without any repo session prints the tables and exits 1
_ms_rc=0
python3 "$SCRIPT" --db "$DBDIR/opencode.db" --repo "$GR" --since 2026-10-05 --until 2026-10-06 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >"$WORK/out3.txt" 2>"$WORK/err5.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 1 ] && grep -qF -- 'no repo session found since 2026-10-05' "$WORK/err5.txt" &&
    grep -qF -- '## M1 - boot context' "$WORK/out3.txt"; then
    pass "fail-loud: no repo session in the window exits 1, tables still printed"
else
    fail "fail-loud: an empty selection must exit 1 with a named warning (rc=$_ms_rc err=$(cat "$WORK/err5.txt"))"
fi

_ms_rc=0
python3 "$SCRIPT" --db "$DBDIR/opencode.db" --repo "$GR" --since 2026-13-40 \
    --global-instructions "$WORK/opk-test/global/AGENTS.md" >/dev/null 2>"$WORK/err6.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 2 ] && grep -qF -- '--since expects YYYY-MM-DD' "$WORK/err6.txt"; then
    pass "fail-loud: a malformed date exits 2 and names the flag"
else
    fail "fail-loud: a malformed --since must exit 2 (rc=$_ms_rc err=$(cat "$WORK/err6.txt"))"
fi

# a repository without an origin remote cannot derive --match
mkdir -p "$WORK/noremote"
git -C "$WORK/noremote" init -q
GIT_COMMITTER_DATE="2026-11-12 12:00:00" git -C "$WORK/noremote" -c user.name=t \
    -c user.email=t@e commit -q --allow-empty -m x
_ms_rc=0
python3 "$SCRIPT" --db "$DBDIR/opencode.db" --repo "$WORK/noremote" --since 2026-11-09 \
    --until 2026-11-22 --global-instructions "$WORK/opk-test/global/AGENTS.md" >/dev/null 2>"$WORK/err7.txt" || _ms_rc=$?
if [ "$_ms_rc" -eq 2 ] && grep -qF -- 'no origin remote in ' "$WORK/err7.txt"; then
    pass "fail-loud: no origin remote and no --match exits 2 and says what to pass"
else
    fail "fail-loud: a missing origin must exit 2 without --match (rc=$_ms_rc err=$(cat "$WORK/err7.txt"))"
fi

# --- 2f. documented command blocks (agent/docs-loop.md) -----------------------
# The trigger check and the sweep list are run by hand from the page's
# fenced blocks; a block that fails open turns an API error into a
# count. Both blocks are extracted from the page AS WRITTEN and run
# under a stubbed gh, so an edit that breaks a failure path or the
# count reds here. No network: the stub answers for gh. It reads none
# of gh's arguments -- the list-side jq programs and the label filter of
# the trigger block are not exercised here (PR #769 round b, F1).

doc_block() { # $1 = heading text -> the first fenced sh block after it
    awk -v h="$1" '
        index($0, h) { f = 1 }
        f && /^```sh$/ { b = 1; next }
        b && /^```$/ { exit }
        b { print }
    ' "$REPO_ROOT/agent/docs-loop.md"
}
doc_block "## Counting sessions" >"$WORK/trigger-block.sh"
doc_block "## Hygiene" >"$WORK/sweep-block.sh"
if [ -s "$WORK/trigger-block.sh" ] && [ -s "$WORK/sweep-block.sh" ]; then
    pass "docs blocks: both fenced blocks extracted from agent/docs-loop.md"
else
    fail "docs blocks: extraction empty -- heading or fence drift in agent/docs-loop.md"
fi
if sh -n "$WORK/trigger-block.sh" && sh -n "$WORK/sweep-block.sh"; then
    pass "docs blocks: both parse as shell"
else
    fail "docs blocks: a fenced block of agent/docs-loop.md does not parse (sh -n)"
fi

mkdir -p "$WORK/ghstub"
cat >"$WORK/ghstub/gh" <<'EOF'
#!/bin/sh
# stub for the documented blocks: $1 = issue, $2 = list|view, $5 = number
case "$FAKE_MODE" in
    listfail) echo "gh: HTTP 403: rate limit" >&2; exit 1 ;;
esac
if [ "$2" = list ]; then
    [ "$FAKE_MODE" = empty ] && exit 0
    printf '7 from-reflection,prio:med\n8 from-reflection,prio:high\n'
    exit 0
fi
if [ "$FAKE_MODE" = viewfail ]; then
    echo "gh: issue $5 not found (HTTP 404)" >&2
    exit 1
fi
case "$5" in
    7) printf 'body line\nSession: ses_AAA\n'; printf 'Confirmed\nSession: ses_BBB\n'; printf 'dup\n  Session: ses_AAA\n' ;;
    8) printf 'Session: ses_CCC\n' ;;
esac
EOF
chmod 755 "$WORK/ghstub/gh"

run_trigger() { # $1 = gh mode -> stdout/stderr in $WORK/t.out / $WORK/t.err
    FAKE_MODE="$1" PATH="$WORK/ghstub:$PATH" sh "$WORK/trigger-block.sh" >"$WORK/t.out" 2>"$WORK/t.err"
}
run_trigger listfail
if grep -qF -- 'TRIGGER CHECK FAILED' "$WORK/t.err" && ! grep -qF -- 'sessions=' "$WORK/t.out"; then
    pass "trigger block: an unreadable issue list says so and prints no count"
else
    fail "trigger block: a failed issue list must say so and print no count (out=$(tr '\n' '|' <"$WORK/t.out") err=$(tr '\n' '|' <"$WORK/t.err"))"
fi
run_trigger empty
if grep -qxF -- 'no unpromoted reflection issue is open' "$WORK/t.out"; then
    pass "trigger block: an empty intake is said, not left silent"
else
    fail "trigger block: an empty issue list must be said (out=$(tr '\n' '|' <"$WORK/t.out"))"
fi
run_trigger viewfail
if grep -qF -- '#7: FETCH FAILED' "$WORK/t.err" && grep -qF -- '#8: FETCH FAILED' "$WORK/t.err" &&
    ! grep -qF -- 'sessions=' "$WORK/t.out"; then
    pass "trigger block: an issue that cannot be fetched is marked, never counted as zero"
else
    fail "trigger block: a failed issue fetch must be marked and not counted (out=$(tr '\n' '|' <"$WORK/t.out") err=$(tr '\n' '|' <"$WORK/t.err"))"
fi
run_trigger ok
if grep -qxF -- '#7 [from-reflection,prio:med] sessions=2' "$WORK/t.out" &&
    grep -qxF -- '#8 [from-reflection,prio:high] sessions=1' "$WORK/t.out"; then
    pass "trigger block: distinct session ids counted (an indented duplicate is one session)"
else
    fail "trigger block: expected #7 sessions=2 and #8 sessions=1 (got: $(tr '\n' '|' <"$WORK/t.out"))"
fi

FAKE_MODE=listfail PATH="$WORK/ghstub:$PATH" sh "$WORK/sweep-block.sh" >"$WORK/s.out" 2>"$WORK/s.err"
if grep -qF -- 'SWEEP FAILED' "$WORK/s.err" && [ ! -s "$WORK/s.out" ]; then
    pass "sweep block: an unreadable candidate list says so"
else
    fail "sweep block: a failed issue list must say so (out=$(tr '\n' '|' <"$WORK/s.out") err=$(tr '\n' '|' <"$WORK/s.err"))"
fi

# The sweep's jq expression dates a candidate by its last CONFIRMING
# comment (one with a Session: line), not by the last comment of any
# author. Host-dependent pin: jq is not a suite requirement -- without
# it the pin is skipped and says so, it never passes silently.
if command -v jq >/dev/null 2>&1; then
    awk -v q="-q '" 'index($0, q) { f = 1; $0 = substr($0, index($0, q) + length(q)) }
        f { if (sub(/\047 \|\|$/, "")) { print; exit } print }' "$WORK/sweep-block.sh" >"$WORK/sweep.jq"
    cat >"$WORK/sweep.json" <<'EOF'
[{"number":9,"createdAt":"2026-08-01T10:00:00Z","labels":[{"name":"from-reflection"}],"comments":[
  {"createdAt":"2026-08-05T10:00:00Z","body":"Confirmed\nSession: ses_abc123"},
  {"createdAt":"2026-11-20T10:00:00Z","body":"Maintainer note (no session line)"}]},
 {"number":10,"createdAt":"2026-09-01T10:00:00Z","labels":[{"name":"research-candidate"}],"comments":[]},
 {"number":11,"createdAt":"2026-09-01T10:00:00Z","labels":[{"name":"from-reflection"},{"name":"promoted"}],"comments":[]}]
EOF
    jq -r -f "$WORK/sweep.jq" "$WORK/sweep.json" >"$WORK/sweep.out" 2>"$WORK/sweep.err"
    if [ "$(wc -l <"$WORK/sweep.out" | tr -d ' ')" -eq 2 ] &&
        grep -qF -- '#9 [from-reflection] filed 2026-08-01T10:00:00Z last-session 2026-08-05T10:00:00Z' "$WORK/sweep.out" &&
        grep -qF -- '#10 [research-candidate] filed 2026-09-01T10:00:00Z last-session 2026-09-01T10:00:00Z' "$WORK/sweep.out"; then
        pass "sweep block: the last confirming comment dates a candidate (a later note does not); a promoted issue is left out"
    else
        fail "sweep block: the jq expression must date #9 by its confirming comment and drop the promoted #11 (got: $(tr '\n' '|' <"$WORK/sweep.out") $(cat "$WORK/sweep.err"))"
    fi
else
    echo "  pin skipped: the sweep jq expression was not exercised -- jq is not installed here (host-dependent)"
fi

# --- summary gate --------------------------------------------------------------
suite_done "docs-loop tests"
