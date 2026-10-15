# Kotlin with the Gradle wrapper: tests, ktlint, detekt
GRADLE ?= ./gradlew

.PHONY: build test run lint fmt detekt clean help

build: ## Build
	$(GRADLE) build

test: ## Run the tests
	$(GRADLE) test

run: ## Run the application
	$(GRADLE) run

lint: ## Check the style with ktlint
	$(GRADLE) ktlintCheck

fmt: ## Fix the style with ktlint
	$(GRADLE) ktlintFormat

detekt: ## Static analysis with detekt
	$(GRADLE) detekt

clean: ## Remove build/
	$(GRADLE) clean

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
