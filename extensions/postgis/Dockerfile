ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=3.6.4

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl \
    postgresql-server-dev-${PG_MAJOR} \
    libgeos-dev libproj-dev libjson-c-dev libxml2-dev \
    libprotobuf-c-dev protobuf-c-compiler \
    pkg-config dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Use the release tarball (includes pre-generated configure script,
# no autotools needed).
RUN curl -fsSL "https://download.osgeo.org/postgis/source/postgis-${EXT_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && mv /tmp/postgis-${EXT_VERSION} /tmp/ext

WORKDIR /tmp/ext

# Build without raster (avoids the massive GDAL dependency).
# Topology and MVT (protobuf) support are included.
RUN ./configure --without-raster --without-sfcgal \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output

# Bundle runtime shared libraries that PostGIS depends on but are
# NOT part of the base postgres image.  We copy them from this same
# builder stage (which installed the -dev packages) so the library
# names are resolved automatically regardless of Debian release.
RUN set -eux; \
    MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)"; \
    LIBDIR="/usr/lib/${MULTIARCH}"; \
    mkdir -p /runtime${LIBDIR}; \
    for pattern in \
        "libgeos*.so*" \
        "libproj.so*" \
        "libjson-c.so*" \
        "libprotobuf-c.so*" \
    ; do \
        cp -a ${LIBDIR}/${pattern} /runtime${LIBDIR}/ 2>/dev/null || true; \
    done; \
    # PROJ data files needed for coordinate reference system transforms
    if [ -d /usr/share/proj ]; then \
        mkdir -p /runtime/usr/share; \
        cp -r /usr/share/proj /runtime/usr/share/; \
    fi

FROM scratch
COPY --from=builder /output/ /
COPY --from=builder /runtime/ /
