#!/bin/sh
# Unit tests for scripts/reviews-meta-aggregate.py: the aggregator behind
# the reviews-meta runs. Two pins: (1) COMPAT — regenerating the frozen
# 2026-10-10 extraction data must reproduce its committed stats.json
# byte-for-byte (a schema/ordering drift in the aggregator would corrupt
# every future run's comparability); (2) PR-STEM ERA — the 2026-10-22
# corpus added pr-NNNNN stems (cases pr-00179+); grouping, ordering
# (version groups before PR groups, PR groups by number), and crossref
# edges must handle both eras. Run: sh tests/unit/test-reviews-meta-aggregate.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/reviews-meta-aggregate.py"
OLD_DATA="$REPO/internal/reviews-meta/2026-10-10/data"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

WORK="$(mktemp -d /tmp/opencode-test-meta-aggregate.XXXXXX)"
# Trap the receiver on exit and signals (#283): the suite had no trap
# and no inline rm — the scratch leaked on EVERY run, not just aborts.
trap 'rm -rf "${WORK:-}"' EXIT INT TERM

# --- compat: frozen 2026-10-10 data regenerates identically -------------------
mkdir -p "$WORK/old"
cp "$OLD_DATA"/b*.json "$WORK/old/"
python3 "$SCRIPT" "$WORK/old" >/dev/null 2>&1
if cmp -s "$WORK/old/stats.json" "$OLD_DATA/stats.json"; then
    pass "2026-10-10 data regenerates its frozen stats.json byte-for-byte"
else
    fail "2026-10-10 regeneration differs from the frozen stats.json"
fi

# --- PR-stem era: synthetic two-era corpus ------------------------------------
mkdir -p "$WORK/new"
cat > "$WORK/new/b1.json" <<'EOF'
{
  "batch": "b1",
  "snapshots": [
    {
      "stem": "pr-00211a", "file": "synthetic", "date": "2026-10-20",
      "scope": "full", "reviewer": "GLM-5.3", "subject": "synthetic full pass",
      "stop_rule": "not_met",
      "stated_counts": {"HIGH": 1, "MED": 0, "LOW": 0, "INFO": 0},
      "findings": [
        {"id": "F1", "severity": "HIGH", "severity_inferred": false,
         "class": "race-toctou", "secondary_class": null, "area": "sh-lib",
         "provenance": "pre-existing", "summary": "synthetic leaf-only gate",
         "cross_refs": ["0.0.39h F2"], "status": "reported"},
        {"id": "F2", "severity": "INFO", "severity_inferred": false,
         "class": "claim-drift", "secondary_class": null, "area": "docs",
         "provenance": null, "summary": "synthetic same-case backref",
         "cross_refs": ["pr-00211 a F1"], "status": "reported"}
      ],
      "process_notes": []
    },
    {
      "stem": "0.0.47a", "file": "synthetic", "date": "2026-10-10",
      "scope": "wave", "reviewer": "GLM-5.3", "subject": "synthetic legacy wave",
      "stop_rule": "met",
      "stated_counts": {"HIGH": 0, "MED": 1, "LOW": 0, "INFO": 0},
      "findings": [
        {"id": "W1", "severity": "MED", "severity_inferred": false,
         "class": "silent-failure", "secondary_class": null, "area": "update.sh",
         "provenance": "wave-introduced", "summary": "synthetic swallowed error",
         "cross_refs": ["0.0.44a V2"], "status": "reported"}
      ],
      "process_notes": []
    }
  ],
  "resolutions": []
}
EOF
python3 "$SCRIPT" "$WORK/new" >/dev/null 2>&1

json_has() {
    python3 -c "
import json, sys
stats = json.load(open('$WORK/new/stats.json'))
expr = sys.argv[1]
sys.exit(0 if eval(expr) else 1)
" "$1"
}

check "PR stem groups by case (vgroup pr-00211 exists)" \
    json_has "'pr-00211' in stats['vgroup_order']"
check "legacy stem groups by version (vgroup 0.0.47 exists)" \
    json_has "'0.0.47' in stats['vgroup_order']"
check "version groups sort before PR groups" \
    json_has "stats['vgroup_order'] == ['0.0.47', 'pr-00211']"
check "the HIGH severity survives sev_norm into the class table" \
    json_has "stats['classes']['race-toctou']['sev'].get('HIGH') == 1"
check "cross-ref pr-00211 a F1 -> 0.0.39 counts as backward edge" \
    json_has "any(e['to_group'] == '0.0.39' for e in stats['crossref_backward'])"
check "legacy -> legacy edge recorded (0.0.47 stem, 0.0.44 target)" \
    json_has "any(e['from_group'] == '0.0.47' and e['to_group'] == '0.0.44' for e in stats['crossref_edges'])"
check "same-case ref is an edge (pr-00211 -> pr-00211)" \
    json_has "any(e['from_group'] == 'pr-00211' and e['to_group'] == 'pr-00211' for e in stats['crossref_edges'])"
check "same-case ref is NOT a backward edge" \
    json_has "not any(e['from_group'] == 'pr-00211' and e['to_group'] == 'pr-00211' for e in stats['crossref_backward'])"

# --- summary gate --------------------------------------------------------------
echo
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}test-reviews-meta-aggregate: $failures FAILED, $passed passed${NC}"
    exit 1
fi
echo "  ${GREEN}test-reviews-meta-aggregate: all $passed passed${NC}"
