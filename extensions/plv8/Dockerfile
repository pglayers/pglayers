# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v3.2.4

# Stage 1: V8 engine (PG-independent, ~10 min natively)
#
# In CI, this stage is fully cached via the pre-built multi-arch image
# ghcr.io/pglayers/plv8-v8:<version> (built by build-plv8-v8.yml on
# native amd64/arm64 runners). BuildKit skips compilation entirely.
#
# For local builds, V8 compiles from source on the first run (~10 min)
# and is cached by BuildKit for subsequent builds.
FROM debian:bookworm AS v8-builder
ARG EXT_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    python3 ninja-build cmake pkg-config \
    libc++-dev libc++abi-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 --recurse-submodules \
    https://github.com/plv8/plv8.git /tmp/ext

WORKDIR /tmp/ext
RUN make v8

# Stage 2: Build plv8 extension (PG-specific, ~30 sec)
FROM postgres:${PG_TAG}-bookworm AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    postgresql-server-dev-${PG_MAJOR} \
    libc++-dev libc++abi-dev

COPY --from=v8-builder /tmp/ext /tmp/ext
WORKDIR /tmp/ext

RUN make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
