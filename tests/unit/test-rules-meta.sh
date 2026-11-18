#!/bin/sh
# test-rules-meta.sh -- pins scripts/rules-audit.sh (invariants 1-10)
# plus the suite's own no-fake-findings pin 10 (unrelated numbering,
# a suite-pin label -- audit invariants and suite pins count
# separately): outside the trailing (RM-NNNN)
# ref form, no real ID may appear in any scope file.
#
# Every blocking invariant gets a scratch-tree failure path that must
# redden the audit AND name the invariant; the report-only lanes
# (overdue, INDEX regeneration) must NOT redden it.
# Scratch trees carry abstract IDs (RM-9xxx) and live under /tmp only.
#
# Run: sh tests/unit/test-rules-meta.sh

REPO_ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd) || exit 1
cd "$REPO_ROOT" || exit 1

# Shared harness (issue #444 adoption, minimal-pass() class): the local
# counter shell is gone -- the silent pass() and the FAILS-buffered
# fail() are replaced by the shared pass/fail rows, and the summary gate
# is suite_done (the same red strength: any fail row exits 1). The
# scratch tree registers with the work registry (issue #395); the local
# trap is gone. Loud scratch guard (#441 a B1 class swept here): no
# set -e in this suite, so a failed work_new must abort instead of
# degrading every pin writer onto root-level literal paths.
. "$REPO_ROOT/tests/unit/lib/harness.sh"

WORK="$(work_new /tmp/test-rules-meta.XXXXXX)" || {
    echo "rules-meta audit pins: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

run_audit() { # runs the real audit against $SCRATCH; sets OUT/RC
    OUT=$(cd "$SCRATCH" && RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY=2026-10-16 \
        sh "$REPO_ROOT/scripts/rules-audit.sh" 2>&1)
    RC=$?
}

expect_block() { # $1 label, $2 required output snippet
    run_audit
    if [ "$RC" -eq 0 ]; then
        fail "$1: audit exited 0, expected blocking"
        return
    fi
    case $OUT in
        *"$2"*) pass "$1" ;;
        *) fail "$1: output lacks '$2'" ;;
    esac
}

expect_ok() { # $1 label, $2 required output snippet
    run_audit
    if [ "$RC" -ne 0 ]; then
        fail "$1: audit exited $RC, expected pass"
        return
    fi
    case $OUT in
        *"$2"*) pass "$1" ;;
        *) fail "$1: output lacks '$2'" ;;
    esac
}

