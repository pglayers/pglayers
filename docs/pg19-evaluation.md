# PostgreSQL 19 extension evaluation

## Plan

Evaluate against the PG19 base resolved by `scripts/pg-tag.sh`. Keep the
latest stable upstream release pinned; backport small, documented compatibility
fixes instead of pinning development branches. Do not enable an extension just
because its upstream CI mentions PG19.

1. Enable the already-buildable candidates: `pg_clickhouse`, `pg_incremental`,
   and `pg_net`.
2. Evaluate the small compatibility fixes for `pg_textsearch`, `pg_bigm`,
   `pg_stat_monitor`, and `temporal_tables`.
3. Evaluate the heavier/toolchain-dependent candidates: `anon` and `plv8`.
4. Recheck `pg_duckdb`'s missing PG19 artifact. Keep it disabled unless the
   project's prebuilt-image build can be supported reproducibly.
5. For each successful candidate, update its configuration, README row,
   Dockerfile when needed, and functional SQL coverage together. Existing
   profile membership remains unchanged.
6. Rebuild changed layers and run `make test REGISTRY=local PG=<major>` for
   PostgreSQL 17, 18, and 19. This includes collision/overwrite checks on PG17,
   standalone dependency checks, cross-layer isolation, CREATE EXTENSION, and
   functional SQL tests. Run focused candidate tests during development, then
   the complete extension set before accepting the changes.
7. Check licenses, profiles, shell scripts, and whitespace. Check arm64 builds
   when the local builder supports them; otherwise record the limitation and
   leave the existing native arm64 CI matrix as the required release check.
8. Commit each passing extension independently, including its documentation
   and tests. Do not commit failing enablement attempts or publish images.

## Results

All candidates start disabled for PG19 in the project configuration.

| Extension | Stable release | Status | Evaluation |
|-----------|----------------|--------|------------|
| anon | 3.3.2 | Pending | Align pgrx tooling and evaluate the existing PG19 feature against RC2. |
| pg_bigm | v1.2-20250903 | Pending | Evaluate the upstream PG19 compatibility backport. |
| pg_clickhouse | 0.11.1 | Pending | Upstream PG19 image exists for amd64 and arm64. |
| pg_duckdb | v1.2.0 | Pending | Source supports PG19, but the upstream PG19 Docker image is missing. |
| pg_incremental | v1.6.1 | Pending | Audit build and functional tests passed on RC2. |
| pg_net | v0.20.5 | Pending | Audit build and existing SQL checks passed on RC2; strengthen worker coverage. |
| pg_stat_monitor | 2.4.0 | Pending | Evaluate upstream removal of the reverted PG19 property-graph API. |
| pg_textsearch | v1.5.1 | Pending | Audit passed with an explicit limits.h include. |
| plv8 | v3.2.5 | Pending | Upstream CI includes PG19; evaluate the cached V8 build. |
| temporal_tables | v1.2.2 | Pending | Evaluate explicit hash-table includes and the PG19 allocator signature. |

## Deferred extensions

The audit found no PG19 Cargo feature in the current stable releases of
`pg_durable`, `pg_graphql`, `pg_jsonschema`, `pgvectorscale`, or `wrappers`.
These need upstream ports, not just another `VERSION_19` field. DocumentDB's
current release does not provide the PG19 package consumed by its Dockerfile.

The configured PGDG repository does not currently provide PG19 packages for
`age`, `db2fce`, `first_last_agg`, `jsquery`, `periods`, `pg_failover_slots`,
`pg_similarity`, `pgnodemx`, `pgsphere`, `pljs`, `plprofiler`, `prioritize`,
`rum`, `tds_fdw`, or `timescaledb`, on either amd64 or arm64. Their APT-based
builds remain unchanged; the existing APT monitor will detect new packages.
