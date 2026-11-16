# PostgreSQL 19 extension evaluation

## Outcome

Enabled nine additional extensions for PG19, increasing project availability
from 53 to **62 of 84 extensions**. Each successful extension has its own
commit, including its README row and any necessary build/test changes.
All rebuilt layers passed the complete PG17, PG18, and PG19 RC2 layer suites
on amd64. The full PG19 profile passed startup and functional checks with all
62 available extensions included and none missing.

`pg_duckdb` remains disabled because its required upstream PG19 image is not
published. No failing enablement attempt was committed, and no commits or
images were pushed.

## Plan

Evaluate against the PG19 base resolved by `scripts/pg-tag.sh`. Keep the
latest stable upstream release pinned; backport small, documented compatibility
fixes instead of pinning development branches. Do not enable an extension just
because its upstream CI mentions PG19.

1. Enable the already-buildable candidates: `pg_clickhouse`, `pg_incremental`,
   and `pg_net`.
2. Evaluate the small compatibility fixes for `pg_bigm`, `pg_stat_monitor`,
   `pg_textsearch`, and `temporal_tables`.
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

All candidates started disabled for PG19 in the project configuration. The
stable upstream extension pins are unchanged; the compatibility work is
carried explicitly in the build where necessary.

| Extension | Stable release | Status | Commit | Evaluation |
|-----------|----------------|--------|--------|------------|
| anon | 3.3.2 | Enabled | `322946a` | Upgrade cargo-pgrx and compatible pgrx dependencies to 0.19.4 for RC2 bindings and the composite-datum security fix; configure PGDG's prerelease component. Three SQL checks include actual partial masking. |
| pg_bigm | v1.2-20250903 | Enabled | `700f775` | Backport upstream PG19 locale, buffer-lock, and TupleDesc APIs. Four SQL checks cover ASCII/CJK matching, GIN search, similarity, and pending-list statistics. |
| pg_clickhouse | 0.11.1 | Enabled | `fa7d942` | Use the published PG19 image; align the Dockerfile default and make the SQL test create its extensions independently. Three checks cover FDW registration, server validation, and re2 pushdown. |
| pg_duckdb | v1.2.0 | Blocked | — | Confirmed build failure: upstream `pgduckdb/pgduckdb:19-v1.2.0` is not published. Keep disabled; a new source-build path is a separate change. |
| pg_incremental | v1.6.1 | Enabled | `c7ecda6` | Enable the existing stable release. All five functional checks pass, including sequence/time pipelines and pg_cron scheduling. |
| pg_net | v0.20.5 | Enabled | `e440572` | Enable the existing stable release and align the Dockerfile default. Four checks include actual asynchronous worker queue consumption and error-response recording without an external HTTP service. |
| pg_stat_monitor | 2.4.0 | Enabled | `d1b0835` | Backport upstream removal of the reverted PG19 property-graph API. Three checks require real collected query statistics and exercise relation hooks through a view. |
| pg_textsearch | v1.5.1 | Enabled | `c172da3` | Add the missing limits.h include on PG19 and align the Dockerfile default. All four BM25/index/ranking checks pass. |
| plv8 | v3.2.5 | Enabled | `b25caba` | Build V8 from source and validate the existing PG19 support; align Dockerfile and V8-cache workflow defaults. All three JavaScript, JSON, and array checks pass. |
| temporal_tables | v1.2.2 | Enabled | `4e10f6c` | Add the explicit hash-table include and adapt both allocator declaration and definition to PG19. Three checks cover cross-transaction update/delete history and cache reuse. |

The upstream backports are
[pg_bigm a858f4bb55](https://github.com/pgbigm/pg_bigm/commit/a858f4bb552317b2a279920989af41499456ae29)
and
[pg_stat_monitor 293096b428](https://github.com/percona/pg_stat_monitor/commit/293096b42894a7e3196470c10ccd8171375adc3a).
The four C compatibility patches are applied only for PG19; remove or update
them when a later stable release incorporates the fixes. Anon's pgrx 0.19.4
update also rebuilds PG17/18 against their patched headers; pgrx 0.20 is not
used because it requires a larger upstream API migration.

## Validation environment

Evaluation date: 2026-11-16. Local Docker/BuildKit supports native amd64 only;
no arm64 emulator is configured. The existing CI native arm64 builds remain
necessary before release. No images are pushed by this evaluation.

The unmodified baseline passed the complete layer suite on all supported
PostgreSQL versions:

| PostgreSQL | Passed | Failed | Warnings |
|------------|-------:|-------:|---------:|
| 17 | 3824 | 0 | 0 |
| 18 | 254 | 0 | 2 |
| 19 RC2 | 164 | 0 | 0 |

The final complete layer-suite results are:

| PostgreSQL | Passed | Failed | Warnings |
|------------|-------:|-------:|---------:|
| 17 | 3824 | 0 | 0 |
| 18 | 254 | 0 | 2 |
| 19 RC2 | 191 | 0 | 0 |

The PG18 warnings are unchanged from the baseline: the known SQL-level
collision involving `pgnodemx`'s `fips_mode()` function in the combined
database and its skipped integration test. They are not missing shared
libraries or a server crash.

The full PG19 profile includes **62/62 extensions**, with **65 passed and zero
failed** profile checks. Its startup log is clean, every extension's SQL test
passes, the pg_lake companion executes a DuckDB query, and no server crash is
detected. This additionally caught and fixed pg_clickhouse's SQL test relying
on a preceding CREATE EXTENSION step that the profile runner does not supply.

License checks (84 accepted), profile membership, shellcheck, and YAML parsing
of the V8-cache workflow all pass. Source whitespace is checked separately
from unified-diff patch context, whose leading spaces/tabs are intentional;
patch syntax is checked and every backport is applied during the real builds.

### Reproduce the final validation

```bash
for pg in 17 18 19; do
    for ext in anon pg_bigm pg_clickhouse pg_incremental pg_net \
        pg_stat_monitor pg_textsearch plv8 temporal_tables; do
        make build REGISTRY=local PG="$pg" EXT="$ext" || exit 1
    done
    make test REGISTRY=local PG="$pg" || exit 1
done

make image REGISTRY=local PG=19 PROFILE=full \
    IMAGE_NAME=pglayers-pg19-evaluation-full
make test-image REGISTRY=local PG=19 PROFILE=full \
    IMAGE_NAME=pglayers-pg19-evaluation-full
make check-profiles check-licenses
shellcheck -x scripts/pg-tag.sh tests/test-layers.sh tests/test-image.sh
```

## Deferred extensions

The audit found no PG19 Cargo feature in the current stable releases of
`pg_durable`, `pg_graphql`, `pg_jsonschema`, `pgvectorscale`, or `wrappers`.
These need upstream ports, not just another `VERSION_19` field. DocumentDB's
current release does not provide the PG19 package consumed by its Dockerfile.

The configured PGDG repository does not currently provide PG19 packages for
`age`, `db2fce`, `first_last_agg`, `jsquery`, `periods`, `pg_failover_slots`,
`pgnodemx`, `pg_similarity`, `pgsphere`, `pljs`, `plprofiler`, `prioritize`,
`rum`, `tds_fdw`, or `timescaledb`, on either amd64 or arm64. Their APT-based
builds remain unchanged; the existing APT monitor will detect new packages.