write_meta() { # $1 id  $2 quote  $3 rule-anchor-file  $4 anchor  $5 extra
    mkdir -p "$SCRATCH/internal/rules-meta/9/0/0" 2>/dev/null
    # bucket digits from the id: 9001 -> 9/0/0
    digs=${1#RM-}
    b1=$(printf '%s' "$digs" | cut -c1)
    b2=$(printf '%s' "$digs" | cut -c2)
    b3=$(printf '%s' "$digs" | cut -c3)
    mkdir -p "$SCRATCH/internal/rules-meta/$b1/$b2/$b3"
    cat >"$SCRATCH/internal/rules-meta/$b1/$b2/$b3/$1.md" <<EOF
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

new_scratch() { # green baseline tree
    SCRATCH=$WORK/s$$.$1
    mkdir -p "$SCRATCH/scripts" "$SCRATCH/agent" "$SCRATCH/internal/records" \
        "$SCRATCH/internal/rules-meta"
    cp scripts/gen-rules-index.py "$SCRATCH/scripts/"
    : >"$SCRATCH/agent/test-fidelity.md"  # in SCOPE_FILES; empty = no units
    : >"$SCRATCH/agent/review-concept.md" # in SCOPE_FILES; empty = no units
    : >"$SCRATCH/agent/docs-loop.md"      # in SCOPE_FILES; empty = no units
    : >"$SCRATCH/AGENTS.md"               # in SCOPE_FILES; empty = no units
    cat >"$SCRATCH/agent/conventions.md" <<'EOF'
# Conventions

## Interactive prompts (y/n)

- First demo rule. (RM-9001)
- Second demo rule. (RM-9002)

## Script output style

- Output demo rule. (RM-9003)
EOF
    cat >"$SCRATCH/internal/records/rules-meta.md" <<'EOF'
# Record

## Revisit ladder

- Ladder demo rule. (RM-9004)
EOF
    write_meta RM-9001 "First demo rule" agent/conventions.md interactive-prompts-yn ""
    write_meta RM-9002 "Second demo rule" agent/conventions.md interactive-prompts-yn ""
    write_meta RM-9003 "Output demo rule" agent/conventions.md script-output-style ""
    write_meta RM-9004 "Ladder demo rule" internal/records/rules-meta.md revisit-ladder ""
}

meta_file() { # $1 id -> path in the CURRENT scratch
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
    pass "real tree: audit green with 0 blocking"
else
    fail "real tree: audit must be green, got rc=$RC: $OUT"
fi

# 1. inv 1 -- ref-less unit in an active section
new_scratch n1
sed -i 's/ (RM-9002)//' "$SCRATCH/agent/conventions.md"
expect_block "inv1 ref-less unit" "[inv1]"

# 1b. inv 1 -- the record's main-rule section is audit-active (phase-5
#     wiring: its ACTIVE_SECTIONS entry is load-bearing -- losing it
#     would silently stop enforcing the self-application unit)
new_scratch n1b
cat >>"$SCRATCH/internal/records/rules-meta.md" <<'EOF'

## The main rule

- Unreferenced demo rule.
EOF
expect_block "inv1 main-rule section enforced" "the-main-rule"

# 1c. inv 1 -- the RM-keys conventions section is audit-active (#235
#     a Q8: its ACTIVE_SECTIONS entry is load-bearing -- losing it
#     would let future units in that section pass ref-less)
new_scratch n1c
cat >>"$SCRATCH/agent/conventions.md" <<'EOF'

## Referencing house rules (RM keys)

- Unreferenced demo rule.
EOF
expect_block "inv1 RM-keys section enforced" "referencing-house-rules"

# 1d. inv 1 -- the review-tracks section is audit-active (#324: its
#     ACTIVE_SECTIONS entry is load-bearing -- losing it would let
#     the track/staffing/disposition units pass ref-less). Section
#     renamed by #334 (track values shipped|non-shipped) -- the
#     fixture heading and the audit's ACTIVE_SECTIONS entry moved
#     together in the same commit.
new_scratch n1d
cat >>"$SCRATCH/agent/review-concept.md" <<'EOF'

## Review tracks: shipped and non-shipped

- Unreferenced demo rule.
EOF
expect_block "inv1 review-tracks section enforced" "review-tracks"

# 1e. inv 1 -- the scope section (the former two-types table, renamed
#     by #334) is audit-active: its ACTIVE_SECTIONS entry is
#     load-bearing -- losing it would let scope-table-section units
#     pass ref-less. Mirrors n1b/n1c/n1d.
new_scratch n1e
cat >>"$SCRATCH/agent/review-concept.md" <<'EOF'

## Review scope: snapshot and diff

- Unreferenced demo rule.
EOF
expect_block "inv1 scope section enforced" "review-scope"

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

# 5c. inv 5 -- retired metas are exempt (rule bullet removed, quote
#     unfindable by construction; pins the retire exemption)
new_scratch n5c
sed -i '/^- Second demo rule\. (RM-9002)$/d' "$SCRATCH/agent/conventions.md"
sed -i 's/^status: active/status: retired/;
        s/^quote: "Second demo rule"/quote: "Words absent from target"/' \
    "$(meta_file RM-9002)"
expect_ok "inv5 retired exempt" "0 blocking"

# 10a. inv 10 -- composite body quote not in the Source-named file
#      nor the rule file (#561, the body-quote discipline)
new_scratch n10a
sed -i 's|^Body of RM-9002\.$|Source: agent/conventions.md, demo section.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_block "inv10 body quote not in source" "[inv10]"

# 10b. inv 10 -- external source (no in-repo path) is exempt: the
#      #561 spec constraint (issue/PR/chat/man-page quotes are not
#      greppable in-tree)
new_scratch n10b
sed -i 's|^Body of RM-9002\.$|Source: issue #9 (chat quote).\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 external source exempt" "0 blocking"

# 10c. inv 10 -- case normalization: a sentence-initial caps
#      difference stays green (the #561 spec constraint; the fixture
#      rule text carries "First demo rule")
new_scratch n10c
sed -i 's|^Body of RM-9002\.$|Source: agent/conventions.md, demo section.\n\nThe rule "first demo rule" quoted.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 case-folded quote green" "0 blocking"

# 10d. inv 10 -- the rule file is a haystack on its own: the quote
#      sits in the rule back-ref file, NOT in the Source-named file
#      (metas quote both their source record and the rule text)
new_scratch n10d
sed -i 's|^Body of RM-9002\.$|Source: internal/records/rules-meta.md, demo section.\n\nThe rule "First demo rule" via rule file.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 rule-file haystack green" "0 blocking"

# 10e. inv 10 -- code is not quotation (a corpus case from the #561
#      survey): the same composite inside an inline code span stays
#      green
new_scratch n10e
sed -i 's|^Body of RM-9002\.$|Source: agent/conventions.md, demo section.\n\nThe marker `"composite quote nowhere"` arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 code span is not a quote" "0 blocking"

# 10f. inv 10 -- retired metas are exempt (the inv5 retire class)
new_scratch n10f
sed -i '/^- Second demo rule\. (RM-9002)$/d' "$SCRATCH/agent/conventions.md"
sed -i 's/^status: active/status: retired/;
    s|^Body of RM-9002\.$|Source: agent/conventions.md, demo section.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 retired exempt" "0 blocking"

# 10g. inv 10 (#564 a A1) -- a Source path wrapped over a line break
#      heals (the wrap space after a slash fuses) and the quote is
#      checked; without the heal the token cannot resolve and the
#      meta would silently ride the exemption
new_scratch n10g
sed -i 's|^Body of RM-9002\.$|Source: agent/\nconventions.md, demo section.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_block "inv10 wrapped Source path heals and checks" "[inv10]"

# 10h. inv 10 (#564 a A1) -- an unresolvable Source token is REPORTED
#      (report-only lane), not silently exempt
new_scratch n10h
sed -i 's|^Body of RM-9002\.$|Source: management/nonexistent.sh, demo section.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 unresolved token reported" "inv10 unresolved (report-only"

# 10h2. inv 10 (#565, #581 a A1/a A3) -- a Source token that resolves
#       to an existing DIRECTORY is prose naming a tree: ignored --
#       no parity leg, no unresolved-lane entry, but VISIBLE in the
#       ignored sub-lane (a broken file citation colliding with a
#       directory must not vanish silently). The pin asserts the
#       sub-lane line AND the unresolved lane's absence (an
#       expect_ok "0 blocking" would pass either way -- neither lane
#       reddens the rc). The fixture body carries a double-quoted
#       string: deleting the ignore arm lands the token in the
#       unresolved lane (red via the absence grep), and a regression
#       turning the arm into a parity LEG runs the quote check --
#       the unfindable quote blocks (red via rc) -- both halves
#       discriminated.
new_scratch n10h2
sed -i 's|^Body of RM-9002\.$|Source: internal/rules-meta tree, demo.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
run_audit
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q 'inv10 unresolved' &&
    printf '%s' "$OUT" | grep -q 'RM-9002 -- directory mention (ignored): internal/rules-meta'; then
    pass "inv10 directory token: ignored, sub-lane visible, never a leg"
else
    fail "inv10 directory token: ignored + sub-lane expected (rc=$RC): $OUT"
fi

# 10i. inv 10 (#564 a B3) -- multi-file Source lines: every resolvable
#      token is a haystack leg (first-token-only would check only
#      rules-meta.md; the quote lives in the second leg and the rule
#      file is the first leg, so only the union discriminates)
new_scratch n10i
sed -i 's|^Body of RM-9004\.$|Source: internal/records/rules-meta.md and agent/conventions.md, demo.\n\nThe rule "First demo rule" quoted.|' \
    "$(meta_file RM-9004)"
expect_ok "inv10 all resolvable Source tokens are legs" "0 blocking"

# 10j. inv 10 (#564 a B2, b D1) -- dot-dot tokens never resolve (no
#      out-of-root read): a marker planted ../-reachable from $ROOT
#      must NOT become a leg, and the rejection is visible in the
#      report lane. With the guard deleted the marker WOULD resolve
#      and the composite quote would block -- the arm discriminates
#      the guard itself, not the sandbox layout.
new_scratch n10j
printf 'marker\n' >"$WORK/inv10-outside-marker.md"
sed -i 's|^Body of RM-9002\.$|Source: see ../inv10-outside-marker.md, demo.\n\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 dot-dot token rejected and reported" "../inv10-outside-marker.md"

# 10k. inv 10 (#564 a B4) -- an unclosed fence amputates the body:
#      non-blocking, but flagged in the report lane
new_scratch n10k
sed -i 's|^Body of RM-9002\.$|Source: agent/conventions.md, demo section.\n\n```\nstray fence\nThe bad "composite quote nowhere" arm.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 odd fence flagged in report" "odd (unclosed) fence"

# 10l. inv 10 (#572 B4) -- the haystack is content-inclusive: fenced
#      blocks of a haystack file are searchable text. A body quote
#      citing a string that lives ONLY inside a fence of the rule
#      back-ref file (the round-marker template shape) stays green;
#      with the fence-skipping transform as the haystack builder it
#      falsely blocks -- the exact false red the finding names.
new_scratch n10l
printf '\n```\nmarker template: "fence only vocabulary"\n```\n' \
    >>"$SCRATCH/agent/conventions.md"
sed -i 's|^Body of RM-9002\.$|Source: internal/records/rules-meta.md, demo.\n\nCites "fence only vocabulary" values.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 fence-only quote in rule file green" "0 blocking"

# 10m. inv 10 (#572 B4) -- same content-inclusion for a Source leg:
#      the fence-only string sits in the Source-named file, not the
#      rule file (the union's other half)
new_scratch n10m
printf '\n```\nmarker template: "leg fence vocabulary"\n```\n' \
    >>"$SCRATCH/internal/records/rules-meta.md"
sed -i 's|^Body of RM-9002\.$|Source: internal/records/rules-meta.md, demo.\n\nCites "leg fence vocabulary" values.|' \
    "$(meta_file RM-9002)"
expect_ok "inv10 fence-only quote in Source leg green" "0 blocking"

# 10n. inv 8 (#572 B5) -- a FAILING regen never leaves a truncated
#      INDEX: the audit stages the regeneration (--output, the T2
#      generator flag) and replaces the real INDEX only after the
#      generator succeeded. The scratch generator simulates the
#      write-failure arm: it truncates its output target, then dies.
#      Called with --output (the audit's shape) the victim is the
#      staged temp; a regression back to the in-place call shape
#      makes the REAL INDEX the victim -- the sentinel check fails,
#      so the pin discriminates the call shape, not the generator.
new_scratch n10n
printf 'sentinel INDEX -- must survive a failed regen\n' \
    >"$SCRATCH/internal/rules-meta/INDEX.md"
cat >"$SCRATCH/scripts/gen-rules-index.py" <<'PYEOF'
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(ROOT, 'internal', 'rules-meta', 'INDEX.md')
if '--output' in sys.argv:
    out = sys.argv[sys.argv.index('--output') + 1]
open(out, 'w').write('truncated')
sys.exit(1)
PYEOF
run_audit
if [ "$RC" -eq 0 ] &&
    grep -qxF 'sentinel INDEX -- must survive a failed regen' \
        "$SCRATCH/internal/rules-meta/INDEX.md" &&
    printf '%s' "$OUT" | grep -q 'INDEX regeneration failed' &&
    ! printf '%s' "$OUT" | grep -q '\[inv'; then
    pass "inv8 failed regen: staged shape, real INDEX untouched"
else
    fail "inv8 failed regen: INDEX damaged or audit red (rc=$RC)"
fi

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
cat >>"$(meta_file RM-9001)" <<'EOF'
- 2026-10-16 approved by maintainer (scratch probe).
EOF
expect_block "inv9 line without field" "[inv9]"

# meta-tree. #232: find errors block -- an unreadable meta subdir must
# not silently shrink the audit's worklist (the metas inside would be
# invisible to every invariant). Probe runs as the non-root suite
# user; root skips disclosed, like the peers (#318 a B3) -- chmod 000
# cannot block a root reader, the red would be spurious.
# (#318 a A1): a blocked run must NOT regenerate INDEX.md from the
# readable subset -- the sentinel survives, regen is skipped loudly.
if [ "$(id -u)" -eq 0 ]; then
    echo "  pin skipped: meta-tree needs a non-root uid (root reads through 000)"
else
    new_scratch ntree
    write_meta RM-9011 "Unreadable demo rule" agent/conventions.md interactive-prompts-yn ""
    printf 'sentinel INDEX -- must survive a blocked run\n' \
        >"$SCRATCH/internal/rules-meta/INDEX.md"
    chmod 000 "$SCRATCH/internal/rules-meta/9/0/1"
    expect_block "meta-tree unreadable subdir blocks" "[meta-tree]"
    expect_block "meta-tree skips INDEX regeneration" \
        "INDEX not regenerated (meta-tree walk reported errors)"
    if grep -qxF 'sentinel INDEX -- must survive a blocked run' \
        "$SCRATCH/internal/rules-meta/INDEX.md"; then
        pass "meta-tree INDEX survives a blocked run"
    else
        fail "meta-tree INDEX rewritten on a blocked run"
    fi
    chmod 755 "$SCRATCH/internal/rules-meta/9/0/1" # (#318 a B4) teardown
fi

# meta-tree missing. (#318 a B2): a missing meta tree blocks loudly
# (find ENOENT feeds [meta-tree]) -- it is not a silent empty audit.
new_scratch nmtree
rm -rf "${SCRATCH:?}/internal/rules-meta"
expect_block "meta-tree absent meta tree blocks" "[meta-tree]"

# meta-tree rc. #323: the worklist pipeline rc (sort's) blocks even
# with an EMPTY finderr -- a sort write failure (ENOSPC on the
# worklist target) would otherwise leave a silently partial worklist
# (#318 a A2). Executed via a PATH-injected sort stub that fails the
# no-argument sort shape with sort's write-failure rc (2); in
# rules-audit.sh that shape is the worklist build AND the inv-3a
# duplicate scan -- both fire the stub (inert here: the fixture
# carries no duplicate refs, pr-325 a A2). Argument-carrying sort
# calls pass through to the real binary.
# Control arm first: the same shape of tree, unstubbed, stays green --
# the stub fires the gate, not the fixture.
new_scratch n323ctl
run_audit
if [ "$RC" -eq 0 ]; then
    pass "#323 control: unstubbed scratch tree stays green"
else
    fail "#323 control: unstubbed scratch tree must stay green, got rc=$RC: $OUT"
fi
new_scratch n323
SORTSTUB=$WORK/sortstub.$$
mkdir -p "$SORTSTUB"
REAL_SORT=$(command -v sort) || REAL_SORT=/usr/bin/sort
cat >"$SORTSTUB/sort" <<EOF
#!/bin/sh
[ \$# -eq 0 ] && exit 2
exec $REAL_SORT "\$@"
EOF
chmod +x "$SORTSTUB/sort"
OUT=$(cd "$SCRATCH" && RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY=2026-10-16 \
    PATH="$SORTSTUB:$PATH" sh "$REPO_ROOT/scripts/rules-audit.sh" 2>&1)
RC=$?
if [ "$RC" -eq 1 ]; then
    case "$OUT" in
        *'[meta-tree] worklist pipeline failed'*) pass "#323 sort rc: worklist pipeline block fired" ;;
        *) fail "#323 sort rc: rc=1 but no worklist pipeline block: $OUT" ;;
    esac
else
    fail "#323 sort rc: expected rc=1 with the block, got rc=$RC: $OUT"
fi

# meta-tree refids rc. pr-325 a A1 (#323 class): the refids pipeline
# rc (sort's) blocks even with an EMPTY finderr -- a write failure
# shrinking $WORK/refids would false-flag every active meta as an
# orphan (grep -qxF cannot tell an empty file from "no refs"), so the
# orphan check is skipped and the run blocks. Executed via a
# PATH-injected sort stub failing the 'sort -u' shape with sort's
# write-failure rc (2); that shape is the refids build AND the inv-2
# resolver scan -- both fire the stub (inert here: the fixture is
# green); all other sort calls pass through to the real binary.
# Control arm first: unstubbed stays green.
new_scratch n341ctl
run_audit
if [ "$RC" -eq 0 ]; then
    pass "#341 control: unstubbed scratch tree stays green"
else
    fail "#341 control: unstubbed scratch tree must stay green, got rc=$RC: $OUT"
fi
new_scratch n341
SORTSTUB=$WORK/sortstub.$$
mkdir -p "$SORTSTUB"
REAL_SORT=$(command -v sort) || REAL_SORT=/usr/bin/sort
cat >"$SORTSTUB/sort" <<EOF
#!/bin/sh
[ \$# -eq 1 ] && [ "\$1" = "-u" ] && exit 2
exec $REAL_SORT "\$@"
EOF
chmod +x "$SORTSTUB/sort"
OUT=$(cd "$SCRATCH" && RM_AUDIT_ROOT="$SCRATCH" FORCE_TODAY=2026-10-16 \
    PATH="$SORTSTUB:$PATH" sh "$REPO_ROOT/scripts/rules-audit.sh" 2>&1)
RC=$?
if [ "$RC" -eq 1 ]; then
    case "$OUT" in
        *'[meta-tree] refids pipeline failed'*) pass "#341 refids rc: refids pipeline block fired" ;;
        *) fail "#341 refids rc: rc=1 but no refids pipeline block: $OUT" ;;
    esac
else
    fail "#341 refids rc: expected rc=1 with the block, got rc=$RC: $OUT"
fi

# 9c. inv 9 -- a bare 'reviewed:' line (key present, no date) blocks:
#     approval membership is key-presence-with-value (#233) -- a bare
#     line must not count as approved anywhere (report queue, INDEX)
new_scratch n9c
sed -i 's/^status: active/status: active\nreviewed:/' "$(meta_file RM-9001)"
expect_block "inv9 bare reviewed line blocks" "bare 'reviewed:' line (key without a value)"

# 9d-9l. inv 9 amendment state (#333): approved-then-amended metas must
#     carry amended: <date> -- without the field the meta renders
#     approved while its log declares re-approval pending (the exact
#     #333 gap: two amended metas sat in no queue at all). The state
#     machine is order-aware on the log; every arm executes its edge.
approve_probe() { # $1 extra frontmatter lines (sed replacement tail)
    sed -i "s/^status: active/status: active$1/" "$(meta_file RM-9001)"
}

# 9d. THE #333 shape: approved, amended after approval, NO field
new_scratch n9d
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 amended after approval without field" \
    "amended after approval"

# 9e. control: the same tree WITH the field stays green
new_scratch n9e
approve_probe '\nreviewed: 2026-10-16\namended: 2026-10-31'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 amended field green" "0 blocking"

# 9f. amended without any approval before it (never-approved metas
#     are pending via the absent reviewed:, the field is redundant)
new_scratch n9f
approve_probe '\namended: 2026-10-31'
printf '%s\n' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 amended without prior approval" \
    "amendment-after-approval only"

# 9g. amended date with no amendment log line of that date (pairing,
#     the #233 class: field and log must agree)
new_scratch n9g
approve_probe '\nreviewed: 2026-10-16\namended: 2026-10-30'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 amended pairing" \
    "no amendment log line of that date"

# 9h. stale field: a later approval exists (re-approval landed, the
#     field must be dropped -- reviewed: already carries the new date)
new_scratch n9h
approve_probe '\nreviewed: 2026-11-05\namended: 2026-10-31'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    '- 2026-11-05 approved by maintainer (re-approval scratch probe).' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 stale amended field" "stale amended"

# 9i. same-day approve-then-amend re-queues: log ORDER decides what
#     dates cannot (the #333 design decision)
new_scratch n9i
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-16 amended — same-day scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 same-day approve-then-amend re-queues" \
    "amended after approval"

# 9j. same-day amend-then-approve is the fresh approval: green, no
#     field required (the order-aware control for 9i)
new_scratch n9j
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-16 amended — same-day scratch amendment; maintainer review pending.' \
    '- 2026-10-16 approved by maintainer (scratch probe).' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 same-day amend-then-approve approved" "0 blocking"

# 9k. an amendment BEFORE the approval does not re-queue (pre-approval
#     tweaks ride the approval; only post-approval changes count)
new_scratch n9k
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-10 amended — pre-approval scratch tweak.' \
    '- 2026-10-16 approved by maintainer (scratch probe).' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 pre-approval amendment stays approved" "0 blocking"

# 9l. never-approved + amendment log line: pending via absent
#     reviewed:, no field needed (the pending-amendment shape that
#     predates the field -- amendment lines alone must stay legal)
new_scratch n9l
printf '%s\n' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 never-approved amendment stays pending" "0 blocking"

# 9m-9q. #337 a A1 vocabulary pins: an amendment event is a dated log
#     line carrying the STANDALONE word "amended" -- subject-prefixed
#     corpus phrasings count, glued near-miss tokens do not, and lines
#     opening with another event keyword are never amendment events.
# 9m. post-approval "rationale amended" phrasing, fieldless: the #333
#     gap must fire (round-a verifier probe P1's shape)
new_scratch n9m
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 rationale amended from maintainer input — scratch.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 subject-prefixed amendment re-queues" \
    "amended after approval"

# 9n. the same phrasing pairs with the field: green
new_scratch n9n
approve_probe '\nreviewed: 2026-10-16\namended: 2026-10-31'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 rationale amended from maintainer input — scratch.' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 subject-prefixed amendment pairs" "0 blocking"

# 9o. glued near-miss tokens are NOT events: field + only an
#     "amendedness" line of that date blocks unpaired (word-exact)
new_scratch n9o
approve_probe '\nreviewed: 2026-10-16\namended: 2026-10-31'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amendedness check ran on the corpus; nothing changed.' \
    >>"$(meta_file RM-9001)"
expect_block "inv9 glued amended-token is not an event" \
    "no amendment log line of that date"

# 9p. approval free text mentioning "amended" stays an approval event
#     (the call-site dispatch classifies approved-by-maintainer lines
#     before the amendment scan ever runs on them)
new_scratch n9p
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' \
    '- 2026-10-16 approved by maintainer (wording amended in chat).' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 approval free text is not an amendment event" \
    "0 blocking"

# 9q. a revisit note mentioning "amended" is not an amendment event
#     either (revisits run after approvals; findings notes name edits)
new_scratch n9q
approve_probe '\nreviewed: 2026-10-16'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-11-05 revisit findings — rationale amended upstream (interval reset to 1m from 1m, next 2026-12-05).' \
    >>"$(meta_file RM-9001)"
expect_ok "inv9 revisit note is not an amendment event" "0 blocking"

# 6d. inv 6 -- amended is a date when present
new_scratch n6d
approve_probe '\nreviewed: 2026-10-16\namended: soon'
printf '%s\n' '- 2026-10-16 approved by maintainer (scratch probe).' \
    '- 2026-10-31 amended — scratch amendment; maintainer review pending.' \
    >>"$(meta_file RM-9001)"
expect_block "inv6 bad amended date" "amended not an ISO date"

# 322 (#322 scripts part): gen-rules-index dies loud on an unlistable
#     bucket directory -- glob.glob silently swallowed PermissionError
#     and wrote a short INDEX with rc 0 (the docstring promise
#     violated). Control first: the readable tree generates rc 0. Probe
#     runs as the non-root suite user; root skips disclosed, like the
#     peers (#318 a B3) -- chmod 000 cannot block a root reader.
if [ "$(id -u)" -eq 0 ]; then
    echo "  pin skipped: #322 gen bucket probe needs a non-root uid (root reads through 000)"
else
    new_scratch n322
    write_meta RM-9011 "Unreadable demo rule" agent/conventions.md interactive-prompts-yn ""
    if (cd "$SCRATCH" && python3 scripts/gen-rules-index.py) >/dev/null 2>&1; then
        pass "#322 control: readable tree generates rc 0"
    else
        fail "#322 control: readable tree must generate rc 0"
    fi
    chmod 000 "$SCRATCH/internal/rules-meta/9/0/1"
    OUT=$(cd "$SCRATCH" && python3 scripts/gen-rules-index.py 2>&1)
    RC=$?
    case "$OUT" in
        *'cannot list bucket directory'*)
            if [ "$RC" -ne 0 ]; then
                pass "#322 gen die: bucket message with non-zero rc"
            else
                fail "#322 gen die: message but rc=0"
            fi
            ;;
        *) fail "#322 gen die: lacks the bucket message: $OUT" ;;
    esac
    chmod 755 "$SCRATCH/internal/rules-meta/9/0/1" # teardown
