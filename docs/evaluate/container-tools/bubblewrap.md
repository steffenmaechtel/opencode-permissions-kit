# Evaluate: bubblewrap

> Evaluated: 2026-08-24 · Issue
> [#40](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/40)
> · Verdict: **Conflicting with the model**
> · Source: <https://github.com/containers/bubblewrap> (README/docs; v0.11.x era)

## What it is

Low-level unprivileged sandbox launcher (the backbone of Flatpak).
Composes isolation from namespaces: always a new **mount namespace**
with a tmpfs root you populate via **bind mounts** (ro/rw), optionally
unprivileged **user namespaces** (CLONE_NEWUSER), PID/IPC/NET/UTS
namespaces, **seccomp** filters, and `PR_SET_NO_NEW_PRIVS`. It is
deliberately not a ready-made sandbox — "Sandbox security … is entirely
determined by the arguments": the policy is your argv.

## Requirements

- Per-process launcher (`bwrap --ro-bind … cmd`); nothing persistent.
- Unprivileged user namespaces in the kernel. **Setuid mode is
  deprecated and being removed** (0.11.2, Apr 2026, CVE-2026-41163).
- Ubuntu 24.04+ needs the AppArmor `bwrap-userns-restrict` fix or
  `kernel.apparmor_restrict_unprivileged_userns=0`. WSL2: unprivileged
  userns generally works; AppArmor typically not enforced.

## Maturity

~8.5k stars, maintained by Flatpak/Red Hat developers, active releases
(0.9.0 → 0.11.2). Very mature — as a *building block*.

## Fit with the kit

- **Would add:** true OS-level denies — read-only rootfs, hidden paths
  (`--ro-bind` only what the agent may see), seccomp.
- **What breaks:** ddev containers bind-mount project files **from the
  rootless daemon's mount view** — files visible only inside a bwrap
  mount namespace are invisible to the daemon outside it, so the ddev
  handover breaks. Keeping ddev working means rw-binding the project,
  the rootless `DOCKER_HOST` socket, `~/.ddev`/`~/.docker`, and
  near-open networking — which guts the deny surface.
- **History:** explored pre-0.0.11 (`local/IDEA-BUBBLEWRAP+DDEV.md`,
  workspace-internal) and set aside when the kit moved to the soft-only
  model — this evaluation confirms that outcome.

## Verdict

**Conflicting.** The confinement boundary (bwrap mount namespace) and
the ddev-shared-filesystem requirement are mutually exclusive at the
same host. Revisit only if the kit ever offers a non-ddev hard-mode
profile for untrusted one-off work.
