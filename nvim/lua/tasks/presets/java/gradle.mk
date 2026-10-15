# Java with the Gradle wrapper
GRADLE ?= ./gradlew

.PHONY: build test run check clean help

build: ## Build (jar, tests included)
	$(GRADLE) build

test: ## Run the tests
	$(GRADLE) test

run: ## Run the application plugin's main class
	$(GRADLE) run

check: ## Tests and checks without the jar
	$(GRADLE) check

clean: ## Remove build/
	$(GRADLE) clean

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
