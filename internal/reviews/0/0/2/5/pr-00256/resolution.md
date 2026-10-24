# Resolution — pr-00256 (docs end-user optimization pass)

Chain: snapshot a (wave review of 716b8c0..b69a336, 11 effective findings)
→ snapshot b (micro review of the a-wave fix's test-docs.sh pins,
2 findings B1-B2, both fixed in the b fix wave).
This file is created with the first fix commit and grows per disposition.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `d01c7eb` | `shopware6` restored (ddev-integration.md:108); sweep + pin, see detail |
| a W2 (MED) | **implemented** | `d01c7eb` | TOCTOU bullet restored (security-model.md:60-63); pin, see detail |
| a W3 (LOW) | **implemented** | `d01c7eb` | exception clause restored (cli.md:303-305); sweep + pin, see detail |
| a W4 (LOW) | **implemented** | `d01c7eb` | anchor restored (compatibility.md:57); link check validates it |
| a W5 (LOW) | **implemented** | `d01c7eb` | Enter-default note restored; pin tracks install.sh's menu letter |
| a W6 (LOW) | **implemented** | `d01c7eb` | conditional OpenChamber question named + linked in getting-started |
| a W7 (LOW) | **implemented** | `d01c7eb` | /mnt/c disclosure restored at the verify step, never-edits framing |
| a W8 (INFO) | **implemented** | `d01c7eb` | "--yes without the flag the pin stays off" restored (verified true) |
| a W9 (INFO) | **implemented differently** | `d01c7eb` | liveness clause restored; roadmap drop accepted (see detail) |
| a W10 (INFO) | **implemented** | `d01c7eb` | rotate-on-distrust clause restored (ddev-integration.md) |
| a W11 (INFO) | **deliberately not done** | — | pointer/history losses stay out of end-user docs, see detail |
| b B1 (LOW) | **implemented** | `03fdbfe` | sed capture `[mcs]`→`[a-z]` — unmapped guard reachable; see detail |
| b B2 (LOW) | **implemented** | `03fdbfe` | reverse-direction pin + docs-extraction tripwire; see detail |

## Evidence detail

All code anchors verified at the fix tree; docs anchors are content anchors
(grep-able strings) — line numbers are this tree's coordinates.

### a W1 (MED) — shopware6 value restore

ddev-integration.md's root-file list again reads `codeigniter`,
`shopware6`, `symfony` (content anchor: "Root-file types"). Claim audit:
the shipped matcher (ddev-handover.sh:466, ddev-terminal.sh:357+400) is
`codeigniter|shopware6|symfony` — restored value matches. Class sweep
(L2): pattern `grep -rn -iE "shopware|codeigniter|symfony|typo3|maho|
modx|drupal|backdrop|magento" docs/` — every type value in the docs table
(typo3, drupal*, backdrop, magento*, maho, modx, codeigniter, shopware6,
symfony) exists in the code vocabulary; prose "TYPO3" brand mentions
(:56, :120) are not type values; no second drifted site. Pin (test-docs.sh,
"#256 a W1"): extracts the root-file arm from ddev-handover.sh (tripwire
on anchor drift) and requires each type backticked in the docs page —
renaming `shopware6` back to `shopware` goes red (sabotage record below).

### a W2 (MED) — dev-owned flag-write TOCTOU disclosure restore

security-model.md's residual gaps again carry the bullet (content anchor:
"flag-write TOCTOU stays accepted"). Restored wording is grounded, not
invented: the flag write screens for symlinks (ddev-handover.sh:98, :126,
:189 — warns/skips, "links are never followed") but is not atomic, impact
capped at opencode privilege — near-verbatim the old reviewed sentence.
Class sweep (L2): old vs new residual-gap bullet heads enumerated —
Bash-spawned reads, Bind-mounted containers, Renamed copies, swaps bullet,
mkcert, supply chain, OpenChamber password; the TOCTOU tail was the only
dropped disclosure, now restored. The reviewer's folded-in detail (mid-scan
swap → skip-with-warning "on every branch") stays condensed: the
non-atomic-gate essence survives in the handover bullet — accepted
condensation, not a dropped disclosure. Pin (test-docs.sh, "#256 a W2"):
grep for the TOCTOU disclosure — deleting the bullet goes red.

### a W3 (LOW) — advisories exception clause restore

cli.md's missing-library sentence again ends "…; the advisories row names
the skipped security checks instead)" (content anchor: "skipped security
checks instead"). Claim audit: status.sh:373 row text confirmed; the five
file-naming sibling rows confirmed (:353, :770, :845, :999, :1096). Sweep
(L2): :303 is the only "the row names" blanket claim in cli.md. Pin
(test-docs.sh, "#256 a W3"): grep for the clause tail — re-shortening to
the blanket claim goes red. Live discrimination already observed: the pin's
first phrasing caught the fix's own line wrap (phrase split across lines)
and went red — rewrapped pin phrase is wrap-safe and the discrimination is
witnessed, not assumed.

