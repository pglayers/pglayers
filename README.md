# postgres-extender

Composable PostgreSQL extension layers for Docker. Pick the extensions you
need, add a `COPY --from` line per extension, and get a ready-to-use image
in seconds -- no compilation, no build tools, no waiting.

Each extension is pre-built and published as a minimal Docker image
containing only the extension binaries (`.so`, `.sql`, `.control` files).
You compose them on top of the
[official `postgres` image](https://hub.docker.com/_/postgres) using
standard Docker multi-stage `COPY --from` instructions.

## Quick start

Create a `Dockerfile`:

```dockerfile
FROM postgres:17

COPY --from=ghcr.io/iemejia/pgx-pgvector:17  / /
COPY --from=ghcr.io/iemejia/pgx-pg_cron:17   / /
COPY --from=ghcr.io/iemejia/pgx-postgis:17   / /
```

Build and run:

```bash
docker build -t my-postgres .
docker run -d -e POSTGRES_PASSWORD=secret my-postgres
```

That's it. No compilation happens -- Docker pulls the pre-built extension
layers from the registry and overlays them onto the official image.

## Available extensions

| Extension | PG versions | Description |
|-----------|-------------|-------------|
| [pgvector](https://github.com/pgvector/pgvector) | 17, 18 | Open-source vector similarity search |
| [pg_cron](https://github.com/citusdata/pg_cron) | 17, 18 | Job scheduler (run periodic jobs inside the database) |
| [PostGIS](https://github.com/postgis/postgis) | 17, 18 | Geospatial extensions (geometry, geography, MVT) |
| [pg_repack](https://github.com/reorg/pg_repack) | 17, 18 | Online table reorganization without heavy locks |
| [pgaudit](https://github.com/pgaudit/pgaudit) | 17, 18 | Audit logging (session and object-level) |
| [pg_partman](https://github.com/pgpartman/pg_partman) | 17, 18 | Automated table partition management |

### Image tags

Each extension is published with two tag formats:

- `pgx-<extension>:<pg_major>` -- latest build (e.g. `pgx-pgvector:17`)
- `pgx-<extension>:<pg_major>-<version>` -- pinned version (e.g. `pgx-pgvector:17-v0.8.3`)

All images are hosted on GHCR at `ghcr.io/iemejia/pgx-*`.

## Configuration notes

### shared_preload_libraries

Some extensions require entries in `shared_preload_libraries`. Add this to
your Dockerfile after the `COPY` lines:

```dockerfile
RUN echo "shared_preload_libraries = 'pg_cron,pgaudit,pg_partman_bgw'" \
    >> /usr/share/postgresql/postgresql.conf.sample
```

Extensions that need this:

| Extension | Library name |
|-----------|-------------|
| pg_cron | `pg_cron` |
| pgaudit | `pgaudit` |
| pg_partman | `pg_partman_bgw` |

### CREATE EXTENSION

Extensions must be created in each database where you want to use them.
You can automate this with an init script:

```dockerfile
COPY <<'EOF' /docker-entrypoint-initdb.d/10-extensions.sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS postgis;
EOF
```

This runs automatically on first container start (when the data directory
is initialized).

### PostGIS

The PostGIS extension image bundles its runtime shared libraries (libgeos,
libproj, libjson-c, libprotobuf-c, and PROJ data files), so
`COPY --from` is fully self-contained. It is built **without raster
support** to avoid the large GDAL dependency. Geometry, geography,
topology, and MVT (Mapbox Vector Tiles) are all included.

## How it works

The project publishes one Docker image per extension per PostgreSQL
version. These are not runnable containers -- they are `FROM scratch`
images containing only the compiled extension artifacts laid out at the
correct filesystem paths:

```
/usr/lib/postgresql/17/lib/vector.so
/usr/share/postgresql/17/extension/vector.control
/usr/share/postgresql/17/extension/vector--0.8.3.sql
```

When you write `COPY --from=ghcr.io/iemejia/pgx-pgvector:17 / /` in
your Dockerfile, Docker copies these files into the official `postgres`
image at exactly the right locations. PostgreSQL finds them and you can
`CREATE EXTENSION`.

## Building locally

### Prerequisites

- Docker (with BuildKit)
- GNU Make
- Bash

### Commands

```bash
# List available extensions
make list

# Build a single extension
make build EXT=pgvector PG=17

# Build all extensions for a PG version
make build-all PG=17

# Show extension details
make info EXT=pg_cron

# Push to registry
make push EXT=pgvector PG=17

# Override the registry
make build EXT=pgvector PG=17 REGISTRY=ghcr.io/myorg
```

## Adding a new extension

1. Create `extensions/<name>/Dockerfile`:

```dockerfile
ARG PG_MAJOR=17

FROM postgres:${PG_MAJOR} AS builder
ARG PG_MAJOR
ARG EXT_VERSION=v1.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    postgresql-server-dev-${PG_MAJOR} \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch ${EXT_VERSION} --depth 1 \
    https://github.com/org/extension.git /tmp/ext

WORKDIR /tmp/ext

RUN make -j"$(nproc)" && make install DESTDIR=/output

FROM scratch
COPY --from=builder /output/ /
```

2. Create `extensions/<name>/extension.conf`:

```bash
DESCRIPTION="Short description of the extension"
REPO="https://github.com/org/extension.git"
VERSION_17="v1.0.0"
VERSION_18="v1.0.0"
SHARED_PRELOAD=""
NOTES=""
```

3. Test locally: `make build EXT=<name> PG=17`

4. Submit a pull request.

If the extension has runtime shared library dependencies (like PostGIS),
bundle them in the Dockerfile -- see `extensions/postgis/Dockerfile` for
the pattern.

## Project structure

```
postgres-extender/
├── Makefile                          Build interface
├── .github/workflows/build-push.yml  CI: builds all extensions, pushes to GHCR
├── extensions/
│   ├── pgvector/
│   │   ├── Dockerfile                Multi-stage build → artifact image
│   │   └── extension.conf            Metadata and version mapping
│   ├── pg_cron/
│   ├── postgis/
│   ├── pg_repack/
│   ├── pgaudit/
│   └── pg_partman/
└── examples/
    └── Dockerfile.example            End-user reference
```

## License

[MIT](LICENSE)
