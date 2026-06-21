# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=3.6.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl \
    postgresql-server-dev-${PG_MAJOR} \
    libgeos-dev libproj-dev libjson-c-dev libxml2-dev \
    libprotobuf-c-dev protobuf-c-compiler \
    libtiff-dev libcurl4-gnutls-dev \
    pkg-config dpkg-dev

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
    # Find every shared lib our .so files link against (resolve symlinks
    # so we always get /usr/lib/... paths, never /lib/... which is a
    # symlink on modern Debian and would conflict with the base image).
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u | while read -r lib; do \
        canonical="$(readlink -f "$lib")"; \
        echo "$canonical"; \
    done | sort -u > /tmp/all-deps.txt; \
    # Resolve base image lib paths the same way
    sed 's|.*|readlink -f "&" 2>/dev/null|' /tmp/base-libs.txt | sh | sort -u > /tmp/base-resolved.txt; \
    # Subtract libs already in the base image
    comm -23 /tmp/all-deps.txt /tmp/base-resolved.txt > /tmp/new-deps.txt; \
    # Copy each new lib and its symlink family to canonical paths
    while read -r lib; do \
        [ -f "$lib" ] || continue; \
        dir="$(dirname "$lib")"; \
        mkdir -p "/runtime${dir}"; \
        base="$(echo "$lib" | sed 's/\.so.*/.so/')"; \
        for f in "${base}"*; do \
            [ -e "$f" ] || continue; \
            target="$(readlink -f "$f")"; \
            tdir="$(dirname "$target")"; \
            mkdir -p "/runtime${tdir}"; \
            cp -a "$target" "/runtime${target}" 2>/dev/null || true; \
            # Recreate symlink if it was one
            if [ -L "$f" ]; then \
                fname="$(basename "$f")"; \
                fdir="$(cd "$(dirname "$f")" && pwd -P)"; \
                mkdir -p "/runtime${fdir}"; \
                ln -sf "$(basename "$target")" "/runtime${fdir}/${fname}" 2>/dev/null || true; \
            fi; \
        done; \
    done < /tmp/new-deps.txt; \
    # PROJ data files needed for coordinate reference system transforms
    if [ -d /usr/share/proj ]; then \
        mkdir -p /runtime/usr/share; \
        cp -r /usr/share/proj /runtime/usr/share/; \
    fi

FROM scratch
COPY --from=builder /output/ /
COPY --from=deps /runtime/ /
