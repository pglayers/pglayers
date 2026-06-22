# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v2.0.5

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libsybdb5 freetds-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/tds-fdw/tds_fdw.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" USE_PGXS=1 && make install USE_PGXS=1 DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle FreeTDS runtime library
RUN set -eux; \
    MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"; \
    LIBDIR="/usr/lib/${MULTIARCH}"; \
    mkdir -p /output${LIBDIR}; \
    cp -a ${LIBDIR}/libsybdb.so* /output${LIBDIR}/; \
    cp -a ${LIBDIR}/libct.so* /output${LIBDIR}/ 2>/dev/null || true; \
    # FreeTDS config
    mkdir -p /output/etc; \
    cp -a /etc/freetds /output/etc/ 2>/dev/null || true

FROM scratch
COPY --from=builder /output/ /
