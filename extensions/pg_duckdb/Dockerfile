# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG EXT_VERSION=v1.1.1

# Use official pre-built pg_duckdb image (avoids 10-15 min DuckDB compilation).
FROM pgduckdb/pgduckdb:${PG_MAJOR}-${EXT_VERSION} AS upstream

# Snapshot base image libraries for diffing (by soname, not canonical path)
FROM postgres:${PG_MAJOR} AS base
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
RUN set -eux; \
    PG=${PG_MAJOR}; \
    # Collect all ldd-reported paths from extension .so files
    ldd /usr/lib/postgresql/${PG}/lib/pg_duckdb.so \
        /usr/lib/postgresql/${PG}/lib/libduckdb.so 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    # Copy each dep whose soname is not already in the base image
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output${dest}" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

FROM scratch
COPY --from=collector /output/ /
