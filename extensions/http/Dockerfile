# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.7.1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libcurl4-gnutls-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/pramsey/pgsql-http.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
