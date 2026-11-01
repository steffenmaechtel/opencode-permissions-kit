.PHONY: help test lint fmt fmt-scope install-shfmt check-host check-py test-opencode-as-opencode test-fs-baseline test-staged-write test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-check-host test-docs test-skills-lint test-reviews-meta-aggregate test-rules-meta test-rules-revisit test-line-length test-string-continuations test-format-gate test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags test-release test-e2e-sources test-browser-bridge test-security-advisories test-log test-deploy-lib test-secure-binary test-sudoers-deploy test-sandbox-policy test-pages test-rules-index-parity rules-report e2e e2e-rootless e2e-ddev e2e-ddev-fresh e2e-all install-dev clean version check-version release

# Scripts checked by `make lint` — DERIVED FROM DISK (0.0.42d C4 /
# 0.0.42e C10): every file under files/ and scripts/ whose first line is
# a shell shebang or a `# shellcheck shell=` directive. The list cannot
# rot when scripts are added — the old hand-maintained list had silently
# dropped seven shipped scripts. Python helpers are gated by check-py.
SHELLCHECK_FILES = $(shell find files scripts -type f -exec \
	awk 'FNR == 1 && (/^[#]!\/bin\/sh/ || /^[#] shellcheck shell=/) {print FILENAME}' {} + | sort)

# Intentional deviations, excluded repo-wide:
#   SC1090/SC1091 — kit scripts source helpers/configs via variables
#                  (checkout -> temp fetch -> installed library lookups)
#   SC2034        — sourced libs / fallback blocks define vars used by callers
#   SC3043        — 'local' is not POSIX but dash AND bash support it; the
#                  kit targets exactly those two shells
#   SC3040        — guarded `(set -o pipefail)` probe: bash enables it, dash
#                  skips it (the 2>/dev/null subshell test) — deliberate
# SC2140 excluded since the line-length ratchet (tests/unit/test-line-length.sh):
# wrapping over-long message strings uses the POSIX adjacent-string line
# continuation idiom ("part one"\
# "part two") -- byte-identical output, flagged by SC2140 on every split.
SHELLCHECK_EXCLUDES = SC1090,SC1091,SC2034,SC3043,SC3040,SC2140

# make install-shfmt puts the pinned binary in ~/.local/bin -- make
# every make-driven shfmt call find it there, whatever the invoking
# shell's PATH (agent sessions, non-login shells, fresh tabs). APPEND,
# not prepend (round d H2): a stray binary in ~/.local/bin (a curl,
# say) must never shadow system tools or the suite's PATH-injected
# stubs inside nested make calls -- the resolver only needs the
# FALLBACK position. The version pin still guards: whatever resolves
# first must be exactly v3.14.1. Direct `shfmt` calls outside make
# keep needing the PATH (new login shells usually get it from the
# ~/.profile snippet once the dir exists -- where that snippet and a
# profile-reading login shell exist; round d I3).
export PATH := $(PATH):$(HOME)/.local/bin

# shfmt -- canonical formatter for every kit shell script (issue #255
# stage 0a). Pinned EXACTLY: formatting output differs between shfmt
# versions (measured 2026-10-28: 3.7.0 and 3.12.0 each reformat lines
# that 3.14.1 leaves alone -- a mixed-version gate flaps between
# contributor hosts and CI), and the dash language variant first ships
# in 3.14.x (3.13.0 still rejects -ln dash). Same settings live in
# .editorconfig for editors; the equivalence is pinned by
# tests/unit/test-format-gate.sh.
SHFMT_VERSION = 3.14.1
SHFMT_FLAGS = -ln dash -i 4 -ci
# Tests' own scripts: every TRACKED .sh under tests/. Tracked-only on
# purpose: warm checkouts carry untracked foreign shell (e2e camino
# share-providers, cache dumps -- bash, not ours to format). Asymmetry,
# deliberate (review a B5, #301): the shipped half (SHELLCHECK_FILES)
# derives from DISK, so an untracked shebang-first scratch file under
# files/ or scripts/ reddens both gates -- nothing foreign lives there
# today (verified review a B5), and a stray scratch file failing loud
# under files/ is the safer direction.
SHFMT_TEST_FILES = $(shell git ls-files -- 'tests/*.sh' | sort)

