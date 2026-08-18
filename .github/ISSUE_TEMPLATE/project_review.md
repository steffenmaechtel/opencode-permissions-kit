---
name: Project review
about: Periodic full review (security, bugs, quality, docs, CI). Open when a
  trigger fires — see "When to run a review" in CONTRIBUTING.md.
title: 'Project review: <version or date>'
labels: 'review'
assignees: ''

---

Full review of the current state of `master` (or the branch named below).
Work through every discipline top to bottom; findings become checklist
entries here and, when actionable, separate issues labeled `review` or
`tech-debt`.

Scope: branch / commit range since last review: `<e.g. v0.0.16..master>`

## 0. Backlog first

- [ ] Open issues labeled `review` / `tech-debt` from the previous review:
      carry unresolved ones forward or close them with a reason.

## 1. Security

- [ ] sudoers surface still minimal (fixed paths, `(opencode)` only, no
      wildcards beyond the gated helpers; `visudo -c` gate intact)
- [ ] No new root-equivalent fallbacks (docker socket, docker group,
      RunAsdeveloper paths) anywhere in wrapper / helpers
- [ ] Everything root writes into world-writable dirs uses mktemp
      (backup dirs, downloaded scripts)
- [ ] New input paths validated (project paths, flags, config file reads)
- [ ] Soft-only model intact: no OS-level deny ACLs re-introduced
- [ ] Docs security pages still match the code
      (`docs/concepts/security-model.md`)

## 2. Bugs

- [ ] `set -e` / `set -u` traps: reads on closed stdin, unset vars in
      case-branches, commands whose failure kills the script mid-flow
- [ ] POSIX sh compliance (dash) for everything under `files/`

## 3. Quality

- [ ] `make lint` + full unit suite green (`make test`)
- [ ] Both e2e suites green for changes to install/update/wrapper/backend
- [ ] Duplication guards still hold (`test-kit-files.sh`,
      project_path_sane identity) — or new duplication found: decide
      refactor vs. guard vs. accept
- [ ] Error messages actionable (say what failed AND how to fix it)

## 4. Docs

- [ ] Behavior changes since the last review have matching docs changes
      (same-PR rule was followed)
- [ ] `sh tests/test-docs.sh` green; one page = one topic type

## 5. CI

- [ ] New executables are in the chmod lists (guarded — should be green)
- [ ] No workflow step duplicates what a Makefile target already does

## 6. Shrink the next review

For every finding: can it become a lint rule / unit test / guard?
Record what was automated so the checklist above can get shorter.

- [ ] Automation added for: `<rules/tests>`

## Result

- Findings: `<number>` (critical: `<n>`)
- Automated away: `<rules/tests added>`
- Next review trigger: `<version / cumulative diff / risky merges>`
