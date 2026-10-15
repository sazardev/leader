# Go service: live reload, race and coverage, a container image
BIN ?= $(notdir $(CURDIR))
MAIN ?= .
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
IMAGE ?= $(BIN):$(VERSION)

.PHONY: build run dev test race cover lint docker-build docker-run clean help

build: ## Build with the version stamped in
	CGO_ENABLED=0 go build -ldflags "-s -w -X main.version=$(VERSION)" -o bin/$(BIN) $(MAIN)

run: ## Run the service
	go run $(MAIN)

dev: ## Run with live reload (needs air)
	@command -v air >/dev/null || { echo "install air: go install github.com/air-verse/air@latest"; exit 1; }
	air

test: ## Run the tests
	go test ./...

race: ## Run the tests with the race detector
	go test -race ./...

cover: ## Coverage summary (coverage.out)
	go test -coverprofile=coverage.out ./...
	go tool cover -func=coverage.out | tail -n 1

lint: ## Lint with golangci-lint
	golangci-lint run

docker-build: ## Build the container image
	docker build -t $(IMAGE) .

docker-run: ## Run the container on :8080
	docker run --rm -p 8080:8080 $(IMAGE)

clean: ## Remove build output and coverage
	rm -rf bin coverage.out

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
