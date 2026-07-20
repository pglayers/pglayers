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

.PHONY: help list build build-all image push push-all dockerfile clean clean-all test test-image list-profiles check-profiles check-licenses add-apt-ext

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
	@printf "  make check-licenses               Verify extension licenses comply with policy\n"
	@printf "  make add-apt-ext PKG=cron NAME=pg_cron  Scaffold a new APT extension\n"
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
		ci_skip=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$${CI_SKIP:-}"'); \
		versions=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && \
			if [ -n "$${APT_PACKAGE:-}" ]; then \
				printf "apt "; \
			else \
				for v in $(PG_VERSIONS); do \
					ver_var="VERSION_$$v"; \
					ver="$${!ver_var}"; \
					[ -n "$$ver" ] && printf "$$v "; \
				done; \
			fi'); \
		skip_marker=""; \
		[ "$$ci_skip" = "1" ] && skip_marker=" [CI_SKIP]"; \
		printf "%-15s %-6s %s%s\n" "$$ext" "$$versions" "$$desc" "$$skip_marker"; \
	done

# Cache scope for GHA cache (used in CI). Set to enable layer caching.
CACHE_SCOPE ?=

build: _check-ext ## Build a single extension image
	$(eval EXT_APT_PACKAGE := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo "$$APT_PACKAGE"'))
	$(eval EXT_VERSION := $(shell ./scripts/ext-version.sh $(EXT) $(PG)))
	$(eval EXT_DESC := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo "$$DESCRIPTION"'))
	$(eval EXT_REPO := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo "$$REPO"'))
	$(eval EXT_LICENSE := $(shell bash -c 'source extensions/$(EXT)/extension.conf && echo "$$LICENSE"'))
	$(eval DOCKERFILE := $(if $(wildcard extensions/$(EXT)/Dockerfile),extensions/$(EXT)/Dockerfile,Dockerfile.apt))
	@test -n "$(EXT_VERSION)" || { echo "Error: $(EXT) is not available for PG $(PG) (no VERSION_$(PG), and $(if $(EXT_APT_PACKAGE),PGDG has no postgresql-$(PG)-$(EXT_APT_PACKAGE),no APT_PACKAGE set))"; exit 1; }
	@test -f "$(DOCKERFILE)" || { echo "Error: $(EXT) has no Dockerfile and no APT_PACKAGE for the shared template"; exit 1; }
	@{ test "$(DOCKERFILE)" = "extensions/$(EXT)/Dockerfile" || test -n "$(EXT_APT_PACKAGE)"; } || { echo "Error: $(EXT) uses the shared Dockerfile.apt but has no APT_PACKAGE set"; exit 1; }
	@echo "Building $(PREFIX)-$(EXT):$(PG) (extension $(EXT_VERSION), $(if $(filter Dockerfile.apt,$(DOCKERFILE)),shared apt template,custom Dockerfile))..."
	docker buildx build \
		$(if $(PLATFORM),--platform $(PLATFORM)) \
		$(if $(CACHE_SCOPE),--cache-from type=gha$(comma)scope=$(EXT)-$(PG)) \
		$(if $(CACHE_SCOPE),--cache-from type=registry$(comma)ref=$(REGISTRY)/$(PREFIX)-$(EXT):$(PG)) \
		$(if $(CACHE_SCOPE),--cache-to type=gha$(comma)mode=max$(comma)scope=$(EXT)-$(PG)) \
		--build-arg PG_MAJOR=$(PG) \
		--build-arg PG_TAG=$(or $(PG_TAG),$(PG)) \
		--build-arg EXT_VERSION=$(EXT_VERSION) \
		--build-arg APT_PACKAGE=$(EXT_APT_PACKAGE) \
		--build-arg EXT_NAME=$(EXT) \
		--build-arg LAYOUT=$(if $(filter 17,$(PG)),classic,isolated) \
		--label "org.opencontainers.image.title=$(EXT)" \
		--label "org.opencontainers.image.description=$(EXT_DESC)" \
		--label "org.opencontainers.image.version=$(EXT_VERSION)" \
		--label "org.opencontainers.image.source=$(EXT_REPO)" \
		--label "org.opencontainers.image.licenses=$(EXT_LICENSE)" \
		--label "org.opencontainers.image.vendor=pglayers" \
		--label "org.opencontainers.image.base.name=scratch" \
		--label "io.pglayers.extension.name=$(EXT)" \
		--label "io.pglayers.extension.version=$(EXT_VERSION)" \
		--label "io.pglayers.pg.major=$(PG)" \
		--label "io.pglayers.layout=$(if $(filter 17,$(PG)),classic,isolated)" \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG) \
		-t $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)-$(EXT_VERSION) \
		-f $(DOCKERFILE) \
		$(if $(PLATFORM),--push,--load) \
		extensions/$(EXT)

comma := ,

build-all: ## Build all extensions for PG version(s)
	@failed=""; \
	for pg in $(PG); do \
		for ext in $(EXTENSIONS); do \
			version=$$(./scripts/ext-version.sh "$$ext" "$$pg"); \
			if [ -n "$$version" ]; then \
				$(MAKE) --no-print-directory build EXT=$$ext PG=$$pg || { \
					echo "FAILED: $$ext (PG $$pg)"; \
					failed="$${failed:+$$failed }$$ext:$$pg"; \
				}; \
			else \
				echo "Skipping $$ext (not available for PG $$pg)"; \
			fi; \
		done; \
	done; \
	if [ -n "$$failed" ]; then \
		echo; echo "Build failures: $$failed"; \
		exit 1; \
	fi

push: _check-ext ## Push a single extension image
	docker push $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)
	$(eval EXT_VERSION := $(shell ./scripts/ext-version.sh $(EXT) $(PG)))
	@test -n "$(EXT_VERSION)" && docker push $(REGISTRY)/$(PREFIX)-$(EXT):$(PG)-$(EXT_VERSION) || true

