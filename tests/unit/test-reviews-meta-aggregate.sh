#!/bin/sh
# Unit tests for scripts/reviews-meta-aggregate.py: the aggregator behind
# the reviews-meta runs. Five pins: (1) COMPAT — regenerating the frozen
# 2026-10-10 extraction data must reproduce its committed stats.json
# byte-for-byte (a schema/ordering drift in the aggregator would corrupt
# every future run's comparability); (2) PR-STEM ERA — the 2026-10-22
# corpus added pr-NNNNN stems (cases pr-00179+); grouping, ordering
# (version groups before PR groups, PR groups by number), and crossref
# edges must handle both eras; (3) LOCALE — batch IO pins utf-8, so a
# 7-bit-locale host survives a batch with raw non-ASCII (#513 A3);
# (4) PRINT — the console summary survives a non-ASCII PRINTED field
# under the same locale (#517 S1); (5) RECIPE — the reusable extract.py
# pins its text IO (#517 S2, source pins).
# Run: sh tests/unit/test-reviews-meta-aggregate.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/reviews-meta-aggregate.py"
OLD_DATA="$REPO/internal/reviews-meta/2026-10-10/data"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$REPO/tests/unit/lib/harness.sh"

# Loud scratch guard (#441 a B1 / #454 a C1 class): the suite runs set -u
# only -- a failed work_new must abort instead of degenerating writes.
WORK="$(work_new /tmp/opencode-test-meta-aggregate.XXXXXX)" || {
    echo "reviews-meta aggregate tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

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
cat >"$WORK/new/b1.json" <<'EOF'
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

# --- #513 A3: locale-hardened batch IO (utf-8 pinned) --------------------------
# The #485 F22 / #510 locale class as it remained at this script
# (beyond #510's sh-lib sweep scope): json.load(open(f)) and the
# stats.json write rode the locale codec, so a 7-bit-locale host
# (LC_ALL=C with the PEP 538/540 escapes disabled, #510's measured
# trigger) died reading any batch with raw non-ASCII (an em-dash in a
# summary) as a UnicodeDecodeError. Both opens pin utf-8 now, like
# scripts/gen-rules-index.py. Load-bearing per the #510 convention:
# control arm first, then the unpinned read shape must die on the exact
# fixture (non-vacuity proof), then the aggregator must survive it.
# The fixture writer emits RAW em-dash bytes (ensure_ascii=False) — a
# JSON \u2014 escape is ASCII on the wire and never exercises the
# locale decode.
HSP="$(hostile_stdio_python)" || {
    echo "reviews-meta aggregate tests: hostile-locale bin setup failed" >&2
    exit 1
}
check "control arm: 7-bit hostility effective (#513 A3)" \
    hostile_stdio_control "$HSP"
mkdir -p "$WORK/loc"
python3 - "$WORK/loc/b1.json" <<'PY'
import json, sys
em = chr(0x2014)  # em-dash, written as raw UTF-8 below
batch = {
    "batch": "b1",
    "snapshots": [{
        "stem": "0.0.47a", "file": "synthetic", "date": "2026-10-10",
        "scope": "wave", "reviewer": "GLM-5.3",
        "subject": "em" + em + "dash run", "stop_rule": "met",
        "stated_counts": {"HIGH": 0, "MED": 0, "LOW": 0, "INFO": 1},
        "findings": [{
            "id": "L1", "severity": "INFO", "severity_inferred": False,
            "class": "claim-drift", "secondary_class": None, "area": "docs",
            "provenance": None, "summary": "em" + em + "dash",
            "cross_refs": [], "status": "reported"}],
        "process_notes": []}],
    "resolutions": [],
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(batch, f, ensure_ascii=False, indent=1)
    f.write("\n")
PY
if PATH="$HSP:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    PYTHONIOENCODING=ascii python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
    "$WORK/loc/b1.json" >/dev/null 2>&1; then
    fail "unpinned json.load(open(f)) must die on the em-dash batch under the hostile locale (#513 A3)"
else
    pass "unpinned json.load(open(f)) dies on the em-dash batch under the hostile locale (#513 A3)"
fi
_A3_RC=0
PATH="$HSP:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    PYTHONIOENCODING=ascii python3 "$SCRIPT" "$WORK/loc" >/dev/null 2>&1 || _A3_RC=$?
check "aggregator reads the em-dash batch and writes stats under the hostile locale (#513 A3)" \
    [ "$_A3_RC" -eq 0 ]
check "hostile-locale stats.json groups the batch stem (#513 A3)" \
    grep -q '"0.0.47"' "$WORK/loc/stats.json"

# --- #517 S1: locale-hardened console summary -----------------------------------
# PR #515 round a S1 (deferred to #517): the console summary printed
# batch-derived values (areas, class names, reviewer keys) with no
# stdout pin — a 7-bit-locale host died at the print AFTER writing a
# correct stats.json (rc!=0 despite correct output). The guard now
# reconfigures stdout like jsonc-parser.py. The stdout death control is
# hostile_stdio_control above (it IS the non-ASCII stdout write probe).
# Fixture: the em-dash rides a PRINTED field (area) — the #513 A3
# fixture deliberately keeps printed fields ASCII, so only this
# fixture drives the print arm.
mkdir -p "$WORK/pr"
python3 - "$WORK/pr/b1.json" <<'PY'
import json, sys
em = chr(0x2014)  # em-dash in a PRINTED field (area) — raw UTF-8 below
batch = {
    "batch": "b1",
    "snapshots": [{
        "stem": "0.0.47a", "file": "synthetic", "date": "2026-10-10",
        "scope": "wave", "reviewer": "GLM-5.3",
        "subject": "print-arm run", "stop_rule": "met",
        "stated_counts": {"HIGH": 0, "MED": 0, "LOW": 0, "INFO": 1},
        "findings": [{
            "id": "P1", "severity": "INFO", "severity_inferred": False,
            "class": "claim-drift", "secondary_class": None,
            "area": "docs" + em + "internal", "provenance": None,
            "summary": "print arm", "cross_refs": [],
            "status": "reported"}],
        "process_notes": []}],
    "resolutions": [],
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(batch, f, ensure_ascii=False, indent=1)
    f.write("\n")
PY
_S1_RC=0
PATH="$HSP:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    PYTHONIOENCODING=ascii python3 "$SCRIPT" "$WORK/pr" >/dev/null 2>&1 || _S1_RC=$?
check "aggregator prints a non-ASCII area under the hostile locale (#517 S1)" \
    [ "$_S1_RC" -eq 0 ]
check "print-arm run wrote stats.json with the area escaped (#517 S1)" \
    grep -q 'docs\\u2014internal' "$WORK/pr/stats.json"

# --- #517 S2: the reusable extraction recipe pins its text IO -------------------
# The 2026-11-07 recipe is what the next run copies (reviews-meta
# README); the pins landed in place via #517 (post-run — the 2026-11-07
# run itself executed unpinned, recorded in the recipe's docstring).
# Source pins: the recipe runs against live gh + the session db, so no
# unit execution exists — check_live guards the constructs in
# comment-stripped live source.
EXTRACT="$REPO/internal/reviews-meta/2026-11-07/data/extract.py"
check_live "recipe: gh call decodes utf-8, not locale (#517 S2)" "$EXTRACT" \
    -qF 'capture_output=True, encoding="utf-8", check=True'
check_live "recipe: marker-comments write pins utf-8 (#517 S2)" "$EXTRACT" \
    -qF 'open("marker-comments.jsonl", "w", encoding="utf-8")'
check_live "recipe: markers-parsed write pins utf-8 (#517 S2)" "$EXTRACT" \
    -qF 'open("markers-parsed.jsonl", "w", encoding="utf-8")'
check_live "recipe: rounds write pins utf-8 (#517 S2)" "$EXTRACT" \
    -qF 'open("rounds.jsonl", "w", encoding="utf-8")'
check_live "recipe: subagents write pins utf-8 (#517 S2)" "$EXTRACT" \
    -qF 'open("subagents.jsonl", "w", encoding="utf-8")'
# #518 a S1: the five rows above guard the constructs; this absence
# leg guards two SHAPES — text=True and w/a-mode opens without
# encoding — the realistic reintroduction paths of the #517 class in
# a recipe copy (#518 b S1: the label claims exactly that, no more).
# Deliberately not covered (speculative growth — the next copy's own
# reviewed case owns them): plus-modes, read-mode opens, pathlib
# read_text/write_text, universal_newlines, a second text-mode
# subprocess, variable-mode opens.
_UNPINNED="$(live_src "$EXTRACT" | grep -cE 'text=True|open\([^)]*"[wa]"\)')"
check "recipe: no unpinned w/a-mode open or text=True remains (#518 a S1, #518 b S1)" \
    [ "$_UNPINNED" -eq 0 ]

# --- summary gate --------------------------------------------------------------
echo
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}test-reviews-meta-aggregate: $failures FAILED, $passed passed${NC}"
    exit 1
fi
echo "  ${GREEN}test-reviews-meta-aggregate: all $passed passed${NC}"
