# Project Agent Instructions

## pglayers

Composable PostgreSQL extension Docker layers on top of official images.

## Licensing Policy

This project only ships extensions with **permissive (or safe
weak-copyleft) licenses**. The policy is codified in
`scripts/licenses.conf` and enforced automatically by
`make check-licenses` (run in CI):

- **`ALLOW_LICENSES`** -- auto-accepted: PostgreSQL, MIT, ISC, Zlib,
  Apache-2.0, the BSD family, plus safe weak/file-level copyleft (MPL-2.0)
  and permissive-classified (Artistic-2.0). Safe because extensions are
  separate `.so` files loaded at runtime, never statically linked into a
  combined derivative work.
- **`DENY_LICENSES`** -- never accepted: source-available (BSL/BUSL, SSPL,
  FSL, Elastic-2.0/ELv2) and infectious copyleft (AGPL, GPL, LGPL).
- **`LICENSE_EXCEPTIONS`** -- deliberate, documented deviations from the
  deny list (currently `postgis` and `pgrouting`, GPL geospatial
  extensions loaded at runtime -- mere aggregation, not derivative). Each
  exception records a rationale for the audit trail.

When adding an extension:

1. **Set the `LICENSE` field** in `extension.conf` (e.g.
   `LICENSE="PostgreSQL"`). The value must resolve to `ALLOW_LICENSES`
   (after alias normalization) or be recorded as an exception, or
   `make check-licenses` fails. Debian ships a machine-readable DEP-5
   copyright file per package
   (`/usr/share/doc/postgresql-<pg>-<pkg>/copyright`) you can consult to
   determine the license.

2. **A denied or unknown license fails CI.** To ship a denied license
   anyway (rare), add an entry to `LICENSE_EXCEPTIONS` **and**
   `LICENSE_EXCEPTION_REASON` in `scripts/licenses.conf` with a written
   justification.

3. **When in doubt, skip it** -- If an extension's license is ambiguous
   or has changed recently (e.g., TimescaleDB moved to TSL for some
   features), do not include it until the licensing is verified.

Extensions we explicitly exclude:
- **oracle_fdw** -- requires proprietary Oracle Instant Client
- Any extension under BSL/SSPL/FSL/ELv2 or similar delayed-open licenses

## Version Policy

**APT-based extensions have no `VERSION_XX` fields.** Their version is
whatever `apt.postgresql.org` (PGDG) currently ships: the build resolves
it at build time (`scripts/apt-support.sh` / `scripts/ext-version.sh`),
availability is probed per PG major (an extension "supports" a PG version
iff PGDG publishes `postgresql-<pg>-<pkg>`), and `apt-get` always installs
the latest patch. So there is nothing to bump -- do **not** add
`VERSION_XX` to an APT extension.

**Source-built extensions** pin the upstream git tag. Always use the
**latest stable release** compatible with our supported PostgreSQL
versions (currently 17, 18, and 19). When a new upstream release is
published:

1. Update `VERSION_17`, `VERSION_18`, and `VERSION_19` in `extension.conf`.
2. Update the `ARG EXT_VERSION` default in the Dockerfile.
3. Run `make test REGISTRY=local PG=17`, `PG=18`, and `PG=19`.
4. Update the README if the version appears in any examples.

Do not pin to old versions unless the latest has a known incompatibility
or license change. Stale versions are a bug.

## Testing Requirements

When adding new extensions or modifying existing ones, **always run the
layer collision and overwrite tests** before merging:

```bash
make test REGISTRY=local PG=17
```

This test suite validates:

1. **No file collisions between extension layers** (PG 17 only; the
   isolated layout on PG 18+ eliminates this structurally) -- If two
   extensions install a file at the same path, the last `COPY --from`
   silently overwrites the first. This can break extensions at runtime
   with no warning from Docker. The test compares file lists across all
   extension pairs and fails on any overlap.

2. **No base image overwrites** (PG 17 only; isolated layout on PG 18+
   installs into a separate `/extensions/` namespace) -- Extensions must
   not replace files already present in the official `postgres:XX` image
   (shared libs, config files, binaries). The test diffs each extension's
   file list against the base image.

