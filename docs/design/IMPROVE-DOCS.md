# IMPROVE-DOCS: Rebuild the documentation (README + split handbook)

> Status: **DECIDED (2026-08-17)** — the §9 open questions are answered (see
> §9 "Decisions"); implementation not started yet. This is the design/plan
> record for the documentation epic. Implementation happens phase by phase
> (see §8), ideally as one GitHub issue per phase so PRs can close them
> (`Closes #N`, see `local/INFO-INTERN.md` workflow).

## 1. Problem

The kit's documentation has grown organically and now has structural problems:

- **`docs/MANUAL.md` is a 622-line monolith.** Installation tutorial, concept
  explanations (security model, sharing group), how-to guides (manage
  projects, customize denies), and reference material (file overview,
  `install.conf` keys) are mixed in one file. Readers must scan past
  everything to find their task.
- **No task coverage for common problems.** There is no troubleshooting
  page, no glossary, no documentation index. The only entry points are the
  README (short) and MANUAL (everything).
- **`README.md` mixes audiences.** Evaluator content (what/why), user
  content (managing, updating), and reference fragments (uninstall
  details) all live on one page.
- **Duplicated content drifts.** The README repeats install/update/uninstall
  commands from MANUAL; AGENTS.md summarizes the security model a third
  time. Three places to update on every change — the "stay up-to-date"
  rule (docs as code) is already violated today.

## 2. Research summary

Sources (full notes: `local/research/2026-08-17-docs-research.md`):

