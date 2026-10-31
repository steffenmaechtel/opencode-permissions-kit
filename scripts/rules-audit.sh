#!/bin/sh
# rules-audit.sh -- deterministic audit of the rule-meta system
#
# Invariants per internal/records/rules-meta.md ("Audit invariants"):
#   1. every rule unit in an ACTIVE section carries exactly one
#      (RM-NNNN) ref (units = col-0 list items; tables/paragraphs are
#      not units; fenced blocks skipped)
#   2. every ref resolves: internal/rules-meta/<N>/<N>/<N>/RM-NNNN.md
#      exists (bucket = first three ID digits)
#   3. 1:1 -- a meta referenced by two units fails; an active meta
#      without any ref in the scope files fails (orphan)
#   4. filename <-> id: identical; IDs unique; id format RM-NNNN
#   5. the rule: back-ref exists (file + heading anchor) and the
#      quote: prefix is findable -- both sides normalized: code
#      backticks and bold markers stripped, wrapped lines joined,
#      whitespace squeezed; the needle is the quote's first five
#      words (plain-text rendering, the established meta practice).
#      Retired metas are exempt (the retire rule): retirement removes the
#      rule bullet, so neither anchor-quote pairing nor quote
#      findability can hold.
#   6. frontmatter complete, ISO dates, next-revisit >= created,
#      status/interval vocabulary, no duplicate keys (#321: malformed
#      hand edit, the #233 slip class -- FIRST wins canonically where
#      extraction runs ungated; duplicates block)
#   9. approval consistency: reviewed: is set exactly when the review
#      log carries an "approved by maintainer" line of the same date;
#      a bare "reviewed:" line (key without a value) blocks -- approval
#      membership is key-presence-with-value (#233)
#
# Report-only (non-blocking -- overdue is a maintenance signal):
# 7. overdue list sorted by lateness; 8. INDEX.md regenerated on every
#    audit run (python3 + gen-rules-index.py present)
# The Phase-2 pending-unit parking valve (prefix-matched ref-less
# units reported non-blocking) was retired 2026-10-17 when its five
# occupants received metas -- a ref-less unit in an ACTIVE section
# now always blocks.
#
# Scope lives HERE, reviewable (record: "the section allowlist lives
# in the audit script"): SCOPE_FILES are scanned for refs (2, 3);
# ACTIVE_SECTIONS additionally enforce unit refs (1). Phase 3 is
# complete: the agent/ files and AGENTS.md ## Rules are in scope;
# learnings.md stays out (record decision 10).
#
# Exit: 1 on blocking violations (1-6, 9) and [meta-tree] scope
#      errors, 0 otherwise.
# Env: RM_AUDIT_ROOT (run against another tree -- tests),
#      FORCE_TODAY (pin the date for overdue/report checks).

set -u

if [ -n "${RM_AUDIT_ROOT:-}" ]; then
    ROOT=$(cd -- "$RM_AUDIT_ROOT" && pwd) || exit 1
else
    ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
fi
TODAY=${FORCE_TODAY:-$(date +%F)}
METAS=internal/rules-meta

SCOPE_FILES="AGENTS.md agent/conventions.md agent/test-fidelity.md agent/review-concept.md internal/records/rules-meta.md"
ACTIVE_SECTIONS="AGENTS.md#rules"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#interactive-prompts-yn"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#script-output-style"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#shell-security-untrusted-input"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#test-sandbox-unit-suites"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#referencing-review-findings"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#referencing-house-rules-rm-keys"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS internal/records/rules-meta.md#revisit-ladder"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS internal/records/rules-meta.md#the-main-rule"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS internal/records/rules-meta.md#meta-format-v11"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS internal/records/rules-meta.md#open-defaults-the-pilot-validates-them"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#3-terminology-test-doubles-and-fidelity"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#4-patterns-that-close-the-gaps"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#6-checklist-for-new-kit-code"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#two-review-types-two-jobs"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#the-pr-native-loop"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#the-loop-and-the-stop-rule"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#round-typing-and-tiering"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#curation-and-verification"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#reviewer-freshness"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#the-round-comment-contract"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#fixes-close-classes-not-sites"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#who-records-what"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#finding-provenance"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#verification-duty"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#suites-are-the-standing-review"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#parallel-reviewer-agents"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/review-concept.md#release-gate"

