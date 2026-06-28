# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v0.3.3

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    cmake zlib1g-dev curl ruby

# Clone with submodules (bundles protobuf source in third_party/)
RUN git clone --branch ${EXT_VERSION} --recurse-submodules \
    https://github.com/mpartel/postgres-protobuf.git /tmp/ext

WORKDIR /tmp/ext

# Build bundled protobuf library, then build the extension.
RUN ./build-protobuf-library.sh \
    && make -j"$(nproc)" && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \; \
    && rm -rf /output/usr/share/doc

FROM scratch
COPY --from=builder /output/ /