3. **No missing shared library dependencies** -- Runs `ldd` on every
   `.so` in the combined image. Catches transitive runtime deps that
   weren't bundled (e.g., PostGIS needing libtiff via libproj).

4. **Self-containment** -- Overlays each extension on the *bare* base
   image alone (no sibling layers) and runs `ldd` on every ELF object it
   ships. An extension must resolve all of its own runtime deps without
   help from any other layer (e.g. `pg_net` must bundle its own
   `libcurl.so.4`, not borrow postgis's). See Dockerfile requirement #8.

5. **All extensions load** -- `CREATE EXTENSION` must succeed for every
   extension in the combined image.

6. **Functional smoke tests** -- Basic operations per extension to catch
   runtime failures that CREATE EXTENSION alone wouldn't surface.

### When to run tests

- Before committing any change to `extensions/*/Dockerfile`
- Before committing any change to `extensions/*/extension.conf`
- When bumping extension versions
- When adding a new extension
- When changing the base PG version

Tests **must pass for all supported PostgreSQL versions** (currently 17,
18, and 19). Run:

```bash
make test REGISTRY=local PG=17
make test REGISTRY=local PG=18
make test REGISTRY=local PG=19
```

All must pass before merging. An extension that builds on one PG
version but fails on another is not acceptable -- either fix it for
all supported versions or remove the unsupported version from
`extension.conf`.

### Common collision scenarios to watch for

> **Note:** For PG 18+, collisions are **structurally impossible** due to
> the isolated layout (each extension has its own `/extensions/<name>/`
> namespace). The scenarios below only apply to PG 17 (classic layout).

- Two extensions bundling the same runtime shared library at different
  versions (e.g., both PostGIS and pgRouting shipping libgeos)
- Extensions that install CLI tools with generic names in `/usr/local/bin`
- LLVM bitcode index files in `/usr/lib/postgresql/XX/lib/bitcode/`
- Shared PROJ data files across geo extensions

### Adding a new extension checklist

For an **APT-based** extension, you usually only need an
`extensions/<ext>/extension.conf` with `APT_PACKAGE` set (no Dockerfile --
the shared `Dockerfile.apt` handles it; see Dockerfile requirement #3).
Source-built or special-case extensions add their own
`extensions/<ext>/Dockerfile`.

The fastest way to add an APT extension is the scaffold:

```bash
make add-apt-ext PKG=<apt-package> [NAME=<dir>] [PG=17]
```

It probes PGDG for availability + version, detects the license from the
Debian DEP-5 copyright (`scripts/detect-license.sh`), auto-fills the
description, writes `extensions/<name>/extension.conf`, and runs
`make check-licenses`. If the license is denied or undetected it stops and
asks you to decide (fix `LICENSE`, extend `ALLOW_LICENSES`, or record an
exception). You still add test coverage (below) and review the conf.

Every new extension **must** have full test coverage before merging.
This means updating `tests/test-layers.sh` to include:

1. **Extension name mapping** -- Add an entry to `EXT_SQL_NAMES` if the
   SQL extension name differs from the directory name (e.g.,
   `[pgvector]="vector"`).

2. **CREATE EXTENSION test** -- Automatically covered for all extensions
   in the `EXTENSIONS` list. If the extension is not loadable via
   `CREATE EXTENSION` (e.g., logical decoding output plugins like
   wal2json), add it to `SKIP_CREATE_EXT` instead.

3. **Functional smoke test** -- Add a `smoke_test` call that exercises
   the extension's core functionality (not just loading). Examples:
   - Data type creation/cast
   - A function call that returns a result
   - An operator or index operation
   The smoke test must produce non-empty output on success.

4. **shared_preload_libraries** -- If the extension requires preloading,
   add `SHARED_PRELOAD="<library>"` to `extension.conf`. Phase 5 of
   `test-layers.sh` auto-generates the `shared_preload_libraries` line
   from this field for both classic (PG 17) and isolated (PG 18+)
   layouts.

5. **Integration test file** -- Create `extensions/<name>/test.sql` with
   multi-step validation. Each test outputs a line starting with `PASS`
   or `FAIL`. Format:
   ```sql
   SELECT CASE
       WHEN <condition>
       THEN 'PASS <ext_name>: <description>'
       ELSE 'FAIL <ext_name>: <description>'
   END;
   ```
   Tests must be self-contained (create own tables, clean up after).
   Aim for 2-4 checks per extension covering:
   - Core data type or function works
   - Index or operator behavior
   - Integration with other PG features (e.g., triggers, aggregates)

The collision, overwrite, and ldd checks are automatic for all
extensions in the `extensions/` directory -- no manual update needed
for those. (Collision and overwrite checks are skipped for PG 18+ since
the isolated layout eliminates them by design.)

### Version monitoring

**APT-based extensions are not version-monitored** -- they carry no
`VERSION_XX` and `apt-get` installs the latest PGDG package on every
rebuild, so `monitor-extensions.yml` skips them automatically (no
`TAG_FILTER` needed). The rest of this section applies to **source-built**
extensions only.

Every source-built extension **must** be handled by the version
monitoring workflow (`.github/workflows/monitor-extensions.yml`). When
adding a new source-built extension:

1. **Standard semver tags** (e.g., `v1.0.0`, `1.0.0`) -- No action
   needed. The workflow detects these automatically via the GitHub
   Releases API.

2. **Non-standard tag formats** (e.g., `REL2_4_7`, `ver_1.5.3`,
   `VERSION_4_16_7`) -- Add a `TAG_FILTER` field to `extension.conf`
   with a regex matching valid tags for this extension:
   ```bash
   TAG_FILTER="^REL"
   ```
   For PG-version-coupled tags (e.g., `REL17_1_7_1`), use `${PG}` as
   a placeholder:
   ```bash
   TAG_FILTER="^REL${PG}_"
   ```

3. **No tagged releases** (pinned to `main`/`master`) -- Add the
   extension name to the `SKIP_MONITOR` list in the workflow. These
   extensions cannot be version-monitored automatically.

4. **GitLab-hosted repos** -- Automatically detected from the `REPO`
   URL. The workflow uses the GitLab Releases API instead of GitHub.

5. **Profile membership** -- If the extension is available in a managed
   PostgreSQL service (e.g., Azure), add it to the appropriate profile
   in `profiles/`. Run `make check-profiles` to validate.

### Dockerfile requirements

Most APT extensions have **no Dockerfile** -- they use the shared
`Dockerfile.apt` (see requirement #3 below). The rules here apply to the
shared template and to any **custom** `extensions/<ext>/Dockerfile` (source
builds and special-case APT extensions).

Every extension Dockerfile **must** follow these practices:

1. **BuildKit syntax** -- Start with `# syntax=docker/dockerfile:1`.

2. **APT cache mounts** -- Use `--mount=type=cache` for APT to avoid
   re-downloading packages on rebuilds:
   ```dockerfile
   RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
       --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
       apt-get update && apt-get install -y --no-install-recommends ...
   ```
   Do NOT add `rm -rf /var/lib/apt/lists/*` (unnecessary with cache
   mounts and it defeats the caching).

3. **Prefer APT packages via the shared template** -- If the extension is
   available in the PGDG APT repository (`apt.postgresql.org`), install it
   via `apt-get` rather than compiling from source. This is faster, more
   reproducible, and automatically picks up security patches.

   **APT extensions do not need a Dockerfile.** The repo ships a single
   shared `Dockerfile.apt` that handles the entire APT pattern -- file
   extraction, generic runtime-dependency bundling, classic relocation +
   soname mangling, and the classic/isolated layout selection. To add an
   APT extension, create `extensions/<ext>/extension.conf` with
   `APT_PACKAGE="<package>"` set (no `postgresql-<pg>-` prefix, no version)
   and **no Dockerfile**. The Makefile routes any extension that lacks its
   own `extensions/<ext>/Dockerfile` to `Dockerfile.apt`, passing
   `APT_PACKAGE` and `EXT_NAME` as build args.

   The shared template is self-contained and collision-safe by
   construction (it bundles every non-base runtime dep and, for the
   classic layout, relocates + mangles them per requirement #8). For
   SQL-only extensions or extensions whose deps are all in the base image,
   the bundling/relocation stages are no-ops, so the output is identical to
   the old hand-written boilerplate.

   **Only write a custom `extensions/<ext>/Dockerfile` when the extension
   needs something the template can't express** -- e.g. multiple/renamed
   APT packages, `.control` update-alternatives symlinks, or extra build
   steps. A custom Dockerfile always overrides the template. Current custom
   APT Dockerfiles: `postgis` (postgis-3 + -scripts + control symlinks),
   `pgrouting`, `h3_pg`, `tds_fdw`, `http`.

4. **Source builds (when no APT package exists)** -- Strip `.so` files
   after `make install` to reduce image size (50-80% reduction):
   ```dockerfile
   RUN make -j"$(nproc)" && make install DESTDIR=/output \
       && find /output -name '*.so' -exec strip --strip-unneeded {} \;
   ```

5. **Minimal final image** -- The final stage uses `FROM ${LAYOUT}`
   which selects either `classic` (PG 17) or `isolated` (PG 18+). The
   Makefile passes `--build-arg LAYOUT=isolated` for PG >= 18.

6. **Layout selection stages** -- Every Dockerfile **must** include the
   layout selection pattern (classic + normalizer + isolated + FROM
   ${LAYOUT}) as the final stages. The `LAYOUT` build arg must be
   declared as a top-level ARG. BuildKit skips unused stages, so the
   normalizer stage adds zero overhead for PG 17 builds.

7. **Architecture-neutral** -- Dockerfiles must work on both `linux/amd64`
   and `linux/arm64` without modification. Do NOT hardcode architecture-
   specific paths like `/usr/lib/x86_64-linux-gnu/`. Use
   `dpkg-architecture -q DEB_HOST_MULTIARCH` if you need the multiarch
   tuple. APT packages and source builds (git clone + make) are
   inherently portable; only pre-built binary downloads need
   `TARGETARCH` handling.

8. **Extensions MUST always be self-contained** -- Every extension layer
   must carry *all* of its runtime shared-library dependencies that are
   not already present in the official `postgres:XX` base image. An
   extension must never rely on a *sibling* layer to provide a shared
   library (e.g. `http`/`pg_net`/`pg_duckdb` must not depend on `postgis`
   to supply `libcurl.so.4`). A layer must load successfully when overlaid
   on the bare base image with no other extension layers present.

   This is enforced by **Phase 5 of `tests/test-layers.sh`**, which
   overlays each extension on the bare base image alone and runs `ldd` on
   every ELF object it ships; any unresolved dependency fails the build.

   The two layouts satisfy self-containment differently:

   - **Isolated (PG 18+):** each extension lives in its own
     `/extensions/<ext>/lib` namespace, so bundled deps sit flat next to
     the extension `.so` and are found via the per-extension
     `dynamic_library_path` / `ld.so.conf.d` entry. Bundling every
     non-base dep (no skip lists) is sufficient -- collisions are
     structurally impossible.

   - **Classic (PG 17):** the flat overlay means every layer shares
     `/usr/lib/<multiarch>/`, so two extensions bundling the same soname
     (e.g. `libcurl.so.4`) at different versions would collide. Do **not**
     solve this by dropping the dep and delegating to a sibling layer --
     that breaks self-containment. Instead, **relocate** the bundled deps
     into an extension-private directory
     (`/usr/lib/postgresql/<pg>/lib/<ext>-deps/`) and point each ELF
     object's `RUNPATH` at it via `$ORIGIN` using `patchelf`. The private
     dir name is unique per extension, so there is no file collision, and
     the layer stays self-contained.

     A private dir + RUNPATH alone is **not** enough, though: sonames are
     process-global. In a combined image several extensions load into the
     same postgres backend, and if one (e.g. via `shared_preload_libraries`)
     loads its own `libssh2.so.1` first, another layer's `libcurl` -- or
     postgis's -- will bind to that already-loaded soname and may hit
     undefined symbols. So also **mangle each bundled dep's soname** with a
     per-extension prefix (`patchelf --set-soname pglx_<ext>_<soname>`,
     rename the file to match) and rewrite the `NEEDED` entries of every ELF
     object you ship (`patchelf --replace-needed`). Unique sonames make
     cross-layer symbol clashes impossible.

     See the `classic-relocate` stage in `extensions/http/Dockerfile`,
     `extensions/pg_net/Dockerfile`, `extensions/pg_duckdb/Dockerfile`, and
     `extensions/pg_lake/Dockerfile` for the reference pattern (the last
     also relocates and rewrites the `pgduck_server` binary via
     `$ORIGIN/../lib`).

   Never introduce a `skip-libs` list that omits a real runtime dependency
   in the hope that another layer provides it.

### Keeping documentation in sync

When adding, removing, or modifying extensions, **all of the following
must be updated in the same commit**:

1. **`README.md` "Available extensions" table** -- Add a row with the
   extension name (linked to its repo), PG versions, and description.
   Also update the `shared_preload_libraries` table if applicable.

2. **`README.md` "Configuration notes" section** -- If the extension
   requires any special configuration beyond `shared_preload_libraries`
   (e.g., environment variables, GUC parameters, init scripts, or
   runtime setup), document it in the README under "Configuration
   notes" with a dedicated subsection.

3. **`make list` output** -- This is automatic (driven by
   `extension.conf` files), but verify the description is concise and
   the PG version columns are correct.

4. **`tests/test-layers.sh`** -- As described above (name mapping,
   smoke test, shared_preload entry).

5. **`extension.conf` LICENSE field** -- Every extension must document
   its license. Run `make list` and verify the new extension appears.

6. **`extension.conf` DEPENDS field** -- If the extension requires
   another extension at runtime, add a `DEPENDS` field with a
   comma-separated list of SQL extension names (not directory names):
   ```bash
   DEPENDS="vector"           # pgvectorscale needs pgvector
   DEPENDS="postgis"          # pgrouting needs PostGIS
   DEPENDS="pgcrypto"         # pgjwt needs pgcrypto (contrib)
   ```
   The test suite reads this field to auto-install dependencies before
   running `CREATE EXTENSION`. Both pglayers extensions and built-in
   contrib extensions are valid values.

7. **`extension.conf` PG_CONF field** -- If the extension requires
   GUC settings in `postgresql.conf` beyond `shared_preload_libraries`,
   add a `PG_CONF` field with pipe-delimited config lines:
   ```bash
   PG_CONF="documentdb_gateway.database = 'postgres'|documentdb_gateway.setup_configuration_file = '/etc/documentdb/gateway_config.json'"
   PG_CONF="pg_durable.database = 'postgres'|pg_durable.worker_role = 'postgres'"
   ```
   These lines are appended to `postgresql.conf.sample` in both the
   test suite and combined profile images (`make image`). Use this for
   any GUC that the extension requires at startup (background worker
   config, database names, feature flags).

8. **`extension.conf` COMPANION_CMD field** -- If the extension
   requires a standalone background process running alongside
   PostgreSQL, add a `COMPANION_CMD` field:
   ```bash
   COMPANION_CMD="pgduck_server --cache_dir /tmp/pg_lake_cache"
   ```
   In combined profile images (`make image`), this generates an
   entrypoint wrapper (`/usr/local/bin/pglayers-entrypoint.sh`) that
   starts the process in the background before delegating to the
   standard postgres entrypoint. For individual layers, the extension
   should also include its own entrypoint script (e.g.,
   `/usr/local/bin/pg-lake-entrypoint.sh`). Use `COMPANION_CMD` only
   when the process cannot be a PostgreSQL background worker (e.g.,
   because it embeds a multi-threaded engine incompatible with
   PostgreSQL's process model).

Do not merge a PR that adds an extension to `extensions/` without
updating the README table and tests. Stale documentation is a bug.

### Ordering convention

All lists of extensions **must be sorted alphabetically** wherever they
appear:

- `README.md` "Available extensions" table
- `README.md` `shared_preload_libraries` table
- `tests/test-layers.sh` `EXT_SQL_NAMES` array
- `tests/test-layers.sh` `SKIP_CREATE_EXT` array
- `tests/test-layers.sh` smoke test calls

This ensures consistency, makes diffs readable, and avoids merge
conflicts when multiple extensions are added in parallel.

### Multi-architecture support

All extension images **must** support both `linux/amd64` and
`linux/arm64`. CI builds multi-arch manifest lists via QEMU emulation.

Rules:

1. **No hardcoded architecture paths** -- Never use
   `/usr/lib/x86_64-linux-gnu/` directly. Use
   `dpkg-architecture -q DEB_HOST_MULTIARCH` or let PGXS resolve paths
   via `pg_config`.

2. **Source builds are portable** -- `git clone` + `make` compiles
   natively for both architectures without modification.

3. **Binary downloads must use TARGETARCH** -- If an extension downloads
   a pre-built binary (rare), use the `TARGETARCH` build arg:
   ```dockerfile
   ARG TARGETARCH
   RUN curl -fsSL "https://example.com/bin-${TARGETARCH}.tar.gz" | tar xz
   ```

4. **Test on both architectures** when feasible -- At minimum, CI builds
   for both. The test suite runs on amd64; arm64 correctness is verified
   by the successful build + `ldd` check.

### GitHub Actions version policy

Always use the **latest major version** of all GitHub Actions in CI
workflows. Stale action versions are a bug (they miss security fixes,
performance improvements, and eventually break when GitHub deprecates
old Node.js runtimes).

Current minimum versions:

| Action | Version |
|--------|---------|
| `actions/checkout` | `@v7` |
| `docker/setup-qemu-action` | `@v4` |
| `docker/setup-buildx-action` | `@v4` |
| `docker/login-action` | `@v4` |
| `docker/build-push-action` | `@v7` |

When updating action versions:

1. Check the action's releases page for the latest major tag.
2. Update **all** workflow files that reference the action.
3. Verify CI passes after the update.

Do not pin to patch versions (e.g., `@v4.1.0`). Use the major tag
(e.g., `@v4`) which floats to the latest compatible release.

### Pre-commit checks

Before committing changes to shell scripts (`*.sh`), **always run
shellcheck**:

```bash
shellcheck tests/test-layers.sh tests/test-image.sh
```

Fix all errors and warnings before committing. Acceptable suppressions
(via `# shellcheck disable=SCXXXX`) must include a comment explaining
why the warning is inapplicable.

Common shellcheck issues to watch for:

- `SC2086` -- Word splitting on unquoted variables. Quote them.
- `SC2034` -- Unused variables. Remove or mark with `# shellcheck disable=SC2034`.
- `SC2155` -- Declare and assign separately to avoid masking return values.
- `SC2016` -- Single-quoted strings with expressions. Intentional when
  passing literal `$` to sub-shells.

If adding a new shell script, include it in the shellcheck invocation.
CI may enforce this check in the future; running it locally catches
issues earlier.

Before committing changes to GitHub Actions workflow files
(`.github/workflows/*.yml`), **validate the YAML syntax**:

```bash
# If actionlint is installed (preferred):
actionlint

# Otherwise, use Python:
python3 -c "
import yaml, sys
for f in sys.argv[1:]:
    yaml.safe_load(open(f))
    print(f'OK: {f}')
" .github/workflows/*.yml
```

Common workflow issues to watch for:

- Missing or incorrect `if:` conditions when adding new event triggers
  (e.g., `schedule` events must be handled alongside `push` and
  `workflow_dispatch`).
- Incorrect indentation under `steps:` or `strategy:` blocks.
- Using `${{ }}` expressions in `run:` blocks where shell variables
  are intended (and vice versa).
