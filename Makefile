REGISTRY   ?= ghcr.io/$(or $(shell git remote get-url origin 2>/dev/null | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p' | tr '[:upper:]' '[:lower:]'),local)
PREFIX     ?= pgx
PG_VERSIONS ?= 17 18
EXTENSIONS := $(sort $(notdir $(patsubst %/,%,$(wildcard extensions/*/))))

# Default PG version for single-extension targets
PG ?= 17

.PHONY: help list build build-all image push push-all dockerfile clean clean-all test

help: ## Show this help
	@printf "Usage:\n"
	@printf "  make build EXT=pgvector [PG=17]   Build one extension image\n"
	@printf "  make build-all [PG=17]            Build all extensions for a PG version\n"
	@printf "  make image [PG=17]                Build combined image with all extensions\n"
	@printf "  make push  EXT=pgvector [PG=17]   Push one extension image\n"
	@printf "  make push-all [PG=17]             Push all extensions for a PG version\n"
	@printf "  make dockerfile EXT=pgvector      Print generated Dockerfile to stdout\n"
	@printf "  make list                         List available extensions\n"
	@printf "  make test [REGISTRY=local] [PG=17] Run collision and functional tests\n"
	@printf "  make clean EXT=pgvector           Remove built image for one extension\n"
	@printf "  make clean-all                    Remove all built extension images\n"
	@printf "\nVariables:\n"
	@printf "  REGISTRY=%s\n" "$(REGISTRY)"
	@printf "  PREFIX=%s\n"   "$(PREFIX)"
	@printf "  PG=%s\n"       "$(PG)"

list: ## List available extensions
	@printf "%-15s %-6s %s\n" "EXTENSION" "PG" "DESCRIPTION"
	@printf "%-15s %-6s %s\n" "---------" "--" "-----------"
	@for ext in $(EXTENSIONS); do \
		desc=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$$DESCRIPTION"'); \
		versions=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && \
			for v in $(PG_VERSIONS); do \
				ver_var="VERSION_$$v"; \
				ver="$${!ver_var}"; \
				[ -n "$$ver" ] && printf "$$v "; \
			done'); \
		printf "%-15s %-6s %s\n" "$$ext" "$$versions" "$$desc"; \
	done

build: _check-ext ## Build a single extension image
	$(eval EXT_VERSION := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo $${VERSION_$(PG)}'))
	@test -n "$(EXT_VERSION)" || { echo "Error: $(EXT) has no version defined for PG $(PG)"; exit 1; }
	@echo "Building $(PREFIX)-$(EXT):$(PG) (extension $(EXT_VERSION))..."
	docker build \
		--build-arg PG_MAJOR=$(PG) \
		--build-arg EXT_VERSION=$(EXT_VERSION) \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG) \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)-$(EXT_VERSION) \
		-f extensions/$(EXT)/Dockerfile \
		extensions/$(EXT)

build-all: ## Build all extensions for PG version(s)
	@for pg in $(PG); do \
		for ext in $(EXTENSIONS); do \
			version=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$$pg"'}'); \
			if [ -n "$$version" ]; then \
				$(MAKE) --no-print-directory build EXT=$$ext PG=$$pg || exit 1; \
			else \
				echo "Skipping $$ext (no version for PG $$pg)"; \
			fi; \
		done; \
	done

push: _check-ext ## Push a single extension image
	docker push $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)
	$(eval EXT_VERSION := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo $${VERSION_$(PG)}'))
	@test -n "$(EXT_VERSION)" && docker push $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)-$(EXT_VERSION) || true

push-all: ## Push all extensions for PG version(s)
	@for pg in $(PG); do \
		for ext in $(EXTENSIONS); do \
			version=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$$pg"'}'); \
			if [ -n "$$version" ]; then \
				$(MAKE) --no-print-directory push EXT=$$ext PG=$$pg || exit 1; \
			fi; \
		done; \
	done

dockerfile: _check-ext ## Print the Dockerfile for an extension
	@cat extensions/$(EXT)/Dockerfile

info: _check-ext ## Show details for an extension
	@bash -c 'source extensions/$(EXT)/extension.conf; \
		echo "Extension: $(EXT)"; \
		echo "Description: $$DESCRIPTION"; \
		echo "Repository: $$REPO"; \
		for v in $(PG_VERSIONS); do \
			ver_var="VERSION_$$v"; \
			ver="$${!ver_var}"; \
			[ -n "$$ver" ] && echo "PG $$v: $$ver"; \
		done; \
		[ -n "$$SHARED_PRELOAD" ] && echo "shared_preload_libraries: $$SHARED_PRELOAD"; \
		[ -n "$$NOTES" ] && echo "Notes: $$NOTES"'

IMAGE_NAME ?= postgres-extender

image: ## Build a combined image with all extensions
	@echo "Building combined image $(IMAGE_NAME):$(PG) with all extensions..."
	@TMPFILE=$$(mktemp); \
	{ \
		echo "FROM postgres:$(PG)"; \
		for ext in $(EXTENSIONS); do \
			ver=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$(PG)"'}'); \
			[ -n "$$ver" ] && echo "COPY --from=$(REGISTRY)/$(PREFIX)-$$ext:$(PG) / /"; \
		done; \
		preloads=""; \
		for ext in $(EXTENSIONS); do \
			spl=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$$SHARED_PRELOAD"'); \
			[ -n "$$spl" ] && preloads="$${preloads:+$$preloads,}$$spl"; \
		done; \
		[ -n "$$preloads" ] && echo "RUN echo \"shared_preload_libraries = '$$preloads'\" >> /usr/share/postgresql/postgresql.conf.sample"; \
	} > "$$TMPFILE"; \
	docker build -t $(IMAGE_NAME):$(PG) -f "$$TMPFILE" .; \
	rm -f "$$TMPFILE"
	@echo "Done: $(IMAGE_NAME):$(PG)"

clean: _check-ext ## Remove built image for a single extension
	@for pg in $(PG_VERSIONS); do \
		img="$(REGISTRY)/$(PREFIX)-$(EXT):$$pg"; \
		if docker image inspect "$$img" >/dev/null 2>&1; then \
			docker rmi "$$img" && echo "Removed $$img"; \
		fi; \
		ver=$$(bash -c 'source extensions/$(EXT)/extension.conf && echo $${VERSION_'"$$pg"'}'); \
		img_ver="$(REGISTRY)/$(PREFIX)-$(EXT):$$pg-$$ver"; \
		if docker image inspect "$$img_ver" >/dev/null 2>&1; then \
			docker rmi "$$img_ver" && echo "Removed $$img_ver"; \
		fi; \
	done

clean-all: ## Remove all built extension images
	@for pg in $(PG_VERSIONS); do \
		for ext in $(EXTENSIONS); do \
			img="$(REGISTRY)/$(PREFIX)-$$ext:$$pg"; \
			docker rmi "$$img" 2>/dev/null && echo "Removed $$img" || true; \
			ver=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$$pg"'}'); \
			docker rmi "$(REGISTRY)/$(PREFIX)-$$ext:$$pg-$$ver" 2>/dev/null || true; \
		done; \
	done
	@echo "Done. Run 'docker image prune' to reclaim disk space."

test: ## Run layer collision and functional tests
	@./tests/test-layers.sh $(REGISTRY) $(PG)

_check-ext:
	@test -n "$(EXT)" || { echo "Error: EXT is required. Usage: make build EXT=pgvector [PG=17]"; exit 1; }
	@test -d "extensions/$(EXT)" || { echo "Error: unknown extension '$(EXT)'. Run 'make list' to see available extensions."; exit 1; }
