#!/bin/sh
# Unit tests for the group-baseline helper with live progress (issue #14):
#   - fs_baseline_root applies chgrp + setgid + group rw + default ACLs
#     (same final state the install/update/config blocks produced)
#   - live per-pass counters ("N entries — done") go to stderr
#   - the chgrp pass never dereferences symlinks (targets outside the
#     tree keep their group — xargs chgrp would follow them)
#   - .git is included (issue #17 semantics carried over)
#   - the python3 health gate (#223): a missing or broken interpreter
#     degrades the passes to a warned-but-applied fallback (one warn
#     line — not silent, #244 a Q2) instead of the old false green,
#     probes once per run, and a dead consumer ends the tee silently
#     (pr-00221 W2/W6 rider)
# Runs against the repo lib as the CURRENT user (FS_SUDO="") — no root.
# Run: sh tests/unit/test-fs-baseline.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/fs-baseline.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
UPDATE_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"

# Shared harness (issue #394 adoption): pass/fail, colors, counters
# and the summary gate live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

WORK=$(mktemp -d)
# Widen the trap to every bare receiver of the suite (#283): TR, V9ROOT,
# STUBBIN, _bstub, SW, F1DIR, F1STUB, F1SP, F1SPD, F1SPS and F12S lived
# outside $WORK with only inline rm on their normal paths — a set -e
# abort inside the window leaked them. The list is a function (twelve
# receivers do not fit one line); unset-safe operands skip cleanly.
# This file's line-form trap was the wave's sibling idiom reference; the
# long receiver list now needs the function form (install.sh's cleanup
# precedent).
_trap_cleanup() {
    rm -rf "${WORK:-}" "${TR:-}" "${V9ROOT:-}" "${STUBBIN:-}" \
        "${_bstub:-}" "${SW:-}" "${F1DIR:-}" "${F1STUB:-}" \
        "${F1SP:-}" "${F1SPD:-}" "${F1SPS:-}" "${F12S:-}"
}
trap _trap_cleanup EXIT INT TERM

echo ""
echo "fs-baseline (group baseline progress, issue #14)"
echo "================================================="
echo ""

# Fixture: a tree with subdir, .git, files (tight modes), a symlink
# pointing OUT of the tree, and a foreign group on the root.
GRP="$(id -gn)"
mkdir -p "$WORK/proj/sub" "$WORK/proj/.git"
printf 'a\n' >"$WORK/proj/file.txt"
printf 'g\n' >"$WORK/proj/.git/config"
ln -s /etc/hostname "$WORK/proj/link-out"
chmod 700 "$WORK/proj" "$WORK/proj/sub" "$WORK/proj/.git"
chmod 600 "$WORK/proj/file.txt" "$WORK/proj/.git/config"

OUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$WORK/proj" "$GRP" 2>&1)"

# --- 1. final state -------------------------------------------------------------
assert_eq "root dir: group + setgid + group rwx, NO sticky (700 -> 2770, root un-stickied #703)" "2770" \
    "$(stat -c %a "$WORK/proj")"
assert_eq "subdir carries setgid" "2770" "$(stat -c %a "$WORK/proj/sub")"
assert_eq ".git shared and sticky-healed (issue #17 + #651)" "3770" "$(stat -c %a "$WORK/proj/.git")"
assert_eq "file gets group rw (600 -> 660)" "660" "$(stat -c %a "$WORK/proj/file.txt")"
assert_eq ".git/config healed developer-owned, no group write (#651)" "644" \
    "$(stat -c %a "$WORK/proj/.git/config")"
assert_eq "group applied everywhere" "$GRP" "$(stat -c %G "$WORK/proj/sub")"
if getfacl -p "$WORK/proj/sub" 2>/dev/null | grep -q '^default:group:.*:rwx'; then
    pass "default ACL g:<group>:rwx set on directories"
else
    fail "default ACL g:<group>:rwx set on directories"
fi

# --- 1b. .git metadata heal (#644, wave #651) ------------------------------------------
# The heal pins the execution-bearing .git entries developer-owned after
# the sharing passes. Unit pins assert the STATE (modes, owners,
# ACL-free, sticky); the uid-separation BLOCKING (an opencode-uid write
# bouncing off a developer-owned sticky entry) is e2e/pilot territory —
# a same-uid unit run cannot see ownership walls (the live battery is
# the evidence in issue #644).
HG="$WORK/healproj"
HGGRP="$(id -gn)"
HGME="$(id -u)"
mkdir -p "$HG/proj/.git/hooks" "$HG/proj/.git/refs/heads" "$HG/proj/.git/objects" \
    "$HG/proj/.git/logs/refs" "$HG/proj/.git/worktrees/wt1" \
    "$HG/proj/.git/modules/sub/hooks" "$HG/proj/.git/modules/nohooks" \
    "$HG/proj/nested/.git/hooks"
printf 'cfg\n' >"$HG/proj/.git/config"
printf 'nc\n' >"$HG/proj/nested/.git/config"
printf 'sm\n' >"$HG/proj/.git/modules/sub/config"
printf 'nh\n' >"$HG/proj/.git/modules/nohooks/config"
printf 's\n' >"$HG/proj/.git/hooks/pre-commit.sample"
printf '#!/bin/sh\n' >"$HG/proj/.git/hooks/planted-pre-commit"
chmod 755 "$HG/proj/.git/hooks/planted-pre-commit"
printf 'i\n' >"$HG/proj/.git/index"
printf 'h\n' >"$HG/proj/.git/HEAD"
printf 'r\n' >"$HG/proj/.git/refs/heads/main"
printf '..\n' >"$HG/proj/.git/worktrees/wt1/commondir"
printf '..\n' >"$HG/proj/.git/worktrees/wt1/gitdir"
printf 'wh\n' >"$HG/proj/.git/worktrees/wt1/HEAD"
printf 'log\n' >"$HG/proj/.git/logs/HEAD"
chmod 700 "$HG/proj/.git" "$HG/proj/.git/hooks"
HGOUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG/proj" "$HGGRP" 2>&1)"
assert_eq "heal: project root NOT sticky — legacy bit stripped (#703)" "2775" \
    "$(stat -c %a "$HG/proj")"
assert_eq "heal: NESTED .git parent NOT sticky — ancestor walk strips (#703)" \
    "2775" "$(stat -c %a "$HG/proj/nested")"
assert_eq "heal: nested .git healed like any other" "644" \
    "$(stat -c %a "$HG/proj/nested/.git/config")"
assert_eq "heal: .git keeps sharing mode + sticky (dirs pass then +t)" "3770" \
    "$(stat -c %a "$HG/proj/.git")"
assert_eq "heal: .git/config 644" "644" "$(stat -c %a "$HG/proj/.git/config")"
assert_eq "heal: .git/config owner is the developer (root-derived)" "$HGME" \
    "$(stat -c %u "$HG/proj/.git/config")"
assert_eq "heal: .git/hooks 755 shape, no group write (dir setgid rides along, harmless)" "2755" \
    "$(stat -c %a "$HG/proj/.git/hooks")"
assert_eq "heal: .git/hooks owner is the developer" "$HGME" "$(stat -c %u "$HG/proj/.git/hooks")"
# The umask-644 fixture files (not pre-tightened to 600 — the healed
# invariant is group rw, not a specific absolute mode): files pass g+rw
# lands on 664, and the heal must NOT touch these agent-workflow files.
assert_eq "heal: hook sample files stay shared (no execution surface)" "664" \
    "$(stat -c %a "$HG/proj/.git/hooks/pre-commit.sample")"
assert_eq "heal: index keeps group rw (agent workflow file)" "664" \
    "$(stat -c %a "$HG/proj/.git/index")"
assert_eq "heal: HEAD keeps group rw" "664" "$(stat -c %a "$HG/proj/.git/HEAD")"
assert_eq "heal: refs keep group rw" "664" "$(stat -c %a "$HG/proj/.git/refs/heads/main")"
assert_eq "heal: logs keep group rw" "664" "$(stat -c %a "$HG/proj/.git/logs/HEAD")"
assert_eq "heal: worktrees collection sticky, still group-writable (agent adds its own)" "3775" \
    "$(stat -c %a "$HG/proj/.git/worktrees")"
assert_eq "heal: registration dir keeps group rw (merge-state files must appear)" "2775" \
    "$(stat -c %a "$HG/proj/.git/worktrees/wt1")"
assert_eq "heal: commondir pointer pinned 644" "644" \
    "$(stat -c %a "$HG/proj/.git/worktrees/wt1/commondir")"
assert_eq "heal: gitdir pointer pinned 644" "644" \
    "$(stat -c %a "$HG/proj/.git/worktrees/wt1/gitdir")"
assert_eq "heal: worktree HEAD keeps group rw" "664" \
    "$(stat -c %a "$HG/proj/.git/worktrees/wt1/HEAD")"
assert_eq "heal: module gitdir sticky, no group write (setgid rides along)" "3755" \
    "$(stat -c %a "$HG/proj/.git/modules/sub")"
assert_eq "heal: module config pinned 644" "644" \
    "$(stat -c %a "$HG/proj/.git/modules/sub/config")"
assert_eq "heal: module hooks pinned, no group write" "2755" \
    "$(stat -c %a "$HG/proj/.git/modules/sub/hooks")"
assert_eq "heal: modules CONTAINER pinned (sticky on the parent — gates wholesale child swaps, #655 a C2)" \
    "3755" "$(stat -c %a "$HG/proj/.git/modules")"
assert_eq "heal: container owner is the developer (#655 a C2)" "$HGME" \
    "$(stat -c %u "$HG/proj/.git/modules")"
assert_eq "heal: hooks-LESS module gitdir pinned too (marker-free enumeration, #655 a C3)" \
    "3755" "$(stat -c %a "$HG/proj/.git/modules/nohooks")"
assert_eq "heal: hooks-less module config pinned (#655 a C3)" "644" \
    "$(stat -c %a "$HG/proj/.git/modules/nohooks/config")"
if printf '%s\n' "$HGOUT" | grep -qF 'non-sample entries'; then
    pass "heal: non-sample hook content surfaces as a warn (metadata pinning preserves it, #655 a C1)"
else
    fail "heal: non-sample hook content surfaces as a warn (metadata pinning preserves it, #655 a C1)"
fi
if printf '%s\n' "$HGOUT" | grep -qF "non-sample entries in $HG/proj/.git/hooks"; then
    pass "heal: the warn names the hooks directory (inspect-and-remove pointer)"
else
    fail "heal: the warn names the hooks directory (inspect-and-remove pointer)"
fi
if getfacl -p "$HG/proj/.git/hooks" 2>/dev/null | grep -q '^default:'; then
    fail "heal: default ACLs stripped from .git/hooks (they would re-grant group write)"
else
    pass "heal: default ACLs stripped from .git/hooks (they would re-grant group write)"
fi
if getfacl -p "$HG/proj/.git/config" 2>/dev/null | grep -qE '^(group:[^:]|default:)'; then
    fail "heal: no extended ACL entries survive on .git/config"
else
    pass "heal: no extended ACL entries survive on .git/config"
fi
if printf '%s\n' "$HGOUT" | grep -q 'git heal:'; then
    pass "heal: one progress line per healed .git"
else
    fail "heal: one progress line per healed .git"
fi
# Idempotence of the heal cycle: the sharing passes re-grant, the heal
# re-narrows — the end state must be byte-stable across runs.
HGRC2=0
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG/proj" "$HGGRP" \
    >/dev/null 2>&1 || HGRC2=$?
assert_eq "heal: idempotent re-run rc 0" "0" "$HGRC2"
assert_eq "heal: idempotent re-run state stable (root/config/hooks/.git/worktrees)" \
    "2775/644/2755/3770/3775" \
    "$(stat -c %a "$HG/proj")/$(stat -c %a "$HG/proj/.git/config")/$(stat -c %a "$HG/proj/.git/hooks")/$(stat -c %a "$HG/proj/.git")/$(stat -c %a "$HG/proj/.git/worktrees")"

# Trailing-slash root (#655 a C4): the belt accepts the spelling; the
# heal must normalize before the component walk — pre-fix, the walk
# voided and the config stayed unpinned (group-writable). Drive the
# driver directly so the belt is out of the picture.
HG4="$WORK/healslash"
mkdir -p "$HG4/proj2/.git/hooks"
printf 'c\n' >"$HG4/proj2/.git/config"
printf 'h\n' >"$HG4/proj2/.git/hooks/pre-commit.sample"
FS_SUDO="" sh -c '. "$1" && _fsb_heal_git "$2/" "$3"' _ "$LIB" "$HG4/proj2" "$HGGRP" >/dev/null 2>&1
assert_eq "heal: trailing-slash root still pins (walk normalized, #655 a C4)" "644" \
    "$(stat -c %a "$HG4/proj2/.git/config")"
# Sticky-ABSENCE assertion, not absolute mode: this host's /tmp grants
# group write through default ACLs at mkdir time (1775, not 1755) — the
# direct-driver pin cares about the sticky bit alone (leading 1), which
# the #703 driver must have STRIPPED (the fixture is chmod +t'd first:
# the migration shape — installed bases carry the bit).
chmod 3775 "$HG4/proj2"
FS_SUDO="" sh -c '. "$1" && _fsb_heal_git "$2/" "$3"' _ "$LIB" "$HG4/proj2" "$HGGRP" >/dev/null 2>&1
case "$(stat -c %a "$HG4/proj2")" in
    [1357]???)
        fail "heal: trailing-slash root strip applies (#703; got $(stat -c %a "$HG4/proj2"))"
        ;;
    *)
        pass "heal: trailing-slash root strip applies (#703)"
        ;;
esac

# Root swapped to a symlink before the heal (#655 a C5): refused loud —
# the empty-scan silent no-op must not happen. _FSB_ERRORS is the
# observable (the belt refuses this shape earlier at the fs_baseline_root
# level, so the driver is driven directly).
HG5="$WORK/healswap"
mkdir -p "$HG5/real/.git"
ln -s "$HG5/real" "$HG5/link"
HG5OUT="$(FS_SUDO="" sh -c '. "$1" && _FSB_ERRORS=0 && _fsb_heal_git "$2" "$3" && echo "ERRS=$_FSB_ERRORS"' \
    _ "$LIB" "$HG5/link" "$HGGRP" 2>&1)"
if printf '%s\n' "$HG5OUT" | grep -q 'ERRS=1$'; then
    pass "heal: symlinked root counts as an error (no silent no-op, #655 a C5)"
else
    fail "heal: symlinked root counts as an error (no silent no-op, #655 a C5) — got: $HG5OUT"
fi
if printf '%s\n' "$HG5OUT" | grep -qF 'root became a symlink'; then
    pass "heal: the C5 refusal names the cause"
else
    fail "heal: the C5 refusal names the cause"
fi

# --- 1c. fix-wave-b arms (#655 b) ------------------------------------------------
# C1 ancestor chain (inverted by #703): a .git at depth 2 — BOTH
# intermediate dirs must be STRIPPED of the legacy sticky.
HG6="$WORK/healdepth2"
mkdir -p "$HG6/proj/grp/site/.git/hooks"
printf 'c\n' >"$HG6/proj/grp/site/.git/config"
# Migration shape: plant the legacy bits the #655-era heal would have
# left (root, both ancestors) — the #703 run must take all three off.
chmod 3775 "$HG6/proj" "$HG6/proj/grp" "$HG6/proj/grp/site"
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG6/proj" "$HGGRP" >/dev/null 2>&1
assert_eq "heal: depth-2 ancestor dir NOT sticky (stripped, #703)" "2775" \
    "$(stat -c %a "$HG6/proj/grp")"
