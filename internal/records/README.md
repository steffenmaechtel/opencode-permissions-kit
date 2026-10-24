# records/ — design + decision records

Frozen-after-implementation records documenting why the kit is built the
way it is. Where wording differs from the code, the code wins. Status
vocabulary: `implemented` (landed as described), `living` (a
still-current reference, not history), `superseded` (kept only in the
archive).

| Record | Topic | Status |
|---|---|---|
| [ddev-working.md](ddev-working.md) | soft-only model origin: ACL denies dropped, ddev keeps working | IMPLEMENTED |
| [streamline.md](streamline.md) | file/folder taxonomy; extension = usage; repo mirrors deployed lib | IMPLEMENTED |
| [ddev-dev-owned-projects.md](ddev-dev-owned-projects.md) | permanently group-writable projects for dev-owned trees | IMPLEMENTED |
| [ddev-e2e-test.md](ddev-e2e-test.md) | the real-ddev e2e suite with a cached golden container | IMPLEMENTED |
| [ddev-migration.md](ddev-migration.md) | database bridge for the daemon switch at install time | IMPLEMENTED |
| [ddev-url-transports.md](ddev-url-transports.md) | how browser commands get their URL to the Windows side | IMPLEMENTED |
| [ddev-workflow-improvements.md](ddev-workflow-improvements.md) | issue #149 workflow audit: replay method, findings, fixes | IMPLEMENTED |
| [handover-scan-skip.md](handover-scan-skip.md) | fast `opk update` on large trees (scan-skip stamps) | CURRENT |
| [openchamber-2x-hardening.md](openchamber-2x-hardening.md) | OpenChamber 2.x settings-pin bypass + policy-pin fix | CURRENT |
| [root-ancestor-traversal.md](root-ancestor-traversal.md) | root ancestor traversal + versioned no-bind-mounts | IMPLEMENTED |
| [wsl-conf-consent.md](wsl-conf-consent.md) | the kit never writes /etc/wsl.conf implicitly — scope | CURRENT |
| [restructure-docs.md](restructure-docs.md) | docs restructure: two-world split, birth-PR review cases | IMPLEMENTED |
| [rootless-backend.md](rootless-backend.md) | rootless backends: provisioning + selection reference | CURRENT |
| [opencode-2x.md](opencode-2x.md) | opencode 2.x compatibility: model, detection, open items | CURRENT |
| [security-advisories.md](security-advisories.md) | advisory warnings: database, upstream watch, curation | CURRENT |
| [review-independence.md](review-independence.md) | redundancy context: external reviewer checkout | CURRENT |
| [rules-meta.md](rules-meta.md) | rule-rationale system: metas, revisit ladder, audit invariants | CURRENT |
| [review-calibration.md](review-calibration.md) | review-process history: calibration + incident evidence | CURRENT |

Superseded and purely historical records live in
[_archive/](_archive/) — `design/` (pre-streamline records),
`security/` (the three proof write-ups), and `evaluations/` (third-party
tool assessments from issues #40/#41: verdicts that mattered flowed
into the records above; the rest is kept as an information collection).
