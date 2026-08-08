.PHONY: help test test-wrapper test-config verify setup-dev clean

help:
	@echo "opencode permissions kit — dev makefile"
	@echo ""
	@echo "  make test          Run all self-contained tests"
	@echo "  make test-wrapper  Run wrapper validation tests"
	@echo "  make test-config   Run project config tests"
	@echo "  make verify        Run system verification (requires setup.sh)"
	@echo "  make setup-dev     Quick dev setup (skip prompts)"
	@echo "  make clean         Uninstall"

test: test-wrapper test-config
	@echo ""
	@echo "All tests passed."

test-wrapper:
	@echo "=== Wrapper Validation Tests ==="
	@./tests/test-wrapper-validation.sh

test-config:
	@echo "=== Project Config Tests ==="
	@./tests/test-project-config.sh

verify:
	@./tests/verify.sh

setup-dev:
	@sudo ./files/setup.sh --yes $(if $(PROJECTS),--projects $(PROJECTS))

clean:
	@./files/uninstall.sh --yes
