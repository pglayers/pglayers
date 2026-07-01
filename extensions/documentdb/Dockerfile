# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v0.113-0

FROM postgres:${PG_TAG} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION
ARG TARGETARCH

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates

# Download DocumentDB deb from GitHub releases.
# Tag format: v0.113-0 -> deb version: 0.113-0
RUN DEB_VERSION="${EXT_VERSION#v}" && \
    curl -fsSL -o /tmp/documentdb.deb \
    "https://github.com/documentdb/documentdb/releases/download/${EXT_VERSION}/deb12-postgresql-${PG_MAJOR}-documentdb_${DEB_VERSION}_${TARGETARCH}.deb"

# Extract deb contents without installing (avoids dependency resolution)
RUN mkdir -p /extracted && dpkg-deb -x /tmp/documentdb.deb /extracted

# Copy only PostgreSQL extension files to output
RUN mkdir -p /output && \
    find /extracted/usr/lib/postgresql/ /extracted/usr/share/postgresql/ \
        -type f 2>/dev/null \
    | while IFS= read -r f; do \
        dest="${f#/extracted}"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -a "$f" "/output$dest"; \
    done

# Bundle runtime shared libraries not in the base postgres image
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
        | awk '/=>/ && /\// {print $3}' | sort -u > /tmp/all-deps.txt; \
    while IFS= read -r lib; do \
        soname="$(basename "$lib")"; \
        if grep -qxF "$soname" /tmp/base-libs.txt 2>/dev/null; then \
            continue; \
        fi; \
        dest="$(echo "$lib" | sed 's|^/lib/|/usr/lib/|')"; \
        mkdir -p "/output$(dirname "$dest")"; \
        cp -aL "$lib" "/output$dest" 2>/dev/null || true; \
    done < /tmp/all-deps.txt

FROM scratch
COPY --from=builder /output/ /
