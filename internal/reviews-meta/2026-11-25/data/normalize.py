#!/usr/bin/env python3
"""Normalize the raw marker rows into the M3 rounds table.

- skips closing summaries — dedicated closing comments in every era
  spelling: wave "z" (the new era, case-total closing markers), wave
  "closing" and wave "close" (older dedicated spellings), state
  "closed". They carry case-aggregated totals and would double-count
  (#780 a B4). Pilot-era round comments with state "closing-proposed"
  and a round-letter wave STAY: the closing proposal rode the last
  round comment then, their counts are round-level, and the frozen
  2026-11-07 run includes them.
- PR identity is the ground truth extract.py forced into every row
  (data["pr"] = the PR the comment lives on); the marker's own "case"
  field is untrusted comment text and never overrides it — a
  disagreeing case is logged as an anomaly, ground truth kept
  (#780 a B1: a marker on merged PR #563 claimed "case":"pr-00562").
- normalizes the two marker eras: old markers carry the curator in a
  "curated" STRING field and no curated count; new markers carry
  "curator" plus a numeric "curated"
- case keys: old era "280", new era "pr-00689" -> int PR number
"""

import json
import re
import sys

CLOSING_WAVES = ("z", "closing", "close")

rows = [json.loads(l) for l in open("rounds-raw.jsonl")]
out, seen = [], set()
for r in rows:
    if r.get("state") == "closed" or r.get("wave") in CLOSING_WAVES:
        continue
    # Ground-truth PR identity (#780 a B1): extract.py forces data["pr"]
    # from the PR the comment lives on; the marker's "case" field is
    # untrusted text — logged when it disagrees, never trusted.
    pr = int(str(r["pr"]))
    m = re.search(r"\d+", str(r.get("case", "")))
    if m and int(m.group(0)) != pr:
        sys.stderr.write(
            f"CASE-MISMATCH pr={pr} marker case={r.get('case')!r}: "
            "ground truth kept\n"
        )
    wave = r["wave"]
    if (pr, wave) in seen:
        sys.stderr.write(f"DUPE pr={pr} wave={wave} skipped later copy\n")
        continue
    seen.add((pr, wave))
    cur = r.get("curated")
    row = {
        "pr": pr,
        "wave": wave,
        "date": (r.get("commentAt") or "")[:10],
        "mergedAt": (r.get("mergedAt") or "")[:10],
        "reviewers": r.get("reviewers"),
        "curator": r.get("curator") if not isinstance(cur, str) else cur,
        "curated_count": cur if not isinstance(cur, str) else None,
        "raw": r.get("raw"),
        "retracted": r.get("retracted"),
        "med": r.get("med"),
        "high": r.get("high"),
        "state": r.get("state"),
        "tier": r.get("tier"),
        "track": r.get("track"),
    }
    out.append(row)

out.sort(key=lambda x: (x["pr"], x["wave"]))
with open("rounds.jsonl", "w") as f:
    for r in out:
        f.write(json.dumps(r, sort_keys=True) + "\n")
print(f"{len(out)} rounds ({len(seen)} unique (pr,wave))")