push-all: ## Push all extensions for PG version(s)
	@for pg in $(PG); do \
		for ext in $(EXTENSIONS); do \
			version=$$(./scripts/ext-version.sh "$$ext" "$$pg"); \
			if [ -n "$$version" ]; then \
				$(MAKE) --no-print-directory push EXT=$$ext PG=$$pg || exit 1; \
			fi; \
		done; \
	done

dockerfile: _check-ext ## Print the Dockerfile for an extension
	@if [ -f extensions/$(EXT)/Dockerfile ]; then \
		cat extensions/$(EXT)/Dockerfile; \
	else \
		echo "# $(EXT) uses the shared Dockerfile.apt (APT_PACKAGE=$$(bash -c 'source extensions/$(EXT)/extension.conf && echo $$APT_PACKAGE'))"; \
		cat Dockerfile.apt; \
	fi

info: _check-ext ## Show details for an extension
	@bash -c 'source extensions/$(EXT)/extension.conf; \
		echo "Extension: $(EXT)"; \
		echo "Description: $$DESCRIPTION"; \
		echo "Repository: $$REPO"; \
		if [ -n "$${APT_PACKAGE:-}" ]; then \
			echo "Source: PGDG apt (postgresql-<pg>-$$APT_PACKAGE); versions resolved at build"; \
		else \
			for v in $(PG_VERSIONS); do \
				ver_var="VERSION_$$v"; \
				ver="$${!ver_var}"; \
				[ -n "$$ver" ] && echo "PG $$v: $$ver"; \
			done; \
		fi; \
		[ -n "$$SHARED_PRELOAD" ] && echo "shared_preload_libraries: $$SHARED_PRELOAD"; \
		[ -n "$$NOTES" ] && echo "Notes: $$NOTES"'

