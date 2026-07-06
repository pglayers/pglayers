# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG LAYOUT=classic

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    postgresql-${PG_MAJOR}-roaringbitmap

# Extract extension files (exclude headers and docs)
RUN mkdir -p /output && \
    dpkg -L postgresql-${PG_MAJOR}-roaringbitmap \
    | grep -E '^/usr/(lib|share)/postgresql/' \
    | while IFS= read -r f; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done

# --- Layout selection ---
# Classic: files at standard PG paths (PG 17)
FROM scratch AS classic
COPY --from=builder /output/ /

# Isolated: flat /lib/ + /share/extension/ layout (PG 18+, CNPG-compatible)
FROM builder AS normalizer
ARG PG_MAJOR
RUN mkdir -p /isolated/lib /isolated/share/extension && \
    find /output/usr/lib/postgresql/${PG_MAJOR}/lib -maxdepth 1 -type f \
        -exec cp -a {} /isolated/lib/ \; && \
    cp -a /output/usr/share/postgresql/${PG_MAJOR}/extension/* \
        /isolated/share/extension/ && \
    cp -a /output/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode /isolated/lib/bitcode \
        2>/dev/null || true

FROM scratch AS isolated
COPY --from=normalizer /isolated/ /

FROM ${LAYOUT}
