# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    postgresql-${PG_MAJOR}-repack

# Extract extension files (exclude headers and docs)
RUN mkdir -p /output && \
    dpkg -L postgresql-${PG_MAJOR}-repack \
    | grep -E '^/usr/(lib|share)/postgresql/' \
    | while IFS= read -r f; do \
        [ -f "$f" ] || continue; \
        mkdir -p "/output$(dirname "$f")"; \
        cp -a "$f" "/output$f"; \
    done

FROM scratch
COPY --from=builder /output/ /
