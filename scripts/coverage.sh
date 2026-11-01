#!/bin/sh
# coverage.sh — kcov line-coverage report over the unit suites (issue #255,
# stage 0b). Dev tool (world B): never shipped, not a contributor-host gate,
# and deliberately no coverage-percentage ratchet — stage 0b produces a
# report artifact, it does not gate anything.
#
# How it works:
#   - kcov runs each unit suite unmodified, one kcov process per suite
#     (kcov's default PS4/xtrace method — child `sh ...` processes inherit
#     the trace via BASH_ENV/BASH_XTRACEFD), then merges the per-suite
#     reports into one tree.
#   - A PATH shim resolves `sh` to bash for the run: dash does not expand
#     kcov's PS4 marker, so child shells must be bash. The kit is strict
#     POSIX and runs under bash unchanged (validated over the whole suite
#     family; one dash-only test delta tracks in issue #342).
#   - The one known method conflict is the kit's `set -eu` idiom inside
#     `bash -c` blocks: kcov's PS4 expands ${BASH_SOURCE}, which aborts
#     under `set -u` (unbound variable). Affected test blocks carry a
#     one-line PS4 shield (`PS4="+ "`). Repro and measurements:
#     internal/records/kcov-coverage.md.
#   - Attribution is by executed file path: everything running in a bash
#     process maps into the report (sourced libs, `sh <repo-path>`
#     invocations, and scripts suites copy into scratch count under the
#     path they were executed at — kcov cannot map copies back to the
#     source tree). Coverage here complements the e2e suites; it does not
#     replace them.
#
# Requirements: docker (ONCE, to extract the digest-pinned kcov binary into
# ~/.cache/opk-kcov/), python3 for the summary, plus whatever the suites
# themselves need. No sudo, no host installs, nothing written in the repo.
#
# Usage:
#   scripts/coverage.sh                # all eligible suites
#   scripts/coverage.sh test-log       # suites whose name matches a substring
#
# Output: merged HTML + cobertura.xml under $COVERAGE_OUT (default
# /tmp/opk-kcov-coverage), summary table on stdout. Exit is non-zero when
# any suite FAILS under the run (fail loud) — never because of a percentage.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"

die() {
    echo "error: $*" >&2
    exit 1
}

