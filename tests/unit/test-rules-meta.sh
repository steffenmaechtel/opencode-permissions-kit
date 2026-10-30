#!/bin/sh
# test-rules-meta.sh -- pins scripts/rules-audit.sh (invariants 1-9)
# plus the no-fake-findings pin 10: outside the trailing (RM-NNNN)
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

RED=''
NC=''
[ -t 1 ] && RED='\033[31m' && NC='\033[0m'

WORK=$(mktemp -d /tmp/test-rules-meta.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
FAILS=$WORK/fails
: >"$FAILS"
passed=0

fail() { printf '  %sFAIL%s  %s\n' "${RED:-}" "${NC:-}" "$1" >>"$FAILS"; }
pass() { passed=$((passed + 1)); }

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
        *"$2"*) pass ;;
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
        *"$2"*) pass ;;
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
    pass
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

# 7. overdue is report-only
new_scratch n7
sed -i 's/^created: 2026-10-16/created: 2026-09-01/; s/^next-revisit: 2026-11-16/next-revisit: 2026-10-01/' "$(meta_file RM-9001)"
expect_ok "inv7 overdue non-blocking" "overdue metas"

# 8. stale INDEX regenerates without blocking
new_scratch n8
run_audit # first run regenerates the scratch INDEX
printf 'hand edit\n' >>"$SCRATCH/internal/rules-meta/INDEX.md"
expect_ok "inv8 stale INDEX non-blocking" "INDEX regenerated"
if grep -q '^hand edit$' "$SCRATCH/internal/rules-meta/INDEX.md"; then
    fail "inv8: INDEX was not rewritten to the generated state"
else
    pass
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
    pass
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
    sed 's/(RM-[0-9][0-9][0-9][0-9])//g' "$REPO_ROOT/$f" |
        grep -n 'RM-[0-9][0-9][0-9][0-9]' |
        sed "s|^|$f:|" >>"$WORK/p10a" || true
done
if [ -s "$WORK/p10a" ]; then
    fail "pin10 lane a, fake ID mention(s) in scope files:"
    sed 's/^/         /' "$WORK/p10a" >>"$FAILS"
else
    pass
fi

# lane b: meta files carry only their own id -- cross-references in
# meta bodies name the rule text, never an ID
: >"$WORK/p10b"
find "$REPO_ROOT/internal/rules-meta" -type f -name 'RM-*.md' 2>/dev/null |
    LC_ALL=C sort | while IFS= read -r m; do
    own=$(basename "$m" .md)
    sed "s/^id: $own\$//" "$m" |
        grep -n 'RM-[0-9][0-9][0-9][0-9]' |
        sed "s|^|${m#"$REPO_ROOT"/}:|" >>"$WORK/p10b"
done
if [ -s "$WORK/p10b" ]; then
    fail "pin10 lane b, foreign ID mention(s) inside meta files:"
    sed 's/^/         /' "$WORK/p10b" >>"$FAILS"
else
    pass
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
p10_lane_c_hits() { # $1 root, $2 scope
    grep -rn "RM-[0-9][0-9][0-9][0-9]" \
        --include="*.md" --include="*.sh" --include="*.py" --include="*.yml" \
        --include="*.json" \
        "$1" 2>/dev/null |
        grep -v "/internal/rules-meta/" |
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
p10_lane_c_hits "$REPO_ROOT" "$SCOPE" >"$WORK/p10c"
if [ -s "$WORK/p10c" ]; then
    fail "pin10 lane c, real ID(s) outside refs and meta files:"
    sed 's/^/         /' "$WORK/p10c" >>"$FAILS"
else
    pass
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
                            *) pass ;;
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

# ------------------------------------------------------------- summary
if [ -s "$FAILS" ]; then
    printf 'rules-meta audit pins: FAILED\n'
    cat "$FAILS"
    exit 1
fi
printf 'rules-meta audit pins: OK (%s pins green)\n' "$passed"
