# Django: server, migrations, shell, tests
PY ?= python

.PHONY: run migrate migrations shell test superuser static lint help

run: ## Run the development server
	$(PY) manage.py runserver

migrate: ## Apply migrations
	$(PY) manage.py migrate

migrations: ## Create migrations from the models
	$(PY) manage.py makemigrations

shell: ## Open the Django shell
	$(PY) manage.py shell

test: ## Run the tests
	$(PY) manage.py test

superuser: ## Create an admin user
	$(PY) manage.py createsuperuser

static: ## Collect static files
	$(PY) manage.py collectstatic --noinput

lint: ## Lint with ruff
	ruff check .

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
