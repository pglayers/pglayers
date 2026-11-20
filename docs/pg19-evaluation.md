# PostgreSQL 19 extension evaluation

## GA transition: local validation passed, CI pending

PostgreSQL [19.0 was released on November 19, 2026](https://www.postgresql.org/about/news/postgresql-19-released-3449/).
The evaluation results below are from RC2, not the GA release.

The prepared GA changes select `postgres:19`, remove prerelease retagging and
rollover automation, and make PG19 build, test, promotion, and profile failures
blocking, like PG17 and PG18. They do not enable additional extensions.

On November 20, 2026, Docker Hub published the official `postgres:19` GA
image. Both `linux/amd64` and `linux/arm64/v8` manifests are present. A local
pull reports `postgres (PostgreSQL) 19.0 (Debian 19.0-1.pgdg13+1)`.

The verified multi-architecture manifest digest is
`sha256:bb6e70add742cd868fb62cb3b2f67d1dd2bdd2b65a521e778420748753687c60`.
It is recorded in `.github/base-image-digests.json`, using the monitor's
exact raw-manifest hashing. Fresh PGDG discovery still resolves 62 of 84
extensions on amd64; the APT snapshot now records pgAudit 19.0 (and 17.2/18.1).
All 46 configured PG19 APT packages were also found in the arm64 package
index. This verifies package availability, not native arm64 build/runtime
correctness; those builds still need the existing CI matrix.
Keep the prerelease compatibility guard in `scripts/apt-support.sh`: mixing
an RC server with GA extension packages is not a safe workaround.

The GA follow-up adds running-server major/release checks to the layer and
profile suites, makes supported-layer build failures fatal rather than
silently skipping them, and adds Docker-free regressions for both gates.
CI tests the PG19 full profile (including a complete-manifest assertion),
alongside all Azure profiles, and expands Kubernetes/CNPG integration to PG19.
Extensions that still lack upstream support remain disabled; the required
`pgduckdb/pgduckdb:19-v1.2.0` image was rechecked and is still absent.
The recent `pg_bigm` v1.2-20261118 release already includes the PG19 backport,
so its obsolete local patch is removed. Its Dockerfile default, pgmq's default,
and the README now match the recent stable pins. README PG19 availability
also matches the current APT package discovery.

Completed local checks: `make test-harness`, `make check-profiles`,
`make check-licenses` (84 accepted), shellcheck for all changed shell files,
actionlint for `ci.yml`, and parsing of all workflow YAML. The profile matrix
was checked for both all-major and single-major dispatches. The new server
identity gate also passes against a real `postgres:19` container and rejects
an incorrect expected major. All 62 available PG19 layers have rebuilt
successfully against GA, and complete local layer suites pass on PG17/18/19.
Both PG19 profiles and the PG18/19 integration suites below also pass.
Native arm64 and final GitHub CI validation remain required before merging.

The initial PG19 Kubernetes ImageVolume run passed all 18 checks. It exposed
a separate CNPG harness bug: the operand was hardcoded to PG18, producing an
undefined-symbol error when it loaded PG19's pg_cron. The follow-up uses the
official resolved GA image with its actual PostgreSQL UID/GID, and asserts
the operand and running cluster major. This avoids depending on the not-yet-
published `ghcr.io/cloudnative-pg/postgresql:19-minimal-trixie` image. A second
harness fix normalizes Docker shorthand image names to canonical CRI references
before verifying k3d imports, and retains import diagnostics on failure.
The fixed CNPG suites pass on both PG18 and PG19, and the PG19 Kubernetes
ImageVolume suite passes with the running-major assertion enabled.

### Completed GA profile results

| Profile | Included extensions | Passed | Failed |
|---------|--------------------:|-------:|-------:|
| Azure, PostgreSQL 19.0 | 24/24 | 27 | 0 |
| Full, PostgreSQL 19.0 | 62/62 | 66 | 0 |

Both profile results follow fresh GA layer rebuilds, complete-manifest
assertions and `make test-image`. All included extension SQL tests pass,
startup logs contain no warnings/errors, the running server reports PG19 GA,
and the server-crash gate passes. The full profile additionally verifies that
the pg_lake companion executes a DuckDB query.

### Completed GA integration results

| Integration | PostgreSQL | Passed | Failed |
|-------------|------------|-------:|-------:|
| CloudNativePG | 18 GA | 19 | 0 |
| CloudNativePG | 19 GA | 19 | 0 |
| Kubernetes ImageVolume | 19 GA | 19 | 0 |

These local runs use the official GA images and native amd64 layers. CNPG
bootstraps successfully with the operand's actual PostgreSQL UID/GID. Both
integration harnesses verify the running server major, load pgvector,
pg_cron and PostGIS, exercise their functions, and check contrib discovery.
Docker-free regression tests cover canonical CRI names and preserve failure
gating when an imported image is absent.

### Final-harness layer results

| PostgreSQL | Passed | Failed | Warnings |
|------------|-------:|-------:|---------:|
| 17 GA | 3825 | 0 | 0 |
| 18 GA | 255 | 0 | 2 |
| 19 GA | 192 | 0 | 0 |

These runs use the final version-check/build-failure gates and refreshed
pgAudit 17.2/18.1 layers. PG18's two warnings are the unchanged `pgnodemx`
SQL-level `fips_mode()` collision and its skipped combined integration test,
not an ABI failure or server crash. The PG19 suite tests all 62 available GA
layers, including standalone dependency resolution, cross-layer isolation,
extension loading, functional SQL, the running GA major, and crash detection.
The local layer suites ran sequentially to avoid shared Docker container-name
collisions; GitHub's PG-version jobs run on separate runners.

Before merging the GA transition:

- Rebuild available PG19 layers against GA. Run the complete layer suites for
  PG17, PG18, and PG19, plus PG19 `full` and `azure` profile startup and
  functional tests. Require successful native amd64 and arm64 builds in CI.
- Update branch protection to require `Test PG 18` and `Test PG 19` alongside
  `Test PG 17`, plus the profile and integration checks (including
  `Test profile full (PG 19)`). On November 20, only `Test PG 17` is required;
  a failed PG19 test can otherwise leave auto-merge eligible even though the
  workflow fails. Repository settings are not changed by this patch.
- Record the GA results separately from the historical RC2 results below.

Keep the GA work on the dedicated `pg19-ga` branch, not the monitor-managed
`auto/base-image-update` branch. Scheduled monitor runs recreate the latter
from `main` and can overwrite manual additions.

### Reproduce the GA validation

```bash
docker pull postgres:19
make build-all REGISTRY=local PG=19
for pg in 17 18 19; do
    make test REGISTRY=local PG="$pg" || exit 1
done

for profile in full azure; do
    make image REGISTRY=local PG=19 PROFILE="$profile" || exit 1
    docker run --rm --entrypoint cat "pglayers-${profile}:19" \
        /etc/pglayers/manifest.json \
        | jq -e '.missing == [] and .count == .total and .count > 0' || exit 1
    make test-image REGISTRY=local PG=19 PROFILE="$profile" || exit 1
done

# Requires k3d and kubectl; validates mounted isolated GA layers.
make test-k8s REGISTRY=local PG=19
make test-cnpg REGISTRY=local PG=19
```

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

### Azure profile: seven missing extensions rechecked on November 20

The Azure profile has 31 members available on PG17/18 and 24 available on
PG19. Fresh amd64 and arm64 PGDG probes still have no PG19 package for any
of the six package-dependent missing extensions below. Upstream source
compatibility is not the same as an available, validated pglayers layer.

| Extension | Latest relevant version | PG19 evidence / remaining blocker |
|-----------|-------------------------|-----------------------------------|
| age | `PG19/v1.8.0-rc0` | The tag exists, but its [RELEASE](https://github.com/apache/age/blob/PG19/v1.8.0-rc0/RELEASE) explicitly calls it a beta based on PG19beta1. No PG19 release is published in Apache's stable download directory, and there is no PGDG package. Not a verified GA-compatible stable release. |
| documentdb | `v1.2-0` | [Release packages](https://github.com/documentdb/documentdb/releases/tag/v1.2-0) cover PG17/18; the gateway's Cargo features stop at PG18 and use pgrx 0.16.0. No PG19 package; needs an upstream gateway port as well. |
| pg_duckdb | `v1.2.0` | The [release](https://github.com/duckdb/pg_duckdb/releases/tag/v1.2.0) includes PG19 compatibility fixes, but is explicitly experimental. Its binary assets stop at PG18 and `pgduckdb/pgduckdb:19-v1.2.0` remains absent. The existing pinned version has PG19 source work; a new source-build path still needs validation. |
| pg_failover_slots | `v1.2.1` tag (`v1.2.0` latest GitHub release) | The tagged source still has the pre-PG19 slot/database APIs. [PG19 fixes, PR #68](https://github.com/EnterpriseDB/pg_failover_slots/pull/68), remain open. No compatible release/package found. |
| rum | `1.3.15` | The [latest release](https://github.com/postgrespro/rum/releases/tag/1.3.15) supports PG18. PG19 changes exist on master (including TupleDesc finalization), but are absent from the tag; no newer release or PG19 package. Do not mistake closed-but-unmerged PR #180 for a merged release fix. |
| tds_fdw | `v2.0.5`; `2.0.6` pending | [PG19 signal-handler fixes](https://github.com/tds-fdw/tds_fdw/pull/422) are merged, but [the 2.0.6 release PR](https://github.com/tds-fdw/tds_fdw/pull/447) is still open and no 2.0.6 tag or PG19 package exists. |
| timescaledb | `2.32.1` | The November 19 [release](https://github.com/timescale/timescaledb/releases/tag/2.32.1) fixes issues on supported PG16/17/18 minors. Its CMake compatibility guard still rejects PG19 unless experimental checks are bypassed; no supported PG19 release/package. |

No extension is enabled by this audit. The existing APT monitor will discover
packages when PGDG publishes them. RUM/tds_fdw source backports and pg_duckdb's
source-build path would be separate build/runtime validation work, not simple
version-field additions.

The audit found no PG19 Cargo feature in the current stable releases of
`pg_durable`, `pg_graphql`, `pg_jsonschema`, `pgvectorscale`, or `wrappers`.
These need upstream ports, not just another `VERSION_19` field. DocumentDB's
current release does not provide the PG19 package consumed by its Dockerfile.

The configured PGDG repository does not currently provide PG19 packages for
`age`, `db2fce`, `first_last_agg`, `jsquery`, `periods`, `pg_failover_slots`,
`pgnodemx`, `pg_similarity`, `pgsphere`, `pljs`, `plprofiler`, `prioritize`,
`rum`, `tds_fdw`, or `timescaledb`, on either amd64 or arm64. Their APT-based
builds remain unchanged; the existing APT monitor will detect new packages.