# Single-source derivation link (review a B3, #301):
# tests/unit/test-format-gate.sh reads the gate scope from HERE, never
# re-derives it -- a drift between the suite's copy and the gate's
# actual scope is impossible by construction.
fmt-scope:
	@echo $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES)

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests (shell) + lint"
	@echo "  make check-host    Verify the host has all tools needed to contribute"
	@echo "  make lint          ShellCheck + shfmt format gate over the kit shell (needs both)"
	@echo "  make fmt           One-shot shfmt -w over the whole gate scope"
	@echo "  make fmt-scope     Print the gate's file scope (single source, used by the format-gate suite)"
	@echo "  make install-shfmt Download the pinned shfmt to ~/.local/bin (no root)"
	@echo "  make test-opencode-as-opencode  Run wrapper (opencode-as-opencode) validation tests"
	@echo "  make test-fs-baseline  Run group-baseline progress tests (issue #14)"
	@echo "  make test-staged-write  Run symlink-safe write / handover gate tests (0.0.39g)"
	@echo "  make test-parser   Run JSONC parser edge-case tests"
	@echo "  make test-git-config  Run git-config toggle tests"
	@echo "  make test-container-backend  Run container-backend tests"
	@echo "  make test-bypass-guard  Run wrapper-bypass guard tests"
	@echo "  make test-ddev-as-opencode  Run ddev-as-opencode (ddev always runs as opencode) tests"
	@echo "  make test-ddev-migrate    Run ddev database migration tests"
	@echo "  make test-ddev-hosts      Run Windows hosts bridge tests"
	@echo "  make test-mkcert-reuse    Run mkcert CA reuse tests"
	@echo "  make test-wsl-exposure   Run WSL2 /mnt/c exposure warning tests"
	@echo "  make test-ui         Run shared UI helper tests"
	@echo "  make test-kit-cli   Run CLI dispatcher tests"
	@echo "  make test-project-paths  Run project path policy tests"
	@echo "  make test-workflows Run CI workflow consistency tests"
	@echo "  make test-docs     Run docs link check"
	@echo "  make test-install-args  Run install.sh arg-parsing tests"
	@echo "  make test-kit-files     Run kit file list consistency tests"
	@echo "  make test-uninstall     Run uninstall.sh tests"
	@echo "  make test-status        Run status.sh tests"
	@echo "  make test-e2e-sources   Run e2e source-consistency tests"
	@echo "  make test-browser-bridge  Run WSL browser bridge tests"
	@echo "  make test-security-advisories  Run advisory database/watch tests"
	@echo "  make test-deploy-lib     Run lib deploy manifest tests (0.0.41d)"
	@echo "  make test-secure-binary  Run binary hardening tests (0.0.41c)"
	@echo "  make test-sudoers-deploy Run sudoers pipeline tests (0.0.41b)"
	@echo "  make test-sandbox-policy  Run unit-suite host-path sandbox guard (0.0.42e C1)"
	@echo "  make test-rules-meta    Run rule-meta audit pins (invariants 1-9)"
	@echo "  make test-rules-revisit  Run rule-meta revisit workflow pins (phase 4)"
	@echo "  make test-skills-lint    Run .agents/skills frontmatter lint (issue #178)"
	@echo "  make rules-report  Show the rule-meta revisit worklist (overdue + horizon + approval queue)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make e2e E2E_GIT_CHANNEL=latest  Same, with the current git-core PPA git in the container (e2e-rootless forwards the knob too; e2e-ddev deliberately has no git dimension — see run-ddev.sh; issue #118)"
	@echo "  make e2e-rootless   Run docker-rootless daemon end-to-end test (Docker + systemd-in-container required; skips if unavailable)"
	@echo "  make e2e-rootless ARGS=--debug   Same, keep the container on failure + dump daemon logs"
	@echo "  make e2e-ddev       Run the real-ddev e2e suite (golden-image cache; first run builds it, see internal/records/ddev-e2e-test.md)"
	@echo "  make e2e-ddev ARGS='--fresh'     Force a golden-image rebuild (new ddev version, recipe bump)"
	@echo "  make e2e-ddev-fresh Same as e2e-ddev ARGS=--fresh"
	@echo "  make e2e-all        Run both e2e suites"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Set display version stamp (VERSION file only)"
	@echo "  make check-version Validate VERSION + consistent KIT_BRANCH in install.sh/update.sh"
	@echo "  make release VERSION=x.y.z  Cut a release: tag + fast-forward the stable mirror (maintainer)"

