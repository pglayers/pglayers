# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=3.6.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl \
    postgresql-server-dev-${PG_MAJOR} \
    libgeos-dev libproj-dev libgdal-dev \
    libjson-c-dev libxml2-dev \
    libprotobuf-c-dev protobuf-c-compiler \
    libtiff-dev libcurl4-openssl-dev \
    pkg-config dpkg-dev

# Use the release tarball (includes pre-generated configure script,
# no autotools needed).
RUN curl -fsSL "https://download.osgeo.org/postgis/source/postgis-${EXT_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && mv /tmp/postgis-${EXT_VERSION} /tmp/ext

WORKDIR /tmp/ext

# Build with raster support (uses distro GDAL).
# Topology and MVT (protobuf) support are included.
RUN ./configure --without-sfcgal \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Snapshot the base postgres image's shared libraries so we can diff later.
FROM postgres:${PG_MAJOR} AS base
RUN find /usr/lib -name '*.so*' -type f -o -name '*.so*' -type l 2>/dev/null | sort > /tmp/base-libs.txt

# Collect only the runtime shared libraries PostGIS needs that are NOT
# already in the base postgres image.  Uses ldd on every built .so to
# find the full transitive dependency closure, then subtracts what the
# base image already provides.
FROM builder AS deps
ARG PG_MAJOR
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    mkdir -p /runtime; \
    # Collect all ldd-reported paths from PostGIS .so files
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-ldd-paths.txt; \
    # Build resolved base image set for comparison
    while IFS= read -r lib; do \
        readlink -f "$lib" 2>/dev/null; \
    done < /tmp/base-libs.txt | sort -u > /tmp/base-resolved.txt; \
    # Normalize a path: /lib/... -> /usr/lib/... (Debian compat)
    norm() { echo "$1" | sed 's|^/lib/|/usr/lib/|'; }; \
    # Copy each dep that's not already in the base image.
    # Use the ldd-reported path (preserves alternatives symlink names
    # like libblas.so.3) and dereference to get actual file content.
    while IFS= read -r lib; do \
        canonical="$(readlink -f "$lib")"; \
        # Skip if the canonical target is in the base image
        if grep -qxF "$canonical" /tmp/base-resolved.txt 2>/dev/null; then \
            continue; \
        fi; \
        # Normalize path to avoid /lib vs /usr/lib conflicts
        dest="$(norm "$lib")"; \
        dir="$(dirname "$dest")"; \
        mkdir -p "/runtime${dir}"; \
        cp -L "$lib" "/runtime${dest}" 2>/dev/null || true; \
    done < /tmp/all-ldd-paths.txt; \
    # Second pass: also resolve deps of the libs we just bundled
    # (catches transitive deps like libblas via libgdal).
    find /runtime -name '*.so*' -type f -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/pass2-paths.txt; \
    while IFS= read -r lib; do \
        dest="$(norm "$lib")"; \
        # Skip if already bundled
        [ -f "/runtime${dest}" ] && continue; \
        canonical="$(readlink -f "$lib")"; \
        # Skip if in base image
        if grep -qxF "$canonical" /tmp/base-resolved.txt 2>/dev/null; then \
            continue; \
        fi; \
        dir="$(dirname "$dest")"; \
        mkdir -p "/runtime${dir}"; \
        cp -L "$lib" "/runtime${dest}" 2>/dev/null || true; \
    done < /tmp/pass2-paths.txt; \
    # PROJ data files needed for coordinate reference system transforms
    if [ -d /usr/share/proj ]; then \
        mkdir -p /runtime/usr/share; \
        cp -r /usr/share/proj /runtime/usr/share/; \
    fi; \
    # GDAL data files needed for raster format detection and SRS
    if [ -d /usr/share/gdal ]; then \
        mkdir -p /runtime/usr/share; \
        cp -r /usr/share/gdal /runtime/usr/share/; \
    fi

FROM scratch
COPY --from=builder /output/ /
COPY --from=deps /runtime/ /
