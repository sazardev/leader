# Python with uv: sync, run, test, lint, type check
.PHONY: sync run test lint fmt typecheck lock clean help

sync: ## Install the locked dependencies
	uv sync

run: ## Run main.py
	uv run python main.py

test: ## Run the tests
	uv run pytest

lint: ## Lint with ruff
	uv run ruff check .

fmt: ## Format with ruff
	uv run ruff format .

typecheck: ## Type check with mypy
	uv run mypy .

lock: ## Update uv.lock
	uv lock --upgrade

clean: ## Remove caches
	rm -rf .pytest_cache .ruff_cache .mypy_cache

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
