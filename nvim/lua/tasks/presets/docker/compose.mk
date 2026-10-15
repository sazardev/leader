# Docker Compose: the daily commands of a multi-container project
SERVICE ?= app

.PHONY: up down restart logs ps build shell prune help

up: ## Start everything in the background
	docker compose up -d

down: ## Stop and remove the containers
	docker compose down

restart: ## Restart the services
	docker compose restart

logs: ## Follow the logs
	docker compose logs -f --tail=100

ps: ## List the containers
	docker compose ps

build: ## Rebuild the images
	docker compose build

shell: ## Open a shell in $(SERVICE)
	docker compose exec $(SERVICE) sh

prune: ## Remove unused images and volumes (asks first)
	docker system prune --volumes

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