test: lint check-py test-opencode-as-opencode test-fs-baseline test-staged-write test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-check-host test-docs test-skills-lint test-reviews-meta-aggregate test-rules-meta test-rules-revisit test-line-length test-string-continuations test-format-gate test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags test-release test-e2e-sources test-browser-bridge test-security-advisories test-log test-deploy-lib test-secure-binary test-sudoers-deploy test-sandbox-policy test-pages test-rules-index-parity
	@echo ""
	@echo "All shell tests passed."

lint:
	@echo "=== ShellCheck (shipped scripts) ==="
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "error:  shellcheck is required for 'make lint' (part of 'make test')."; \
		echo "        Debian/Ubuntu:  sudo apt install shellcheck"; \
		echo "        macOS:          brew install shellcheck"; \
		echo "        other:          https://github.com/koalaman/shellcheck#installing"; \
		echo "        or run:         sh tests/check-host.sh  (checks all contributor tools)"; \
		exit 1; \
	fi
	@shellcheck --severity=warning --exclude=$(SHELLCHECK_EXCLUDES) $(SHELLCHECK_FILES)
	@echo "ShellCheck passed."
	@echo "=== shfmt (format gate, pinned v$(SHFMT_VERSION)) ==="
	@if ! command -v shfmt >/dev/null 2>&1; then \
		echo "error:  shfmt is required for 'make lint' (part of 'make test')."; \
		echo "        install with:  make install-shfmt"; \
		exit 1; \
	fi
	@if [ "$$(shfmt --version)" != "v$(SHFMT_VERSION)" ]; then \
		echo "error:  shfmt $$(shfmt --version) found, v$(SHFMT_VERSION) required -- the pin is"; \
		echo "        exact on purpose: formatting output drifts between shfmt versions."; \
		echo "        fix with:       make install-shfmt"; \
		exit 1; \
	fi
	@_err="$$(shfmt -l $(SHFMT_FLAGS) $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES) 2>&1 >/dev/null)"; \
	if [ -n "$$_err" ]; then \
		echo "error:  shfmt cannot parse file(s) in the gate scope:"; \
		printf '%s\n' "$$_err" | sed 's/^/        /'; \
		echo "        a parse error must fail the gate, not pass it silently."; \
		exit 1; \
	fi
	@if [ -n "$$(shfmt -l $(SHFMT_FLAGS) $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES))" ]; then \
		echo "error:  files differ from shfmt's canonical format:"; \
		shfmt -l $(SHFMT_FLAGS) $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES) | sed 's/^/        /'; \
		echo "        fix with:       make fmt"; \
		exit 1; \
	fi
	@_err="$$(shfmt -l $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES) 2>&1 >/dev/null)"; \
	if [ -n "$$_err" ]; then \
		echo "error:  bare shfmt cannot parse file(s) in the gate scope:"; \
		printf '%s\n' "$$_err" | sed 's/^/        /'; \
		exit 1; \
	fi
	@if [ -n "$$(shfmt -l $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES))" ]; then \
		echo "error:  .editorconfig disagrees with the gate flags (bare shfmt lists files):"; \
		shfmt -l $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES) | sed 's/^/        /'; \
		echo "        keep .editorconfig equivalent to $(SHFMT_FLAGS); an extensionless"; \
		echo "        shell script outside files/**/bin/ needs its own section there."; \
		exit 1; \
	fi
	@echo "shfmt gate passed."

# One-shot canonical format over the whole gate scope (issue #255
# stage 0a). Run before committing when shfmt -l flags your edits.
fmt:
	@if ! command -v shfmt >/dev/null 2>&1 || \
		[ "$$(shfmt --version)" != "v$(SHFMT_VERSION)" ]; then \
		echo "error:  shfmt v$(SHFMT_VERSION) required first:  make install-shfmt"; \
		exit 1; \
	fi
	@shfmt -w $(SHFMT_FLAGS) $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES)
	@echo "formatted (gate scope): $$(echo $(SHELLCHECK_FILES) $(SHFMT_TEST_FILES) | wc -w) files"

