# shellcheck shell=sh
# opencode permissions kit — known security advisories (sh/advisories.sh)
#
# The kit's advisory database (issue #107, docs/design/security-advisories.md):
# a static, curated list shipped with every kit release. NO real database, no
# service, no runtime network — the wrapper checks it locally on every start
# and `opk status` diffs it against the upstream GitHub feed. Fresh entries
# travel through the normal release channel (make release → stable mirror →
# opk update); a scheduled CI watch (scripts/security-scan.sh) opens a
# maintainer issue when upstream publishes an advisory the database lacks.
#
# Sourced (never executed):
#   . /usr/local/lib/opencode-permissions-kit/sh/advisories.sh
#
# Record fields, '|' separated (summaries must not contain a '|'):
#   1 package   — 'opencode' now; 'ddev' etc. later (the schema stays)
#   2 ranges    — vulnerable version ranges: comma-separated comparators
#                 (>=, >, <=, <, =, or a bare version), ALL must hold
#   3 patched   — first patched version ('' when unknown)
#   4 channel   — installation channel the advisory affects: 'npm' or
#                 'standalone'; empty = every channel. Kit installs are
#                 always 'standalone' (the kit deploys the binary itself,
#                 never through a package manager).
#   5 severity  — upstream advisory severity (low/moderate/high/critical)
#   6 id        — advisory identifier (GHSA-...)
#   7 summary   — one-line description
#
# Ranges are REFINED against upstream data: GitHub's vulnerable_version_range
# only opens a range (e.g. ">=1.14.30"); the patched version closes it here
# (">=1.14.30,<1.18.22") so a patched install does not warn.
ADVISORY_RECORDS='
opencode|<1.0.216|1.0.216||high|GHSA-vxw4-wv6m-9hhh|Unauthenticated HTTP server allows arbitrary command execution
opencode|<1.1.10|1.1.10||critical|GHSA-c83v-7274-4vgp|Malicious website can execute commands on the local system through XSS in the OpenCode web UI
opencode|>=1.14.30,<1.18.22|1.18.22|npm|high|GHSA-632h-h47v-g4x4|Cross-site opencode serve request can install arbitrary packages (npm-managed installations only)
'

# x.y.z of an `opencode --version` line. 1.x prints the bare version
# ("1.18.31"), 2.x prints "opencode v2.0.11" (issue #99) — both yield the
# plain triple. Empty output when nothing parses (callers skip the check).
advisories_version_of() {
    printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

# Relation of two dotted versions: prints gt, eq, or lt. sort -V gives real
# segment-wise order ("1.9.0" < "1.10.0", which lexicographic compare gets
# wrong).
advisories_version_cmp() {
    _avc_hi=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)
    if [ "$_avc_hi" = "$1" ] && [ "$_avc_hi" = "$2" ]; then
        printf 'eq\n'
    elif [ "$_avc_hi" = "$1" ]; then
        printf 'gt\n'
    else
        printf 'lt\n'
    fi
}

# Does <version> fall into <ranges> ("[>=]x[,[<]y...]", spaces allowed)?
# Every comma-separated comparator must hold (conjunction). Malformed
# comparators or an empty version fail SAFE (not affected) — a broken
# database line must never warn, and must never keep a session from
# starting. Exit 0 = inside the range, 1 = outside.
advisory_range_holds() {
    _arh_version="$1" _arh_range="$2"
    [ -n "$_arh_version" ] && [ -n "$_arh_range" ] || return 1
    _arh_rest="$_arh_range,"
    while [ -n "$_arh_rest" ]; do
        _arh_cmp="${_arh_rest%%,*}"
        _arh_rest="${_arh_rest#*,}"
        _arh_cmp=$(printf '%s' "$_arh_cmp" | tr -d ' ')
        [ -n "$_arh_cmp" ] || continue
        _arh_op=eq
        case "$_arh_cmp" in
            '>='*) _arh_op=ge; _arh_cmp=${_arh_cmp#>=} ;;
            '<='*) _arh_op=le; _arh_cmp=${_arh_cmp#<=} ;;
            '>'*)  _arh_op=gt; _arh_cmp=${_arh_cmp#>} ;;
            '<'*)  _arh_op=lt; _arh_cmp=${_arh_cmp#<} ;;
            '='*)  _arh_op=eq; _arh_cmp=${_arh_cmp#=} ;;
        esac
        case "$_arh_cmp" in
            ''|.*|*.|*[!0-9.]*) return 1 ;;
        esac
        _arh_rel=$(advisories_version_cmp "$_arh_version" "$_arh_cmp")
        case "${_arh_op}_${_arh_rel}" in
            ge_eq|ge_gt|le_eq|le_lt|gt_gt|lt_lt|eq_eq) ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# advisories_matching <package> <version> <channel> — prints every record
# (all 7 fields, '|' separated) whose package matches, channel matches
# (empty record channel = every channel), and version falls inside the
# ranges. Re-split with `IFS='|' read -r pkg ranges patched channel sev id
# summary` — the 7th field carries the rest of the line.
advisories_matching() {
    _adv_pkg_want="$1" _adv_version="$2" _adv_channel_want="$3"
    while IFS= read -r _adv_line; do
        case "$_adv_line" in
            ''|'#'*) continue ;;
        esac
        _adv_line=$(printf '%s' "$_adv_line" | sed 's/[[:space:]]*$//')
        [ -n "$_adv_line" ] || continue
        _adv_pkg="${_adv_line%%|*}"
        [ "$_adv_pkg" = "$_adv_pkg_want" ] || continue
        _adv_ranges=$(printf '%s' "$_adv_line" | cut -d'|' -f2)
        _adv_channel=$(printf '%s' "$_adv_line" | cut -d'|' -f4)
        [ -n "$_adv_channel" ] && [ "$_adv_channel" != "$_adv_channel_want" ] && continue
        if advisory_range_holds "$_adv_version" "$_adv_ranges"; then
            printf '%s\n' "$_adv_line"
        fi
    done <<EOF
$ADVISORY_RECORDS
EOF
}

# advisories_ids <package> — every known advisory id for <package>, one per
# line. `opk status` diffs this against the upstream feed (freshness signal:
# an upstream id missing here means the shipped database lags a release).
advisories_ids() {
    _adv_ids_pkg="$1"
    while IFS= read -r _adv_line; do
        case "$_adv_line" in
            ''|'#'*) continue ;;
        esac
        _adv_pkg=$(printf '%s' "$_adv_line" | cut -d'|' -f1)
        [ "$_adv_pkg" = "$_adv_ids_pkg" ] || continue
        printf '%s\n' "$(printf '%s' "$_adv_line" | cut -d'|' -f6)"
    done <<EOF
$ADVISORY_RECORDS
EOF
}
