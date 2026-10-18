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
#      words (plain-text rendering, the established meta practice)
#   6. frontmatter complete, ISO dates, next-revisit >= created,
#      status/interval vocabulary
#   9. approval consistency: reviewed: is set exactly when the review
#      log carries an "approved by maintainer" line of the same date
#
# Report-only (non-blocking, per RM-0030): 7. overdue list sorted by
# lateness; 8. INDEX.md regenerated on every run (stale -> warning).
# The Phase-2 pending-unit parking valve (prefix-matched ref-less
# units reported non-blocking) was retired 2026-10-17 when its five
# occupants received metas -- a ref-less unit in an ACTIVE section
# now always blocks.
#
# Scope lives HERE, reviewable (record: "the section allowlist lives
# in the audit script"): SCOPE_FILES are scanned for refs (2, 3);
# ACTIVE_SECTIONS additionally enforce unit refs (1). Phase 3 extends
# the lists as the remaining agent/ files get metas.
#
# Exit: 1 on blocking violations (1-6, 9), 0 otherwise.
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

SCOPE_FILES="agent/conventions.md agent/test-fidelity.md internal/records/rules-meta.md"
ACTIVE_SECTIONS="agent/conventions.md#interactive-prompts-yn"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#script-output-style"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#shell-security-untrusted-input"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#test-sandbox-unit-suites"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/conventions.md#referencing-review-findings"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS internal/records/rules-meta.md#revisit-ladder"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#3-terminology-test-doubles-and-fidelity"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#4-patterns-that-close-the-gaps"
ACTIVE_SECTIONS="$ACTIVE_SECTIONS agent/test-fidelity.md#6-checklist-for-new-kit-code"

WORK=$(mktemp -d /tmp/rules-audit.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
V=$WORK/violations; : > "$V"
OVER=$WORK/overdue; : > "$OVER"

block() { printf '[inv%s] %s\n' "$1" "$2" >> "$V"; }

# ---------------------------------------------------------------- helpers
date_ok() {  # ISO + plausible ranges
    case $1 in
        [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
        *) return 1 ;;
    esac
    _m=${1#*-}; _m=${_m%%-*}
    _d=${1##*-}
    [ "$_m" -ge 1 ] && [ "$_m" -le 12 ] && [ "$_d" -ge 1 ] && [ "$_d" -le 31 ]
}

iso_lt() {  # iso_lt a b -- true when date a sorts before date b
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'
}

norm_join() {  # file -> single line, ` and * stripped, ws squeezed
    awk 'BEGIN { ORS = "" }
        /^```/ { fence = !fence; next }
        fence { next }
        { gsub(/`/, ""); gsub(/\*/, ""); printf "%s ", $0 }' "$1" \
    | tr -s ' \t' ' '
}

first5() {  # quote -> first five words (or fewer)
    set -f
    # shellcheck disable=SC2086  # intentional word split
    set -- $1
    set +f
    _n=""
    _i=0
    for _w in "$@"; do
        _i=$((_i + 1)); [ $_i -gt 5 ] && break
        _n="${_n:+$_n }$_w"
    done
    printf '%s' "$_n"
}

fm_get() {  # file key -> value ('' when absent)
    sed -n '2,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 \
        | sed 's/^"//; s/"$//'
}

# ------------------------------------------- pass 1: scope files (1, 2, 3)
REFS=$WORK/refs; : > "$REFS"
UNITS=$WORK/units; : > "$UNITS"
HEADS=$WORK/heads; : > "$HEADS"

for f in $SCOPE_FILES; do
    [ -f "$ROOT/$f" ] || { block 2 "scope file missing: $f"; continue; }
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
            REF)  printf '%s\n' "$rest" >> "$REFS" ;;
            UNIT) printf '%s\n' "$rest" >> "$UNITS" ;;
            HEAD) printf '%s\n' "$rest" >> "$HEADS" ;;
        esac
    done
done

# invariant 1: ref-less units in active sections
while IFS='	' read -r _loc _text; do
    [ -n "$_loc" ] || continue
    block 1 "$_loc -- unit without (RM-NNNN) ref: ${_text}"
