# ddev's CLI contract — verified facts behind the migrate name gates

> Status: **CURRENT** (living reference). Measured 2026-11-18 against
> the local ddev source clone (§2) at commit 319fa3d3d (ddev/ddev main;
> vendored cobra v1.10.2, pflag v1.0.10 per go.mod). Origin: issue #635
> — the dash-shape gate decision. It retires the #612-era caveat
> ("ddev's own project-name validation is external behavior,
> unverifiable from this repo"): on this host it IS verifiable, and the
> next ddev-contract claim gets measured, not caveated. The general
> lesson — claims about an external tool's behavior are measured against
> the tool, never inherited — is [agent/learnings.md](../../agent/learnings.md)
> L3's class; this record is that class's ddev instance (the sibling
> instance is [sudo-l-contract.md](sudo-l-contract.md)).

## 1. The question

ddev-migrate.sh addresses projects by bare NAME in ddev argv —
`start`/`export-db`/`stop` on the export side, `start`/`import-db` on
the import side — using registry- and manifest-derived strings. The
gate waves #612 (slash / `..` shapes) and #635 (dash shapes) needed
ddev's CLI contract to decide the gate design: which dash arguments
parse as flags, whether a `--` end-of-options separator would rescue a
literal name, and whether a dash-leading name could ever be
legitimate.

## 2. The substrate

- Local clone: `/var/www/vhosts/opencode-permissions-kit/github/ddev`
  (ddev/ddev, branch main). Read substrate only — update with
  `git fetch && git merge --ff-only origin/main`, never commit there.
- Cobra/pflag behavior is read from the clone's `vendor/` tree: the
  go.mod pins at the measured commit are part of the provenance, and a
  future ddev bump can silently change flag semantics.
- Provenance duty: a wave that consults a fact records the commit it
  measured against (this header or the wave's gate comment). Nothing
  in the kit depends on the clone at runtime — it is maintainer-side
  verification only, and CI/checkouts never see it.

## 3. The measured facts (commit 319fa3d3d)

**Project names are RFC 1123 hostname labels** — every label starts
and ends with `[a-zA-Z0-9]`, hyphens interior only
(`pkg/ddevapp/config.go:32` hostRegex, enforced by
`ValidateProjectName` at :483 through `ValidateConfig` and at project
creation). Measured against the regex: `--all`, `-x`, `-foo`, `foo-`,
`my_project` never match; `my-project`, `9foo`, `a--b` do. Corollary:
a dash-leading registry key or manifest name can never be a real ddev
project — refusing it has no false-positive arm.

**`ddev start` and `ddev stop` really carry `--all` (`-a`)** —
`cmd/ddev/cmd/start.go:230` ("Start all projects"), `stop.go:155`
(stop and remove all running projects): a bare dash argument in name
position silently changes semantics fleet-wide — start hits every
registered project, stop every running or container-stopped one (the
export loop's one-at-a-time discipline exists for RAM).

**`ddev export-db` / `ddev import-db` have no `--all`** — their
`Args:` is `cobra.RangeArgs(0, 1)` (count only; `export-db.go:40`,
`import-db.go:18`), so a dash argument dies at pflag parse
("unknown flag") before the command runs.

**`--` IS honored ddev-side** — pflag terminates flag parsing at `--`
(vendored `flag.go`, `parseArgs`); start/stop define no Args validator,
so `ddev start -- --all` delivers a literal positional that then fails
at name lookup. A `--`-based fix would have been VIABLE; the rejection
grounds are operand order and signal quality, not parser support (§4).

**Name resolution goes through `getRequestedProjects`** —
`cmd/ddev/cmd/utils.go:16` (the exported wrapper;
`getRequestedProjectsExtended` at :22), called by all four
subcommands; misses fail with
`could not find requested project '<name>'` (:72).
`ddev stop --unlist` skips config validation (`stop.go:93`) — that
bypasses checking an already-catalogued project, never the creation
of a dash-leading name.

## 4. What the kit concluded (#635)

Both migrate name gates refuse dash-leading names instead of passing
`--` separators — the full rationale (operand order under `--file=`,
the no-false-positive arm, the ddev-hosts.sh 0.0.39g Q6 sibling
precedent) lives in the gate comments in
`files/opencode-permissions-kit-lib/sh/ddev-migrate.sh` (export loop
and import loop) and is not restated here. Design context for the
migration flow itself: [ddev-migration.md](ddev-migration.md).
