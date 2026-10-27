#!/bin/sh
# test-reviews-parity.sh -- generated INDEX <-> case folders + pointer
# integrity over internal/reviews/ (supersedes the review_pointer_check
# that lived in test-docs.sh before the structure wave).
#
#   1. every sharded case folder (A/B/C/D/pr-ABCDE) has exactly one
#      INDEX row, every INDEX row has a folder (both directions)
#   2. regenerating the INDEX reproduces the file byte-for-byte — a
#      hand edit drifts and fails
#   3. every snapshot carries exactly one "> Resolution:" pointer line
#      iff its case has a resolution.md (README rule 1/2)
#   4. status directions (issue #238): the generator derives the INDEX
#      Status column from the resolution's "Status:" line — absent
#      reads open (the silent direction: an unrecorded closure leaves
#      the case open, nothing fails), "Status: closed ..." reads
#      closed. Runs the REAL generator in a scratch tree.
#
# Run: sh tests/unit/test-reviews-parity.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
GENDIR="$(mktemp -d)"
trap 'rm -f "$TMP" "$TMP.gen"; rm -rf "$GENDIR"' EXIT INT TERM

INDEX=internal/reviews/INDEX.md

# 1. folder <-> row parity (rows carry linked keys: | [pr-N](N/N/N/N/pr-N) |)
find internal/reviews -type d -name 'pr-[0-9][0-9][0-9][0-9][0-9]' 2>/dev/null | sed 's|.*/||' | sort > "$TMP.folders"
grep -E '^\| \[pr-[0-9]{5}\]\([0-9](/[0-9]){3}/pr-[0-9]{5}\) \|' "$INDEX" \
    | sed 's/^| \[\(pr-[0-9]\{5\}\)\](\([^)]*\)).*/\1 \2/' > "$TMP.rows"
awk '{ print $1 }' "$TMP.rows" | sort > "$TMP.keys"
# 1b. a row's link target must be the row key's own case folder
awk '{ base = $2; sub(/.*\//, "", base)
       if ($1 != base) printf "FAIL %s: link target %s is not its own folder\n", $1, $2 }' \
    "$TMP.rows" >> "$TMP"
comm -23 "$TMP.folders" "$TMP.keys" | while IFS= read -r k; do
    echo "FAIL $k: folder without INDEX row" >> "$TMP"
done
comm -13 "$TMP.folders" "$TMP.keys" | while IFS= read -r k; do
    echo "FAIL $k: INDEX row without folder" >> "$TMP"
done

# 2. regeneration is byte-identical (hand edits drift)
cp "$INDEX" "$TMP.gen"
python3 scripts/gen-review-index.py > /dev/null 2>&1 || {
    echo "FAIL generator exited non-zero" >> "$TMP"
}
if ! cmp -s "$INDEX" "$TMP.gen"; then
    echo "FAIL INDEX.md is not what the generator produces (hand edit? regenerate)" >> "$TMP"
    cp "$TMP.gen" "$INDEX"   # restore the committed state
fi

# 3. pointer <-> resolution parity
for f in internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-*/review-*.md; do
    [ -e "$f" ] || continue
    d=$(dirname "$f")
    # Guarded count (#260, the #244 f W1 class): grep -c exits 1 on
    # zero matches. This suite runs without set -e, so nothing
    # aborted today — guarded for uniformity with the swept family.
    ptr=$(grep -c '^> Resolution:' "$f" || true)
    if [ -e "$d/resolution.md" ]; then
        [ "$ptr" -eq 1 ] || echo "FAIL $f: resolution exists but $ptr pointer line(s)" >> "$TMP"
    else
        [ "$ptr" -eq 0 ] || echo "FAIL $f: no resolution but $ptr pointer line(s)" >> "$TMP"
    fi
done

# 4. status directions (issue #238) -- the real generator in a scratch
#    tree: one new-style case, resolution without a Status line must
#    read open; with "Status: closed ..." must read closed. Pins the
#    claim the closure rule stands on: the INDEX Status column comes
#    from that one line, and its absence fails nothing.
GENCASE="$GENDIR/internal/reviews/0/0/4/2/pr-00420"
mkdir -p "$GENDIR/scripts" "$GENCASE"
cp scripts/gen-review-index.py "$GENDIR/scripts/"
cat > "$GENCASE/review-a.md" <<'EOF'
<!-- review-meta
ID: pr-00420
Snapshot: a
Subject: status-direction pin case
Scope: wave
Base: v0.0.55 @ 0000000
Diff: 0000000..0000001
Date: 2026-10-24
Reviewer: parity pin
-->
EOF
printf '# Resolution — pr-00420\n\nchain still running; nothing closed yet.\n' \
    > "$GENCASE/resolution.md"
# the word "closed" in fixture 1's prose is LOAD-BEARING: a status()
# regression to substring search must fail the open direction (#241 a S1)
(cd "$GENDIR" && python3 scripts/gen-review-index.py) > /dev/null 2>&1 \
    || echo "FAIL status pin: generator exited non-zero" >> "$TMP"
# Guarded reads (#260, the #244 f W1 class; #280 a S2 — uniformity
# riders, this suite runs without set -e): a missing row must land in
# the case's FAIL arm below, never abort the suite.
row=$(grep 'pr-00420' "$GENDIR/internal/reviews/INDEX.md" || true)
case "$row" in
    *'| open |') ;;
    *) echo "FAIL status pin: no Status line must read open, got: $row" >> "$TMP" ;;
esac
printf '# Resolution — pr-00420\n\nStatus: closed — stop rule met (pin).\n' \
    > "$GENCASE/resolution.md"
(cd "$GENDIR" && python3 scripts/gen-review-index.py) > /dev/null 2>&1 \
    || echo "FAIL status pin: generator exited non-zero (closed)" >> "$TMP"
row=$(grep 'pr-00420' "$GENDIR/internal/reviews/INDEX.md" || true)
case "$row" in
    *'| closed |') ;;
    *) echo "FAIL status pin: Status closed must read closed, got: $row" >> "$TMP" ;;
esac

if [ -s "$TMP" ]; then
    echo "reviews parity: FAILED"
    cat "$TMP"
    exit 1
fi
echo "reviews parity: OK ($(wc -l < "$TMP.rows" | tr -d ' ') index rows, pointers consistent, status directions pinned)"