assert_eq "heal: depth-2 .git parent NOT sticky (stripped, #703)" "2775" \
    "$(stat -c %a "$HG6/proj/grp/site")"
assert_eq "heal: depth-2 root NOT sticky (stripped, #703)" "2775" \
    "$(stat -c %a "$HG6/proj")"
assert_eq "heal: depth-2 .git healed like any other" "644" \
    "$(stat -c %a "$HG6/proj/grp/site/.git/config")"

# C2: a symlinked .git is never followed, always surfaced.
HG7="$WORK/heallnk"
mkdir -p "$HG7/proj/repoA" "$HG7/outside"
ln -s "$HG7/outside" "$HG7/proj/repoA/.git"
HG7OUT="$(FS_SUDO="" sh -c '. "$1" && _FSB_ERRORS=0 && fs_baseline_root "$2" "$3"' \
    _ "$LIB" "$HG7/proj" "$HGGRP" 2>&1)"
HG7RC=$?
assert_eq "heal: symlinked .git warns without failing the baseline (b C2)" "0" "$HG7RC"
if printf '%s\n' "$HG7OUT" | grep -qF 'symlinked .git not followed'; then
    pass "heal: the symlinked-.git warn names the entry (b C2)"
else
    fail "heal: the symlinked-.git warn names the entry (b C2)"
fi

# C3: symlinked containers and symlinked children are surfaced, never
# followed — two separate gitdirs (a symlinked modules container hides
# its children from every scan, so each arm needs its own fixture).
mkdir -p "$HG7/proj/realgit/.git" "$HG7/proj/realgit/.git/hooks" "$HG7/modtarget"
mkdir -p "$HG7/proj/contgit/.git/hooks"
printf 'c\n' >"$HG7/proj/realgit/.git/config"
printf 'c\n' >"$HG7/proj/contgit/.git/config"
ln -s "$HG7/modtarget" "$HG7/proj/contgit/.git/modules"
mkdir -p "$HG7/proj/realgit/.git/modules/real" "$HG7/childtarget"
ln -s "$HG7/childtarget" "$HG7/proj/realgit/.git/modules/lnk-child"
HG7BOUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' \
    _ "$LIB" "$HG7/proj" "$HGGRP" 2>&1)"
if printf '%s\n' "$HG7BOUT" | grep -qF 'symlinked modules dir not followed'; then
    pass "heal: the symlinked-modules warn fires (b C3)"
else
    fail "heal: the symlinked-modules warn fires (b C3)"
fi
if printf '%s\n' "$HG7BOUT" | grep -qF 'symlinked module entry not followed'; then
    pass "heal: the child-level symlink warn fires (c S3)"
else
    fail "heal: the child-level symlink warn fires (c S3)"
fi

# C4: submodule worktree registration pointers are pinned like the top
# gitdir's (helper extraction).
mkdir -p "$HG/proj/.git/modules/sub/worktrees/wt2"
printf '..\n' >"$HG/proj/.git/modules/sub/worktrees/wt2/commondir"
printf '..\n' >"$HG/proj/.git/modules/sub/worktrees/wt2/gitdir"
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG/proj" "$HGGRP" >/dev/null 2>&1
assert_eq "heal: submodule worktree commondir pinned (b C4)" "644" \
    "$(stat -c %a "$HG/proj/.git/modules/sub/worktrees/wt2/commondir")"
assert_eq "heal: submodule worktree gitdir pinned (b C4)" "644" \
    "$(stat -c %a "$HG/proj/.git/modules/sub/worktrees/wt2/gitdir")"

# S2/C7: a `/` root is refused — driver and belt both.
HG8OUT="$(FS_SUDO="" sh -c '. "$1" && _FSB_ERRORS=0 && _fsb_heal_git / "$2" && echo "ERRS=$_FSB_ERRORS"' \
    _ "$LIB" "$HGGRP" 2>&1)"
if printf '%s\n' "$HG8OUT" | grep -qF 'never a heal root'; then
    pass "heal: the / root is refused loud by the driver (b S2)"
else
    fail "heal: the / root is refused loud by the driver (b S2) — got: $HG8OUT"
fi
if printf '%s\n' "$HG8OUT" | grep -q 'ERRS=1$'; then
    pass "heal: the / refusal COUNTS as an error (c S4)"
else
    fail "heal: the / refusal COUNTS as an error (c S4) — got: $HG8OUT"
fi
HG8BOUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root / "$2"' _ "$LIB" "$HGGRP" 2>&1)" &&
    HG8BRC=0 || HG8BRC=$?
assert_eq "belt: the / root is refused before any pass runs (b S2/C7)" "1" "$HG8BRC"
# Message leg (#792, the #791 a C1 residue): the rc assert above is
# ambiguous — a sabotage keeping rc 1 while breaking the refusal
# message stayed green. The captured stderr must carry the arm's own
# refusal line; inside THIS probe's capture the fragment is
# leg-specific twice over — the fs-baseline CLI belt's message at
# :318 shares only the sub-phrase 'never a baseline root', the full
# fragment does not occur in its emission, and that belt lives in a
# function this probe never calls (its own legs are pinned
# separately below).
if printf '%s\n' "$HG8BOUT" | grep -qF 'error: / is never a baseline root'; then
    pass "belt: the / refusal names the whole-filesystem scope (b S2/C7; #792)"
else
    fail "belt: the / refusal must print its own message (rc=$HG8BRC, out=$HG8BOUT) (b S2/C7; #792)"
fi

# S1: the wc-guard degradation — a restricted PATH without wc over a
# tree WITH a non-sample hook must stay rc 0, warn nothing, not abort.
HG9="$WORK/healnowc"
HG9BIN="$WORK/healnowc-bin"
mkdir -p "$HG9/proj/.git/hooks" "$HG9BIN"
printf 'c\n' >"$HG9/proj/.git/config"
printf '#!/bin/sh\n' >"$HG9/proj/.git/hooks/planted-x"
chmod 755 "$HG9/proj/.git/hooks/planted-x"
for _t in sh find cat chgrp chmod setfacl chown mktemp dirname stat rm xargs; do
    ln -s "$(command -v "$_t")" "$HG9BIN/$_t"
done
HG9RC=0
HG9OUT="$(FS_SUDO="" PATH="$HG9BIN" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG9/proj" "$HGGRP" 2>&1)" ||
    HG9RC=$?
assert_eq "heal: missing wc degrades to no-warn, no abort (rc 0, b S1)" "0" "$HG9RC"
if printf '%s\n' "$HG9OUT" | grep -qF 'non-sample entries'; then
    fail "heal: missing wc must not emit the warn (b S1)"
else
    pass "heal: missing wc must not emit the warn (b S1)"
fi

# S6: the ==0 control arm — a samples-only hooks dir stays silent
# (HG4 carries only pre-commit.sample; capture the driver output).
HG4OUT="$(FS_SUDO="" sh -c '. "$1" && _fsb_heal_git "$2/" "$3"' _ "$LIB" "$HG4/proj2" "$HGGRP" 2>&1)"
if printf '%s\n' "$HG4OUT" | grep -qF 'non-sample entries'; then
    fail "heal: samples-only hooks dir stays warn-silent (b S6)"
else
    pass "heal: samples-only hooks dir stays warn-silent (b S6)"
fi

# d S1: the depth-1 guard's NEGATIVE arm — an in-tree dir named after
# a root-path segment (here: "tmp", a segment of every /tmp/... root)
# must stay UN-sticky when the .git sits directly under the root;
# without the guard the walk would chew the parent's absolute segments
# and strip exactly this dir of a sticky it may legitimately carry.
HG10="$WORK/healneg"
mkdir -p "$HG10/proj/tmp" "$HG10/proj/.git/hooks"
printf 'c\n' >"$HG10/proj/.git/config"
# #703 flip: the .git parent at depth 1 IS the scan root, and the root
# is stripped — the control arm pins sticky ABSENCE now (and a
# deliberately planted sticky on the segment-named sibling must
# SURVIVE: the walk never touches it).
chmod 3775 "$HG10/proj/tmp"
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG10/proj" "$HGGRP" >/dev/null 2>&1
case "$(stat -c %a "$HG10/proj/tmp")" in
    [1357]???)
        pass "heal: segment-named dir keeps its sticky at depth 1 (d S1, #703)"
        ;;
    *)
        fail "heal: segment-named dir keeps its sticky at depth 1 (d S1, #703; got $(stat -c %a "$HG10/proj/tmp"))"
        ;;
esac
case "$(stat -c %a "$HG10/proj")" in
    [1357]???)
        fail "heal: the .git parent (== root at depth 1) is NOT sticky (control, #703)"
        ;;
    *)
        pass "heal: the .git parent (== root at depth 1) is NOT sticky (control, #703)"
        ;;
esac

# d S2 + #818 a S1: the temp registrations — a RECORDING _tmp_track
# over a heal run with symlinks (all three sidecar shapes fire: driver
# .git scan, container scan, child scan) must log the opk-fsb-heal
# stems, and (S1) every logged name must ALREADY be a regular file at
# registration time: the sidecars are their own mktemp files now, and
# under the pre-S1 form the base+l names were tracked before the
# redirect ever created them.
HG11="$WORK/healtrack"
HG11_TRACK="$HG11/tracked"
mkdir -p "$HG11/proj/contgit/.git/hooks" "$HG11/proj/realgit/.git/hooks" \
    "$HG11/proj/realgit/.git/modules/real" "$HG11/tgt"
printf 'c\n' >"$HG11/proj/contgit/.git/config"
printf 'c\n' >"$HG11/proj/realgit/.git/config"
ln -s "$HG11/tgt" "$HG11/proj/contgit/.git/modules"
ln -s "$HG11/tgt" "$HG11/proj/realgit/.git/modules/lnk-child"
F12_TRACK="$HG11_TRACK" FS_SUDO="" \
    sh -c '. "$1" && _tmp_track() { printf "%s\n" "$1" >> "$F12_TRACK"; } \
    && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG11/proj" "$HGGRP" >/dev/null 2>&1
# This fixture deterministically registers EIGHT opk-fsb-heal files
# (#818 a S1): FOUR bases (driver .git scan + two gitdir modules scans
# + realgit's module child scan) and FOUR sidecars (the driver's
# .git-symlink scan — empty here, its .git dirs are real — two module
# container scans — contgit's fires on a real symlink, realgit's is
# empty — and realgit's child scan, which fires on the symlinked
# child). Empty scans still register — the contract is abort-leak
# coverage. All eight are bare mktemp names (stem + 8 chars); the
# pre-S1 {8}l$ flake discriminator is gone with the base+l spelling
# itself.
if grep -cE 'opk-fsb-heal\.[A-Za-z0-9]{8}$' "$HG11_TRACK" 2>/dev/null | grep -q '^8$'; then
    pass "heal: all scan temps (bases + sidecars) registered with _tmp_track (d S2, #818 a S1)"
else
    fail "heal: all scan temps (bases + sidecars) registered with _tmp_track (d S2, #818 a S1) — got: $(cat "$HG11_TRACK" 2>/dev/null | tr '\n' ' ')"
fi

# #818 a S1, the security property itself: every temp a heal run
# registers is a REGULAR FILE at registration time (mktemp's O_EXCL
# product — never a plain-`>` open at an unclaimed name a 1777-TMPDIR
# neighbor could have planted a symlink at). The stat-recording
# _tmp_track fires while the file exists; under the pre-S1 form the
# sidecar names were tracked before any redirect created them, so
# this leg redds exactly on the old shape.
HG11_STAT="$HG11/stattrack"
F12_TRACK="$HG11_STAT" FS_SUDO="" \
    sh -c '. "$1" && _tmp_track() {
        if [ -f "$1" ] && [ ! -L "$1" ]; then _t=reg; else _t=planted-or-missing; fi
        printf "%s %s\n" "$1" "$_t" >> "$F12_TRACK"
    } && fs_baseline_root "$2" "$3"' _ "$LIB" "$HG11/proj" "$HGGRP" >/dev/null 2>&1
if [ -s "$HG11_STAT" ] && awk '$2 != "reg" { bad = 1 } END { exit bad ? 1 : 0 }' "$HG11_STAT"; then
    pass "heal: every registered scan temp is a regular file at registration time (#818 a S1)"
else
    fail "heal: every registered scan temp is a regular file at registration time (#818 a S1) — got: $(cat "$HG11_STAT" 2>/dev/null | tr '\n' ' ')"
fi

# #818 a S1, the class guard (L2 sweep pinned): no shipped file opens a
# redirect at a braced-variable-plus-l name anymore — the base+l
# sidecar spelling WAS the S1 class (an unclaimed name, a plain
# truncating open, root-run). The closing sweep found the class only
# in fs-baseline.sh; this pin keeps the whole shipped tree free of
# the shape.
if grep -rEq '>"\$\{[A-Za-z_][A-Za-z0-9_]*\}l"' "$SCRIPT_DIR/../../files" 2>/dev/null; then
    fail "shipped tree: plain redirect at a base+l sidecar name still present (#818 a S1) — $(grep -rlE '>"\$\{[A-Za-z_][A-Za-z0-9_]*\}l"' "$SCRIPT_DIR/../../files" 2>/dev/null | tr '\n' ' ')"
else
    pass "shipped tree: no plain redirect at a base+l sidecar name anywhere (#818 a S1)"
fi

rm -rf "$HG" "$HGS" "$HGF" "$HGFSTUB" "$HG4" "$HG5" "$HG6" "$HG7" "$HG9" "$HG9BIN" "$HG10" "$HG11"

# A symlinked operand never gets pinned (the follow would write through
# the link — the L5 class): a config swapped for a link is skipped with
# the named warn, the run stays green, and the link TARGET outside the
# tree keeps its mode.
HGS="$WORK/healsym"
mkdir -p "$HGS/proj/.git" "$HGS/outside"
printf 't\n' >"$HGS/outside/target"
chmod 600 "$HGS/outside/target"
ln -s "$HGS/outside/target" "$HGS/proj/.git/config"
HGSOUT="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$HGS/proj" "$HGGRP" 2>&1)"
HGSRC=$?
assert_eq "heal: symlinked config skips without failing the baseline" "0" "$HGSRC"
if printf '%s\n' "$HGSOUT" | grep -qF 'git heal skipped'; then
    pass "heal: the skip names the operand (warn, not silence)"
else
    fail "heal: the skip names the operand (warn, not silence)"
fi
assert_eq "heal: symlink target outside the tree untouched" "600" \
    "$(stat -c %a "$HGS/outside/target")"

# A failing heal op fails the WHOLE baseline loud (the F10 contract):
# a PATH-stubbed chown passes the tool probe but dies per operand —
# the summary must refuse "applied".
HGF="$WORK/healfail"
HGFSTUB="$WORK/healfail-bin"
mkdir -p "$HGF/proj/.git/hooks" "$HGFSTUB"
printf 'c\n' >"$HGF/proj/.git/config"
cat >"$HGFSTUB/chown" <<'EOF'
#!/bin/sh
echo "chown stub: deliberate failure" >&2
exit 1
EOF
chmod +x "$HGFSTUB/chown"
HGFOUT="$(PATH="$HGFSTUB:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$HGF/proj" "$HGGRP" 2>&1 || true)"
if printf '%s\n' "$HGFOUT" | grep -q BASELINE-RC0; then
    fail "heal: a failing heal op must fail the baseline (loud, not green)"
else
    pass "heal: a failing heal op must fail the baseline (loud, not green)"
fi
if printf '%s\n' "$HGFOUT" | grep -qF 'git heal: chown'; then
    pass "heal: the failing op is named (chown)"
else
    fail "heal: the failing op is named (chown)"
