# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS base
RUN find /usr/lib -name '*.so*' \( -type f -o -type l \) 2>/dev/null \
    | sed 's|.*/||' | sort -u > /tmp/base-libs.txt

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    postgresql-${PG_MAJOR}-pgrouting

# Extract extension files from all installed PG packages (includes -scripts)
RUN mkdir -p /output && \
    dpkg -l "postgresql-${PG_MAJOR}-pgrouting*" 2>/dev/null \
    | awk '/^ii/ {print $2}' \
    | xargs -I{} dpkg -L {} \
    | grep -E '^/usr/(lib|share)/postgresql/' \
    | sort -u \
    | while IFS= read -r f; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done

# Bundle runtime shared libraries not in the base postgres image
COPY --from=base /tmp/base-libs.txt /tmp/base-libs.txt
RUN set -eux; \
    PG=${PG_MAJOR}; \
    find /output/usr/lib/postgresql/${PG}/lib -name '*.so' -exec ldd {} + 2>/dev/null \
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
