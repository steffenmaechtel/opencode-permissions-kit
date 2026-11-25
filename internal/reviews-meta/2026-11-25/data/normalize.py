#!/usr/bin/env python3
"""Normalize the raw marker rows into the M3 rounds table.

- skips closing summaries (state "closed" or wave "close") — they carry
  case-aggregated totals and would double-count (same exclusion as the
  2026-11-07 run: "9 pure closing summaries excluded")
- normalizes the two marker eras: old markers carry the curator in a
  "curated" STRING field and no curated count; new markers carry
  "curator" plus a numeric "curated"
- case keys: old era "280", new era "pr-00689" -> int PR number
"""

import json
import re
import sys

rows = [json.loads(l) for l in open("rounds-raw.jsonl")]
out, seen = [], set()
for r in rows:
    if r.get("state") == "closed" or r.get("wave") == "close":
        continue
    case = str(r.get("case", r.get("pr")))
    m = re.search(r"\d+", case)
    pr = int(m.group(0)) if m else int(r["pr"])
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
