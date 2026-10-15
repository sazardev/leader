# Go command line tool: install it, cross-compile it for every platform
BIN ?= $(notdir $(CURDIR))
PLATFORMS ?= linux/amd64 linux/arm64 darwin/arm64 windows/amd64

.PHONY: build install test fmt dist clean help

build: ## Build the binary into bin/
	go build -o bin/$(BIN) .

install: ## Install into GOBIN
	go install .

test: ## Run the tests
	go test ./...

fmt: ## Format the code
	gofmt -w .

dist: ## Cross-compile for every platform into dist/
	@for p in $(PLATFORMS); do \
	  os=$${p%/*}; arch=$${p#*/}; ext=; \
	  if [ $$os = windows ]; then ext=.exe; fi; \
	  echo "building $$os/$$arch"; \
	  GOOS=$$os GOARCH=$$arch CGO_ENABLED=0 go build -o dist/$(BIN)-$$os-$$arch$$ext . || exit 1; \
	done

clean: ## Remove bin/ and dist/
	rm -rf bin dist

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
