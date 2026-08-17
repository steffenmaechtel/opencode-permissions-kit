# Project History Summary

How the kit evolved — problem → decision. Short overview; details live in
the linked design docs and commit history.

## Milestones

| Version / Era | Problem (Issue) | Decision (Way) |
|---|---|---|
| Start (pre-0.0.8) | opencode's permissions are **soft** (config-level); the agent's bash could still read denied files | Mirror the deny rules into **hard** Linux ACL denies (`u:opencode:---`) — the kit began as an ACL enforcement layer |
| ≤ 0.0.8 | Distribution as an **opencode plugin** via npmjs.org | Plugin + npm install flow (`/permission-setup` command, later npm bin commands, then plugin-only). Plugin hooks were fragile (v1 hook API churn) and npm added an install step the target audience wouldn't do |
| 0.0.9 | Plugin distribution didn't reach system-level concerns (users, sudoers, ACLs need root anyway) | **Drop plugin/npm entirely** — one-liner install (`curl \| sudo bash`), self-fetching scripts from the branch. System-level only, no plugin, no npm package, no tags |
| 0.0.10 | Layout clarity; kit dirs named `opencode` collided with opencode's own | Rename to `opencode-permissions-kit` everywhere (`/usr/local/lib/…`, `/etc/…`, sudoers, umask profile) with legacy fallback + migration. Still **root docker** via docker-group |
| 0.0.10 → 0.0.11 | Root docker socket = **root-equivalent** for the agent (security analyses PROOF-1..3); ddev could not read `settings.php` etc. under hard ACL denies (app breaks) | Two-step: `feature/ddev-sandbox` (transactional ddev as opencode user — abandoned, see below), then **DDEV-WORKING**: soft-only model. Hard ACL denies removed; UID separation + **rootless container backend** (mandatory) as the hard guarantee; ddev always runs as the `opencode` user |
| 0.0.11 | — (release of the above) | Rootless-only, opencode usergroup as sharing group, ddev-as-opencode, wrapper bypass guards, audit log, WSL2 `/mnt/c` exposure warnings |
| 0.0.12 | CLI output was plain/unprofessional; install asked too many questions in the wrong order | **UX overhaul**: shared UI library (`ui.sh`), Standard/Advanced install mode with pre-flight inventory + plan + confirm, restyled status/update/config |
| 0.0.13 | Live-testing 0.0.12 revealed: git choice ignored on re-install, inverted SECURE_GIT mapping, plan numbering gaps, installer probe broke on the wrapper, binary re-download on re-install | Re-install correctness fixes + wrapper `--version` passthrough + binary reuse, all with regression tests |

## Retired / backup branches

| Branch | What it tried | Why it was abandoned |
|---|---|---|
| `feature/different-plugin-integration` | Alternative plugin hook integration (v1 `config/event/command.execute.before`) | Superseded by dropping the plugin entirely (0.0.9) |
| `feature/ddev-sandbox` (after 0.0.10, before 0.0.11) | Transactional "sandbox" ddev: developer's `ddev` delegates to a root-side shim running ddev as opencode (PROOF-3 H3) | Burn-in 2026-08-14: ddev chmods `.ddev` + app settings dirs unconditionally and chmod is owner-only → **EPERM** for files the app needs to run (e.g. TYPO3 `settings.php` "Permission denied" in the web container; `ddev describe` red for the developer driver) → replaced by the simpler DDEV-WORKING model: ddev runs **natively** as the opencode user, `.ddev` + settings dirs handed over |
| `feature/docker-rootless` | Rootless backend phases 1–2 + e2e suites | Merged — became the 0.0.11 backend |
| `feature/remove-hard-file-protection` | The soft-only migration itself (DDEV-WORKING phases) | Merged — became 0.0.11's permission model |

## Key model changes at a glance

| Topic | Before (≤ 0.0.10) | Since 0.0.11 |
|---|---|---|
| File permissions | Hard ACL denies (`u:opencode:---`) mirrored from opencode.jsonc | Soft-only: opencode's own permission layer; no OS backstop |
| Container backend | docker-group (root-equivalent socket) | Rootless only (docker-rootless / podman-rootless), mandatory |
| ddev | Delegating shim + transactions | Native as the `opencode` user (sudoers helper + shell function) |
| Hard guarantee | ACLs (broken by ddev's needs) | UID separation + user-owned rootless backend + zero RunAs-dev sudoers |
| Distribution | npm plugin | One-liner install from the branch, self-fetching |
