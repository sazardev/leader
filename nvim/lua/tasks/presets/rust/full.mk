# Rust, everything: watch mode, audit, coverage, benchmarks, install
.PHONY: watch test-watch test clippy fmt audit cover bench install release clean help

watch: ## Re-run on every change (needs cargo-watch)
	cargo watch -x run

test-watch: ## Re-test on every change (needs cargo-watch)
	cargo watch -x test

test: ## Run the tests
	cargo test --all-features

clippy: ## Lint with clippy, warnings are errors
	cargo clippy --all-targets --all-features -- -D warnings

fmt: ## Check the formatting
	cargo fmt --check

audit: ## Check dependencies for advisories (needs cargo-audit)
	cargo audit

cover: ## Coverage report (needs cargo-llvm-cov)
	cargo llvm-cov --html

bench: ## Run the benchmarks
	cargo bench

install: ## Install the binary
	cargo install --path .

release: ## Build optimized
	cargo build --release

clean: ## Remove target/
	cargo clean

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
