ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=17.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/pgaudit/pgaudit.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" USE_PGXS=1 && make install USE_PGXS=1 DESTDIR=/output

FROM scratch
COPY --from=builder /output/ /
