# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.1.1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    cmake ninja-build libssl-dev pkg-config \
    liblz4-dev libicu-dev libcurl4-openssl-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 --recurse-submodules \
    https://github.com/duckdb/pg_duckdb.git /tmp/ext

WORKDIR /tmp/ext

# Build DuckDB and pg_duckdb
RUN make -j"$(nproc)" DUCKDB_GEN=ninja \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle runtime shared libraries not in the base postgres image
RUN set -eux; \
    MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"; \
    LIBDIR="/usr/lib/${MULTIARCH}"; \
    mkdir -p /output${LIBDIR}; \
    cp -a ${LIBDIR}/libcurl.so* /output${LIBDIR}/

FROM scratch
COPY --from=builder /output/ /
