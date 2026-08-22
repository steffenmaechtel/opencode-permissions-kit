#!/bin/sh
# tests/e2e/fixtures/make-bare-origin.sh — build the per-run bare git origin
# for the e2e-ddev git-flow tier (docs/design/ddev-e2e-test.md §7.2, DD12).
# Run via `sh` (like fake-ddev, it carries no exec bit and is not in the CI
# chmod lists). Reconciled against the real burn-in bare repo
# (local/TEST-PROJECT-INSTALL.txt, 2026-08-22): the tracked set there is
# .ddev/config.yaml + the composer/TYPO3 tree — no AGENTS.md, so the
# top-level branch works on README.md/LICENSE instead.
#
# Usage: sh make-bare-origin.sh <bare-target-dir> <fixture-site-dir>
#   <bare-target-dir>  created (must not already be a git repo)
#   <fixture-site-dir> the camino fixture master (tests/e2e/fixtures/camino/site)
#
# Produces a bare repo with:
#   main              site master + a tracked custom host command
#                     (.ddev/commands/host/hello) — the realistic baseline
#   feature/top-level README.md replaced (unlink+recreate on switch) and
#                     LICENSE deleted (unlink/recreate both switch directions)
#   feature/settings  config/system/settings.php + config/sites/camino/
#                     config.yaml modified (tracked-file replacement under
#                     handed-over settings dirs)
#   feature/ddev-tree .ddev/commands/host/hello deleted + .ddev/config.yaml
#                     modified (git unlink/rename inside opencode-owned .ddev/)
set -eu

usage() { sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^Usage:/,$p'; exit 2; }

[ "$#" -eq 2 ] || usage
BARE_TARGET=$1
SITE_DIR=$2

[ -f "$SITE_DIR/composer.json" ] || { echo "error: $SITE_DIR is not the camino site fixture" >&2; exit 1; }
[ ! -e "$BARE_TARGET/.git" ] && [ ! -e "$BARE_TARGET/config" ] || {
    echo "error: $BARE_TARGET already looks like a git repo" >&2
    exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

cp -a "$SITE_DIR/." "$WORK/"
mkdir -p "$WORK/.ddev/commands/host"
printf '#!/bin/sh\necho "hello from a custom ddev host command"\n' \
    > "$WORK/.ddev/commands/host/hello"
chmod +x "$WORK/.ddev/commands/host/hello"

git -C "$WORK" init -q -b main
git -C "$WORK" config user.email e2e@opencode-permissions-kit.invalid
git -C "$WORK" config user.name "e2e fixture"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "site master (camino fixture, DD12 baseline)"

git -C "$WORK" checkout -q -b feature/top-level
printf "# camino e2e — top-level file replaced on feature/top-level\n" > "$WORK/README.md"
rm "$WORK/LICENSE"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "replace README.md, drop LICENSE (top-level unlink/recreate)"

git -C "$WORK" checkout -q -b feature/settings main
printf '\n// feature/settings: appended marker line\n' >> "$WORK/config/system/settings.php"
sed -i 's/websiteTitle: Camino/websiteTitle: Camino (feature-settings)/' \
    "$WORK/config/sites/camino/config.yaml"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "modify tracked settings/site config"

git -C "$WORK" checkout -q -b feature/ddev-tree main
rm "$WORK/.ddev/commands/host/hello"
sed -i 's/^nodejs_version: .*/nodejs_version: 20/' "$WORK/.ddev/config.yaml"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "drop custom host command, tweak ddev config"

git -C "$WORK" checkout -q main
mkdir -p "$BARE_TARGET"
git -C "$WORK" init -q --bare "$BARE_TARGET"
# fresh bare repos default HEAD to refs/heads/master — point it at main so
# plain `git clone` checks out the fixture baseline.
git --git-dir="$BARE_TARGET" symbolic-ref HEAD refs/heads/main
git -C "$WORK" push -q "$BARE_TARGET" main feature/top-level feature/settings feature/ddev-tree

echo "bare origin ready: $BARE_TARGET"
git -C "$BARE_TARGET" for-each-ref --format='  %(refname:short)' refs/heads
