# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic
ARG EXT_VERSION=v0.113-0

# ── Stage 1: Snapshot base image libs (for dep-bundling) ────────────
FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

# ── Stage 2: Extract C extensions from release deb ──────────────────
FROM postgres:${PG_TAG} AS deb-stage
ARG PG_MAJOR
ARG EXT_VERSION
ARG TARGETARCH

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates patchelf

# Download DocumentDB deb from GitHub releases.
# Tag format: v0.113-0 -> deb version: 0.113-0
# Use deb13 (trixie) to match the postgres:17+ base image.
RUN DEB_VERSION="${EXT_VERSION#v}" && \
    curl -fsSL -o /tmp/documentdb.deb \
    "https://github.com/documentdb/documentdb/releases/download/${EXT_VERSION}/deb13-postgresql-${PG_MAJOR}-documentdb_${DEB_VERSION}_${TARGETARCH}.deb"

# Extract deb contents without installing (avoids dependency resolution)
RUN mkdir -p /extracted && dpkg-deb -x /tmp/documentdb.deb /extracted

# Copy only PostgreSQL extension files to output
RUN mkdir -p /output && \
    find /extracted/usr/lib/postgresql/ /extracted/usr/share/postgresql/ \
        -type f 2>/dev/null \
    | while IFS= read -r f; do \
        dest="${f#/extracted}"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -a "$f" "/output$dest"; \
    done

# Bundle runtime shared libraries not in the base postgres image
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
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

# ── Stage 3: Install cargo-pgrx + clone source (PG-independent) ────
FROM rust:1.92-bookworm AS pgrx-builder
ARG EXT_VERSION

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install cargo-pgrx --version 0.16.0 --locked

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && git clone --branch ${EXT_VERSION} --depth 1 \
       https://github.com/documentdb/documentdb.git /tmp/ext

# ── Stage 4: Build pg_documentdb_gw_host (PG-specific) ─────────────
FROM rust:1.92-bookworm AS rust-builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        postgresql-${PG_MAJOR} \
        postgresql-server-dev-${PG_MAJOR} \
        pkg-config libssl-dev libclang-dev clang

COPY --from=pgrx-builder /usr/local/cargo/bin/cargo-pgrx /usr/local/cargo/bin/cargo-pgrx
COPY --from=pgrx-builder /tmp/ext /tmp/ext

RUN cargo pgrx init "--pg${PG_MAJOR}=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config"

WORKDIR /tmp/ext/pg_documentdb_gw_host

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/tmp/ext/pg_documentdb_gw_host/target \
    cargo pgrx package --no-default-features --features "pg${PG_MAJOR}" \
        --pg-config "/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config" \
    && mkdir -p /output \
    && cp -a target/release/pg_documentdb_gw_host-pg${PG_MAJOR}/* /output/ \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# ── Final: Combine all artifacts ────────────────────────────────────
# --- Layout selection ---
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=deb-stage /output/ /
COPY --from=rust-builder /output/ /
COPY documentdb_gw_config.json /etc/documentdb/gateway_config.json

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible).
# Each extension resolves its OWN bundled deps from its private
# /extensions/<ext>/lib via $ORIGIN RUNPATH -- never through a global ld.so
# cache -- with bundled-dep sonames mangled per extension so identical sonames
# in sibling layers can't clash in the shared postgres process.
FROM deb-stage AS normalizer
ARG PG_MAJOR
COPY --from=rust-builder /output/ /output/
COPY documentdb_gw_config.json /output/etc/documentdb/gateway_config.json
RUN set -eux; \
    PG=${PG_MAJOR}; \
    tag="pglx_documentdb_"; \
    mkdir -p /isolated/lib /isolated/share/extension /isolated/etc/documentdb; \
    find /output/usr/lib/postgresql/${PG}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; ; \
    cp -a /output/usr/share/postgresql/${PG}/extension/* /isolated/share/extension/; \
    cp -a /output/etc/documentdb/* /isolated/etc/documentdb/; \
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
