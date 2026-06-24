# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG PG_TAG=${PG_MAJOR}

FROM postgres:${PG_TAG} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v3.1.11
ARG LIBSODIUM_VERSION=1.0.22

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates curl \
    postgresql-server-dev-${PG_MAJOR}

# Build libsodium from source (distro version too old for pgsodium 3.1.11+)
RUN curl -fsSL "https://download.libsodium.org/libsodium/releases/libsodium-${LIBSODIUM_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/libsodium-${LIBSODIUM_VERSION} \
    && ./configure --prefix=/usr && make -j"$(nproc)" && make install

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/michelp/pgsodium.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" && make install DESTDIR=/output \
    && find /output -name '*.so' -exec strip --strip-unneeded {} \;

# Bundle libsodium runtime library (not in base postgres image)
RUN cp /usr/lib/libsodium.so* /output/usr/lib/

# Install default getkey script (generates a random root key in $PGDATA)
RUN install -m 755 /dev/stdin \
    /output/usr/share/postgresql/${PG_MAJOR}/extension/pgsodium_getkey <<'SCRIPT'
#!/bin/bash
KEY_FILE=$PGDATA/pgsodium_root.key
if [ ! -f "$KEY_FILE" ]; then
    head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "$KEY_FILE"
fi
cat "$KEY_FILE"
SCRIPT

FROM scratch
COPY --from=builder /output/ /
