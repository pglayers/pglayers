# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v3.2.4

# Stage 1: Build V8 engine (PG-independent, ~10 min, cached across PG versions)
# Uses debian:bookworm so the layer cache is shared between PG 17/18/19 builds.
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
