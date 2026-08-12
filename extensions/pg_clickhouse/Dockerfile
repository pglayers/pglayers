# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic
ARG EXT_VERSION=0.10.0

# Use ClickHouse's official pre-built pg_clickhouse image (avoids compiling the
# extension + the RE2/abseil dependency stack). Same approach as pg_duckdb.
# NOTE: upstream tags the image WITHOUT a leading "v" (e.g. 18-0.10.0), so
# EXT_VERSION/VERSION_XX are stored v-less to match this tag directly.
FROM ghcr.io/clickhouse/pg_clickhouse:${PG_MAJOR}-${EXT_VERSION} AS upstream

# Snapshot base image libraries for diffing (by soname, not canonical path)
FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

# Collector: extract extensions + bundle missing runtime deps.
# The upstream image ships two extensions in one layer: pg_clickhouse (the FDW)
# and re2 (its recommended companion, ClickHouse-compatible RE2 regex functions
# used for regex pushdown). We ship both, exactly as upstream packages them.
FROM upstream AS collector
ARG PG_MAJOR
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends patchelf

# Copy extension artifacts (both pg_clickhouse and re2) to /output
RUN set -eux; \
    PG=${PG_MAJOR}; \
    LIB="/usr/lib/postgresql/${PG}/lib"; \
    SHARE="/usr/share/postgresql/${PG}/extension"; \
    mkdir -p "/output${LIB}/bitcode" \
             "/output${SHARE}"; \
    cp "${LIB}/pg_clickhouse.so" "/output${LIB}/"; \
    cp "${LIB}/re2.so" "/output${LIB}/"; \
    cp "${SHARE}"/pg_clickhouse* "/output${SHARE}/"; \
    cp "${SHARE}"/re2* "/output${SHARE}/"; \
    # Bitcode: per-extension index files + the pg_clickhouse subtree. Copy only
    # our files so we never overwrite the base image's bitcode entries.
    for bc in "${LIB}/bitcode/pg_clickhouse.index.bc" \
              "${LIB}/bitcode/re2.index.bc"; do \
        [ -f "$bc" ] && cp "$bc" "/output${LIB}/bitcode/"; \
    done; \
    [ -d "${LIB}/bitcode/pg_clickhouse" ] && \
        cp -r "${LIB}/bitcode/pg_clickhouse" "/output${LIB}/bitcode/" || true

# Bundle ALL runtime shared libraries that pg_clickhouse/re2 need but the base
# postgres image doesn't have (libcurl + transitive brotli/nghttp/ssh2/rtmp/psl,
# and re2's libre2 + the whole libabsl_* / libstdc++ stack), so the layer is
# fully self-contained (never rely on a sibling layer to provide libcurl et al.).
# Compare by soname to avoid bundling older versions of libs already in the base
# image. Collisions in the flat classic layout are prevented later by relocating
# these into a private dir with RUNPATH + mangled sonames.
RUN set -eux; \
    PG=${PG_MAJOR}; \
    ldd /usr/lib/postgresql/${PG}/lib/pg_clickhouse.so \
        /usr/lib/postgresql/${PG}/lib/re2.so 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output${dest}" 2>/dev/null || true; \
    done < /tmp/all-deps.txt; \
    find /output -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

# --- Layout selection ---
# Classic (PG 17): relocate bundled deps into an extension-private directory
# and point each ELF object's RUNPATH at it via $ORIGIN. Keeps the flat layout
# self-contained AND collision-free (private dir name is unique per ext).
FROM collector AS classic-relocate
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    EXT=pg_clickhouse; \
    LIBDIR="/output/usr/lib/postgresql/${PG}/lib"; \
    DEPS_DIR="${LIBDIR}/${EXT}-deps"; \
    tag="pglx_${EXT}_"; \
    mkdir -p "$DEPS_DIR"; \
    find /output/usr/lib -path '/output/usr/lib/postgresql' -prune -o \
        -name '*.so*' \( -type f -o -type l \) -print \
        | while IFS= read -r lib; do mv "$lib" "$DEPS_DIR/"; done; \
    # Mangle each bundled dep's soname with a per-extension prefix. sonames are
    # process-global, so a private dir + RUNPATH alone does NOT isolate symbols:
    # if a sibling extension loads its own libssh2.so.1 first, our libcurl would
    # bind to it and hit undefined symbols. Unique sonames make cross-layer
    # clashes impossible while keeping the layer self-contained.
    find "$DEPS_DIR" -type l -delete 2>/dev/null || true; \
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        soname="$(patchelf --print-soname "$dep" 2>/dev/null || true)"; \
        [ -n "$soname" ] || soname="$(basename "$dep")"; \
        patchelf --set-soname "${tag}${soname}" "$dep"; \
        mv "$dep" "$DEPS_DIR/${tag}${soname}"; \
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

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible).
# Each extension resolves its OWN bundled deps from its private
# /extensions/<ext>/lib via $ORIGIN RUNPATH -- never through a global ld.so
# cache. Bundled-dep sonames are mangled with a per-extension prefix so two
# layers that ship the same soname (e.g. libssh2.so.1 pulled in via libcurl by
# both postgis and pg_clickhouse) can't clash in the shared postgres process.
FROM collector AS normalizer
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    tag="pglx_pg_clickhouse_"; \
    mkdir -p /isolated/lib /isolated/share/extension; \
    find /output/usr/lib/postgresql/${PG}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; ; \
    cp -a /output/usr/share/postgresql/${PG}/extension/* /isolated/share/extension/; \
    : > /tmp/bundled.txt; \
    find /output/usr/lib -name '*.so*' ! -path '*/postgresql/*' \
        \( -type f -o -type l \) 2>/dev/null | while IFS= read -r f; do \
        cp -a "$f" /isolated/lib/ && basename "$f" >> /tmp/bundled.txt; \
    done; \
    cp -a /output/usr/lib/postgresql/${PG}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true; \
    if [ -s /tmp/bundled.txt ]; then \
        sort -u /tmp/bundled.txt > /tmp/bundled-u.txt; \
        while IFS= read -r name; do \
            [ -L "/isolated/lib/$name" ] && rm -f "/isolated/lib/$name" || true; \
        done < /tmp/bundled-u.txt; \
        while IFS= read -r name; do \
            dep="/isolated/lib/$name"; \
            [ -f "$dep" ] || continue; \
            soname="$(patchelf --print-soname "$dep" 2>/dev/null || true)"; \
            [ -n "$soname" ] || soname="$name"; \
            patchelf --set-soname "${tag}${soname}" "$dep"; \
            mv "$dep" "/isolated/lib/${tag}${soname}"; \
        done < /tmp/bundled-u.txt; \
        for obj in /isolated/lib/*.so*; do \
            [ -f "$obj" ] || continue; \
            for need in $(patchelf --print-needed "$obj" 2>/dev/null); do \
                case "$need" in "${tag}"*) continue ;; esac; \
                if [ -f "/isolated/lib/${tag}${need}" ]; then \
                    patchelf --replace-needed "$need" "${tag}${need}" "$obj"; \
                fi; \
            done; \
        done; \
    fi; \
    for obj in /isolated/lib/*.so*; do \
        [ -f "$obj" ] || continue; \
        patchelf --set-rpath '$ORIGIN' "$obj"; \
    done

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