fi

# 6c. inv 6 -- duplicate frontmatter keys block (#321): a malformed
#     hand edit (the #233 slip class) used to split the three
#     extractors (shell first-wins, gen last-wins). Both orders block;
#     the standalone INDEX generator dies on the same tree (fail-loud
#     structural promise -- order-independent, one arm pinned), so a
#     duplicate-key-blocked run never rewrites INDEX.md: gen dies on
#     the same tree before any write. (Other blocked causes do regen
#     when gen accepts the tree; the finderr gate is the separate,
#     stronger skip -- audit inv 8.)
new_scratch n6c
printf 'sentinel INDEX -- must survive a blocked run\n' \
    >"$SCRATCH/internal/rules-meta/INDEX.md"
sed -i 's/^status: active$/status: active\nstatus: retired/' \
    "$(meta_file RM-9001)"
expect_block "inv6 duplicate key blocks (dup status)" \
    "duplicate frontmatter key: status"
if grep -qxF 'sentinel INDEX -- must survive a blocked run' \
    "$SCRATCH/internal/rules-meta/INDEX.md"; then
    pass "inv6 duplicate key: INDEX survives a blocked run"
else
    fail "inv6 duplicate key: INDEX rewritten on a blocked run"
fi
OUT=$(cd "$SCRATCH" && python3 scripts/gen-rules-index.py 2>&1)
RC=$?
case "$OUT" in
    *'duplicate frontmatter key'*)
        if [ "$RC" -ne 0 ]; then
            pass "inv6 gen die: duplicate-key message with non-zero rc"
        else
            fail "inv6 gen die: message but rc=0"
        fi
        ;;
    *) fail "inv6 gen die: lacks the duplicate-key message: $OUT" ;;
