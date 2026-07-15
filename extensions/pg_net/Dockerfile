# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic

FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v0.20.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates patchelf \
    postgresql-server-dev-${PG_MAJOR} \
    libcurl4-openssl-dev libicu-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/supabase/pg_net.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle ALL runtime shared libraries not in the base postgres image so the
# layer is fully self-contained (pg_net links libcurl, which is NOT in the
# base image -- it must ship its own, never borrow a sibling's). Collisions
# in the flat classic layout are prevented later by relocating these into a
# private dir with RUNPATH.
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    PG=${PG_MAJOR}; \
    find /output/usr/lib/postgresql/${PG}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output$dest" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

# --- Layout selection ---
# Classic (PG 17): relocate bundled deps into an extension-private directory
# and point the extension's RUNPATH at it via $ORIGIN. Keeps the flat layout
# self-contained AND collision-free (private dir name is unique per ext).
FROM builder AS classic-relocate
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    EXT=pg_net; \
    LIBDIR="/output/usr/lib/postgresql/${PG}/lib"; \
    DEPS_DIR="${LIBDIR}/${EXT}-deps"; \
    tag="pglx_${EXT}_"; \
    mkdir -p "$DEPS_DIR"; \
    find /output/usr/lib -path '/output/usr/lib/postgresql' -prune -o \
        -name '*.so*' \( -type f -o -type l \) -print \
        | while IFS= read -r lib; do mv "$lib" "$DEPS_DIR/"; done; \
    # Mangle bundled dep sonames with a per-extension prefix so they can never
    # satisfy another layer's (or postgis's) soname in the shared postgres
    # process. See extensions/pg_duckdb/Dockerfile for the rationale.
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        bn="$(basename "$dep")"; \
        patchelf --set-soname "${tag}${bn}" "$dep"; \
        mv "$dep" "$DEPS_DIR/${tag}${bn}"; \
    done; \
    for obj in "$LIBDIR"/*.so* "$DEPS_DIR"/*.so*; do \
        [ -f "$obj" ] || continue; \
        for need in $(patchelf --print-needed "$obj" 2>/dev/null); do \
            case "$need" in "${tag}"*) continue ;; esac; \
            if [ -f "$DEPS_DIR/${tag}${need}" ]; then \
                patchelf --replace-needed "$need" "${tag}${need}" "$obj"; \
            fi; \
        done; \
    done; \
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
FROM builder AS normalizer
ARG PG_MAJOR
RUN mkdir -p /isolated/lib /isolated/share/extension && \
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; && \
    cp -a /output/usr/share/postgresql/${PG_MAJOR}/extension/* \
        /isolated/share/extension/ && \
    # Bundled runtime deps (system libs not in base image)
    find /output/usr/lib -name '*.so*' ! -path '*/postgresql/*' \
        \( -type f -o -type l \) -exec cp -a {} /isolated/lib/ \; && \
    cp -a /output/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
