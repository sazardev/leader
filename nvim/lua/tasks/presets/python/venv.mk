# Python: a virtualenv with pip, pytest and ruff
PY ?= python3
VENV ?= .venv
BIN := $(VENV)/bin

.PHONY: venv install run test lint fmt clean help

venv: ## Create the virtualenv
	test -d $(VENV) || $(PY) -m venv $(VENV)

install: venv ## Install requirements.txt
	$(BIN)/pip install -U pip
	$(BIN)/pip install -r requirements.txt

run: ## Run main.py
	$(BIN)/python main.py

test: ## Run the tests
	$(BIN)/python -m pytest

lint: ## Lint with ruff
	$(BIN)/ruff check .

fmt: ## Format with ruff
	$(BIN)/ruff format .

clean: ## Remove the virtualenv and caches
	rm -rf $(VENV) .pytest_cache .ruff_cache

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