fi

# #703: the root STRIP's own failure path (L1 — the twin arm of the
# chown stub above): a PATH-stubbed chmod failing ONLY on -t must
# count into _FSB_ERRORS and fail the baseline loud — a silent strip
# failure would leave legacy stickies behind while the caller prints
# "applied" (the #699/#682/#701 friction this wave exists to remove).
HGF2="$WORK/healstripfail"
HGF2STUB="$WORK/healstripfail-bin"
mkdir -p "$HGF2/proj/.git/hooks" "$HGF2STUB"
printf 'c\n' >"$HGF2/proj/.git/config"
_real_chmod="$(command -v chmod)"
cat >"$HGF2STUB/chmod" <<EOF
#!/bin/sh
[ "\$1" = "-t" ] && exit 1
exec "$_real_chmod" "\$@"
EOF
chmod +x "$HGF2STUB/chmod"
HGF2OUT="$(PATH="$HGF2STUB:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$HGF2/proj" "$HGGRP" 2>&1 || true)"
if printf '%s' "$HGF2OUT" | grep -q BASELINE-RC0; then
    fail "heal: a failing root strip must fail the baseline (#703, loud)"
else
    pass "heal: a failing root strip must fail the baseline (#703, loud)"
fi
if printf '%s' "$HGF2OUT" | grep -qF 'chmod -t (project root strip)'; then
    pass "heal: the failing strip is named (project root, #703)"
else
    fail "heal: the failing strip is named (out=$(printf '%s' "$HGF2OUT" | grep -F 'chmod -t' | head -2))"
fi

# #706 a S3: the WALK twin's own failure leg (_fsb_heal_unsticky, the
# ancestor strip — distinct from the driver's root strip above): the
# HGF2 fixture sits .git at depth 1 (parent == root, no walk), so this
# arm drives a DEPTH-2 .git whose ancestors (proj/grp, proj/grp/site)
# go through _fsb_heal_unsticky — a chmod stub failing only on -t must
# fail the baseline loud AND name the ANCESTOR operand (the driver's
# root error alone would not discriminate the twin's fold).
HGF3="$WORK/healwalkfail"
HGF3STUB="$WORK/healwalkfail-bin"
mkdir -p "$HGF3/proj/grp/site/.git/hooks" "$HGF3STUB"
printf 'c\n' >"$HGF3/proj/grp/site/.git/config"
cat >"$HGF3STUB/chmod" <<EOF
#!/bin/sh
[ "\$1" = "-t" ] && exit 1
exec "$_real_chmod" "\$@"
EOF
chmod +x "$HGF3STUB/chmod"
HGF3OUT="$(PATH="$HGF3STUB:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$HGF3/proj" "$HGGRP" 2>&1 || true)"
if printf '%s' "$HGF3OUT" | grep -q BASELINE-RC0; then
    fail "heal: a failing ancestor strip must fail the baseline (#706 a S3)"
else
    pass "heal: a failing ancestor strip must fail the baseline (#706 a S3)"
fi
if printf '%s' "$HGF3OUT" | grep -qF "chmod -t failed on $HGF3/proj/grp"; then
    pass "heal: the failing ANCESTOR strip is named (the walk twin's fold, #706 a S3)"
else
    fail "heal: the failing ancestor strip is named (out=$(printf '%s' "$HGF3OUT" | grep -F 'chmod -t failed' | head -3))"
fi
rm -rf "$HG" "$HGS" "$HGF" "$HGFSTUB" "$HGF2" "$HGF2STUB" "$HGF3" "$HGF3STUB"

# A bare `chgrp <link>` follows the TARGET; chgrp -R (the old code) did
# not. The pass must skip symlinks entirely — the link's TARGET (here a
# root-owned system file) keeps its group. NB: plain stat(1) lstats a
# symlink, -L dereferences.
if [ "$(stat -L -c %G "$WORK/proj/link-out" 2>/dev/null)" != "$GRP" ]; then
    pass "symlink target untouched (outside the tree, group kept)"
else
    fail "symlink target untouched (target group became $GRP)"
fi

# --- 3. progress output (issue #14) ----------------------------------------------
echo "$OUT" | grep -q "large trees can take several minutes" &&
    pass "heads-up line for large trees present" ||
    fail "heads-up line for large trees present"
echo "$OUT" | grep -q "chgrp *[0-9]* entries — done" &&
    pass "chgrp pass reports a done-counter" ||
    fail "chgrp pass reports a done-counter"
echo "$OUT" | grep -q "dirs g+rwxs *[0-9]* entries — done" &&
    pass "dirs pass reports a done-counter" ||
    fail "dirs pass reports a done-counter"
echo "$OUT" | grep -q "files g+rw *[0-9]* entries — done" &&
    pass "files pass reports a done-counter" ||
    fail "files pass reports a done-counter"
echo "$OUT" | grep -q "default ACLs *[0-9]* entries — done" &&
    pass "ACL pass reports a done-counter" ||
    fail "ACL pass reports a done-counter"

# --- 4. idempotence ---------------------------------------------------------------
_idem_rc=0
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$WORK/proj" "$GRP" >/dev/null 2>&1 ||
    _idem_rc=$?
assert_eq "idempotent re-run exits 0" "0" "$_idem_rc"
assert_eq "re-run is idempotent (modes stable; root stays un-stickied, #703)" \
    "2770 2770 660" \
    "$(stat -c %a "$WORK/proj") $(stat -c %a "$WORK/proj/sub") $(stat -c %a "$WORK/proj/file.txt")"

# --- 5. empty/missing root is a silent no-op ----------------------------------------
OUT3="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2-nope" "$3"' _ "$LIB" "$WORK/proj" "$GRP" 2>&1)" || true
assert_eq "missing root: no output, no error" "" "$OUT3"

# --- 6. wiring: all three callers use the helper -------------------------------------
# update.sh calls fs_baseline_root from its phase lib since #346 wave 2,
# install.sh likewise since wave 3 (#407 b B1: the $INSTALL leg matched
# only the bootstrap stub definer — the real call lives in
# install-core.sh, same class as round a's P1). Call-form pattern
# (#407 c C1/C2: the opening quote of the first argument matches CALL
# SITES only — the lib's header comment and the entries' stub-definer
# code lines (`fs_baseline_root() {`) must not keep a leg green after
# the real call is deleted; proven by scratch deletion probe).
for f in "$INSTALL_CORE" "$UPDATE_CORE" "$CONFIG"; do
    if grep -q 'fs_baseline_root "' "$f"; then
        pass "$(basename "$f") runs the baseline through fs_baseline_root"
    else
        fail "$(basename "$f") runs the baseline through fs_baseline_root"
    fi
done
live_src "$INSTALL" | grep -q 'opencode-permissions-kit-lib/sh/fs-baseline.sh' &&
    pass "install.sh fetch list includes fs-baseline.sh" ||
    fail "install.sh fetch list includes fs-baseline.sh"
live_src "$UPDATE" | grep -q 'opencode-permissions-kit-lib/sh/fs-baseline.sh' &&
    pass "update.sh KIT_FILES includes fs-baseline.sh" ||
    fail "update.sh KIT_FILES includes fs-baseline.sh"
live_src "$UPDATE_CORE" | grep -q 'large trees: this can take a while' &&
    pass "update.sh hints before the ddev handover scan (issue #14)" ||
    fail "update.sh hints before the ddev handover scan (issue #14)"
# The hint line lives in do_plan_phase's getfacl backup (install-core.sh
# since #346 wave 3).
live_src "$INSTALL_CORE" | grep -q 'large trees: this can take minutes' &&
    pass "install.sh hints before the getfacl backup (issue #14)" ||
    fail "install.sh hints before the getfacl backup (issue #14)"

# --- 7. ancestor traversal (fs_ensure_traversable) ------------------------------------
# Fresh chain outside $WORK (which already carries the traverse entry
# from the runs above): $TR (700, group GRP) -> pub (755) -> proj.
# Ancestors of $TR/pub/proj: pub has other-x (untouched), $TR is 700
# with the sharing group (grant), /tmp and / are world-x (untouched).
TR=$(mktemp -d)
mkdir -p "$TR/pub/proj" "$TR/gx/proj"
chmod 700 "$TR"
chmod 755 "$TR/pub"
chmod 750 "$TR/gx"
_anc_rc=0
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$TR/pub/proj" "$GRP" >/dev/null 2>&1 ||
    _anc_rc=$?
if [ "$_anc_rc" = 0 ] && getfacl -p "$TR" 2>/dev/null | grep -q "^group:$GRP:--x"; then
    pass "blocking ancestor gets a traverse-only ACL (x, no read/list)"
else
    fail "blocking ancestor gets a traverse-only ACL (got: $(getfacl -p "$TR" 2>/dev/null | grep "^group:$GRP" | tr '\n' ' '))"
fi
if getfacl -p "$TR" 2>/dev/null | grep -q "^group:$GRP:r"; then
    fail "traverse grant must not add read (dir stays non-listable)"
else
    pass "traverse grant must not add read (dir stays non-listable)"
fi
if getfacl -p "$TR/pub" 2>/dev/null | grep -q "^group:$GRP:"; then
    fail "other-x ancestor stays untouched (no ACL entry)"
else
    pass "other-x ancestor stays untouched (no ACL entry)"
fi
# 750 dir owned by the sharing group already grants group-x: no entry.
if getfacl -p "$TR/gx" 2>/dev/null | grep -q "^group:$GRP:"; then
    fail "group-x ancestor (dir group == sharing group) stays untouched"
else
    pass "group-x ancestor (dir group == sharing group) stays untouched"
fi
FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$TR/gx/proj" "$GRP" >/dev/null 2>&1
# Guarded count (#260, the #244 f W1 class): zero entries (the
# idempotence regression this pins) aborted under set -e before
# assert_eq could record the FAIL.
_n=$(getfacl -p "$TR" 2>/dev/null | grep -c "^group:$GRP:--x" || true)
assert_eq "traverse grant is idempotent (single ACL entry)" "1" "$_n"
rm -rf "$TR"

# --- 7b. mid-batch failure fails the baseline (0.0.44a V9) ---------------------------
# One failing setfacl entry MID-batch must fail the pass: the inner xargs
# loop used to return only the LAST command's status — a broken entry
# followed by healthy ones stayed green, the caller printed "applied"
# over an incomplete baseline (REVIEW-B W5's falsified premise). A stub
# fails exactly one operand; the rest delegate to the real setfacl.
V9ROOT=$(mktemp -d)
mkdir -p "$V9ROOT/d1" "$V9ROOT/d2" "$V9ROOT/d3"
chmod 700 "$V9ROOT" "$V9ROOT/d1" "$V9ROOT/d2" "$V9ROOT/d3"
STUBBIN=$(mktemp -d)
REAL_SETFACL="$(command -v setfacl)"
cat >"$STUBBIN/setfacl" <<EOF
#!/bin/sh
case "\$*" in *"/d2"*) exit 1 ;; esac
exec "$REAL_SETFACL" "\$@"
EOF
chmod +x "$STUBBIN/setfacl"
_mb_rc=0
FS_SUDO="" PATH="$STUBBIN:$PATH" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$V9ROOT" "$GRP" >/dev/null 2>&1 ||
    _mb_rc=$?
assert_eq "mid-batch ACL failure fails the baseline (V9)" "1" "$_mb_rc"
rm -rf "$V9ROOT" "$STUBBIN"

# --- 7c. the batch loop fails on a MIDDLE entry regardless of find order (0.0.44b W11) ----
# The V9 stub test is find-order-dependent (readdir decides which operand
# is batch-final). The loop body itself is extracted and executed with a
# FIXED operand list: a failing middle entry must fail the batch, a
# symlink-last batch must not.
_batch_body=$(sed -n '/^                _n=\$1; shift$/,/^                \[ "\$_fail" -eq 0 \]$/p' "$LIB")
if [ -n "$_batch_body" ]; then
    pass "fs-baseline: batch loop body extractable (W11)"
    _bstub=$(mktemp -d)
    cat >"$_bstub/failmid" <<'EOS'
#!/bin/sh
case "$1" in *midfail*) exit 1 ;; esac
exit 0
EOS
    chmod +x "$_bstub/failmid"
    _brc=0
    # Root arg is deliberately a path that cannot exist (#211 b W27):
    # the W11 drives assert batch rc semantics, not root-relative walks
    # — an absent root keeps the drives about the operands alone.
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 midfail ok2 || _brc=$?
    assert_eq "mid-batch failure fails the batch, order-independent (W11)" "1" "$_brc"
    _brc=0
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 ok2 || _brc=$?
    assert_eq "all-healthy batch stays green (W11)" "0" "$_brc"
    ln -sf /etc/hostname "$_bstub/lnk"
    _brc=0
    sh -c "$_batch_body" xargs-sh 1 /nonexistent-opk-root "$_bstub/failmid" ok1 "$_bstub/lnk" || _brc=$?
    assert_eq "symlink-last batch stays green (skip is not a failure)" "0" "$_brc"
    rm -rf "$_bstub"
else
    fail "fs-baseline: batch loop body extractable (W11)"
fi

# --- 7d. nailed .git pointer: the sharing passes skip it (#758) -------------------------
# A git-protection pointer (.git as a regular FILE, chattr +i — #704/
# PR #754) refuses chgrp/chmod even for root: before the skip, the
# chgrp and files-g+rw passes failed rc 123 on every such project and
# the whole refresh aborted with "N baseline pass(es) failed". lsattr
# is a PATH stub here (per-file .nailed marker — the controlled-PATH
# rule; the real chattr needs capabilities the unit sandbox lacks).
# Fixtures keep mode 600: the files pass would land 660 if it ran —
# the skip's observable. Three discriminators in one run: the nailed
# pointer stays 600 (skip), the unnailed worktree-registration pointer
# lands 660 (no i flag — normal operand), and a classic .git DIRECTORY
# carrying the same marker lands 3770 (the skip is file-only).
GP7D="$WORK/gp7d"
GP7DBIN="$WORK/gp7dbin"
mkdir -p "$GP7D/proj" "$GP7D/wt" "$GP7D/classic/.git" "$GP7DBIN"
printf 'gitdir: /var/tmp/gp7d-storage/proj.git\n' >"$GP7D/proj/.git"
printf 'gitdir: /var/tmp/gp7d-storage/x.git/worktrees/wt\n' >"$GP7D/wt/.git"
printf 'a\n' >"$GP7D/proj/file.txt"
touch "$GP7D/proj/.git.nailed" "$GP7D/classic/.git.nailed"
chmod 600 "$GP7D/proj/.git" "$GP7D/wt/.git" "$GP7D/proj/file.txt"
chmod 700 "$GP7D/classic/.git"
cat >"$GP7DBIN/lsattr" <<'EOS'
#!/bin/sh
# lsattr stub (#758): real output shape (flags grid, space, path);
# i is rendered iff a "<path>.nailed" marker exists.
for _la in "$@"; do
    if [ -e "$_la.nailed" ]; then
        printf -- '----i--------------- %s\n' "$_la"
    else
        printf -- '-------------------- %s\n' "$_la"
    fi
done
exit 0
EOS
chmod 755 "$GP7DBIN/lsattr"
GP7DOUT="$(PATH="$GP7DBIN:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$GP7D" "$GRP" 2>&1)"
if printf '%s\n' "$GP7DOUT" | grep -qF 'BASELINE-RC0'; then
    pass "7d: baseline over a nailed pointer completes rc 0 (#758)"
else
    fail "7d: baseline aborted on the nailed pointer (out: $GP7DOUT)"
fi
if printf '%s\n' "$GP7DOUT" | grep -qF 'hit errors'; then
    fail "7d: pass-failure warn present over the pointer (out: $GP7DOUT)"