esac
new_scratch n6c2
sed -i 's/^status: active$/status: active\nreviewed: 2026-05-01\nreviewed:/' \
    "$(meta_file RM-9001)"
expect_block "inv6 duplicate key blocks (dated-first reviewed)" \
    "duplicate frontmatter key: reviewed"

# 7. overdue is report-only
new_scratch n7
sed -i 's/^created: 2026-10-16/created: 2026-09-01/; s/^next-revisit: 2026-11-16/next-revisit: 2026-10-01/' "$(meta_file RM-9001)"
expect_ok "inv7 overdue non-blocking" "overdue metas"

# 7b. #527: an audit run over an overdue tree leaves the date-invariant
#     INDEX — byte-identical to the bare generator output the parity
#     gate pins. The audit's regen used to pass FORCE_TODAY, so the
#     scratch INDEX carried the Overdue variant and the next make test
#     rejected the tree with the misleading hand-edit message.
cp "$SCRATCH/internal/rules-meta/INDEX.md" "$WORK/index7.audit"
(cd "$SCRATCH" && python3 scripts/gen-rules-index.py) >/dev/null 2>&1 ||
    fail "inv7b: bare regen exited non-zero -- pin exercised nothing (#529 a A1)"
if cmp -s "$SCRATCH/internal/rules-meta/INDEX.md" "$WORK/index7.audit"; then
    pass "inv7b audit leaves the date-invariant INDEX (#527)"
