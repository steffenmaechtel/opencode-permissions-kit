.PHONY: help test test-wrapper test-parser test-git-config test-container-backend test-bypass-guard test-migration test-ddev-as-opencode verify e2e e2e-rootless e2e-all install-dev clean version check-version

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests (shell)"
	@echo "  make test-wrapper  Run wrapper validation tests"
	@echo "  make test-parser   Run JSONC parser edge-case tests"
	@echo "  make test-git-config  Run git-config toggle tests"
	@echo "  make test-container-backend  Run container-backend tests"
	@echo "  make test-bypass-guard  Run wrapper-bypass guard tests"
	@echo "  make test-migration    Run hard-deny migration tests"
	@echo "  make test-ddev-as-opencode  Run ddev-as-opencode (ddev always runs as opencode) tests"
	@echo "  make verify        Run system verification (requires install.sh)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make e2e-rootless   Run docker-rootless daemon end-to-end test (Docker + systemd-in-container required; skips if unavailable)"
	@echo "  make e2e-rootless ARGS=--debug   Same, keep the container on failure + dump daemon logs"
	@echo "  make e2e-all        Run both e2e suites"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Set display version stamp (VERSION file only)"
	@echo "  make check-version Validate VERSION + consistent KIT_BRANCH in install.sh/update.sh"

test: test-wrapper test-parser test-git-config test-container-backend test-bypass-guard test-migration test-ddev-as-opencode
	@echo ""
	@echo "All shell tests passed."

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

test-migration:
	@echo "=== Hard-Deny Migration Tests ==="
	@./tests/test-migration.sh

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