else
    pass "7d: no pass-failure warn over the pointer (#758)"
fi
assert_eq "7d: nailed pointer NOT touched by the passes (600 stays)" "600" \
    "$(stat -c %a "$GP7D/proj/.git")"
assert_eq "7d: unnailed pointer stays a normal operand (600 -> 660)" "660" \
    "$(stat -c %a "$GP7D/wt/.git")"
assert_eq "7d: regular files still shared (600 -> 660)" "660" \
    "$(stat -c %a "$GP7D/proj/file.txt")"
assert_eq "7d: classic .git dir with the same marker is NOT skipped (2770+sticky)" "3770" \
    "$(stat -c %a "$GP7D/classic/.git")"
# Companion drive (#760 a C1): the INERT arm — a failing or absent
# lsattr leaves the pointer a normal operand. The stub fails rc 1
# with no stdout (the empty-_lsv shape a missing or failing lsattr
# produces; the not-found variant differs only in how the emptiness
# arises — both suppress through the 2>/dev/null and match no *i*).
# §7d above left proj/.git at 600 (the skip arm ran); this drive must
# EXECUTE the operand and land 660 — a regressed gate (e.g. one that
# defaults the empty field, ${_lsv:-i}) would keep 600 and red here.
GP7DNO="$WORK/gp7dno"
mkdir -p "$GP7DNO"
cat >"$GP7DNO/lsattr" <<'EOS'
#!/bin/sh
# failing lsattr: no stdout, rc 1 (unsupported fs / absent-tool shape)
exit 1
EOS
chmod 755 "$GP7DNO/lsattr"
GP7DNOUT="$(PATH="$GP7DNO:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$GP7D" "$GRP" 2>&1)"
if printf '%s\n' "$GP7DNOUT" | grep -qF 'BASELINE-RC0'; then
    pass "7d: failing lsattr keeps the baseline green (inert arm)"
else
    fail "7d: failing lsattr aborted the baseline (out: $GP7DNOUT)"
fi
if printf '%s\n' "$GP7DNOUT" | grep -qF 'hit errors'; then
    fail "7d: pass-failure warn under failing lsattr (out: $GP7DNOUT)"
else
    pass "7d: no pass-failure warn under failing lsattr"
fi
assert_eq "7d: failing lsattr runs the pointer operand (600 -> 660, inert arm)" "660" \
    "$(stat -c %a "$GP7D/proj/.git")"

# --- 8. Makefile + CI wiring -----------------------------------------------------------
# Chain membership via the wrapped test: span (issue #464): a bare grep
# would also match the suite's .PHONY line and pass without membership --
# the awk span reads the test: block only.
_test_chain="$(test_chain "$MAKEFILE")"
echo "$_test_chain" | grep -qxF 'test-fs-baseline' &&
    pass "Makefile test target includes test-fs-baseline" ||
    fail "Makefile test target includes test-fs-baseline"
live_src "$TEST_CI" | grep -q 'tests/unit/test-fs-baseline.sh' &&
    pass "test-unit.yml run step includes the new test" ||
    fail "test-unit.yml run step includes the new test"
# fs-baseline.sh is a sourced lib (install.sh, config.sh, update.sh) —
# per the repo invariant (755 <=> executed by path) it must be 100644.
[ "$(git -C "$SCRIPT_DIR/../.." ls-files -s -- files/opencode-permissions-kit-lib/sh/fs-baseline.sh | cut -d' ' -f1)" = "100644" ] &&
    pass "fs-baseline.sh is a sourced lib (git 100644, not executed by path)" ||
    fail "fs-baseline.sh is a sourced lib (git 100644, not executed by path)"

# --- 8b. exec-time symlink recheck (0.0.39e S1) -----------------------------------------
# The leaf race (swap between find's scan and xargs' exec) cannot be
# scripted deterministically via stream interleaving — what CAN be
# asserted is the guard: the consumer re-tests [ -L ] immediately before
# running the command, so a path that is a symlink AT EXEC TIME is
# skipped even when find's expression matched it. (The PARENT-swap form
# IS scripted deterministically — section 9's wrapper find performs the
# swap between scan output and replay.) Simulate by driving _fsb_pass
# with an expression (-true) that deliberately includes symlinks: the
# target OUTSIDE the root must keep its mode, the regular file inside
# must not.
SW=$(mktemp -d)
mkdir -p "$SW/root"
printf 'inside\n' >"$SW/root/in-file"
chmod 600 "$SW/root/in-file"
printf 'target\n' >"$SW/target" # outside the pass root below
chmod 600 "$SW/target"
ln -s "$SW/target" "$SW/root/link" # symlink INSIDE the pass root
FS_SUDO="" sh -c '. "$1" && _fsb_pass "test" "$2" -true -- chmod g+rw' _ "$LIB" "$SW/root" >/dev/null 2>&1
if [ "$(stat -c %a "$SW/target")" = "600" ]; then
    pass "exec-time recheck: symlink operands are skipped — target outside the root untouched"
else
    fail "exec-time recheck: symlink operands are skipped — target outside the root untouched (mode now $(stat -c %a "$SW/target"))"
fi
if [ "$(stat -c %a "$SW/root/in-file")" = "660" ]; then
    pass "exec-time recheck: regular files inside the pass root still processed (chain works)"
else
    fail "exec-time recheck: regular files still processed (mode $(stat -c %a "$SW/root/in-file"))"
fi
rm -rf "$SW"

# --- 8c. pass failures propagate (0.0.43a F10) ----------------------------------------
# A wholesale pass failure used to be invisible (pipeline status dropped,
# unconditional return 0) while callers printed "applied" regardless. Now:
# a failing per-path command warns per pass, the summary names the root,
# and fs_baseline_root exits non-zero (install/config/update fail loud
# under set -e instead of lying green).
FB="$WORK/failroot"
mkdir -p "$FB/root"
printf 'x\n' >"$FB/root/f"
STUBS="$WORK/failstubs"
mkdir -p "$STUBS"
cat >"$STUBS/setfacl" <<'EOF'
#!/bin/sh
echo "setfacl stub: deliberate failure" >&2
exit 1
EOF
chmod +x "$STUBS/setfacl"
FBOUT="$(PATH="$STUBS:$PATH" FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3" && echo BASELINE-RC0' \
    _ "$LIB" "$FB/root" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$FBOUT" | grep -q BASELINE-RC0; then
    fail "a failing pass must propagate a non-zero exit"
else
    pass "a failing pass must propagate a non-zero exit"
fi
if printf '%s\n' "$FBOUT" | grep -qF 'baseline pass "default ACLs" hit errors'; then
    pass "the failing pass is named in the warn line"
else
    fail "the failing pass is named in the warn line"
fi
if printf '%s\n' "$FBOUT" | grep -qF 'may be incomplete'; then
    pass "the summary names the root and the risk"
else
    fail "the summary names the root and the risk"
fi
rm -rf "$FB" "$STUBS"

# A missing required tool dies loudly BEFORE any pass runs (the old code
# lost find's failure inside the redirected pipeline and xargs -r happily
# no-op'd on empty input). PATH is narrowed INSIDE the subshell so the
# /bin/sh invocation itself stays resolvable.
EMPTY="$WORK/emptypath"
mkdir -p "$EMPTY"
MTOUT="$(FS_SUDO="" /bin/sh -c '. "$1" && PATH="$2" && fs_baseline_root "$3" "$4"' \
    sh "$LIB" "$EMPTY" "$WORK/proj" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$MTOUT" | grep -qF 'required tool missing for the group baseline: find'; then
    pass "a missing tool is reported before any pass runs"
else
    fail "a missing tool is reported before any pass runs"
fi
rm -rf "$EMPTY"

# A find that DIES wholesale mid-walk with an empty stream (0.0.43b W4):
# xargs -r no-ops green on empty input, so the old pipeline rc said
# nothing — the baseline printed "applied" over a walk that never ran.
# The temp-file restructure tracks find's own rc.
DEAD="$WORK/deadfind"
mkdir -p "$DEAD"
cat >"$DEAD/find" <<'EOF'
#!/bin/sh
echo "find stub: simulated wholesale failure" >&2
exit 1
EOF
chmod +x "$DEAD/find"
DFOUT="$(FS_SUDO="" /bin/sh -c '. "$1" && PATH="$2:$PATH" && fs_baseline_root "$3" "$4" && echo BASELINE-RC0' \
    sh "$LIB" "$DEAD" "$WORK/proj" "$(id -gn)" 2>&1 || true)"
if printf '%s\n' "$DFOUT" | grep -q BASELINE-RC0; then
    fail "a wholesale find failure must propagate a non-zero exit (W4)"
else
    pass "a wholesale find failure must propagate a non-zero exit (W4)"
fi
if printf '%s\n' "$DFOUT" | grep -qF 'baseline pass "chgrp" hit errors (rc 1)'; then
    pass "the dead find is attributed to its pass with its rc (W4)"
else
    fail "the dead find is attributed to its pass with its rc (W4)"
fi
if printf '%s\n' "$DFOUT" | grep -qF 'simulated wholesale failure'; then
    pass "find's stderr survives for diagnosis (the why behind the rc)"
else
    fail "find's stderr survives for diagnosis (the why behind the rc)"
fi
rm -rf "$DEAD"

# --- 9. parent-swap race: component walk (#211 a F1, 0.0.39h F2 class) ------------------
# The scan->act window spans the whole temp-file replay, and the agent
# can swap a PARENT directory for a symlink inside it: find recorded
# proj/x/y/secret as a regular file, then x/y becomes a link to a dir
# OUTSIDE the tree — the operand now resolves there, and the leaf-only
# [ -L ] recheck passes (the leaf is a regular file). Deterministic
# seam: a PATH-stubbed find runs the REAL find (paths land in the temp
# file), performs the swap, then exits — the replay then chews stale
# paths. Without the component walk, chmod g+w hits the victim (mode
# 600 -> 620); with it, the operand is skipped and the pass stays green
# (a skip is not a failure).
F1DIR=$(mktemp -d)
F1STUB=$(mktemp -d)
F1REAL="$(command -v find)"
mkdir -p "$F1DIR/proj/x/y" "$F1DIR/victim"
printf 'secret\n' >"$F1DIR/proj/x/y/secret"
printf 'victim\n' >"$F1DIR/victim/secret"
chmod 600 "$F1DIR/proj/x/y/secret" "$F1DIR/victim/secret"
cat >"$F1STUB/find" <<EOF
#!/bin/sh
"$F1REAL" "\$@"
_rc=\$?
if [ -d "$F1DIR/proj/x/y" ] && [ ! -L "$F1DIR/proj/x/y" ]; then
    mv "$F1DIR/proj/x/y" "$F1DIR/proj/x/moved-away"
    ln -s "$F1DIR/victim" "$F1DIR/proj/x/y"
fi
exit \$_rc
EOF
chmod +x "$F1STUB/find"
F1RC=0
# Slashed root on purpose (#211 b W7): this one drive covers both the
# a F1 walk (victim keeps its mode only when the walk runs) and the
# b W7 normalization (an unnormalized root voids the walk pattern —
# victim would go 620).
FS_SUDO="" PATH="$F1STUB:$PATH" \
    sh -c '. "$1" && _fsb_pass "parent-swap" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1DIR/proj/" >/dev/null 2>&1 || F1RC=$?
if [ -f "$F1DIR/proj/x/moved-away/secret" ] && [ -L "$F1DIR/proj/x/y" ]; then
    pass "race fixture: parent swapped between scan and replay (seam fired)"
else
    fail "race fixture: parent swapped between scan and replay (seam fired)"
fi
assert_eq "parent-swap: victim outside the tree keeps its mode (#211 a F1)" "600" \
    "$(stat -c %a "$F1DIR/victim/secret")"
assert_eq "parent-swap: skipped operand does not fail the pass (rc 0)" "0" "$F1RC"
rm -rf "$F1DIR" "$F1STUB"

# --- 9b. root-swap race: worker-head scan-root recheck (#421) -----------------------
# The #421 shape: the 9 walk (a F1) starts BELOW the scan root, so a
# ROOT swapped for a symlink between find and the batch redirected
# every walk test — and the command — through it, where components
# are real directories and no gate fires. Same deterministic seam as
# 9: the stub find runs the REAL find, then swaps the ROOT itself,
# then exits — the replay then starts with a linked root. The worker
# head must refuse the batch LOUD: the victim keeps its mode, the
# pass FAILS (a redirected batch is never a skip), the message names
# the swap.
F2DIR=$(mktemp -d)
F2STUB=$(mktemp -d)
F2REAL="$(command -v find)"
mkdir -p "$F2DIR/proj" "$F2DIR/victim"
printf 'scanned\n' >"$F2DIR/proj/file"
printf 'victim\n' >"$F2DIR/victim/file"
chmod 600 "$F2DIR/victim/file"
cat >"$F2STUB/find" <<EOF
#!/bin/sh
"$F2REAL" "\$@"
_rc=\$?
if [ -d "$F2DIR/proj" ] && [ ! -L "$F2DIR/proj" ]; then
    mv "$F2DIR/proj" "$F2DIR/proj-moved"
    ln -s "$F2DIR/victim" "$F2DIR/proj"
fi
exit \$_rc
EOF
chmod +x "$F2STUB/find"
F2RC=0
F2MSG=$(FS_SUDO="" PATH="$F2STUB:$PATH" \
    sh -c '. "$1" && _fsb_pass "root-swap" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F2DIR/proj" 2>&1) || F2RC=$?
if [ -d "$F2DIR/proj-moved" ] && [ -L "$F2DIR/proj" ]; then
    pass "root-swap fixture: the scan root was swapped between find and replay (#421 seam)"
else
    fail "root-swap fixture: the scan root was swapped between find and replay (#421 seam)"
fi
assert_eq "root-swap: victim outside the tree keeps its mode (#421)" "600" \
    "$(stat -c %a "$F2DIR/victim/file")"
if [ "$F2RC" -eq 0 ] &&
    printf '%s' "$F2MSG" | grep -qF "scan root $F2DIR/proj was replaced by a symlink" &&
    printf '%s' "$F2MSG" | grep -qF 'baseline pass "root-swap" hit errors'; then
    pass "root-swap: the batch is refused loud, the pass counts the error (#421)"
else
    fail "root-swap: the batch is refused loud, the pass counts the error (#421; rc=$F2RC out=$F2MSG)"
fi
rm -rf "$F2DIR" "$F2STUB"

# Root '/' is refused loud, never walked (#211 b W7): the refusal fires
# before any find runs — nothing on the host is touched.
F1RRC=0
F1RMSG=$(FS_SUDO="" sh -c '. "$1" && _fsb_pass "refuse" "/" -type f -- chmod g+w' _ "$LIB" 2>&1) || F1RRC=$?
assert_eq "root / refused: rc 1 (#211 b W7)" "1" "$F1RRC"
case "$F1RMSG" in
    *never*) pass "root / refused: loud message (#211 b W7)" ;;
    *) fail "root / refused: loud message (got: $F1RMSG)" ;;
esac
# The message must name the refused ROOT (#211 c W2): the shift at the
# prologue renumbers positionals, so a ${_fsbp_root:-$2} fallback named
# a find-expression word instead ('/' drive) — and the '//' drive shows
# the ORIGINAL form, proving the capture happened before the shift.
case "$F1RMSG" in
    *"refusing scan root '/'"*) pass "root / refused: names the refused root (#211 c W2)" ;;
    *) fail "root / refused: names the refused root (got: $F1RMSG) (#211 c W2)" ;;
