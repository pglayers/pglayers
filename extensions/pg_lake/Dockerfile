# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v3.3.4
ARG VCPKG_VERSION=2025.10.17

# Capture base image library list for dep-bundling
FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

# Stage 1: Build vcpkg + Azure SDK (PG-independent, heavily cached)
FROM debian:bookworm AS vcpkg-builder
ARG VCPKG_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates pkg-config curl zip unzip \
    cmake ninja-build libssl-dev libcurl4-openssl-dev

RUN git clone --branch ${VCPKG_VERSION} --depth 1 \
    https://github.com/Microsoft/vcpkg.git /opt/vcpkg \
    && /opt/vcpkg/bootstrap-vcpkg.sh

RUN /opt/vcpkg/vcpkg install \
    azure-identity-cpp azure-storage-blobs-cpp \
    azure-storage-files-datalake-cpp openssl

# Stage 2: Build pg_lake extensions + pgduck_server
FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates pkg-config cmake ninja-build \
    postgresql-server-dev-${PG_MAJOR} \
    libssl-dev libcurl4-openssl-dev libjansson-dev \
    liblz4-dev liblzma-dev libsnappy-dev \
    libxml2-dev libxslt1-dev libicu-dev libpam0g-dev \
    libreadline-dev libselinux1-dev patch python3-dev curl

COPY --from=vcpkg-builder /opt/vcpkg /opt/vcpkg
ENV VCPKG_TOOLCHAIN_PATH="/opt/vcpkg/scripts/buildsystems/vcpkg.cmake"

RUN git clone --branch ${EXT_VERSION} --recurse-submodules --depth 1 \
    https://github.com/Snowflake-Labs/pg_lake.git /tmp/pg_lake

WORKDIR /tmp/pg_lake

# Build and install everything (avro + extensions + DuckDB + pgduck_server)
# LIBRARY_PATH ensures pgduck_server linker finds libpgcommon/libpgport in pkglibdir
RUN LIBRARY_PATH="$(pg_config --pkglibdir):${LIBRARY_PATH:-}" \
    make install -j"$(nproc)"

# Collect output artifacts
RUN mkdir -p /output && \
    PG_LIBDIR="$(pg_config --pkglibdir)" && \
    PG_SHAREDIR="$(pg_config --sharedir)" && \
    PG_BINDIR="$(pg_config --bindir)" && \
    # Extension shared libraries
    for f in "$PG_LIBDIR"/pg_lake*.so \
             "$PG_LIBDIR"/pg_extension_base.so \
             "$PG_LIBDIR"/pg_extension_updater.so \
             "$PG_LIBDIR"/pg_map.so \
             "$PG_LIBDIR"/libduckdb.so \
             "$PG_LIBDIR"/libavro.*; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done && \
    # Extension SQL and control files
    for f in "$PG_SHAREDIR"/extension/pg_lake* \
             "$PG_SHAREDIR"/extension/pg_extension_base* \
             "$PG_SHAREDIR"/extension/pg_extension_updater* \
             "$PG_SHAREDIR"/extension/pg_map*; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done && \
    # pgduck_server binary
    if [ -f "$PG_BINDIR/pgduck_server" ]; then \
        mkdir -p "/output$PG_BINDIR"; \
        cp -a "$PG_BINDIR/pgduck_server" "/output$PG_BINDIR/"; \
    fi && \
    # Strip binaries
    find /output -name '*.so' -exec strip --strip-unneeded {} \; && \
    find /output -name 'pgduck_server' -exec strip --strip-unneeded {} \;

# Create auto-start entrypoint wrapper
RUN mkdir -p /output/usr/local/bin && \
    printf '%s\n' \
        '#!/bin/bash' \
        '# Start pgduck_server in the background (required by pg_lake extensions).' \
        '# Listens on Unix socket /tmp:5332 -- no external port needed.' \
        'PG_BINDIR="$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/17/bin)"' \
        'if [ -x "$PG_BINDIR/pgduck_server" ]; then' \
        '    "$PG_BINDIR/pgduck_server" --cache_dir /tmp/pg_lake_cache &' \
        'fi' \
        'exec docker-entrypoint.sh "$@"' \
        > /output/usr/local/bin/pg-lake-entrypoint.sh && \
    chmod +x /output/usr/local/bin/pg-lake-entrypoint.sh

# Bundle runtime shared libraries not present in the base postgres image
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    find /output -name '*.so*' -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    ldd /output/$(pg_config --bindir)/pgduck_server 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' >> /tmp/all-deps.txt; \
    sort -u -o /tmp/all-deps.txt /tmp/all-deps.txt; \
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output$dest" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

FROM scratch
COPY --from=builder /output/ /
