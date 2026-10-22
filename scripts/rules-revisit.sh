#!/bin/sh
# rules-revisit.sh -- record a rule-meta revisit (rollout phase 4)
#
# The mechanical half of a revisit (internal/records/rules-meta.md,
# "Revisit workflow"). The judgment half is the agent's: read the
# rationale, run its Check: probe where present, decide whether the
# external fact still holds. Then record the outcome:
#
#   sh scripts/rules-revisit.sh RM-NNNN clean    ["note"]
#   sh scripts/rules-revisit.sh RM-NNNN findings "what no longer holds"
#
#   clean     -- the rationale holds; the ladder goes up one step
#                (1m -> 6m -> 1y -> 2y; 2y is the max, a clean
#                revisit at 2y stays 2y)
#   findings  -- the rationale no longer holds as stated; the
#                interval resets to 1m and the finding enters the
#                normal fix flow (rule text, rationale, or both)
#
# next-revisit is computed from the REVISIT date, never from the
# stale due date -- lateness must not compound. Interval
# math is calendar-correct with end-of-month clamp (Jan 31 + 1m ->
# Feb 28), via python3 stdlib (required contributor tool,
# tests/check-host.sh).
#
# The meta's review log gains exactly one line ("- DATE revisit
# clean/findings -- ..."). A revisit log line is NOT an approval:
# the reviewed: field stays with the maintainer (the audit's
# invariant 9 pairs approvals only). Nothing else in the file is
# touched, and the rewrite lands only after every field change was
# validated (fail-loud, no partial writes).
#
# Exit: 0 -- recorded. 1 -- domain refusal (unknown meta, retired
# meta). 2 -- usage or environment error (bad arguments, note
# shape, missing python3).
#
# Env: RM_AUDIT_ROOT (revisit a meta in another tree -- tests),
# FORCE_TODAY (pin the revisit date -- tests), RULES_PYTHON
# (python interpreter, default python3).

set -u

PY=${RULES_PYTHON:-python3}

die() { echo "rules-revisit: $*" >&2; exit 2; }
refuse() { echo "rules-revisit: $*" >&2; exit 1; }

if [ -n "${RM_AUDIT_ROOT:-}" ]; then
    ROOT=$(cd -- "$RM_AUDIT_ROOT" && pwd) || die "cannot enter RM_AUDIT_ROOT"
else
    ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd) || die "cannot locate repo root"
fi
TODAY=${FORCE_TODAY:-$(date +%F)}
METAS=internal/rules-meta

case $# in
    2 | 3) ;;
    *) die "usage: sh scripts/rules-revisit.sh RM-NNNN clean|findings [note]" ;;
esac
ID=$1
VERDICT=$2
NOTE=${3:-}

case $ID in
    RM-[0-9][0-9][0-9][0-9]) ;;
    *) die "bad id '$ID' (want RM-NNNN)" ;;
esac
case $VERDICT in
    clean | findings) ;;
    *) die "verdict must be clean or findings, got '$VERDICT'" ;;
esac
if [ "$VERDICT" = findings ] && [ -z "$NOTE" ]; then
    die "findings needs a note saying what no longer holds"
fi
NL='
'
case $NOTE in
    *"$NL"*) die "note must be single-line" ;;
esac
command -v "$PY" >/dev/null 2>&1 || die \
    "$PY unavailable -- python3 is a required contributor tool" \
    "(sh tests/check-host.sh); override via RULES_PYTHON"

digs=${ID#RM-}
b1=$(printf '%s' "$digs" | cut -c1)
b2=$(printf '%s' "$digs" | cut -c2)
b3=$(printf '%s' "$digs" | cut -c3)
META=$ROOT/$METAS/$b1/$b2/$b3/$ID.md
[ -f "$META" ] || refuse "no meta $ID at $METAS/$b1/$b2/$b3/$ID.md"

fm() {  # frontmatter value of $1 ('' when absent)
    sed -n '2,/^---$/p' "$META" | sed -n "s/^$1:[[:space:]]*//p" | head -1
}
st=$(fm status)
iv=$(fm revisit-interval)
[ "$st" = active ] || refuse \
    "$ID is $st -- retired metas are outside the revisit cycle"
case $iv in
    1m | 6m | 1y | 2y) ;;
    *) die "$ID: bad revisit-interval '$iv' (run the audit)" ;;
esac

case "$VERDICT-$iv" in
    clean-1m) NEW=6m; N=6; U=m ;;
    clean-6m) NEW=1y; N=1; U=y ;;
    clean-1y) NEW=2y; N=2; U=y ;;
    clean-2y) NEW=2y; N=2; U=y ;;
    findings-*) NEW=1m; N=1; U=m ;;
esac

# from the REVISIT date, calendar-correct, month-end clamped
NEXT=$("$PY" - "$TODAY" "$N" "$U" <<'PYEOF'
import sys
from datetime import date

start = date.fromisoformat(sys.argv[1])
n = int(sys.argv[2])
unit = sys.argv[3]
y, m = start.year, start.month
if unit == "m":
    m += n
else:
    y += n
y += (m - 1) // 12
m = (m - 1) % 12 + 1
leap = y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
last = (31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[m - 1]
print(date(y, m, min(start.day, last)).isoformat())
PYEOF
) || die "next-revisit computation failed for '$TODAY'"

grep -q '^## Review log$' "$META" || die "$ID: no '## Review log' section"

if [ "$VERDICT" = clean ]; then
    [ -z "$NOTE" ] && NOTE='rationale holds'
    LOG="$TODAY revisit clean — $NOTE (interval $iv -> $NEW, next $NEXT)."
else
    LOG="$TODAY revisit findings — $NOTE (interval reset to 1m from $iv, next $NEXT)."
fi

# rewrite: both frontmatter fields replaced exactly once, log line
# appended, everything validated BEFORE the file is swapped in
TMP=$(mktemp "${META}.tmp.XXXXXX") || die "mktemp failed"
trap 'rm -f "$TMP"' EXIT
awk -v iv="revisit-interval: $NEW" -v nr="next-revisit: $NEXT" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { fm = 0; print; next }
    fm && /^revisit-interval:/ { print iv; c1++; next }
    fm && /^next-revisit:/ { print nr; c2++; next }
    { print }
    END { if (c1 != 1 || c2 != 1) exit 3 }
' "$META" > "$TMP" || { rm -f "$TMP"; die "$ID: frontmatter fields not found exactly once"; }
printf '%s\n' "- $LOG" >> "$TMP"

sed -n '2,/^---$/p' "$TMP" | grep -qx "revisit-interval: $NEW" \
    || { rm -f "$TMP"; die "$ID: rewrite check failed (revisit-interval)"; }
sed -n '2,/^---$/p' "$TMP" | grep -qx "next-revisit: $NEXT" \
    || { rm -f "$TMP"; die "$ID: rewrite check failed (next-revisit)"; }
[ "$(tail -n 1 "$TMP")" = "- $LOG" ] \
    || { rm -f "$TMP"; die "$ID: rewrite check failed (log line)"; }

mv -f "$TMP" "$META" || die "cannot update $META"

echo "$ID: $VERDICT — interval $iv -> $NEW, next-revisit $NEXT" \
    "(from revisit date $TODAY); review log +1 line"
