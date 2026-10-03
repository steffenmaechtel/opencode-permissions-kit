.PHONY: help test lint check-host check-py test-opencode-as-opencode test-fs-baseline test-staged-write test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-docs test-line-length test-string-continuations test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags test-release test-e2e-sources test-browser-bridge test-security-advisories test-log test-deploy-lib test-secure-binary test-sudoers-deploy test-sandbox-policy e2e e2e-rootless e2e-ddev e2e-ddev-fresh e2e-all install-dev clean version check-version release

# Scripts checked by `make lint` (everything shipped in files/, plus the
# maintainer helpers in scripts/).
SHELLCHECK_FILES = files/install.sh \
	scripts/release.sh scripts/advisory-watch.sh \
	files/opencode-permissions-kit-lib/management/config.sh files/opencode-permissions-kit-lib/management/update.sh \
	files/opencode-permissions-kit-lib/management/status.sh files/opencode-permissions-kit-lib/management/uninstall.sh \
	files/etc/umask.sh \
	files/opencode-permissions-kit-lib/bin/opencode-as-opencode files/opencode-permissions-kit-lib/bin/opk \
	files/opencode-permissions-kit-lib/sh/log.sh files/opencode-permissions-kit-lib/sh/ui.sh \
	files/opencode-permissions-kit-lib/sh/advisories.sh \
	files/opencode-permissions-kit-lib/sh/shell-warn.sh files/opencode-permissions-kit-lib/bin/setup-container-backend \
	files/opencode-permissions-kit-lib/sh/ddev-terminal.sh files/opencode-permissions-kit-lib/sh/ddev-handover.sh \
	files/opencode-permissions-kit-lib/sh/ddev-migrate.sh files/opencode-permissions-kit-lib/bin/ddev-migrate \
	files/opencode-permissions-kit-lib/sh/ddev-hosts.sh \
	files/opencode-permissions-kit-lib/sh/fs-baseline.sh \
	files/opencode-permissions-kit-lib/sh/staged-write.sh \
	files/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh files/opencode-permissions-kit-lib/bin/browser-bridge \
	files/opencode-permissions-kit-lib/bin/socket-check files/opencode-permissions-kit-lib/bin/cwd-check \
	files/opencode-permissions-kit-lib/bin/ddev-as-opencode

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

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests (shell) + lint"
	@echo "  make check-host    Verify the host has all tools needed to contribute"
	@echo "  make lint          ShellCheck over the shipped scripts (needs shellcheck)"
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
	@echo "  make test-sandbox-policy  Run unit-suite host-path sandbox guard (0.0.42e C1)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make e2e E2E_GIT_CHANNEL=latest  Same, with the current git-core PPA git in the container (e2e-rootless forwards the knob too; e2e-ddev deliberately has no git dimension — see run-ddev.sh; issue #118)"
	@echo "  make e2e-rootless   Run docker-rootless daemon end-to-end test (Docker + systemd-in-container required; skips if unavailable)"
	@echo "  make e2e-rootless ARGS=--debug   Same, keep the container on failure + dump daemon logs"
	@echo "  make e2e-ddev       Run the real-ddev e2e suite (golden-image cache; first run builds it, see docs/design/ddev-e2e-test.md)"
	@echo "  make e2e-ddev ARGS='--fresh'     Force a golden-image rebuild (new ddev version, recipe bump)"
	@echo "  make e2e-ddev-fresh Same as e2e-ddev ARGS=--fresh"
	@echo "  make e2e-all        Run both e2e suites"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Set display version stamp (VERSION file only)"
	@echo "  make check-version Validate VERSION + consistent KIT_BRANCH in install.sh/update.sh"
	@echo "  make release VERSION=x.y.z  Cut a release: tag + fast-forward the stable mirror (maintainer)"

test: lint check-py test-opencode-as-opencode test-fs-baseline test-staged-write test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-docs test-line-length test-string-continuations test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags test-release test-e2e-sources test-browser-bridge test-security-advisories test-log test-deploy-lib test-secure-binary test-sudoers-deploy test-sandbox-policy
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
	@echo "Version stamp set to $(VERSION) (VERSION file). Release: tag it, then fast-forward 'stable' to master (docs/design/release-handling.md)."

check-version:
	@v="$$(cat VERSION)"; \
	case "$$v" in \
		[0-9]*.[0-9]*.[0-9]*) ;; \
		*) echo "VERSION file is not a semver stamp: '$$v'"; exit 1; ;; \
	esac; \
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
