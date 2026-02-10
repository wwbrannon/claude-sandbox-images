VERSION  ?= v1.0
VARIANTS := base r

IMAGE_PREFIX := claude-sandbox

.PHONY: build lint test scan clean push list shell

#
# image building and management
#

build:
	for variant in $(VARIANTS); do \
		docker build -f "Dockerfile.$$variant" \
			-t "$(IMAGE_PREFIX)-$$variant:$(VERSION)" \
			-t "$(IMAGE_PREFIX)-$$variant:latest" \
			.; \
	done

REGISTRY ?=
push: build
ifndef REGISTRY
	$(error REGISTRY is not set. Usage: make push REGISTRY=ghcr.io/youruser)
endif
	for variant in $(VARIANTS); do \
		docker tag $(IMAGE_PREFIX)-$$variant:$(VERSION) $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:$(VERSION) && \
		docker tag $(IMAGE_PREFIX)-$$variant:latest   $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:latest   && \
		docker push $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:$(VERSION) && \
		docker push $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:latest; \
	done

rm:
	@for variant in $(VARIANTS); do \
		docker rmi $(IMAGE_PREFIX)-$$variant:$(VERSION) $(IMAGE_PREFIX)-$$variant:latest 2>/dev/null || true; \
	done

#
# quality checks, dev shell
#

scan: build
	for variant in $(VARIANTS); do \
		trivy image --severity HIGH,CRITICAL "$(IMAGE_PREFIX)-$$variant:$(VERSION)"; \
	done

lint:
	jq empty settings/managed-settings.json
	jq empty settings/settings.json
	shellcheck entrypoint.sh hooks/*.sh
	for variant in $(VARIANTS); do \
		hadolint "Dockerfile.$$variant"; \
	done

IMAGE ?= base
shell:
	docker run --rm -it $(IMAGE_PREFIX)-$(IMAGE):$(VERSION) /bin/bash