else
    fail "inv7b: audit wrote a date-dependent INDEX variant (#527)"
fi

# 8. stale INDEX regenerates without blocking
new_scratch n8
run_audit # first run regenerates the scratch INDEX
printf 'hand edit\n' >>"$SCRATCH/internal/rules-meta/INDEX.md"
expect_ok "inv8 stale INDEX non-blocking" "INDEX regenerated"
if grep -q '^hand edit$' "$SCRATCH/internal/rules-meta/INDEX.md"; then
    fail "inv8: INDEX was not rewritten to the generated state"
else
    pass "inv8: INDEX rewritten to the generated state"
fi

# 10. no fake findings -- every real meta ID occurs at exactly THREE
#     genuine sites: the trailing (RM-NNNN) ref at its rule unit, the
#     id: line in its meta file, and its generated row in the
#     rule-meta INDEX (machine-made and parity-pinned -- lanes a-c do
#     not scan it). Every other occurrence is a bug (ID ranges,
#     prose, comments, cross-refs): searching an ID must only ever
#     hit genuine sites.
#     Exempt: the generated INDEX.md, frozen history (internal/reviews,
#     internal/records/_archive), and the 9xxx abstract test namespace.
#     Lanes: (a) scope files -- only ref-form tokens; (b) meta files --
#     only the own id line; (c) everywhere else -- no real ID at all.
#     Scope list is derived from the audit script (drifts loud: an
#     empty extraction fails this pin's setup).
SCOPE=$(sed -n 's/^SCOPE_FILES="\(.*\)"$/\1/p' "$REPO_ROOT/scripts/rules-audit.sh")
if [ -n "$SCOPE" ]; then
    pass "pin10 setup: SCOPE_FILES extracted from rules-audit.sh"
else
    fail "pin10 setup: SCOPE_FILES not extractable from rules-audit.sh"
fi
# lane a: scope files -- only ref-form tokens. One verdict for the
# whole lane (per-file detail lands in the failure output), so the
# suite's printed pin count does not drift with SCOPE_FILES length
# (#189 a W2 fix; the shape mirrors lanes b and c).
: >"$WORK/p10a"
for f in $SCOPE; do
    if [ ! -f "$REPO_ROOT/$f" ]; then
        fail "pin10 setup: scope file missing: $f"
        continue
    fi
    # #519 (the lane-b class): an unreadable-but-present scope file
    # made sed die silently inside the pipe -- the lane read clean.
    if [ ! -r "$REPO_ROOT/$f" ]; then
        fail "pin10 lane a: scope file unreadable: $f (#519)"
        continue
    fi
    # #522 (from #520 review a A2): the bare || true swallowed the pipe
    # rc wholesale -- sfx_scan's per-file capture instead, with grep
    # ending the pipe so its rc is the observable one: rc 1 stays the
    # normal empty contribution (no non-ref IDs), rc > 1 fails loud.
    # The rc > 1 arm has no hermetic trigger (grep reads the pipe, not
    # a file operand; the -r pre-check above owns the readable leg) --
    # residual per #522: a scope file vanishing between the -r check
    # and the open still reads as the empty contribution.
    _pa_rc=0
    _pa_hits="$(sed 's/(RM-[0-9][0-9][0-9][0-9])//g' "$REPO_ROOT/$f" |
        grep -n 'RM-[0-9][0-9][0-9][0-9]')" || _pa_rc=$?
    if [ "$_pa_rc" -gt 1 ]; then
        fail "pin10 lane a: detector died on $f (rc=$_pa_rc) -- lane output unreliable (#522)"
        continue
    fi
    if [ -n "$_pa_hits" ]; then
        printf '%s\n' "$_pa_hits" | sed "s|^|$f:|" >>"$WORK/p10a"
    fi
