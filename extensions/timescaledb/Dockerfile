# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=2.28.0

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    cmake libssl-dev libkrb5-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/timescale/timescaledb.git /tmp/ext

WORKDIR /tmp/ext/build

# Build Apache-2.0 community edition only (no TSL-licensed code)
RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DAPACHE_ONLY=ON \
    -DREGRESS_CHECKS=OFF \
    -DWARNINGS_AS_ERRORS=OFF \
    .. \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
