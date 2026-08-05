# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v3.1.11
ARG LIBSODIUM_VERSION=1.0.22

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates curl patchelf \
    postgresql-server-dev-${PG_MAJOR}

# Build libsodium from source (distro version too old for pgsodium 3.1.11+).
# Fetch from the GitHub release mirror first, falling back to the canonical
# download.libsodium.org host (which intermittently fails DNS in CI), each with
# retries.
RUN set -eux; \
    for url in \
        "https://github.com/jedisct1/libsodium/releases/download/${LIBSODIUM_VERSION}-RELEASE/libsodium-${LIBSODIUM_VERSION}.tar.gz" \
        "https://download.libsodium.org/libsodium/releases/libsodium-${LIBSODIUM_VERSION}.tar.gz" \
    ; do \
        if curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
            -o /tmp/libsodium.tar.gz "$url"; then \
            break; \
        fi; \
    done; \
    test -s /tmp/libsodium.tar.gz; \
    tar xz -C /tmp -f /tmp/libsodium.tar.gz; \
    cd /tmp/libsodium-${LIBSODIUM_VERSION}; \
    ./configure --prefix=/usr && make -j"$(nproc)" && make install; \
    rm -f /tmp/libsodium.tar.gz

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/michelp/pgsodium.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle libsodium runtime library (not in base postgres image)
RUN cp /usr/lib/libsodium.so* /output/usr/lib/

# Install default getkey script (generates a random root key in $PGDATA)
RUN install -m 755 /dev/stdin \
    /output/usr/share/postgresql/${PG_MAJOR}/extension/pgsodium_getkey <<'SCRIPT'
#!/bin/bash
KEY_FILE=$PGDATA/pgsodium_root.key
if [ ! -f "$KEY_FILE" ]; then
    head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "$KEY_FILE"
fi
cat "$KEY_FILE"
SCRIPT

# --- Layout selection ---
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=builder /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible).
# pgsodium bundles libsodium; each extension resolves its OWN bundled deps
# from its private /extensions/<ext>/lib via $ORIGIN RUNPATH (never a global
# ld.so cache), with the bundled soname mangled per extension so it can't
# clash with a sibling layer's libsodium in the shared postgres process.
FROM builder AS normalizer
ARG PG_MAJOR
RUN set -eux; \
    PG=${PG_MAJOR}; \
    tag="pglx_pgsodium_"; \
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
