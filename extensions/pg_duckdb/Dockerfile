# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic
ARG EXT_VERSION=v1.1.1

# Use official pre-built pg_duckdb image (avoids 10-15 min DuckDB compilation).
FROM pgduckdb/pgduckdb:${PG_MAJOR}-${EXT_VERSION} AS upstream

# Snapshot base image libraries for diffing (by soname, not canonical path)
FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

# Collector: extract extension + bundle missing runtime deps
FROM upstream AS collector
ARG PG_MAJOR
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends patchelf

# Copy extension artifacts to /output
RUN set -eux; \
    PG=${PG_MAJOR}; \
    mkdir -p /output/usr/lib/postgresql/${PG}/lib/bitcode \
             /output/usr/share/postgresql/${PG}/extension; \
    cp /usr/lib/postgresql/${PG}/lib/libduckdb.so /output/usr/lib/postgresql/${PG}/lib/; \
    cp /usr/lib/postgresql/${PG}/lib/pg_duckdb.so /output/usr/lib/postgresql/${PG}/lib/; \
    cp /usr/lib/postgresql/${PG}/lib/bitcode/pg_duckdb.index.bc /output/usr/lib/postgresql/${PG}/lib/bitcode/; \
    cp -r /usr/lib/postgresql/${PG}/lib/bitcode/pg_duckdb /output/usr/lib/postgresql/${PG}/lib/bitcode/; \
    cp /usr/share/postgresql/${PG}/extension/pg_duckdb* /output/usr/share/postgresql/${PG}/extension/

# Bundle ALL runtime shared libraries that pg_duckdb needs but the base
# postgres image doesn't have, so the layer is fully self-contained (never
# rely on a sibling layer such as http/postgis to provide libcurl et al.).
# Compare by soname to avoid bundling older versions of libs already present
# in the base image. Collisions in the flat classic layout are prevented
# later by relocating these into a private dir with RUNPATH.
RUN set -eux; \
    PG=${PG_MAJOR}; \
    # Collect all ldd-reported paths from extension .so files
    ldd /usr/lib/postgresql/${PG}/lib/pg_duckdb.so \
        /usr/lib/postgresql/${PG}/lib/libduckdb.so 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    # Copy each dep whose soname is not already in the base image
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output${dest}" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

# --- Layout selection ---
# Classic (PG 17): relocate bundled deps into an extension-private directory
# and point the extension's RUNPATH at it via $ORIGIN. Keeps the flat layout
# self-contained AND collision-free (private dir name is unique per ext).
FROM collector AS classic-relocate
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    EXT=pg_duckdb; \
    LIBDIR="/output/usr/lib/postgresql/${PG}/lib"; \
    DEPS_DIR="${LIBDIR}/${EXT}-deps"; \
    tag="pglx_${EXT}_"; \
    mkdir -p "$DEPS_DIR"; \
    find /output/usr/lib -path '/output/usr/lib/postgresql' -prune -o \
        -name '*.so*' \( -type f -o -type l \) -print \
        | while IFS= read -r lib; do mv "$lib" "$DEPS_DIR/"; done; \
    # Mangle each bundled dep's soname with a per-extension prefix. sonames
    # are process-global, so a private dir + RUNPATH alone does NOT isolate
    # symbols: if a sibling extension (e.g. via shared_preload_libraries)
    # loads its own libssh2.so.1 first, postgis's libcurl would bind to it
    # and hit undefined symbols. Unique sonames make cross-layer clashes
    # impossible while keeping the layer self-contained.
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        bn="$(basename "$dep")"; \
        patchelf --set-soname "${tag}${bn}" "$dep"; \
        mv "$dep" "$DEPS_DIR/${tag}${bn}"; \
    done; \
    # Rewrite NEEDED refs to bundled libs across every ELF object we ship.
    for obj in "$LIBDIR"/*.so* "$DEPS_DIR"/*.so*; do \
        [ -f "$obj" ] || continue; \
        for need in $(patchelf --print-needed "$obj" 2>/dev/null); do \
            case "$need" in "${tag}"*) continue ;; esac; \
            if [ -f "$DEPS_DIR/${tag}${need}" ]; then \
                patchelf --replace-needed "$need" "${tag}${need}" "$obj"; \
            fi; \
        done; \
    done; \
    # Point RUNPATHs at the private dir ($ORIGIN for siblings + deps).
    for so in "$LIBDIR"/*.so*; do \
        [ -f "$so" ] || continue; \
        patchelf --set-rpath "\$ORIGIN:\$ORIGIN/${EXT}-deps" "$so"; \
    done; \
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        patchelf --set-rpath '$ORIGIN' "$dep"; \
    done; \
    find /output/usr/lib -type d -empty -delete 2>/dev/null || true

FROM scratch AS classic
COPY --from=classic-relocate /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible)
FROM collector AS normalizer
ARG PG_MAJOR
RUN mkdir -p /isolated/lib /isolated/share/extension && \
    # Extension .so files
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; && \
    # Control + SQL files
    cp -a /output/usr/share/postgresql/${PG_MAJOR}/extension/* \
        /isolated/share/extension/ && \
    # Bundled runtime deps (system libs not in base image)
    find /output/usr/lib -name '*.so*' ! -path '*/postgresql/*' \
        \( -type f -o -type l \) -exec cp -a {} /isolated/lib/ \; && \
    # Bitcode (optional, for JIT)
    cp -a /output/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