# Download the pinned shfmt into ~/.local/bin (single static binary,
# no root). CI uses this too -- the Makefile is the one source of the
# version pin. Fail-loud + atomic (review a B1/B2, #301): every failure
# edge exits 1 explicitly (the trailing PATH-note case must never zero a
# failed run), and the download lands on a temp name -- a broken
# transfer never truncates an existing install in place. SHFMT_BIN_DIR
# (env) redirects the destination so the unit suite can pin this target
# inside its scratch sandbox; set-but-EMPTY fails loud (the `-` form
# keeps the empty value, mkdir errors -- review b D6) and a stale-temp
# sweep at the start clears orphans from interrupted runs, age-guarded
# (review b D7 + c F3): only temps older than 30 minutes match, so a
# concurrent run's in-flight temp (seconds old) is never swept.
install-shfmt:
	@case "$$(uname -s)/$$(uname -m)" in \
		Linux/x86_64) plat=linux_amd64 ;; \
		Linux/aarch64) plat=linux_arm64 ;; \
		Darwin/x86_64) plat=darwin_amd64 ;; \
		Darwin/arm64) plat=darwin_arm64 ;; \
		*) echo "error: unsupported platform for the shfmt download -- install v$(SHFMT_VERSION) manually"; exit 1 ;; \
	esac; \
	bin="$${SHFMT_BIN_DIR-$${HOME}/.local/bin}"; \
	mkdir -p "$$bin" || exit 1; \
	find "$$bin" -name '.shfmt.tmp.*' -mmin +30 -delete 2>/dev/null || true; \
	tmp="$$bin/.shfmt.tmp.$$"; \
	echo "downloading shfmt v$(SHFMT_VERSION) ($$plat) -> $$bin/shfmt"; \
	curl -fsSL -o "$$tmp" \
		"https://github.com/mvdan/sh/releases/download/v$(SHFMT_VERSION)/shfmt_v$(SHFMT_VERSION)_$$plat" \
		|| { rm -f "$$tmp"; exit 1; }; \
	chmod +x "$$tmp" || { rm -f "$$tmp"; exit 1; }; \
	"$$tmp" --version >/dev/null || { rm -f "$$tmp"; echo "error: downloaded shfmt failed its --version probe"; exit 1; }; \
	mv -f "$$tmp" "$$bin/shfmt" || { rm -f "$$tmp"; exit 1; }; \
	"$$bin/shfmt" --version
# No trailing PATH-note case (round d H1): the resolver export above
# puts the bin dir on every recipe PATH, so "not on your PATH" could
# never fire in make context -- dead guard, removed. The final
# --version print is now the recipe's rc-relevant last command (a
# failed probe reddens the target directly; every download edge still
# exits 1 explicitly above).

check-host:
	@echo "=== Contributor host check ==="
	@sh tests/check-host.sh

# Python syntax gate (review 0.0.39a C5): a syntax error in the shipped
# py/ scripts otherwise ships green until an e2e run (or a user) hits it.
# PYTHONPYCACHEPREFIX keeps the bytecode cache out of the repo tree (the
# workflow-consistency test derives requirements from files/ on disk).
# The tui/*.tsx assets are gated CI-only by tests/tsx-syntax-gate.sh
# (issue #114): a parse check needs node + pinned typescript — kept out
# of the unit-suite host requirements on purpose.
check-py:
	@echo "=== Python syntax check (shipped scripts) ==="
	@PYTHONPYCACHEPREFIX="$$(mktemp -d)" python3 -m py_compile \
		files/opencode-permissions-kit-lib/py/jsonc-parser.py \
		files/opencode-permissions-kit-lib/py/tui-register.py
	@echo "Python syntax OK."

test-opencode-as-opencode:
	@echo "=== Wrapper Validation Tests ==="
	@./tests/unit/test-opencode-as-opencode.sh

test-parser:
	@echo "=== JSONC Parser Edge-Case Tests ==="
	@./tests/unit/test-jsonc-parser.sh

test-git-config:
	@echo "=== Git-Config Toggle Tests ==="
	@./tests/unit/test-git-config.sh

test-container-backend:
	@echo "=== Container Backend Tests ==="
	@./tests/unit/test-container-backend.sh

