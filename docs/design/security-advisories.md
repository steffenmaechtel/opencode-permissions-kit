# Security advisory warnings

> Status: **CURRENT** — the shipped advisory database and the warning
> paths (wrapper, `opk status`, maintainer scan). Issue #107.

## Problem

opencode publishes security advisories on GitHub
(`anomalyco/opencode` → Security). A user running an affected version
must notice — without every client hammering the GitHub feed on every
start, and without the wrapper (the hot path of every `opencode`
invocation) going online.

## Design

Two sources, two jobs:

| Source | Job |
|---|---|
| **Shipped database** — `sh/advisories.sh`, static, curated, travels with every kit release | The only source that claims **"your install is affected"** |
| **Upstream feed** — GitHub's advisory API, fetched live | The **freshness signal** for `opk status` and the maintainer scan |

### The shipped database

`files/opencode-permissions-kit-lib/sh/advisories.sh` is a sourced
shell library — no real database, no service, no runtime network. One
static list (`ADVISORY_RECORDS`) plus pure helpers
(`advisories_version_of`, `advisories_version_cmp`,
`advisory_range_holds`, `advisories_matching`, `advisories_ids`).

Record fields, `|`-separated:

1. **package** — `opencode` now; `ddev` etc. later, the schema is ready
2. **ranges** — comma-separated comparators (conjunction); **refined**
   against upstream data: GitHub only opens a range (`>=1.14.30`),
   the patched version closes it here (`>=1.14.30,<1.18.22`) so
   patched installs do not warn
3. **patched** — first patched version
4. **channel** — `npm` or `standalone`; empty = every channel. The kit
   deploys the binary itself (1.x release tarball, 2.x npm tarball
   extracted — never a package manager owning the binary), so kit
   installs are always `standalone`: npm-only advisories
   (GHSA-632h-h47v-g4x4) do not match them — by design, not by luck
5. **severity**, **id**, **summary**

The upstream ecosystem of an advisory is **channel-blind** (everything
ships as npm-package advisories) — that is why channel is a *curation*
field, never inferred from upstream data.

### Wrapper warning

`bin/opencode-as-opencode` checks the database **locally on every
start** (the user-facing decision for #107: always, never throttled):

- The installed version is probed **fresh** — `sudo -n -u opencode
  <binary> --version` per start, never a stale `install.conf` stamp
  (the same lesson as the ddev version probe, issues #56/#72). Cost on
  a real host: ~4 ms; the wrapper already runs a sudo probe per start.
- `timeout(1)` bounds the probe — a wedged 2.x service makes even
  `--version` hang (issue #80). Fail-open: a failed, hung, or
  unparseable probe skips the check — a warning must never keep a
  session from starting.
- The `--version|-v|-h|--help` early-exec stays **ahead** of the check
  (issue #91): that output is parsed by scripts and the official
  installer and must stay clean.
- On a hit: red `WARNING` line, one line per advisory (id, severity,
  summary, patched version), then
  `Please upgrade opencode with 'opk upgrade-opencode'.` — stderr in
  headless mode like every wrapper warning.

### `opk status`

A dedicated **Security advisories** section:

- probes the version (same sudo path), matches the shipped database →
  red `AFFECTED` + advisory lines + fix hint, or green
  `no known advisory affects this install`
- **live upstream check** (the user-facing decision for #107): fetches
  GitHub's advisory list with a 10 s timeout, diffs the ids against the
  shipped database. An unknown upstream id means **the kit release
  lags, not that this install is affected** — output is a warn line
  plus `run: sudo opk update`. Offline / blocked / python3 missing →
  `live check unavailable`, never a false green.

### Maintainer scan (the curation loop)

`.github/workflows/security-scan.yml` (daily 05:23 UTC, manual runs
possible) runs `scripts/security-scan.sh`: fetch the upstream feed,
diff against `advisories_ids opencode`, open **one issue per unknown
advisory** (deduped by the GHSA id in the title search) with the
upstream data and a curation checklist. The script never modifies the
repo — curation and the release stay human decisions:

new issue → curate the record (channel, refined range) → cover it in
`tests/unit/test-security-advisories.sh` → `make release VERSION=x.y.z`
→ stable mirror → users get it via `opk update`.

Freshness therefore rides the normal release cadence (~1 advisory per
month upstream — the daily scan + release channel comfortably keep up).

**Untrusted input** (the feed is external data, the token has
`issues:write`): no shell re-parsing path exists — every expansion is
double-quoted, `printf '%s'`-style takes fields as arguments, free text
(summary/url) flows only into the body FILE, nothing is ever `eval`'d.
What can still be attacked is *semantics*: a crafted id could steer the
`--search` query, a smuggled tab could shift the TSV columns. So every
field that leaves the script as argv or query passes
`scan_advisory_valid` first — charset allowlists (the id pattern is a
negated-class match, never a prefix glob — a `*` tail would swallow
payloads), anchored regexes for ranges/patched, vocabulary for severity.
A malformed advisory is skipped loudly and fails the run. Payload
attempts (command substitution, qualifier smuggling, column shifts) are
unit-tested in `tests/unit/test-security-advisories.sh` (§8).

## Initial database (2026-09)

All three upstream advisories shipped as records:

| Advisory | Severity | Ranges | Channel |
|---|---|---|---|
| GHSA-vxw4-wv6m-9hhh | high | `<1.0.216` | every |
| GHSA-c83v-7274-4vgp | critical | `<1.1.10` | every |
| GHSA-632h-h47v-g4x4 | high | `>=1.14.30,<1.18.22` | npm |

The first two predate realistic kit installs by far (the kit is young,
its opencode versions are current) — they exist so the upstream diff
stays green and so even an exotic `opk upgrade-opencode --version`
pin of an ancient release warns.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | Static shipped database, checked locally — no client-side feed fetches | Hot path stays offline/fast; freshness rides releases |
| 2 | Version probed fresh per start (no stamp) | Stamps go stale the moment a binary is swapped outside `opk` (issues #56/#72) |
| 3 | Warn on every start, never throttled | Cheap (local), and a security nag that hides itself is not a warning |
| 4 | Fail-open on probe/parse errors | Availability of the session over the warning |
| 5 | Upstream feed never decides affectedness | Upstream ranges are channel-blind; only the curated record may claim a hit |
| 6 | `opk status` does the only live check | Interactive, not hot path; offline-fallback wording |
| 7 | Scan opens issues, never PRs | Curation (channel, refined ranges) needs judgment; automation only notices |

## Test coverage

`tests/unit/test-security-advisories.sh`: version parsing (1.x/2.x
lines), `sort -V` segment order (1.10.0 > 1.9.0), range conjunctions
and boundaries, record shape (7 fields, vocabulary, comparators),
matching against the real shipped database — including the headline
property (patched versions and standalone installs do not hit the
npm-only advisory) — and the wrapper/status wiring (early-exec order,
timeout-bounded probe, upgrade hints). The e2e suites run the wrapper
with the database deployed (its npm-only record stays silent on kit
installs, so golden outputs are unaffected).
