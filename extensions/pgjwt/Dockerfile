# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=master

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR}

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/michelp/pgjwt.git /tmp/ext

WORKDIR /tmp/ext

# pgjwt is pure SQL -- no compilation, just install SQL and control files.
RUN make install DESTDIR=/output

FROM scratch
COPY --from=builder /output/ /
