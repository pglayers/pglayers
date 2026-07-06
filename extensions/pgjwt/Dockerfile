# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic

FROM postgres:${PG_TAG} AS builder
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

# --- Layout selection ---
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=builder /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible)
FROM builder AS normalizer
ARG PG_MAJOR
RUN mkdir -p /isolated/lib /isolated/share/extension && \
    (find /output/usr/lib/postgresql/${PG_MAJOR}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; 2>/dev/null || true) && \
    cp -a /output/usr/share/postgresql/${PG_MAJOR}/extension/* \
        /isolated/share/extension/ && \
    cp -a /output/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
