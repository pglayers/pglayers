# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic
ARG EXT_VERSION=v1.1.1

# Use official pre-built pg_duckdb image (avoids 10-15 min DuckDB compilation).
FROM pgduckdb/pgduckdb:${PG_MAJOR}-${EXT_VERSION} AS upstream

# Snapshot base image libraries for diffing (by soname, not canonical path)
FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

# Collector: extract extension + bundle missing runtime deps
FROM upstream AS collector
ARG PG_MAJOR
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt

USER root

# Copy extension artifacts to /output
RUN set -eux; \
    PG=${PG_MAJOR}; \
    mkdir -p /output/usr/lib/postgresql/${PG}/lib/bitcode \
             /output/usr/share/postgresql/${PG}/extension; \
    cp /usr/lib/postgresql/${PG}/lib/libduckdb.so /output/usr/lib/postgresql/${PG}/lib/; \
    cp /usr/lib/postgresql/${PG}/lib/pg_duckdb.so /output/usr/lib/postgresql/${PG}/lib/; \
    cp /usr/lib/postgresql/${PG}/lib/bitcode/pg_duckdb.index.bc /output/usr/lib/postgresql/${PG}/lib/bitcode/; \
    cp -r /usr/lib/postgresql/${PG}/lib/bitcode/pg_duckdb /output/usr/lib/postgresql/${PG}/lib/bitcode/; \
    cp /usr/share/postgresql/${PG}/extension/pg_duckdb* /output/usr/share/postgresql/${PG}/extension/

# Bundle runtime shared libraries that pg_duckdb needs but the base
# postgres image doesn't have (compare by soname to avoid bundling
# older versions of libs already present in the base image).
# Exclude libcurl and its deps -- these are provided by the http/postgis
# layers which install from the same OS as the combined image.
RUN set -eux; \
    PG=${PG_MAJOR}; \
    # Collect all ldd-reported paths from extension .so files
    ldd /usr/lib/postgresql/${PG}/lib/pg_duckdb.so \
        /usr/lib/postgresql/${PG}/lib/libduckdb.so 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    # Libraries provided by other extension layers (http, postgis);
    # skip these to avoid version conflicts in the combined image.
    printf '%s\n' \
        libcurl.so.4 libbrotlicommon.so.1 libbrotlidec.so.1 \
        libnghttp2.so.14 libpsl.so.5 librtmp.so.1 libssh2.so.1 \
        > /tmp/skip-libs.txt; \
    # Copy each dep whose soname is not already in the base image
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        if grep -qxF "$soname" /tmp/skip-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output${dest}" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

# --- Layout selection ---
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=collector /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible)
FROM collector AS normalizer
ARG PG_MAJOR
RUN mkdir -p /isolated/lib /isolated/share/extension && \
    # Extension .so files
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; && \
    # Control + SQL files
    cp -a /output/usr/share/postgresql/${PG_MAJOR}/extension/* \
        /isolated/share/extension/ && \
    # Bundled runtime deps (system libs not in base image)
    find /output/usr/lib -name '*.so*' ! -path '*/postgresql/*' \
        \( -type f -o -type l \) -exec cp -a {} /isolated/lib/ \; && \
    # Bitcode (optional, for JIT)
    cp -a /output/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
