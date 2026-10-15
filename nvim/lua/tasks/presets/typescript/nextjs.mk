# Next.js: dev server, production build and start, lint, type check
PM ?= npm

.PHONY: dev build start lint typecheck clean help

dev: ## Run the dev server
	$(PM) run dev

build: ## Production build
	$(PM) run build

start: build ## Serve the production build
	$(PM) run start

lint: ## Lint
	$(PM) run lint

typecheck: ## Type check without emitting
	npx tsc --noEmit

clean: ## Remove .next/ and node_modules
	rm -rf .next node_modules

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
