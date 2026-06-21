# syntax=docker/dockerfile:1
ARG PG_MAJOR=17

FROM rustlang/rust:nightly-bookworm AS builder
ARG PG_MAJOR
ARG EXT_VERSION=3.1.1

# Install PostgreSQL dev packages
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

# Install cargo-pgrx
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo install cargo-pgrx --version 0.18.0 --locked

# Initialize pgrx with system PG
RUN cargo pgrx init --pg${PG_MAJOR} /usr/lib/postgresql/${PG_MAJOR}/bin/pg_config

WORKDIR /tmp/ext

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://gitlab.com/dalibo/postgresql_anonymizer.git .

# Build the extension
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/tmp/ext/target \
    cargo pgrx package --features pg${PG_MAJOR} \
        --pg-config /usr/lib/postgresql/${PG_MAJOR}/bin/pg_config \
    && mkdir -p /output \
    && cp -a target/release/anon-pg${PG_MAJOR}/* /output/ \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

FROM scratch
COPY --from=builder /output/ /
