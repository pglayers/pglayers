# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.2-20250903

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libicu-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/pgbigm/pg_bigm.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" USE_PGXS=1 && make install USE_PGXS=1 DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
