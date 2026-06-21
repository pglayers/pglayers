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

## Version Policy

Always use the **latest stable release** of each extension that is
compatible with our supported PostgreSQL versions (currently 17 and 18).
When a new upstream release is published:

1. Update `VERSION_17` and `VERSION_18` in `extension.conf`.
2. Update the `ARG EXT_VERSION` default in the Dockerfile.
3. Run `make test REGISTRY=local PG=17` and `PG=18`.
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

Tests **must pass for all supported PostgreSQL versions** (currently 17,
18, and 19). Run:

```bash
make test REGISTRY=local PG=17
make test REGISTRY=local PG=18
make test REGISTRY=local PG=19
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
for those.

### Dockerfile requirements

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

3. **Strip debug symbols** -- Always strip `.so` files after
   `make install` to reduce image size (50-80% reduction):
   ```dockerfile
   RUN make -j"$(nproc)" && make install DESTDIR=/output \
       && find /output -name '*.so' -exec strip --strip-unneeded {} \;
   ```

4. **Minimal final image** -- The final stage must be `FROM scratch`
   containing only the extension artifacts. No build tools, no source
   code, no package manager state.

5. **Architecture-neutral** -- Dockerfiles must work on both `linux/amd64`
   and `linux/arm64` without modification. Do NOT hardcode architecture-
   specific paths like `/usr/lib/x86_64-linux-gnu/`. Use
   `dpkg-architecture -q DEB_HOST_MULTIARCH` if you need the multiarch
   tuple. All source builds (git clone + make) are inherently portable;
   only pre-built binary downloads need `TARGETARCH` handling.

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
