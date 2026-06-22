# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.1.9

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR}

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/postgrespro/pg_wait_sampling.git /tmp/ext

WORKDIR /tmp/ext

RUN make USE_PGXS=1 -j"$(nproc)" && make USE_PGXS=1 install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
