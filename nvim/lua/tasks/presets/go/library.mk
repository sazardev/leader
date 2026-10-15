# Go library: tests, race detector, benchmarks, coverage report, docs
.PHONY: test race bench cover lint fmt tidy doc help

test: ## Run the tests
	go test ./...

race: ## Run the tests with the race detector
	go test -race ./...

bench: ## Run the benchmarks
	go test -run '^$$' -bench . -benchmem ./...

cover: ## Coverage report (coverage.html)
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

lint: ## Lint with golangci-lint
	golangci-lint run

fmt: ## Format the code
	gofmt -w .

tidy: ## Sync go.mod and go.sum
	go mod tidy

doc: ## Print the package documentation
	go doc -all .

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