### a W4 (LOW) — anchor restore

compatibility.md's OpenChamber bypass link again points at
`../how-to/openchamber.md#prevent-the-bypass-the-policy-pin`; the heading
exists (openchamber.md:52) and the suite's GitHub-slug checker validates
the anchor on every run (test-docs.sh) — a standing pin, no extra one.

### a W5 (LOW) — Enter-default caveat restore

getting-started.md again says "Enter defaults to **skip** — move removes
the developer-side sources after the copy, so it never rides on an empty
Enter". Claim audit: menu default letter "s" (install.sh:2295); move
removes the dev-side sources after the copy (`sudo rm -rf "$_opk_src"`,
install.sh:2235). Sweep (L2): cli.md:199's "default: ask (`--yes` = move)"
covers the FLAG default and matches the non-interactive branch
(install.sh:2300 `_opk_ag=m`) — consistent, no sibling site. Pin
(test-docs.sh, "#256 a W5"): extracts the ui_menu default letter from
install.sh (tripwire + unmapped-letter guard) and requires the matching
"defaults to **word**" phrase in getting-started.md — flipping either side
goes red.

### a W6 (LOW) — conditional installer question named

getting-started.md now names the fifth, conditional question ("Protect
OpenChamber sessions too?") with a link to the how-to. Claim audit: the
question fires whenever interactive + OpenChamber detected
(install.sh:1072-1077) — pre-existing gap (snapshot a W6, provenance
pre-existing) closed by the fix wave.

### a W7 (LOW) — /mnt/c install-path disclosure restore

getting-started.md's verify step now discloses the /mnt/c exposure, the
start warning, the manual snippet, and the never-edits framing. Claim
audit: exposure section exists (status.sh:1099+), warn-on-start +
never-edits statements carried from security-model.md:87-90 (cross-checked
this wave); the restored sentence links there. RM-0104 framing intact
(opt-in/manual, kit never writes /etc/wsl.conf).

### a W8 (INFO) — unattended default restored

openchamber.md again states "under `--yes` without the flag the pin stays
off". Claim audit: install.sh:1081 (`|| OPENCHAMBER_POLICY=no`) after the
keep-earlier-opt-in branch (:1076) — the restored default is true. No pin:
the default is compound logic (keep-earlier-opt-in), no stable one-token
anchor to extract at proportionate cost; recorded as verified prose.

### a W9 (INFO) — supply-chain detail, partially restored

The liveness-check clause is back ("the `--binary` "verification" is a
liveness check — `opencode --version` runs — not an integrity check").
Claim audit: bounded --version probe confirmed (update.sh:1016-1031).
Deliberately NOT restored: the pinned-release checksum-manifest roadmap
sentence — condensation is the wave's purpose, the trust conclusion is
unchanged, and the roadmap lives in the design records. Implemented
differently therefore.

### a W10 (INFO) — rotate-on-distrust restored

ddev-integration.md's SSH-key trade-off again ends "Prefer dedicated,
rotatable deploy keys — and rotate them if the machine is not trusted."
Hygiene advice, no code claim; no pin (nothing mechanical to extract).

### a W11 (INFO) — pointer/history losses stay dropped

Every sub-item verified in snapshot a with no safety-meaning change;
the wave's purpose (end-user shortening) argues they stay out of user
docs: internal/records rationale links (design-record territory, the
consent statements remain), the historical 0.0.36 recovery section
(auto-stripped since 0.0.38, no realistic trigger at base 0.0.56), the
"root-equivalent-access" status enumeration item (audit still documented
in security-model.md), the legacy //SECURE_GIT diagnostics block, and the
uninstall home-loss parenthetical "(ddev homes, imported keys)" — the
home-removal ask with its default:no survives. The wsl-ask `--yes`
shorthand drop the reviewer misattributed to uninstall.md was real in
security-model.md/files.md only, and the behavior stays documented in
cli.md:45+217.

### b B1 (LOW) — W5 pin's unmapped-letter guard made reachable

The sed capture class was exactly the mapped set (`[mcs]`), so the
"unmapped default" branch (test-docs.sh, #256 a W5) was unsatisfiable
dead code — a default letter outside the vocabulary broke the sed match
instead and misfired the anchor-drift tripwire. Fix: capture widened to
`[a-z]`; the case still maps m/c/s, anything else now lands in the
unmapped guard with the correct message. This also makes the
"unmapped-letter guard" claim in the a-W5 evidence detail (above) true
as written. Class sweep (L2): the other extraction pins carry tripwires
on the same shape (F36 #211 b W28 both directions, W1 both sides); no
further dead guard exists — W1/W2/W3 pins have no unreachable branches
(bare greps or tripwired extractions only).

### b B2 (LOW) — W1 pin gains the reverse direction

New block in test-docs.sh (#256 b B2): extracts the backticked types
from the docs paragraph anchor `**Root-file types (…` (up to the first
`)`, so the `.env` mentions later in the paragraph are out of scope),
tripwires on empty extraction, and requires every docs type to appear
in the code matcher set (`codeigniter` + the extracted handover arms).
Membership is word-delimited, so `shopware` does not false-match
`shopware6`. Wildcard tokens (`drupal*`) count as drift by definition —
matcher arms are literal. Live discrimination witnessed before commit:
the extraction's first phrasing (backslash-escaped backticks in the
grep ERE) went RED on the clean tree via its own tripwire — GNU grep
ERE does not match `\`` — the pin caught its author's regex bug; fixed
to the plain-backtick form and green. The #211 b W30 precedent (reverse
direction added to the F36 flag pin) is the sibling this closes for W1.

## Gates and sabotage record

Gates at the fix commit d01c7eb (check-then-commit, all before the commit):
`sh tests/unit/test-docs.sh` OK (with the four new pins),
`sh tests/unit/test-line-length.sh` OK (ratchet baseline held; one
resolution row rewrapped after a first red), `sh tests/unit/test-reviews-
lint.sh` OK, `sh tests/unit/test-reviews-parity.sh` OK (after INDEX
regen), `make lint` (ShellCheck) OK.

Sabotage spot-checks on the committed tree (delete-never-comment;
`git restore` back; final suite green):

- Run A (four docs mutations at once): `shopware6`→`shopware`
  (ddev-integration.md), `flag-write TOCTOU`→`flag-write race accepted`
  (security-model.md), `skipped security checks instead`→`skipped checks
  instead` (cli.md), `defaults to **skip**`→`defaults to **move**`
  (getting-started.md) — suite RED with exactly the four pin FAIL lines
  (#256 a W1, W2, W3, W5), each naming its finding.
- Run B (code direction, W5): install.sh's ui_menu default letter "s"→"m"
  — suite RED with the W5 FAIL line ("'m' => move"), proving the pin
  tracks the code side, not only the docs side. Restored; suite green.
- Live discrimination witnessed before commit: the W3 pin's first phrasing
  ("advisories row names the skipped security checks") went RED on the
  fix's own line wrap — the pin caught a real split-phrase regression
  shape; rewrapped to the wrap-safe tail.

### b-wave (fix commit 03fdbfe)

Gates at 03fdbfe (check-then-commit, all before the commit):
`sh tests/unit/test-docs.sh` OK (with both new pin directions),
`sh tests/unit/test-line-length.sh` OK, `make lint` (ShellCheck) OK,
`sh tests/unit/test-sandbox-policy.sh` OK, full unit sweep
(`sh tests/unit/test-*.sh`) OK — no suite interference from the new
`_w1_dt`/`_w1_doctypes` namespace.

Sabotage spot-checks on the committed tree (delete-never-comment;
`git restore` back; final suite green):

- Run 1 (b B2 reverse): `laravel` added to the docs root-file paragraph —
  suite RED with exactly `docs root-file type 'laravel' not in the code
  matcher (#256 b B2)`.
- Run 2 (b B2 tripwire): paragraph anchor `Root-file types`→`Root-file
  kinds` — suite RED with `docs root-file-type extraction empty — anchor
  drift? (#256 b B2)`.
- Run 3 (b B1): install.sh's ui_menu default letter "s"→"x" — suite RED
  with `unmapped agent-resources menu default 'x' (#256 a W5)`: the
  previously dead guard fires with the correct attribution.
- Run 4 (forward regression, a W1 shape): `shopware6`→`shopware` in the
  docs — suite RED from BOTH directions (`missing from the docs` #256 a
  W1 + `not in the code matcher` #256 b B2); restored, final suite green.
- Live discrimination witnessed before commit: the b B2 extraction's
  first phrasing went RED on the clean tree via its own tripwire (escaped
  backticks match nothing in GNU grep ERE) — see the b B2 detail.

## Follow-ups

- Round c (micro-wave review of the b fix diff) is OWED: the wave touches
  test code (test-docs.sh pins), which is review-relevant (RM-0105) — the
  review starts on the maintainer's go, not before.
