#!/bin/sh
# opencode permissions kit -- scripts/security-scan.sh
# Maintainer security-advisory watch (issue #107, docs/design/
# security-advisories.md). Runs from CI (.github/workflows/security-scan.yml,
# daily) and compares the upstream opencode advisories against the ids the
# shipped database (files/opencode-permissions-kit-lib/sh/advisories.sh)
# knows. Every unknown upstream id opens ONE GitHub issue (deduped by the
# GHSA id in the title search) with the upstream data and a curation
# checklist — curation and the release stay human decisions, the script
# never modifies the repo.
#
# Usage (CI sets GITHUB_REPOSITORY + GH_TOKEN; locally: export both):
#   scripts/security-scan.sh
#   OPK_SCAN_DRY_RUN=1 scripts/security-scan.sh   # print instead of create
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB="$REPO/files/opencode-permissions-kit-lib/sh/advisories.sh"
UPSTREAM_API="https://api.github.com/repos/anomalyco/opencode/security-advisories"

say()  { printf '  %s\n' "$*"; }
die()  { printf 'error:  %s\n' "$*" >&2; exit 1; }

[ -f "$DB" ] || die "advisory database missing: $DB"
[ -n "${GITHUB_REPOSITORY:-}" ] || die "GITHUB_REPOSITORY is not set (CI provides it; locally: export GITHUB_REPOSITORY=owner/repo)"
command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required (feed parser)"
command -v curl >/dev/null 2>&1 || die "curl is required"

# --- upstream feed -> one TSV line per advisory ---------------------------------
# id<TAB>severity<TAB>ranges<TAB>patched<TAB>summary<TAB>url — ranges/patched
# join every vulnerabilities[] entry with ", " (an advisory can carry more
# than one package/range pair); newlines in summaries become spaces so the
# TSV stays one line per advisory.
FEED=$(curl -fsSL --max-time 30 "$UPSTREAM_API" || true)
[ -n "$FEED" ] || { say "upstream feed unreachable (offline or blocked) — nothing to do"; exit 0; }
if ! UPSTREAM=$(printf '%s' "$FEED" | python3 -c 'import json,sys
try:
    feed = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for adv in feed or []:
    vulns = adv.get("vulnerabilities") or []
    ranges = ", ".join(v.get("vulnerable_version_range", "") for v in vulns if v.get("vulnerable_version_range"))
    patched = ", ".join(v.get("patched_versions", "") for v in vulns if v.get("patched_versions"))
    summary = " ".join(str(adv.get("summary", "")).split())
    print("\t".join([adv.get("ghsa_id", ""), adv.get("severity", ""), ranges, patched, summary, adv.get("html_url", "")]))
' 2>/dev/null); then
    die "failed to parse the upstream feed (expected a JSON advisory list)"
fi
[ -n "$UPSTREAM" ] || { say "upstream feed is empty — nothing to do"; exit 0; }

# --- ids the shipped database knows --------------------------------------------
# shellcheck disable=SC1090  # the shipped database, checked above
. "$DB"
KNOWN=$(advisories_ids opencode || true)

# scan_advisory_valid <id> <severity> <ranges> <patched> — shape-validate one
# parsed advisory line BEFORE any field reaches argv (title) or a query
# string (--search). Untrusted-input guard, CWE-74 discipline:
#   - no shell re-parsing risk exists — every expansion stays
#     double-quoted, printf takes fields as %s arguments, free text
#     (summary/url) flows only into the body FILE, nothing is ever eval'd
#   - what CAN be attacked is SEMANTICS: a crafted id ("GHSA-x is:closed",
#     a tab smuggled into a field shifting the TSV columns) would steer the
#     dedup search or garble the issue — so every field that leaves the
#     script as argv/query is charset-allowlisted first, and anything else
#     is SKIPPED loudly instead of interpolated
# Returns 0 = usable, 1 = skip.
scan_advisory_valid() {
    case "$1" in
        GHSA-*) ;;
        *) return 1 ;;
    esac
    # charset allowlist, NOT a prefix glob: a `*` tail would swallow
    # payloads ("GHSA-632h$(...)") — the negated class rejects any char
    # outside [A-Za-z0-9-] (spaces steer --search, quotes/parens smuggle
    # shell syntax into argv text)
    case "$1" in
        *[!A-Za-z0-9-]*) return 1 ;;
    esac
    case "$2" in
        low|moderate|high|critical) ;;
        *) return 1 ;;
    esac
    _sav_patched=$(printf '%s' "$4" | tr -d ' ')
    case "$_sav_patched" in
        *[!0-9.]*) return 1 ;;
    esac
    _sav_rest="$3,"
    while [ -n "$_sav_rest" ]; do
        _sav_cmp="${_sav_rest%%,*}"
        _sav_rest="${_sav_rest#*,}"
        _sav_cmp=$(printf '%s' "$_sav_cmp" | tr -d ' ')
        [ -n "$_sav_cmp" ] || continue
        printf '%s' "$_sav_cmp" | grep -qE '^(>=|<=|<|>|=)?[0-9]+(\.[0-9]+)*$' || return 1
    done
    return 0
}

