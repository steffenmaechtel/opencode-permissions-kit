#!/bin/sh
# opencode permissions kit -- scripts/release.sh
# Maintainer release helper (issue #38, docs/design/release-handling.md).
# A release is: tag x.y.z on master + fast-forward of the 'stable' mirror
# (byte-identical to master). The script does the mechanics; the judgment
# calls (when to release, release notes, announcements) stay with you.
#
# Usage:
#   scripts/release.sh <x.y.z> [--dry-run] [--skip-tests]
#   make release VERSION=x.y.z
#
# Pre-conditions (each verified, fail fast):
#   - clean working tree on master, up to date with origin/master
#   - VERSION file already equals x.y.z — the bump lands via PR first
#     (repo rule: never commit on master directly, so this script never
#     bumps or commits anything)
#   - tag x.y.z not taken (an existing tag pointing at HEAD resumes)
#   - 'stable' (if it exists on origin) is an ancestor of master, so the
#     mirror is a pure fast-forward — a diverged 'stable' aborts, this
#     script never force-pushes
#   - unit suite + lint + check-version green (unless --skip-tests)
#
# Then: create the annotated tag, move local 'stable' to master, push
# tag + stable. --dry-run prints every step instead of running it (no
# fetch, no push, nothing written).
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"

VERSION=""
DRY_RUN=false
SKIP_TESTS=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --dry-run)     DRY_RUN=true ;;
        --skip-tests)  SKIP_TESTS=true ;;
        -*)            echo "error:  unknown option: $1" >&2; exit 1 ;;
        *)             [ -z "$VERSION" ] || { echo "error:  only one version argument allowed" >&2; exit 1; }
                       VERSION="$1" ;;
    esac
    shift
done
if [ -z "$VERSION" ]; then
    echo "error:  usage: scripts/release.sh <x.y.z> [--dry-run] [--skip-tests]" >&2
    exit 1
fi
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error:  '$VERSION' is not a bare x.y.z stamp (no 'v' prefix, no suffix — matches the VERSION file)" >&2
    exit 1
fi

say()  { printf '  %s\n' "$*"; }
err()  { printf 'error:  %s\n' "$*" >&2; }
step() { printf '\n== %s ==\n' "$*"; }

# run <cmd...>: execute, or just announce in dry-run mode.
run() {
    if [ "$DRY_RUN" = true ]; then
        say "dry-run: $*"
    else
        say "$*"
        "$@"
    fi
}

step "1/5 pre-flight: repo state"

if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    err "working tree is not clean — commit or stash first."
    exit 1
fi
BRANCH="$(git -C "$REPO" symbolic-ref --short HEAD)"
if [ "$BRANCH" != "master" ]; then
    err "not on master (branch: $BRANCH) — releases are cut from master only."
    exit 1
fi
if [ "$DRY_RUN" != true ]; then
    git -C "$REPO" fetch origin master --tags --quiet
    git -C "$REPO" fetch origin stable --quiet 2>/dev/null || true
fi
if ! git -C "$REPO" rev-parse -q --verify origin/master >/dev/null; then
    err "origin/master not known — fetch failed or no remote 'origin'."
    exit 1
fi
if [ "$(git -C "$REPO" rev-parse master)" != "$(git -C "$REPO" rev-parse origin/master)" ]; then
    err "master is not in sync with origin/master — push/pull first."
    exit 1
fi
say "clean tree on master, in sync with origin/master"

step "2/5 pre-flight: version stamp"

STAMP="$(cat "$REPO/VERSION")"
if [ "$STAMP" != "$VERSION" ]; then
    err "VERSION file says '$STAMP', requested release is '$VERSION'."
    say "Bump lands via PR first (never commit on master directly):"
    say "  git checkout -b release/$VERSION && make version VERSION=$VERSION"
    say "  git commit VERSION -m 'chore: bump VERSION to $VERSION' && git push -u origin release/$VERSION"
    say "Then merge the PR and re-run this script."
    exit 1
fi

step "3/5 pre-flight: tag + mirror fast-forward check"

HEAD_REV="$(git -C "$REPO" rev-parse master)"
# ^{commit}: an annotated tag resolves to its tag OBJECT — unwrap to the
# commit so the resume path compares commits, not object types.
TAG_REV="$(git -C "$REPO" rev-parse -q --verify "refs/tags/$VERSION^{commit}" || true)"
if [ -n "$TAG_REV" ]; then
    if [ "$TAG_REV" != "$HEAD_REV" ]; then
        err "tag $VERSION already exists on a different commit ($TAG_REV) — pick a new version."
        exit 1
    fi
    say "tag $VERSION already points at master (resuming)"
else
    say "tag $VERSION is free"
fi

STABLE_KNOWN=true
if ! git -C "$REPO" rev-parse -q --verify origin/stable >/dev/null; then
    STABLE_KNOWN=false
    say "origin has no 'stable' yet — this release creates the mirror (first go-live)"
else
    if ! git -C "$REPO" merge-base --is-ancestor origin/stable master; then
        err "origin/stable has diverged from master — a fast-forward is impossible."
        say "Never force-push. Investigate: git log --oneline origin/stable ^master"
        say "Reconcile via a PR master <- stable differences (the mirror must be"
        say "byte-identical to master, docs/design/release-handling.md)."
        exit 1
    fi
    if [ "$(git -C "$REPO" rev-parse origin/stable)" = "$HEAD_REV" ]; then
        say "origin/stable already at master (mirror up to date)"
    else
        say "origin/stable fast-forwards to master"
    fi
fi

if [ "$SKIP_TESTS" = true ]; then
    say "tests skipped (--skip-tests)"
else
    step "3.5/5 pre-flight: suite"
    make -C "$REPO" test check-version
fi

step "4/5 tag + mirror"

if [ -z "$TAG_REV" ]; then
    run git -C "$REPO" tag -a "$VERSION" -m "opencode permissions kit $VERSION" master
else
    say "tag $VERSION exists — skipping"
fi
run git -C "$REPO" update-ref refs/heads/stable "$HEAD_REV"
if [ "$DRY_RUN" != true ]; then
    if [ "$(git -C "$REPO" rev-parse stable)" != "$HEAD_REV" ]; then
        err "local stable did not move to master — aborting before push."
        exit 1
    fi
    if ! git -C "$REPO" diff --quiet stable master; then
        err "stable != master (diff not empty) — the mirror invariant is broken, aborting before push."
        exit 1
    fi
fi

step "5/5 push"

PUSH_NEEDED=false
[ -z "$TAG_REV" ] && PUSH_NEEDED=true
{ [ "$STABLE_KNOWN" = true ] && [ "$(git -C "$REPO" rev-parse origin/stable)" != "$HEAD_REV" ]; } && PUSH_NEEDED=true
[ "$STABLE_KNOWN" = false ] && PUSH_NEEDED=true
if [ "$PUSH_NEEDED" = true ]; then
    run git -C "$REPO" push origin "refs/tags/$VERSION" refs/heads/stable
else
    say "nothing to push (tag + stable already at master on origin)"
fi

step "done"
say "released $VERSION: tag + stable mirror at $HEAD_REV"
if command -v gh >/dev/null 2>&1; then
    say "optional GitHub release:  gh release create $VERSION --generate-notes"
else
    say "optional GitHub release notes: https://github.com/steffenmaechtel/opencode-permissions-kit/releases/new?tag=$VERSION"
fi
say "installs now stream $VERSION: curl .../stable/files/install.sh | sudo env KIT_BRANCH=stable bash"
