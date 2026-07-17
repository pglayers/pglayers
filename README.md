# pglayers

The [official PostgreSQL Docker images](https://hub.docker.com/_/postgres)
ship without extensions. Every time you need pgvector, PostGIS, or
pg_cron, you're stuck manually installing dependencies, compiling from
source, or settling for third-party images that bundle a fixed set of
extensions.

pglayers fixes this. It's both a **ready-to-use PostgreSQL distribution
with extensions pre-installed** and a **tool to build your own custom
image** with exactly the extensions you need -- all on top of the
official `postgres` Docker images. You don't need to figure out how to
build PostgreSQL extensions, install dependencies, or set up compilers.

Each extension is published as a minimal Docker image layer containing
only its binaries. You stack them on top of the official `postgres`
image using `COPY --from` -- one line per extension, no compilation.

## Quick start

### Option 1: Ready-to-use images

Pre-built combined images with `shared_preload_libraries` already
configured:

```bash
# All 80+ extensions
docker run -d -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-full:17

# Azure Database for PostgreSQL compatible (30+ extensions)
docker run -d -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-azure:17
```

Available profiles: `full`, `azure`. Each is published for PG 17, 18,
and 19. See [Profiles](#profiles) for details and how to create custom
ones.

The `azure` profile includes DocumentDB, providing MongoDB wire protocol
compatibility on port 10260 -- the same engine behind Azure DocumentDB.

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

#### PG 18+ isolated layout

Starting with PostgreSQL 18, pglayers uses an **isolated extension
layout** that leverages PostgreSQL's `extension_control_path` GUC. Each
extension lives in its own `/extensions/<name>/` namespace, eliminating
file collision risk entirely:

```dockerfile
FROM postgres:18

COPY --from=ghcr.io/pglayers/pgx-pgvector:18  / /extensions/pgvector/
COPY --from=ghcr.io/pglayers/pgx-pg_cron:18   / /extensions/pg_cron/
COPY --from=ghcr.io/pglayers/pgx-postgis:18   / /extensions/postgis/

# Tell PostgreSQL where to find isolated extensions
RUN echo "extension_control_path = '/extensions/pgvector/share:/extensions/pg_cron/share:/extensions/postgis/share:\$system'" \
    >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "dynamic_library_path = '/extensions/pgvector/lib:/extensions/pg_cron/lib:/extensions/postgis/lib:\$libdir'" \
    >> /usr/share/postgresql/postgresql.conf.sample

# Resolve bundled shared library dependencies
RUN for d in /extensions/*/lib; do echo "$d"; done \
    > /etc/ld.so.conf.d/pglayers.conf && ldconfig
```

The `$system` and `$libdir` suffixes ensure built-in contrib extensions
(hstore, pg_stat_statements, etc.) remain discoverable.

> **Note:** The pre-built profile images (`pglayers-full:18`,
> `pglayers-azure:18`) handle all GUC and linker configuration
> automatically. The manual setup above is only needed when composing
> your own image with Option 2.

> **New to Docker?** See [Verifying your container](#verifying-your-container)
> for how to check it's running and handle port conflicts.

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

| Extension | Version | PG versions | Description |
|-----------|---------|-------------|-------------|
| [age](https://github.com/apache/age) | 1.7.0 (PG17), 1.8.0 (PG18) | 17, 18 | Graph database with openCypher query language (Apache AGE) |
| [anon](https://gitlab.com/dalibo/postgresql_anonymizer) | 3.1.1 | 17, 18 | Data anonymization and masking |
| [credcheck](https://github.com/HexaCluster/credcheck) | 5.0 | 17, 18, 19 | Credential checks on user creation / password change |
| [db2fce](https://github.com/credativ/db2fce) | 0.0.17 | 17, 18 | DB2 compatibility functions (date/time, string helpers) |
| [documentdb](https://github.com/documentdb/documentdb) | 0.113-0 | 17, 18 | MongoDB-compatible document database engine (BSON types and CRUD API) |
| [extra_window_functions](https://github.com/xocolatl/extra_window_functions) | 1.0 | 17, 18, 19 | Extra window functions (ignore-nulls variants, nth-from-last) |
| [first_last_agg](https://github.com/wulczer/first_last_agg) | 0.1.4-4-gd63ea3b | 17, 18 | first() and last() aggregate functions |
| [h3-pg](https://github.com/zachasme/h3-pg) | 4.2.3 | 17, 18 | Uber H3 hexagonal geospatial indexing |
| [hll](https://github.com/citusdata/postgresql-hll) | 2.21 | 17, 18, 19 | HyperLogLog probabilistic distinct counting |
| [http](https://github.com/pramsey/pgsql-http) | 1.7.2 | 17, 18, 19 | HTTP client for PostgreSQL (web requests from SQL) |
| [hypopg](https://github.com/HypoPG/hypopg) | 1.4.3 | 17, 18, 19 | Hypothetical indexes for what-if analysis |
| [icu_ext](https://github.com/dverite/icu_ext) | 1.11.0 | 17, 18, 19 | ICU functions: Unicode names, transliteration, spellout, collation |
| [ip4r](https://github.com/RhodiumToad/ip4r) | 2.4.3 | 17, 18, 19 | IPv4/IPv6 range data types with GiST indexing |
| [jsquery](https://github.com/postgrespro/jsquery) | 1.2 | 17, 18 | JSON query language with GIN indexing |
| [orafce](https://github.com/orafce/orafce) | 4.16.7 | 17, 18, 19 | Oracle compatibility functions and packages |
| [periods](https://github.com/xocolatl/periods) | 1.2.3 | 17, 18 | SQL:2016 application-time PERIODs and system versioning |
| [pg_background](https://github.com/vibhorkum/pg_background) | 2.0.2 | 17, 18, 19 | Run SQL in background worker processes |
| [pg_csv](https://github.com/PostgREST/pg_csv) | 1.0.2 | 17, 18, 19 | Aggregate result rows into CSV text |
| [pg_dirtyread](https://github.com/df7cb/pg_dirtyread) | 2.8 | 17, 18, 19 | Read dead (deleted, unvacuumed) tuples for forensics/recovery |
| [pg_pwhash](https://github.com/cybertec-postgresql/pg_pwhash) | 1.0 | 17, 18, 19 | Password hashing (scrypt, argon2, yescrypt) |
| [pg_show_plans](https://github.com/cybertec-postgresql/pg_show_plans) | 2.1.8 | 17, 18, 19 | Show execution plans of all currently running queries |
| [pg_statviz](https://github.com/vyruss/pg_statviz) | 1.1 | 17, 18, 19 | Time-series snapshots of PostgreSQL statistics for visualization |
| [pgaudit](https://github.com/pgaudit/pgaudit) | 17.1 | 17, 18 | Audit logging (session and object-level) |
| [pg_bigm](https://github.com/pgbigm/pg_bigm) | 1.2 | 17, 18 | 2-gram full text search (better for CJK languages) |
| [pg_cron](https://github.com/citusdata/pg_cron) | 1.6.7 | 17, 18 | Job scheduler (periodic jobs inside the database) |
| [pg_duckdb](https://github.com/duckdb/pg_duckdb) | 1.1.1 | 17, 18 | DuckDB columnar analytics engine embedded in Postgres |
| [pg_durable](https://github.com/microsoft/pg_durable) | 0.2.3 | 17, 18 | In-database durable execution (fault-tolerant workflows) |
| [pg_failover_slots](https://github.com/EnterpriseDB/pg_failover_slots) | 1.2.1 | 17, 18 | Logical replication slot manager for failover |
| [pg_graphql](https://github.com/supabase/pg_graphql) | 1.6.1 | 17, 18 | GraphQL support for PostgreSQL |
| [pg_hashids](https://github.com/iCyberon/pg_hashids) | 1.2.1 | 17, 18, 19 | Short unique hash IDs from integers |
| [pg_hint_plan](https://github.com/ossc-db/pg_hint_plan) | 1.7.1 | 17, 18 | Tweak execution plans using hints in SQL comments |
| [pg_ivm](https://github.com/sraoss/pg_ivm) | 1.13 | 17, 18 | Incremental View Maintenance for materialized views |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema) | 0.3.4 | 17, 18 | JSON Schema validation |
| [pg_lake](https://github.com/Snowflake-Labs/pg_lake) | 3.3.4 | 17, 18 | Iceberg and data lake access (Parquet, CSV, JSON via DuckDB) |
| [pg_net](https://github.com/supabase/pg_net) | 0.20.3 | 17, 18, 19 | Async non-blocking HTTP/HTTPS requests |
| [pg_partman](https://github.com/pgpartman/pg_partman) | 5.4.3 | 17, 18, 19 | Automated table partition management |
| [pg_permissions](https://github.com/cybertec-postgresql/pg_permissions) | 1.4.1 | 17, 18, 19 | Review and audit object permissions against a desired state |
| [pg_qualstats](https://github.com/powa-team/pg_qualstats) | 2.1.4 | 17, 18, 19 | Statistics collector for WHERE clause predicates |
| [pg_repack](https://github.com/reorg/pg_repack) | 1.5.3 | 17, 18, 19 | Online table reorganization without heavy locks |
| [pg_roaringbitmap](https://github.com/ChenHuajun/pg_roaringbitmap) | 1.2.0 | 17, 18 | Roaring bitmap data type for fast set operations |
| [pg_rrule](https://github.com/Natureshadow/pg_rrule) | 0.3.0 | 17, 18, 19 | iCalendar RRULE recurrence type and occurrence expansion |
| [pg_similarity](https://github.com/eulerto/pg_similarity) | 1.0 | 17, 18 | Similarity functions (Levenshtein, Jaro-Winkler, Cosine, Jaccard) |
| [pg_squeeze](https://github.com/cybertec-postgresql/pg_squeeze) | 1.9.3 | 17, 18, 19 | Remove unused space from tables without heavy locks |
| [pg_stat_monitor](https://github.com/percona/pg_stat_monitor) | 2.3.2 | 17, 18 | Enhanced query statistics with histograms and buckets |
| [pg_textsearch](https://github.com/timescale/pg_textsearch) | 1.3.1 | 17, 18 | BM25 relevance-ranked full-text search |
| [pg_uuidv7](https://github.com/fboulnois/pg_uuidv7) | 1.7.0 | 17, 18, 19 | UUIDv7 generation (time-sortable unique identifiers) |
| [pg_wait_sampling](https://github.com/postgrespro/pg_wait_sampling) | 1.1.11 | 17, 18, 19 | Sampling-based statistics of wait events |
| [pgfincore](https://github.com/klando/pgfincore) | 1.4.0 | 17, 18, 19 | Inspect and manage OS page cache for data files |
| [pgjwt](https://github.com/michelp/pgjwt) | master | 17, 18, 19 | JSON Web Token (JWT) generation and validation |
| [pglogical](https://github.com/2ndQuadrant/pglogical) | 2.4.7 | 17, 18, 19 | Logical streaming replication using publish/subscribe model |
| [pgnodemx](https://github.com/CrunchyData/pgnodemx) | 2.0.1 | 17, 18 | Expose node OS/cgroup metrics as SQL (container-aware monitoring) |
| [pgpcre](https://github.com/petere/pgpcre) | 0.20190509 | 17, 18, 19 | Perl-compatible regular expression (PCRE) type and functions |
| [pgrouting](https://github.com/pgRouting/pgrouting) | 4.0.1 | 17, 18, 19 | Geospatial routing and network analysis on PostGIS |
| [pgsodium](https://github.com/michelp/pgsodium) | 3.1.11 | 17, 18, 19 | Modern cryptography using libsodium |
| [pgsphere](https://github.com/postgrespro/pgsphere) | 1.5.2 | 17, 18 | Spherical data types (points, circles, polygons) for astronomy/geo |
| [pgtap](https://github.com/theory/pgtap) | 1.3.4 | 17, 18, 19 | Unit testing framework for PostgreSQL |
| [pgtt](https://github.com/darold/pgtt) | 4.5 | 17, 18, 19 | Oracle-style Global Temporary Tables |
| [pgvector](https://github.com/pgvector/pgvector) | 0.8.5 | 17, 18, 19 | Vector similarity search for AI/embeddings |
| [pgvectorscale](https://github.com/timescale/pgvectorscale) | 0.9.0 | 17, 18 | High-performance vector search with DiskANN (complements pgvector) |
| [pljs](https://github.com/plv8/pljs) | 1.0.5 | 17, 18 | JavaScript (QuickJS) procedural language |
| [plpgsql_check](https://github.com/okbob/plpgsql_check) | 2.10.1 | 17, 18, 19 | PL/pgSQL linter and validator |
| [plprofiler](https://github.com/bigsql/plprofiler) | 4.2.5 | 17, 18 | Performance profiler for PL/pgSQL functions |
| [plv8](https://github.com/plv8/plv8) | 3.2.4 | 17, 18 | JavaScript (V8) procedural language |
| [PostGIS](https://github.com/postgis/postgis) | 3.6.4 | 17, 18, 19 | Geospatial extensions (geometry, geography, raster, MVT) |
| [postgres_protobuf](https://github.com/mpartel/postgres-protobuf) | 0.3.2 | 17, 18, 19 | Protocol Buffer support (query, convert to/from JSON) |
| [prefix](https://github.com/dimitri/prefix) | 1.2.11 | 17, 18, 19 | Prefix range data type for phone routing lookups |
| [prioritize](https://github.com/cybertec-postgresql/prioritize) | 1.0.4 | 17, 18 | Get/set OS scheduling priority of backend processes |
| [rational](https://github.com/begriffs/pg_rational) | 0.0.2 | 17, 18, 19 | Precise fractional (rational number) arithmetic |
| [rum](https://github.com/postgrespro/rum) | 1.3.15 | 17, 18 | GIN-like index with ordering for full text search |
| [semver](https://github.com/theory/pg-semver) | 0.41.0 | 17, 18, 19 | Semantic version data type |
| [set_user](https://github.com/pgaudit/set_user) | 4.2.0 | 17, 18, 19 | Auditable privilege escalation control (set_user/reset_user) |
| [tdigest](https://github.com/tvondra/tdigest) | 1.4.4 | 17, 18, 19 | T-digest for quantile and percentile estimation |
| [tds_fdw](https://github.com/tds-fdw/tds_fdw) | 2.0.5 | 17, 18 | Foreign data wrapper for SQL Server and Sybase |
| [temporal_tables](https://github.com/arkhipov/temporal_tables) | 1.2.2 | 17, 18 | System-period temporal tables |
| [timescaledb](https://github.com/timescale/timescaledb) | 2.28.2 | 17, 18 | Time-series hypertables, compression, continuous aggregates |
| [timestamp9](https://github.com/optiver/timestamp9) | 1.4.0 | 17, 18, 19 | Nanosecond-precision timestamp type |
| [toastinfo](https://github.com/df7cb/toastinfo) | 1.7 | 17, 18, 19 | Inspect the TOAST storage details of a value |
| [wal2json](https://github.com/eulerto/wal2json) | 2.6 | 17, 18 | JSON output plugin for logical replication / CDC |
| [wrappers](https://github.com/supabase/wrappers) | 0.6.2 | 17, 18 | Foreign Data Wrapper framework (Stripe, S3, Firebase, etc.) |

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
| documentdb | `pg_documentdb_gw_host` |
| pg_cron | `pg_cron` |
| pg_duckdb | `pg_duckdb` |
| pg_durable | `pg_durable` |
| pg_failover_slots | `pg_failover_slots` |
| pg_hint_plan | `pg_hint_plan` |
| pg_lake | `pg_extension_base` |
| pg_net | `pg_net` |
| pg_partman | `pg_partman_bgw` |
| pg_qualstats | `pg_qualstats` |
| pg_show_plans | `pg_show_plans` |
| pg_squeeze | `pg_squeeze` |
| pg_stat_monitor | `pg_stat_monitor` |
| pg_textsearch | `pg_textsearch` |
| pg_wait_sampling | `pg_wait_sampling` |
| pgaudit | `pgaudit` |
| pglogical | `pglogical` |
| pgnodemx | `pgnodemx` |
| pgsodium | `pgsodium` |
| pgtt | `pgtt` |
| plprofiler | `plprofiler` |
| set_user | `set_user` |
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

### DocumentDB

DocumentDB provides a MongoDB-compatible document database engine built
on PostgreSQL. It consists of two extensions:

- **`documentdb_core`** -- BSON data type and core operations (no
  dependencies, works standalone).
- **`documentdb`** -- Full CRUD API surface. Requires `documentdb_core`,
  `pg_cron`, `vector` (pgvector), `postgis`, and `tsm_system_rows`.

The layer also includes `pg_documentdb_gw_host`, a background worker
that provides MongoDB wire protocol compatibility on port 10260. When
loaded via `shared_preload_libraries`, MongoDB clients (mongosh, pymongo,
Node.js driver) can connect directly.

Create extensions in order:

```sql
CREATE EXTENSION IF NOT EXISTS documentdb_core;
-- For the full API (requires pg_cron, vector, postgis layers):
CREATE EXTENSION IF NOT EXISTS documentdb;
```

Gateway configuration (add to `postgresql.conf`):

```ini
shared_preload_libraries = 'pg_documentdb_gw_host'
documentdb_gateway.database = 'postgres'
documentdb_gateway.setup_configuration_file = '/etc/documentdb/gateway_config.json'
```

A default configuration file is bundled in the layer at
`/etc/documentdb/gateway_config.json`. It listens on port 10260 with
auto-generated self-signed TLS certificates (clients can connect with or
without TLS). Override with your own file to customize ports, TLS, or
blocked roles.

### pg_lake

pg_lake provides Iceberg table support and data lake file access
(Parquet, CSV, JSON) for PostgreSQL. It uses DuckDB as its query engine
via a companion process.

The layer includes:
- Multiple PostgreSQL extensions (`pg_lake`, `pg_lake_table`,
  `pg_lake_engine`, `pg_lake_iceberg`, `pg_lake_copy`,
  `pg_extension_base`, `pg_map`)
- `pgduck_server` binary (standalone DuckDB-backed process)
- Auto-start entrypoint wrapper

**Setup:**

```dockerfile
FROM postgres:17
COPY --from=ghcr.io/pglayers/pgx-pg_lake:17 / /
RUN echo "shared_preload_libraries = 'pg_extension_base'" \
    >> /usr/share/postgresql/postgresql.conf.sample
ENTRYPOINT ["/usr/local/bin/pg-lake-entrypoint.sh"]
CMD ["postgres"]
```

The entrypoint wrapper starts `pgduck_server` in the background (Unix
socket on port 5332, no external port exposed) then delegates to the
standard postgres entrypoint. No manual process management required.

```sql
CREATE EXTENSION pg_lake CASCADE;
```

**Note:** pg_lake conflicts with pg_duckdb (both bundle `libduckdb.so`).
Do not use both in the same image.

### Profile images (auto-configuration)

The pre-built combined images (`pglayers-full`, `pglayers-azure`)
automatically handle all runtime configuration:

- **`shared_preload_libraries`** -- set from each extension's
  `SHARED_PRELOAD` field.
- **postgresql.conf settings** -- GUC parameters required by extensions
  (e.g., `documentdb_gateway.database`) are appended automatically from
  each extension's `PG_CONF` field.
- **Companion processes** -- extensions that need a background process
  (e.g., pg_lake's `pgduck_server`) are started automatically via a
  generated entrypoint wrapper. No manual process management required.

When using profile images, you don't need to configure any of the above
manually -- just `docker run` and `CREATE EXTENSION`.

## How it works

The project publishes one Docker image per extension per PostgreSQL
version. These are not runnable containers -- they are `FROM scratch`
images containing only the extension artifacts.

### How extensions are built

Extensions fall into four build families (in order of preference):

1. **APT via the shared template** -- the default for most extensions.
   They have no Dockerfile at all: a single shared `Dockerfile.apt`
   installs `postgresql-<pg>-<pkg>` from PGDG, extracts the files, bundles
   any non-base runtime libraries, and relocates them for the classic
   layout. You only write an `extension.conf` (with `APT_PACKAGE`) and a
   `test.sql`. *(~56 extensions, e.g. pgvector, pg_cron.)*
2. **APT with a custom Dockerfile** -- for apt packages the shared template
   can't express: multiple/renamed packages, `.control` update-alternatives
   symlinks, or extra steps. *(e.g. postgis, pgrouting, http, h3_pg,
   tds_fdw.)*
3. **Source-built from an upstream prebuilt image** -- for heavy builds
   that ship an official image or a cached build stage, avoiding a long
   compile in CI. *(e.g. pg_duckdb from `pgduckdb/pgduckdb`, pg_lake from a
   prebuilt vcpkg image.)*
4. **Source-built from git** -- `git clone` + `make` at a pinned upstream
   tag, when no apt package exists. *(e.g. pg_net, pgsodium, the pgrx/Rust
   extensions.)*

Whatever the family, every layer must be **self-contained** (carry all of
its own non-base runtime libraries) and collision-free -- enforced by the
test suite. See [AGENTS.md](AGENTS.md) for the build requirements and
[CONTRIBUTING.md](CONTRIBUTING.md) for how to add one.

### PG 17: Classic layout

Extension files are at their standard PostgreSQL filesystem paths:

```
/usr/lib/postgresql/17/lib/vector.so
/usr/share/postgresql/17/extension/vector.control
/usr/share/postgresql/17/extension/vector--0.8.4.sql
```

When you write `COPY --from=ghcr.io/pglayers/pgx-pgvector:17 / /` in
your Dockerfile, Docker copies these files into the official `postgres`
image at exactly the right locations. PostgreSQL finds them and you can
`CREATE EXTENSION`.

### PG 18+: Isolated layout

Extension files use a flat layout compatible with PostgreSQL's
`extension_control_path` GUC and [CloudNativePG ImageVolumes](https://cloudnative-pg.io/docs/1.30/imagevolume_extensions/):

```
/lib/vector.so
/lib/bitcode/vector/...
/share/extension/vector.control
/share/extension/vector--0.8.4.sql
```

Each extension image is mounted into its own namespace
(`/extensions/<name>/`) in the combined image. PostgreSQL discovers them
via the `extension_control_path` and `dynamic_library_path` GUCs. This
approach:

- **Eliminates file collisions** -- two extensions can bundle different
  versions of the same library without conflict
- **Enables runtime composability** -- extensions can be mounted at
  deploy time via Docker volumes or Kubernetes ImageVolumes
- **Is CNPG-native** -- pglayers `:18` images are directly usable as
  CloudNativePG `ClusterImageCatalog` entries without modification

### CloudNativePG usage

pglayers PG 18+ images are directly compatible with
[CloudNativePG ImageVolume extensions](https://cloudnative-pg.io/docs/1.30/imagevolume_extensions/)
(requires CNPG >= 1.27 and Kubernetes >= 1.33).

> **Important: OS compatibility.** pglayers extensions are built against
> `postgres:18` (Debian Trixie, glibc 2.38). When using CNPG, the
> operand image must also be Trixie-based:
>
> ```yaml
> imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
> ```
>
> The Bullseye/Bookworm variants (`ghcr.io/cloudnative-pg/postgresql:18`)
> have an older glibc and will fail with `GLIBC_2.38 not found`. This is
> the same constraint that applies to CNPG's own extension images --
> extensions must match the operand's OS distribution.

Generate a `ClusterImageCatalog` for your cluster:

```bash
make cnpg-catalog PG=18 REGISTRY=ghcr.io/pglayers > catalog.yaml
kubectl apply -f catalog.yaml
```

Or for a specific profile:

```bash
make cnpg-catalog PG=18 PROFILE=azure REGISTRY=ghcr.io/pglayers > catalog-azure.yaml
```

Then reference extensions in your CNPG `Cluster` spec:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-cluster
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie

  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: pglayers
    major: 18

  postgresql:
    shared_preload_libraries:
      - pg_cron
    extensions:
      - name: pgvector
      - name: pg-cron
      - name: postgis
        ld_library_path:
          - lib
```

You can also define extensions directly without a catalog:

```yaml
  postgresql:
    extensions:
      - name: pgvector
        image:
          reference: ghcr.io/pglayers/pgx-pgvector:18-0.8.4
      - name: postgis
        image:
          reference: ghcr.io/pglayers/pgx-postgis:18-3.6.4
        ld_library_path:
          - lib
```

Extensions with bundled runtime dependencies (PostGIS, pgRouting) need
`ld_library_path: ["lib"]` so the system linker can find their shared
libraries at `/extensions/<name>/lib/`.

### Kubernetes ImageVolumes (without CNPG)

pglayers extension images also work as
[Kubernetes ImageVolumes](https://kubernetes.io/docs/concepts/storage/volumes/#image)
with the stock `postgres:18` image -- no operator required. This gives
you runtime extension composition on any Kubernetes 1.33+ cluster:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: postgres-with-extensions
spec:
  volumes:
    - name: ext-pgvector
      image:
        reference: ghcr.io/pglayers/pgx-pgvector:18-0.8.4
    - name: ext-postgis
      image:
        reference: ghcr.io/pglayers/pgx-postgis:18-3.6.4
    - name: ext-pg-cron
      image:
        reference: ghcr.io/pglayers/pgx-pg_cron:18-v1.6.7
  containers:
    - name: postgres
      image: postgres:18
      env:
        - name: POSTGRES_PASSWORD
          value: "secret"
        - name: LD_LIBRARY_PATH
          value: "/extensions/postgis/lib"
      args:
        - "postgres"
        - "-c"
        - "extension_control_path=/extensions/pgvector/share:/extensions/pg_cron/share:/extensions/postgis/share:$$system"
        - "-c"
        - "dynamic_library_path=/extensions/pgvector/lib:/extensions/pg_cron/lib:/extensions/postgis/lib:$$libdir"
        - "-c"
        - "shared_preload_libraries=pg_cron"
      volumeMounts:
        - name: ext-pgvector
          mountPath: /extensions/pgvector
          readOnly: true
        - name: ext-postgis
          mountPath: /extensions/postgis
          readOnly: true
        - name: ext-pg-cron
          mountPath: /extensions/pg_cron
          readOnly: true
```

Each extension image is mounted as a read-only volume at
`/extensions/<name>/`. PostgreSQL discovers them via
`extension_control_path` and `dynamic_library_path`. No image rebuild
needed -- add or remove extensions by changing volume definitions.

> **Requirements:** Kubernetes 1.33+ (ImageVolume GA). The `$$system`
> and `$$libdir` suffixes ensure built-in contrib extensions remain
> available.

### OCI image labels

Every extension image includes standard OCI labels for machine-readable
discovery:

| Label | Description |
|-------|-------------|
| `org.opencontainers.image.title` | Extension name |
| `org.opencontainers.image.description` | Short description |
| `org.opencontainers.image.version` | Extension version |
| `org.opencontainers.image.source` | Upstream repository URL |
| `org.opencontainers.image.licenses` | SPDX license identifier |
| `io.pglayers.pg.major` | PostgreSQL major version |
| `io.pglayers.layout` | `classic` or `isolated` |
| `io.pglayers.extension.name` | Extension name |
| `io.pglayers.extension.version` | Extension version |

Query labels with:

```bash
docker inspect ghcr.io/pglayers/pgx-pgvector:18 --format '{{json .Config.Labels}}'
```

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

# Scaffold a new APT-based extension (probes PGDG, detects license,
# writes extension.conf + a test.sql stub)
make add-apt-ext PKG=<apt-package> [NAME=<dir>] [PG=17]

# Verify all extensions comply with the licensing policy
make check-licenses

# Verify profiles are in sync with the extensions/ directory
make check-profiles
```

> APT-based extensions have **no Dockerfile** -- they are built by the
> shared `Dockerfile.apt`, with their version and PostgreSQL-version
> support resolved from PGDG at build time. Adding one is usually just
> `make add-apt-ext` + writing `test.sql`. See the
> [Contributing guide](CONTRIBUTING.md#adding-a-new-extension).

### Skipping extensions from CI

Extensions with `CI_SKIP=1` in their `extension.conf` are excluded
from CI builds but remain in the repository for local builds. This is
useful for extensions with prohibitively long build times (e.g., plv8
whose V8 engine compilation exceeds CI timeouts on arm64 emulation).

```bash
# Still works locally
make build EXT=plv8 PG=17

# But skipped by CI (not in build matrix, not in profile images)
```

To skip an extension, add `CI_SKIP=1` to its `extension.conf`. To
re-enable, remove the field and add the extension back to the
appropriate profiles.

### Running tests

```bash
# Full test suite: collisions, ldd, CREATE EXTENSION, smoke tests,
# integration tests (builds all extensions first)
make test REGISTRY=local PG=17

# Quick integration tests against an already-built combined image
make image PG=17 REGISTRY=local
make test-image PG=17

# Kubernetes ImageVolume integration test (requires k3d, PG 18+)
make test-k8s REGISTRY=local PG=18
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

## Verifying your container

After running a `docker run` command, the container starts in the
background (`-d` flag). To confirm it's running:

```bash
# List running containers -- look for STATUS "Up"
docker ps

# Check the container logs for "database system is ready to accept connections"
docker logs <container_id>
```

To connect and verify PostgreSQL is working:

```bash
# Connect from inside the running container
docker exec -it <container_id> psql -U postgres -c "SELECT version();"
```

Replace `<container_id>` with the ID shown by `docker ps` (or the first
few characters of it).

### Exposing and changing the port

By default, the examples above don't publish a port to your host machine.
To access PostgreSQL from outside the container, add `-p`:

```bash
# Publish pglayers (PostgreSQL) on the default port (5432)
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-full:17
```

If port 5432 is already in use (another PostgreSQL instance, for example),
map to a different host port:

```bash
# Use host port 5433 instead (container still listens on 5432 internally)
docker run -d -p 5433:5432 -e POSTGRES_PASSWORD=secret ghcr.io/pglayers/pglayers-full:17
```

Then connect specifying the port:

```bash
psql -h localhost -p 5433 -U postgres
```

The format is `-p <host_port>:<container_port>`. Only the host port
(left side) needs to change -- the container always listens on 5432.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide on adding
extensions, reporting bugs, and submitting changes.

## Project structure

```
pglayers/
├── Makefile                          Build interface
├── Dockerfile                        Combined image (all extensions)
├── Dockerfile.apt                    Shared build for all APT extensions
├── CONTRIBUTING.md                   Contribution guide
├── AGENTS.md                         Agent/CI instructions
├── scripts/
│   ├── apt-support.sh                PGDG availability + version probing
│   ├── apt-lock.sh                   Generate .github/apt-versions.json
│   ├── ext-version.sh                Resolve an extension's build version
│   ├── detect-license.sh             License detection from Debian copyright
│   ├── check-licenses.sh             Enforce the licensing policy
│   └── licenses.conf                 Allow/deny/exception license lists
├── .github/
│   ├── base-image-digests.json       Tracked base image digests
│   ├── apt-versions.json             Recorded apt versions (per PG major)
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml            Bug report form
│   │   ├── new_extension.yml         Extension request form
│   │   └── config.yml                Template chooser config
│   └── workflows/
│       ├── build-push.yml            CI: builds extensions, pushes to GHCR
│       ├── test.yml                  CI: full test suite (PG 17, 18, 19)
│       ├── monitor-base-image.yml    Detects base image updates (every 6h)
│       ├── monitor-extensions.yml    Detects new source-build releases
│       ├── monitor-apt-versions.yml  Tracks apt versions (apt-versions.json)
│       └── cache-cleanup.yml         Prunes stale GHA caches
├── extensions/
│   ├── pgvector/                     APT extension: conf + test only
│   │   ├── extension.conf            Metadata (APT_PACKAGE, license, ...)
│   │   └── test.sql                  Integration tests (PASS/FAIL assertions)
│   ├── pg_net/                       Source-built: adds its own Dockerfile
│   ├── postgis/                      Custom APT Dockerfile (bundles libs)
│   ├── ... (80+ extensions)
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
(PostgreSQL, MIT, ISC, Zlib, Apache-2.0, the BSD family, plus the safe
weak/file-level copyleft MPL-2.0 and permissive-classified Artistic-2.0)
and, where industry practice clearly supports it, **GPL-2.0 extensions
loaded via PostgreSQL's dynamic extension mechanism**.

The policy is codified in [`scripts/licenses.conf`](scripts/licenses.conf)
and enforced automatically by `make check-licenses` in CI: source-available
licenses (BSL/BUSL, SSPL, FSL, Elastic-2.0/ELv2) and infectious copyleft
(GPL/LGPL/AGPL) are denied, with `postgis` and `pgrouting` recorded as
documented, deliberate exceptions. Every extension's license is
auto-detected from its Debian copyright when it is added (see the
[Contributing guide](CONTRIBUTING.md#licensing)).

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

## FAQ

### How does pglayers work?

Each extension is built as a minimal `FROM scratch` Docker image containing
only the extension's files (shared libraries, control files, SQL scripts).
These images are not runnable containers -- they are filesystem layers.

When you write:
```dockerfile
COPY --from=ghcr.io/pglayers/pgx-pgvector:17 / /
```

Docker copies the extension files into the official `postgres` image at
exactly the right paths (`/usr/lib/postgresql/17/lib/`,
`/usr/share/postgresql/17/extension/`). PostgreSQL discovers them and
you can `CREATE EXTENSION`. No compilation, no package manager, no
runtime dependencies to resolve -- just file copies stacked on top of
the official image.

### Why is version X of extension Y not available?

pglayers follows a deliberate version policy. We prefer stability and
reproducibility over bleeding-edge releases, using this priority order:

1. **PGDG APT packages** (preferred) -- Most extensions are installed
   from the official PostgreSQL APT repository (`apt.postgresql.org`).
   The version you get is whatever the PGDG maintainers have packaged.
   This is typically the latest stable release, but may lag a few days
   or weeks behind upstream.

2. **Source builds** (fallback) -- Extensions not available in PGDG are
   compiled from source at the latest stable release tag.

If the PGDG repository ships an older version than upstream, we ship
that older version. This is intentional: PGDG packages are tested
against the corresponding PostgreSQL release, receive security patches
through the same channel, and are guaranteed to be ABI-compatible.
We only override this if there is a critical bug fix or security issue
in a newer release that PGDG has not yet packaged.

### Why is my extension not included?

Possibly one of:

- **License** -- pglayers only ships extensions with permissive
  open-source licenses (PostgreSQL, MIT, BSD, Apache 2.0, ISC). We
  exclude proprietary, source-available (BSL, SSPL, FSL, ELv2), and
  strong copyleft (AGPL) licenses. We also exclude extensions that
  require proprietary runtime dependencies (e.g., Oracle client).
  See the [Licensing policy](#licensing-policy) section for details.

- **Not yet contributed** -- We welcome contributions! To add a new
  extension, see the [Contributing guide](CONTRIBUTING.md) for the
  full checklist, Dockerfile patterns, and test requirements.

### Why is there no package for my PostgreSQL version?

Extension availability per PostgreSQL version depends on upstream
support:

- **APT-based extensions** -- Available when the PGDG repository
  publishes a package for that PG version. New major PG versions
  (e.g., PG 19 during beta) may not have all packages yet.

- **Source-built extensions** -- Available when the extension compiles
  cleanly against that PG version's headers.

If an extension you need doesn't support your PG version yet, you can
contribute by following the [Contributing guide](CONTRIBUTING.md).

## Acknowledgements

This project stands on the shoulders of the PostgreSQL community:

- The [PostgreSQL Global Development Group](https://www.postgresql.org/community/) for building the best open-source database
- The [PGDG APT Repository](https://apt.postgresql.org/) maintainers who package and distribute extensions for Debian and Ubuntu
- The [Official PostgreSQL Docker image](https://hub.docker.com/_/postgres) maintainers for providing reliable, well-configured base images
- The [Debian PostgreSQL team](https://wiki.debian.org/PostgreSql) for their packaging work that makes all of this possible
- Every extension author who releases their work under permissive open-source licenses

pglayers is a thin layer of automation on top of their work. Without the quality and consistency of the upstream ecosystem, this project would not exist.

## License

[MIT](LICENSE)