esac
F1R2RC=0
F1R2MSG=$(FS_SUDO="" sh -c '. "$1" && _fsb_pass "refuse" "//" -type f -- chmod g+w' _ "$LIB" 2>&1) || F1R2RC=$?
assert_eq "root // refused: rc 1 (#211 c W2)" "1" "$F1R2RC"
case "$F1R2MSG" in
    *"refusing scan root '//'"*) pass "root // refused: original form named (#211 c W2)" ;;
    *) fail "root // refused: original form named (got: $F1R2MSG) (#211 c W2)" ;;
esac

# Walker string safety: components and names with spaces flow through
# the prefix-peeling without word splitting — the chmod still applies.
# rc captured (#211 b W13): the drive used to run unguarded under the
# suite's set -e, aborting the whole suite pre-tally on a walker
# regression instead of recording a FAIL.
F1SP=$(mktemp -d)
mkdir -p "$F1SP/proj/a/dir two"
printf 's\n' >"$F1SP/proj/a/dir two/has space.txt"
chmod 600 "$F1SP/proj/a/dir two/has space.txt"
F1SPRC=0
FS_SUDO="" sh -c '. "$1" && _fsb_pass "spaces" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1SP/proj" >/dev/null 2>&1 || F1SPRC=$?
assert_eq "walker: spaces drive exits 0 (#211 b W13)" "0" "$F1SPRC"
assert_eq "walker: spaces in components and names survive the walk" "620" \
    "$(stat -c %a "$F1SP/proj/a/dir two/has space.txt")"
rm -rf "$F1SP"

# Spaced-path PARENT-SWAP RACE (external mini-review follow-up, post-b):
# the happy-path drive above proves chmod still APPLIES on spaced paths
# (620) — it cannot notice a walk regression that silently stops SKIPPING
# (the operand still chmods, the pin stays green; the b W6 class, missed
# on this pin), and the a F1 race fixture drives unspaced paths only.
# Same deterministic seam as section 9, with spaces in every component:
# find records the operand, the stub swaps the parent for a symlink to a
# victim dir OUTSIDE the tree — the walk must skip (victim stays 600);
# a word-splitting or voided walk chmods through the link (victim 620).
F1SPD=$(mktemp -d)
F1SPS=$(mktemp -d)
mkdir -p "$F1SPD/proj/a/dir two" "$F1SPD/victim dir"
printf 'secret\n' >"$F1SPD/proj/a/dir two/has space.txt"
printf 'victim\n' >"$F1SPD/victim dir/has space.txt"
chmod 600 "$F1SPD/proj/a/dir two/has space.txt" "$F1SPD/victim dir/has space.txt"
cat >"$F1SPS/find" <<EOF
#!/bin/sh
"$(command -v find)" "\$@"
_rc=\$?
if [ -d "$F1SPD/proj/a/dir two" ] && [ ! -L "$F1SPD/proj/a/dir two" ]; then
    mv "$F1SPD/proj/a/dir two" "$F1SPD/proj/a/moved away"
    ln -s "$F1SPD/victim dir" "$F1SPD/proj/a/dir two"
fi
exit \$_rc
EOF
chmod +x "$F1SPS/find"
F1SPDRC=0
FS_SUDO="" PATH="$F1SPS:$PATH" \
    sh -c '. "$1" && _fsb_pass "spaces-race" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F1SPD/proj" >/dev/null 2>&1 || F1SPDRC=$?
if [ -f "$F1SPD/proj/a/moved away/has space.txt" ] && [ -L "$F1SPD/proj/a/dir two" ]; then
    pass "spaces race: seam fired (parent swapped between scan and replay)"
else
    fail "spaces race: seam fired (parent swapped between scan and replay)"
fi
assert_eq "spaces race: victim outside the tree keeps its mode (walk skips)" "600" \
    "$(stat -c %a "$F1SPD/victim dir/has space.txt")"
assert_eq "spaces race: skip is not a failure (rc 0)" "0" "$F1SPDRC"
rm -rf "$F1SPD" "$F1SPS"

# --- 10. pass scratch registered with the caller's cleanup trap (#211 a F12) ------
# _fsb_pass's NUL temp was a plain mktemp + rm: an aborted pass (Ctrl-C
# during the minutes-long walk) left the root-owned file in /tmp. The
# staged-write shape registers it with the caller's _tmp_track trap.
# Pin: source the real lib with a RECORDING _tmp_track, run one pass,
# assert the opk-fsb-pass temp was registered.
F12S=$(mktemp -d)
mkdir -p "$F12S/root"
printf 'x\n' >"$F12S/root/f"
F12_TRACK="$F12S/tracked" FS_SUDO="" \
    sh -c '. "$1" && _tmp_track() { printf "%s\n" "$1" >> "$F12_TRACK"; } \
    && _fsb_pass "f12" "$2" -type f -- chmod g+w' \
    _ "$LIB" "$F12S/root" >/dev/null 2>&1 || true
if grep -q 'opk-fsb-pass' "$F12S/tracked" 2>/dev/null; then
    pass "pass scratch registered with _tmp_track (#211 a F12)"
else
    fail "pass scratch registered with _tmp_track (#211 a F12)"
fi
rm -rf "$F12S"

# --- 10b. dead TMPDIR: named-cause error, pass counted, nothing applied (#431) --
# The #429 B4 class beyond the update scope: every shipped caller of
# _fsb_pass runs set -eu — a raw mktemp failure aborted the pass
# mid-run with only mktemp's own diagnostic. The guard names the
# interrupted pass in the family wording and books it like a failed
# pass (F10 counting) so fs_baseline_root's summary fails the whole
# baseline loud. Inject an uncreatable TMPDIR (uid-independent);
# assert the message, the _FSB_ERRORS bookkeeping and that the chmod
# operand stayed UNTOUCHED (no partial application).
F13S=$(mktemp -d)
mkdir -p "$F13S/root"
printf 'x\n' >"$F13S/root/f"
chmod 644 "$F13S/root/f"
F13RC=0
F13OUT=$(FS_SUDO="" _FSB_ERRORS=0 TMPDIR="/nonexistent-431-fsb-$$" \
    sh -c '. "$1" && _fsb_pass "f13" "$2" -type f -- chmod g+w; echo "ERRS=$_FSB_ERRORS"' \
    _ "$LIB" "$F13S/root" 2>&1) || F13RC=$?
if printf '%s\n' "$F13OUT" | grep -qF 'error: mktemp failed (is $TMPDIR writable?) — baseline pass "f13"' &&
    printf '%s\n' "$F13OUT" | grep -qF 'cannot run' &&
    printf '%s\n' "$F13OUT" | grep -q '^ERRS=1$' &&
    [ "$(stat -c %a "$F13S/root/f" 2>/dev/null)" = "644" ]; then
    pass "dead TMPDIR: pass error named + counted, operand untouched (#431)"
else
    fail "dead TMPDIR pass guard (rc=$F13RC out=$F13OUT mode=$(stat -c %a "$F13S/root/f" 2>/dev/null)) (#431)"
fi
rm -rf "$F13S"

# --- 10c. heal-sidecar mktemp guards, failure legs EXECUTED (#818 a S1) ---------
# The #431 pin covers the PASS guards; S1 added three heal-sidecar
# guards whose named-cause arms need their own executed leg (L1). A
# PATH-stubbed mktemp serves the first two opk-fsb-heal calls (the
# driver and gitdir bases) and fails every later heal-template call:
# the gitdir sidecar guard fires ("cannot scan <gitdir>", the gitdir
# heal skips, ERRS+1) and the driver's symlinked-.git sidecar guard
# fires after the loop ("cannot run the symlinked-.git scan", ERRS+1)
# — the whole baseline fails loud (F10), never a partial-heal green.
# Pass templates (opk-fsb-pass) delegate to the real mktemp untouched.
F14S=$(mktemp -d)
mkdir -p "$F14S/bin" "$F14S/proj/.git/hooks" "$F14S/proj/.git/modules/real"
printf 'c\n' >"$F14S/proj/.git/config"
printf 'x\n' >"$F14S/proj/.git/modules/real/config"
F14MK="$F14S/mk-count"
cat >"$F14S/bin/mktemp" <<EOF
#!/bin/sh
case "\$*" in
*opk-fsb-heal*)
    _n=\$(cat "$F14MK" 2>/dev/null || echo 0)
    _n=\$((_n + 1))
    printf '%s\n' "\$_n" >"$F14MK"
    if [ "\$_n" -ge 3 ]; then
        echo "mktemp stub: S1 sidecar failure leg" >&2
        exit 1
    fi
    ;;
esac
exec $(command -v mktemp) "\$@"
EOF
chmod 755 "$F14S/bin/mktemp"
F14RC=0
F14OUT=$(FS_SUDO="" PATH="$F14S/bin:$PATH" \
    sh -c '. "$1" && _FSB_ERRORS=0 && fs_baseline_root "$2" "$3"; echo "ERRS=$_FSB_ERRORS"' \
    _ "$LIB" "$F14S/proj" "$(id -gn)" 2>&1) || F14RC=$?
if printf '%s\n' "$F14OUT" | grep -qF "error: mktemp failed (is \$TMPDIR writable?) — the git heal cannot scan $F14S/proj/.git" &&
    printf '%s\n' "$F14OUT" | grep -qF "error: mktemp failed (is \$TMPDIR writable?) — the git heal cannot run the symlinked-.git scan under $F14S/proj" &&
    printf '%s\n' "$F14OUT" | grep -q '^ERRS=2$' &&
    printf '%s\n' "$F14OUT" | grep -qF 'baseline pass(es) failed'; then
    pass "heal sidecar mktemp guards fire loud, count, and fail the baseline (#818 a S1)"
else
    fail "heal sidecar mktemp guards (rc=$F14RC out=$F14OUT) (#818 a S1)"
fi
rm -rf "${F14S:?}"

# --- 11. python3 health gate (#223, #221 a W3 shape) ----------------------------------
# _fsb_count_tee sits in the DATA pipeline of a MUTATING pass: an
# ungated missing-or-broken python3 killed the tee at startup, xargs -r
# no-oped GREEN on the empty stream, and the baseline was silently not
# applied (false-green at a root-run site — recorded as the W3 sibling
# in the pr-00221 resolution). The gate probes health once per run and
# degrades the tee to a plain passthrough. Marker FILE, not stderr: the
# production probe discards its own stderr (L1 — observe the way
# production does; the marker lesson of #221 pin 7).
W23="$WORK/issue223"
W23BIN="$WORK/issue223-bin"
W23PROBE="$WORK/issue223-probe.log"
mkdir -p "$W23BIN" "$W23/proj/sub"
chmod 700 "$W23/proj" "$W23/proj/sub"
printf 'gate\n' >"$W23/proj/f"
chmod 600 "$W23/proj/f"
printf '#!/bin/sh\necho probe >> "%s"\nexit 9\n' "$W23PROBE" >"$W23BIN/python3"
chmod +x "$W23BIN/python3"
rm -f "$W23PROBE"
W23RC=0
W23OUT="$(PATH="$W23BIN:$PATH" FS_SUDO="" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23/proj" "$(id -gn)" 2>&1)" ||
    W23RC=$?
assert_eq "#223 broken python3: baseline still applies (rc 0, no false green)" "0" "$W23RC"
assert_eq "#223 broken python3: file got group rw (600 -> 660 — the gate fed xargs)" "660" \
    "$(stat -c %a "$W23/proj/f")"
# Probe count: 2 = the cached probe + the diagnostic rerun (#244 c
# S3, the installer gate's #244 b-S2 shape) — the rerun is a deliberate
# second interpreter EXECUTION on the failure path. The cache is still
# pinned: without it this would read 8 (2 × four passes).
assert_eq "#223 broken python3: probe+rerun ran exactly once per run (cache across the four passes)" "2" \
    "$(wc -l <"$W23PROBE" 2>/dev/null || echo 0)"
assert_eq "#223 broken python3: degradation warn exactly once per run" "1" \
    "$(printf '%s\n' "$W23OUT" | grep -c 'live progress unavailable')"
if printf '%s\n' "$W23OUT" | grep -q 'Traceback'; then
    fail "#223 broken python3: no traceback on the fallback path"
else
    pass "#223 broken python3: no traceback on the fallback path"
fi
# ...and the healthy path through the SAME fixture still counts (the
# gate must not eat the tee when python3 is fine — rc + done-line):
W23RC2=0
W23OUT2="$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23/proj" "$(id -gn)" 2>&1)" ||
    W23RC2=$?
assert_eq "#223 healthy python3: baseline applies (control for the gate)" "0" "$W23RC2"
if printf '%s\n' "$W23OUT2" | grep -q 'chgrp *[0-9]* entries — done'; then
    pass "#223 healthy python3: live counter still runs (gate passes the tee through)"
else
    fail "#223 healthy python3: live counter still runs (gate ate the tee)"
fi
rm -rf "$W23" "$W23BIN"
rm -f "$W23PROBE"

# --- 11b. python3 absent entirely (restricted PATH, no shim) ---------------------------
# "missing" and "broken" are different probe outcomes: a PATH without
# any python3 must take the same bare fallback. Controlled PATH per the
# sandbox rules (tests/AGENTS.md "Test sandbox"): symlinks to the few
# externals the baseline needs, python3 deliberately absent.
W23NP="$WORK/issue223-nopy"
W23NPBIN="$WORK/issue223-nopy-bin"
mkdir -p "$W23NPBIN" "$W23NP/proj"
chmod 700 "$W23NP/proj"
printf 'nopy\n' >"$W23NP/proj/f"
chmod 600 "$W23NP/proj/f"
for _t in sh find cat chgrp chmod setfacl chown mktemp dirname stat getfacl grep rm xargs wc; do
    ln -s "$(command -v "$_t")" "$W23NPBIN/$_t"
done
W23NPRC=0
W23NPOUT="$(FS_SUDO="" PATH="$W23NPBIN" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23NP/proj" "$(id -gn)" 2>&1)" ||
    W23NPRC=$?
assert_eq "#223 python3 absent: baseline still applies (rc 0)" "0" "$W23NPRC"
assert_eq "#223 python3 absent: file got group rw (600 -> 660)" "660" \
    "$(stat -c %a "$W23NP/proj/f")"
assert_eq "#223 python3 absent: degradation warn exactly once" "1" \
    "$(printf '%s\n' "$W23NPOUT" | grep -c 'live progress unavailable')"

# Missing cat is now loud TOO (the fallback pipes the pass through it —
# a missing cat would rebuild the exact empty-stream false-green the
# gate closes): same restricted bin minus cat, probed BEFORE walking.
W23NPBIN2="$WORK/issue223-nopy-bin2"
mkdir -p "$W23NPBIN2"
# reset the fixture the 11b run already baselined: the loud abort must
# leave the file at 600, proving no pass ran at all
chmod 600 "$W23NP/proj/f"
for _t in sh find chgrp chmod setfacl chown mktemp dirname stat getfacl grep rm xargs wc; do
    ln -s "$(command -v "$_t")" "$W23NPBIN2/$_t"
done
W23CATRC=0
W23CATOUT="$(FS_SUDO="" PATH="$W23NPBIN2" \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23NP/proj" "$(id -gn)" 2>&1)" ||
    W23CATRC=$?
assert_eq "#223 missing cat: fails loud before any pass runs" "1" "$W23CATRC"
if printf '%s\n' "$W23CATOUT" | grep -qF 'required tool missing for the group baseline: cat'; then
    pass "#223 missing cat: the error names cat"
else
    fail "#223 missing cat: the error names cat (got: $W23CATOUT)"
fi
assert_eq "#223 missing cat: nothing applied (file keeps 600)" "600" \
    "$(stat -c %a "$W23NP/proj/f")"
