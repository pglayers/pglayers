REGISTRY   ?= ghcr.io/$(or $(shell git remote get-url origin 2>/dev/null | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p' | tr '[:upper:]' '[:lower:]'),local)
PREFIX     ?= pgx
PG_VERSIONS ?= 17 18
EXTENSIONS := $(sort $(notdir $(patsubst %/,%,$(wildcard extensions/*/))))

# Default PG version for single-extension targets
PG ?= 17

.PHONY: help list build build-all push push-all dockerfile clean

help: ## Show this help
	@printf "Usage:\n"
	@printf "  make build EXT=pgvector [PG=17]   Build one extension image\n"
	@printf "  make build-all [PG=17]            Build all extensions for a PG version\n"
	@printf "  make push  EXT=pgvector [PG=17]   Push one extension image\n"
	@printf "  make push-all [PG=17]             Push all extensions for a PG version\n"
	@printf "  make dockerfile EXT=pgvector      Print generated Dockerfile to stdout\n"
	@printf "  make list                         List available extensions\n"
	@printf "  make clean                        Remove generated files\n"
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

clean: ## Remove generated files
	@echo "Nothing to clean (artifacts are Docker images)."
	@echo "Use 'docker image prune' to remove unused images."

_check-ext:
	@test -n "$(EXT)" || { echo "Error: EXT is required. Usage: make build EXT=pgvector [PG=17]"; exit 1; }
	@test -d "extensions/$(EXT)" || { echo "Error: unknown extension '$(EXT)'. Run 'make list' to see available extensions."; exit 1; }