done
if [ -s "$WORK/p10a" ]; then
    fail "pin10 lane a, fake ID mention(s) in scope files:"
    sed 's/^/         /' "$WORK/p10a"
else
    pass "pin10 lane a: scope files carry only ref-form tokens"
fi

# lane b: meta files carry only their own id -- cross-references in
# meta bodies name the rule text, never an ID
# #519 (from #516 a A5's class): the producer ran find behind
# 2>/dev/null into a pipe -- a find death left the lane empty and read
# as a clean pass. The scan is a guarded producer now (rc + non-empty
# + per-file readability), and the loop feeds from a FILE, not a pipe,
# so the fail rows sit in the main shell (the counter survives,
# conventions.md "Script output style").
p10b_scan() { # $1 = meta dir, $2 = dst list; loud on death/empty
    # #522 (from #520 review a A1): the rc is captured beside the find
    # -- inside `if ! find` the negation left $? at 0, so the death
    # message always printed rc=0. Lane c's capture pattern (below).
    _pb_rc=0
    find "$1" -type f -name 'RM-*.md' >"$2" || _pb_rc=$?
    if [ "$_pb_rc" -ne 0 ]; then
        echo "rules-meta pin10: lane b scan died on '$1' (rc=$_pb_rc) -- lane output unreliable (#519)" >&2
        return 1
    fi
    if [ ! -s "$2" ]; then
        echo "rules-meta pin10: lane b scan empty on '$1' -- lane output unreliable (#519)" >&2
        return 1
    fi
}
if ! p10b_scan "$REPO_ROOT/internal/rules-meta" "$WORK/p10b.list"; then
    fail "pin10 lane b: rules-meta scan unreliable (#519)"
else
    LC_ALL=C sort "$WORK/p10b.list" >"$WORK/p10b.sorted"
    : >"$WORK/p10b"
    while IFS= read -r m; do
        own=$(basename "$m" .md)
        if [ ! -r "$m" ]; then
            fail "pin10 lane b: unreadable meta file: ${m#"$REPO_ROOT"/} (#519)"
            continue
        fi
        sed "s/^id: $own\$//" "$m" |
            grep -n 'RM-[0-9][0-9][0-9][0-9]' |
            sed "s|^|${m#"$REPO_ROOT"/}:|" >>"$WORK/p10b"
    done <"$WORK/p10b.sorted"
    if [ -s "$WORK/p10b" ]; then
        fail "pin10 lane b, foreign ID mention(s) inside meta files:"
        sed 's/^/         /' "$WORK/p10b"
    else
        pass "pin10 lane b: meta files carry only their own id"
    fi
fi

# lane c helper: greps <root> for real IDs with the frozen-corpus
# exemptions; <scope> = the SCOPE_FILES list (space-separated). Shared
# by the real-tree lane and the scratch pins below so the pins cannot
# drift from the enforced shape (#235 a Q4). Two NARROW exemption
# classes, both frozen evidence quoting IDs verbatim:
# (1) internal/reviews/: the generated, frozen legacy-index and frozen
#     case folders only -- living files under internal/reviews/ are
#     covered. The corpus INDEX alternative was dropped post-archive
#     (#294): the generated INDEX lives at tag review-corpus, so an
#     INDEX.md under internal/reviews/ would be a LIVING recreated
#     file and is caught.
# (2) internal/reviews-meta/<date>/: frozen per-run analysis data
#     (#297) -- the dated run folders' data/ files quote findings
#     verbatim; living files there (README.md at the root) stay
#     covered. *.json is in the include list BECAUSE of this class:
#     without it the whole .json world was invisible to the guard.
p10_lane_c_hits() { # $1 root, $2 scope; loud on scan death (#519:
    # the raw grep ran behind 2>/dev/null -- a grep death degraded
    # silently: a death mid-traversal left partial rows flowing (the
    # lane read green over missing coverage), a death before any rows
    # read as a clean tree; rc 1 = no matches stays the normal clean
    # case, rc >= 2 is the loud path now)
    # Traversal-level dumps prune (#587): e2e run evidence under
    # tests/e2e/dumps/ is container-created (container-UID-owned,
    # mode 700 -- the live make test died rc 2 mid-traversal; a
    # post-filter grep -v chain cannot prevent a traversal death),
    # and dump copies of repo files quoting RM-NNNN would false-red
    # as fourth-site citations. Same exemption rationale as the
    # line-length ratchet's reviews-meta data/ carve-out.
    # Basename-scoped by --exclude-dir (matches at any depth):
    # tests/e2e/dumps is the only dumps dir in-tree (created by
    # tests/e2e/lib.sh); class sweep #587 found no other unit-lane
    # scan walking the repo root -- every other traversal targets
    # scratch, files/, .agents/skills/, or explicit path lists
    # (skills-lint: scratch + .agents/skills; update-core: scratch
    # + files/; status: scratch + files/; wsl-exposure: files/;
    # workflows, line-length: explicit lists; sandbox-policy: an
    # explicit tests/e2e '*.sh' walk -- descends toward dumps when
    # readable, shielded today by container ownership, a readable
    # dump with an unguarded rm-suffix shape would false-red
    # check 3, #593 b B2).
    _c_rc=0
    grep -rn "RM-[0-9][0-9][0-9][0-9]" \
        --include="*.md" --include="*.sh" --include="*.py" --include="*.yml" \
        --include="*.json" \
        --exclude-dir=dumps \
        "$1" >"$WORK/p10c.raw" || _c_rc=$?
    if [ "$_c_rc" -gt 1 ]; then
        echo "rules-meta pin10: lane c scan died (rc=$_c_rc) -- lane output unreliable (#519)" >&2
        return 1
    fi
    grep -v "/internal/rules-meta/" "$WORK/p10c.raw" |
        grep -v -E "/internal/reviews/legacy-index\.md" |
        grep -v -E "/internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-[0-9]+/" |
        grep -v -E "/internal/reviews-meta/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/" |
        grep -v "/internal/records/_archive/" |
        while IFS= read -r _l; do
            _rel=${_l%%:*}
            _rel=${_rel#"$1"/}
            case " $2 " in
                *" $_rel "*) continue ;;
            esac
            _l=$(printf '%s' "$_l" | sed 's/RM-9[0-9][0-9][0-9]//g')
            case $_l in
                *RM-[0-9][0-9][0-9][0-9]*) printf '%s\n' "$_l" ;;
            esac
        done
}

