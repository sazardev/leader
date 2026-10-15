# Dart command line app or package
BIN ?= $(notdir $(CURDIR))

.PHONY: get run test analyze fmt compile clean help

get: ## Fetch the packages
	dart pub get

run: ## Run bin/main.dart
	dart run

test: ## Run the tests
	dart test

analyze: ## Static analysis
	dart analyze

fmt: ## Format the code
	dart format .

compile: ## Compile a native executable into build/
	mkdir -p build
	dart compile exe bin/main.dart -o build/$(BIN)

clean: ## Remove build/
	rm -rf build .dart_tool

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
