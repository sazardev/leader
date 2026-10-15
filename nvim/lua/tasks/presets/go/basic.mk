# Go: build, run, test and tidy a module
BIN ?= $(notdir $(CURDIR))

.PHONY: build run test vet fmt tidy clean help

build: ## Build the binary into bin/
	go build -o bin/$(BIN) .

run: ## Run the program
	go run .

test: ## Run the tests
	go test ./...

vet: ## Run go vet
	go vet ./...

fmt: ## Format the code
	gofmt -w .

tidy: ## Sync go.mod and go.sum
	go mod tidy

clean: ## Remove the build output
	rm -rf bin

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
