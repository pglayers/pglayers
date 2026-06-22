# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.3.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR}

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/theory/pgtap.git /tmp/ext

WORKDIR /tmp/ext

# pgTAP is pure SQL -- make install just copies SQL and control files.
RUN make && make install DESTDIR=/output

FROM scratch
COPY --from=builder /output/ /
