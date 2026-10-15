# Java with Maven
.PHONY: compile test package verify run clean help

compile: ## Compile
	mvn -q compile

test: ## Run the tests
	mvn test

package: ## Build the jar (skips the tests)
	mvn -q package -DskipTests

verify: ## Run the full lifecycle, tests included
	mvn verify

run: package ## Run the jar in target/
	java -jar $$(ls target/*.jar | grep -v original | head -n 1)

clean: ## Remove target/
	mvn -q clean

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
