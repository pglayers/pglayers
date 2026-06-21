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
| [pgvector](https://github.com/pgvector/pgvector) | 17, 18 | Vector similarity search for AI/embeddings |
| [pg_cron](https://github.com/citusdata/pg_cron) | 17, 18 | Job scheduler (periodic jobs inside the database) |
| [PostGIS](https://github.com/postgis/postgis) | 17, 18 | Geospatial extensions (geometry, geography, MVT) |
| [pg_repack](https://github.com/reorg/pg_repack) | 17, 18 | Online table reorganization without heavy locks |
| [pgaudit](https://github.com/pgaudit/pgaudit) | 17, 18 | Audit logging (session and object-level) |
| [pg_partman](https://github.com/pgpartman/pg_partman) | 17, 18 | Automated table partition management |
| [wal2json](https://github.com/eulerto/wal2json) | 17, 18 | JSON output plugin for logical replication / CDC |
| [pg_hint_plan](https://github.com/ossc-db/pg_hint_plan) | 17, 18 | Tweak execution plans using hints in SQL comments |
| [hypopg](https://github.com/HypoPG/hypopg) | 17, 18 | Hypothetical indexes for what-if analysis |
| [hll](https://github.com/citusdata/postgresql-hll) | 17, 18 | HyperLogLog probabilistic distinct counting |
| [orafce](https://github.com/orafce/orafce) | 17, 18 | Oracle compatibility functions and packages |
| [topn](https://github.com/citusdata/postgresql-topn) | 17, 18 | Top-N values aggregation |
| [tdigest](https://github.com/tvondra/tdigest) | 17, 18 | T-digest for quantile and percentile estimation |
| [ip4r](https://github.com/RhodiumToad/ip4r) | 17, 18 | IPv4/IPv6 range data types with GiST indexing |
| [semver](https://github.com/theory/pg-semver) | 17, 18 | Semantic version data type |
| [temporal_tables](https://github.com/arkhipov/temporal_tables) | 17, 18 | System-period temporal tables |
| [pg_squeeze](https://github.com/cybertec-postgresql/pg_squeeze) | 17, 18 | Remove unused space from tables without heavy locks |
| [pg_ivm](https://github.com/sraoss/pg_ivm) | 17, 18 | Incremental View Maintenance for materialized views |
| [credcheck](https://github.com/HexaCluster/credcheck) | 17, 18 | Credential checks on user creation / password change |
| [pg_failover_slots](https://github.com/EnterpriseDB/pg_failover_slots) | 17, 18 | Logical replication slot manager for failover |

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
| pg_hint_plan | `pg_hint_plan` |
| pg_squeeze | `pg_squeeze` |
| credcheck | `credcheck` |
| pg_failover_slots | `pg_failover_slots` |

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

### Build commands

```bash
# List available extensions with descriptions and PG versions
make list

# Build a single extension for a specific PG version
make build EXT=pgvector PG=17

# Build all extensions for a PG version
make build-all PG=17

# Show detailed info for an extension (versions, notes, preload reqs)
make info EXT=pg_cron

# Push a built extension image to the registry
make push EXT=pgvector PG=17

# Push all extensions
make push-all PG=17

# Override the default registry
make build EXT=pgvector PG=17 REGISTRY=ghcr.io/myorg

# Print the Dockerfile for an extension (useful for debugging)
make dockerfile EXT=pgvector
```

### Running the test suite

The test suite validates that all extensions can coexist without
conflicts. **Always run tests before submitting changes:**

```bash
# Run the full test suite (builds all extensions, checks collisions,
# validates shared libraries, runs functional tests)
make test REGISTRY=local PG=17
```

The tests check:

1. **No file collisions** -- Every pair of extensions is compared for
   overlapping files. If two extensions install a file at the same path,
   the last `COPY --from` silently overwrites the first. Docker gives
   zero warning about this, but it can break extensions at runtime.

2. **No base image overwrites** -- Extensions must not replace files
   from the official `postgres:XX` image.

3. **Shared library dependencies** -- `ldd` is run on every `.so` in
   the combined image to catch missing transitive dependencies.

4. **CREATE EXTENSION** -- Every extension loads successfully in the
   combined image.

5. **Functional smoke tests** -- Each extension is exercised with a
   real query (not just loaded) to verify runtime behavior.

Example output:

```
---- Phase 3: Checking for file collisions between extensions...
PASS pgvector <-> postgis: no collisions
PASS pgvector <-> pg_cron: no collisions
...
PASS No file collisions detected between any extension pair

---- Phase 5: Building combined image and checking shared libraries...
PASS All shared library dependencies resolve

---- Phase 6: Functional tests...
PASS CREATE EXTENSION vector
PASS smoke: pgvector similarity
...
========================================
Results: 252 passed, 0 failed, 0 warnings
========================================
```

## Contributing a new extension

### Before you start

1. **Check the license.** We only ship extensions with permissive
   open-source licenses (PostgreSQL, MIT, BSD, Apache 2.0, ISC).
   Copyleft (GPL, AGPL) and source-available (BSL, SSPL, ELv2) are
   not accepted. Extensions requiring proprietary runtime dependencies
   (e.g., Oracle Instant Client) are also excluded.

2. **Check for conflicts.** If your extension bundles runtime shared
   libraries, verify they don't overlap with existing extensions
   (especially PostGIS, which bundles libgeos, libproj, etc.).

### Step 1: Create the extension definition

Create `extensions/<name>/Dockerfile`:

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

Create `extensions/<name>/extension.conf`:

```bash
DESCRIPTION="Short description of the extension"
REPO="https://github.com/org/extension.git"
LICENSE="PostgreSQL"
VERSION_17="v1.0.0"
VERSION_18="v1.0.0"
SHARED_PRELOAD=""
NOTES=""
```

### Step 2: Build and verify locally

```bash
# Build the extension image
make build EXT=<name> PG=17 REGISTRY=local

# Run the full test suite (collision detection + functional tests)
make test REGISTRY=local PG=17
```

### Step 3: Add test coverage

Edit `tests/test-layers.sh`:

1. **Name mapping** (if SQL name differs from directory name):
   ```bash
   # In the EXT_SQL_NAMES array:
   [my_ext]="my_extension"
   ```

2. **Skip CREATE EXTENSION** (if it's an output plugin, not a regular
   extension):
   ```bash
   # In the SKIP_CREATE_EXT array:
   [my_ext]=1
   ```

3. **Add a smoke test** that exercises the extension's functionality:
   ```bash
   smoke_test "my_ext basic operation" \
       "SELECT my_ext_function('test');"
   ```
   The smoke test must return non-empty output on success.

4. **Add shared_preload_libraries** (if needed) to the test Dockerfile
   generator in Phase 5.

### Step 4: Handle runtime dependencies

If the extension links against shared libraries not in the base
`postgres` image (check with `ldd`):

- **Option A (preferred):** Bundle the runtime `.so` files in the
  extension image. See `extensions/postgis/Dockerfile` for the pattern
  using `ldd` + base image diffing.

- **Option B:** Document the runtime deps in `NOTES` if they can't
  reasonably be bundled.

Common gotchas:

- The `gssapi/gssapi.h` header requires `libkrb5-dev` at build time.
- PostgreSQL 18's PGXS links against `libnuma` -- add `libnuma-dev`.
- Extensions using `flex`/`bison` scanners need those as build deps.
- Avoid `/lib` paths in artifact images (Debian's `/lib -> /usr/lib`
  symlink causes COPY conflicts with the base image).

### Step 5: Submit

```bash
# Verify everything passes
make test REGISTRY=local PG=17

# Commit and open a PR
git add extensions/<name>/ tests/test-layers.sh
git commit -m "Add <name> extension"
```

## Project structure

```
postgres-extender/
├── Makefile                          Build interface
├── Dockerfile                        Combined image (all extensions)
├── AGENTS.md                         Agent/CI instructions
├── .github/workflows/build-push.yml  CI: builds all extensions, pushes to GHCR
├── extensions/
│   ├── pgvector/
│   │   ├── Dockerfile                Multi-stage build -> artifact image
│   │   └── extension.conf            Metadata and version mapping
│   ├── pg_cron/
│   ├── postgis/                      (complex: bundles runtime libs)
│   ├── ... (20 extensions total)
│   └── wal2json/
├── tests/
│   └── test-layers.sh                Collision + functional test suite
└── examples/
    └── Dockerfile.example            End-user reference
```

## Licensing policy

This project only ships extensions with **permissive open-source
licenses** (PostgreSQL, MIT, BSD, Apache 2.0, ISC).

### Why no GPL/copyleft extensions?

You might notice that some managed PostgreSQL services (like Azure
Database for PostgreSQL) offer GPL-licensed extensions such as
`login_hook` or `session_variable`. We deliberately exclude these.
The reason is that our legal situation is different from a cloud
provider's:

- **Cloud services (SaaS)** run GPL code on their own servers. Users
  access it over a network but never receive a copy of the binary.
  Under the GPL, this does not count as "distribution," so the
  copyleft source-sharing obligation is never triggered.

- **Docker images (us)** are distributed to users. When you pull or
  `COPY --from` an extension layer, you receive a compiled `.so` file.
  This IS distribution under the GPL, which means:
  - The GPL license terms apply to anyone who receives the binary.
  - Whether a dynamically-loaded PostgreSQL extension constitutes a
    "combined work" with other extensions in the same image is legally
    ambiguous.
  - Users who compose a GPL extension layer with proprietary code or
    other non-GPL-compatible extensions may unknowingly create
    compliance issues.

We take a conservative approach to protect end users: by shipping only
permissively-licensed extensions, you can freely compose any combination
of layers without worrying about license interactions. You can use the
resulting image in proprietary projects, embed it in commercial products,
or distribute it to customers -- no copyleft obligations attached.

### What this means in practice

| License | Included? | Examples |
|---------|-----------|----------|
| PostgreSQL, MIT, BSD, Apache 2.0, ISC | Yes | pgvector, pg_cron, PostGIS, pgaudit |
| GPL-2.0 (with PostgreSQL linking exception) | Case by case | PostGIS (has linking exception) |
| GPL-3.0 | No | login_hook, session_variable |
| AGPL-3.0 | No | -- |
| BSL, SSPL, ELv2, FSL | No | -- |
| Requires proprietary deps | No | oracle_fdw (Oracle Instant Client) |

## License

[MIT](LICENSE)
