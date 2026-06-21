# Project Agent Instructions

## postgres-extender

Composable PostgreSQL extension Docker layers on top of official images.

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
