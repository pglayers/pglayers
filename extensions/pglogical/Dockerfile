# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=REL2_4_7

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libkrb5-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/2ndQuadrant/pglogical.git /tmp/ext

WORKDIR /tmp/ext

# Skip pglogical_create_subscriber (optional CLI tool that requires
# PostgreSQL static archives not available in the -dev package).
RUN make -j"$(nproc)" SCRIPTS_built= \
    && make install DESTDIR=/output SCRIPTS_built= \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