test-bypass-guard:
	@echo "=== Wrapper-Bypass Guard Tests ==="
	@./tests/unit/test-bypass-guard.sh

test-wsl-exposure:
	@echo "=== WSL2 /mnt/c exposure Tests ==="
	@./tests/unit/test-wsl-exposure.sh

test-ui:
	@echo "=== UI Helper Tests ==="
	@./tests/unit/test-ui.sh

test-kit-cli:
	@echo "=== CLI Dispatcher Tests ==="
	@./tests/unit/test-kit-cli.sh

test-mkcert-reuse:
	@echo "=== mkcert CA reuse Tests ==="
	@./tests/unit/test-mkcert-reuse.sh

test-ddev-as-opencode:
	@echo "=== ddev-as-opencode Tests ==="
	@./tests/unit/test-ddev-as-opencode.sh

test-ddev-migrate:
	@echo "=== ddev database migration Tests ==="
	@./tests/unit/test-ddev-migrate.sh

test-ddev-hosts:
	@echo "=== Windows hosts bridge Tests ==="
	@./tests/unit/test-ddev-hosts.sh

e2e:
	@E2E_OC_VERSION='$(E2E_OC_VERSION)' E2E_GIT_CHANNEL='$(E2E_GIT_CHANNEL)' sh ./tests/e2e/run.sh

e2e-rootless:
	@E2E_OC_VERSION='$(E2E_OC_VERSION)' E2E_GIT_CHANNEL='$(E2E_GIT_CHANNEL)' sh ./tests/e2e/run-docker-rootless.sh $(if $(ARGS),$(ARGS))

e2e-ddev:
	@E2E_OC_VERSION='$(E2E_OC_VERSION)' sh ./tests/e2e/run-ddev.sh $(if $(ARGS),$(ARGS))

e2e-ddev-fresh:
	@sh ./tests/e2e/run-ddev.sh --fresh

e2e-all: e2e e2e-rootless

install-dev:
	@sudo ./files/install.sh --yes $(if $(PROJECTS),--projects $(PROJECTS))

clean:
	@./files/opencode-permissions-kit-lib/management/uninstall.sh --yes

version:
	@[ -n "$(VERSION)" ] || { echo "Usage: make version VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" > VERSION
	@echo "Version stamp set to $(VERSION) (VERSION file). Release: tag it, then fast-forward 'stable' to master (internal/process/release-handling.md)."

check-version:
	@v="$$(cat VERSION)"; \
	ok=1; \
	oldifs="$$IFS"; IFS=.; set -- $$v; IFS="$$oldifs"; \
	[ "$$#" -eq 3 ] || ok=0; \
	for c in "$$@"; do case "$$c" in ''|*[!0-9]*) ok=0 ;; esac; done; \
	if [ "$$ok" -ne 1 ]; then \
		echo "VERSION file is not a semver stamp (X.Y.Z, digits only): '$$v'"; exit 1; \
	fi; \
	i="$$(sed -n 's/.*KIT_BRANCH="\$${KIT_BRANCH:-\([^"]*\)}".*/\1/p' files/install.sh | head -1)"; \
	u="$$(sed -n 's/.*KIT_BRANCH="\$${KIT_BRANCH:-\([^"]*\)}".*/\1/p' files/opencode-permissions-kit-lib/management/update.sh | head -1)"; \
	normalize() { printf '%s' "$$1" | sed 's/^\$${[^:]*:-//; s/}$$//'; }; \
	i="$$(normalize "$$i")"; u="$$(normalize "$$u")"; \
	if [ -z "$$i" ] || [ "$$i" != "$$u" ]; then \
		echo "MISMATCH: install.sh KIT_BRANCH=$$i update.sh KIT_BRANCH=$$u"; exit 1; \
	fi; \
	if [ "$$i" != "master" ]; then \
		echo "UNEXPECTED DEFAULT: in-code KIT_BRANCH default must stay 'master' (stable is docs-only + stamp), got '$$i'"; exit 1; \
	fi; \
	echo "Version stamp: $$v  (in-code channel default '$$i'; docs one-liners use the stable mirror)"

release:
	@[ -n "$(VERSION)" ] || { echo "Usage: make release VERSION=x.y.z"; exit 1; }
	@./scripts/release.sh $(VERSION) $(if $(ARGS),$(ARGS))

