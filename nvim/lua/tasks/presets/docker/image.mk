# Docker image: build, run, shell, tag and push
IMAGE ?= $(notdir $(CURDIR))
TAG ?= latest
REGISTRY ?=

.PHONY: build run shell push help

build: ## Build the image
	docker build -t $(IMAGE):$(TAG) .

run: build ## Build and run it
	docker run --rm -it $(IMAGE):$(TAG)

shell: build ## Open a shell inside the image
	docker run --rm -it --entrypoint sh $(IMAGE):$(TAG)

push: build ## Tag and push to REGISTRY
	@test -n "$(REGISTRY)" || { echo "set REGISTRY=host/namespace"; exit 1; }
	docker tag $(IMAGE):$(TAG) $(REGISTRY)/$(IMAGE):$(TAG)
	docker push $(REGISTRY)/$(IMAGE):$(TAG)

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
