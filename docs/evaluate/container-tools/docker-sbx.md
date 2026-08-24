# Evaluate: Docker `sbx` (Docker Sandboxes)

> Evaluated: 2026-08-24 · Issue
> [#40](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/40)
> · Verdict: **Not applicable (alternative model — replaces the kit
> rather than hardening it)**
> · Source: <https://docs.docker.com/reference/cli/sbx/> and
> `docker/sandbox-templates:opencode` (CLI ~0.39.x era)

## What it is

Docker's sandbox CLI: each sandbox is a **local microVM** (KVM on Linux
/ Windows Hypervisor Platform / Apple Virtualization) with its **own
isolated Docker daemon**, filesystem, and network. Outbound TCP is
forced through a host-side proxy enforcing network policies +
credential injection. Local VMs, not Docker's cloud — but a mandatory
`sbx login` (free Docker account) and outbound access to Docker
infrastructure are required. CLI is free incl. commercial use; only org
governance is paid. Closed-source CLI (`docker/sbx-releases`), young
and rapidly evolving.

## opencode support

First-class: `sbx create opencode` /
[docker/sandbox-templates:opencode](https://docs.docker.com/reference/cli/sbx/create/opencode/),
TUI works, `sbx secret set` for provider credentials. Agents run with
approval prompts skipped — "the sandbox itself is the safety boundary".

- **Files in/out:** default live passthrough bind mount (virtiofs) at
  the same absolute path; alternative `--clone` mode does a private git
  clone with commits flowing back via a `sandbox-<name>` remote; plus
  `sbx cp` for ad-hoc copies.
- **Nested containers:** each sandbox has its own Docker daemon, so
  ddev could in principle run inside — against a *different* daemon
  than anything on the host.

## Requirements / WSL2

Standalone CLI (no Docker Desktop/Engine needed). Linux: Ubuntu 24.04+,
**KVM required** (`kvm` group). **WSL2 hard blocker:** no `/dev/kvm` by
default — needs Windows 11 + `nestedVirtualization=true` in
`.wslconfig`, which is flaky; the FAQ also calls out WSL keyring gaps.

## Fit with the kit

- **Would add:** full hypervisor isolation — stronger than UID
  separation.
- **Why it does not fit:** it substitutes the kit's whole stack
  (UID separation + rootless backend + soft config). User-level
  opencode config is not imported into the sandbox (project-level
  only), so the kit's global `opencode.jsonc` policy would not apply
  inside; ddev would run against the VM-internal daemon, decoupled from
  the developer's setup; and the WSL2 KVM blocker hits the kit's
  primary platform.

## Verdict

**Not applicable** for enhancing the kit — a separate
disposable-agent track, not a hardening of this one. Revisit if the
kit ever grows an "untrusted task" mode on machines with KVM.
