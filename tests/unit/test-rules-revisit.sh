#!/bin/sh
# test-rules-revisit.sh -- pins the phase-4 revisit workflow:
# scripts/rules-report.sh (the worklist) and scripts/rules-revisit.sh
# (the mechanical revisit record).
#
# Report pins: the real tree stays green; a scratch tree lists the
# right metas per lane (overdue first, horizon window, approval
# queue); the due-TODAY boundary counts as horizon, not overdue;
# HORIZON overrides discriminate; retired metas never enter the
# revisit lanes; usage/env arms fail loud (bad HORIZON, missing
# python interpreter).
#
# Revisit pins: clean bumps the ladder and computes the next date
# from the REVISIT date -- never from the stale due date;
# 2y is the max; findings resets to 1m and requires a note; notes
# stay single-line; unknown and retired metas are refused; month
# arithmetic clamps at month end (Jan 31 + 1m -> Feb 28); the
# approval state is never touched; the audit stays green on a
# revisited tree (a revisit log line is not an approval); no temp
# files are left behind.
#
# Scratch trees carry abstract IDs (RM-9xxx) and live under /tmp only.
#
# Run: sh tests/unit/test-rules-revisit.sh

REPO_ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd) || exit 1
cd "$REPO_ROOT" || exit 1

RED=''
NC=''
[ -t 1 ] && RED='\033[31m' && NC='\033[0m'

