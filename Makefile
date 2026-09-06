.PHONY: help test lint check-host test-opencode-as-opencode test-fs-baseline test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-docs test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags e2e e2e-rootless e2e-ddev e2e-ddev-fresh e2e-all install-dev clean version check-version

# Scripts checked by `make lint` (everything shipped in files/).
SHELLCHECK_FILES = files/install.sh \
	files/opencode-permissions-kit-lib/management/config.sh files/opencode-permissions-kit-lib/management/update.sh \
	files/opencode-permissions-kit-lib/management/status.sh files/opencode-permissions-kit-lib/management/uninstall.sh \
	files/etc/umask.sh \
	files/opencode-permissions-kit-lib/bin/opencode-as-opencode files/opencode-permissions-kit-lib/bin/opk \
	files/opencode-permissions-kit-lib/sh/log.sh files/opencode-permissions-kit-lib/sh/ui.sh \
	files/opencode-permissions-kit-lib/sh/shell-warn.sh files/opencode-permissions-kit-lib/bin/setup-container-backend \
	files/opencode-permissions-kit-lib/sh/ddev-terminal.sh files/opencode-permissions-kit-lib/sh/ddev-handover.sh \
	files/opencode-permissions-kit-lib/sh/ddev-migrate.sh files/opencode-permissions-kit-lib/bin/ddev-migrate \
	files/opencode-permissions-kit-lib/sh/ddev-hosts.sh \
	files/opencode-permissions-kit-lib/sh/fs-baseline.sh \
	files/opencode-permissions-kit-lib/bin/socket-check files/opencode-permissions-kit-lib/bin/cwd-check \
	files/opencode-permissions-kit-lib/bin/ddev-as-opencode

# Intentional deviations, excluded repo-wide:
#   SC1090/SC1091 — kit scripts source helpers/configs via variables
#                  (checkout -> temp fetch -> installed library lookups)
#   SC2034        — sourced libs / fallback blocks define vars used by callers
#   SC3043        — 'local' is not POSIX but dash AND bash support it; the
#                  kit targets exactly those two shells
SHELLCHECK_EXCLUDES = SC1090,SC1091,SC2034,SC3043

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests (shell) + lint"
	@echo "  make check-host    Verify the host has all tools needed to contribute"
	@echo "  make lint          ShellCheck over the shipped scripts (needs shellcheck)"
	@echo "  make test-opencode-as-opencode  Run wrapper (opencode-as-opencode) validation tests"
	@echo "  make test-fs-baseline  Run group-baseline progress tests (issue #14)"
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
	@echo "  make verify        Run system verification (requires install.sh)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
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

test: lint test-opencode-as-opencode test-fs-baseline test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-ddev-migrate test-ddev-hosts test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-docs test-install-args test-kit-files test-tui-mode test-uninstall test-status test-update-flags
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
	@sh ./tests/e2e/run.sh

e2e-rootless:
	@sh ./tests/e2e/run-docker-rootless.sh $(if $(ARGS),$(ARGS))

e2e-ddev:
	@sh ./tests/e2e/run-ddev.sh $(if $(ARGS),$(ARGS))

e2e-ddev-fresh:
	@sh ./tests/e2e/run-ddev.sh --fresh

e2e-all: e2e e2e-rootless

install-dev:
	@sudo ./files/install.sh --yes $(if $(PROJECTS),--projects $(PROJECTS))

clean:
	@./files/uninstall.sh --yes

version:
	@[ -n "$(VERSION)" ] || { echo "Usage: make version VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" > VERSION
	@echo "Version stamp set to $(VERSION) (VERSION file). Install URLs track the master branch, no tag needed."

check-version:
	@v="$$(cat VERSION)"; \
	case "$$v" in \
		[0-9]*.[0-9]*.[0-9]*) ;; \
		*) echo "VERSION file is not a semver stamp: '$$v'"; exit 1; ;; \
	esac; \
	i="$$(sed -n 's/.*KIT_BRANCH="\$${KIT_BRANCH:-\([^"]*\)}".*/\1/p' files/install.sh | head -1)"; \
	u="$$(sed -n 's/.*KIT_BRANCH="\$${KIT_BRANCH:-\([^"]*\)}".*/\1/p' files/opencode-permissions-kit-lib/management/update.sh | head -1)"; \
	if [ -z "$$i" ] || [ "$$i" != "$$u" ]; then \
		echo "MISMATCH: install.sh KIT_BRANCH=$$i update.sh KIT_BRANCH=$$u"; exit 1; \
	fi; \
	echo "Version stamp: $$v  (installs from branch '$$i')"

test-project-paths:
	@echo "=== Project Path Policy Tests ==="
	@./tests/unit/test-project-paths.sh

test-workflows:
	@echo "=== CI Workflow Consistency Tests ==="
	@./tests/unit/test-workflows.sh

test-docs:
	@echo "=== Docs Link Check ==="
	@./tests/unit/test-docs.sh

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
	@echo "=== update.sh Flags Tests ==="
	@./tests/unit/test-update-flags.sh