# --- diff + one issue per unknown advisory --------------------------------------
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT INT TERM
NEW=0
SKIPPED=0
while IFS='	' read -r ID SEVERITY RANGES PATCHED SUMMARY URL; do
    [ -n "$ID" ] || continue
    if ! scan_advisory_valid "$ID" "$SEVERITY" "$RANGES" "$PATCHED"; then
        SKIPPED=$((SKIPPED + 1))
        say "WARN: skipping '$ID' — malformed feed fields (id/severity/ranges/patched shape; feed corruption?)"
        continue
    fi
    if printf '%s\n' "$KNOWN" | grep -qxF "$ID"; then
        say "$ID known (shipped database) — ok"
        continue
    fi
    # dedup: GHSA ids are globally unique, the id alone identifies the issue
    TRACKED=$(gh issue list -R "$GITHUB_REPOSITORY" --state all --search "$ID in:title" --json number --jq 'length' 2>/dev/null || echo 0)
    if [ "$TRACKED" -gt 0 ] 2>/dev/null; then
        say "$ID already tracked (issue exists) — ok"
        continue
    fi
    NEW=$((NEW + 1))
    {
        printf 'The scheduled security scan found an upstream advisory the\n'
        printf "kit's shipped database does not know yet.\n\n"
        printf 'Upstream advisory:\n\n'
        printf '  - id: %s\n' "$ID"
        printf '  - severity: %s\n' "$SEVERITY"
        printf '  - summary: %s\n' "$SUMMARY"
        printf '  - vulnerable ranges: %s\n' "$RANGES"
        printf '  - patched versions: %s\n' "$PATCHED"
        printf '  - url: %s\n\n' "$URL"
        printf 'Curation checklist (docs/design/security-advisories.md):\n\n'
        printf '  - [ ] Decide the affected install channel — upstream data is channel-blind\n'
        printf '        (npm-only advisories do not hit kit installs, the kit deploys the binary itself)\n'
        printf '  - [ ] Refine the range against the patched version (upstream opens, patched closes)\n'
        printf '  - [ ] Add the record to ADVISORY_RECORDS in\n'
        printf '        files/opencode-permissions-kit-lib/sh/advisories.sh:\n'
        printf '        opencode|%s|%s|<channel>|%s|%s|<one-line summary>\n' "$RANGES" "$PATCHED" "$SEVERITY" "$ID"
        printf '  - [ ] Cover the new record in tests/unit/test-security-advisories.sh\n'
        printf '  - [ ] Cut a release (make release VERSION=x.y.z) so opk update ships it\n'
        printf '  - [ ] Close this issue\n\n'
        printf 'Auto-created by scripts/security-scan.sh (.github/workflows/security-scan.yml).\n'
    } > "$BODY"
    if [ -n "${OPK_SCAN_DRY_RUN:-}" ]; then
        say "$ID NOT in the shipped database — dry run, would open:"
        sed 's/^/      /' "$BODY"
    else
        ISSUE_URL=$(gh issue create -R "$GITHUB_REPOSITORY" \
            --title "New upstream advisory $ID affects opencode" \
            --body-file "$BODY") || die "gh issue create failed for $ID"
        say "$ID NOT in the shipped database — opened: $ISSUE_URL"
    fi
done <<EOF
$UPSTREAM
EOF

if [ "$SKIPPED" -gt 0 ]; then
    die "$SKIPPED malformed advisory(ies) skipped — inspect the upstream feed (see the WARN lines above)"
fi
say "scan done — $NEW new advisory(ies)"
