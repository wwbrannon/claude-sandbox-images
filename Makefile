SHELL := /bin/bash

VERSION  ?= v1.1
VARIANTS := base r tex
IMAGE_PREFIX := claude-sandbox
PLATFORMS ?= linux/amd64,linux/arm64

#
# image building and management
#

.PHONY: build
build: ## help: Build all containers
	for variant in $(VARIANTS); do \
		docker build -f "Dockerfile.$$variant" \
			-t "$(IMAGE_PREFIX)-$$variant:$(VERSION)" \
			-t "$(IMAGE_PREFIX)-$$variant:latest" \
			.; \
	done

REGISTRY ?=
.PHONY: push
push: ## help: Build multi-arch images and push to the registry given by REGISTRY
ifndef REGISTRY
	$(error REGISTRY is not set. Usage: make push REGISTRY=ghcr.io/youruser)
endif
	for variant in $(VARIANTS); do \
		build_arg=""; \
		if [ "$$variant" != "base" ]; then \
			build_arg="--build-arg BASE_IMAGE=$(REGISTRY)/$(IMAGE_PREFIX)-base:$(VERSION)"; \
		fi; \
		docker buildx build --platform $(PLATFORMS) \
			-f "Dockerfile.$$variant" \
			$$build_arg \
			-t "$(REGISTRY)/$(IMAGE_PREFIX)-$$variant:$(VERSION)" \
			-t "$(REGISTRY)/$(IMAGE_PREFIX)-$$variant:latest" \
			--push .; \
	done

rm: ## help: Delete the built containers
	@for variant in $(VARIANTS); do \
		docker rmi $(IMAGE_PREFIX)-$$variant:$(VERSION) $(IMAGE_PREFIX)-$$variant:latest 2>/dev/null || true; \
	done

#
# quality checks, dev shell
#

.PHONY: scan
scan: build ## help: Scan containers for security vulnerabilities with trivy
	for variant in $(VARIANTS); do \
		trivy image --severity HIGH,CRITICAL "$(IMAGE_PREFIX)-$$variant:$(VERSION)"; \
	done

.PHONY: lint
lint: ## help: Run shellcheck, hadolint, etc.
	jq empty settings/managed-settings.json
	jq empty settings/settings.json
	shellcheck entrypoint.sh hooks/*.sh
	for variant in $(VARIANTS); do \
		hadolint "Dockerfile.$$variant"; \
	done

IMAGE ?= base
.PHONY: shell
shell: ## help: Run a shell in the container given by IMAGE (default base)
	docker run --rm -it $(IMAGE_PREFIX)-$(IMAGE):$(VERSION) /bin/bash

#
# help
#

.PHONY: help
help: ## help: Show this help message
	@echo "Development Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## help: .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## help: "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
