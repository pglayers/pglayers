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
    done < /tmp/all-deps.txt; \
    # Strip bundled deps too. Today these are all Debian apt libs (already
    # stripped), but the strip pass above runs before this bundling step, so
    # strip here defensively -- keeps the layer minimal if a self-built lib is
    # ever bundled. strip --strip-unneeded is safe and idempotent.
    find /output -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

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
    find "$DEPS_DIR" -type l -delete 2>/dev/null || true; \
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        soname="$(patchelf --print-soname "$dep" 2>/dev/null || true)"; \
        [ -n "$soname" ] || soname="$(basename "$dep")"; \
        patchelf --set-soname "${tag}${soname}" "$dep"; \
        mv "$dep" "$DEPS_DIR/${tag}${soname}"; \
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

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible).
# Each extension resolves its OWN bundled deps from its private
# /extensions/<ext>/lib via $ORIGIN RUNPATH -- never through a global ld.so
# cache. Bundled-dep sonames are mangled with a per-extension prefix so two
# layers that ship the same soname (e.g. libcurl.so.4) can't clash in the
# shared postgres process.
FROM builder AS normalizer
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    tag="pglx_pg_net_"; \
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
