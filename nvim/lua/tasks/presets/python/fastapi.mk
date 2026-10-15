# FastAPI service: auto-reload server, tests, lint, container
APP ?= app.main:app
PORT ?= 8000
IMAGE ?= $(notdir $(CURDIR))

.PHONY: dev serve test lint fmt docker-build docker-run help

dev: ## Run with auto-reload
	uvicorn $(APP) --reload --port $(PORT)

serve: ## Run for production (no reload)
	uvicorn $(APP) --host 0.0.0.0 --port $(PORT)

test: ## Run the tests
	pytest

lint: ## Lint with ruff
	ruff check .

fmt: ## Format with ruff
	ruff format .

docker-build: ## Build the container image
	docker build -t $(IMAGE) .

docker-run: ## Run the container
	docker run --rm -p $(PORT):$(PORT) $(IMAGE)

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
