# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

# Build on Bookworm (older C++ stdlib compatible with V8 v6.4)
# The resulting .so is still loadable on Trixie (libc is backward compatible)
FROM postgres:${PG_TAG}-bookworm AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v3.2.4

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    python3 ninja-build cmake pkg-config \
    libc++-dev libc++abi-dev

RUN git clone --branch ${EXT_VERSION} --depth 1 --recurse-submodules \
    https://github.com/plv8/plv8.git /tmp/ext

WORKDIR /tmp/ext

# Build V8 then plv8 (takes ~10 min)
RUN make v8 \
    && make -j"$(nproc)" \
    && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
