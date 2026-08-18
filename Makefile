.PHONY: help test lint check-host test-wrapper test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows verify e2e e2e-rootless e2e-all install-dev clean version check-version

# Scripts checked by `make lint` (everything shipped in files/).
SHELLCHECK_FILES = files/install.sh files/config.sh files/update.sh files/status.sh files/uninstall.sh files/umask.sh \
	files/opencode-permissions-kit-lib/wrapper files/opencode-permissions-kit-lib/kit \
	files/opencode-permissions-kit-lib/log.sh files/opencode-permissions-kit-lib/ui.sh \
	files/opencode-permissions-kit-lib/shell-warn.sh files/opencode-permissions-kit-lib/setup-container-backend.sh \
	files/opencode-permissions-kit-lib/ddev-as-opencode.sh files/opencode-permissions-kit-lib/ddev-handover.sh \
	files/opencode-permissions-kit-lib/migrate-denies.sh \
	files/opencode-permissions-kit-lib/bin/socket-check.sh files/opencode-permissions-kit-lib/bin/ddev-as-opencode

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
	@echo "  make test-wrapper  Run wrapper validation tests"
	@echo "  make test-parser   Run JSONC parser edge-case tests"
	@echo "  make test-git-config  Run git-config toggle tests"
	@echo "  make test-container-backend  Run container-backend tests"
	@echo "  make test-bypass-guard  Run wrapper-bypass guard tests"
	@echo "  make test-ddev-as-opencode  Run ddev-as-opencode (ddev always runs as opencode) tests"
	@echo "  make test-mkcert-reuse    Run mkcert CA reuse tests"
	@echo "  make test-wsl-exposure   Run WSL2 /mnt/c exposure warning tests"
	@echo "  make test-ui         Run shared UI helper tests"
	@echo "  make test-kit-cli   Run CLI dispatcher tests"
	@echo "  make test-project-paths  Run project path policy tests"
	@echo "  make test-workflows Run CI workflow consistency tests"
	@echo "  make test-docs     Run docs link check"
	@echo "  make verify        Run system verification (requires install.sh)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make e2e-rootless   Run docker-rootless daemon end-to-end test (Docker + systemd-in-container required; skips if unavailable)"
	@echo "  make e2e-rootless ARGS=--debug   Same, keep the container on failure + dump daemon logs"
	@echo "  make e2e-all        Run both e2e suites"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Set display version stamp (VERSION file only)"
	@echo "  make check-version Validate VERSION + consistent KIT_BRANCH in install.sh/update.sh"

test: lint test-wrapper test-parser test-git-config test-container-backend test-bypass-guard test-ddev-as-opencode test-mkcert-reuse test-wsl-exposure test-ui test-kit-cli test-project-paths test-workflows test-docs
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

test-wrapper:
	@echo "=== Wrapper Validation Tests ==="
	@./tests/test-wrapper-validation.sh

test-parser:
	@echo "=== JSONC Parser Edge-Case Tests ==="
	@./tests/test-jsonc-parser.sh

test-git-config:
	@echo "=== Git-Config Toggle Tests ==="
	@./tests/test-git-config.sh

test-container-backend:
	@echo "=== Container Backend Tests ==="
	@./tests/test-container-backend.sh

test-bypass-guard:
	@echo "=== Wrapper-Bypass Guard Tests ==="
	@./tests/test-bypass-guard.sh

test-wsl-exposure:
	@echo "=== WSL2 /mnt/c exposure Tests ==="
	@./tests/test-wsl-exposure.sh

test-ui:
	@echo "=== UI Helper Tests ==="
	@./tests/test-ui.sh

test-kit-cli:
	@echo "=== CLI Dispatcher Tests ==="
	@./tests/test-kit-cli.sh

test-mkcert-reuse:
	@echo "=== mkcert CA reuse Tests ==="
	@./tests/test-mkcert-reuse.sh

test-ddev-as-opencode:
	@echo "=== ddev-as-opencode Tests ==="
	@./tests/test-ddev-as-opencode.sh

verify:
	@./tests/verify.sh

e2e:
	@sh ./tests/e2e/run.sh

e2e-rootless:
	@sh ./tests/e2e/run-docker-rootless.sh $(if $(ARGS),$(ARGS))

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
	u="$$(sed -n 's/.*KIT_BRANCH="\$${KIT_BRANCH:-\([^"]*\)}".*/\1/p' files/update.sh | head -1)"; \
	if [ -z "$$i" ] || [ "$$i" != "$$u" ]; then \
		echo "MISMATCH: install.sh KIT_BRANCH=$$i update.sh KIT_BRANCH=$$u"; exit 1; \
	fi; \
	echo "Version stamp: $$v  (installs from branch '$$i')"

test-project-paths:
	@echo "=== Project Path Policy Tests ==="
	@./tests/test-project-paths.sh

test-workflows:
	@echo "=== CI Workflow Consistency Tests ==="
	@./tests/test-workflows.sh

test-docs:
	@echo "=== Docs Link Check ==="
	@./tests/test-docs.sh
