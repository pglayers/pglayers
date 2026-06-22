# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}
ARG EXT_VERSION=v1.6.1

# Stage 1: Rust toolchain + cargo-pgrx (PG-independent, cached across PG versions)
FROM debian:bookworm AS rust-builder
ARG EXT_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates pkg-config \
    libssl-dev libclang-dev curl

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . /root/.cargo/env && rustup default stable

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/supabase/pg_graphql.git /tmp/ext

WORKDIR /tmp/ext

RUN . /root/.cargo/env \
    && cargo install cargo-pgrx --version "$(grep '^pgrx' Cargo.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')" --locked

# Stage 2: Build extension (PG-specific)
FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    libssl-dev libclang-dev

COPY --from=rust-builder /root/.cargo /root/.cargo
COPY --from=rust-builder /root/.rustup /root/.rustup
COPY --from=rust-builder /tmp/ext /tmp/ext

WORKDIR /tmp/ext

RUN . /root/.cargo/env \
    && cargo pgrx init "--pg${PG_MAJOR}=$(which pg_config)" \
    && cargo pgrx package --pg-config "$(which pg_config)" --features "pg${PG_MAJOR}" \
    && cp -r target/release/pg_graphql-pg${PG_MAJOR}/* /output/ \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