# lane c: the rest of the living tree carries no real ID at all
: >"$WORK/p10c"
if ! p10_lane_c_hits "$REPO_ROOT" "$SCOPE" >"$WORK/p10c"; then
    fail "pin10 lane c: tree scan died -- lane output unreliable (#519)"
elif [ -s "$WORK/p10c" ]; then
    fail "pin10 lane c, real ID(s) outside refs and meta files:"
    sed 's/^/         /' "$WORK/p10c"
else
    pass "pin10 lane c: no real ID outside refs and meta files"
fi

# lane c scratch pins (#235 a Q4): a LIVING README.md under
# internal/reviews/ citing an ID must be caught; a FROZEN snapshot in
# a case folder quoting IDs as verbatim evidence must stay exempt.
# Post-archive (#294): a recreated in-tree INDEX.md is a LIVING file
# (the generated corpus INDEX lives at the tag) -- it must be caught;
# the generated, frozen legacy-index stays exempt by the narrow rule.
# #297: a LIVING .json citing an ID must be caught too (the include
# list was .json-blind); frozen per-run data under a dated
# reviews-meta folder stays exempt (verbatim evidence, same class as
# the frozen corpus folders).
# The demo ID is concatenated at runtime so this test file's own
# source never carries a literal real-ID token (lane c scans *.sh).
_p10demo="RM-00""44"
P10S="$WORK/p10scratch.$$"
mkdir -p "$P10S/internal/reviews/0/0/0/1/pr-00001"
mkdir -p "$P10S/internal/reviews-meta/2026-01-01/data"
printf 'Living file citing a rule by ID (%s) instead of file+section.\n' \
    "$_p10demo" >"$P10S/internal/reviews/README.md"
printf 'Recreated generated index still citing %s.\n' \
    "$_p10demo" >"$P10S/internal/reviews/INDEX.md"
printf 'Generated frozen map file citing %s.\n' \
    "$_p10demo" >"$P10S/internal/reviews/legacy-index.md"
printf 'Frozen snapshot quoting %s as verbatim evidence.\n' \
    "$_p10demo" >"$P10S/internal/reviews/0/0/0/1/pr-00001/review-a.md"
printf '{"living": "citing %s in a living json file"}\n' \
    "$_p10demo" >"$P10S/living-data.json"
printf '{"frozen": "run data quoting %s as verbatim evidence"}\n' \
    "$_p10demo" >"$P10S/internal/reviews-meta/2026-01-01/data/run.json"
