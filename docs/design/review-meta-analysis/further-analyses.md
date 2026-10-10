# Further analyses — precision, provenance, blind spots, convergence

> **As of the analysis run 2026-10-10.** Corpus: review snapshots 0.0.38–0.0.46
> (54 snapshots, 2026-09-26 → 2026-10-09). Point-in-time measurement —
> re-run instructions in the [record README](README.md#re-running-this-analysis),
> raw data in [data/](data/README.md).

## 1) Review precision

Of 620 extracted rows, **67 (10.8 %) were dropped inside the review itself**
(46 retracted, 21 rejected) and 12 downgraded — the lead-verification step
("every claim verified against the code") works.

| Reviewer group | Snapshots | Rows | dropped | Rate |
|---|--:|--:|--:|--:|
| GLM-5.3-Flash (subagents) | 27 | 312 | 30 | 9.6 % |
| GLM-5.3 (family) | 26 | 281 | 35 | 12.5 % |
| GPT-6 Luna (external) | 1 | 27 | 2 | 7.4 % |

Small samples — read with care: Flash as a *reviewer* is not markedly less
precise; lead verification catches the false positives. Retractions cluster
in high-volume wave reviews (0.0.43b: 13, 0.0.44a: 11 rejected) — fresh-context
sessions also document their "considered and rejected" discipline better.

**What the grouping cannot show (maintainer calibration, 2026-10-10):** the
axis above is the *model* — but the model was never the big difference
between the review eras. The **tooling** was:

| Era | Tooling | Snapshots |
|---|---|---|
| A | opencode v1, kit's custom review skill, single session (no subagents) | 0.0.38, 0.0.39a–e |
| B | opencode v1, kit's custom review skill + custom fresh-context subagents (GLM-5.3-Flash) | internal snapshots ~0.0.42–0.0.45 |
| C | opencode **v2 with its built-in `/review` skill** | 0.0.45c–f, 0.0.46b–c (external); 0.0.46a ran the v2 agent in the repo session; 0.0.42e (GPT-6 Luna) was the early external full pass that established the pattern |

The v2 built-in `/review` is much stronger than v1's `/review` and much
stronger than the kit's custom project review skill. The precision table
above is confounded with this timeline (the C-era sessions are also the
fresh-context external ones) — it must not be read as a model ranking.

## 2) Escape and provenance

| Provenance | Share | Meaning |
|---|--:|---|
| pre-existing | 44 % | full reviews lift legacy debt (0.0.39a/b: 57/59 rows predate the tag) |
| **fix-induced** | **20 %** | **our own repair wave introduces the next defect** |
| wave + delta introduced | 19 % | the new feature brings its class along |

The most expensive phase is not the feature, it is the **fix wave** — and the
wave reviews catch exactly these (0.0.42f: all 5 MED fix-induced/fix-incomplete;
0.0.44d: 2 of 4). The loop's economy is right: one micro-wave review per fix
wave. (Also the reason for L6 in [learnings.md](learnings.md).)

## 3) Blind spots: review tooling (v1 custom skill vs v2 `/review`), wave vs full

Maintainer calibration (2026-10-10): what separated the deep passes from the
shallow ones was never mainly the model — it was the session tooling.
"Internal" reviews ran opencode v1 with the kit's custom project review
skill (first solo — era A — then with custom GLM-5.3-Flash subagents — era
B); the deep external passes ran **opencode v2 with its built-in `/review`
skill**, which is much stronger than v1's `/review` and much stronger than
the custom project review skill.

- **Same tree, two reviews, different depth:** 0.0.42d (internal, v1 custom
  skill + Flash subagents, tree `b3418ac`) found 2 MED — 0.0.42e (external,
  *same tree*) found 2 HIGH + 6 MED, including the uninstall chown symlink
  (S1) and the unit suite `rm -rf` on fixed host paths (S2, executed as an
  incident on the external host).
- **The cleanest tooling comparison in the corpus — same tree, same model,
  one day apart:** 0.0.45b (external, but opencode **1.18.34 with the kit's
  own skills**, three sequential roles, no subagent tool) found 4 findings,
  zero MED/HIGH, verdict "release-ready". 0.0.45c (external, opencode
  **2.0.22**, lead + four fresh-context axis subagents) found **2 HIGH +
  6 MED** on the same tree — including both HIGHs that shaped 0.0.46. The
  skill made the difference; neither the model nor externality alone did.
- **Both v2-era full passes (0.0.42e, 0.0.45c) delivered 8 HIGH+MED each**,
  including 4 of the 12 HIGHs overall. Wave reviews almost never find HIGHs
  (their scope is the diff).
- **Keep:** a pre-release full pass through **opencode v2's built-in
  `/review`** in a fresh external session (established since 0.0.42e /
  0.0.45b–c) — the only proven source of `perm-model` HIGHs. Fresh eyes
  help; the v2 `/review` tooling is why it works.

## 4) Convergence speed

| Version chain | Snapshots until stop rule met | Duration |
|---|--:|---|
| 0.0.39 (a→p) | 16 | 5 days |
| 0.0.42 (a→i) | 9 | 2 days |
| 0.0.43 (a→b) | 2 | 1 day |
| 0.0.44 (a→g) | 7 | **1 day** (7 waves) |
| 0.0.45 (a→f) | 6 | 3 days |
| 0.0.46 (a→c) | 3 | 2 days, 1 MED total |

0.0.39 needed 16 snapshots to converge; 0.0.46 needed 3 — on a larger code
base. The loop speeds up because (a) the stop-rule culture took hold, (b)
class sweeps prevent large aftershocks, (c) snapshots are created with the
first fix commit (README rule 4, since 0.0.41). Caveat: 0.0.39 was the big
hardening monolith, 0.0.46 a small feature — comparability is limited.

## 5) Severity trend over time

HIGH+MED per full/external pass: 0.0.38: 16 → 0.0.39a: 19 → 0.0.39e: 5 →
0.0.39g: 7 → 0.0.41f: 1 → 0.0.42d: 2 → 0.0.42e: 8 (external) → 0.0.43a: 6 →
0.0.44a: 4 → 0.0.45c: 8 (external) → final waves 0.0.45f/0.0.46: 0–1.

The stock gets cleaner (internal passes 16 → 2), but **every new subsystem
(ddev export 0.0.44, security hardening 0.0.45) produces a fresh spike** —
20 % of which is fix-induced. The center of gravity shifts from
`shell-semantics`/`docs-policy` (early) to `perm-model`/`silent-failure`/
`fix-regression` (late): from hygiene to design depth.

## 6) tests-unit is hotspot #1

92 findings touch unit tests; 60 % of those are `test-vacuous`/`test-gap`.
The e2e suites almost never collect findings (7). Unit coverage grows with
every feature, but its own quality is the least verified — L4 in
[learnings.md](learnings.md) targets exactly this.

## 7) Analyses worth running next (ideas, no data yet)

1. **Class half-life:** how often does a *named* class recur after its naming?
   First raw signals: the "0.0.42d class" recurred 2×, the 0.0.39b-probe
   class 3× — naming alone did not stop them; only the enforced step did
   (compare `sibling-sweep`). A re-run delta makes this systematic.
2. **Snapshot→disposition latency:** extract timestamps from resolution
   commits (`git log`) — measures rule-4 compliance (resolution grows with
   the chain).
3. **Catch quota per gate level:** which share of MED/HIGH could unit/e2e/
   rootless/ddev have caught? (Summaries already carry hints: "e2e-invisible",
   "CI-blind" — extractable from the JSON.)
4. **Issue↔class coupling:** map issues (#80, #94, #112, #116, #118, #123,
   #145, #149) to classes — does issue-driven work produce different defect
   classes than review-driven work?
5. **Fix cost per class:** fix commits per finding class (from resolution
   SHAs) — prioritizes the learnings by cost instead of count.
6. **Fail-but-green guard:** a suite-level check "named FAILs vs rc 0" would
   generically prevent the `0.0.44c C1` class (L4b) — small, high-yield
   kit improvement candidate.
7. **Review-prompt calibration:** snapshots since 0.0.45d are verbatim
   external sessions; their MED→LOW downgrade rate is a quality signal for
   prompt/skill tuning.

## 8) Data quality of this analysis

- Classification by 9 independent agents on one taxonomy; judgment calls
  documented (version-parse family → `silent-failure`, acceptance records →
  `other`). `other` (57) could shed ~2–3 more subclasses (supply chain, API
  contract, data format) with a finer cut.
- A few known duplicate rows from parallel in-review agents (~3–5 cases) —
  irrelevant for class trends, slightly inflating absolute n.
- Severity partly inferred (Q-tier, ghosts), flagged per row in the JSON.
