# pglayers

The [official PostgreSQL Docker images](https://hub.docker.com/_/postgres)
ship without extensions. Every time you need pgvector, PostGIS, or
pg_cron, you're stuck compiling from source or settling for third-party
images that only include a handful of extensions.

pglayers fixes this. It's both a **ready-to-use PostgreSQL distribution
with extensions pre-installed** and a **tool to build your own custom
image** with exactly the extensions you need -- all on top of the
official `postgres` Docker images. You don't need to figure out how to
build extensions, chase dependencies, or maintain Dockerfiles.

Each extension is published as a minimal Docker image layer containing
only its binaries. You stack them on top of the official `postgres`
image using `COPY --from` -- one line per extension, no compilation.

## Quick start

### Option 1: Ready-to-use images

Pre-built combined images with `shared_preload_libraries` already
configured:

```bash
# All 52 extensions
docker run -d -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-full:17

# Azure Database for PostgreSQL compatible (28 extensions)
docker run -d -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-azure:17
```

Available profiles: `full`, `azure`. Each is published for PG 17, 18,
and 19. See [Profiles](#profiles) for details and how to create custom
ones.

> **Note:** Vendor profiles (e.g., `azure`) are a best-effort
> approximation for local development. They are not a replacement for
> the actual managed service -- extension versions, configuration
> defaults, and platform-specific behavior may differ. Use them to
> develop and test locally, not to replicate production exactly.

### Option 2: Pick your own extensions

Each extension is published as its own image layer. You stack them onto
the official `postgres` image with `COPY --from` -- each line adds one
extension to the final image:

```dockerfile
FROM postgres:17

COPY --from=ghcr.io/pglayers/pgx-pgvector:17  / /
COPY --from=ghcr.io/pglayers/pgx-pg_cron:17   / /
COPY --from=ghcr.io/pglayers/pgx-postgis:17   / /
```

Build and run:

```bash
docker build -t my-postgres .
docker run -d -e POSTGRES_PASSWORD=secret my-postgres
```

No compilation happens -- Docker pulls the pre-built extension
layers from the registry and overlays them onto the official image.
The result is a single image with exactly the extensions you chose,
composed layer by layer.

## Supported PostgreSQL versions

| Version | Status |
|---------|--------|
| PostgreSQL 17 | Stable |
| PostgreSQL 18 | Stable |
| PostgreSQL 19 | Experimental (beta -- supported until officially released) |

All extensions are built and tested against PG 17 and 18. Support for
PG 19 is best-effort while it remains in beta; some extensions may not
yet have upstream compatibility. Once PG 19 reaches GA, it will be
promoted to stable.

## Available extensions

| Extension | PG versions | Description |
|-----------|-------------|-------------|
| [age](https://github.com/apache/age) | 17, 18 | Graph database with openCypher query language (Apache AGE) |
| [anon](https://gitlab.com/dalibo/postgresql_anonymizer) | 17, 18 | Data anonymization and masking |
| [credcheck](https://github.com/HexaCluster/credcheck) | 17, 18, 19 | Credential checks on user creation / password change |
| [h3-pg](https://github.com/zachasme/h3-pg) | 17, 18, 19 | Uber H3 hexagonal geospatial indexing |
| [hll](https://github.com/citusdata/postgresql-hll) | 17, 18 | HyperLogLog probabilistic distinct counting |
| [http](https://github.com/pramsey/pgsql-http) | 17, 18, 19 | HTTP client for PostgreSQL (web requests from SQL) |
| [hypopg](https://github.com/HypoPG/hypopg) | 17, 18, 19 | Hypothetical indexes for what-if analysis |
| [ip4r](https://github.com/RhodiumToad/ip4r) | 17, 18, 19 | IPv4/IPv6 range data types with GiST indexing |
| [orafce](https://github.com/orafce/orafce) | 17, 18, 19 | Oracle compatibility functions and packages |
| [pgaudit](https://github.com/pgaudit/pgaudit) | 17, 18 | Audit logging (session and object-level) |
| [pg_bigm](https://github.com/pgbigm/pg_bigm) | 17, 18 | 2-gram full text search (better for CJK languages) |
| [pglogical](https://github.com/2ndQuadrant/pglogical) | 17, 18, 19 | Logical streaming replication using publish/subscribe model |
| [pg_cron](https://github.com/citusdata/pg_cron) | 17, 18 | Job scheduler (periodic jobs inside the database) |
| [pg_duckdb](https://github.com/duckdb/pg_duckdb) | 17, 18 | DuckDB columnar analytics engine embedded in Postgres |
| [pg_durable](https://github.com/microsoft/pg_durable) | 17, 18 | In-database durable execution (fault-tolerant workflows) |
| [pg_failover_slots](https://github.com/EnterpriseDB/pg_failover_slots) | 17, 18 | Logical replication slot manager for failover |
| [pg_graphql](https://github.com/supabase/pg_graphql) | 17, 18 | GraphQL support for PostgreSQL |
| [pg_hashids](https://github.com/iCyberon/pg_hashids) | 17, 18, 19 | Short unique hash IDs from integers |
| [pg_hint_plan](https://github.com/ossc-db/pg_hint_plan) | 17, 18 | Tweak execution plans using hints in SQL comments |
| [pg_ivm](https://github.com/sraoss/pg_ivm) | 17, 18 | Incremental View Maintenance for materialized views |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema) | 17, 18 | JSON Schema validation |
| [pg_net](https://github.com/supabase/pg_net) | 17, 18, 19 | Async non-blocking HTTP/HTTPS requests |
| [pg_partman](https://github.com/pgpartman/pg_partman) | 17, 18, 19 | Automated table partition management |
| [pg_qualstats](https://github.com/powa-team/pg_qualstats) | 17, 18, 19 | Statistics collector for WHERE clause predicates |
| [pg_repack](https://github.com/reorg/pg_repack) | 17, 18, 19 | Online table reorganization without heavy locks |
| [pg_roaringbitmap](https://github.com/ChenHuajun/pg_roaringbitmap) | 17, 18 | Roaring bitmap data type for fast set operations |
| [pg_similarity](https://github.com/eulerto/pg_similarity) | 17, 18, 19 | Similarity functions (Levenshtein, Jaro-Winkler, Cosine, Jaccard) |
| [pgrouting](https://github.com/pgRouting/pgrouting) | 17, 18 | Geospatial routing and network analysis on PostGIS |
| [pgsodium](https://github.com/michelp/pgsodium) | 17, 18, 19 | Modern cryptography using libsodium |
| [pg_squeeze](https://github.com/cybertec-postgresql/pg_squeeze) | 17, 18, 19 | Remove unused space from tables without heavy locks |
| [pg_stat_monitor](https://github.com/percona/pg_stat_monitor) | 17, 18 | Enhanced query statistics with histograms and buckets |
| [pg_uuidv7](https://github.com/fboulnois/pg_uuidv7) | 17, 18, 19 | UUIDv7 generation (time-sortable unique identifiers) |
| [pg_wait_sampling](https://github.com/postgrespro/pg_wait_sampling) | 17, 18, 19 | Sampling-based statistics of wait events |
| [pgvector](https://github.com/pgvector/pgvector) | 17, 18, 19 | Vector similarity search for AI/embeddings |
| [pgjwt](https://github.com/michelp/pgjwt) | 17, 18, 19 | JSON Web Token (JWT) generation and validation |
| [pgtap](https://github.com/theory/pgtap) | 17, 18, 19 | Unit testing framework for PostgreSQL |
| [pgtt](https://github.com/darold/pgtt) | 17, 18, 19 | Oracle-style Global Temporary Tables |
| [plpgsql_check](https://github.com/okbob/plpgsql_check) | 17, 18, 19 | PL/pgSQL linter and validator |
| [plprofiler](https://github.com/bigsql/plprofiler) | 17, 18 | Performance profiler for PL/pgSQL functions |
| [plv8](https://github.com/plv8/plv8) | 17, 18 | JavaScript (V8) procedural language |
| [PostGIS](https://github.com/postgis/postgis) | 17, 18, 19 | Geospatial extensions (geometry, geography, raster, MVT) |
| [postgres_protobuf](https://github.com/mpartel/postgres-protobuf) | 17, 18, 19 | Protocol Buffer support (query, convert to/from JSON) |
| [prefix](https://github.com/dimitri/prefix) | 17, 18, 19 | Prefix range data type for phone routing lookups |
| [pgfincore](https://github.com/klando/pgfincore) | 17, 18, 19 | Inspect and manage OS page cache for data files |
| [rum](https://github.com/postgrespro/rum) | 17, 18 | GIN-like index with ordering for full text search |
| [semver](https://github.com/theory/pg-semver) | 17, 18, 19 | Semantic version data type |
| [tdigest](https://github.com/tvondra/tdigest) | 17, 18, 19 | T-digest for quantile and percentile estimation |
| [tds_fdw](https://github.com/tds-fdw/tds_fdw) | 17, 18 | Foreign data wrapper for SQL Server and Sybase |
| [temporal_tables](https://github.com/arkhipov/temporal_tables) | 17, 18 | System-period temporal tables |
| [timescaledb](https://github.com/timescale/timescaledb) | 17, 18 | Time-series hypertables, compression, continuous aggregates |
| [wal2json](https://github.com/eulerto/wal2json) | 17, 18 | JSON output plugin for logical replication / CDC |
| [wrappers](https://github.com/supabase/wrappers) | 17, 18 | Foreign Data Wrapper framework (Stripe, S3, Firebase, etc.) |

### Image tags

Each extension is published with two tag formats:

- `pgx-<extension>:<pg_major>` -- latest build (e.g. `pgx-pgvector:17`)
- `pgx-<extension>:<pg_major>-<version>` -- pinned version (e.g. `pgx-pgvector:17-v0.8.3`)

All images are multi-architecture (`linux/amd64` and `linux/arm64`) and
hosted on GHCR at `ghcr.io/pglayers/pgx-*`. Docker automatically pulls
the correct architecture for your platform.

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
| age | `age` |
| anon | `anon` |
| credcheck | `credcheck` |
| pg_cron | `pg_cron` |
| pg_duckdb | `pg_duckdb` |
| pg_durable | `pg_durable` |
| pg_failover_slots | `pg_failover_slots` |
| pg_hint_plan | `pg_hint_plan` |
| pg_net | `pg_net` |
| pg_partman | `pg_partman_bgw` |
| pg_qualstats | `pg_qualstats` |
| pg_squeeze | `pg_squeeze` |
| pg_stat_monitor | `pg_stat_monitor` |
| pg_wait_sampling | `pg_wait_sampling` |
| pgaudit | `pgaudit` |
| pglogical | `pglogical` |
| pgsodium | `pgsodium` |
| pgtt | `pgtt` |
| plprofiler | `plprofiler` |
| timescaledb | `timescaledb` |

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
libproj, libgdal, libjson-c, libprotobuf-c, and PROJ/GDAL data files), so
`COPY --from` is fully self-contained. Geometry, geography, topology,
raster, and MVT (Mapbox Vector Tiles) are all included.

To enable GDAL raster format drivers (GeoTIFF, PNG, etc.), set the
environment variable:

```dockerfile
ENV POSTGIS_GDAL_ENABLED_DRIVERS=ENABLE_ALL
```

By default, GDAL drivers are disabled for security (same as the official
PostGIS Docker image).

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

When you write `COPY --from=ghcr.io/pglayers/pgx-pgvector:17 / /` in
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

# Build for PG 19 (beta -- requires PG_TAG override until GA)
make build EXT=pgvector PG=19 PG_TAG=19beta1
make build-all PG=19 PG_TAG=19beta1

# Build a combined image with ALL extensions included
make image PG=17 REGISTRY=local

# Custom image name
make image PG=18 REGISTRY=local IMAGE_NAME=my-postgres

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

# Remove built image for a single extension
make clean EXT=pgvector

# Remove all built extension images (reclaim disk space)
make clean-all
```

### Running tests

```bash
# Full test suite: collisions, ldd, CREATE EXTENSION, smoke tests,
# integration tests (builds all extensions first)
make test REGISTRY=local PG=17

# Quick integration tests against an already-built combined image
make image PG=17 REGISTRY=local
make test-image PG=17
```

Tests must pass for all supported PG versions (17, 18, 19).

### Profiles

Profiles let you build and test a curated subset of extensions rather
than the full set. This is useful for matching managed PostgreSQL
service offerings (e.g., Azure Database for PostgreSQL) or creating
purpose-built images.

```bash
# List available profiles
make list-profiles

# List extensions in a profile
make list PROFILE=azure

# Build only the extensions in a profile
make build-all PG=17 PROFILE=azure

# Build a combined image with only the profile's extensions
make image PG=17 PROFILE=azure    # produces: pglayers-azure:17

# Run the full test suite against a profile
make test REGISTRY=local PG=17 PROFILE=azure

# Validate all profile files are in sync with extensions/
make check-profiles
```

#### Shipped profiles

| Profile | Description |
|---------|-------------|
| `full` | All extensions provided by pglayers |
| `azure` | Extensions matching Azure Database for PostgreSQL Flexible Server |

#### Creating a custom profile

Create a text file in `profiles/` with one extension directory name per
line (alphabetically sorted). Comments (`#`) and blank lines are ignored:

```
# My custom profile
pg_cron
pgvector
postgis
```

Then use it:

```bash
make image PG=17 PROFILE=myprofile
make test REGISTRY=local PG=17 PROFILE=myprofile
```

#### Published profile images

CI builds and pushes combined profile images to GHCR:

- `ghcr.io/<owner>/pglayers-azure:17`
- `ghcr.io/<owner>/pglayers-azure:18`
- `ghcr.io/<owner>/pglayers-full:17`
- `ghcr.io/<owner>/pglayers-full:18`

These are ready-to-use PostgreSQL images with the profile's extensions
pre-installed and `shared_preload_libraries` configured.

The `make test` suite checks:

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

6. **Integration tests** -- Each extension's `test.sql` file runs
   multi-step validation with PASS/FAIL assertions.

Example output:

```
---- Phase 3: Checking for file collisions between extensions...
PASS pgvector <-> postgis: no collisions
...
PASS No file collisions detected between any extension pair

---- Phase 5: Building combined image and checking shared libraries...
PASS All shared library dependencies resolve

---- Phase 6: Functional tests...
PASS CREATE EXTENSION vector
PASS smoke: pgvector similarity
...

---- Phase 7: Integration tests (extensions/*/test.sql)...
PASS integration pgvector (3 checks)
PASS integration postgis (4 checks)
...
========================================
Results: 699 passed, 0 failed, 0 warnings
========================================
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide on adding
extensions, reporting bugs, and submitting changes.

## Project structure

```
pglayers/
├── Makefile                          Build interface
├── Dockerfile                        Combined image (all extensions)
├── CONTRIBUTING.md                   Contribution guide
├── AGENTS.md                         Agent/CI instructions
├── .github/
│   ├── base-image-digests.json       Tracked base image digests
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml            Bug report form
│   │   ├── new_extension.yml         Extension request form
│   │   └── config.yml                Template chooser config
│   └── workflows/
│       ├── build-push.yml            CI: builds extensions, pushes to GHCR
│       ├── test.yml                  CI: full test suite (PG 17, 18, 19)
│       ├── monitor-base-image.yml    Detects base image updates (every 6h)
│       ├── monitor-extensions.yml    Detects new extension releases (daily)
│       └── cache-cleanup.yml         Prunes stale GHA caches
├── extensions/
│   ├── pgvector/
│   │   ├── Dockerfile                Multi-stage build -> artifact image
│   │   ├── extension.conf            Metadata and version mapping
│   │   └── test.sql                  Integration tests (PASS/FAIL assertions)
│   ├── pg_cron/
│   ├── postgis/                      (complex: bundles runtime libs)
│   ├── ... (52 extensions total)
│   └── wal2json/
├── profiles/
│   ├── azure.txt                     Azure PostgreSQL Flexible Server extensions
│   └── full.txt                      All extensions (CI-verified)
├── tests/
│   ├── test-layers.sh                Full test suite (collisions + functional)
│   └── test-image.sh                 Quick integration tests against combined image
└── examples/
    └── Dockerfile.example            End-user reference
```

## Licensing policy

This project ships extensions with **permissive open-source licenses**
(PostgreSQL, MIT, BSD, Apache 2.0, ISC) and, where industry practice
clearly supports it, **GPL-2.0 extensions loaded via PostgreSQL's
dynamic extension mechanism**.

### GPL-2.0 extensions (PostGIS, pgRouting)

PostGIS and pgRouting are licensed under GPL-2.0. Strictly interpreted,
the GPL could apply to any program that "links" with GPL code. However,
PostgreSQL extensions are loaded at runtime via `dlopen()` through a
stable public API (`CREATE EXTENSION`), which the PostgreSQL community
and broader industry treat as **"mere aggregation"** rather than
creating a combined work:

- Every managed PostgreSQL service (AWS RDS, Azure, Google Cloud SQL,
  Neon, Supabase) distributes PostGIS and pgRouting the same way.
- The official `postgis/postgis` Docker image on Docker Hub uses the
  identical `COPY --from` pattern.
- No GPL enforcement action has ever been taken against distributors
  of dynamically-loaded PostgreSQL extensions.
- The PostgreSQL project has operated under this interpretation for
  20+ years.

We include these extensions because the practical risk is zero and
excluding them would make the project significantly less useful.
If your legal team disagrees with this interpretation, simply omit
the PostGIS and pgRouting `COPY --from` lines from your Dockerfile.

### Extensions we exclude

| License | Policy | Examples |
|---------|--------|----------|
| GPL-3.0 | Excluded (stronger copyleft, less industry consensus) | login_hook, session_variable |
| AGPL-3.0 | Excluded | topn |
| BSL, SSPL, ELv2, FSL | Excluded (not open source) | -- |
| Requires proprietary deps | Excluded | oracle_fdw (Oracle Instant Client) |

### What this means in practice

| License | Included? | Examples |
|---------|-----------|----------|
| PostgreSQL, MIT, BSD, Apache 2.0, ISC | Yes | pgvector, pg_cron, pgaudit, timescaledb |
| MPL-2.0 (weak file-level copyleft) | Yes | pg_uuidv7 |
| GPL-2.0 (dynamic extension loading) | Yes | PostGIS, pgRouting |
| GPL-3.0 | No | login_hook, session_variable |
| AGPL-3.0 | No | -- |
| BSL, SSPL, ELv2, FSL | No | -- |

## License

[MIT](LICENSE)
