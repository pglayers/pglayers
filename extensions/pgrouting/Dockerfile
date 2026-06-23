# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v4.0.1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates curl \
    postgresql-server-dev-${PG_MAJOR} \
    cmake libboost-graph-dev \
    libgeos-dev libproj-dev libjson-c-dev libxml2-dev \
    libprotobuf-c-dev protobuf-c-compiler \
    libtiff-dev libcurl4-gnutls-dev

# PostGIS is a build dependency (pgrouting needs PostGIS headers)
# Install PostGIS from source first (serial build: parallel make has
# race conditions with --without-raster on upgrade SQL generation)
ARG POSTGIS_VERSION=3.6.4
RUN curl -fsSL "https://download.osgeo.org/postgis/source/postgis-${POSTGIS_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/postgis-${POSTGIS_VERSION} \
    && ./configure --without-raster --without-sfcgal \
    && make \
    && make install

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/pgRouting/pgrouting.git /tmp/ext

WORKDIR /tmp/ext/build

RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DWITH_DOC=OFF \
    -DBUILD_DOXY=OFF \
    .. \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
