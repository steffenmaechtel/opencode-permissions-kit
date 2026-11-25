#!/usr/bin/env python3
"""M3 extraction over PR timelines (issue #768 baseline).

Read-only: gh pr list / gh pr view --json comments over the merged PRs
of the window; parses the multi-line `<!-- opk-review {...} -->` JSON
markers from the comment bodies; emits one JSON row per review round.

Usage: python3 extract.py <first-pr-number>   (default 280)
"""

import json
import re
import subprocess
import sys
import time

REPO = "steffenmaechtel/opencode-permissions-kit"
FIRST_PR = int(sys.argv[1]) if len(sys.argv) > 1 else 280

MARKER_RE = re.compile(r"<!--\s*opk-review\s*(\{.*?\})\s*-->", re.DOTALL)


def gh_json(args, tries=4):
    for attempt in range(tries):
        p = subprocess.run(
            ["gh", "-R", REPO, *args], capture_output=True, text=True
        )
        if p.returncode == 0:
            return json.loads(p.stdout)
        sys.stderr.write(
            f"gh rc={p.returncode} attempt {attempt + 1}: "
            f"{p.stderr.strip()[:200]}\n"
        )
        time.sleep(5 * (attempt + 1))
    raise SystemExit(f"gh failed for: {args}")


def merged_prs():
    # --limit 400: gh paginates internally (verified: returns all 147
    # merged PRs > #407 on this repo); a manual --page flag rides the
    # search API and fails on this query shape.
    return gh_json(
        ["pr", "list", "--state", "merged", "--limit", "400",
         "--json", "number,mergedAt"]
    )


def main():
    prs = merged_prs()
    n_done = 0
    rows = []
    targets = sorted(
        (p for p in prs if p["number"] >= FIRST_PR),
        key=lambda p: p["number"],
    )
    for pr in targets:
        n = pr["number"]
        comments = gh_json(
            ["pr", "view", str(n), "--json", "comments"]
        )["comments"]
        for c in comments:
            for m in MARKER_RE.finditer(c["body"]):
                raw = re.sub(r"\s+", " ", m.group(1))
                try:
                    data = json.loads(raw)
                except json.JSONDecodeError:
                    sys.stderr.write(f"MARKER-UNPARSED pr={n}: {raw[:120]}\n")
                    continue
                data["pr"] = n
                data["mergedAt"] = pr["mergedAt"]
                data["commentAt"] = c["createdAt"]
                rows.append(data)
        n_done += 1
        if n_done % 25 == 0:
            sys.stderr.write(f"progress {n_done}/{len(targets)} PRs\n")
    for r in rows:
        print(json.dumps(r, sort_keys=True))
    sys.stderr.write(f"done: {len(rows)} rounds over {len(targets)} PRs\n")


if __name__ == "__main__":
    main()