| Source | Key takeaway applied here |
|---|---|
| T3DD26 talk „What do we need documentation for?" (Sandra Erbel) + local notes | Topic-based writing: **Concept / Task / Reference**, one topic type per page. Start with a concept topic (why/for whom). New-user path: install → configure → verify. Scannability, active voice, easy language. Revision via reverse outlining + reading aloud. |
| [CNCF sandbox-doc-primer](https://contribute.cncf.io/techdocs/sandbox-doc-primer/) | Define **personas → goals → tasks** first; docs must be primarily *instructional*. Minimal required set: technical overview, getting-started guide, reference. |
| [Diátaxis](https://diataxis.fr/) (successor of the Divio system) | Four quadrants: **Tutorials / How-to guides / Reference / Explanation** (DITA task ≈ tutorial+how-to, DITA concept ≈ explanation). Don't mix types; site structure mirrors the quadrants. Apply pragmatically, iterate. |
| [opencode docs](https://opencode.ai/docs/) | Intro page as a pure tutorial flow (prerequisites → install → configure → first use). Task-oriented sidebar groups. |
| [ddev docs](https://docs.ddev.com) | Nav follows Getting Started / Usage / Configuration / Reference; platform differences as separate sections; requirements early and prominent. |

**Framework decision:** use **Diátaxis** (4 types) as the model, mapped onto
the DITA terms from the talk:

| Diátaxis | DITA (talk) | Kit directory |
|---|---|---|
| Tutorial | task (learning) | `docs/getting-started.md` |
| How-to guide | task (goal) | `docs/how-to/*.md` |
| Reference | reference | `docs/reference/*.md` |
| Explanation | concept | `docs/concepts/*.md` |

Pragmatic deviation: **`docs/troubleshooting.md` stays top-level** (symptom →
cause → fix). Troubleshooting is technically a how-to, but troubleshooters
scan for their symptom and must not navigate a quadrant first (ddev does the
same).

## 3. Personas and their goals

| Persona | Question they bring | Primary page |
|---|---|---|
| **Evaluator** | "Is this kit the right thing for my setup? What's the catch?" | `README.md` → `docs/concepts/security-model.md` |
| **New user** | "Get this running on my WSL2 box, safely, in 15 minutes" | `docs/getting-started.md` |
| **Daily developer / kit admin** | "Add a project, allow ddev, tweak denies, update the kit" | `docs/how-to/*.md` |
| **Troubleshooter** | "ddev start fails / wrapper warns / ports blocked" | `docs/troubleshooting.md` |
| **Contributor** | "How is this built, where are tests, how do I PR?" | `CONTRIBUTING.md`, `docs/design/*` |

New-user path (talk + CNCF): **install → configure → verify with a simple
task** — `getting-started.md` must end with a visible success (an opencode
session answering inside a registered project, optionally a `ddev start`
smoke test).

## 4. Target structure

```
README.md                      # landing page (Evaluator) — see §5
CONTRIBUTING.md                # NEW (small): dev workflow, tests, PR rules
docs/
  README.md                    # NEW: documentation index (all quadrants)
  getting-started.md           # NEW: tutorial (replaces MANUAL Quick Start)
  troubleshooting.md           # NEW: symptom → cause → fix
  concepts/                    # explanation (why it works this way)
    security-model.md          #   soft-only model, guarantees, residual gaps, /mnt/c
    wrapper.md                 #   wrapper walk-through + bypass guard + deny-all net
    sharing-group.md           #   opencode usergroup, setgid, ACLs, umask 002
    ddev-integration.md        #   ddev as opencode user, handover table, ports, mkcert, auth-ssh trade-off
  how-to/                      # goal-oriented recipes
    manage-projects.md         #   add / list / remove project dirs (+ manual equivalent)
    container-tools.md         #   opt a project into docker/ddev (the "Two States")
    switch-container-backend.md#   docker-rootless <-> podman-rootless
    customize-deny-list.md     #   global + per-project rules, tripwires, leak scan scope
    secure-git-config.md       #   git-config on/off/status + when to enable
    update.md                  #   update kit + opencode binary (--binary, --binary-path)
    migrate-from-hard-acl.md   #   legacy migration story (DDEV-WORKING)
    uninstall.md               #   uninstall + what stays behind
  reference/                   # lookup
    cli.md                     #   every script + flag (install/config/update/status/uninstall)
    files.md                   #   file overview tables + install.conf keys
    audit-log.md               #   location, modes, events, rotation
    glossary.md                #   kit, wrapper, rootless, soft deny, sharing group, handover, tripwire, ...
  design/                      # unchanged: internal design records (DDEV-WORKING, UX-IMPROVEMENT, ...)
  security/                    # unchanged: PROOF-1..3 records
```

Rules:

- **One page = one topic type**, declared in the page's first line
  ("This page explains …" / "This guide shows how to …").
- Pages link to each other instead of duplicating (how-to pages link to
  concepts for the why; concepts never contain install steps).
- `docs/design/` and `docs/security/` stay as they are — internal records,
  linked from `CONTRIBUTING.md`, not part of the user quadrants.
- No static-site generator for now (no npm dependency, GitHub rendering is
  enough — see §9). The structure above maps 1:1 onto a later MkDocs/
  Starlight nav if we ever want one.

### Content migration map (MANUAL.md → new pages)

| MANUAL section | New home |
|---|---|
| What It Does | `README.md` (short) + `concepts/security-model.md` (full) |
| Security Model (soft-only) | `concepts/security-model.md` |
| The Two States | `how-to/container-tools.md` (steps) + `concepts/ddev-integration.md` (why) |
| Quick Start | `getting-started.md` (Standard mode focus) |
| Managing Project Directories | `how-to/manage-projects.md` |
| The Sharing Group | `concepts/sharing-group.md` |
| How the Wrapper Works | `concepts/wrapper.md` |
| Container Tools (docker/ddev) | `how-to/container-tools.md` + `how-to/switch-container-backend.md` + `concepts/ddev-integration.md` |
| CONTAINER_BACKEND keys | `reference/files.md` |
| Customizing the Deny List | `how-to/customize-deny-list.md` |
| Self-Update Bypass Protection | `concepts/wrapper.md` |
| Wrapper-Bypass Guard | `concepts/wrapper.md` |
| Project-Specific Config | `how-to/customize-deny-list.md` |
| .git/config Hardening | `how-to/secure-git-config.md` |
| Migration from a hard-ACL install | `how-to/migrate-from-hard-acl.md` |
| Verification | `getting-started.md` (verify step) + `reference/cli.md` |
| Development Tests | `CONTRIBUTING.md` |
| Management Scripts | `reference/cli.md` |
| Audit Log | `reference/audit-log.md` |
| Updating the Kit / binary | `how-to/update.md` |
| Uninstalling | `how-to/uninstall.md` |
| File Overview | `reference/files.md` |

`MANUAL.md` is **deleted in the same PR** that lands the migration
(decision §9.1) — no stub phase. README/AGENTS.md links are updated in the
same PR as the migration.

## 5. Page blueprints

### README.md (Evaluator landing page)

Order: (1) name + one-sentence purpose + alpha warning, (2) what it does —
3 bullets (UID separation, rootless backend, soft permissions), (3) who it's
for + who not (WSL2/Linux dev with ddev; not macOS, not CI), (4) quick-start
one-liner → link `getting-started.md`, (5) how it works — 3-bullet summary +
link `concepts/security-model.md`, (6) requirements table, (7) docs links
(index), (8) license/disclaimer. **No managing/update/uninstall details** —
those live in how-to pages.

### docs/README.md (index)

Four groups (Getting started / Concepts / How-to / Reference) with a
one-line description per page — the GitHub-markdown equivalent of the talk's
"overview card grid". First line explains who the docs are for.

### getting-started.md (tutorial)

Linear, no choices: prerequisites → one-liner install (Standard mode) →
what the installer asked → restart terminal (command-hash pitfall) → first
opencode session (the visible success) → optional ddev smoke test → next
steps (links). Advanced mode/flags: one paragraph + link to
`reference/cli.md`. Beginners get full steps (CNCF: "don't worry about
giving too much information").

### troubleshooting.md

Entries as `## Symptom:` headings (scannable), each: cause → fix → deeper
link. Seed content: wrapper bypass warning, old binary in PATH
(`hash -r`), first `ddev start` slow, ports <1024 refused (sysctl), EPERM on
settings dirs (handover), `docker ps` shows "wrong" daemon (expected),
`/mnt/c` world-readable warning, group changes need fresh login.

### glossary.md

Short entries, links to concept pages: wrapper, rootless backend, soft
deny, tripwire, sharing group, handover, deny-all config, leak scan, leak
of terms from scripts' output. Abbreviations expanded on first use per page
anyway (style rule).

## 6. Style rules (from the talk, binding for all new pages)

1. American English, active voice, direct address ("Run …", not "The
   settings should be configured").
2. **Important things first** — per page and per section; one-line purpose
   statement at the top.
3. Scannable: `##` headings as question-or-task phrases, tables for
   lookups, code blocks copy-pasteable (with the `sudo` prefix where
   needed).
4. Abbreviations expanded at first use per page (UID, ACL, TUI, CA …).
5. Logical order: general → specific within concepts.
6. Kit terms consistently spelled as in `reference/glossary.md`.
7. Every command shown in docs must actually work (one-liner, config.sh
   invocations — the e2e suite already exercises the install one-liner).
8. Docs change with the code: a PR that changes user-facing behavior
   updates the affected page in the same PR (AGENTS.md rule, extended from
   "update MANUAL.md" to the new structure).

## 7. Tooling & CI

- **Now:** plain Markdown on GitHub. `docs/README.md` as index; relative
  links only.
- **New CI check (optional, phase 4):** a small shell script
  `tests/test-docs.sh` that fails on broken relative links / dangling
  anchors inside `docs/` + README (no npm — pure grep/wget-less parsing).
  Add to `test.yml` next to the existing unit tests.
- **Explicitly out of scope:** MkDocs/Starlight site, i18n, versioned docs.
  Revisit when the kit leaves alpha (see `local/TODO.md` release question).

## 8. Phases (one issue + PR each)

Tracking issues (created 2026-08-17): phase 1 = #5, phase 2 = #6,
phase 3 = #7, phase 4 = #8. PR bodies use `Closes #N`.

| Phase | Content | Done when |
|---|---|---|
| **0** | ~~Decisions~~ (done, §9) — ~~create GitHub issues~~ (done: #5–#8) | ✓ |
| **1** | Skeleton: `docs/` subdirs, `docs/README.md` index, `CONTRIBUTING.md` (thin), README rewrite (Evaluator focus), AGENTS.md split (`repo/AGENTS.md` versioned + thin workspace pointer, see §9.5). MANUAL untouched | README ships no how-to details; index lists planned pages; `repo/AGENTS.md` in git |
| **2** | Tutorials + how-tos: `getting-started.md`, all `how-to/*` (content from MANUAL, restructured, split by task) | Every MANUAL task section has a new home; commands verified by hand |
| **3** | Concepts + reference: `concepts/*`, `reference/*` (incl. glossary) from MANUAL + AGENTS.md knowledge; **then delete `MANUAL.md`** + fix all links | No content left unmapped in §4 table; `MANUAL.md` gone, no dangling links |
| **4** | `troubleshooting.md` (seed from e2e failures + real support), `tests/test-docs.sh` link check, reverse-outlining + read-aloud revision pass over all new pages | Link check green in CI; revision pass done |

## 9. Decisions (2026-08-17)

1. **MANUAL.md: delete immediately.** No stub — the same PR that lands the
   last migrated content (phase 3) deletes the file and fixes all links.
   Old external links will 404; acceptable for an alpha project.
2. **CONTRIBUTING.md: thin version in phase 1.** Dev workflow (feature
   branches, PR + CI green), `make test` / `check-version` / `e2e`
   (including the "never rely on repo mode bits" rule), executable-bit CI
   note, links into `docs/design/`. Grows later if contributor interest
   appears.
3. **troubleshooting.md: top-level** in `docs/` (next to
   `getting-started.md`). Symptom-first scanning beats quadrant purity
   (same call as ddev docs).
4. **App-type handover table: lives in `concepts/ddev-integration.md`.**
   The table documents *why* the handover exists (the EPERM fixes), which
   is explanation; `reference/files.md` links to it instead of copying.
5. **AGENTS.md rule: rewritten in the same PR as the migration** — plus the
   AGENTS.md split itself (own decision, from `local/TODO.md` "Zusatz
   Task"):
   - `repo/AGENTS.md` **goes into git** (English, repo-relevant rules only:
     branch/PR rules, testing, executable bits, docs rule → new `docs/`
     paths, no VERSION bump without the developer). Committing AGENTS.md is
     the officially recommended pattern (opencode docs: "You should commit
     your project's AGENTS.md file to Git"); anyone cloning the repo gets
     it auto-loaded as their project root rules.
   - The **workspace-root AGENTS.md stays** (not in git) as the internal
     file: workspace layout (`repo/` vs `local/` + warning), dev-workspace
     specifics (docker/ddev grant, `logs/`, e2e how-to), and a pointer
     "read and follow `repo/AGENTS.md` before working in `repo/`".
   - **Why a pointer, not auto-discovery:** opencode loads AGENTS.md by
     traversing **up** from the cwd — a session started at the workspace
     root does not auto-load `repo/AGENTS.md` (it is *below* the cwd). The
     explicit pointer instruction in the root file fixes that (opencode
     docs document this "manual instructions" pattern). Belt-and-suspenders:
     the workspace-level `opencode.jsonc` additionally lists
     `"instructions": ["repo/AGENTS.md"]` (opencode's recommended way to
     include extra rule files).
   - **No symlink:** the workspace file must keep internal-only content
     (local/, dev grants) that must not ship in the repo, so the two files
     cannot be one file.
6. **Index: `docs/README.md`** — GitHub renders it automatically when
   opening the `docs/` directory.

## 10. Quality gates (definition of done for the epic)

- [ ] Every page has exactly one topic type + a first-line purpose statement.
- [ ] Each persona's primary question (§3) is answerable in ≤ 3 clicks from
      the repo root.
- [ ] No duplicated install/update/uninstall command blocks across pages
      (single source, linked).
- [ ] All internal links + anchors valid (`tests/test-docs.sh` in CI).
- [ ] Reverse outlining pass done per page (headings alone must read as a
      sensible table of contents).
- [ ] Read-aloud pass done on getting-started + security-model.
- [ ] README contains no content that belongs to how-to/reference pages.
- [ ] AGENTS.md split done: `repo/AGENTS.md` in git with the new docs
      paths, workspace root file is a thin pointer + internal notes.
- [ ] MANUAL.md deleted; no page links to it anymore (link check proves it).
