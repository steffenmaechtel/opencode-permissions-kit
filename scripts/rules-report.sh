#!/bin/sh
# rules-report.sh -- the rule-meta revisit worklist (rollout phase 4)
#
# Companion to scripts/rules-audit.sh: the audit is the gate, this is
# the worklist. One call answers three questions -- which metas are
# due for a revisit now (overdue, most overdue first), which come due
# within the planning horizon (HORIZON days, default 30, earliest
# first), and which metas still sit in the maintainer approval queue
# (no reviewed: field -- same definition as INDEX.md).
#
# Rows carry the meta id, the due date, the current interval and the
# rule back-reference -- enough to pick the next revisit without
# opening files.
#
# Exit codes: 0 -- report produced. Overdue work does NOT change the
# exit code: an overdue meta is a maintenance signal, not a broken
# build; CI stays governed by the audit alone. 2 -- usage
# or environment error (bad HORIZON, missing meta tree, missing
# python3); the report never prints a partial worklist.
#
# Retired metas are outside the revisit cycle and never appear in the
# overdue/horizon lanes; they may still appear in the
# approval queue -- a retired meta that was never approved keeps a
# pending review log, and the INDEX reports it the same way.
#
# Env: RM_AUDIT_ROOT (report on another tree -- tests), FORCE_TODAY
# (pin the date), HORIZON (day count, default 30), RULES_PYTHON
# (python interpreter, default python3).
#
# Date math runs through python3 (stdlib only, calendar-correct,
# portable beyond GNU date) -- python3 is a required contributor
# tool (tests/check-host.sh).

set -u

PY=${RULES_PYTHON:-python3}

die() {
    echo "rules-report: $*" >&2
    exit 2
}

if [ -n "${RM_AUDIT_ROOT:-}" ]; then
    ROOT=$(cd -- "$RM_AUDIT_ROOT" && pwd) || die "cannot enter RM_AUDIT_ROOT"
else
    ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd) || die "cannot locate repo root"
fi
TODAY=${FORCE_TODAY:-$(date +%F)}
HORIZON=${HORIZON:-30}
METAS=internal/rules-meta

case $HORIZON in
    '' | *[!0-9]*) die "HORIZON must be a day count, got '$HORIZON'" ;;
esac
[ -d "$ROOT/$METAS" ] || die "no meta tree at $ROOT/$METAS"
command -v "$PY" >/dev/null 2>&1 || die \
    "$PY unavailable -- python3 is a required contributor tool" \
    "(sh tests/check-host.sh); override via RULES_PYTHON"

UNTIL=$(
    "$PY" - "$TODAY" "$HORIZON" <<'PYEOF'
import datetime
import sys
day = datetime.date.fromisoformat(sys.argv[1])
print((day + datetime.timedelta(days=int(sys.argv[2]))).isoformat())
PYEOF
) || die "horizon date computation failed for '$TODAY' + ${HORIZON}d"

WORK=$(mktemp -d /tmp/rules-report.XXXXXX) || die "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
ACT=$WORK/active
: >"$ACT"
PEND=$WORK/pending
: >"$PEND"

# #232: find errors are loud -- a partially unreadable meta tree dies
# BEFORE any lane prints (the report never prints a partial worklist);
# find's own stderr names the unreadable path.
find "$ROOT/$METAS" -type f -name 'RM-*.md' 2>"$WORK/finderr" |
    LC_ALL=C sort >"$WORK/files"
if [ -s "$WORK/finderr" ]; then
    sed 's/^/rules-report: find error: /' "$WORK/finderr" >&2
    die "find reported errors under $METAS -- the worklist would be partial, no report printed"
fi
[ -s "$WORK/files" ] || die "no metas found under $METAS"

date_ok() { # ISO + plausible ranges (same shape as rules-audit.sh)
    case $1 in
        [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
        *) return 1 ;;
    esac
    _m=${1#*-}
    _m=${_m%%-*}
    _d=${1##*-}
    [ "$_m" -ge 1 ] && [ "$_m" -le 12 ] && [ "$_d" -ge 1 ] && [ "$_d" -le 31 ]
}

while IFS= read -r m; do
    fm() { # frontmatter value of $1 ('' when absent)
        sed -n '2,/^---$/p' "$m" | sed -n "s/^$1:[[:space:]]*//p" | head -1
    }
    id=$(fm id)
    st=$(fm status)
    [ -n "$id" ] || die "$m: no id in frontmatter (run the audit)"
    case $st in
        active | retired) ;;
        *) die "$m: bad status '$st' (run the audit)" ;;
    esac
    # approval queue: same membership rule as INDEX.md (no reviewed:)
    [ -z "$(fm reviewed)" ] && printf '%s\n' "$id" >>"$PEND"
    [ "$st" = active ] || continue
    iv=$(fm revisit-interval)
    nr=$(fm next-revisit)
    case $iv in
        1m | 6m | 1y | 2y) ;;
        *) die "$m: bad revisit-interval '$iv' (run the audit)" ;;
    esac
    date_ok "$nr" || die "$m: active meta without ISO next-revisit '$nr'"
    printf '%s\t%s\t%s\t%s\n' "$nr" "$id" "$iv" "$(fm rule)" >>"$ACT"
done <"$WORK/files"

LC_ALL=C sort "$ACT" >"$WORK/act.s" && mv "$WORK/act.s" "$ACT"
n_all=$(wc -l <"$WORK/files" | tr -d ' ')
n_act=$(wc -l <"$ACT" | tr -d ' ')
n_pend=$(wc -l <"$PEND" | tr -d ' ')

awk -F'\t' -v t="$TODAY" '$1 < t' "$ACT" >"$WORK/od"
awk -F'\t' -v t="$TODAY" -v u="$UNTIL" '$1 >= t && $1 <= u' "$ACT" \
    >"$WORK/hz"
n_od=$(wc -l <"$WORK/od" | tr -d ' ')
n_hz=$(wc -l <"$WORK/hz" | tr -d ' ')

echo "rule-meta revisit report — $TODAY · horizon ${HORIZON}d" \
    "(until $UNTIL) · $n_all metas ($n_act active," \
    "$((n_all - n_act)) retired)"

echo "overdue: $n_od"
awk -F'\t' '{ printf "  %s  due %s  %s  %s\n", $2, $1, $3, $4 }' "$WORK/od"

echo "due within the horizon ($TODAY..$UNTIL): $n_hz"
awk -F'\t' '{ printf "  %s  due %s  %s  %s\n", $2, $1, $3, $4 }' "$WORK/hz"

echo "review-pending (approval queue): $n_pend"
sed 's/^/  /' "$PEND"

next_after=$(awk -F'\t' -v u="$UNTIL" '$1 > u { print $1 " (" $2 ")"; exit }' \
    "$ACT")
echo "next due after the horizon: ${next_after:-none}"
