# wsl.conf consent — the kit never writes /etc/wsl.conf implicitly

> Status: **CURRENT.** Decided after
> [issue #100](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/100)
> (kit 0.0.36 wrote an invalid section into `/etc/wsl.conf` and, on WSL
> ≤ 2.9.12, silently disabled *every* WSL setting in the file). Branch:
> `feature/wsl-conf-user-consent`.

## 1. Problem

Two kit features used to write into `/etc/wsl.conf` during
install/update:

- the `[automount]` /mnt/c hardening (install.sh, after a yes/no prompt),
- the browser-bridge carrier that keeps opencode 1.x device logins alive
  on a hardened /mnt/c (install.sh/update.sh, no prompt at all).

`/etc/wsl.conf` is user-owned system configuration with boot-time
effects on the whole distro. Issue #100 showed what an implicit write
costs when it goes wrong: WSL aborted parsing the file and the user's
own settings (systemd, automount restriction) silently stopped applying.
A yes/no prompt inside a long install flow is not informed consent for
that class of change — and there was no prompt at all for the carrier.

## 2. Decision

The kit **never writes `/etc/wsl.conf` on its own**. The only paths that
ever touch it:

1. **Explicit opt-in command:** `sudo opk wsl-add-opencode-1-fix` —
   deploys the browser-bridge stand-in tree and writes the kit comment
   block (pure comments, WSL-silent; see
   [security model](../concepts/security-model.md)). Called by the user,
   nothing else. status.sh and the wrapper advertise it whenever the
   mount is hardened but the carrier is missing.
2. **Printed snippets:** install.sh prints the ready-to-run
   `[automount]` hardening snippet (with the resolved uid/gid); applying
   it is the user's manual step, like the documented manual fix.
3. **Removal of kit-owned content only, with consent:** update.sh strips
   the broken legacy 0.0.36 section (regression cleanup — it restores the
   user's file to a WSL-parseable state; never writes anything).
   `opk uninstall` asks before removing the kit comment block (or assumes
   yes with `--yes`); declining prints the exact line range so the user
   can delete it by hand — after uninstall there is no `opk` left to do
   it for them. Neither path ever writes kit content into the file.

An existing carrier (written by earlier kit versions or the opt-in
command) is deliberately left untouched by updates — removing it would
break working device logins. `AGENTS.md` carries this as a repo rule for
future features: user-owned system config is only ever changed through
opt-in commands or printed instructions.

## 3. Consequences

- Fresh installs land with `opk status` showing the bridge as
  stand-in-only until the user opts in — one explicit command, and the
  wrapper/status explain exactly when it is needed (hardened /mnt/c,
  opencode 1.x). opencode 2.x never needs it (its `open` access-checks
  powershell and falls back to xdg-open).
- The /mnt/c hardening UX loses one prompt and gains a printed snippet —
  the wrapper already repeats the snippet on every start until applied.
- Uninstall behavior: the stand-in tree always goes; the kit block is
  removed only after an explicit yes (or `--yes`), otherwise the exact
  lines to delete are printed. User content never goes.
