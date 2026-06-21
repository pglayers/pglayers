# Project Agent Instructions

## postgres-extender

Composable PostgreSQL extension Docker layers on top of official images.

## Licensing Policy

This project only ships extensions with **permissive open-source
licenses** (PostgreSQL, MIT, BSD, Apache 2.0, ISC). Before adding any
extension:

1. **Audit the license** -- Check the extension's LICENSE/COPYING file
   in its repository. Reject anything that is:
   - Proprietary or source-available (e.g., BSL, SSPL, FSL, ELv2)
   - Copyleft that would infect the combined image (e.g., AGPL)
   - Requires proprietary runtime dependencies (e.g., Oracle client)

2. **Document the license** -- Add a `LICENSE` field to `extension.conf`
   (e.g., `LICENSE="PostgreSQL"` or `LICENSE="MIT"`).

3. **When in doubt, skip it** -- If an extension's license is ambiguous
   or has changed recently (e.g., TimescaleDB moved to TSL for some
   features), do not include it until the licensing is verified.

Extensions we explicitly exclude:
- **oracle_fdw** -- requires proprietary Oracle Instant Client
- Any extension under BSL/SSPL/FSL/ELv2 or similar delayed-open licenses

## Testing Requirements

When adding new extensions or modifying existing ones, **always run the
layer collision and overwrite tests** before merging:

```bash
make test REGISTRY=local PG=17
```

This test suite validates:

1. **No file collisions between extension layers** -- If two extensions
   install a file at the same path, the last `COPY --from` silently
   overwrites the first. This can break extensions at runtime with no
   warning from Docker. The test compares file lists across all extension
   pairs and fails on any overlap.

2. **No base image overwrites** -- Extensions must not replace files
   already present in the official `postgres:XX` image (shared libs,
   config files, binaries). The test diffs each extension's file list
   against the base image.

3. **No missing shared library dependencies** -- Runs `ldd` on every
   `.so` in the combined image. Catches transitive runtime deps that
   weren't bundled (e.g., PostGIS needing libtiff via libproj).

4. **All extensions load** -- `CREATE EXTENSION` must succeed for every
   extension in the combined image.

5. **Functional smoke tests** -- Basic operations per extension to catch
   runtime failures that CREATE EXTENSION alone wouldn't surface.

### When to run tests

- Before committing any change to `extensions/*/Dockerfile`
- Before committing any change to `extensions/*/extension.conf`
- When bumping extension versions
- When adding a new extension
- When changing the base PG version

Tests **must pass for all supported PostgreSQL versions** (currently 17
and 18). Run:

```bash
make test REGISTRY=local PG=17
make test REGISTRY=local PG=18
```

Both must pass before merging. An extension that builds on PG 17 but
fails on PG 18 (or vice versa) is not acceptable -- either fix it for
both versions or remove the unsupported version from `extension.conf`.

### Common collision scenarios to watch for

- Two extensions bundling the same runtime shared library at different
  versions (e.g., both PostGIS and pgRouting shipping libgeos)
- Extensions that install CLI tools with generic names in `/usr/local/bin`
- LLVM bitcode index files in `/usr/lib/postgresql/XX/lib/bitcode/`
- Shared PROJ data files across geo extensions

### Adding a new extension checklist

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
   add it to the `shared_preload_libraries` line in the test Dockerfile
   generator (Phase 5 of `test-layers.sh`).

The collision, overwrite, and ldd checks are automatic for all
extensions in the `extensions/` directory -- no manual update needed
for those.

### Keeping documentation in sync

When adding, removing, or modifying extensions, **all of the following
must be updated in the same commit**:

1. **`README.md` "Available extensions" table** -- Add a row with the
   extension name (linked to its repo), PG versions, and description.
   Also update the `shared_preload_libraries` table if applicable.

2. **`make list` output** -- This is automatic (driven by
   `extension.conf` files), but verify the description is concise and
   the PG version columns are correct.

3. **`tests/test-layers.sh`** -- As described above (name mapping,
   smoke test, shared_preload entry).

4. **`extension.conf` LICENSE field** -- Every extension must document
   its license. Run `make list` and verify the new extension appears.

Do not merge a PR that adds an extension to `extensions/` without
updating the README table and tests. Stale documentation is a bug.