_hits=$(p10_lane_c_hits "$P10S" "")
case "$_hits" in
    *internal/reviews/README.md*)
        case "$_hits" in
            *internal/reviews/INDEX.md*)
                case "$_hits" in
                    */living-data.json*)
                        case "$_hits" in
                            *pr-00001*) fail "pin10 lane c scratch: frozen snapshot flagged" ;;
                            *internal/reviews/legacy-index.md*) fail "pin10 lane c scratch: frozen legacy-index flagged" ;;
                            *internal/reviews-meta/2026-01-01/*) fail "pin10 lane c scratch: frozen run data flagged" ;;
                            *) pass "pin10 lane c scratch: living citations caught, frozen files exempt" ;;
                        esac
                        ;;
                    *) fail "pin10 lane c scratch: living .json citation not caught" ;;
                esac
                ;;
            *) fail "pin10 lane c scratch: recreated INDEX citation not caught (post-archive: living file)" ;;
        esac
        ;;
    *) fail "pin10 lane c scratch: README citation not caught" ;;
esac

# --- #587 dumps prune arm: e2e run evidence under tests/e2e/dumps/
# must neither kill the scan (unreadable container-made tree) nor
# count as citations (readable dump copies quoting IDs verbatim),
# while the living tree stays covered. Root-context caveat (mirror
# of the #520 a B4 note below): as root, grep reads through chmod
# 000 and the death leg trivially holds -- the readable-capture leg
# still discriminates (the dump copy must stay absent from hits).
P10D="$WORK/p10dumps.$$"
mkdir -p "$P10D/tests/e2e/dumps/run-20260101-000000/tmp" "$P10D/docs"
printf 'container-made run evidence\n' \
    >"$P10D/tests/e2e/dumps/run-20260101-000000/tmp/containers-user-1001.md"
chmod 000 "$P10D/tests/e2e/dumps/run-20260101-000000/tmp"
printf 'readable dump copy quoting %s verbatim\n' "$_p10demo" \
    >"$P10D/tests/e2e/dumps/run-20260101-000000/captured.md"
printf 'living doc citing %s by bare ID\n' "$_p10demo" >"$P10D/docs/living.md"
_pd_rc=0
_pd_out="$(p10_lane_c_hits "$P10D" "")" || _pd_rc=$?
if [ "$_pd_rc" -eq 0 ] &&
    ! printf '%s\n' "$_pd_out" | grep -q 'dumps/run-20260101' &&
    printf '%s\n' "$_pd_out" | grep -q 'docs/living.md'; then
    pass "pin10 lane c dumps prune: run evidence exempt (unreadable + readable), living citations kept (#587)"
else
    fail "pin10 lane c dumps prune: run evidence must stay traversal-exempt, living citations kept (rc=$_pd_rc) (#587)"
fi
chmod 755 "$P10D/tests/e2e/dumps/run-20260101-000000/tmp" # teardown rc 2 guard

# --- #519 guard arms: executed death paths for the lane producers -------------
# lane b death leg (vanished dir) and empty leg (existing, empty);
# lane c death leg (unreadable file under the scan root -- grep rc 2).
# All three must fail loud with their guard message on stderr and a
# nonzero rc, observed the way a failing lane observes it (stdout
# discarded, stderr captured).
# Root-context caveat (#520 a B4): the lane c death is DAC-enforced
# (chmod 000) -- as root grep reads through and this arm false-reds;
# no root invocation path exists for this suite today (CI runner
# user, no e2e/kit-script call site).
_gb_rc=0
_gb_err="$( (p10b_scan "$WORK/no-such-metadir-$$" "$WORK/p10b.arm") 2>&1 >/dev/null)" || _gb_rc=$?
# The rc=0) veto pins the #522 a A1 capture: the old negated-if shape
# printed rc=0 here (dying find -> negation -> $? 0)
if [ "$_gb_rc" -ne 0 ] && printf '%s\n' "$_gb_err" | grep -q 'lane b scan died' &&
    ! printf '%s\n' "$_gb_err" | grep -q 'rc=0)'; then
    pass "pin10 lane b guard: scan death fails loud, rc reported (#519, #522)"
else
    fail "pin10 lane b guard: a scan death must fail loud with a real rc (rc=$_gb_rc) (#519, #522)"
fi
mkdir -p "$WORK/p10b-empty.$$"
_gb_rc=0
_gb_err="$( (p10b_scan "$WORK/p10b-empty.$$" "$WORK/p10b.arm") 2>&1 >/dev/null)" || _gb_rc=$?
if [ "$_gb_rc" -ne 0 ] && printf '%s\n' "$_gb_err" | grep -q 'lane b scan empty'; then
    pass "pin10 lane b guard: empty scan fails loud (#519)"
else
    fail "pin10 lane b guard: an empty scan must fail loud (rc=$_gb_rc) (#519)"
fi
_gc_dir="$WORK/p10guard.$$"
mkdir -p "$_gc_dir"
printf 'unreadable\n' >"$_gc_dir/hidden.md"
chmod 000 "$_gc_dir/hidden.md"
_gc_rc=0
_gc_err="$( (p10_lane_c_hits "$_gc_dir" "") 2>&1 >/dev/null)" || _gc_rc=$?
if [ "$_gc_rc" -ne 0 ] && printf '%s\n' "$_gc_err" | grep -q 'lane c scan died'; then
    pass "pin10 lane c guard: scan death fails loud (#519)"
else
    fail "pin10 lane c guard: an unreadable scan root must fail loud (rc=$_gc_rc) (#519)"
fi

# 11. ACTIVE_SECTIONS anchors resolve to real headings (#540 §4): a
#     typo'd or stale entry is silently inert -- the audit attributes
#     no units to it, inv1 never fires for it, and the only coverage
#     is incidental (inv5 back-refs lapse if the referencing metas
#     retire). The pin extracts the audit's own ACTIVE_SECTIONS list
#     and asserts every entry's file exists and its anchor equals the
#     audit's slugging of a real heading in that file (fences skipped,
#     same transform as rules-audit.sh's awk).
_active_sections_list() { # $1: audit script -> entries on stdout, dies loud
    if [ ! -r "$1" ]; then
        echo "active-sections extract died: unreadable $1" >&2
        return 1
    fi
    # Residual (round a D2, strictly narrower than pin 10 lane a's
    # disclosed #522 sibling): the || observes the LAST sed only; a
    # mid-stream death of the first sed could emit a partial list --
    # hard deaths and the unreadable case are caught (-r pre-check,
    # the empty assertion in _active_check), an exotic partial emit
    # is not.
    sed -n 's/^ACTIVE_SECTIONS=//p' "$1" |
        sed 's/^"\$ACTIVE_SECTIONS //; s/^"//; s/"$//' || {
        echo "active-sections extract died: sed rc=$? on $1" >&2
        return 1
    }
}

_active_headings() { # $1: markdown file -> slugged headings, dies loud
    if [ ! -r "$1" ]; then
        echo "active-headings scan died: unreadable $1" >&2
        return 1
    fi
    awk '
        /^```/ { fence = !fence; next }
        fence { next }
        /^#{1,6}[ \t]/ {
            h = $0; sub(/^#+[ \t]+/, "", h); sub(/[ \t]*#*$/, "", h)
            tmp = tolower(h)
            gsub(/[^a-z0-9 -]/, "", tmp)
            gsub(/^ +| +$/, "", tmp); gsub(/ +/, " ", tmp); gsub(/ /, "-", tmp)
            print tmp
        }
    ' "$1" || {
        echo "active-headings scan died: awk rc=$? on $1" >&2
        return 1
    }
}

_active_check() { # $1: audit script, $2: findings out-file
    _ac_list=$WORK/active-sections.$$.tmp
    if ! _active_sections_list "$1" >"$_ac_list" || [ ! -s "$_ac_list" ]; then
        printf '%s\n' "extraction died or empty (audit: $1)" >>"$2"
        return 1
    fi
    while IFS= read -r _ac_e; do
        [ -n "$_ac_e" ] || continue
        _ac_f=${_ac_e%#*}
        _ac_a=${_ac_e#*#}
        if [ ! -f "$REPO_ROOT/$_ac_f" ]; then
            printf '%s\n' "$_ac_e (file missing: $_ac_f)" >>"$2"
            continue
        fi
        if ! _active_headings "$REPO_ROOT/$_ac_f" | grep -qxF "$_ac_a"; then
            printf '%s\n' "$_ac_e (anchor '$_ac_a' not a heading in $_ac_f)" >>"$2"
        fi
    done <"$_ac_list"
    return 0
}

: >"$WORK/p11"
# Boundary (round a D3): the pin reads entry files directly; the audit
# slugs headings only inside its SCOPE_FILES loop -- an entry whose
# file left SCOPE_FILES but kept a valid heading stays pin-green yet
# audit-inert. 33/33 entries sit in SCOPE_FILES today (no live
# divergence); disclosed here so the next reader does not re-derive it.
_active_check "$REPO_ROOT/scripts/rules-audit.sh" "$WORK/p11"
if [ -s "$WORK/p11" ]; then
    fail "pin11: ACTIVE_SECTIONS entr(ies) resolving to no real heading:"
    sed 's/^/         /' "$WORK/p11"
else
    _n11=$(_active_sections_list "$REPO_ROOT/scripts/rules-audit.sh" | grep -c .)
    pass "pin11: every ACTIVE_SECTIONS entry resolves to a real heading ($_n11 checked)"
fi

# executed mismatch arm: a scratch extraction carrying one bogus entry
# must land exactly that row in the findings file -- the failure path
# runs, it does not merely exist (hermetic: the real audit is read-only).
P11S="$WORK/p11scratch.$$"
grep '^ACTIVE_SECTIONS=' "$REPO_ROOT/scripts/rules-audit.sh" >"$P11S"
printf '%s\n' 'ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#no-such-heading-pin11"' >>"$P11S"
: >"$WORK/p11arm"
_active_check "$P11S" "$WORK/p11arm"
if grep -q 'no-such-heading-pin11' "$WORK/p11arm" &&
    [ "$(grep -c . "$WORK/p11arm")" -eq 1 ]; then
    pass "pin11 mismatch arm: bogus entry flagged, real entries clean"
else
    fail "pin11 mismatch arm: the bogus scratch entry must be the one flagged row"
fi

# --- guard arms: executed death paths for the two producers (#519 class) -------
_ga_rc=0
_ga_err="$( (_active_sections_list "$WORK/no-such-audit-$$") 2>&1 >/dev/null)" || _ga_rc=$?
if [ "$_ga_rc" -ne 0 ] && printf '%s\n' "$_ga_err" | grep -q 'active-sections extract died'; then
    pass "pin11 extract guard: unreadable audit fails loud"
else
    fail "pin11 extract guard: an unreadable audit must fail loud (rc=$_ga_rc)"
fi
_ga_rc=0
_ga_err="$( (_active_headings "$WORK/no-such-headings-$$") 2>&1 >/dev/null)" || _ga_rc=$?
if [ "$_ga_rc" -ne 0 ] && printf '%s\n' "$_ga_err" | grep -q 'active-headings scan died'; then
    pass "pin11 headings guard: unreadable file fails loud"
else
    fail "pin11 headings guard: an unreadable file must fail loud (rc=$_ga_rc)"
fi

# ------------------------------------------------------------- summary
suite_done "rules-meta audit pins"
