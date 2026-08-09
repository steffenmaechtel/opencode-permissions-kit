.PHONY: help test test-wrapper test-config test-hooks verify e2e install-dev clean version check-version

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests"
	@echo "  make test-wrapper  Run wrapper validation tests"
	@echo "  make test-config   Run project config tests"
	@echo "  make test-hooks    Run git hook regression tests"
	@echo "  make verify        Run system verification (requires install.sh)"
	@echo "  make e2e           Run end-to-end test (Docker required)"
	@echo "  make install-dev   Quick dev install (skip prompts)"
	@echo "  make clean         Uninstall"
	@echo "  make version VERSION=x.y.z   Bump version in VERSION + package.json"
	@echo "  make check-version Validate VERSION and package.json match"

test: test-wrapper test-config test-hooks
	@echo ""
	@echo "All tests passed."

test-wrapper:
	@echo "=== Wrapper Validation Tests ==="
	@./tests/test-wrapper-validation.sh

test-config:
	@echo "=== Project Config Tests ==="
	@./tests/test-project-config.sh

test-hooks:
	@echo "=== Git Hook Regression Tests ==="
	@./tests/test-hooks.sh

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
	@sed -i 's|"version": "[^"]*"|"version": "$(VERSION)"|' package.json
	@echo "Version set to $(VERSION) (VERSION + package.json)"

check-version:
	@v="$$(cat VERSION)"; p="$$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' package.json | head -1)"; \
	if [ "$$v" != "$$p" ]; then \
		echo "MISMATCH: VERSION=$$v package.json=$$p"; exit 1; \
	fi; \
	echo "Version consistent: $$v"
