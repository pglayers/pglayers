# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic

FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    postgresql-${PG_MAJOR}-http patchelf

# Extract extension files (exclude headers and docs)
RUN mkdir -p /output && \
    dpkg -L postgresql-${PG_MAJOR}-http \
    | grep -E '^/usr/(lib|share)/postgresql/' \
    | while IFS= read -r f; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done

# Bundle ALL runtime shared libraries not in the base postgres image so the
# layer is fully self-contained (never rely on a sibling layer such as
# postgis to provide libcurl et al.). Collisions in the flat classic layout
# are prevented later by relocating these into a private dir with RUNPATH.
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
# Classic (PG 17): files at standard PG paths. The flat layout means every
# layer shares /usr/lib/<multiarch>/, so two extensions bundling the same
# soname (e.g. libcurl.so.4) at different versions would collide. Relocate
# the bundled deps into an extension-private directory and point the
# extension's RUNPATH at it via $ORIGIN. This keeps the layer self-contained
# AND collision-free (the private dir name is unique per extension).
FROM builder AS classic-relocate
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    EXT=http; \
    LIBDIR="/output/usr/lib/postgresql/${PG}/lib"; \
    DEPS_DIR="${LIBDIR}/${EXT}-deps"; \
    tag="pglx_${EXT}_"; \
    mkdir -p "$DEPS_DIR"; \
    # Move every bundled system lib (all of /output/usr/lib except the
    # postgresql tree) into the private deps dir.
    find /output/usr/lib -path '/output/usr/lib/postgresql' -prune -o \
        -name '*.so*' \( -type f -o -type l \) -print \
        | while IFS= read -r lib; do mv "$lib" "$DEPS_DIR/"; done; \
    # Mangle each bundled dep's soname with a per-extension prefix. sonames
    # are process-global, so a private dir + RUNPATH alone does NOT isolate
    # symbols: if a sibling extension (e.g. via shared_preload_libraries)
    # loads its own libssh2.so.1 first, postgis's libcurl would bind to it
    # and hit undefined symbols. Unique sonames make cross-layer clashes
    # impossible while keeping the layer self-contained.
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
    # Extension .so files resolve siblings ($ORIGIN) and bundled deps.
    for so in "$LIBDIR"/*.so*; do \
        [ -f "$so" ] || continue; \
        patchelf --set-rpath "\$ORIGIN:\$ORIGIN/${EXT}-deps" "$so"; \
    done; \
    # Bundled deps resolve each other from within the private dir.
    for dep in "$DEPS_DIR"/*.so*; do \
        [ -f "$dep" ] || continue; \
        patchelf --set-rpath '$ORIGIN' "$dep"; \
    done; \
    # Drop now-empty multiarch dirs left behind by the move.
    find /output/usr/lib -type d -empty -delete 2>/dev/null || true

FROM scratch AS classic
COPY --from=classic-relocate /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible)
FROM builder AS normalizer
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
