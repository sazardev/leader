# Shell scripts: shellcheck, shfmt, bats
SCRIPTS := $(shell find . -name '*.sh' -not -path './node_modules/*')

.PHONY: lint fmt check test help

lint: ## Lint with shellcheck
	shellcheck $(SCRIPTS)

fmt: ## Format with shfmt
	shfmt -w $(SCRIPTS)

check: ## Check the formatting without writing
	shfmt -d $(SCRIPTS)

test: ## Run the bats tests in test/
	bats test

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