add-apt-ext: ## Scaffold a new APT extension (PKG=<apt package> [NAME=<dir>] [PG=17])
	@test -n "$(PKG)" || { echo "Usage: make add-apt-ext PKG=<apt package> [NAME=<dir>] [PG=17]"; exit 1; }
	@name="$(or $(NAME),$(subst -,_,$(PKG)))"; \
	pg="$(or $(PG),17)"; \
	pgtag="$$pg"; [ "$$pg" = "19" ] && pgtag="19beta1"; \
	dir="extensions/$$name"; \
	if [ -e "$$dir" ]; then echo "Error: $$dir already exists"; exit 1; fi; \
	echo "Probing PGDG for postgresql-$$pg-$(PKG)..."; \
	ver=$$(./scripts/apt-support.sh version "$$pg" "$(PKG)"); \
	if [ -z "$$ver" ]; then echo "Error: postgresql-$$pg-$(PKG) not found in PGDG"; exit 1; fi; \
	echo "  version: $$ver"; \
	echo "Detecting license from Debian copyright..."; \
	lic=$$(./scripts/detect-license.sh "$$pg" "$(PKG)"); \
	echo "  license: $$lic"; \
	desc=$$(docker run --rm postgres:$$pgtag bash -c "apt-get update >/dev/null 2>&1; apt-cache show postgresql-$$pg-$(PKG) 2>/dev/null | awk '/^Description:/{sub(/^Description:[[:space:]]*/,\"\"); print; exit}'"); \
	mkdir -p "$$dir"; \
	{ \
		echo "DESCRIPTION=\"$$desc\""; \
		echo "REPO=\"\""; \
		echo "LICENSE=\"$$lic\""; \
		echo "SHARED_PRELOAD=\"\""; \
		echo "NOTES=\"\""; \
		echo "APT_PACKAGE=\"$(PKG)\""; \
	} > "$$dir/extension.conf"; \
	echo "Wrote $$dir/extension.conf"; \
	{ \
		echo "-- $$name integration tests (the single source of truth for"; \
		echo "-- functional coverage). Each check MUST print a line starting"; \
		echo "-- with PASS or FAIL. Replace the placeholder with real checks"; \
		echo "-- (data type, function, index/operator behaviour), and clean up."; \
		echo "CREATE EXTENSION IF NOT EXISTS $$name;"; \
		echo ""; \
		echo "SELECT CASE"; \
		echo "    WHEN (SELECT count(*) FROM pg_extension WHERE extname = '$$name') = 1"; \
		echo "    THEN 'PASS $$name: extension loads'"; \
		echo "    ELSE 'FAIL $$name: extension loads'"; \
		echo "END;"; \
	} > "$$dir/test.sql"; \
	echo "Wrote $$dir/test.sql (stub -- replace with real functional checks)"; \
	echo; \
	echo "Validating license policy..."; \
	./scripts/check-licenses.sh "$$name" || { \
		echo; \
		echo "The detected license is not auto-accepted. Either fix LICENSE in"; \
		echo "$$dir/extension.conf (if detection is wrong), add it to ALLOW_LICENSES,"; \
		echo "or record an exception in scripts/licenses.conf."; \
		exit 1; \
	}; \
	echo; \
	echo "Next steps:"; \
	echo "  - review $$dir/extension.conf (REPO, SHARED_PRELOAD, NOTES, DEPENDS, PG_CONF)"; \
	echo "  - flesh out $$dir/test.sql with real functional checks"; \
	echo "  - if the SQL name differs from '$$name', add it to EXT_SQL_NAMES in tests/test-layers.sh"; \
	echo "  - build: make build EXT=$$name PG=$$pg REGISTRY=local"

IMAGE_NAME ?= pglayers$(if $(PROFILE),-$(PROFILE))