# COVERAGE_OUT is resolved to an ABSOLUTE path against the CALLER's cwd
# before anything else happens (#343 a A1): a relative value used to be
# interpreted once for the scratch setup and again — now relative to the
# repo — for every later use, either littering the repo (violating the
# contract below) or misdiagnosing every suite as failed. The runner's
# contract is "nothing written in the repo", so an OUT inside it is
# refused outright (#343 a A1 shape a).
OUT="${COVERAGE_OUT:-/tmp/opk-kcov-coverage}"
case "$OUT" in
    /*) ;;
    *) OUT="$(pwd)/$OUT" ;;
esac
case "$OUT/" in
    "$REPO"/*) die "COVERAGE_OUT must live outside the repo ($REPO) — got $OUT" ;;
esac

# Digest-pinned (the last versioned tag, v42, is Debian 11 with archived
# apt repos and cannot even install git anymore — see the record). To bump:
# pull a newer kcov/kcov image, re-run this script end to end, re-read the
# record's validation checklist, then pin the new digest here.
KCOV_IMAGE="kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603"
KCOV_DIR="$HOME/.cache/opk-kcov/kcov-${KCOV_IMAGE##*:}"

# Suites excluded from the coverage run. Every entry needs an open issue
# that names the delta and tracks the fix; lift the entry when it closes.
#   test-ddev-as-opencode.sh — one stamp pin is dash-only under bash (#342)
EXCLUDED="test-ddev-as-opencode.sh"

# --- 1. kcov binary: extract once from the digest-pinned image -------------
if [ ! -x "$KCOV_DIR/bin/kcov" ]; then
    command -v docker >/dev/null 2>&1 ||
        die "docker not found — kcov is extracted from its image once into ~/.cache/opk-kcov; retry on a host with docker"
    mkdir -p "$KCOV_DIR" || die "cannot create $KCOV_DIR"
    cid="$(docker create "$KCOV_IMAGE")" || die "docker create $KCOV_IMAGE failed"
    if ! docker cp "$cid":/usr/local/bin/. "$KCOV_DIR/bin"; then
        docker rm "$cid" >/dev/null 2>&1
        die "docker cp of the kcov binary failed"
    fi
    docker rm "$cid" >/dev/null 2>&1
fi
KCOV="$KCOV_DIR/bin/kcov"
"$KCOV" --version >/dev/null 2>&1 ||
    die "$KCOV does not run on this host (missing shared libs?) — internal/records/kcov-coverage.md"

# --- 2. scratch: out dirs + the sh->bash PATH shim --------------------------
# Scratch cleanup is stamp-guarded (#343 a A2): rm -rf on the four child
# names must never run under an OUT the runner does not own — a
# COVERAGE_OUT pointing at a live directory (say $HOME) would otherwise
# delete its runs/logs/merged/shim children. A fresh or empty OUT is
# adopted and stamped; a non-empty dir WITHOUT our stamp is refused loud
# (an out dir from a pre-stamp run counts as foreign — pick a fresh one).
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ] && [ ! -f "$OUT/.opk-kcov-out" ]; then
    die "refusing to clean $OUT: non-empty and not opk-kcov stamped — use an empty or fresh COVERAGE_OUT"
fi
mkdir -p "$OUT" || die "cannot create $OUT"
: >"$OUT/.opk-kcov-out" || die "cannot stamp $OUT"
rm -rf "${OUT:?}/runs" "${OUT:?}/logs" "${OUT:?}/merged" "${OUT:?}/shim"
mkdir -p "$OUT/runs" "$OUT/logs" "$OUT/shim" || die "cannot set up $OUT"
# Quoted heredoc on purpose: the wrapper must survive every shell layer
# verbatim (a double-quoted printf variant once let the outer shell expand
# "$@" away — every shimmed child broke; see the record).
cat >"$OUT/shim/sh" <<'EOF'
#!/bin/bash
exec /usr/bin/bash "$@"
EOF
chmod +x "$OUT/shim/sh"

# --- 3. run every eligible suite under kcov ---------------------------------
# kcov's bash engine only traces when the script-under-test is passed as a
# RELATIVE path (an absolute argv yields a green run with an empty report —
# measured, see the record), so this loop runs from the repo root.
cd "$REPO" || die "cannot cd to $REPO"
filter="${1:-}"
fails=""
count=0
for suite in tests/unit/test-*.sh; do
    name="${suite##*/}"
    skip=""
    for x in $EXCLUDED; do
        [ "$x" = "$name" ] && skip="excluded (see scripts/coverage.sh)"
    done
    if [ -n "$skip" ]; then
        echo "SKIP  $name — $skip"
        continue
    fi
    case "$name" in
        *"$filter"*) ;;
        *) continue ;;
    esac
    if PATH="$OUT/shim:$PATH" "$KCOV" \
        --include-pattern="$REPO/files/,$REPO/scripts/" \
        "$OUT/runs/$name" "$suite" >"$OUT/logs/$name.log" 2>&1; then
        echo "OK    $name"
    else
        echo "FAIL  $name (rc=$? — log: $OUT/logs/$name.log)"
        fails="$fails $name"
    fi
    count=$((count + 1))
done
[ "$count" -gt 0 ] || die "no suite matched the filter '$filter'"

# --- 4. merge + summary ------------------------------------------------------
REPORT="$OUT/merged"
if [ "$count" -eq 1 ]; then
    # kcov's --merge emits an empty report from a single source (measured,
    # see the record) — with one suite the per-run report IS the merged one.
    run_dir="$(ls -d "$OUT"/runs/* 2>/dev/null || true)"
    REPORT="$run_dir"
else
    "$KCOV" --merge "$OUT/merged" "$OUT"/runs/* >/dev/null 2>&1 ||
        die "merging the per-suite reports failed"
fi

# A report with zero <class> entries means the trace never attached (the
# green-but-empty shape from the absolute-path pitfall) — fail loud instead
# of presenting a plausible-looking 0-line tree.
python3 - "$REPORT" <<'PYEOF' || die "coverage summary failed (empty or malformed report?)"
import glob
import sys
import xml.etree.ElementTree as ET

paths = glob.glob(sys.argv[1] + "/*/cobertura.xml")
rows = []
for p in sorted(paths):
    cand = []
    for cls in ET.parse(p).getroot().iter("class"):
        lines = list(cls.iter("line"))
        if not lines:
            continue
        cov = sum(1 for l in lines if l.get("hits") != "0")
        cand.append((cov, len(lines), cls.get("filename")))
    if cand:
        rows = cand  # first non-empty report wins — summing several would double-count
        break
if not rows:
    sys.exit("no coverage rows found in the merged report")
rows.sort(key=lambda r: (r[0] / r[1], r[2]))
print("")
print("Coverage (executed lines, files/ + scripts/):")
for cov, tot, f in rows:
    print("  %3d%%  %4d/%-4d %s" % (100 * cov // tot, cov, tot, f))
tc = sum(r[0] for r in rows)
tt = sum(r[1] for r in rows)
print("")
print("  TOTAL %d/%d = %.1f%% over %d reported files" % (tc, tt, 100 * tc / tt, len(rows)))
print("")
print("  HTML report: %s/index.html" % sys.argv[1])
PYEOF

[ -z "$fails" ] || die "suite(s) failed under the coverage run:$fails"
echo "coverage run complete."
