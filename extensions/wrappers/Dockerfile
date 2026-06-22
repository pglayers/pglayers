# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v0.6.2

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates pkg-config \
    postgresql-server-dev-${PG_MAJOR} \
    libssl-dev libclang-dev curl

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . /root/.cargo/env && rustup default stable

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/supabase/wrappers.git /tmp/ext

WORKDIR /tmp/ext/wrappers

# Install matching cargo-pgrx version and build the extension
RUN . /root/.cargo/env \
    && cargo install cargo-pgrx --version "$(grep '^pgrx' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')" --locked \
    && cargo pgrx init "--pg${PG_MAJOR}=$(which pg_config)" \
    && cargo pgrx package --pg-config "$(which pg_config)" --features "pg${PG_MAJOR}" \
    && mkdir -p /output \
    && cp -r target/release/wrappers-pg${PG_MAJOR}/* /output/ \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
