#!/bin/sh
# test-rules-meta.sh -- pins scripts/rules-audit.sh (invariants 1-9)
#
# Every blocking invariant gets a scratch-tree failure path that must
# redden the audit AND name the invariant; the report-only lanes
# (overdue, INDEX regeneration) must NOT redden it.
# Scratch trees carry abstract IDs (RM-9xxx) and live under /tmp only.
#
# Run: sh tests/unit/test-rules-meta.sh

REPO_ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd) || exit 1
cd "$REPO_ROOT" || exit 1

RED=''
NC=''
[ -t 1 ] && RED='\033[31m' && NC='\033[0m'

WORK=$(mktemp -d /tmp/test-rules-meta.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILS=$WORK/fails; : > "$FAILS"
passed=0

fail() { printf '  %sFAIL%s  %s\n' "${RED:-}" "${NC:-}" "$1" >> "$FAILS"; }
pass() { passed=$((passed + 1)); }

run_audit() {  # runs the real audit against $SCRATCH; sets OUT/RC
    OUT=$(cd "$SCRATCH" && RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY=2026-10-16 \
        sh "$REPO_ROOT/scripts/rules-audit.sh" 2>&1)
    RC=$?
}

expect_block() {  # $1 label, $2 required output snippet
    run_audit
    if [ "$RC" -eq 0 ]; then
        fail "$1: audit exited 0, expected blocking"
        return
    fi
    case $OUT in
        *"$2"*) pass ;;
        *) fail "$1: output lacks '$2'" ;;
    esac
}

expect_ok() {  # $1 label, $2 required output snippet
    run_audit
    if [ "$RC" -ne 0 ]; then
        fail "$1: audit exited $RC, expected pass"
        return
    fi
    case $OUT in
        *"$2"*) pass ;;
        *) fail "$1: output lacks '$2'" ;;
    esac
}

