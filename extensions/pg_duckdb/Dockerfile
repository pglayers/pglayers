# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v1.1.1

# Stage 1: Build DuckDB engine (PG-independent, cached across PG versions)
# DuckDB is ~1M lines of C++; this takes ~10-15 min but is identical for all PG versions.
FROM debian:bookworm AS duckdb-builder
ARG EXT_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    cmake ninja-build libssl-dev pkg-config \
    liblz4-dev libicu-dev libcurl4-openssl-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 --recurse-submodules \
    https://github.com/duckdb/pg_duckdb.git /tmp/ext

WORKDIR /tmp/ext

# Build DuckDB directly via its own Makefile (bypasses pg_duckdb's PGXS check)
RUN OVERRIDE_GIT_DESCRIBE=v1.4.3 \
    GEN=ninja \
    CMAKE_VARS="-DCXX_EXTRA=-fvisibility=default -DBUILD_SHELL=0 -DBUILD_PYTHON=0 -DBUILD_UNITTESTS=0" \
    DISABLE_SANITIZER=1 \
    EXTENSION_CONFIGS="../pg_duckdb_extensions.cmake" \
    make -C third_party/duckdb release

# Stage 2: Build pg_duckdb extension (PG-specific, ~1-2 min)
FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    cmake ninja-build libssl-dev pkg-config \
    liblz4-dev libicu-dev libcurl4-openssl-dev

# Copy source tree with pre-built DuckDB library
COPY --from=duckdb-builder /tmp/ext /tmp/ext

WORKDIR /tmp/ext

# Build only the pg_duckdb extension (DuckDB library already built)
RUN make -j"$(nproc)" DUCKDB_GEN=ninja \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle runtime shared libraries not in the base postgres image.
# Uses libcurl-openssl (same as PostGIS) so the files are identical
# when both extensions are combined in the same image.
RUN set -eux; \
    MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"; \
    LIBDIR="/usr/lib/${MULTIARCH}"; \
    mkdir -p /output${LIBDIR}; \
    cp -a ${LIBDIR}/libcurl.so* /output${LIBDIR}/

FROM scratch
COPY --from=builder /output/ /
