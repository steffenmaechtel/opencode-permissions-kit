#!/usr/bin/env python3
"""Extraction recipe for the 2026-11-07 subagent-economics run.

Re-runs the whole extraction from the two live sources:

  1. GitHub: every issue comment carrying an `opk-review` marker
     (round staffing + finding counters, per the round comment contract).
  2. opencode session db: every subagent session (parent_id NOT NULL)
     of the PR-native era — role classified from the session title,
     model/tier from the model JSON, duration and tokens from the
     session row.

Outputs into the current directory:
  marker-comments.jsonl  raw gh comments (id, created, issue, body)
  markers-parsed.jsonl   one row per marker (hand-fixes applied)
  rounds.jsonl           one row per review round (deduped, closings out)
  subagents.jsonl        one row per subagent session (role, tier, minutes)

Usage:  python3 extract.py [corpus-start-date ISO, default 2026-10-26]

Requires: gh (authenticated), python3, read access to
~/.local/share/opencode/opencode.db (opened read-only, uri mode).
"""

import datetime
import json
import re
import sqlite3
import subprocess
import sys
from collections import OrderedDict

REPO = "steffenmaechtel/opencode-permissions-kit"
DB = "file:/home/opencode/.local/share/opencode/opencode.db?mode=ro"
START = sys.argv[1] if len(sys.argv) > 1 else "2026-10-26"


# ---------------------------------------------------------------- markers --

def fetch_marker_comments():
    """All issue comments whose body contains an opk-review marker.

    The corpus-archive readability mirrors (pre-PR-native era) mention
    `opk-review` in prose — filter by the actual marker syntax.
    """
    out = subprocess.run(
        ["gh", "api", "--paginate",
         f"repos/{REPO}/issues/comments?per_page=100&sort=created&direction=asc",
         "--jq", '.[] | select(.body | contains("opk-review"))'
                 ' | {id: .id, created: .created_at,'
                 ' issue: (.issue_url | split("/") | last), body: .body}'],
        capture_output=True, text=True, check=True)
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    with open("marker-comments.jsonl", "w") as f:
        for l in lines:
            f.write(l + "\n")
    return [json.loads(l) for l in lines]


MARKER_RE = re.compile(r"<!--\s*opk-review\s+(\{.*?\})\s*-->", re.S)


def parse_markers(comments):
    """Parse markers; hand-fix known malformed ones (era caveats)."""
    rows = []
    for c in comments:
        for m in MARKER_RE.finditer(c["body"]):
            raw = m.group(1)
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                # pr-287 closing marker (2026-10-27) shipped unquoted lists
                fixed = raw.replace('"reviewers":3,3,1,1,1', '"reviewers":"3,3,1,1,1"') \
                           .replace('"curated":"flash,flash,main"', '"curator":"flash,flash,main"') \
                           .replace('"verifiers":2,2,0,0,0', '"verifiers":"2,2,0,0,0"')
                data = json.loads(fixed)
                data["_handfixed"] = True
            rows.append({"comment_id": c["id"], "created": c["created"],
                         "issue": c["issue"], **data})
    with open("markers-parsed.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    return rows


def first_num(value, default=0):
    """Marker fields are ints, or comma lists (per-round history in
    closing markers) — take the first element."""
    if isinstance(value, str):
        try:
            return int(value.split(",")[0])
        except ValueError:
            return default
    return value if value is not None else default


def round_rows(markers):
    """Dedup split-part comments (same issue+wave, same counters) and
    drop pure closing summaries (case aggregates, not rounds)."""
    seen = OrderedDict()
    for r in markers:
        key = (r["issue"], r.get("wave"))
        if key not in seen:
            seen[key] = r
    rounds = []
    for r in seen.values():
        pure_closing = (r.get("state") == "closing-proposed"
                        and (r.get("wave") in ("closing", "close")
                             or r.get("wave") is None or r.get("raw") is None))
        if not pure_closing:
            rounds.append(r)
    out = []
    for r in rounds:
        out.append({
            "pr": r["issue"], "wave": r.get("wave"), "date": r["created"][:10],
            "reviewers": first_num(r.get("reviewers")),
            "curator": r.get("curator"),
            "verifiers": first_num(r.get("verifiers"), -1),
            "raw": first_num(r.get("raw")), "curated": first_num(r.get("curated")),
            "med": first_num(r.get("med")), "high": first_num(r.get("high")),
            "retracted": first_num(r.get("retracted")),
            "tier": r.get("tier"), "track": r.get("track"),
            "mode": r.get("mode"), "session": r.get("session"),
            "state": r.get("state")})
    with open("rounds.jsonl", "w") as f:
        for r in out:
            f.write(json.dumps(r) + "\n")
    return out


# ------------------------------------------------------------- subagents --

def classify_role(title):
    """Role from the session title. ORDER MATTERS: 'verif' must match
    before 'digest' — "Verify digest batch 1" is a VERIFIER (the
    2026-11-07 run's first pass got this wrong and mis-filed 6 verifier
    sessions as curators)."""
    t = (title or "").lower()
    if "verif" in t:
        return "verifier"
    if any(k in t for k in ("kurator", "curator", "curate", "kuration", "digest")):
        return "curator"
    if any(k in t for k in ("review", "achse", "axis", "micro")):
        return "reviewer"
    return "other"


def fetch_subagents():
    """Subagent sessions (children) since the corpus start, from the V2
    table. Subagents always land in session_v2 on this host (opencode
    V2 server); the V1 `session` table holds only the legacy named
    review-* agents of the pre-PR-native era (out of corpus)."""
    con = sqlite3.connect(DB, uri=True)
    epoch = int(datetime.datetime.fromisoformat(START + "T00:00:00+00:00")
                .timestamp() * 1000)
    rows = []
    q = """SELECT id, title, model, time_created, time_updated,
                  tokens_input, tokens_output, directory
           FROM session_v2 WHERE parent_id IS NOT NULL AND time_created >= ?
           ORDER BY time_created"""
    for sid, title, model, tc, tu, tin, tout, directory in con.execute(q, (epoch,)):
        model_id = json.loads(model)["id"] if model else "?"
        rows.append({
            "id": sid, "title": title, "model": model_id,
            "tier": "fast" if "flash" in model_id else "strong",
            "role": classify_role(title),
            "created": datetime.datetime.fromtimestamp(
                tc / 1000, datetime.timezone.utc).isoformat(),
            "minutes": round((tu - tc) / 60000, 1),
            "tok_in": tin, "tok_out": tout, "directory": directory})
    con.close()
    with open("subagents.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    return rows


if __name__ == "__main__":
    comments = fetch_marker_comments()
    markers = parse_markers(comments)
    rounds = round_rows(markers)
    subs = fetch_subagents()
    print(f"comments with markers: {len(comments)}")
    print(f"markers parsed: {len(markers)} (rounds after dedup: {len(rounds)})")
    print(f"subagent sessions since {START}: {len(subs)}")
