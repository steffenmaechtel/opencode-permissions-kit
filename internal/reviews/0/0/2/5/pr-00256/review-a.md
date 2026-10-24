<!-- review-meta
ID: pr-00256
Snapshot: a
Subject: docs end-user optimization pass — all 21 user-docs pages shortened to snippet-first prose (issue #252)
Scope: wave
Base: 0.0.56 @ 716b8c0
Diff: 716b8c0..b69a336
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) — 3 fast-tier reviewer agents (GLM-5.3-Flash, axes S/C/X) + main-session verification
Skills: opk-review-pass
-->

# Review a — wave review of the docs end-user optimization pass (pr-00256)

Round a over the diff 716b8c0..b69a336 (1 commit: b69a336 "docs(all): end-user
optimization pass — shorten every page to snippet-first prose (#252)").
Material: **docs-only** — 21 pages under `docs/`, +990/−1869 lines (net −879);
no shipped code, tests, Makefile or workflows touched. Scope keyword **wave**
(USER commission: "Review Snapshot a über aktuelle branch", birth-PR #256).
Base 0.0.56; tree clean and committed at b69a336 throughout the pass.

**Result: 12 reported → 11 effective findings** (1 cross-axis duplicate,
S1 ≡ C1) — **2 MED, 5 LOW, 4 INFO**. No HIGH. One ghost sub-claim inside X5
was corrected during main-session verification (a `--yes` phrase attributed
to uninstall.md that never stood there — the underlying drop is real in
security-model.md and files.md; see Retracted/ghost findings). Every finding
was re-verified against the code by the main session before entering this
snapshot; no other reviewer claim failed verification. The axis-C reviewer's
notable clean results are recorded in its coverage section — among them one
stale claim the wave *fixed* (files.md's old `HARD_DENY_REMOVED` update-gate
text was the lie; the key has zero grep hits in `files/`).

## Findings index

| ID | Severity | One-liner | Provenance | Reported by |
|---|---|---|---|---|
| W1 | MED | ddev-integration renames the app type `shopware6` → `shopware` — a value in neither the kit code nor ddev's type vocabulary | wave-introduced | S1 + C1 (dup) |
| W2 | MED | dev-owned mode's accepted flag-write TOCTOU vanished from the residual-gaps list — the default mode's accepted race is no longer disclosed anywhere in docs | wave-introduced | X1 |
| W3 | LOW | cli.md asserts every missing-library row "names the file"; the advisories row names the consequence instead — the old text documented exactly this exception | wave-introduced | S2 |
| W4 | LOW | compatibility.md de-anchored the OpenChamber bypass link to the bare page although the target heading still exists | wave-introduced | S3 |
| W5 | LOW | getting-started drops the "menu Enter default is skip" caveat for agent resources — the installer default IS skip, the docs say "(recommended)" with no default note | wave-introduced | C2 |
| W6 | LOW | getting-started's 4-question installer list omits the conditional OpenChamber prompt (and the re-install reconfigure gate) — gap carried forward from the old page | pre-existing | C3 |
| W7 | LOW | /mnt/c install-time exposure disclosure dropped from getting-started — mitigated by `opk status` + the wrapper start warning | wave-introduced | X2 |
| W8 | INFO | `--openchamber-policy` default under `--yes` (pin stays off) no longer stated anywhere in the corpus | wave-introduced | S4 |
| W9 | INFO | security-model supply-chain entry dropped the liveness-check and checksum-manifest detail — core disclosure survives | wave-introduced | X3 |
| W10 | INFO | SSH-key trade-off dropped its mitigation sentence and "rotate if the machine is not trusted" | wave-introduced | X4 |
| W11 | INFO | pointer/history losses (record links, 0.0.36 recovery section, home-loss detail, status enumeration item, //SECURE_GIT block) — no safety-meaning change | wave-introduced | X5 |

## Verification log (main session)

Every finding re-verified against the tree at b69a336 before entering this
snapshot (RM-0074):

| # | Finding | Verified how | Verdict |
|---|---|---|---|
| 1 | W1 shopware rename | New docs/concepts/ddev-integration.md:108 says `shopware`; old :149 said `shopware6` (second old mention :187 removed entirely); shipped matchers ddev-terminal.sh:357+400 and ddev-handover.sh:466 all `codeigniter\|shopware6\|symfony`; e2e fixture type list agrees (`shopware6`, no bare `shopware`) | HOLDS |
| 2 | W2 TOCTOU disclosure dropped | `git grep -iE "TOCTOU\|flag-write" 716b8c0 -- docs/` → exactly ONE hit (old security-model.md:71-72, the residual-gap bullet); same grep at b69a336 → 0 hits; the handover half survives at new security-model.md:57; dev-owned is the default (getting-started.md:52) | HOLDS |
| 3 | W3 advisories blanket claim | status.sh:373 row text "missing — security checks skipped (fix: sudo opk update)" names the consequence; the five sibling rows DO name files (:353, :770, :845, :999, :1096); old cli.md:396-397 spelled the exception ("the advisories row names the skipped security checks instead") | HOLDS |
| 4 | W4 de-anchored link | Old compatibility.md:72 linked `../how-to/openchamber.md#prevent-the-bypass-the-policy-pin`; new :57 links the bare page; target heading exists (openchamber.md:52 "Prevent the bypass: the policy pin"; slug resolves, cli.md:14 still anchors it) | HOLDS |
| 5 | W5 Enter-default caveat dropped | install.sh:2295 `ui_menu … "s"` — Enter default is skip; new getting-started.md:55-56 lists "(recommended), copy, or skip" with no default note; old :96-98 named the default AND the move-removes-sources trade-off (both gone); cli.md:199 covers only the flag default ("--yes = move") | HOLDS |
| 6 | W6 prompt-list gap pre-existing | OpenChamber question exists (install.sh:1072-1077, asked whenever interactive + detected); old getting-started.md:68-70 had the same 4-item "essential questions" list without it | HOLDS, pre-existing as reported |
| 7 | W7 /mnt/c disclosure dropped | Old getting-started.md:114-116 (exposure never a prompt; kit only prints the snippet; never edits /etc/wsl.conf) → gone; new /mnt/c mentions only :88 (status enumeration); mitigation confirmed at security-model.md:87-90 ("reports the exposure in opk status and warns on every opencode start until fixed … the kit never edits that file itself") | HOLDS |
| 8 | W8 --yes default undocumented | Old openchamber.md:99-102 stated "under `--yes` without the flag the pin stays off"; code confirms that default was TRUE (install.sh:1081 `\|\| OPENCHAMBER_POLICY=no` after the keep-earlier-opt-in branch :1076); no successor statement anywhere (cli.md:179, files.md:63, openchamber.md:66 checked) | HOLDS |
| 9 | W9 supply-chain detail | Old security-model.md:94-101 (liveness check, pinned-release checksum manifest); new :71 keeps "over HTTPS without checksums or signatures" — core claim survives | HOLDS |
| 10 | W10 rotate clause dropped | Old ddev-integration.md:373 "rotatable deploy keys and rotate them if the machine is not trusted"; grep `rotate` over new docs/ → 0 hits; import-deny + trade-off framing survives (new :262-270) | HOLDS |
| 11 | W11 round-up, incl. ghost | Record links: old security-model.md:38+:127 → 0 in new; 0.0.36 recovery section: old troubleshooting.md:539-541 → 0 in new; "(ddev homes, imported keys)": old uninstall.md:67 → 0 in new; root-equivalent-access item: old getting-started.md:152 → new :88 lacks it; //SECURE_GIT block: old secure-git-config.md:47 → 0 in new; GHOST sub-claim: "(or assumes yes with `--yes`)" never stood in uninstall.md (old :50 = new :40, wsl ask intact) — real drops of that phrase: security-model.md:219, files.md:21; surviving: cli.md:45 + :217 | MIXED — sub-claim corrected (below), round-up itself holds, INFO stands |

## Retracted/ghost findings

- **X5 sub-claim ghost (corrected, not retracted as a finding):** the
  security reviewer attributed the dropped phrase "(or assumes yes with
  `--yes`)" to docs/how-to/uninstall.md. The phrase never stood in that file
  at base (the wsl-block ask with "default: yes" is byte-identical old :50 →
  new :40). The phrase did exist at base in security-model.md:219 and
  files.md:21 — both drops are real — and the behavior stays documented at
  cli.md:45 and :217. W11 keeps the corrected attribution; severity INFO
  unchanged (the `--yes` semantics remain documented on cli.md).
- **Cross-axis duplicate:** S1 (sweep) and C1 (claims) report the same
  shopware rename independently with consistent evidence; merged into W1,
  both originals preserved verbatim below.
- No finding was retracted as false; no unverifiable claim entered the
  index (all reviewer claims resolved within one follow-up read).

## Reviewer output — axis S (mechanical sweep), verbatim

# Mechanical sweep — wave 716b8c0..b69a336 (docs end-user optimization pass)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | MED | ddev-integration renames the app type `shopware6` to `shopware` — a value that exists in neither the kit code nor ddev's type vocabulary | wave-introduced |
| S2 | LOW | cli.md asserts every missing-kit-library row "names the file"; the advisories row names "security checks skipped" instead (status.sh:373) — the old text documented this exact exception, the new text contradicts it | wave-introduced |
| S3 | LOW | compatibility.md de-anchored the OpenChamber bypass link to the bare page although the target heading still exists | wave-introduced |
| S4 | INFO | The `--openchamber-policy` default under unattended installs ("stays off under `--yes` without the flag") is no longer stated anywhere in the docs | wave-introduced |

## Details

### S1 — MED: `shopware6` renamed to `shopware` in the root-file types list

`docs/concepts/ddev-integration.md:108`:

```
**Root-file types (`codeigniter`, `shopware`, `symfony`).** Their settings
```

The pre-wave text (`git show 716b8c0:docs/concepts/ddev-integration.md`) said `codeigniter`, `shopware6`, `symfony`. The table this paragraph belongs to is explicitly framed as "App type (`.ddev/config.yaml` `type:`)" values (ddev-integration.md:100). The shipped code matches `shopware6`, not `shopware`:

- `files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:357` and `:400` — `codeigniter|shopware6|symfony`
- `files/opencode-permissions-kit-lib/sh/ddev-handover.sh:466` — `codeigniter|shopware6|symfony`
- ddev's own type list (comment in `tests/e2e/fixtures/camino/site/.ddev/config.yaml:26`) carries `shopware6` and no plain `shopware`

Why it matters: a Shopware 6 user pattern-matching their committed `type: shopware6` against this docs list finds no match and cannot tell their project is a root-file type (permanent root-inode handover at mode `2755`). Realistic trigger: any Shopware project owner reading the page. The rename looks like a careless shortening (a config identifier silently changed), not a deliberate normalization. Docs-only — no code impact.

### S2 — LOW: "the row names the file" is wrong for the advisories family

`docs/reference/cli.md:303`:

```
library file (a damaged deploy — the row names the file and the repair hint
`fix: sudo opk update`).
```

`files/opencode-permissions-kit-lib/management/status.sh:373`:

```
    ui_kv_warn "advisories database" "missing — security checks skipped (fix: sudo opk update)"
```

Five of the six missing-library rows do name the file (`sh/git-check.sh`, `sh/ddev-terminal.sh`, `sh/ddev-handover.sh`, `sh/ddev-migrate.sh`, `sh/ddev-hosts.sh` — status.sh:353, 770, 845, 999, 1096), but the advisories row names the consequence ("security checks skipped"), not the file. The old cli.md documented exactly this: "the row names the missing kit file — the advisories row names the skipped security checks instead". The wave compressed the paragraph into a blanket claim that is false for one of the rows it covers. Severity LOW because the repair hint is still correct and only one sub-case is misdescribed; conditions: a damaged/partial deploy missing `sh/advisories.sh`, read by a user comparing the docs claim against the actual row.

### S3 — LOW: OpenChamber caveat link lost its working anchor

`docs/reference/compatibility.md:56-57`:

```
  the bypass with `opk openchamber-secure` — see
  [the how-to](../how-to/openchamber.md).
```

The pre-wave link was `../how-to/openchamber.md#prevent-the-bypass-the-policy-pin`. The target heading still exists on the post-change page (the identical fragment is linked from `docs/reference/cli.md:14` and resolves — verified by slug match against openchamber.md's heading "Prevent the bypass: the policy pin"). The link is not broken, but the reader lands on the page top instead of the recovery/policy-pin section this caveat points at. Every other cross-page anchor in the corpus was preserved; this is the one de-anchoring.

### S4 — INFO: undocumented default for `--openchamber-policy` under `--yes`

`docs/how-to/openchamber.md:66`:

```
  (asked when OpenChamber is detected; `--openchamber-policy yes|no` for
```

The old text continued "…— under `--yes` without the flag the pin stays off", i.e. it stated the default for unattended installs. That default is stated nowhere in the post-wave corpus: `docs/reference/cli.md:179` says only "Pre-decide the OpenChamber policy pin (non-interactive installs)". Not a contradiction — an operative default was dropped, so an unattended-install user cannot predict the pin state without testing. Severity INFO (precision loss only).

## Coverage

- **Section 1 (index):** docs/README.md lists all 20 content pages exactly once under correct topic headings; index heading slugs (`#concepts-why-it-works-this-way`, `#how-to-guides-solve-a-task`, `#reference-look-it-up`) match GitHub slug rules; outbound `../README.md`, `../agent/README.md`, `../internal/README.md` exist. Clean.
- **Section 2 (inbound links):** every `docs/…` reference from README.md, CONTRIBUTING.md, agent/, internal/, files/, .agents/ resolves; both `docs/how-to/update.md#channels` sites (README.md:38, CONTRIBUTING.md:165) resolve to update.md:5 `## Channels`; all internal/records links are fragment-less to existing pages. Clean.
- **Section 3 (internal links):** scripted GitHub-slug resolver over all 21 pages — all relative targets and fragments resolve, including self-page fragments (`#supported-distros`, `#openchamber-2x-requires-opencode-2020`, `#server-working-directory`, `#projectless-chats`, `#headless-invocations-serve-run-queries`, `#mode-display-in-the-tui`, `#the-ssh-key-trade-off`, `#known-residual-gaps`, `#prevent-the-bypass-the-policy-pin`, `#caveats` was removed with the de-anchoring in S3). Clean.
- **Section 4 (shortening artifacts):** all 21 per-page diffs read; no empty sections, no duplicate headings, no half-removed lists, no dangling "see above/below" (the three candidates — files.md:22, security-model.md:9, cli.md:67 — all have live targets). The new update.md major-crossing claim was verified against update.sh:505-506/532/540 (accurate). The `sudo env KIT_BRANCH=0.0.29 opk update` line inside the KIT_BRANCH curl block (update.md:38) looked like a misplacement but is pre-existing and intentional (block intro covers both entry points) — not flagged. Clean apart from S1–S4.
- **Section 5 (markdown hygiene):** single H1 per page, no skipped heading levels, all 82 fences language-tagged, all tables well-formed, glossary has no inbound fragment links to break. Clean.
- **Deferred/unverified:** none. Two diff-level claim compressions were checked against code and found consistent rather than contradictory, so not flagged: the status.sh exit-code paragraph now omits the opencode-version-verdict nuance (old text's "affected version counts as an alert at any privilege [where the caller can exec the binary]" remains true under the new wording — non-contradicting omission), and the binary "unexecutable" verdict remains audience/mode-bit based. Both are precision losses consistent with the wave's stated purpose, not mechanical errors.

## Reviewer output — axis C (quality: docs that lie), verbatim

# Claims-axis review — wave 716b8c0..b69a336 (docs-only end-user optimization, base 0.0.56)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| C1 | MED | ddev-integration.md renames the app type `shopware6` to `shopware`; the code and ddev's `type:` value are `shopware6` | wave-introduced |
| C2 | LOW | getting-started.md drops the "menu Enter default is skip" caveat for the agent-resources prompt; the installer's Enter default is skip | wave-introduced |
| C3 | LOW | getting-started's "then asks" 4-question list omits the conditional OpenChamber install prompt (and the re-install reconfigure prompt) | pre-existing |

## Details

### C1 — MED — `shopware6` renamed to `shopware` in the root-file types

**Evidence** — `docs/concepts/ddev-integration.md:108`:

> **Root-file types (`codeigniter`, `shopware`, `symfony`).** Their settings file lives at the project root …

vs. the shipped matcher, `files/opencode-permissions-kit-lib/sh/ddev-handover.sh:466`:

```sh
        codeigniter|shopware6|symfony)
```

and the old page, `716b8c0:docs/concepts/ddev-integration.md:149`:

> **Root-file types (`codeigniter`, `shopware6`, `symfony`).** …

**Why it matters:** the docs use the exact `type:` string from `.ddev/config.yaml` as the join key — ddev's app type is `shopware6`; a bare `shopware` type does not exist in ddev. A Shopware user matching their project's `type:` line against this table finds nothing, and cannot tell that their root-directory handover (root inode to `opencode`, mode 2755) is expected behavior. Exact-spelling drift on a config value, introduced by the rewrite (old page was correct).

### C2 — LOW — dropped caveat: agent-resources menu Enter default is skip, not the recommended move

**Evidence** — new `docs/getting-started.md:55-56`:

> 4. **Agent resources** (only when `~/.agents` or `~/.claude/skills` exist) —
>    move them into `/home/opencode` (recommended), copy, or skip.

vs. the code, `files/install.sh:2295-2298`:

```sh
_opk_ag=$(ui_menu "Bring the developer's agent resources over?" "s" \
    "m|Move — recommended: one canonical copy; ..." \
    "c|Copy — duplicate; ..." \
    "s|Skip — leave them in your home (the agent cannot use them)")
```

The old page carried the guard explicitly (`716b8c0:docs/getting-started.md` ≈ line 96): "The menu's Enter default is **skip** — move removes the developer-side sources after the copy, so it never rides on an empty Enter." The only remaining docs statement is `docs/reference/cli.md:199` "default: ask (`--yes` = move)" — which describes the flag default, not the interactive menu default, and sits on a different page.

**Why it matters:** a reader of getting-started sees "(recommended)" on move and can reasonably expect Enter to take it; Enter actually selects skip (the agent then cannot use their skills/agents, with no docs trace of why). Severity is LOW, not MED, because `ui_menu` marks the default on-screen at the prompt (`sh/ui.sh:228-233` prints the default key as `[s]`), so the mistake is visible at choice time and recoverable (`--migrate-agents move`, re-run). Wave-introduced caveat drop; the "move removes the dev-side sources" trade-off note was dropped with it.

### C3 — LOW — installer prompt list is incomplete: OpenChamber question missing

**Evidence** — `docs/getting-started.md:44-56` says the installer "prints a pre-flight inventory …, then asks:" and lists exactly 4 questions. The code asks a fifth conditional question in **both** standard and advanced mode, `files/install.sh:1065-1076`:

```sh
    if [ "$INTERACTIVE" = true ] && [ "$_oc_seen" = true ]; then
        if ui_confirm "Protect OpenChamber sessions too? (policy pin — its self-update buttons go dark)" "y"; then
```

plus the re-install gate at `install.sh:891` ("Re-configure the existing installation with install.sh?"). The OpenChamber question is documented only in `docs/how-to/openchamber.md:65-67` ("answer *Yes* to 'Protect OpenChamber sessions too?' (asked when OpenChamber is detected…)"), which getting-started does not link from the prompt list.

**Why it matters:** the numbered list reads as the complete set of installer questions; a user with OpenChamber installed sees a fifth prompt the page never mentions. Pre-existing: the old page (`716b8c0`) had the same 4-item list without the OpenChamber question — the rewrite carried the gap forward, it did not create it.

## Coverage

**Covered, all cross-checked against shipped code:** cli.md — every `opk` subcommand/flag, install.sh's 9 flags, update.sh's 8 flags, config.sh's command table, status.sh flags/exit codes/progress-line claim, upgrade-opencode shorthand, handover guardrails incl. `/tmp` carve-out, ensure-shared default, ddev-hosts behavior (prune set, `*.ddev.site` exclusion, `ddev hostname <name> 127.0.0.1`), `--version`/`0.0.0` fallback. files.md — every path and install.conf key (one stale claim *fixed* by the wave: `HARD_DENY_REMOVED` has zero grep hits in `files/`; the old "updates < 0.0.14 refused" text was the lie). update.md/uninstall.md — update floor 0.0.14, KIT_BRANCH>stamp precedence, backup dir, `autoupdate: false`, advisory "standalone" qualification; uninstall removals/keeps list, wsl.conf ask + line-range print, PARTIALLY rc, orphaned-gid setfacl hint, RC tag line. getting-started.md — distro whitelist, ddev/git gates, root-shell refusal, podman default, plan-confirm, migration dump paths, ddev-migrate usage. wrapper.md — headless subcommand list (verbatim match), env_keep set, BAK_<ts> + update-only-if-absent, 750 root:opencode, TUI 1.x/2.x registration, no-prompt claim. ddev-integration.md — URL extraction keys, browser-cmds.conf, BASH_ENV, handover table/anchors, heal commands, ports/mkcert/auth-ssh-deny/migration claims. container-tools.md (sed targets byte-exact vs template), switch-container-backend.md, customize-deny-list.md (leak-scan dirs + override, template tripwires, agent-config dir 2775), troubleshooting.md (uninstall root refusal, safe.directory install+update, PPA hint, no-bind-mounts both entry points, registry/`outside:`/INCOMPLETE, WSLInterop, stand-in debug line), security-model.md (mkcert key 0600, sudoers opencode-only, KIT_BASE_URL, ROOT_EQUIV_SOCKS), audit-log.md (750/640, rotation, "unlogged operations" claim is true — `bin/opk` and `wsl-browser-bridge.sh` contain zero `log` calls), sharing-group.md, dev-owned-projects.md, secure-git-config.md (`bak-<ts>` naming + status wording verbatim), manage-projects.md, glossary.md, compatibility.md (CI-both-majors claim matches workflow lanes), README.md (prose only).

**Deferred / unverified (recorded, not flagged):**
- Third-party tool behavior claims (OpenChamber 2.0.20 gate, ≥ 1.22.2 chats root, "OpenCode port is not available" message, toast/one-click behavior; compatibility.md tool statuses) — external tools, unverifiable against `files/`.
- ddev upstream behavior claims (unconditional settings chmods, hardcoded 0755/0644, bind-mount fix in 1.25.3, `name:` key derivation) — ddev-side; consistent with the kit code's own comments, not independently verified.
- cli.md:301-304 "two exceptions always count" verdict aggregation — the warn lines and exit codes 1/2/64 verified to exist; the full verdict tallying path not traced (budget: one follow-up read spent, claim left unverified rather than confirmed).
- Pages-URL availability (`steffenmaechtel.github.io/.../install.sh`, `update.sh`) — deployment-side, not checkable from the checkout.

## Reviewer output — axis X (security-relevant guidance), verbatim

# Security-axis review — wave diff 716b8c0..b69a336 (docs-only end-user optimization pass, base 0.0.56)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| X1 | MED | Dev-owned mode's accepted flag-write TOCTOU vanished from the residual-gaps list — no longer disclosed anywhere in docs | wave-introduced |
| X2 | LOW | getting-started.md lost its `/mnt/c`-exposure guidance; install-time disclosure of the world-readable Windows profile now has no docs anchor on the install path | wave-introduced |
| X3 | INFO | security-model supply-chain entry dropped the "verification is a liveness check only" and checksum-manifest-notes details; core disclosure survives | wave-introduced |
| X4 | INFO | SSH-key trade-off dropped its mitigation sentence (read/edit denies + tripwires keep gating) and "rotate if the machine is not trusted" | wave-introduced |
| X5 | INFO | Consent-rationale links, historical 0.0.36 recovery section, uninstall `--yes`/home-loss details, and audit enumeration dropped — no safety-meaning change | wave-introduced |

## Details

### X1 — MED · Dev-owned flag-write TOCTOU disclosure dropped tree-wide

Old `docs/concepts/security-model.md` (residual gaps, `git show 716b8c0:docs/concepts/security-model.md` lines 62–73):

> "… the gate is not atomic — a swap in the short window between the gate and the recursive pair itself stays undetected (a leaf-only mid-recheck covers just the chown half), and **dev-owned mode's flag-write TOCTOU stays accepted (opencode-privilege-capped)** …"

New `docs/concepts/security-model.md:63` keeps only the handover half:

> "**Handover symlink swaps:** the root-run `.ddev` handover re-tests every path component immediately before acting, but the gate is not atomic — a swap in the short window before the recursive pair stays undetected."

`git grep -i -E "TOCTOU|flag-write" b69a336 -- docs/` returns nothing; the only hit in the old tree is that one line. The disclosure was never duplicated in `docs/how-to/dev-owned-projects.md` or `docs/concepts/ddev-integration.md` (old or new), so the deletion removed it from the docs entirely.

Why it matters: the page's stated purpose is residual-gap disclosure, and dev-owned mode is the installer default (`docs/getting-started.md:82` — "dev-owned projects (default: …)"). A reader of the new security model concludes the only accepted race is the handover gate; the default mode's accepted window (a root-run flag write into `.ddev/config.yaml`, redirectable by the agent within the race window, impact capped at opencode privilege) is undocumented. Severity MED, not HIGH: the advice on the page stays correct to follow; the loss is honesty/completeness of the threat disclosure, and the gap is opencode-privilege-capped per the removed text. The dropped detail that the handover re-check makes a mid-scan swap skip-with-warning ("on every branch") is also gone, but the non-atomic-gate essence survives — same finding, counted once.

### X2 — LOW · Install path no longer discloses the /mnt/c exposure

Old `docs/getting-started.md:114–116` (install walkthrough):

> "`/mnt/c` exposure is never a prompt in either mode — the kit only *prints* the ready-to-run restriction snippet (it never edits `/etc/wsl.conf` itself …)"

New `docs/getting-started.md` has no `/mnt/c` content except the `opk status` enumeration (line 88: "It reports the protection mode, backend, ddev readiness, `/mnt/c` exposure and a leak scan") and the old line 105 root-ownership mention is gone with the restructure.

Why it matters: a user following only the getting-started page installs without being told their Windows profile (`.ssh/`, `NTUSER.DAT`) is readable by the agent until they apply the `[automount]` snippet. Mitigations keep this LOW: `opk status` surfaces the exposure and the wrapper warns on every start until fixed (`docs/concepts/security-model.md:89–90`), and the manual fix remains fully documented in security-model and troubleshooting. Consent framing is intact everywhere the file is named (see coverage) — this is a disclosure-coverage loss, not an RM-0104 violation.

### X3 — INFO · Supply-chain disclosure shortened, core kept

New `docs/concepts/security-model.md:73–77` keeps "over HTTPS without checksums or signatures … treat the install environment as trusted". Dropped: the `--binary` "verification is a liveness check (`opencode --version` runs)" detail, the fallback `opencode.ai/v2/install` stream mention, and "A pinned-release checksum manifest … would close the gap". The dropped sentences sharpened *how weak* the verification is; the surviving claim is accurate and the trust conclusion unchanged.

### X4 — INFO · SSH-key trade-off mitigations sentence dropped

Old `docs/concepts/ddev-integration.md:368–371`:

> "The read/edit denies (`*id_rsa*`, `*.pem`, …) and the bash tripwires keep gating opencode's tools. … Prefer dedicated, rotatable deploy keys **and rotate them if the machine is not trusted**."

New `docs/concepts/ddev-integration.md:265–268` keeps the import-deny and deploy-keys advice; the two dropped clauses told the reader direct key reads stay soft-gated after an import, and the rotation-on-distrust hygiene. Following the new page as written stays correct — INFO.

### X5 — INFO · Pointer/history losses with no safety-meaning change

All verified survived-or-harmless; recorded so the deferral is explicit:

- `docs/concepts/security-model.md`: rationale links to `internal/records/wsl-conf-consent.md` and `ddev-working.md` dropped (old lines 51, 131); the consent statements themselves remain (new lines 90, 114–115).
- `docs/troubleshooting.md`: the 0.0.36 `wsl: Expected ']'` recovery section removed — historical; the kit auto-strips that section since 0.0.38, base is 0.0.56, so no realistic trigger remains.
- `docs/how-to/uninstall.md`: "(or assumes yes with `--yes`)" for the wsl-block ask and "(ddev homes, imported keys)" home-loss detail dropped; the ask and default:no survive (new lines 39–41, 58–59).
- `docs/getting-started.md:88`: `opk status` enumeration dropped the root-equivalent-access audit item (audit still documented, security-model.md:141–155).
- `docs/how-to/secure-git-config.md`: legacy `//SECURE_GIT` markers block dropped (diagnostics only; backup-before-render caveat kept at new lines 28–30).

## Coverage

- **Covered, all 5 mandated sections:** security-model old-vs-new line-by-line; install/update/uninstall command shapes (curl|sudo env KIT_BRANCH shapes intact at getting-started.md:36,68 and update.md; no invented flags; root-shell warning kept at getting-started.md:39–41); wsl.conf framing on every page that names it — consent intact at security-model.md:90,114, troubleshooting.md:365, files.md:5–15, uninstall.md:39, cli.md:43–45; the five Section-4 how-to/concept pages (rule-order + credential-gate warning and private-key risk kept in container-tools.md; safe.directory `'*'` + `.git/config` caveat kept in sharing-group.md); troubleshooting destructive commands — only three destructive shapes exist, byte-identical old→new with preconditions (`rm -rf ~/.opencode/bin` with "removal only drops the self-installed bypass binary" new:157; `find|xargs chown -R` behind the "`.ddev` already handed over?" precondition new:207–209; traverse-only `setfacl` new:250).
- **Covered beyond the brief:** compatibility.md (OpenChamber 2.x bypass caveat survived, new lines 51–60), wrapper.md (OPENCODE_SERVER_PASSWORD/USERNAME disclosure consistent with security-model — no overstating), openchamber.md ("runs **as you, outside the kit**" warning kept, new line 35), cli.md (openchamber-secure ask-before-remove kept), ddev-integration.md.
- **Deferred:** no script bodies read (per budget discipline — docs-only diff, doc claims about script behavior cross-checked against each other, not against `files/` source); the "takes effect immediately" claim for the wsl carrier (new security-model.md:117, cli.md, troubleshooting.md) was not verified against script behavior — plausible, stated consistently in three pages, and not safety-relevant either way.
- **Pre-existing, not wave findings:** the `.ddev` handback `chown -R` runbook and the bypass-cleanup `rm -rf` predate the wave unchanged; their conditioning was checked and is adequate as written.

## Run provenance

- **Commission:** USER (maintainer), in-session — "Review Snapshot a über aktuelle branch",
  birth-PR #256; scope wave; skill `opk-review-pass` loaded (recorded in header).
- **Pass shape:** 3 reviewer subagents on the provider's fast tier
  (`zai-coding-plan/glm-5.3-Flash`, axes S sweep / C claims / X security),
  staged in one launch (3 of 5 concurrent seats — cap respected), + this
  main session (GLM-5.3) owning verification. Checkpoint files under
  `/tmp/opencode/pr-00256-a/checkpoints/` (outside the reviewed tree);
  checkpoint lines absorbed here.
- **Host timestamps (RM-0114):** fan-out start `2026-10-24T22:24:08Z`,
  fan-out end `2026-10-24T22:40:59Z` (~17 min wall, all three agents
  returned). Sandbox launch/return stamps: claims 22:24:57Z→22:40:05Z,
  security 22:24:55Z→return (end stamp in checkpoint file), sweep carried
  section lines without clock stamps — normalized against the host window.
- **Observed skew:** the axis-C reviewer's wall-clock was extended by a
  permission hold — its `git -C … diff` call waited for interactive USER
  approval (USER-confirmed command:
  `git -C /var/www/opencode-permissions-kit diff 716b8c0..b69a336 -- docs/README.md | head -60`).
  Budgets are section-based, not clock-based, so the pass is unaffected;
  the checkpoint trail shows continuous section progress around the wait.
- **Mutation/sabotage windows:** none — no tree mutations in this pass; the
  tree was a clean read substrate throughout (`git status --porcelain` empty
  before material collection and again before this commit). Reviewers were
  read-only; no screening in either direction was owed (RM-0111).
- **Environment:** opencode session, main model GLM-5.3
  (`zai-coding-plan/glm-5.3`), reviewers GLM-5.3-Flash; checkout at
  `/var/www/opencode-permissions-kit`, branch
  `feature/docs-end-user-optimizations`, clean at b69a336 (base 716b8c0 =
  master merge of PR #243, VERSION 0.0.56).

## Gates

Run before this snapshot commit (check-then-commit, RM-0117):

- `python3 scripts/gen-review-index.py` — INDEX regenerated with this case.
- `sh tests/unit/test-reviews-lint.sh` — PASS.
- `sh tests/unit/test-reviews-parity.sh` — PASS.
- `sh tests/unit/test-line-length.sh` — PASS.
- `sh tests/unit/test-docs.sh` — PASS (docs gates green on the reviewed
  tree; the suite does not pin the claim-level drift this review found —
  W1–W11 are prose findings, no gate exists for them yet).

## Calibration

Single snapshot (wave scope) — no second independent pass ran and none is
owed at wave scope; no collapsed redundancy axis to disclose beyond the
`Skills:` line in the header. Axis overlap: S1 ≡ C1 cross-confirmed the one
MED with independent evidence chains (both cited ddev-handover.sh:466);
the axes' clean verdicts did not contradict each other anywhere.

## Recommendation

The wave is a genuine shortening (−879 net lines) with unusually good claim
hygiene — the claims axis verified the overwhelming majority of behavioral
claims against the code and found exactly two content errors (W1, W3) plus
precision losses. Dispositions owed: 11 findings, none blocking the PR's
purpose; W1 and W2 deserve fixes (one-line value rename; one-bullet
residual-gap restore), W3–W7 are small text restorations, W8–W11 are
record-or-accept items. The fix wave — and whether any finding class here
is worth a docs lint pin — is the maintainer's call; this round ends at the
snapshot (hard seam — no fix starts before the go).
