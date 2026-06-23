REGISTRY   ?= ghcr.io/$(or $(shell git remote get-url origin 2>/dev/null | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p' | tr '[:upper:]' '[:lower:]'),local)
PREFIX     ?= pgx
PG_VERSIONS ?= 17 18 19
EXTENSIONS := $(sort $(notdir $(patsubst %/,%,$(wildcard extensions/*/))))

# Default PG version for single-extension targets
PG ?= 17

# Profile support: override EXTENSIONS with a subset from profiles/<name>.txt
ifdef PROFILE
  _PROFILE_FILE := profiles/$(PROFILE).txt
  ifeq ($(wildcard $(_PROFILE_FILE)),)
    $(error Profile '$(PROFILE)' not found. Available: $(basename $(notdir $(wildcard profiles/*.txt))))
  endif
  EXTENSIONS := $(shell grep -v '^\#' $(_PROFILE_FILE) | grep -v '^$$' | sort)
endif

# Platform(s) for multi-arch builds.  Override with:
#   make build EXT=pgvector PLATFORM=linux/amd64,linux/arm64
# Default: native architecture only (fast local builds).
PLATFORM ?=

.PHONY: help list build build-all image push push-all dockerfile clean clean-all test test-image list-profiles check-profiles

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
	@printf "  make test-image [PG=17]            Run integration tests against combined image\n"
	@printf "  make list-profiles                 List available profiles\n"
	@printf "  make check-profiles                Verify profile files are in sync\n"
	@printf "  make clean EXT=pgvector           Remove built image for one extension\n"
	@printf "  make clean-all                    Remove all built extension images\n"
	@printf "\nVariables:\n"
	@printf "  REGISTRY=%s\n" "$(REGISTRY)"
	@printf "  PREFIX=%s\n"   "$(PREFIX)"
	@printf "  PG=%s\n"       "$(PG)"
	@printf "  PROFILE=%s (set to filter extensions by profile, e.g. PROFILE=azure)\n" "$(or $(PROFILE),<none>)"
	@printf "  PLATFORM=%s (set to linux/amd64,linux/arm64 for multi-arch)\n" "$(or $(PLATFORM),<native>)"

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

# Cache scope for GHA cache (used in CI). Set to enable layer caching.
CACHE_SCOPE ?=

build: _check-ext ## Build a single extension image
	$(eval EXT_VERSION := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo $${VERSION_$(PG)}'))
	@test -n "$(EXT_VERSION)" || { echo "Error: $(EXT) has no version defined for PG $(PG)"; exit 1; }
	@echo "Building $(PREFIX)-$(EXT):$(PG) (extension $(EXT_VERSION))..."
	docker buildx build \
		$(if $(PLATFORM),--platform $(PLATFORM)) \
		$(if $(CACHE_SCOPE),--cache-from type=gha$(comma)scope=$(CACHE_SCOPE)-$(EXT)-$(PG)) \
		$(if $(CACHE_SCOPE),--cache-from type=registry$(comma)ref=$(REGISTRY)/$(PREFIX)-$(EXT):$(PG)) \
		$(if $(CACHE_SCOPE),--cache-to type=gha$(comma)mode=max$(comma)scope=$(CACHE_SCOPE)-$(EXT)-$(PG)) \
		--build-arg PG_MAJOR=$(PG) \
		--build-arg PG_TAG=$(or $(PG_TAG),$(PG)) \
		--build-arg EXT_VERSION=$(EXT_VERSION) \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG) \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)-$(EXT_VERSION) \
		-f extensions/$(EXT)/Dockerfile \
		$(if $(PLATFORM),--push,--load) \
		extensions/$(EXT)

comma := ,

build-all: ## Build all extensions for PG version(s)
	@failed=""; \
	for pg in $(PG); do \
		for ext in $(EXTENSIONS); do \
			version=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$$pg"'}'); \
			if [ -n "$$version" ]; then \
				$(MAKE) --no-print-directory build EXT=$$ext PG=$$pg || { \
					echo "FAILED: $$ext (PG $$pg)"; \
					failed="$${failed:+$$failed }$$ext:$$pg"; \
				}; \
			else \
				echo "Skipping $$ext (no version for PG $$pg)"; \
			fi; \
		done; \
	done; \
	if [ -n "$$failed" ]; then \
		echo; echo "Build failures: $$failed"; \
		exit 1; \
	fi

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

IMAGE_NAME ?= pglayers$(if $(PROFILE),-$(PROFILE))

image: ## Build a combined image with all extensions
	@echo "Building combined image $(IMAGE_NAME):$(PG)..."
	@TMPFILE=$$(mktemp); \
	skipped=""; \
	included_list=""; \
	included_label=""; \
	included=0; \
	total=0; \
	{ \
		echo "FROM postgres:$(PG)"; \
		for ext in $(EXTENSIONS); do \
			ver=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$(PG)"'}'); \
			[ -z "$$ver" ] && continue; \
			total=$$((total + 1)); \
			if [ "$(REGISTRY)" = "local" ]; then \
				docker image inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || { skipped="$${skipped:+$$skipped }$$ext"; continue; }; \
			else \
				docker buildx imagetools inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || { skipped="$${skipped:+$$skipped }$$ext"; continue; }; \
			fi; \
			echo "COPY --from=$(REGISTRY)/$(PREFIX)-$$ext:$(PG) / /"; \
			included=$$((included + 1)); \
			included_list="$${included_list:+$$included_list,}\"$$ext\""; \
			included_label="$${included_label:+$$included_label }$$ext"; \
		done; \
		preloads=""; \
		for ext in $(EXTENSIONS); do \
			ver=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo $${VERSION_'"$(PG)"'}'); \
			[ -z "$$ver" ] && continue; \
			if [ "$(REGISTRY)" = "local" ]; then \
				docker image inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			else \
				docker buildx imagetools inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			fi; \
			spl=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$$SHARED_PRELOAD"'); \
			[ -n "$$spl" ] && preloads="$${preloads:+$$preloads,}$$spl"; \
		done; \
		[ -n "$$preloads" ] && echo "RUN echo \"shared_preload_libraries = '$$preloads'\" >> /usr/share/postgresql/postgresql.conf.sample"; \
		echo "RUN mkdir -p /etc/pglayers && echo '{' > /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"pg_version\": \"$(PG)\",' >> /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"profile\": \"$(or $(PROFILE),full)\",' >> /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"count\": '$$included',' >> /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"total\": '$$total',' >> /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"included\": [$$included_list],' >> /etc/pglayers/manifest.json \\"; \
		if [ -n "$$skipped" ]; then \
			skipped_json=$$(echo "$$skipped" | tr ' ' '\n' | sed 's/.*/"&"/' | paste -sd,); \
			echo "  && echo '  \"missing\": [$$skipped_json]' >> /etc/pglayers/manifest.json \\"; \
		else \
			echo "  && echo '  \"missing\": []' >> /etc/pglayers/manifest.json \\"; \
		fi; \
		echo "  && echo '}' >> /etc/pglayers/manifest.json"; \
		echo "LABEL org.pglayers.pg_version=\"$(PG)\""; \
		echo "LABEL org.pglayers.profile=\"$(or $(PROFILE),full)\""; \
		echo "LABEL org.pglayers.extensions.count=$$included"; \
		echo "LABEL org.pglayers.extensions.total=$$total"; \
		echo "LABEL org.pglayers.extensions.included=\"$$included_label\""; \
		if [ -n "$$skipped" ]; then \
			echo "LABEL org.pglayers.extensions.missing=\"$$skipped\""; \
		fi; \
	} > "$$TMPFILE"; \
	if [ -n "$$skipped" ]; then \
		echo "Included $$included/$$total extensions (missing: $$skipped)"; \
	else \
		echo "Included $$included/$$total extensions"; \
	fi; \
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
	@PGLAYERS_EXTENSIONS="$(EXTENSIONS)" ./tests/test-layers.sh $(REGISTRY) $(PG)

test-image: ## Run integration tests against the combined image
	@./tests/test-image.sh $(IMAGE_NAME):$(PG)

list-profiles: ## List available profiles
	@printf "%-12s %-6s %s\n" "PROFILE" "COUNT" "DESCRIPTION"
	@printf "%-12s %-6s %s\n" "-------" "-----" "-----------"
	@for f in profiles/*.txt; do \
		name=$$(basename "$$f" .txt); \
		count=$$(grep -cv '^\(#\|$$\)' "$$f"); \
		desc=$$(head -1 "$$f" | sed 's/^# *//'); \
		printf "%-12s %-6d %s\n" "$$name" "$$count" "$$desc"; \
	done

check-profiles: ## Verify profiles/full.txt matches extensions/ directory
	@expected=$$(for dir in extensions/*/; do \
		ext=$$(basename "$$dir"); \
		ci_skip=$$(bash -c 'source '"$$dir"'/extension.conf && echo $${CI_SKIP:-}'); \
		[ "$$ci_skip" = "1" ] && continue; \
		echo "$$ext"; \
	done | sort); \
	actual=$$(grep -v '^\#' profiles/full.txt | grep -v '^$$' | sort); \
	if [ "$$expected" != "$$actual" ]; then \
		echo "Error: profiles/full.txt is out of sync with extensions/ directory."; \
		echo "Expected:"; echo "$$expected"; \
		echo "Actual:"; echo "$$actual"; \
		echo; echo "Update profiles/full.txt (extensions with CI_SKIP=1 are excluded)."; \
		exit 1; \
	fi
	@for f in profiles/*.txt; do \
		while IFS= read -r ext; do \
			[ -z "$$ext" ] && continue; \
			echo "$$ext" | grep -q '^#' && continue; \
			if [ ! -d "extensions/$$ext" ]; then \
				echo "Error: profile $$(basename $$f) references unknown extension '$$ext'"; \
				exit 1; \
			fi; \
		done < "$$f"; \
	done
	@echo "All profiles valid."

_check-ext:
	@test -n "$(EXT)" || { echo "Error: EXT is required. Usage: make build EXT=pgvector [PG=17]"; exit 1; }
	@test -d "extensions/$(EXT)" || { echo "Error: unknown extension '$(EXT)'. Run 'make list' to see available extensions."; exit 1; }
