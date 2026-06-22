# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG EXT_VERSION=3.1.1

# Stage 1: Install cargo-pgrx (PG-independent, cached across PG versions)
FROM rustlang/rust:nightly-bookworm AS pgrx-builder
ARG EXT_VERSION

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install cargo-pgrx --version 0.18.0 --locked

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://gitlab.com/dalibo/postgresql_anonymizer.git /tmp/ext

# Stage 2: Build extension (PG-specific)
FROM rustlang/rust:nightly-bookworm AS builder
ARG PG_MAJOR

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        postgresql-${PG_MAJOR} \
        postgresql-server-dev-${PG_MAJOR} \
        pkg-config libssl-dev libclang-dev clang

COPY --from=pgrx-builder /usr/local/cargo/bin/cargo-pgrx /usr/local/cargo/bin/cargo-pgrx
COPY --from=pgrx-builder /tmp/ext /tmp/ext

RUN cargo pgrx init --pg${PG_MAJOR} /usr/lib/postgresql/${PG_MAJOR}/bin/pg_config

WORKDIR /tmp/ext

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/tmp/ext/target \
    cargo pgrx package --features pg${PG_MAJOR} \
        --pg-config /usr/lib/postgresql/${PG_MAJOR}/bin/pg_config \
    && mkdir -p /output \
    && cp -a target/release/anon-pg${PG_MAJOR}/* /output/ \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
