#!/bin/sh
# shellmetrics.sh — one-command complexity numbers for the kit's shell
# surface (issue #255 stage 0c preparation). Runs shellspec/shellmetrics
# (itself a plain bash script) over the same file set `make lint` checks.
#
# The tool is fetched ONCE into ~/.cache/opk-shellmetrics — pinned
# exactly, because metric values vary slightly between tool versions and
# between shells (both pinned: bash, v0.5.0 @ b3bfff2). No sudo, nothing
# written inside the repo.
#
# Usage:
#   scripts/shellmetrics.sh            # pretty report (per function)
#   scripts/shellmetrics.sh --csv      # one CSV row per function
#
# The tool sorts only per-file (functions ascending by CCN, files in
# argument order). Cross-file rankings come from --csv + sort (the
# recipes also live in #346):
#   scripts/shellmetrics.sh --csv | tail -n +2 \
#     | grep -v '"<begin>"\|"<end>"' | sort -t, -k5 -rn | head -15
#   ... | sort -t, -k4 -rn ...   # same shape, ranked by LLOC instead
#   bash ~/.cache/opk-shellmetrics/shellmetrics-*/shellmetrics --csv <one-file>
#     # single-file drilldown (note the <begin>/<end> bookend rows)
#
# Any arguments are passed through to the tool (--csv, --no-color, ...).
set -u

cd "$(dirname "$0")/.." || {
    echo "error: cannot cd to the repo root" >&2
    exit 1
}

SM_SHA="b3bfff2af6880443112cdbf2ea449440b30ab9b0"
SM_URL="https://raw.githubusercontent.com/shellspec/shellmetrics/$SM_SHA/shellmetrics"
SM_DIR="$HOME/.cache/opk-shellmetrics/shellmetrics-$SM_SHA"

die() {
    echo "error: $*" >&2
    exit 1
}

if [ ! -x "$SM_DIR/shellmetrics" ]; then
    command -v curl >/dev/null 2>&1 ||
        die "curl not found — the pinned shellmetrics script is fetched once into ~/.cache/opk-shellmetrics"
    mkdir -p "$SM_DIR" || die "cannot create $SM_DIR"
    curl -fsSL "$SM_URL" -o "$SM_DIR/shellmetrics" ||
        die "downloading shellmetrics ($SM_SHA) failed"
    chmod +x "$SM_DIR/shellmetrics" || die "cannot chmod $SM_DIR/shellmetrics"
fi
bash "$SM_DIR/shellmetrics" --version >/dev/null 2>&1 ||
    die "$SM_DIR/shellmetrics does not run (bash required)"

# Same set `make lint` gates (the Makefile's SHELLCHECK_FILES
# derivation): every file under files/ and scripts/ whose first line is
# a shell shebang or a shellcheck directive. This mirror must move with
# the Makefile's derivation.
# shellcheck disable=SC2086
# (repo paths are space-free by construction — the word split is wanted)
FILES="$(find files scripts -type f -exec \
    awk 'FNR == 1 && (/^#!\/bin\/sh/ || /^# shellcheck shell=/) {print FILENAME}' {} + | sort)"
[ -n "$FILES" ] || die "no shell files found under files/ and scripts/"

# bash is deliberate: the tool parses with the running shell, and the
# metric values differ slightly between shells.
exec bash "$SM_DIR/shellmetrics" "$@" $FILES