done < "$UNITS"

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
IDS=$WORK/ids; : > "$IDS"
find "$ROOT/$METAS" -type f -name 'RM-*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r m; do
    rel=${m#"$ROOT"/}
    base=$(basename "$m" .md)

    # 4: filename <-> id, id format
    id=$(fm_get "$m" id)
    case $id in
        RM-[0-9][0-9][0-9][0-9]) ;;
        *) block 4 "$rel -- bad id field: '$id'"; id="" ;;
    esac
    [ "$id" = "$base" ] || block 4 "$rel -- filename != id '$id'"
    [ -n "$id" ] && printf '%s\n' "$id" >> "$IDS"

    # 6: frontmatter completeness + dates + vocabulary
    for k in id rule quote created status revisit-interval next-revisit; do
        v=$(fm_get "$m" "$k")
        [ -n "$v" ] || block 6 "$rel -- missing frontmatter field: $k"
    done
    created=$(fm_get "$m" created); nrev=$(fm_get "$m" next-revisit)
    date_ok "$created" || block 6 "$rel -- created not an ISO date: '$created'"
    date_ok "$nrev"   || block 6 "$rel -- next-revisit not an ISO date: '$nrev'"
    if date_ok "$created" && date_ok "$nrev"; then
        iso_lt "$nrev" "$created" && block 6 "$rel -- next-revisit $nrev before created $created"
    fi
    st=$(fm_get "$m" status)
    case $st in active|retired) ;; *) block 6 "$rel -- bad status: '$st'" ;; esac
    iv=$(fm_get "$m" revisit-interval)
    case $iv in 1m|6m|1y|2y) ;; *) block 6 "$rel -- bad revisit-interval: '$iv'" ;; esac

    # 7: overdue (report-only)
    if [ "$st" = active ] && date_ok "$nrev" && iso_lt "$nrev" "$TODAY"; then
        printf '%s\t%s\n' "$nrev" "$base" >> "$OVER"
    fi

    # 5: rule back-ref file + anchor + quote prefix findable
    rule=$(fm_get "$m" rule)
    tpath=${rule%%#*}; tanch=${rule#*#}
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

    # 9: approval consistency (field <=> review-log line, same date --
    # any approval line counts: re-approvals after edits are legal)
    reviewed=$(fm_get "$m" reviewed)
    if [ -n "$reviewed" ]; then
        sed -n '/^## Review log/,$p' "$m" \
            | grep -qE "^- $reviewed approved by maintainer" \
            || block 9 "$rel -- reviewed '$reviewed' but no approval log line of that date"
    else
        logdate=$(sed -n '/^## Review log/,$p' "$m" \
            | grep -oE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} approved by maintainer" \
            | head -1 | sed 's/^- //; s/ .*//')
        [ -n "$logdate" ] && block 9 "$rel -- approval log line '$logdate' but no reviewed field"
    fi
done

# 4: IDs unique
LC_ALL=C sort "$IDS" | uniq -d | while IFS= read -r r; do
    block 4 "duplicate id: $r"
done

# 3 (b): orphans -- active metas never referenced in the scope files
cut -f1 "$REFS" | sort -u > "$WORK/refids"
find "$ROOT/$METAS" -type f -name 'RM-*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r m; do
    base=$(basename "$m" .md)
    st=$(fm_get "$m" status)
    [ "$st" = active ] || continue
    grep -qxF "$base" "$WORK/refids" || block 3 "$base -- active meta without a ref (orphan)"
done

# ------------------------------------------------ 8: INDEX regeneration
if [ -x "$(command -v python3)" ] && [ -f "$ROOT/scripts/gen-rules-index.py" ]; then
    cp "$ROOT/$METAS/INDEX.md" "$WORK/index.before" 2>/dev/null || : > "$WORK/index.before"
    FORCE_TODAY=$TODAY python3 "$ROOT/scripts/gen-rules-index.py" > /dev/null 2>&1 \
        || echo "warning: INDEX regeneration failed (structural meta errors above)" >&2
    if ! cmp -s "$ROOT/$METAS/INDEX.md" "$WORK/index.before"; then
        echo "INDEX regenerated (was stale)"
    fi
else
    echo "warning: python3 or gen-rules-index.py unavailable -- INDEX not regenerated"
fi

# ------------------------------------------------------------- summary
nv=$(wc -l < "$V" | tr -d ' ')
no=$(wc -l < "$OVER" | tr -d ' ')

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
