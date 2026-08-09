.PHONY: help test test-wrapper test-config test-hooks test-parser test-git-config verify e2e install-dev clean version check-version

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests (shell)"
	@echo "  make test-wrapper  Run wrapper validation tests"
	@echo "  make test-config   Run project config tests"
	@echo "  make test-hooks    Run git hook regression tests"
	@echo "  make test-parser   Run JSONC parser edge-case tests"
	@echo "  make test-git-config  Run git-config toggle tests"
	@echo "  make verify        Run system verification (requires install.sh)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Bump version in VERSION + KIT_TAG in install.sh/update.sh"
	@echo "  make check-version Validate VERSION and KIT_TAG match"

test: test-wrapper test-config test-hooks test-parser test-git-config
	@echo ""
	@echo "All shell tests passed."

test-wrapper:
	@echo "=== Wrapper Validation Tests ==="
	@./tests/test-wrapper-validation.sh

test-config:
	@echo "=== Project Config Tests ==="
	@./tests/test-project-config.sh

test-hooks:
	@echo "=== Git Hook Regression Tests ==="
	@./tests/test-hooks.sh

test-parser:
	@echo "=== JSONC Parser Edge-Case Tests ==="
	@./tests/test-jsonc-parser.sh

test-git-config:
	@echo "=== Git-Config Toggle Tests ==="
	@./tests/test-git-config.sh

verify:
	@./tests/verify.sh

e2e:
	@./tests/e2e/run.sh

install-dev:
	@sudo ./files/install.sh --yes $(if $(PROJECTS),--projects $(PROJECTS))

clean:
	@./files/uninstall.sh --yes

version:
	@[ -n "$(VERSION)" ] || { echo "Usage: make version VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" > VERSION
	@sed -i "s|KIT_TAG=\"\$${KIT_TAG:-[^\"]*}\"|KIT_TAG=\"\$${KIT_TAG:-$(VERSION)}\"|" files/install.sh files/update.sh
	@echo "Version set to $(VERSION) (VERSION file + KIT_TAG in install.sh/update.sh)"

check-version:
	@v="$$(cat VERSION)"; \
	i="$$(sed -n 's/.*KIT_TAG="\$${KIT_TAG:-\([^"]*\)}".*/\1/p' files/install.sh | head -1)"; \
	u="$$(sed -n 's/.*KIT_TAG="\$${KIT_TAG:-\([^"]*\)}".*/\1/p' files/update.sh | head -1)"; \
	if [ "$$v" != "$$i" ] || [ "$$v" != "$$u" ]; then \
		echo "MISMATCH: VERSION=$$v install.sh KIT_TAG=$$i update.sh KIT_TAG=$$u"; exit 1; \
	fi; \
	echo "Version consistent: $$v"