rm -rf "$W23NP" "$W23NPBIN" "$W23NPBIN2"

# --- 11c. dead consumer ends the tee silently (#223 rider, pr-00221 W2/W6) -------------
# The tee had no except clause: a downstream xargs dying first ended it
# in a BrokenPipeError traceback. 1 MiB input (beyond the pipe buffer)
# against a reader that exits at once fires EPIPE deterministically —
# the reader is gone before python finishes starting. stderr is
# captured at the ENCLOSING sh -c: a redirect on the pipeline's last
# member would capture only the reader's stderr and prove nothing.
# Sabotage (drop the except clause) drops a Traceback into the asserted
# file; the devnull dup2 in the clause keeps the interpreter's own
# shutdown flush quiet too ("Exception ignored").
W23BP="$WORK/issue223-bp"
python3 -c 'import sys; sys.stdout.buffer.write(b"e\0" * 524288)' >"$W23BP"
FS_SUDO="" sh -c '. "$1" && _fsb_count_tee bp < "$2" | sh -c "exit 0"' \
    _ "$LIB" "$W23BP" >/dev/null 2>"$W23BP.err"
# rc assert dropped (#244 a Q5): under this suite's dash (no pipefail)
# the reader rc is 0 regardless of tee behavior — dead weight that
# could never fail. The stderr greps below are the discriminators.
if grep -q 'Traceback\|Exception ignored' "$W23BP.err"; then
    fail "#223 broken pipe: tee dies silently when xargs goes first"
else
    pass "#223 broken pipe: tee dies silently when xargs goes first"
fi
# No completion line for an aborted pass (#244 a S2/W3/Q4): counted is
# bytes READ, not entries applied — the consumer died mid-stream.
if grep -q '— done' "$W23BP.err"; then
    fail "#244 broken pipe: no completion line for an aborted pass"
else
    pass "#244 broken pipe: no completion line for an aborted pass"
fi
# Production-shape rider (#244 a Q1): install/update/config run bash
# WITH pipefail — the tee must exit 0 on EPIPE or a green pass fails
# through the old traceback rc. Environment-dependent (L4b): skipped
# with a note where bash is absent.
if command -v bash >/dev/null 2>&1; then
    W23PFRC=0
    FS_SUDO="" bash -c 'set -o pipefail; . "$1" && _fsb_count_tee pf < "$2" | sh -c "exit 0"' \
        _ "$LIB" "$W23BP" >/dev/null 2>&1 || W23PFRC=$?
    assert_eq "#244 pipefail rider: tee exits 0 on EPIPE under bash pipefail" "0" "$W23PFRC"
else
    echo "  note: bash absent — pipefail rider skipped (#244 a Q1)"
fi
rm -rf "$W23BP"

# --- 11d. env poison cannot reach the gate (#244 a S1) --------------------------------
# PYTHONHOME poison: without -I a bogus PYTHONHOME breaks interpreter
# startup (rc 1) and the probe would degrade the passes to a
# counter-less fallback; with -I the interpreter ignores the env
# entirely — the baseline runs WITH its live counters. (An os.py
# PYTHONPATH shadow cannot be the vehicle here: os is already in
# sys.modules at -c startup, the shadow never loads — a vacuous-pin
# trap caught by sabotage during the fix wave.)
W23EP="$WORK/issue223-envpoison"
mkdir -p "$W23EP/proj"
chmod 700 "$W23EP/proj"
printf 'env\n' >"$W23EP/proj/f"
chmod 600 "$W23EP/proj/f"
W23EPRC=0
W23EPOUT="$(FS_SUDO="" PYTHONHOME=/nonexistent-opk \
    sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$W23EP/proj" "$(id -gn)" 2>&1)" ||
    W23EPRC=$?
assert_eq "#244 env poison: baseline applies despite hostile PYTHONHOME (rc 0)" "0" "$W23EPRC"
assert_eq "#244 env poison: file got group rw (600 -> 660)" "660" \
    "$(stat -c %a "$W23EP/proj/f")"
if printf '%s\n' "$W23EPOUT" | grep -q 'entries — done'; then
    pass "#244 env poison: live counters still run (the -I isolation works)"
else
    fail "#244 env poison: live counters still run (got: $W23EPOUT)"
fi
if printf '%s\n' "$W23EPOUT" | grep -q 'live progress unavailable'; then
    fail "#244 env poison: no degradation warn (isolation, not fallback)"
else
    pass "#244 env poison: no degradation warn (isolation, not fallback)"
fi
rm -rf "$W23EP"

# --- 11d-bis. hostile-locale decode+IO (#510) ---------------------------------------
# Two layers under a 7-bit locale (the harness #510 wrapper + env):
#   decode — the tee's python source travels as -c ARGV (locale codec +
#       surrogateescape); non-ASCII source bytes used to die at startup
#       with "Unable to decode the command from the command line"
#       (em-dashes in comments and the completion line). The source is
#       pure ASCII now, the rendered em-dash rides a \u2014 escape
#       (byte-identical stderr), and the region scan pins it.
#   IO — already buffer-based (binary passthrough + counter); the pin
#       proves it survives the hostile env byte-exact, stderr clean.
# Control arm first (harness #510): the strict stdout must actually
# kill the unpinned non-ASCII write, or every pin here is vacuous.
P510="$(hostile_stdio_python)"
if hostile_stdio_control "$P510"; then
    pass "control arm: strict 7-bit stdout kills the -I non-ASCII write (#510)"
else
    fail "control arm: hostile stdio not effective -- the #510 pins would pass vacuously"
fi
_H510_RC=0
_H510_ERR="$WORK/h510-err"
: >"$_H510_ERR"
_H510_OUT="$(printf 'a\0b\0c\0' | PATH="$P510:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 \
    PYTHONCOERCECLOCALE=0 PYTHONIOENCODING=ascii FS_SUDO="" \
    sh -c '. "$1" && _fsb_count_tee lbl' _ "$LIB" 2>"$_H510_ERR" |
    od -An -tx1 | tr -s ' ')" || _H510_RC=$?
# stderr carries the cosmetic completion line (under the hostile locale
# stderr's backslashreplace renders the em-dash as "\u2014" text — the
# documented cosmetic class); the discriminators are the absent
# interpreter death (traceback or decode refusal) and the byte-exact
# passthrough.
if [ "$_H510_RC" = 0 ] &&
    [ "$_H510_OUT" = " 61 00 62 00 63 00" ] &&
    ! grep -q "Traceback\|Unable to decode" "$_H510_ERR"; then
    pass "count tee: hostile locale cannot kill the startup or the passthrough (#510)"
else
    fail "count tee must start and stream under the 7-bit locale (rc=$_H510_RC out=[$_H510_OUT] err=$(head -2 "$_H510_ERR" 2>/dev/null)) (#510)"
fi
# region scan: the -c source must stay pure ASCII (#510, the
# argv-decode class; the doctor prefilter idiom detects any 8th-bit
# byte — ui text outside this region is deliberately UTF-8 and NOT
# scanned)
if sed -n "/^    python3 -I -c '$/,^' \"\\\$1\"\$/p" "$LIB" |
    LC_ALL=C grep -q "$(printf '[\200-\377]')"; then
    fail "fs-baseline -c source must stay pure ASCII (#510 argv-decode class)"
else
    pass "fs-baseline -c source is pure ASCII (#510 argv-decode class)"
fi
rm -f "$_H510_ERR"

# --- 11e. Ctrl-C ends the tee silently (#244 a W4 — the KI arm of 11c's clause) --------
# 11c pins BrokenPipeError; the except tuple's OTHER arm —
# KeyboardInterrupt — needs its own executed failure path (L1). The
# tee reads a FIFO a writer holds open: counted > 0, then blocked in
# read. setsid gives the tee its own process group so kill -INT reaches
# the python itself (a bare kill of the sh parent would orphan it and
# the tee would finish normally on EOF — a false pass). Asserts are on
# stderr content only: the sh wrapper's rc after SIGINT is
# shell-dependent. Arm proof before the signal (#244 b W3): the
# writer's drain marker appears once the tee has drained the stream —
# all but at most one pipe buffer (~64 KiB) may still be buffered
# when the blocking write returns (#244 c W5: not the "whole"
# stream), which is enough: the SIGINT always hits an interpreter
# that already initialized. A fixed sleep instead could race the
# startup chain and pass vacuously. Guarded on setsid presence with a
# skip note (#244 b W2, the §11c bash-rider pattern).
W23KI="$WORK/issue223-ki"
if command -v setsid >/dev/null 2>&1; then
    mkdir -p "$W23KI"
    W23KIF="$W23KI/in.fifo"
    mkfifo "$W23KIF"
    # fd 3 on the SUBSHELL (exec 3>): the write end must stay open through
    # the sleep — a redirect on the python command alone closes it when
    # python exits, the tee sees EOF, finishes normally and prints its
    # completion line before the signal ever arrives (fixture bug caught
    # by this very pin on first run). The ready marker after the write
    # is the arm proof (#244 b W3): a fifo write blocks until the
    # reader drains it, so the marker appears once the tee has
    # consumed all but at most one pipe buffer of the stream and sits
    # blocked in read (#244 c W5 wording fix).
    (
        exec 3>"$W23KIF"
        python3 -c 'import sys; sys.stdout.buffer.write(b"e\0" * 524288)' >&3 2>/dev/null
        : >"$W23KI/ready"
        sleep 10
    ) &
    W23KIWR=$!
    # The async-list SIGINT rule (POSIX): a background command of a
    # non-interactive shell starts with SIGINT IGNORED — CPython then never
    # installs its KeyboardInterrupt handler and kill -INT would be a
    # silent no-op: the pin could not fire AT ALL (caught live — the
    # completion line still appeared and the no-traceback assert passed
    # vacuously). The wrapper RESTORES the disposition — a caught signal
    # resets to default across exec — then execs the real sh+tee.
    setsid python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.default_int_handler)
os.execv(sys.argv[1], [sys.argv[1], "-c",
    ". \"$1\" && _fsb_count_tee ki < \"$2\"", "ki", sys.argv[2], sys.argv[3]])' \
        /bin/sh "$LIB" "$W23KIF" >/dev/null 2>"$W23KI/err" &
    W23KITEE=$!
    # Readiness poll (#244 b W3): signal only an ARMED tee — the marker
    # proves the stream drained (interpreter initialized, read loop
    # live). No marker within 10 s goes red by itself instead of
    # passing green with nothing executed. Integer sleep only (#244 c
    # Q3): POSIX sleep need not accept a fractional operand, and a
    # failing one aborts the whole suite under set -e — the very
    # block the setsid guard made portable. 10 × 1 s keeps the bound.
    W23KIWAIT=0
    while [ ! -e "$W23KI/ready" ] && [ "$W23KIWAIT" -lt 10 ]; do
        sleep 1
        W23KIWAIT=$((W23KIWAIT + 1))
    done
    if [ -e "$W23KI/ready" ]; then
        pass "#244 ctrl-c: tee armed before the signal (stream drained)"
    else
        fail "#244 ctrl-c: tee never armed — inspect $W23KI/err"
    fi
    # No "--" before the negative pid: dash's kill builtin rejects it
    # (rc 2, usage) while bash accepts it — the suite runs under dash, and
    # the group kill silently never happened until this was caught live
    # (bash-vs-dash trap: the debug session ran bash and looked green).
    kill -INT "-$W23KITEE" 2>/dev/null ||
        /bin/kill -INT "-$W23KITEE" 2>/dev/null ||
        kill -INT "$W23KITEE" 2>/dev/null ||
        true
    wait "$W23KITEE" 2>/dev/null || true
    kill "$W23KIWR" 2>/dev/null || true
    wait "$W23KIWR" 2>/dev/null || true
    if grep -q 'Traceback' "$W23KI/err"; then
        fail "#244 ctrl-c: no traceback on the KeyboardInterrupt arm"
    else
        pass "#244 ctrl-c: no traceback on the KeyboardInterrupt arm"
    fi
    if grep -q '— done' "$W23KI/err"; then
        fail "#244 ctrl-c: no completion line for an aborted pass"
    else
        pass "#244 ctrl-c: no completion line for an aborted pass"
    fi
    rm -rf "$W23KI"
else
    echo "  note: setsid absent — ctrl-c pins skipped (#244 b W2)"
fi

# --- 11f. a broken python3 names its problem above the warn (#244 c S3) ---------------
# The probe's rerun (the installer gate's #244 b-S2 shape): a
# present-but-broken interpreter surfaces its own diagnostic stderr
# above the degradation warn — an attributeless degrade hides the
# cause. An ABSENT python3 stays silent (command -v guard: no
# not-found noise for a legitimate absence). Fixture wording is
# CPython's real unhyphenated message.
W23NZ="$WORK/issue223-noisy"
# The diagnostic text lives in a variable: a consuming grep line
# quoting the literal ('platform…' "$VAR/x") chains into the sandbox
# scanner's raw-line rm-suffix pattern — the definition line does
# not (#244 c S1: the wave-2 mechanism is real for grep lines, not
# for the fixture printf shape both reviews probed).
W23DIAG='platform independent libraries'
mkdir -p "$W23NZ/bin"
printf '#!/bin/sh\necho "%s" >&2\nexit 9\n' "$W23DIAG" >"$W23NZ/bin/python3"
chmod +x "$W23NZ/bin/python3"
FS_SUDO="" PATH="$W23NZ/bin:$PATH" \
    sh -c '. "$1" && _fsb_py_probe' _ "$LIB" >"$W23NZ/out" 2>"$W23NZ/err"
if grep -qF "$W23DIAG" "$W23NZ/err" &&
    grep -qF 'live progress unavailable' "$W23NZ/err"; then
    pass "#244 c S3: fs-baseline probe surfaces a broken interpreter's diagnostic"
else
    fail "#244 c S3: probe diagnostic passthrough (err=$(cat "$W23NZ/err"))"
fi
rm -rf "$W23NZ"

# --- 12. symlinked project roots are refused everywhere (issue #245) -----------------
# Measured (issue #245 comment, ext4 + overlayfs): on a root ENTRY that
# is itself a symlink to a directory, every find-based baseline pass
# visits NOTHING (silent no-op under the callers' success lines) while
# chmod g-s / setfacl -R -x dereference onto the TARGET. Gates: writer
# (project_path_sane — pinned in test-project-paths.sh), the shared
# helper (behavioral, below), and the raw-conf reader loops (behavioral
# drivers below — config.sh refresh and the update.sh root loop have NO
# writer gate in front of them, the #247 gap is the blocklist, not the
# symlink arm). Belt arms behind the writer (install.sh baseline loop,
# config.sh add/handover) carry rider'd presence pins at the end of
# this section.
S245="$WORK/s245"
mkdir -p "$S245/real" "$S245/real2"
ln -s "$S245/real" "$S245/link"
ln -s "$S245/gone" "$S245/dangling"

# 12a. fs_baseline_root refuses a symlinked root LOUDLY and touches
# nothing: rc 1 (the 0.0.43a F10 shape — success lines must not print
# over a baseline that did not run), the reason on stderr, and the
# target tree keeps mode, group and default-ACL state. The slash
# spelling hits the same refusal through the internal ${fsb_root%/}
# strip ([ -L "path/" ] is false — measured; a raw-conf caller may
# hand the stored spelling through).
_s245_mode() { stat -c '%A %G' "$S245/real"; }
_s245_before=$(_s245_mode)
S245A_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/link" "$(id -gn)" 2>&1) &&
    S245A_RC=0 || S245A_RC=$?
S245B_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/link/" "$(id -gn)" 2>&1) &&
    S245B_RC=0 || S245B_RC=$?
