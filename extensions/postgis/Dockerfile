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
    postgresql-${PG_MAJOR}-postgis-3 patchelf

# Extract extension files from all installed PG packages (includes -scripts)
RUN mkdir -p /output && \
    dpkg -l "postgresql-${PG_MAJOR}-postgis*" 2>/dev/null \
    | awk '/^ii/ {print $2}' \
    | xargs -I{} dpkg -L {} \
    | grep -E '^/usr/(lib|share)/postgresql/' \
    | sort -u \
    | while IFS= read -r f; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done && \
    # Resolve update-alternatives symlinks for .control files
    find /usr/share/postgresql/${PG_MAJOR}/extension -name '*.control' -type l \
    | while IFS= read -r link; do \
        target="$(readlink -f "$link")"; \
        [ -f "$target" ] || continue; \
        mkdir -p "/output$(dirname "$link")"; \
        ln -sf "$(basename "$target")" "/output$link"; \
    done

# Bundle runtime shared libraries not in the base postgres image
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
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=builder /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible).
# Each extension resolves its OWN bundled deps from its private
# /extensions/<ext>/lib via $ORIGIN RUNPATH -- never through a global ld.so
# cache. Bundled-dep sonames are mangled with a per-extension prefix so two
# layers that ship the same soname (e.g. libssh2.so.1 pulled in via libcurl by
# both postgis and pg_duckdb) can't clash in the shared postgres process.
FROM builder AS normalizer
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    tag="pglx_postgis_"; \
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
