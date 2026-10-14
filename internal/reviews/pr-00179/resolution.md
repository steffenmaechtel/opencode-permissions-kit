# Review resolution — pr-00179 (issue #173 docs reflow baseline)

Status: closed

Case: wave review `a` of `feature/issue-173-docs-reflow-baseline`
(`ee54ca0..6e87eed`, docs-only: 12 docs files + line-length baseline
burn-down). Verdict at review time: 0 HIGH/MED, 1 LOW + 2 INFO, stop rule
met. All three findings dispositioned **deliberately not done** — no fix
commit exists or is owed; the special case of the stop rule applies
(every finding deliberately not done → nothing changed, nothing to
review).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **deliberately not done** | — | update.sh URLs are unbreakable under 120 — see detail |
| a W2 (INFO) | **deliberately not done** | — | all three nuances survive in same-page prose |
| a W3 (INFO) | **deliberately not done** | — | taste; detail sits directly beneath the rows |

## Evidence detail

### a W1 (LOW) — wrapped vs. unwrapped one-liners

The six surviving overlong lines (update.md 33/36/39/69/89, cli.md 287)
are the `update.sh` curl-streaming one-liners. Measured: their URL
segment alone runs ~150–165 content columns
(`.../opencode-permissions-kit-lib/management/update.sh` under the
longest ref path), so a `\`-wrap can shave the tail onto its own line
but can never bring the URL line under the 120 limit — unlike the
`install.sh` one-liners, whose shorter URLs fit under 120 when wrapped,
which is exactly why the wave wrapped those and only those. Wrapping the
update.sh six would shrink baseline excess (325/62 → roughly half)
without clearing a single entry, at the cost of turning six
triple-click-copyable one-liners into two-line blocks. Left as the
documented baseline remainder; the ratchet pins it against growth.

### a W2 (INFO) — cell specificity losses

Each lost nuance is recoverable on the same page: the enforce-vs-ask
distinction lives in "Known residual gaps" ("only caught by the
template's lexical ask-tripwires") and the intro prose of
security-model.md; the packet/log mechanism is implied by the group
names `wireshark`/`adm`/`systemd-journal` themselves; "installs and
updates track it" is entailed by "The default recommendation" plus the
channel-following prose two paragraphs below. Restoring the wording into
the cells would push them back over the limit the wave exists to clear.

### a W3 (INFO) — "(notes)" pointer labeling

Two pages point "(notes)" at an unlabeled paragraph
(sharing-group.md, container-tools.md) and one uses "(legacy fallback —
notes)" (ddev-integration.md); the other pages label their blocks (Key
notes, Surface notes, Flag notes, Command notes, Deployment notes). In
every case the detail is the paragraph directly beneath the table row,
findable without the label. A uniform labeling convention is a docs-wide
style decision, not a defect of this wave — recorded here so a future
docs wave can pick it up deliberately.

## Gates at disposition time

Reviews lint + parity OK, line-length ratchet OK (unchanged baseline),
docs link check OK, full unit sweep (36 suites) green. e2e not owed
(docs-only wave, no `files/` change).
