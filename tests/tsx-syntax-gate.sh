#!/bin/sh
# tsx-syntax-gate.sh — parse-only syntax gate for the shipped tui/*.tsx
# assets (issue #114, review 0.0.39a C5 TSX half).
#
# Nothing else syntax-checks these files: `make lint` is shellcheck-only,
# `make check-py` covers py/, and the e2e suites assert the plugin
# REGISTRATION (symlinks + cli.json), not that opencode can parse the
# file. A syntax error would otherwise ship green — worst case it
# surfaces on a user's machine when the TUI fails to load the plugin.
#
# Deliberately NOT part of `make test` or tests/check-host.sh: node+npm
# are not contributor-host requirements. CI runs this gate in
# test-unit.yml (ubuntu-latest ships node); locally anyone with node can:
#
#   sh tests/tsx-syntax-gate.sh
#
# Parse-only by design: the assets use opencode's plugin API, whose type
# declarations this repo does not ship. --noResolve plus the wildcard
# shim (tests/fixtures/tsx-parse-shim.d.ts) turn every import into `any`.
# Node's `--experimental-strip-types --check` cannot replace this: it
# supports erasable TS syntax only, not JSX.
#
# typescript comes from tests/fixtures/tsx-gate/ (package.json with an
# EXACT version pin + committed lockfile): `npm ci` verifies the
# tarball's integrity hash against the lockfile, so a registry serving
# different bytes for the same version is rejected before extraction —
# the gate cannot be supply-chain-drifted silently. --ignore-scripts
# closes the install-scripts vector (typescript needs none). Bump
# procedure: edit the pin in package.json, then regenerate the lockfile
# with `npm install --package-lock-only`; the wiring (run step + chmod
# entry + pin/lockfile sync) is guarded by tests/unit/test-workflows.sh
# section 2c.
#
# Exit status: 0 = all assets parse, 1 = setup or parse failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_SRC="$REPO_ROOT/tests/fixtures/tsx-gate"

# Shared UI helpers — same visual language as every kit script.
UI_LIB="$REPO_ROOT/files/opencode-permissions-kit-lib/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    . "$UI_LIB"
else
    ui_info()    { echo "  info     $1"; }
    ui_success() { echo "  success  $1"; }
    ui_error()   { echo "  error    $1" >&2; }
    ui_detail()  { echo "     $1"; }
fi

for tool in node npm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        ui_error "tsx gate: '$tool' is required (CI always has it; locally install node or rely on CI)"
        exit 1
    fi
done

for f in package.json package-lock.json; do
    if [ ! -f "$GATE_SRC/$f" ]; then
        ui_error "tsx gate: $GATE_SRC/$f missing (pin/lockfile fixture, see script header)"
        exit 1
    fi
done
TS_VERSION="$(sed -n 's/.*"typescript": "\([0-9][0-9.]*\)".*/\1/p' "$GATE_SRC/package.json" | head -1)"
if [ -z "$TS_VERSION" ]; then
    ui_error "tsx gate: cannot read the typescript pin from $GATE_SRC/package.json"
    exit 1
fi

# Install into a temp dir OUTSIDE the repo tree — no node_modules/, no
# npm side files next to the sources the repo-wide tests scan (same
# trick as check-py's PYTHONPYCACHEPREFIX). The lockfile travels with
# the copy so npm ci can verify the integrity hash.
GATE_DIR="$(mktemp -d)"
NPM_LOG="$GATE_DIR/npm-ci.log"
trap 'rm -rf "$GATE_DIR"' EXIT INT TERM

ui_info "installing locked typescript@$TS_VERSION (npm ci, integrity-verified, no repo changes)"
cp "$GATE_SRC/package.json" "$GATE_SRC/package-lock.json" "$GATE_DIR/"
if ! (cd "$GATE_DIR" && npm ci --ignore-scripts --no-audit --no-fund) >"$NPM_LOG" 2>&1; then
    ui_error "tsx gate: npm ci failed (lockfile out of sync with package.json, or integrity mismatch):"
    sed 's/^/     /' "$NPM_LOG"
    exit 1
fi

TSC="$GATE_DIR/node_modules/.bin/tsc"
SHIM="$REPO_ROOT/tests/fixtures/tsx-parse-shim.d.ts"

# Flag rationale:
#   --noEmit        check only, write nothing
#   --jsx preserve  parse JSX via the files' own @jsxImportSource pragma;
#                   the jsx-runtime module is covered by the shim
#   --noResolve     never probe the filesystem for imports; unresolved
#                   modules become `any` through the wildcard shim
#   --target esnext the assets use async functions (a down-level target
#                   would report those as errors)
#   --lib esnext    baseline globals without pulling @types/node
# The glob covers every current and future tui/*.tsx asset — no
# hand-maintained file list to drift.
ui_info "parse-checking files/opencode-permissions-kit-lib/tui/*.tsx"
if "$TSC" --noEmit --jsx preserve --noResolve --target esnext --lib esnext \
        --skipLibCheck \
        "$SHIM" \
        "$REPO_ROOT"/files/opencode-permissions-kit-lib/tui/*.tsx; then
    ui_success "tsx syntax OK."
    exit 0
fi
ui_error "tsx gate: syntax error in the shipped tui assets (see the tsc output above)"
exit 1
