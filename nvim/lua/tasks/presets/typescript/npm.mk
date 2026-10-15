# TypeScript / Node with npm: the package.json scripts behind short targets
.PHONY: install dev build test lint fmt typecheck clean help

install: ## Install the dependencies (clean, from the lockfile)
	npm ci

dev: ## Run the dev server
	npm run dev

build: ## Build for production
	npm run build

test: ## Run the tests
	npm test

lint: ## Lint
	npm run lint

fmt: ## Format with prettier
	npx prettier --write .

typecheck: ## Type check without emitting
	npx tsc --noEmit

clean: ## Remove build output and node_modules
	rm -rf dist build node_modules

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
