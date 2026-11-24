# Removing the project-root/ancestor sticky — the measured trade

> Status: **IMPLEMENTED** (#703 wave, PR #706; decision record and full
> measurement artifacts: issue #702). Measured 2026-11-20 on a
> kit-managed host (Ubuntu/WSL2, kernel 6.6.87.2-microsoft-standard-WSL2,
> ext4, dev uid 1000 / agent uid 1001, group `opencode`). This record is
> the durable in-repo summary of why the #655-era root/ancestor stickies
> came back out; the harness, the four run logs and the option research
> live in the #702 timeline.

## 1. The question

The `.git` heal (#651, PR #655) set sticky bits on `.git` AND its
metadata containers AND the project root AND every `.git` ancestor
directory. The root/ancestor bits blocked the wholesale arms — `mv .git
.git.old && mkdir .git` renames a TOP-LEVEL entry, gated only by the
parent's sticky — but bred everyday failure classes on every honest
workflow:

- #699: under `fs.protected_regular=2` (Ubuntu default) the developer
  cannot append/edit agent-owned top-level files (editors, `>>`,
  `sed -i`) — systematic, because the sanctioned agent-commits workflow
  drifts top-level files to agent ownership
- #701: agent tooling (`make sums`) died on the rename-over of the
  dev-owned manifest AND failed open
- #682: agent `git checkout`/switch over dev-owned top-level files →
  EPERM or rc-0 stale-dirty (undiscardable modifications)
- #697-class handback friction

Decision question: keep the sticky (and force the sysctl down to 1), or
drop it (and reopen the wholesale arms under the default 2)? Measured,
not estimated — then decided: **drop the root/ancestor sticky, keep the
`.git`-internal heal, ship under `fs.protected_regular=2`**.

## 2. The two mechanisms (they are different classes)

**O_CREAT class** — `may_create_in_sticky()` (fs/namei.c), active under
`fs.protected_regular=2` on sticky group-writable dirs: an `O_CREAT` open
of an EXISTING regular file is refused (EACCES) unless

- file-owner == dir-owner (exempts ANY opener — why the agent can always
  `>>` dev-owned top files in dev-owned roots), or
- file-owner == opener.

No capability bypass — root is subject too. `=1` gates only
world-writable dirs, so it never bites the kit's group-writable roots.

**Rename/unlink class** — POSIX sticky, independent of any sysctl: an
entry may be renamed/unlinked only by its owner, the directory owner, or
CAP_FOWNER. This is the class the `.git`-internal heal keeps using (and
the class the root sticky used against `mv .git`).

POSIX offers NO per-entry rename protection — sticky is per-directory.
The only per-entry "nails" are system mechanisms: a mountpoint (rename →
EBUSY), the immutable flag (`chattr +i` — but on a directory it also
blocks writes INSIDE, so it kills a live `.git`), or an LSM/BPF policy.

## 3. The measurement series (issue #702 artifacts)

Self-contained harness, run as the dev, agent arms via `sudo -u opencode`,
fresh fixture per state under /tmp scratch: a dev-owned and an
agent-owned project top (real git, shared bare origin), the `.git` heal
state always on (sticky `.git`, dev-owned `config`/`hooks` pins,
agent-owned `index`/`HEAD`), a read/write matrix over actor × file-owner
× dir-owner (`cat`, `>>`, `sed -i`, editor-sim `cp`+`mv -f`, `rm`,
create+delete), a git battery (both actors add/commit, #671 lockout vs
healed, #682 checkout/switch classes, cross-clone fetch+merge), `.git`
protection arms, the wholesale `mv .git` arm, and a leg exercising the
REAL worktree form (agent `worktree add` in the dev-owned main repo).
Expectations were DERIVED from the §2 rules, so every run also verifies
the rules themselves. Final run: **320 PASS / 0 UNEXPECTED**.

| state | RW both sides | git base | `.git` protections | worktree leg |
|---|---|---|---|---|
| `=1` sticky on | rule-conform (2 exempt cells) | ok | blocked | ok |
| `=2` sticky on | rule-conform (#699 cells DO block) | ok | blocked | ok |
| `=1` sticky off | all green | ok | blocked | ok |
| `=2` sticky off | all green | ok | blocked | ok |

Exactly two of 32 append cells block under `=2`+sticky (dev→agent file
in dev dir; agent→dev file in agent dir) — the #699 lockout and its
mirror, and nothing else. The `=2`+no-sticky row is the release gate:
the default sysctl is fully workable once the root sticky is gone.

## 4. Findings beyond the matrix (all rule-conform, all PASS)

1. **#682 reproduced 1:1**: `git switch` does NOT abort on unlink EPERM —
   it completes rc 0, leaves the affected files at old content
   (stale-dirty), and the switch BACK then fails on "local changes would
   be overwritten". Modeled as the expected g6/g6b arm pair.
2. **Rename-bypass of the pins in agent-owned gitdirs**: when the agent
   owns the `.git` directory (agent clones; gitdirs under
   `.git/worktrees/`), the dev-owned `config`/`hooks` pins survive
   direct writes but NOT renames — the directory owner may rename
   foreign entries despite sticky. The pins are hard only in dev-owned
   gitdirs (#652 residual family, now measured).
3. **Dev lockout in agent-owned repos**: with the `.git` sticky always on
   and agent-owned operands, DEV git operations in agent-owned repos
   fail in every state — the #671 mirror. The real worktree form is
   friendlier: its gitdir is agent-owned but NOT sticky, so both actors
   commit fine inside it.
4. **The git-heal operand contract is load-bearing**: without re-pinning
   after dev operations, agent `add`/`merge`/`pull` break on
   `index`/`ORIG_HEAD` (#678 class); `FETCH_HEAD` is a transient variant
   whose mode (umask 022 vs 002) gates the other actor by plain DAC.

## 5. What shipped (#703 wave, PR #706)

- `fs-baseline.sh`: no sticky on scan root / ancestor chain; a baseline
  run STRIPS legacy bits as migration. `_ddev_heal_sticky` disarmed
  consistently. `.git` and everything inside keeps sticky + pins
  (verified protective in all four states).
- `fs.protected_regular=2` is the supported default; the `=1` hotfix
  guidance is obsolete (#700 closed as moot).
- Detection row (the #653 family): warn when a project's `.git` dir
  owner differs from the project root owner — the cheap wholesale-swap
  detector (see §6).

## 6. The reopened surface, compensations, dead ends

Reopened (documented residuals, security-model.md): **W1** the stealth
`.git` swap (`cp -a .git .git.new`, plant fsmonitor/hooks in the copy,
swap — repo keeps working, dev's next `git status` executes as the
developer: the #644 impact returns), **W2** project-dir swap at depth,
**W3** agent rename/unlink of dev-owned top-level entries (marginal over
the soft model's existing content overwrite; real loss surface is
dev-owned untracked files).

**Successor (implemented):** W1 is closed by the nailed-pointer layout —
[gitdir-pointer-protection.md](gitdir-pointer-protection.md) (status
IMPLEMENTED, PR #754; follow-ups #760/#761/#765). W2 (project-dir swap
at depth) stays out of scope. Shipped behavior:
[the how-to](../../docs/how-to/git-protection.md).

Compensations: the §5 detection row (catches W1/W2 after the fact — a
swap necessarily leaves an agent-owned `.git`); documented dead ends so
nobody "fixes" them that way — a global `core.hooksPath` does NOT defend
W1 (repo config overrides it), no `fs.protected_*` value gates renames,
`chattr +i` on the `.git` dir kills git, chattr `P` is XFS-only.

The only complete closure remains a separate agent-owned clone — the
upstream commenter's conclusion, unchanged, workflow change, out of
scope. Per-entry alternatives researched in #702: bind-mount pin
(EBUSY), pointer-file layout + `chattr +i` on the pointer + sticky
external gitdir storage (now the successor record above), BPF-LSM guard
(kernel supports it here but securityfs is not mounted on this WSL2
host — practically unverifiable).

## 7. Re-measure

The #702 timeline carries the harness verbatim (collapsible artifacts).
Minimal re-verification of a shipped state, agent-side on a real
kit-managed checkout:

```sh
ls -ld <root> <root>/<proj>          # no 't' in the mode column
ls -ld <root>/<proj>/.git            # 't' present (drwxrwsr-t)
touch <proj>/.git/hooks/probe        # → Permission denied
echo x >> <proj>/.git/config         # → Permission denied
mv <proj>/.git <proj>/.git.probe     # → succeeds: W1 open, known (§6)
```

and the everyday arms the sticky used to break — `make sums` with a
stale manifest, `git checkout -- <dev-owned top-level file>` — must be
green for BOTH actors under `=2`.
