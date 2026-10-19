<!-- review-meta
ID: pr-00208
Snapshot: a
Subject: issue-205 git-config status/apply wording (feature wave)
Scope: wave
Base: v0.0.53 @ f07f2fb
Diff: 9d89dea (single feature commit: config.sh +17/-5, test-git-config.sh +17, docs/how-to/secure-git-config.md +13)
Date: 2026-10-20
Reviewer: GLM-5.3 (house session — maintainer-requested micro pass, single-pass main agent, no subagents)
-->

# Review — pr-00208 snapshot a — issue-205 git-config wording

Wave question: did the wave break or lie? Wave = `9d89dea`: the
`opk config git-config status` rows drop the bare `ON  ($f, soft-only)`
shape for `ON — protected (soft-only, agent tools blocked)` /
`OFF — access allowed (agent tools may edit git config)`, the file path
moves to a `ui_detail` line, `on`/`off` apply confirmations reuse the
same rows, a wording pin lands in test-git-config.sh, and the how-to
shows the output. Claimed intent (PR + in-code comment): same wording
`opk status` shows (issue #158), so both outputs agree.

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | the ON phrase is NOT the same wording status.sh shows — config.sh says `protected (soft-only, agent tools blocked)` (comma), status.sh:206 says `protected (soft-only — agent tools blocked)` (em dash); the wave's own claim ("same wording … both outputs agree", code comment + PR + docs) fails on one of its two phrases | wave-introduced |
| W2 | LOW | the how-to now documents the status output but shows only 2 of its 3 shapes — the markers-present branch's detail suffix `(markers present, rules inactive)` (config.sh:416) appears nowhere in docs | wave-introduced |

## W1 (LOW) — ON phrase differs from status.sh; equality claim fails

Verified on the tree: `status.sh:206` renders
`ui_kv_ok ".git/config" "protected (soft-only — agent tools blocked)"`
(em dash between `soft-only` and `agent`), while both new ON sites
(`config.sh:412`, `config.sh:478`) render
`"ON — protected (soft-only, agent tools blocked)"` (comma). The OFF
phrase `access allowed (agent tools may edit git config)` matches
status.sh:208 exactly at all three new sites. So the alignment the wave
exists for holds verbatim for OFF and is off by one punctuation mark for
ON — user-visible only when a user diffs the two outputs side by side;
no parser consumes either string (output is display-only; CI gates on
exit codes). The claim audit is the real defect: the PR text, the new
in-code comment (config.sh:407-409, "the same phrases `opk status` uses
… so both outputs agree") and the new docs sentence
(secure-git-config.md:33-34, "the same wording `opk status` shows")
each assert a phrase-equality that is testable and false for ON. The
new unit pin (test-git-config.sh:288-303) pins config.sh's internal
consistency only — nothing pins cross-file agreement with status.sh,
which is why the gap passed a green suite. Fix is one character either
way: align config.sh to the em-dash form, or weaken the three claims to
"mirrors the `opk status` phrasing". Note the em-dash fix touches
production strings and the pin literals → owes snapshot b.

## W2 (LOW) — third status shape undocumented in the how-to

`git_config_status` has three branches (config.sh:411-419): ON,
OFF-with-markers, OFF-clean. The how-to's new example blocks
(secure-git-config.md:36-43) show ON and OFF-clean only; the
markers-present case renders the detail line
`$f (markers present, rules inactive)` (config.sh:416), which no docs
page mentions. The suffix itself is pre-existing wording carried over
from the old `OFF  ($f — markers present, rules inactive)` row, so this
is a docs-completeness gap opened by this wave's "how-to shows the
output" claim, not a behavior change. One docs sentence closes it;
docs-only disposition would not extend the chain under the stop rule.

## Verified claims (commit/PR audit)

- Class sweep: no `"ON  (` / `"OFF  (` rows survive anywhere under
  files/ (incl. tui/) or docs/ — the old format is fully gone; the
  wave's sweep obligation holds.
- Pin discrimination: the new pin's counted forms match reality —
  `grep -cF` finds exactly 2 ON sites (status + apply) and 3 OFF sites
  (status×2 + apply), matching its `-ge 2` / `-ge 3` guards; the
  negative `grep -qF '"ON  ('` / `'"OFF  ('` target exactly the retired
  format; `$CONFIG` is defined at test-git-config.sh:279, before the
  pin. Suite green: 34 passed, 0 failed.
- Docs examples are rendering-exact: `ui_kv`'s format string
  (`'  %-14s %s%s%s\n'`, sh/ui.sh:123) puts the value at column 17 for
  the 10-char `git-config` key — the docs' 5 spaces between key and
  value match; `ui_detail` (sh/ui.sh:78-79) indents 5 spaces, matching
  the docs' path lines.
- `git_config_apply` reorder is behavior-neutral: `ui_detail "$target"`
  moved below the if/else covers both branches; the path info that
  previously rode inside the ui_kv value is now suppressed under
  `UI_SILENT=1` — consistent with ui_detail's silent guard and with
  how every other detail line behaves; `log` still records
  target + enable for the log consumers.
- No consumer parses the old rows: greps over files/, tui/, tests/,
  .github/, scripts/, Makefile find no reference to the `ON  (`
  shape.

## Gates

- `sh tests/unit/test-git-config.sh` — green, 34 passed, rc=0.
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, clean tree at `9d89dea`
  throughout (wording-only wave; no mutations needed).

## Retracted/ghost findings

None filed. Explicitly considered and dropped: the `UI_SILENT=1` path
suppression (verified consistent with the ui contract and the log line,
see above); an em-dash punctuation lint over shipped strings (no
consumer splits on either character — a guard would be taste, not a
pin).

## Provenance

W1 wave-introduced: both the new ON phrase and the equality claim
(README comment, PR body, docs sentence) landed with `9d89dea`.
W2 wave-introduced: the how-to output blocks landed with `9d89dea`
without the third shape; the undocumented suffix text is pre-existing
wording carried forward. Run provenance: header.

## Recommendation

**GO.** No MED/HIGH finding — the wave does what it set out to do
(effect spelled out, class sweep clean, pin discriminates, docs
rendering-exact, no parser depends on the old shape). W1/W2 are claim
and docs gaps. W1's string-alignment fix (if chosen over weakening the
claim) touches production strings and the pin literals and therefore
owes snapshot b; a weaken-the-claims disposition plus the W2 docs
sentence would close the chain without touching review-relevant code.
