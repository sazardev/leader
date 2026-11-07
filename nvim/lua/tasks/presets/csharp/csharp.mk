# C# / .NET: restore, build, run, watch, test, format, publish and clean a solution or project
PROJECT ?= $(firstword $(wildcard *.sln) $(wildcard *.slnx) $(wildcard *.csproj))
RUN_PROJECT ?= $(firstword $(wildcard *.csproj) $(wildcard */*.csproj))
CONFIG ?= Release

.PHONY: restore build run watch test format format-check publish clean help

restore: ## Restore NuGet packages
	dotnet restore $(PROJECT)

build: ## Build the project or solution
	dotnet build $(PROJECT) -c $(CONFIG)

run: ## Run the project
	dotnet run --project $(or $(RUN_PROJECT),$(PROJECT))

watch: ## Run with hot reload
	dotnet watch --project $(or $(RUN_PROJECT),$(PROJECT)) run

test: ## Run the tests
	dotnet test $(PROJECT)

format: ## Format with CSharpier
	csharpier format .

format-check: ## Verify formatting without writing
	csharpier check .

publish: ## Publish into publish/
	dotnet publish $(PROJECT) -c $(CONFIG) -o publish

clean: ## Remove build output and publish/
	dotnet clean $(PROJECT)
	rm -rf publish

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
