# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=main

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    cmake

# h3-pg builds h3 from source via CMake FetchContent
RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/zachasme/h3-pg.git /tmp/ext

WORKDIR /tmp/ext/build

RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DPOSTGRESQL_VERSION=${PG_MAJOR} \
    .. \
    && touch /tmp/ext/h3/typedefs.list /tmp/ext/h3_postgis/typedefs.list \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