image: ## Build a combined image with all extensions
	@echo "Building combined image $(IMAGE_NAME):$(PG)..."
	@TMPFILE=$$(mktemp); \
	skipped=""; \
	included_list=""; \
	included_label=""; \
	included=0; \
	total=0; \
	included_exts=""; \
	{ \
		echo "FROM postgres:$(PG)"; \
		for ext in $(EXTENSIONS); do \
			ver=$$(./scripts/ext-version.sh "$$ext" "$(PG)"); \
			[ -z "$$ver" ] && continue; \
			total=$$((total + 1)); \
			if [ "$(REGISTRY)" = "local" ]; then \
				docker image inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || { skipped="$${skipped:+$$skipped }$$ext"; continue; }; \
			else \
				docker buildx imagetools inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || { skipped="$${skipped:+$$skipped }$$ext"; continue; }; \
			fi; \
			if [ "$(PG)" -ge 18 ] 2>/dev/null; then \
				echo "COPY --from=$(REGISTRY)/$(PREFIX)-$$ext:$(PG) / /extensions/$$ext/"; \
			else \
				echo "COPY --from=$(REGISTRY)/$(PREFIX)-$$ext:$(PG) / /"; \
			fi; \
			included=$$((included + 1)); \
			included_list="$${included_list:+$$included_list,}\"$$ext\""; \
			included_label="$${included_label:+$$included_label }$$ext"; \
			included_exts="$${included_exts:+$$included_exts }$$ext"; \
		done; \
		if [ "$(PG)" -ge 18 ] 2>/dev/null; then \
			ext_paths=""; lib_paths=""; \
			for ext in $$included_exts; do \
				ext_paths="$${ext_paths}/extensions/$$ext/share:"; \
				lib_paths="$${lib_paths}/extensions/$$ext/lib:"; \
			done; \
			echo "RUN echo \"extension_control_path = '$${ext_paths}\\\$$system'\" >> /usr/share/postgresql/postgresql.conf.sample"; \
			echo "RUN echo \"dynamic_library_path = '$${lib_paths}\\\$$libdir'\" >> /usr/share/postgresql/postgresql.conf.sample"; \
		fi; \
		preloads=""; \
		for ext in $(EXTENSIONS); do \
			ver=$$(./scripts/ext-version.sh "$$ext" "$(PG)"); \
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
		for ext in $(EXTENSIONS); do \
			ver=$$(./scripts/ext-version.sh "$$ext" "$(PG)"); \
			[ -z "$$ver" ] && continue; \
			if [ "$(REGISTRY)" = "local" ]; then \
				docker image inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			else \
				docker buildx imagetools inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			fi; \
			pgconf=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$${PG_CONF:-}"'); \
			[ -z "$$pgconf" ] && continue; \
			echo "$$pgconf" | tr '|' '\n' | while IFS= read -r line; do \
				[ -z "$$line" ] && continue; \
				echo "RUN echo \"$$line\" >> /usr/share/postgresql/postgresql.conf.sample"; \
			done; \
		done; \
		if [ "$(PG)" -ge 18 ] 2>/dev/null && echo " $$included_exts " | grep -q ' pgsodium '; then \
			echo "RUN echo \"pgsodium.getkey_script = '/extensions/pgsodium/share/extension/pgsodium_getkey'\" >> /usr/share/postgresql/postgresql.conf.sample"; \
		fi; \
		companions=""; \
		for ext in $(EXTENSIONS); do \
			ver=$$(./scripts/ext-version.sh "$$ext" "$(PG)"); \
			[ -z "$$ver" ] && continue; \
			if [ "$(REGISTRY)" = "local" ]; then \
				docker image inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			else \
				docker buildx imagetools inspect "$(REGISTRY)/$(PREFIX)-$$ext:$(PG)" >/dev/null 2>&1 || continue; \
			fi; \
			cmd=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$${COMPANION_CMD:-}"'); \
			[ -n "$$cmd" ] && companions="$${companions:+$$companions|}$$cmd"; \
		done; \
		if [ -n "$$companions" ]; then \
			echo "RUN { echo '#!/bin/bash'; \\"; \
			echo "$${companions}" | tr '|' '\n' | while IFS= read -r c; do \
				[ -z "$$c" ] && continue; \
				echo "     echo '$$c &'; \\"; \
			done; \
			echo "     echo 'exec docker-entrypoint.sh \"\$$@\"'; \\"; \
			echo "   } > /usr/local/bin/pglayers-entrypoint.sh && chmod +x /usr/local/bin/pglayers-entrypoint.sh"; \
			echo "ENTRYPOINT [\"/usr/local/bin/pglayers-entrypoint.sh\"]"; \
			echo "CMD [\"postgres\"]"; \
		fi; \
		echo "RUN mkdir -p /etc/pglayers && echo '{' > /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"pg_version\": \"$(PG)\",' >> /etc/pglayers/manifest.json \\"; \
		echo "  && echo '  \"profile\": \"$(or $(PROFILE),full)\",' >> /etc/pglayers/manifest.json \\"; \
		if [ "$(PG)" -ge 18 ] 2>/dev/null; then \
			echo "  && echo '  \"layout\": \"isolated\",' >> /etc/pglayers/manifest.json \\"; \
		else \
			echo "  && echo '  \"layout\": \"classic\",' >> /etc/pglayers/manifest.json \\"; \
		fi; \
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

test-k8s: ## Run Kubernetes ImageVolume integration test (requires k3d, PG 18+)
	@./tests/test-k8s.sh $(REGISTRY) $(PG)

test-cnpg: ## Run CloudNativePG integration test (requires k3d, PG 18+)
	@./tests/test-cnpg.sh $(REGISTRY) $(PG)

list-profiles: ## List available profiles
	@printf "%-12s %-6s %s\n" "PROFILE" "COUNT" "DESCRIPTION"
	@printf "%-12s %-6s %s\n" "-------" "-----" "-----------"
	@for f in profiles/*.txt; do \
		name=$$(basename "$$f" .txt); \
		count=$$(grep -cv '^\(#\|$$\)' "$$f"); \
		desc=$$(head -1 "$$f" | sed 's/^# *//'); \
		printf "%-12s %-6d %s\n" "$$name" "$$count" "$$desc"; \
	done

check-licenses: ## Verify all extensions comply with the licensing policy
	@./scripts/check-licenses.sh

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
	@# Check that extension dependencies are satisfied within each profile
	@bash -c '\
		declare -A sql_to_dir; \
		for dir in extensions/*/; do \
			ext=$$(basename "$$dir"); \
			sql_to_dir[$$ext]=$$ext; \
		done; \
		while IFS= read -r line; do \
			dir=$$(echo "$$line" | sed "s/.*\[//;s/\].*//"); \
			sql=$$(echo "$$line" | sed "s/.*=\"//;s/\".*//"); \
			sql_to_dir[$$sql]=$$dir; \
		done < <(grep -E "^\s*\[.*\]=\"" tests/test-layers.sh | grep -v SKIP); \
		for f in profiles/*.txt; do \
			profile=$$(basename "$$f"); \
			while IFS= read -r ext; do \
				[ -z "$$ext" ] && continue; \
				echo "$$ext" | grep -q "^#" && continue; \
				deps=$$(bash -c "source extensions/$$ext/extension.conf && echo \$${DEPENDS:-}"); \
				[ -z "$$deps" ] && continue; \
				IFS="," read -ra dep_arr <<< "$$deps"; \
				for dep in "$${dep_arr[@]}"; do \
					dep_dir="$${sql_to_dir[$$dep]:-}"; \
					[ -z "$$dep_dir" ] && continue; \
					if ! grep -v "^#" "$$f" | grep -qx "$$dep_dir"; then \
						echo "Error: profile $$profile includes '\''$$ext'\'' but is missing dependency '\''$$dep_dir'\'' (provides $$dep)"; \
						exit 1; \
					fi; \
				done; \
			done < "$$f"; \
		done'
	@echo "All profiles valid."

cnpg-catalog: ## Generate CloudNativePG ClusterImageCatalog YAML (PG 18+)
	@PG=$${PG:-18}; \
	if [ "$$PG" -lt 18 ] 2>/dev/null; then \
		echo "Error: CNPG catalog requires PG >= 18 (isolated layout)"; exit 1; \
	fi; \
	echo "apiVersion: postgresql.cnpg.io/v1"; \
	echo "kind: ClusterImageCatalog"; \
	echo "metadata:"; \
	echo "  name: pglayers$(if $(PROFILE),-$(PROFILE))"; \
	echo "  labels:"; \
	echo "    io.pglayers.pg.major: \"$$PG\""; \
	echo "    io.pglayers.profile: \"$(or $(PROFILE),full)\""; \
	echo "spec:"; \
	echo "  images:"; \
	echo "    - major: $$PG"; \
	echo "      image: postgres:$$PG"; \
	echo "      extensions:"; \
	for ext in $(EXTENSIONS); do \
		ver=$$(./scripts/ext-version.sh "$$ext" "$$PG"); \
		[ -z "$$ver" ] && continue; \
		spl=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$$SHARED_PRELOAD"'); \
		deps=$$(bash -c 'source extensions/'"$$ext"'/extension.conf && echo "$${DEPENDS:-}"'); \
		echo "        - name: $$ext"; \
		echo "          image:"; \
		echo "            reference: $(REGISTRY)/$(PREFIX)-$$ext:$$PG-$$ver"; \
		if [ -n "$$spl" ]; then \
			echo "          shared_preload_libraries:"; \
			echo "            - $$spl"; \
		fi; \
		echo "          ld_library_path:"; \
		echo "            - lib"; \
		if [ -n "$$deps" ]; then \
			echo "          required_extensions:"; \
			echo "$$deps" | tr ',' '\n' | while IFS= read -r d; do \
				[ -z "$$d" ] && continue; \
				echo "            - $$d"; \
			done; \
		fi; \
	done

_check-ext:
	@test -n "$(EXT)" || { echo "Error: EXT is required. Usage: make build EXT=pgvector [PG=17]"; exit 1; }
	@test -d "extensions/$(EXT)" || { echo "Error: unknown extension '$(EXT)'. Run 'make list' to see available extensions."; exit 1; }