# Dangling link (review b X4): the belt sits BEFORE the [ -n ] && [ -d ]
# arm now — [ -L ] is true for a dangling link too, so it must refuse
# loudly instead of the old silent rc-0 no-op.
S245D_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/dangling" "$(id -gn)" 2>&1) &&
    S245D_RC=0 || S245D_RC=$?
# c X1 arms: the belt refuses the dodge spellings outright (form arms
# before the [ -L ] belt) — executed in review c, the FULL baseline ran
# through `link/.` onto the target under the old one-slash-strip-only
# shape; non-absolute roots refuse too (the writer's form set).
S245E_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/link/." "$(id -gn)" 2>&1) &&
    S245E_RC=0 || S245E_RC=$?
S245F_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/link//" "$(id -gn)" 2>&1) &&
    S245F_RC=0 || S245F_RC=$?
S245G_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "." "$(id -gn)" 2>&1) &&
    S245G_RC=0 || S245G_RC=$?
# #665 arm: a glob-bearing root. No reachable misfire today — every
# root use in the belt's callers is quoted — the arm is the belt's
# own contract for direct/future callers (issue #665, PR #655 round e
# S3). A spelling with no dots or whitespace isolates the glob arm
# from the sibling form arms.
S245H_ERR=$(FS_SUDO="" sh -c '. "$1" && fs_baseline_root "$2" "$3"' _ "$LIB" "$S245/glb*root" "$(id -gn)" 2>&1) &&
    S245H_RC=0 || S245H_RC=$?
if [ "$S245A_RC" -ne 0 ] &&
    printf '%s' "$S245A_ERR" | grep -qF 'is a symlink — refusing the group baseline' &&
    [ "$(_s245_mode)" = "$_s245_before" ] &&
    [ "$(getfacl -cpd -- "$S245/real" 2>/dev/null | grep -c '^group:')" -eq 0 ] &&
    [ "$S245B_RC" -ne 0 ] &&
    printf '%s' "$S245B_ERR" | grep -qF 'is a symlink — refusing the group baseline' &&
    [ "$S245D_RC" -ne 0 ] &&
    printf '%s' "$S245D_ERR" | grep -qF 'is a symlink — refusing the group baseline' &&
    [ "$S245E_RC" -ne 0 ] && [ "$S245F_RC" -ne 0 ] &&
    printf '%s' "$S245E_ERR" | grep -qF 'is a malformed root' &&
    printf '%s' "$S245F_ERR" | grep -qF 'is a malformed root' &&
    [ "$S245H_RC" -ne 0 ] &&
    printf '%s' "$S245H_ERR" | grep -qF 'is a malformed root' &&
    [ "$S245G_RC" -ne 0 ] &&
    printf '%s' "$S245G_ERR" | grep -qF 'is not an absolute path'; then
    pass "fs_baseline_root: live/dangling/slash/dot/relative/glob link roots all refused loudly, tree untouched (#245, b X4, c X1; #665)"
else
    fail "fs_baseline_root must refuse every dodge spelling (A=$S245A_RC B=$S245B_RC D=$S245D_RC E=$S245E_RC F=$S245F_RC G=$S245G_RC H=$S245H_RC) (#245/#665)"
fi

# 12b. config.sh refresh(): the REAL extracted function over a fixture
# conf — real root, plain link, trailing-slash link, and a bare "/"
# (the strip degenerates it to the empty string: skipped silently —
# the OLD loop refused "/" loudly at the pass guard (#211 b W7) and
# set -e aborted the refresh; the strip turns loud-refuse-abort into
# a safe silent skip, review a Q4). Plus the S1/S2 arms: `link/.`
# (dot spelling that dodges [ -L ] and the belt strip — recursive
# baseline on the target, review a S1) and `link//` (belt refusal
# aborted the whole run under set -e, review a S2) — both are the
# form gate's catch now: loud skip, remaining roots processed. The
# dangling link (a S3) reports as a symlink before [ -d ] can swallow
# it. The baseline/handover markers may fire for the REAL roots ONLY
# (real and real2 — real2 after every malformed entry proves no
# mid-loop abort).
{
    printf '%s\n' \
        'ui_info() { :; }' \
        'ui_success() { :; }' \
        'ui_warn() { echo "ui_warn: $1"; }' \
        'log() { :; }' \
        'fs_baseline_root() { echo "FSB: $1"; }' \
        'ddev_handover_root() { echo "HO: $1"; }' \
        'ddev_handover_stamp_write() { :; }'
    extract_func "$CONFIG" refresh
    printf '%s\n' 'refresh'
} >"$S245/run-refresh.sh"
# conf order: real … malformed/link entries … real2 — real2 AFTER every
# refused entry proves no mid-loop abort (the a S2 over-abort shape).
# The b X1 arms ride along: `.` and `foo` (relative spellings the a-wave
# form arms missed) and a spaced absolute path (writer whitespace arm).
# #660 M6: a '#'-line leads the conf — an annotation must render NO warn
# row in either refresh loop (the pre-fix shape warned "not an absolute
# project path" over it).
# #247 arms at the tail: the classic system paths (/etc, /usr, /var and
# the bare /home — the stripped-compare arm the writer's blocklist owes)
# plus the agent home /home/toc (OPENCODE_USER=toc above; lexical, so
# the nonexistent home still refuses) and /var/backups (#377 O1: the
# completed /var families, behaviorally — the arm exists on every
# Debian-family host this suite runs on). All system entries EXIST on
# every test host — the blocklist sits after [ -d ], a nonexistent
# system path would be skipped silently by the existence gate before
# the blocklist sees it (uninstall-core parity). The /tmp + /var/tmp
# DIVERGENCE is pinned by the REAL roots themselves: they live under
# this suite's scratch (TMPDIR territory) and their FSB/HO counts prove
# those prefixes stay processable — the blocklist deliberately leaves
# them open (the comments in update-core.sh / config.sh name why).
printf '#660 ops note\n%s\n/\n%s\n%s/\n%s/.\n%s//\n%s\n%s\n.\nfoo\n/home/some-user-max-mustermann/foo bar\n/etc\n/usr\n/var\n/home\n/var/backups\n/home/toc\n/relocated/opencode\n' \
    "$S245/real" "$S245/link" "$S245/link" "$S245/link" "$S245/link" \
    "$S245/dangling" "$S245/real2" >"$S245/conf"
# #665: a glob-bearing entry rides at the conf tail (the long printf
# above stays untouched for the line-length ratchet): BOTH readers of
# this conf (config.sh refresh below, the update.sh root loop in 12c)
# must skip it loudly at the form gate, and the FSB/HO counts stay 2 —
# no baseline or handover runs over a glob-bearing root.
printf '%s\n' "$S245/glb*root" >>"$S245/conf"
# getent stub (L1 rider for the agent-home arm): toc's RELOCATED home —
# pins the getent-hit direction (pr-00263 a F10 shape: the literal
# /home/<user> compare alone would miss a moved agent home). Absent
# stubs of getent fall through to the real binary, which has no toc.
mkdir -p "$S245/bin"
printf '#!/bin/sh\n[ "$1" = passwd ] && [ "$2" = toc ] && echo "toc:x:1:1::/relocated/opencode:/bin/sh" && exit 0\nexit 2\n' \
    >"$S245/bin/getent"
chmod +x "$S245/bin/getent"
# OPK_READER_TMP_ROOTS=1 (#479 a F10 unit seam): the fixture roots live
# in this suite's /tmp scratch — the readers screen scratch prefixes
# like the writer does now; the seam re-opens them for the fixtures.
S245R_OUT=$(OPK_READER_TMP_ROOTS=1 PATH="$S245/bin:$PATH" PROJECTS_CONF="$S245/conf" OPENCODE_GROUP=tg OPENCODE_USER=toc DEFAULT_USER=tdv \
    sh "$S245/run-refresh.sh" 2>&1)
