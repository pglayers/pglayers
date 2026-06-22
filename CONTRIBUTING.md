# Contributing to pglayers

Thanks for your interest in contributing. This guide covers the most
common contribution types: adding extensions, reporting bugs, and
improving the project.

## Code of conduct

Be respectful and constructive. We don't have a formal code of conduct
document, but the standard applies: be kind, assume good faith, and
focus on the technical merits.

## Reporting bugs

Use the [bug report template](https://github.com/pglayers/pglayers/issues/new?template=bug_report.yml)
on GitHub Issues. Include:

- Which extension(s) are affected
- PostgreSQL version and architecture
- Steps to reproduce
- Expected vs actual behavior
- Docker version and host OS

## Requesting a new extension

Use the [extension request template](https://github.com/pglayers/pglayers/issues/new?template=new_extension.yml).
We will review the license and feasibility before accepting.

## Adding a new extension

This is the most common type of contribution. The full checklist is
below -- every item is mandatory.

### Prerequisites

- Docker (with BuildKit)
- GNU Make
- Bash
- `shellcheck` (for linting shell scripts)

### Step 1: Check the license

We ship extensions with permissive open-source licenses (PostgreSQL,
MIT, BSD, Apache 2.0, ISC, MPL-2.0) and GPL-2.0 extensions loaded
via PostgreSQL's dynamic extension mechanism. See the
[licensing policy](README.md#licensing-policy) in the README.

**Rejected licenses:** GPL-3.0, AGPL, BSL, SSPL, ELv2, FSL, or any
license requiring proprietary runtime dependencies.

### Step 2: Create the extension directory

```
extensions/<name>/
  Dockerfile        # Multi-stage build -> FROM scratch artifact
  extension.conf    # Metadata, versions, license
  test.sql          # Integration tests (PASS/FAIL assertions)
```

**`extension.conf` fields:**

```bash
DESCRIPTION="Short description"
REPO="https://github.com/org/extension.git"
LICENSE="PostgreSQL"          # Required
VERSION_17="v1.0.0"
VERSION_18="v1.0.0"
VERSION_19="v1.0.0"
SHARED_PRELOAD=""             # Library name if needed, empty otherwise
NOTES=""
TAG_FILTER=""                 # Optional: regex for non-standard tag formats
```

See [AGENTS.md](AGENTS.md) for Dockerfile requirements (BuildKit
syntax, APT cache mounts, strip symbols, `FROM scratch` final stage,
architecture-neutral paths).

### Step 3: Build and verify locally

```bash
make build EXT=<name> PG=17 REGISTRY=local
make test REGISTRY=local PG=17
```

Tests must also pass for PG 18 and PG 19 (if the extension supports
them).

### Step 4: Add test coverage

Edit `tests/test-layers.sh`:

1. **Name mapping** -- If the SQL extension name differs from the
   directory name, add to `EXT_SQL_NAMES`:
   ```bash
   [my_ext]="my_extension"
   ```

2. **Skip list** -- If not loadable via `CREATE EXTENSION` (e.g.,
   output plugins), add to `SKIP_CREATE_EXT`:
   ```bash
   [my_ext]=1
   ```

3. **Smoke test** -- Add a `smoke_test` call that exercises the
   extension (must produce non-empty output):
   ```bash
   has_ext my_ext && smoke_test "my_ext basic op" \
       "SELECT my_function('test');"
   ```

4. **Integration tests** -- Create `extensions/<name>/test.sql`:
   ```sql
   SELECT CASE
       WHEN <condition>
       THEN 'PASS my_ext: description'
       ELSE 'FAIL my_ext: description'
   END;
   ```
   Aim for 2-4 checks per extension.

### Step 5: Update documentation and profiles

In the **same commit**:

- Add a row to the README "Available extensions" table
- Add to the `shared_preload_libraries` table if applicable
- Add to `profiles/full.txt` (alphabetical order)
- Add to relevant service profiles (e.g., `profiles/azure.txt`) if
  the extension is available in that service
- Run `make check-profiles` to validate

### Step 6: Set up version monitoring

The extension must be tracked by the
[monitor-extensions workflow](.github/workflows/monitor-extensions.yml):

- **Standard semver tags** -- No action needed.
- **Non-standard tags** -- Add `TAG_FILTER` to `extension.conf`.
- **No tagged releases** -- Add to `SKIP_MONITOR` in the workflow.

See [AGENTS.md](AGENTS.md#version-monitoring) for details.

### Step 7: Pre-commit checks

Before submitting:

```bash
# Lint shell scripts
shellcheck tests/test-layers.sh tests/test-image.sh

# Validate workflow YAML (if modified)
actionlint  # or: python3 -c "import yaml; ..."

# Run tests for all supported PG versions
make test REGISTRY=local PG=17
make test REGISTRY=local PG=18
make test REGISTRY=local PG=19

# Verify profiles
make check-profiles
```

### Step 8: Submit

```bash
git add extensions/<name>/ tests/test-layers.sh profiles/full.txt README.md
git commit -m "Add <name> extension"
```

Open a PR against `main`. CI will run the full test suite
automatically.

## Ordering convention

All extension lists must be sorted **alphabetically** wherever they
appear: README tables, test arrays, smoke tests, profile files. This
avoids merge conflicts and keeps diffs readable.

## Other contributions

- **Bug fixes** -- Open an issue first (or reference an existing one),
  then submit a PR with tests.
- **New profiles** -- Create `profiles/<name>.txt` with one extension
  per line. Add to `make check-profiles` validation and CI matrix.
- **Infrastructure improvements** -- Discuss in an issue before making
  large changes to the Makefile, test suite, or CI workflows.

## License

By contributing, you agree that your contributions will be licensed
under the [MIT License](LICENSE).