WORK=$(mktemp -d /tmp/rules-audit.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
V=$WORK/violations
: >"$V"
OVER=$WORK/overdue
: >"$OVER"

block() { printf '[inv%s] %s\n' "$1" "$2" >>"$V"; }

# ---------------------------------------------------------------- helpers
date_ok() { # ISO + plausible ranges
    case $1 in
        [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
        *) return 1 ;;
    esac
    _m=${1#*-}
    _m=${_m%%-*}
    _d=${1##*-}
    [ "$_m" -ge 1 ] && [ "$_m" -le 12 ] && [ "$_d" -ge 1 ] && [ "$_d" -le 31 ]
}

iso_lt() { # iso_lt a b -- true when date a sorts before date b
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'
}

norm_join() { # file -> single line, ` and * stripped, ws squeezed
    awk 'BEGIN { ORS = "" }
        /^```/ { fence = !fence; next }
        fence { next }
        { gsub(/`/, ""); gsub(/\*/, ""); printf "%s ", $0 }' "$1" |
        tr -s ' \t' ' '
}

first5() { # quote -> first five words (or fewer)
    set -f
    # shellcheck disable=SC2086  # intentional word split
    set -- $1
    set +f
    _n=""
    _i=0
    for _w in "$@"; do
        _i=$((_i + 1))
        [ $_i -gt 5 ] && break
        _n="${_n:+$_n }$_w"
    done
    printf '%s' "$_n"
}

fm_get() { # file key -> value ('' when absent; ONE paired quote
    # layer stripped, same normalization as gen-rules-index.py and the
    # other shell extractors, #317 d D1). Duplicate keys: FIRST wins
    # here (head -1, the canonical rule); the audit blocks them (#321).
    sed -n '2,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 |
        sed "s/^\([\"']\)\(.*\)\1$/\2/"
}

# ------------------------------------------- pass 1: scope files (1, 2, 3)
REFS=$WORK/refs
: >"$REFS"
UNITS=$WORK/units
: >"$UNITS"
HEADS=$WORK/heads
: >"$HEADS"

for f in $SCOPE_FILES; do
    [ -f "$ROOT/$f" ] || {
        block 2 "scope file missing: $f"
        continue
    }
    awk -v fname="$f" -v act="$ACTIVE_SECTIONS" '
        BEGIN {
            n = split(act, a, " ")
            for (i = 1; i <= n; i++) active[a[i]] = 1
            fence = 0; insec = 0; unitopen = 0; hasref = 0; buf = ""
        }
        function flush() {
            if (unitopen && !hasref) {
                gsub(/ +/, " ", buf)
                printf "UNIT\t%s#%s\t%s\n", fname, sec, substr(buf, 1, 70)
            }
            unitopen = 0; buf = ""; hasref = 0
        }
        /^```/ { fence = !fence; flush(); next }
        fence { next }
        /^#{1,6}[ \t]/ {
            h = $0; sub(/^#+[ \t]+/, "", h); sub(/[ \t]*#*$/, "", h)
            tmp = tolower(h)
            gsub(/[^a-z0-9 -]/, "", tmp)
            gsub(/^ +| +$/, "", tmp); gsub(/ +/, " ", tmp); gsub(/ /, "-", tmp)
            printf "HEAD\t%s\t%s\n", fname, tmp
            flush()
            insec = ((fname "#" tmp) in active) ? 1 : 0
            sec = tmp
            next
        }
        {
            if (match($0, /\(RM-[0-9][0-9][0-9][0-9]\)/)) {
                r = substr($0, RSTART + 1, RLENGTH - 2)
                printf "REF\t%s\t%s\t%d\t%s\n", r, fname, FNR, $0
            }
        }
        !insec { next }
        /^\|/ { flush(); next }
        /^[-*] / || /^[0-9]+\. / {
            flush(); unitopen = 1; buf = $0
            hasref = ($0 ~ /\(RM-[0-9][0-9][0-9][0-9]\)/) ? 1 : 0
            next
        }
        unitopen {
            buf = buf " " $0
            if ($0 ~ /\(RM-[0-9][0-9][0-9][0-9]\)/) hasref = 1
            next
        }
        END { flush() }
    ' "$ROOT/$f" | while IFS='	' read -r tag rest; do
        case $tag in
            REF) printf '%s\n' "$rest" >>"$REFS" ;;
            UNIT) printf '%s\n' "$rest" >>"$UNITS" ;;
            HEAD) printf '%s\n' "$rest" >>"$HEADS" ;;
        esac
    done
done

# invariant 1: ref-less units in active sections
while IFS='	' read -r _loc _text; do
    [ -n "$_loc" ] || continue
    block 1 "$_loc -- unit without (RM-NNNN) ref: ${_text}"
done <"$UNITS"

# invariant 2: refs resolve
cut -f1 "$REFS" | sort -u | while IFS= read -r r; do
    digs=${r#RM-}
    d1=$(printf '%s' "$digs" | cut -c1)
    d2=$(printf '%s' "$digs" | cut -c2)
    d3=$(printf '%s' "$digs" | cut -c3)
    b="$METAS/$d1/$d2/$d3"
    if [ ! -f "$ROOT/$b/$r.md" ]; then
        block 2 "$r -- no meta at $b/$r.md (ref via $(grep -m1 "^$r	" "$REFS" | cut -f2))"
    fi
done

# invariant 3 (a): no meta referenced twice
cut -f1 "$REFS" | sort | uniq -d | while IFS= read -r r; do
    block 3 "$r -- referenced by more than one unit"
done

# ------------------------------------------------------ pass 2: meta files
# (invariants 3b, 4, 5, 6, 7, 9 -- single loop over the tree)
IDS=$WORK/ids
: >"$IDS"
# #232: the meta worklist is built ONCE with find's stderr captured --
# a partially unreadable meta tree BLOCKS (a silently shorter worklist
# would audit a scope nobody chose); both loops below read $METALIST.
METALIST=$WORK/metas
find "$ROOT/$METAS" -type f -name 'RM-*.md' 2>"$WORK/finderr" |
    LC_ALL=C sort >"$METALIST"
if [ -s "$WORK/finderr" ]; then
    sed 's/^/[meta-tree] /' "$WORK/finderr" >>"$V"
    printf '[meta-tree] find reported errors under %s -- audit scope may be partial\n' \
        "$METAS" >>"$V"
fi
while IFS= read -r m; do
    rel=${m#"$ROOT"/}
    base=$(basename "$m" .md)

    # 4: filename <-> id, id format
    id=$(fm_get "$m" id)
    case $id in
        RM-[0-9][0-9][0-9][0-9]) ;;
        *)
            block 4 "$rel -- bad id field: '$id'"
            id=""
            ;;
    esac
    [ "$id" = "$base" ] || block 4 "$rel -- filename != id '$id'"
    [ -n "$id" ] && printf '%s\n' "$id" >>"$IDS"

    # 6: frontmatter completeness + dates + vocabulary
    for k in id rule quote created status revisit-interval next-revisit; do
        v=$(fm_get "$m" "$k")
        [ -n "$v" ] || block 6 "$rel -- missing frontmatter field: $k"
    done
    # 6 (#321): duplicate frontmatter keys are malformed hand edits --
    # they used to split the three extractors (shell head -1 = first
    # wins, gen-rules-index overwrite = last wins); they block now.
    dups=$(sed -n '2,/^---$/p' "$m" |
        sed -n 's/^\([A-Za-z-][A-Za-z-]*\):.*/\1/p' |
        LC_ALL=C sort | uniq -d)
    if [ -n "$dups" ]; then
        printf '%s\n' "$dups" | while IFS= read -r k; do
            block 6 "$rel -- duplicate frontmatter key: $k"
        done
    fi
    created=$(fm_get "$m" created)
    nrev=$(fm_get "$m" next-revisit)
    date_ok "$created" || block 6 "$rel -- created not an ISO date: '$created'"
    date_ok "$nrev" || block 6 "$rel -- next-revisit not an ISO date: '$nrev'"
    if date_ok "$created" && date_ok "$nrev"; then
        iso_lt "$nrev" "$created" && block 6 "$rel -- next-revisit $nrev before created $created"
    fi
    st=$(fm_get "$m" status)
    case $st in active | retired) ;; *) block 6 "$rel -- bad status: '$st'" ;; esac
    iv=$(fm_get "$m" revisit-interval)
    case $iv in 1m | 6m | 1y | 2y) ;; *) block 6 "$rel -- bad revisit-interval: '$iv'" ;; esac

    # 7: overdue (report-only)
    if [ "$st" = active ] && date_ok "$nrev" && iso_lt "$nrev" "$TODAY"; then
        printf '%s\t%s\n' "$nrev" "$base" >>"$OVER"
    fi

    # 5: rule back-ref file + anchor + quote prefix findable
    # (retired metas are exempt: the rule bullet is gone, so the
    # quote cannot be findable -- the retire exemption)
    if [ "$st" != retired ]; then
        rule=$(fm_get "$m" rule)
        tpath=${rule%%#*}
        tanch=${rule#*#}
        [ -z "$tanch" ] && tanch="__none__"
        if [ ! -f "$ROOT/$tpath" ]; then
            block 5 "$rel -- rule target missing: $tpath"
        else
            if ! grep -qF "$tpath	$tanch" "$HEADS"; then
                block 5 "$rel -- anchor '$tanch' not a heading in $tpath"
            fi
            quote=$(fm_get "$m" quote)
            needle=$(first5 "$quote")
            hay=$(norm_join "$ROOT/$tpath")
            case $hay in
                *"$needle"*) ;;
                *) block 5 "$rel -- quote prefix not findable (normalized): '$needle'" ;;
            esac
        fi
    fi

    # 9: approval consistency (field <=> review-log line, same date --
    # any approval line counts: re-approvals after edits are legal)
    reviewed=$(fm_get "$m" reviewed)
    if [ -n "$reviewed" ]; then
        sed -n '/^## Review log/,$p' "$m" |
            grep -qE "^- $reviewed approved by maintainer" ||
            block 9 "$rel -- reviewed '$reviewed' but no approval log line of that date"
    elif sed -n '2,/^---$/p' "$m" | grep -qE '^reviewed:[[:space:]]*$'; then
        # #233: membership is key-presence-with-value -- a bare
        # 'reviewed:' line is a malformed hand edit, not an approval.
        block 9 "$rel -- bare 'reviewed:' line (key without a value): membership is key-presence-with-value"
    else
        logdate=$(sed -n '/^## Review log/,$p' "$m" |
            grep -oE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} approved by maintainer" |
            head -1 | sed 's/^- //; s/ .*//')
        [ -n "$logdate" ] && block 9 "$rel -- approval log line '$logdate' but no reviewed field"
    fi
done <"$METALIST"

# 4: IDs unique
LC_ALL=C sort "$IDS" | uniq -d | while IFS= read -r r; do
    block 4 "duplicate id: $r"
done

# 3 (b): orphans -- active metas never referenced in the scope files
cut -f1 "$REFS" | sort -u >"$WORK/refids"
while IFS= read -r m; do
    base=$(basename "$m" .md)
    st=$(fm_get "$m" status)
    [ "$st" = active ] || continue
    grep -qxF "$base" "$WORK/refids" || block 3 "$base -- active meta without a ref (orphan)"
done <"$METALIST"

# ------------------------------------------------ 8: INDEX regeneration
# (#318 a A1): never regenerate from a partial walk -- a blocked run
# must not leave a truncated INDEX behind (find errors above).
if [ -s "$WORK/finderr" ]; then
    echo "INDEX not regenerated (meta-tree walk reported errors)"
elif [ -x "$(command -v python3)" ] && [ -f "$ROOT/scripts/gen-rules-index.py" ]; then
    cp "$ROOT/$METAS/INDEX.md" "$WORK/index.before" 2>/dev/null || : >"$WORK/index.before"
    FORCE_TODAY=$TODAY python3 "$ROOT/scripts/gen-rules-index.py" >/dev/null 2>&1 ||
        echo "warning: INDEX regeneration failed (structural meta errors above)" >&2
    if ! cmp -s "$ROOT/$METAS/INDEX.md" "$WORK/index.before"; then
        echo "INDEX regenerated (was stale)"
    fi
else
    echo "warning: python3 or gen-rules-index.py unavailable -- INDEX not regenerated"
fi

# ------------------------------------------------------------- summary
nv=$(wc -l <"$V" | tr -d ' ')
no=$(wc -l <"$OVER" | tr -d ' ')

if [ "$no" -gt 0 ]; then
    echo "overdue metas (maintenance signal, not blocking):"
    LC_ALL=C sort "$OVER" | while IFS='	' read -r d r; do echo "  $r (due $d)"; done
fi

if [ "$nv" -gt 0 ]; then
    echo "rules-audit: $nv blocking violation(s), $no overdue"
    cat "$V"
    exit 1
fi
echo "rules-audit: 0 blocking violations, $no overdue"
