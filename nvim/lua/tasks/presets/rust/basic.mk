# Rust: build, run, test, check, lint, format
.PHONY: build release run test check clippy fmt doc clean help

build: ## Build (debug)
	cargo build

release: ## Build optimized
	cargo build --release

run: ## Run the binary
	cargo run

test: ## Run the tests
	cargo test

check: ## Type check without building
	cargo check

clippy: ## Lint with clippy, warnings are errors
	cargo clippy --all-targets -- -D warnings

fmt: ## Format the code
	cargo fmt

doc: ## Build and open the docs
	cargo doc --open

clean: ## Remove target/
	cargo clean

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
