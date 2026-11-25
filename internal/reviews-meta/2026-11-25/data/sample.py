#!/usr/bin/env python3
"""Draw the M3 classification sample: 25 rounds, seeded, from the
window 2026-11-18..2026-11-24; emit per-batch assignments (5 batches)."""

import json
import random
from collections import defaultdict

rows = [json.loads(l) for l in open("rounds.jsonl")]
win = [r for r in rows if "2026-11-18" <= r["mergedAt"] <= "2026-11-24"]
rng = random.Random(768)
sample = rng.sample(win, 25)
sample.sort(key=lambda r: (r["pr"], r["wave"]))

batches = defaultdict(list)
for i, r in enumerate(sample):
    batches[i % 5 + 1].append(r)

for b in sorted(batches):
    print(f"## batch b{b}")
    tot = 0
    for r in batches[b]:
        print(f"  PR {r['pr']} wave {r['wave']} date {r['mergedAt']} raw {r['raw']}")
        tot += r["raw"] or 0
    print(f"  -> {len(batches[b])} rounds, {tot} findings")

with open("sample.json", "w") as f:
    json.dump({"seed": 768, "rounds": sample}, f, indent=1)
total = sum(r["raw"] or 0 for r in sample)
print(f"\ntotal sample findings: {total}")