write_meta() {  # $1 id  $2 quote  $3 rule-anchor-file  $4 anchor  $5 extra
    mkdir -p "$SCRATCH/internal/rules-meta/9/0/0" 2>/dev/null
    # bucket digits from the id: 9001 -> 9/0/0
    digs=${1#RM-}
    b1=$(printf '%s' "$digs" | cut -c1); b2=$(printf '%s' "$digs" | cut -c2)
    b3=$(printf '%s' "$digs" | cut -c3)
    mkdir -p "$SCRATCH/internal/rules-meta/$b1/$b2/$b3"
    cat > "$SCRATCH/internal/rules-meta/$b1/$b2/$b3/$1.md" <<EOF
---
id: $1
rule: $3#$4
quote: "$2"
created: 2026-10-16
status: active
revisit-interval: 1m
next-revisit: 2026-11-16
$5
---

Body of $1.

## Review log

- 2026-10-16 created — agent draft; maintainer review pending.
EOF
}

new_scratch() {  # green baseline tree
    SCRATCH=$WORK/s$$.$1
    mkdir -p "$SCRATCH/scripts" "$SCRATCH/agent" "$SCRATCH/internal/records" \
        "$SCRATCH/internal/rules-meta"
    cp scripts/gen-rules-index.py "$SCRATCH/scripts/"
    cat > "$SCRATCH/agent/conventions.md" <<'EOF'
# Conventions

## Interactive prompts (y/n)

- First demo rule. (RM-9001)
- Second demo rule. (RM-9002)

## Script output style

- Output demo rule. (RM-9003)
EOF
    cat > "$SCRATCH/internal/records/rules-meta.md" <<'EOF'
# Record

## Revisit ladder

- Ladder demo rule. (RM-9004)
EOF
    write_meta RM-9001 "First demo rule" agent/conventions.md interactive-prompts-yn ""
    write_meta RM-9002 "Second demo rule" agent/conventions.md interactive-prompts-yn ""
    write_meta RM-9003 "Output demo rule" agent/conventions.md script-output-style ""
    write_meta RM-9004 "Ladder demo rule" internal/records/rules-meta.md revisit-ladder ""
}

meta_file() {  # $1 id -> path in the CURRENT scratch
    digs=${1#RM-}
    printf '%s/internal/rules-meta/%s/%s/%s/%s.md' "$SCRATCH" \
        "$(printf '%s' "$digs" | cut -c1)" "$(printf '%s' "$digs" | cut -c2)" \
        "$(printf '%s' "$digs" | cut -c3)" "$1"
}

# ---------------------------------------------------------------- pins
# 0. the real tree must pass (living gate)
OUT=$(RM_AUDIT_ROOT="$REPO_ROOT" FORCE_TODAY=2026-10-16 sh scripts/rules-audit.sh 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '0 blocking'; then
    pass
else
    fail "real tree: audit must be green, got rc=$RC: $OUT"
fi

# 1. inv 1 -- ref-less unit in an active section
new_scratch n1
sed -i 's/ (RM-9002)//' "$SCRATCH/agent/conventions.md"
expect_block "inv1 ref-less unit" "[inv1]"

# 2. inv 2 -- dangling ref
new_scratch n2
sed -i 's/ (RM-9002)/(RM-9009)/' "$SCRATCH/agent/conventions.md"
expect_block "inv2 dangling ref" "[inv2]"

# 3a. inv 3 -- one meta referenced twice
new_scratch n3a
sed -i 's/ (RM-9002)/ (RM-9001)/' "$SCRATCH/agent/conventions.md"
expect_block "inv3 double ref" "[inv3]"

# 3b. inv 3 -- orphan meta (active, unreferenced)
new_scratch n3b
write_meta RM-9005 "Orphan demo rule" agent/conventions.md interactive-prompts-yn ""
expect_block "inv3 orphan" "orphan"

# 4. inv 4 -- filename disagrees with id
new_scratch n4
mv "$(meta_file RM-9002)" "$(meta_file RM-9002).tmp" 2>/dev/null
mv "$(meta_file RM-9002).tmp" "$SCRATCH/internal/rules-meta/9/0/0/RM-9008.md"
expect_block "inv4 filename vs id" "[inv4]"

# 5a. inv 5 -- quote prefix not findable
new_scratch n5a
sed -i 's/^quote: "Second demo rule"/quote: "Words absent from target"/' "$(meta_file RM-9002)"
expect_block "inv5 quote" "[inv5]"

# 5b. inv 5 -- anchor not a heading
new_scratch n5b
sed -i 's#interactive-prompts-yn#no-such-section#' "$(meta_file RM-9002)"
expect_block "inv5 anchor" "[inv5]"

# 6a. inv 6 -- next-revisit before created
new_scratch n6a
sed -i 's/^next-revisit: 2026-11-16/next-revisit: 2026-10-01/' "$(meta_file RM-9001)"
expect_block "inv6 revisit before created" "[inv6]"

# 6b. inv 6 -- malformed date
new_scratch n6b
sed -i 's/^created: 2026-10-16/created: 2026-13-40/' "$(meta_file RM-9001)"
expect_block "inv6 bad date" "[inv6]"

# 9a. inv 9 -- reviewed field without approval log line
new_scratch n9a
sed -i 's/^status: active/status: active\nreviewed: 2026-10-16/' "$(meta_file RM-9001)"
expect_block "inv9 field without line" "[inv9]"

# 9b. inv 9 -- approval log line without reviewed field
new_scratch n9b
cat >> "$(meta_file RM-9001)" <<'EOF'
- 2026-10-16 approved by maintainer (scratch probe).
EOF
expect_block "inv9 line without field" "[inv9]"

# 7. overdue is report-only
new_scratch n7
sed -i 's/^created: 2026-10-16/created: 2026-09-01/; s/^next-revisit: 2026-11-16/next-revisit: 2026-10-01/' "$(meta_file RM-9001)"
expect_ok "inv7 overdue non-blocking" "overdue metas"

# 8. stale INDEX regenerates without blocking
new_scratch n8
run_audit   # first run regenerates the scratch INDEX
printf 'hand edit\n' >> "$SCRATCH/internal/rules-meta/INDEX.md"
expect_ok "inv8 stale INDEX non-blocking" "INDEX regenerated"
if grep -q '^hand edit$' "$SCRATCH/internal/rules-meta/INDEX.md"; then
    fail "inv8: INDEX was not rewritten to the generated state"
else
    pass
fi

# ------------------------------------------------------------- summary
if [ -s "$FAILS" ]; then
    printf 'rules-meta audit pins: FAILED\n'
    cat "$FAILS"
    exit 1
fi
printf 'rules-meta audit pins: OK (%s pins green)\n' "$passed"