test-project-paths:
	@echo "=== Project Path Policy Tests ==="
	@./tests/unit/test-project-paths.sh

test-workflows:
	@echo "=== CI Workflow Consistency Tests ==="
	@./tests/unit/test-workflows.sh

test-docs:
	@echo "=== Docs Link Check ==="
	@./tests/unit/test-docs.sh

test-line-length:
	@echo "=== Line Length Ratchet ==="
	@./tests/unit/test-line-length.sh

test-string-continuations:
	@echo "=== String-Continuation Guard ==="
	@./tests/unit/test-string-continuations.sh

test-check-host:
	@echo "=== Check-Host gh Warning Pins (issue #335) ==="
	@./tests/unit/test-check-host.sh

test-format-gate:
	@echo "=== shfmt Format-Gate Pins (issue #255 stage 0a) ==="
	@./tests/unit/test-format-gate.sh

test-install-args:
	@echo "=== install.sh Arg-Parsing Tests ==="
	@./tests/unit/test-install-args.sh

test-kit-files:
	@echo "=== Kit File List Consistency Tests ==="
	@./tests/unit/test-kit-files.sh

test-tui-mode:
	@echo "=== TUI Mode Display Tests ==="
	@./tests/unit/test-tui-mode.sh

test-uninstall:
	@echo "=== Uninstall Tests ==="
	@./tests/unit/test-uninstall.sh

test-status:
	@echo "=== Status Tests ==="
	@./tests/unit/test-status.sh

test-update-flags:
	@echo "=== update.sh Flag Tests ==="
	@./tests/unit/test-update-flags.sh

test-release:
	@echo "=== Release Helper Tests ==="
	@./tests/unit/test-release.sh

test-fs-baseline:
	@echo "=== Group-Baseline Progress Tests ==="
	@./tests/unit/test-fs-baseline.sh

test-staged-write:
	@echo "=== Symlink-Safe Write / Handover Gate Tests (0.0.39g) ==="
	@./tests/unit/test-staged-write.sh

test-e2e-sources:
	@echo "=== E2E Source-Consistency Tests ==="
	@./tests/unit/test-e2e-sources.sh

test-browser-bridge:
	@echo "=== WSL Browser Bridge Tests ==="
	@./tests/unit/test-browser-bridge.sh

test-security-advisories:
	@echo "=== Security Advisory Database/Watch Tests ==="
	@./tests/unit/test-security-advisories.sh

test-log:
	@echo "=== Audit Log Tests ==="
	@./tests/unit/test-log.sh

test-deploy-lib:
	@echo "=== Lib Deploy Manifest Tests (0.0.41d) ==="
	@./tests/unit/test-deploy-lib.sh

test-secure-binary:
	@echo "=== Binary Hardening Tests (0.0.41c) ==="
	@./tests/unit/test-secure-binary.sh

test-sudoers-deploy:
	@echo "=== Sudoers Pipeline Tests (0.0.41b) ==="
	@./tests/unit/test-sudoers-deploy.sh

test-sandbox-policy:
	@echo "=== Unit-Test Sandbox Policy Tests (0.0.42e C1) ==="
	@./tests/unit/test-sandbox-policy.sh

test-pages:
	@echo "=== Pages Site Tests ==="
	@./tests/unit/test-pages.sh

test-rules-index-parity:
	@echo "=== Rules INDEX Parity Tests ==="
	@./tests/unit/test-rules-index-parity.sh

test-skills-lint:
	@echo "=== Agent Skills Lint (issue #178) ==="
	@./tests/unit/test-skills-lint.sh

test-reviews-meta-aggregate:
	@echo "=== Reviews-Meta Aggregator (compat + PR-stem era, run 2026-10-22) ==="
	@./tests/unit/test-reviews-meta-aggregate.sh

test-rules-meta:
	@echo "=== Rule-Meta Audit Pins (invariants 1-9) ==="
	@./tests/unit/test-rules-meta.sh

test-rules-revisit:
	@echo "=== Rule-Meta Revisit Workflow Pins (phase 4) ==="
	@./tests/unit/test-rules-revisit.sh

rules-report:
	@sh scripts/rules-report.sh
