# TypeScript / Node with pnpm
.PHONY: install dev build test lint fmt typecheck clean help

install: ## Install the dependencies from the lockfile
	pnpm install --frozen-lockfile

dev: ## Run the dev server
	pnpm dev

build: ## Build for production
	pnpm build

test: ## Run the tests
	pnpm test

lint: ## Lint
	pnpm lint

fmt: ## Format with prettier
	pnpm exec prettier --write .

typecheck: ## Type check without emitting
	pnpm exec tsc --noEmit

clean: ## Remove build output and node_modules
	rm -rf dist build node_modules

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