if [ "$(printf '%s\n' "$S245R_OUT" | grep -c '^FSB: ')" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -c '^HO: ')" -eq 2 ] &&
    printf '%s\n' "$S245R_OUT" | grep -qF "FSB: $S245/real" &&
    printf '%s\n' "$S245R_OUT" | grep -qF "FSB: $S245/real2" &&
    ! printf '%s\n' "$S245R_OUT" | grep -q '^FSB: .*/link' &&
    ! printf '%s\n' "$S245R_OUT" | grep -q '^HO: .*/link' &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF "ui_warn: skip $S245/link (symlink")" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF "ui_warn: skip $S245/dangling (symlink")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF "ui_warn: skip $S245/link/. (malformed")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF "ui_warn: skip $S245/link// (malformed")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip . (not an absolute project path)')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip foo (not an absolute project path)')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /home/some-user-max-mustermann/foo bar (malformed')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF '(system path — never a project root)')" -eq 5 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /etc (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /var/backups (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /home (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF '(agent home — never a project root)')" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /home/toc (agent home')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF 'ui_warn: skip /relocated/opencode (agent home')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245R_OUT" | grep -cF "ui_warn: skip $S245/glb*root (malformed")" -eq 1 ] &&
    ! printf '%s\n' "$S245R_OUT" | grep -qF 'skip #660 ops note' &&
    ! printf '%s\n' "$S245R_OUT" | grep -q '^FSB: /etc' &&
    ! printf '%s\n' "$S245R_OUT" | grep -q '^FSB: /home$'; then
    pass "config.sh refresh: real roots only, link/dangling/malformed/relative/spaced/glob skipped loudly, system paths + agent home refused, no abort (#245, a S1/S2/S3, b X1; #247; #665)"
else
    fail "config.sh refresh must skip link/dangling/malformed/relative roots without abort (out=$(printf '%s\n' "$S245R_OUT" | head -10)) (#245/#247)"
fi

# 12c. the update.sh root loop (refresh + handover, the #247 raw-conf
# site): same fixture, same expectations — the loop is extracted
# verbatim (conf path hardcoded, fed via stdin like the uninstall
# driver), REFRESH=true so both consumers run, stamp check short-
# circuited away.
{
    printf '%s\n' \
        'ui_detail() { :; }' \
        'ui_warn() { echo "ui_warn: $1"; }' \
        'log() { :; }' \
        'fs_baseline_root() { echo "FSB: $1"; }' \
        'ddev_handover_root() { echo "HO: $1"; }' \
        'ddev_handover_stamp_write() { :; }' \
        'ddev_handover_stamp_valid() { return 1; }' \
        'REFRESH=true' 'OPENCODE_USER=toc' 'NEW_OPENCODE_GROUP=tg' 'DEFAULT_USER=tdv' \
        '_ho_skip=0' '_ho_announced=false'
    sed -n '/while IFS= read -r root; do/,/done <"\$PROJECTS_CONF"/p' "$UPDATE_CORE" |
        sed 's|done <"$PROJECTS_CONF"|done|'
} >"$S245/run-update-loop.sh"
S245U_OUT=$(OPK_READER_TMP_ROOTS=1 PATH="$S245/bin:$PATH" sh "$S245/run-update-loop.sh" <"$S245/conf" 2>&1)
if [ "$(printf '%s\n' "$S245U_OUT" | grep -c '^FSB: ')" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -c '^HO: ')" -eq 2 ] &&
    printf '%s\n' "$S245U_OUT" | grep -qF "FSB: $S245/real" &&
    printf '%s\n' "$S245U_OUT" | grep -qF "FSB: $S245/real2" &&
    ! printf '%s\n' "$S245U_OUT" | grep -q '^FSB: .*/link' &&
    ! printf '%s\n' "$S245U_OUT" | grep -q '^HO: .*/link' &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF "ui_warn: skip $S245/link (symlink")" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF "ui_warn: skip $S245/dangling (symlink")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF "ui_warn: skip $S245/link/. (malformed")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF "ui_warn: skip $S245/link// (malformed")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip . (not an absolute project path)')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip foo (not an absolute project path)')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /home/some-user-max-mustermann/foo bar (malformed')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF '(system path — never a project root)')" -eq 5 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /etc (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /var/backups (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /home (system path')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF '(agent home — never a project root)')" -eq 2 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /home/toc (agent home')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF 'ui_warn: skip /relocated/opencode (agent home')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245U_OUT" | grep -cF "ui_warn: skip $S245/glb*root (malformed")" -eq 1 ] &&
    ! printf '%s\n' "$S245U_OUT" | grep -qF 'skip #660 ops note' &&
    ! printf '%s\n' "$S245U_OUT" | grep -q '^FSB: /etc' &&
    ! printf '%s\n' "$S245U_OUT" | grep -q '^HO: /home$'; then
    pass "update.sh root loop: real roots only, link/dangling/malformed/relative/spaced/glob skipped loudly, system paths + agent home refused, no abort (#245, a S1/S2/S3, b X1; #247; #665)"
else
    fail "update.sh root loop must skip link/dangling/malformed/relative roots without abort (out=$(printf '%s\n' "$S245U_OUT" | head -10)) (#245/#247)"
fi

# 12d. belt arms behind the writer gate (scan->act rechecks, L5):
# install.sh's baseline loop and config.sh's add/handover rechecks are
# driven by the writer pin (test-project-paths.sh) + the loop pins
# above; these presence pins guard the wiring behind a comment-strip
# rider (conventions "Source-counting pins"). install.sh counts TWO
# sites (both $PROJECTS_ROOTS loops — the handover loop joined in
# review a X1); config.sh counts THREE (projects add, handover,
# refresh). The ddev_handover_root belt (a X2) and status.sh's
# symlink report (a X4) ride the same rider'd shape.
S245I=$(live_src "$INSTALL_CORE" |
    grep -cF 'ui_warn "skip $root (symlink — register the target directory instead)"' || true)
if [ "$S245I" -ge 2 ]; then
    pass "install.sh: BOTH \$PROJECTS_ROOTS loops carry the symlink skip arm (#245, a X1)"
else
    fail "install.sh must gate both \$PROJECTS_ROOTS loops (found $S245I of 2) (#245, a X1)"
fi
S245C=$(live_src "$CONFIG" |
    grep -cF 'ui_warn "skip $p (symlink — register the target directory instead)"' || true)
if [ "$S245C" -ge 3 ]; then
    pass "config.sh symlink skip arms wired at all three sites (add, handover, refresh) (#245)"
else
    fail "config.sh must carry the symlink skip arm at add/handover/refresh (found $S245C of 3) (#245)"
fi

# 12e. #660 M6: projects_list renders no "missing" atten row for a
# '#'-line — an annotated conf is not a fleet of phantom roots. Extracted
# like the refresh harness above (12), ui_* stubbed to observable echoes.
{
    printf '%s\n' \
        'ui_info() { :; }' \
        'ui_detail() { :; }' \
        'ui_have() { echo "have: $1"; }' \
        'ui_atten() { echo "atten: $1 $2"; }'
    extract_func "$CONFIG" projects_list
    printf '%s\n' 'projects_list'
} >"$S245/run-list.sh"
printf '#660 ops note\n%s\n' "$S245/real" >"$S245/list-conf"
S245L_OUT=$(PROJECTS_CONF="$S245/list-conf" sh "$S245/run-list.sh" 2>&1)
if printf '%s\n' "$S245L_OUT" | grep -qF "have: [1] $S245/real" &&
    ! printf '%s\n' "$S245L_OUT" | grep -qF 'atten:'; then
    pass "config.sh projects_list: comment lines render no atten rows (#660 M6)"
else
    fail "projects_list must not count comment lines as missing roots (#660 M6, out=$S245L_OUT)"
fi
if live_src "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ddev-handover.sh" |
    grep -qF 'if [ -L "${dhr_root%/}" ]; then'; then
    pass "ddev_handover_root carries the root-operand symlink belt (#245, a X2)"
else
    fail "ddev_handover_root must belt-gate symlinked roots (#245, a X2)"
fi
# Executed belt arm (review b X2): the belt must REFUSE — rc 1, the
# sibling fs_baseline_root shape. rc 0 let a caller stamp "applied"
# over nothing (executed in the b review); the warn alone did not stop
# the unconditional stamp writes. Function extracted, never sourced.
# Boundary note (#416 a R6): the sed range runs inside the sh -c child,
# where the harness's extract_func is not defined (child-shell residual
# class, same boundary as test-ddev-as-opencode's awk legs) — deliberate.
# c X1 arms ride along: the form spellings (`link/.`, `link//`) and a
# non-absolute root refuse too — review c's probe had the find walk
# descend the TARGET through the old one-slash-only belt.
_s245_dhr() {
    sh -c '
        eval "$(sed -n "/^ddev_handover_root() {/,/^}$/p" "$1")"
        ddev_handover_root "$2" u g d' _ \
        "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ddev-handover.sh" \
        "$1" 2>&1
}
S245X2_ERR=$(_s245_dhr "$S245/link") && S245X2_RC=0 || S245X2_RC=$?
S245X3_ERR=$(_s245_dhr "$S245/link/.") && S245X3_RC=0 || S245X3_RC=$?
S245X4_ERR=$(_s245_dhr "$S245/link//") && S245X4_RC=0 || S245X4_RC=$?
S245X5_ERR=$(_s245_dhr ".") && S245X5_RC=0 || S245X5_RC=$?
# #665: the sibling belt's glob arm — same spelling class as the
# fs_baseline_root H arm above.
S245X6_ERR=$(_s245_dhr "$S245/glb*root") && S245X6_RC=0 || S245X6_RC=$?
# #728 M1: a bare "/" root — the sibling fs_baseline_root arm (#655 b
# S2/C7) mirrored. The form arms above admit a lone slash (absolute,
# no dot/empty-segment alternative matches it), and the belt would
# hand find the whole filesystem. The third leg (#791 a B1) closes the
# message-without-refusal class: a dropped `return 1` keeps the
# refusal message and falls through to the lib guard's rc 1 — both
# legs green over a broken guard; the lib guard's own warn line is
# the fall-through tell, so its ABSENCE proves the arm returned.
# #792: the sibling arms carry the same absence leg — probed per arm
# (sabotaged lib copies, the return deleted, message kept), the
# fall-through ends at the lib guard for X2 (link), X3 (link/.),
# X4 (link//) and X5 (.) alike, each capture carrying both warn lines
# over rc 1. X6 is deliberately EXCLUDED: its operand (glb*root) is
# never created on disk, so the dropped-return state ends at the quiet
# [ -d ] `return 0` — rc 0, the lib-guard warn line never prints, the
# block's rc leg reds; an absence leg there could not fail for its
# reason (the L4 vacuous shape).
S245X7_ERR=$(_s245_dhr "/") && S245X7_RC=0 || S245X7_RC=$?
if [ "$S245X2_RC" -ne 0 ] &&
    printf '%s' "$S245X2_ERR" | grep -qF 'is a symlink — refusing the ddev handover' &&
    [ "$S245X3_RC" -ne 0 ] && [ "$S245X4_RC" -ne 0 ] &&
    printf '%s' "$S245X3_ERR" | grep -qF 'is a malformed root' &&
    printf '%s' "$S245X4_ERR" | grep -qF 'is a malformed root' &&
    [ "$S245X6_RC" -ne 0 ] &&
    printf '%s' "$S245X6_ERR" | grep -qF 'is a malformed root' &&
    [ "$S245X7_RC" -ne 0 ] &&
    printf '%s' "$S245X7_ERR" | grep -qF 'is never a handover root' &&
    [ "$S245X5_RC" -ne 0 ] &&
    printf '%s' "$S245X5_ERR" | grep -qF 'is not an absolute path' &&
    ! printf '%s' "$S245X2_ERR" | grep -qF 'OPK_DDEV_HANDOVER_LIB is unset' &&
    ! printf '%s' "$S245X3_ERR" | grep -qF 'OPK_DDEV_HANDOVER_LIB is unset' &&
    ! printf '%s' "$S245X4_ERR" | grep -qF 'OPK_DDEV_HANDOVER_LIB is unset' &&
    ! printf '%s' "$S245X5_ERR" | grep -qF 'OPK_DDEV_HANDOVER_LIB is unset' &&
    ! printf '%s' "$S245X7_ERR" | grep -qF 'OPK_DDEV_HANDOVER_LIB is unset'; then
    pass "ddev_handover_root belt refuses link, dodge spellings, glob, bare-/, and non-absolute roots, all rc 1, every refusal returning at its own arm — no fall-through (#245, b X2, c X1; #665; #728 M1; #791 a B1; #792)"
else
    S245X_CAPS="X2=|$S245X2_ERR| X3=|$S245X3_ERR| X4=|$S245X4_ERR| X5=|$S245X5_ERR| X6=|$S245X6_ERR| X7=|$S245X7_ERR|"
    fail "ddev_handover_root belt must refuse every dodge spelling, each arm returning at its own refusal — a dropped return 1 falls through to the lib guard and its warn line shows inside an X* capture (rcs: X2=$S245X2_RC X3=$S245X3_RC X4=$S245X4_RC X5=$S245X5_RC X6=$S245X6_RC X7=$S245X7_RC; $S245X_CAPS) (#245/#665/#728; #791 b A2; #792)"
fi
if live_src "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh" |
    grep -qF 'ui_atten "$root" "symlinked root — register the target directory instead"'; then
    pass "status.sh reports symlinked roots instead of the dead-end refresh advice (#245, a X4)"
else
    fail "status.sh must name symlinked roots, not advise a refresh that skips them (#245, a X4)"
fi

# 12e. install.sh's HANDOVER loop (review a X1), behavioral: the
# second $PROJECTS_ROOTS loop is extracted by block identity (the one
# whose body calls ddev_handover_root — a plain sed range cannot
# separate the two loops) and driven with marker stubs. A symlinked
# root (and a dangling one) must produce the skip warning and NO
# handover/stamp op — the pre-fix loop wrote the stamp and the
# "applied" audit line for the same root the baseline loop refused.
{
    printf '%s\n' \
        'ui_warn() { echo "ui_warn: $1"; }' \
        'ddev_handover_root() { echo "HO: $1"; }' \
        'ddev_handover_stamp_write() { echo "STAMP: $1"; }' \
        'log() { :; }' \
        "PROJECTS_ROOTS=\"$S245/real $S245/link $S245/dangling\"" \
        'OPENCODE_USER=toc' 'OPENCODE_GROUP=tg' 'DEFAULT_USER=tdv'
    awk '
        /for root in \$PROJECTS_ROOTS; do/ { buf = ""; inl = 1 }
        inl { buf = buf $0 ORS }
        inl && /^[[:space:]]*done$/ {
            if (buf ~ /ddev_handover_root/) { printf "%s", buf; exit }
            inl = 0
        }
    ' "$INSTALL_CORE"
} >"$S245/run-install-handover.sh"
S245H_OUT=$(sh "$S245/run-install-handover.sh" 2>&1)
if [ "$(printf '%s\n' "$S245H_OUT" | grep -c '^HO: ')" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245H_OUT" | grep -c '^STAMP: ')" -eq 0 ] &&
    printf '%s\n' "$S245H_OUT" | grep -qF "HO: $S245/real" &&
    ! printf '%s\n' "$S245H_OUT" | grep -q '^HO: .*/link' &&
    ! printf '%s\n' "$S245H_OUT" | grep -q '^HO: .*dangling' &&
    [ "$(printf '%s\n' "$S245H_OUT" | grep -cF "ui_warn: skip $S245/link (symlink")" -eq 1 ] &&
    [ "$(printf '%s\n' "$S245H_OUT" | grep -cF "ui_warn: skip $S245/dangling (symlink")" -eq 1 ]; then
    pass "install.sh handover loop: no stamp/op for link or dangling root, loud skip (a X1/S3; stamp lives in ddev_handover_root since a D2)"
else
    fail "install.sh handover loop must refuse symlinked roots (out=$(printf '%s\n' "$S245H_OUT" | head -6)) (a X1)"
fi

# --- 13. #265: tee rc contracts — cat-arm mask + stream separation -----------------
# pr-00263 b B2 (cat arm): the old unconditional `return 0` discarded
# cat's rc — a read error truncated the operand stream green. The stub
# cat pins the rc CONTRACT in both directions (7 = read error must
# propagate; 141 = SIGPIPE must map to the documented consumer-EPIPE 0)
# without needing a real mid-stream read error — the old mask answers 0
# to both, the naive `return $?` answers 7/141: only this pair pins the
# exact contract. _fsb_py_checked/_fsb_py_ok force the cat arm
# deterministically (the probe is #223's subject, not this pin's).
W65BIN="$WORK/issue265-bin"
mkdir -p "$W65BIN"
printf '#!/bin/sh\nexit 7\n' >"$W65BIN/cat"
chmod +x "$W65BIN/cat"
W65C7=0
FS_SUDO="" PATH="$W65BIN:$PATH" sh -c '. "$1"; _fsb_py_checked=1; _fsb_py_ok=0; _fsb_count_tee e </dev/null' \
    _ "$LIB" >/dev/null 2>&1 || W65C7=$?
assert_eq "#265 cat arm: read-error rc propagates (7, not the masked 0)" "7" "$W65C7"
printf '#!/bin/sh\nexit 141\n' >"$W65BIN/cat"
W65C141=0
FS_SUDO="" PATH="$W65BIN:$PATH" sh -c '. "$1"; _fsb_py_checked=1; _fsb_py_ok=0; _fsb_count_tee e </dev/null' \
    _ "$LIB" >/dev/null 2>&1 || W65C141=$?
assert_eq "#265 cat arm: SIGPIPE (141) maps to the consumer-EPIPE 0" "0" "$W65C141"
# Real-cat rider under the PRODUCTION shell shape (the §11c pattern,
# strengthened by #418 a A4/C1): bash with set -eu + pipefail — the
# shape every shipped caller runs. A consumer that exits at once ends
# real cat in SIGPIPE; without the cat arm's `|| _fsb_cat_rc=$?`
# errexit-guard, set -e fires AT the failing cat (141) before the
# consumer-EPIPE mapping runs and this pin goes red. The python3
# wrapper resets SIGPIPE to SIG_DFL first (#418 a C1): CI runners
# inherit SIGPIPE IGNORED from the Node runner agent (a child cannot
# clear an inherited ignore via shell trap — POSIX forbids
# re-enabling it), and under SIG_IGN cat exits 1 (write error) instead
# of dying by signal; the disposition reset must happen in a real
# process before exec.
# The SIG_IGN leg (#419) runs the SAME pipeline with the inherited-ignore
# disposition instead of the reset: cat ends in write-error rc 1, the
# cat arm propagates it (only 141 maps to 0) and the pipeline fails
# LOUD rc 1 — the safe direction pinned where fs-baseline.sh's cat-arm
# comment previously claimed it only ("documented, not pinned", the
# #418 b R3 residual). Skipped with a note where bash/python3 absent.
if command -v bash >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    W65BIG="$WORK/issue265-big"
    python3 -c 'import sys; sys.stdout.buffer.write(b"e\0" * 524288)' >"$W65BIG"
    W65PF=0
    FS_SUDO="" python3 -c 'import os, signal, sys
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
os.execvp("bash", ["bash", "-c", sys.argv[1], "_"] + sys.argv[2:])' \
        'set -eu; set -o pipefail; . "$1"; _fsb_py_checked=1; _fsb_py_ok=0; _fsb_count_tee pf <"$2" | sh -c "exit 0"' \
        "$LIB" "$W65BIG" >/dev/null 2>&1 || W65PF=$?
    assert_eq "#265 pipefail rider: cat's SIGPIPE stays green under the production set -eu+pipefail shape" "0" "$W65PF"
    W65IGN=0
    FS_SUDO="" python3 -c 'import os, signal, sys
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
os.execvp("bash", ["bash", "-c", sys.argv[1], "_"] + sys.argv[2:])' \
        'set -eu; set -o pipefail; . "$1"; _fsb_py_checked=1; _fsb_py_ok=0; _fsb_count_tee pf <"$2" | sh -c "exit 0"' \
        "$LIB" "$W65BIG" >/dev/null 2>&1 || W65IGN=$?
    assert_eq "#265 pipefail rider, SIG_IGN leg: inherited-ignore turns cat into write-error rc 1 — fails LOUD (#419)" "1" "$W65IGN"
    rm -rf "${W65BIG:?}"
else
    echo "  note: bash or python3 absent — cat-arm pipefail riders skipped (#244 a Q1 shape)"
fi
# Python arm: an interpreter failure must not be masked either (the
# stub dies rc 3 before touching the stream — the function's rc is
# python's own; this pins that nothing regresses it to a silent 0).
printf '#!/bin/sh\nexit 3\n' >"$W65BIN/python3"
chmod +x "$W65BIN/python3"
W65P3=0
FS_SUDO="" PATH="$W65BIN:$PATH" sh -c '. "$1"; _fsb_py_checked=1; _fsb_py_ok=1; _fsb_count_tee e </dev/null' \
    _ "$LIB" >/dev/null 2>&1 || W65P3=$?
assert_eq "#265 python arm: interpreter failure propagates (3)" "3" "$W65P3"
rm -rf "$W65BIN"

# pr-00263 c C1 (stream separation): a DEAD PROGRESS SINK must degrade
# the counter only, never the data stream. /dev/full makes the sink
# fail deterministically on the first progress write (ENOSPC — OSError;
# EPIPE from a closed fifo reader is the same except arm but carries an
# unfixable open/close race in a unit harness, so the full device
# carries the pin). Two 1 MiB chunks with the 2000-entry threshold
# crossed inside chunk 1: the OLD shape lost chunk 2+ here too, by
# whichever arm the sink's failure took — an EPIPE landed in the single
# consumer-death except (dup2 stdout to devnull, rc 0 — the false-green
# race); an ENOSPC was an uncaught OSError outside the
# BrokenPipeError-only tuple (traceback, rc 1). Either way the data
# stream died with the progress sink. rc 0 + byte-identical
# passthrough discriminate; the done line is suppressed (progress_dead).
if [ -w /dev/full ]; then
    W65EP="$WORK/issue265-epipe"
    mkdir -p "$W65EP"
    python3 -c 'import sys; sys.stdout.buffer.write(b"x\0" * 2500 + b"z" * (1572864 - 5000))' >"$W65EP/in"
    W65EP_RC=0
    FS_SUDO="" sh -c '. "$1"; _fsb_py_checked=1; _fsb_py_ok=1; _fsb_count_tee full <"$2" >"$3" 2>/dev/full' \
        _ "$LIB" "$W65EP/in" "$W65EP/out" >/dev/null 2>&1 || W65EP_RC=$?
    assert_eq "#265 dead progress sink: tee survives, rc 0 (data stream unaffected)" "0" "$W65EP_RC"
    if cmp -s "$W65EP/in" "$W65EP/out"; then
        pass "#265 dead progress sink: data stream intact (both chunks flushed byte-identically)"
    else
        fail "#265 dead progress sink: data truncated ($(wc -c <"$W65EP/out") of $(wc -c <"$W65EP/in") bytes)"
    fi
    rm -rf "$W65EP"
else
    echo "  note: /dev/full unavailable — dead-sink pin skipped"
fi

# --- Summary ---------------------------------------------------------------------------
suite_done "tests"
