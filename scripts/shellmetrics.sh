#!/bin/sh
# shellmetrics.sh — one-command complexity numbers for the kit's shell
# surface (issue #255 stage 0c preparation). Runs shellspec/shellmetrics
# (itself a plain bash script) over the same file set `make lint` checks.
#
# The tool is fetched ONCE into ~/.cache/opk-shellmetrics — pinned
# exactly, because metric values vary slightly between tool versions and
# between shells (both pinned: bash, v0.5.0 @ b3bfff2), and the artifact
# digest is verified against SM_SHA256 before anything is executed
# (#572 B3 — the Makefile install-shfmt #485 F28 standard for the same
# download-and-execute class). No sudo, nothing written inside the repo.
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
# Artifact digest pin (#572 B3): --version alone is a probe a compromised
# release can satisfy. The :-default keeps the pin in the script (the
# one source of truth); an env override exists ONLY as the unit-suite
# seam for stub payloads — the same sanction as the Makefile's
# SHFMT_SHA256_* command-line overrides.
SM_SHA256="${SM_SHA256:-1aab5caf551811a506f11e569a1c4cf00ddd960d9212428531efb075f45d0a5d}"

die() {
    echo "error: $*" >&2
    exit 1
}

# --- fetch + verify (issue #572 B3; block extracted by test-format-gate) ---
if [ ! -x "$SM_DIR/shellmetrics" ]; then
    command -v curl >/dev/null 2>&1 ||
        die "curl not found — the pinned shellmetrics script is fetched once into ~/.cache/opk-shellmetrics"
    mkdir -p "$SM_DIR" || die "cannot create $SM_DIR"
    # temp + verified + mv (atomic, the install-shfmt shape): a broken
    # transfer never truncates an existing cached copy in place
    _sm_tmp="$SM_DIR/.shellmetrics.tmp.$$"
    curl -fsSL "$SM_URL" -o "$_sm_tmp" ||
        {
            rm -f "$_sm_tmp"
            die "downloading shellmetrics ($SM_SHA) failed"
        }
    _sm_got="$(sha256sum "$_sm_tmp" 2>/dev/null | awk '{print $1}')"
    [ -n "$_sm_got" ] || _sm_got="$(shasum -a 256 "$_sm_tmp" 2>/dev/null | awk '{print $1}')"
    [ -n "$_sm_got" ] || {
        rm -f "$_sm_tmp"
        die "no sha256 tool found (sha256sum or shasum) — cannot verify the shellmetrics download, NOT installing"
    }
    if [ "$_sm_got" != "$SM_SHA256" ]; then
        rm -f "$_sm_tmp"
        die "shellmetrics checksum mismatch (want $SM_SHA256, got $_sm_got) — \
download corrupted or compromised, NOT installed; re-run, and update the \
SM_SHA256 pin only if the pinned commit legitimately changed"
    fi
    chmod +x "$_sm_tmp" || {
        rm -f "$_sm_tmp"
        die "cannot chmod the downloaded shellmetrics"
    }
    mv -f "$_sm_tmp" "$SM_DIR/shellmetrics" || {
        rm -f "$_sm_tmp"
        die "cannot install the downloaded shellmetrics"
    }
fi
# cached copies verify on EVERY run: the cache dir is user-writable, and
# a poisoned cache must die as loud as a compromised download (removing
# the bytes lets the next run re-fetch)
_sm_got="$(sha256sum "$SM_DIR/shellmetrics" 2>/dev/null | awk '{print $1}')"
[ -n "$_sm_got" ] || _sm_got="$(shasum -a 256 "$SM_DIR/shellmetrics" 2>/dev/null | awk '{print $1}')"
[ -n "$_sm_got" ] || die "no sha256 tool found (sha256sum or shasum) — cannot verify $SM_DIR/shellmetrics"
if [ "$_sm_got" != "$SM_SHA256" ]; then
    rm -f "$SM_DIR/shellmetrics"
    die "$SM_DIR/shellmetrics fails its digest pin (want $SM_SHA256, got $_sm_got) — removed, the next run re-fetches"
fi
bash "$SM_DIR/shellmetrics" --version >/dev/null 2>&1 ||
    die "$SM_DIR/shellmetrics does not run (bash required)"
# --- end fetch + verify ---

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
