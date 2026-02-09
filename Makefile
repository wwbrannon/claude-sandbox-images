VERSION  ?= v1.0
REGISTRY ?=
VARIANTS := minimal r

IMAGE_PREFIX := claude-sandbox

.PHONY: build $(addprefix build-,$(VARIANTS)) \
        lint test scan clean push list \
        shell

# ---------- build ----------

ifdef IMAGE
build: build-$(IMAGE)
else
build: $(addprefix build-,$(VARIANTS))
endif

build-minimal:
	docker build -f Dockerfile.minimal \
		-t $(IMAGE_PREFIX)-minimal:$(VERSION) \
		-t $(IMAGE_PREFIX)-minimal:latest .

build-r: build-minimal
	docker build -f Dockerfile.r \
		-t $(IMAGE_PREFIX)-r:$(VERSION) \
		-t $(IMAGE_PREFIX)-r:latest .

# ---------- lint ----------

lint:
	shellcheck entrypoint.sh hooks/*.sh
	hadolint Dockerfile.minimal Dockerfile.r
	jq empty settings/managed-settings.json
	jq empty settings/settings.json

# ---------- test ----------

test: build
	@echo "==> Smoke-testing minimal image"
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) python3 --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) node --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) aws --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) gcloud --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) az --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) gh --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) uv --version
	docker run --rm $(IMAGE_PREFIX)-minimal:$(VERSION) jq empty /etc/claude-code/managed-settings.json
	@echo "==> Smoke-testing R image"
	docker run --rm $(IMAGE_PREFIX)-r:$(VERSION) Rscript -e 'library(tidyverse); cat("OK\n")'
	@echo "==> All smoke tests passed"

# ---------- scan ----------

scan: build
	trivy image --severity HIGH,CRITICAL $(IMAGE_PREFIX)-minimal:$(VERSION)
	trivy image --severity HIGH,CRITICAL $(IMAGE_PREFIX)-r:$(VERSION)

# ---------- push ----------

push: build
ifndef REGISTRY
	$(error REGISTRY is not set. Usage: make push REGISTRY=ghcr.io/youruser)
endif
	@for variant in $(VARIANTS); do \
		docker tag $(IMAGE_PREFIX)-$$variant:$(VERSION) $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:$(VERSION) && \
		docker tag $(IMAGE_PREFIX)-$$variant:latest   $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:latest   && \
		docker push $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:$(VERSION) && \
		docker push $(REGISTRY)/$(IMAGE_PREFIX)-$$variant:latest; \
	done

# ---------- clean ----------

clean:
	@for variant in $(VARIANTS); do \
		docker rmi $(IMAGE_PREFIX)-$$variant:$(VERSION) $(IMAGE_PREFIX)-$$variant:latest 2>/dev/null || true; \
	done

# ---------- helpers ----------

list:
	@docker images --filter "reference=$(IMAGE_PREFIX)-*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"

IMAGE ?= minimal
shell:
	docker run --rm -it $(IMAGE_PREFIX)-$(IMAGE):$(VERSION) /bin/bash