WORK=$(mktemp -d /tmp/test-rules-revisit.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILS=$WORK/fails; : > "$FAILS"
passed=0

fail() { printf '  %sFAIL%s  %s\n' "${RED:-}" "${NC:-}" "$1" >> "$FAILS"; }
pass() { passed=$((passed + 1)); }

contains() {  # $1 haystack, $2 needle
    case $1 in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

line_is() {  # $1 file, $2 exact line -> pass/fail on first match
    grep -qx -- "$2" "$1"
}

run_report() {  # runs the report; env: SCRATCH T env-HORIZON; sets OUT/RC
    OUT=$(RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY="$T" \
        HORIZON="${HORIZON:-30}" sh "$REPO_ROOT/scripts/rules-report.sh" 2>&1)
    RC=$?
}

run_revisit() {  # $@ script args; env: SCRATCH T; sets OUT/RC
    OUT=$(RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY="$T" \
        sh "$REPO_ROOT/scripts/rules-revisit.sh" "$@" 2>&1)
    RC=$?
}

write_meta() {  # $1 dir  $2 id  $3 status  $4 interval  $5 next  $6 reviewed|-  [$7 rule]
    digs=${2#RM-}
    b="$1/internal/rules-meta/$(printf '%s' "$digs" | cut -c1)"\
"/$(printf '%s' "$digs" | cut -c2)/$(printf '%s' "$digs" | cut -c3)"
    mkdir -p "$b"
    if [ "$6" = - ]; then
        reviewed=""
    else
        reviewed="reviewed: $6"
    fi
    cat > "$b/$2.md" <<EOF
---
id: $2
rule: ${7:-agent/conventions.md#interactive-prompts-yn}
quote: "Demo rule $2"
created: 2026-01-10
status: $3
$reviewed
revisit-interval: $4
next-revisit: $5
---

Body of $2.

## Review log

- 2026-01-10 created — agent draft; maintainer review pending.
- 2026-05-01 approved by maintainer (direct chat review).
EOF
}

meta_path() {  # $1 dir  $2 id
    digs=${2#RM-}
    printf '%s/internal/rules-meta/%s/%s/%s/%s.md' "$1" \
        "$(printf '%s' "$digs" | cut -c1)" "$(printf '%s' "$digs" | cut -c2)" \
        "$(printf '%s' "$digs" | cut -c3)" "$2"
}

# ----------------------------------------------------------- report pins
# R0. the real tree must report green (living gate, read-only)
OUT=$(FORCE_TODAY=2026-10-16 sh "$REPO_ROOT/scripts/rules-report.sh" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && contains "$OUT" "rule-meta revisit report — 2026-10-16" \
    && contains "$OUT" "overdue: 0"; then
    pass
else
    fail "R0 real tree: report must be green, got rc=$RC: $OUT"
fi

# R1. lanes list the right metas; retired stays out of the lanes
RSCRATCH=$WORK/report1
write_meta "$RSCRATCH" RM-9001 active 1m 2026-06-01 2026-05-01
write_meta "$RSCRATCH" RM-9002 active 6m 2026-06-15 2026-05-01
write_meta "$RSCRATCH" RM-9003 active 1m 2026-06-20 2026-05-01
write_meta "$RSCRATCH" RM-9004 active 2y 2026-12-01 2026-05-01
write_meta "$RSCRATCH" RM-9005 retired 1m 2026-06-01 2026-05-01
write_meta "$RSCRATCH" RM-9006 active 1m 2026-07-01 -
SCRATCH=$RSCRATCH
T=2026-06-15
HORIZON=30
run_report
if [ "$RC" -eq 0 ] && contains "$OUT" "overdue: 1" \
    && contains "$OUT" "RM-9001  due 2026-06-01  1m" \
    && contains "$OUT" "due within the horizon (2026-06-15..2026-07-15): 3" \
    && contains "$OUT" "RM-9002  due 2026-06-15  6m" \
    && contains "$OUT" "RM-9003  due 2026-06-20  1m" \
    && contains "$OUT" "RM-9006  due 2026-07-01  1m" \
    && contains "$OUT" "review-pending (approval queue): 1" \
    && contains "$OUT" "next due after the horizon: 2026-12-01 (RM-9004)"; then
    pass
else
    fail "R1 lanes: wrong worklist, rc=$RC: $OUT"
fi
if contains "$OUT" "RM-9005"; then
    fail "R1 retired lane leak: RM-9005 must not appear in the revisit lanes"
else
    pass
fi
# due-TODAY is horizon, never overdue (audit lateness semantics)
if contains "$OUT" "overdue: 1" && ! contains "$OUT" "overdue: 2"; then
    pass
else
    fail "R1 boundary: due-today meta counted as overdue"
fi

# R2. HORIZON override discriminates the window boundary
HORIZON=0
run_report
if [ "$RC" -eq 0 ] \
    && contains "$OUT" "due within the horizon (2026-06-15..2026-06-15): 1" \
    && contains "$OUT" "RM-9002  due 2026-06-15  6m" \
    && contains "$OUT" "next due after the horizon: 2026-06-20 (RM-9003)"; then
    pass
else
    fail "R2 horizon override: wrong window, rc=$RC: $OUT"
fi
unset HORIZON

# R3. bad HORIZON fails loud
SCRATCH=$RSCRATCH
T=2026-06-15
HORIZON=8x
run_report
if [ "$RC" -eq 2 ] && contains "$OUT" "HORIZON must be a day count"; then
    pass
else
    fail "R3 bad HORIZON: expected rc=2 with message, got rc=$RC: $OUT"
fi
unset HORIZON

# R4. missing interpreter fails loud (fail-loud pin, L1)
SCRATCH=$RSCRATCH
T=2026-06-15
OUT=$(RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY="$T" \
    RULES_PYTHON=/nonexistent-rules-python \
    sh "$REPO_ROOT/scripts/rules-report.sh" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && contains "$OUT" "/nonexistent-rules-python unavailable"; then
    pass
else
    fail "R4 missing python: expected rc=2 naming the interpreter, got rc=$RC: $OUT"
fi

# R5. empty meta tree fails loud (never a partial worklist)
EMPTY=$WORK/empty$$
mkdir -p "$EMPTY/internal/rules-meta"
OUT=$(RM_AUDIT_ROOT="$EMPTY" FORCE_TODAY=2026-06-15 \
    sh "$REPO_ROOT/scripts/rules-report.sh" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && contains "$OUT" "no metas found"; then
    pass
else
    fail "R5 empty tree: expected rc=2, got rc=$RC: $OUT"
fi

# R6. unparsable pinned date fails loud inside the horizon math
OUT=$(RM_AUDIT_ROOT="$RSCRATCH" FORCE_TODAY=2026-13-99 \
    sh "$REPO_ROOT/scripts/rules-report.sh" 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && contains "$OUT" "horizon date computation failed"; then
    pass
else
    fail "R6 bad FORCE_TODAY: expected rc=2, got rc=$RC: $OUT"
fi

# ---------------------------------------------------------- revisit pins
one_scratch() {  # $1 interval  $2 next  -> fresh tree with RM-9001 active
    VSCRATCH=$WORK/one$$.$3
    write_meta "$VSCRATCH" RM-9001 active "$1" "$2" 2026-05-01
}

# V1. clean: 1m -> 6m, next from the REVISIT date, never
#     from the stale due date (due+6m would be 2026-12-01)
one_scratch 1m 2026-06-01 v1
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 clean "still pinned upstream"
M=$(meta_path "$VSCRATCH" RM-9001)
if [ "$RC" -eq 0 ] && contains "$OUT" "RM-9001: clean" \
    && contains "$OUT" "1m -> 6m" && contains "$OUT" "next-revisit 2026-12-15" \
    && line_is "$M" "revisit-interval: 6m" \
    && line_is "$M" "next-revisit: 2026-12-15" \
    && line_is "$M" "reviewed: 2026-05-01" \
    && line_is "$M" \
        "- 2026-06-15 revisit clean — still pinned upstream (interval 1m -> 6m, next 2026-12-15)."; then
    pass
else
    fail "V1 clean ladder: wrong update, rc=$RC: $OUT"
fi
if line_is "$M" "next-revisit: 2026-12-01"; then
    fail "V1 revisit-date basis: next computed from the stale due date (2026-12-01)"
else
    pass
fi
if find "$VSCRATCH" -name '*.tmp.*' | grep -q .; then
    fail "V1 leftover temp file next to the meta"
else
    pass
fi

# V2. clean at 2y stays 2y (the ladder max)
one_scratch 2y 2026-06-01 v2
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 clean
if [ "$RC" -eq 0 ] \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" "revisit-interval: 2y" \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" "next-revisit: 2028-06-15"; then
    pass
else
    fail "V2 2y max: expected 2y -> 2y, next 2028-06-15, rc=$RC: $OUT"
fi

# V3. findings: reset to 1m, note lands in the log line
one_scratch 6m 2026-06-01 v3
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 findings "upstream dropped the flag"
if [ "$RC" -eq 0 ] \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" "revisit-interval: 1m" \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" "next-revisit: 2026-07-15" \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" \
        "- 2026-06-15 revisit findings — upstream dropped the flag (interval reset to 1m from 6m, next 2026-07-15)."; then
    pass
else
    fail "V3 findings reset: wrong update, rc=$RC: $OUT"
fi

# V4. findings without a note is a usage error
one_scratch 1m 2026-06-01 v4
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 findings
if [ "$RC" -eq 2 ] && contains "$OUT" "findings needs a note"; then
    pass
else
    fail "V4 findings no note: expected rc=2, got rc=$RC: $OUT"
fi

# V5. multi-line notes are refused (they would forge log entries)
one_scratch 1m 2026-06-01 v5
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 clean "line one
line two"
if [ "$RC" -eq 2 ] && contains "$OUT" "single-line"; then
    pass
else
    fail "V5 newline note: expected rc=2, got rc=$RC: $OUT"
fi

# V6. unknown meta is a domain refusal naming the id
one_scratch 1m 2026-06-01 v6
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9777 clean
if [ "$RC" -eq 1 ] && contains "$OUT" "no meta RM-9777"; then
    pass
else
    fail "V6 unknown id: expected rc=1 naming RM-9777, got rc=$RC: $OUT"
fi

# V7. retired metas are outside the cycle
VSCRATCH=$WORK/retired$$
write_meta "$VSCRATCH" RM-9001 retired 1m 2026-06-01 2026-05-01
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 clean
if [ "$RC" -eq 1 ] && contains "$OUT" "retired"; then
    pass
else
    fail "V7 retired: expected rc=1 naming retired, got rc=$RC: $OUT"
fi

# V8. bad verdict is a usage error
one_scratch 1m 2026-06-01 v8
SCRATCH=$VSCRATCH
T=2026-06-15
run_revisit RM-9001 maybe
if [ "$RC" -eq 2 ] && contains "$OUT" "clean or findings"; then
    pass
else
    fail "V8 bad verdict: expected rc=2, got rc=$RC: $OUT"
fi

# V8b. malformed interval in the meta is refused loud (audit owns it,
#      but the revisit must not compute from garbage)
BSCRATCH=$WORK/badiv$$
write_meta "$BSCRATCH" RM-9001 active 3w 2026-06-01 2026-05-01
SCRATCH=$BSCRATCH
T=2026-06-15
run_revisit RM-9001 clean
if [ "$RC" -eq 2 ] && contains "$OUT" "bad revisit-interval '3w'"; then
    pass
else
    fail "V8b bad interval: expected rc=2 naming it, got rc=$RC: $OUT"
fi

# V8c. a meta without a review-log section is refused (the log line
#      has nowhere to land)
LSCRATCH=$WORK/nolog$$
digs=9001
lb="$LSCRATCH/internal/rules-meta/9/0/0"
mkdir -p "$lb"
cat > "$lb/RM-9001.md" <<'EOF'
---
id: RM-9001
rule: agent/conventions.md#interactive-prompts-yn
quote: "Demo rule RM-9001"
created: 2026-01-10
status: active
revisit-interval: 1m
next-revisit: 2026-06-01
---

Body without a review log.
EOF
SCRATCH=$LSCRATCH
T=2026-06-15
run_revisit RM-9001 clean
if [ "$RC" -eq 2 ] && contains "$OUT" "Review log"; then
    pass
else
    fail "V8c no review log: expected rc=2, got rc=$RC: $OUT"
fi

# V9. month arithmetic clamps at month end (Jan 31 + 1m -> Feb 28;
#     findings resets to 1m, so the clamp is observable in one step)
one_scratch 6m 2026-06-01 v9
SCRATCH=$VSCRATCH
T=2027-01-31
run_revisit RM-9001 findings "rationale rotted"
if [ "$RC" -eq 0 ] \
    && line_is "$(meta_path "$VSCRATCH" RM-9001)" "next-revisit: 2027-02-28"; then
    pass
else
    fail "V9 clamp: expected 2027-02-28, rc=$RC: $OUT"
fi

# V10. missing interpreter fails loud before any write (L1)
one_scratch 1m 2026-06-01 v10
M=$(meta_path "$WORK/one$$.v10" RM-9001)
before=$(sed -n '2,/^---$/p' "$M" | grep -c '^revisit-interval:')
OUT=$(RM_AUDIT_ROOT="$WORK/one$$.v10" FORCE_TODAY=2026-06-15 \
    RULES_PYTHON=/nonexistent-rules-python \
    sh "$REPO_ROOT/scripts/rules-revisit.sh" RM-9001 clean 2>&1)
RC=$?
if [ "$RC" -eq 2 ] && contains "$OUT" "unavailable" \
    && [ "$before" -eq "$(sed -n '2,/^---$/p' "$M" | grep -c '^revisit-interval:')" ]; then
    pass
else
    fail "V10 missing python: rc=$RC, meta must stay untouched"
fi

# V11. audit interplay: a revisited tree stays audit-green (the log
#      line pairs with nothing, invariant 9 stays silent)
GSCRATCH=$WORK/green$$
mkdir -p "$GSCRATCH/scripts" "$GSCRATCH/agent" "$GSCRATCH/internal/records" \
    "$GSCRATCH/internal/rules-meta"
cp "$REPO_ROOT/scripts/gen-rules-index.py" "$GSCRATCH/scripts/"
cat > "$GSCRATCH/agent/conventions.md" <<'EOF'
# Conventions

## Interactive prompts (y/n)

- Demo rule RM-9001 body text. (RM-9001)
EOF
cat > "$GSCRATCH/AGENTS.md" <<'EOF'
# AGENTS
EOF
cat > "$GSCRATCH/agent/test-fidelity.md" <<'EOF'
# Fidelity
EOF
cat > "$GSCRATCH/agent/review-concept.md" <<'EOF'
# Review
EOF
cat > "$GSCRATCH/internal/records/rules-meta.md" <<'EOF'
# Record

## Revisit ladder

- Demo rule RM-9002 body text. (RM-9002)
EOF
write_meta "$GSCRATCH" RM-9001 active 1m 2026-11-16 2026-05-01
write_meta "$GSCRATCH" RM-9002 active 1m 2026-11-16 2026-05-01 \
    internal/records/rules-meta.md#revisit-ladder
SCRATCH=$GSCRATCH
T=2026-10-22
run_revisit RM-9001 clean "rationale re-verified"
AOUT=$(RM_AUDIT_ROOT="$GSCRATCH" FORCE_TODAY=2026-10-16 \
    sh "$REPO_ROOT/scripts/rules-audit.sh" 2>&1)
ARC=$?
if [ "$RC" -eq 0 ] && [ "$ARC" -eq 0 ] && contains "$AOUT" "0 blocking" \
    && line_is "$(meta_path "$GSCRATCH" RM-9001)" "next-revisit: 2027-04-22"; then
    pass
else
    fail "V11 audit interplay: revisit rc=$RC, audit rc=$ARC: $AOUT"
fi

# ------------------------------------------------------------- summary
if [ -s "$FAILS" ]; then
    printf 'rules-revisit pins: FAILED\n'
    cat "$FAILS"
    exit 1
fi
printf 'rules-revisit pins: OK (%s pins green)\n' "$passed"
