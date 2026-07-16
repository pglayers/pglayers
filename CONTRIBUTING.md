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

Extensions fall into four build families. Which one applies decides how
much work you do:

- **APT via the shared template** *(Path A, most extensions)* -- installed
  from the PGDG apt repo (`apt.postgresql.org`) by a single shared
  `Dockerfile.apt`. **No Dockerfile, no version pins.** `make add-apt-ext`
  does almost everything; you just write `test.sql`.
- **APT with a custom Dockerfile** *(Path A, special cases)* -- an apt
  package the shared template can't express (multiple/renamed packages,
  `.control` symlinks, extra steps): e.g. `postgis`, `pgrouting`, `http`.
- **Source-built from an upstream prebuilt image** *(Path B)* -- heavy
  builds that reuse an official image or cached build stage to avoid a long
  compile: e.g. `pg_duckdb`, `pg_lake`.
- **Source-built from git** *(Path B)* -- `git clone` + `make` at a pinned
  tag, when no apt package exists: e.g. `pg_net`, `pgsodium`.

See [How extensions are built](README.md#how-extensions-are-built) for the
overview. Prefer apt whenever PGDG ships the package.

### Prerequisites

- Docker (with BuildKit)
- GNU Make
- Bash
- `shellcheck` (for linting shell scripts)

### Path A: APT-based extension (recommended)

**1. Check availability.** An extension is apt-installable if PGDG ships
`postgresql-<pg>-<pkg>`:

```bash
./scripts/apt-support.sh version 17 <pkg>   # prints the version, or nothing
```

**2. Scaffold it:**

```bash
make add-apt-ext PKG=<apt-package> [NAME=<dir>] [PG=17]
```

This probes PGDG for the version, **auto-detects the license** from the
Debian copyright, fills in the description, writes
`extensions/<name>/extension.conf` and a starter `test.sql`, and runs
`make check-licenses`. If the license is denied or undetected it stops and
tells you what to do (see [Licensing](#licensing) below).

The resulting `extension.conf` for an apt extension is small -- **no
Dockerfile, no `VERSION_*`**:

```bash
DESCRIPTION="Short description"
REPO="https://github.com/org/extension"
LICENSE="PostgreSQL"      # auto-detected; must pass the license gate
SHARED_PRELOAD=""         # library name if the extension must be preloaded
NOTES=""
APT_PACKAGE="<pkg>"       # PGDG suffix only: no "postgresql-<pg>-", no version
# DEPENDS="btree_gist"    # optional: other extensions this one requires
# PG_CONF="foo.bar = 'x'" # optional: extra postgresql.conf GUCs (pipe-delimited)
```

There is deliberately no `VERSION_*`: `apt-get` installs the latest, and an
extension "supports" a PG major iff PGDG publishes the package for it
(combos that don't exist yet are skipped automatically and re-appear when
PGDG catches up).

**3. Finish the config and tests.** Fill any fields the scaffold left blank
(`REPO`, `SHARED_PRELOAD`, `DEPENDS`, `PG_CONF`) and replace the `test.sql`
stub with real functional checks (see [Tests](#tests)).

**4. Build and verify:**

```bash
make build EXT=<name> PG=17 REGISTRY=local
PGLAYERS_EXTENSIONS="<name>" bash tests/test-layers.sh local 17
```

Only write a **custom** `extensions/<name>/Dockerfile` for an apt extension
if the shared template can't express it -- e.g. multiple/renamed packages,
`.control` update-alternatives symlinks, or extra build steps. See
`extensions/postgis/`, `extensions/pgrouting/`, `extensions/http/`.

### Path B: Source-built extension

When no apt package exists, add `extensions/<name>/Dockerfile` and pin the
upstream tag in `extension.conf` via `VERSION_17/18/19`. Two variants:

- **From git** -- `git clone` + `make`. Use `extensions/pg_net/Dockerfile`
  as the reference: strip `.so` files after `make install`, and include the
  classic/isolated layout-selection stages.
- **From an upstream prebuilt image** -- for heavy builds (large native
  deps, long compiles), `FROM` an official image or a cached build stage
  instead of compiling in CI. See `extensions/pg_duckdb/Dockerfile`
  (`FROM pgduckdb/pgduckdb`) and `extensions/pg_lake/Dockerfile` (prebuilt
  vcpkg image).

If the extension bundles runtime libraries that aren't in the base
`postgres` image, the layer **must stay self-contained** -- never rely on a
sibling layer to provide a shared library. See the "Extensions MUST always
be self-contained" section in [AGENTS.md](AGENTS.md) for the required
relocation + soname-mangling pattern (`extensions/http/Dockerfile` is the
reference).

### Licensing

The licensing policy is codified in `scripts/licenses.conf` and enforced
automatically by `make check-licenses` (also run in CI):

- **Allowed:** PostgreSQL, MIT, ISC, Zlib, Apache-2.0, the BSD family, plus
  safe weak/file-level copyleft (MPL-2.0) and permissive-classified
  (Artistic-2.0).
- **Denied:** GPL / LGPL / AGPL, and source-available licenses
  (BSL/BUSL, SSPL, FSL, Elastic-2.0/ELv2).
- **Exceptions:** GPL geospatial extensions loaded at runtime (`postgis`,
  `pgrouting`) are deliberate, documented exceptions in `licenses.conf`.
  See the [Licensing policy](README.md#licensing-policy) for the rationale.

`make add-apt-ext` auto-detects the license from the Debian DEP-5
copyright file. If detection returns a **denied or unknown** license:

1. Read the actual license text at
   `/usr/share/doc/postgresql-<pg>-<pkg>/copyright`.
2. If it is genuinely permissive under a non-standard label (Debian
   sometimes labels the PostgreSQL license with the author's name), set
   `LICENSE` explicitly to the canonical SPDX id and, if useful, add an
   alias to `scripts/licenses.conf`.
3. If it is genuinely a denied license, do not onboard it -- or, in rare,
   well-justified cases, add a documented entry to `LICENSE_EXCEPTIONS`.

### Tests

Every extension **must** ship `extensions/<name>/test.sql` -- the single
source of truth for functional coverage (there is no separate smoke test).
Each check prints a line starting with `PASS` or `FAIL`:

```sql
CREATE EXTENSION IF NOT EXISTS <sql_name>;

SELECT CASE
    WHEN <condition>
    THEN 'PASS <name>: what this checks'
    ELSE 'FAIL <name>: what this checks'
END;
```

- Make the **first** check a load/sanity assertion (it doubles as a smoke
  test).
- Aim for 2-4 checks total (core type/function, index/operator behaviour,
  integration with another feature).
- Tests must be self-contained: create and clean up their own objects.
- A **missing** `test.sql`, or one that produces **no** `PASS`/`FAIL`
  output, is a hard failure.

In `tests/test-layers.sh`:

- If the SQL extension name differs from the directory name, add it to
  `EXT_SQL_NAMES` (e.g. `[pgsphere]="pg_sphere"`).
- If the extension is not loadable via `CREATE EXTENSION` (e.g. logical
  decoding output plugins like `wal2json`), add it to `SKIP_CREATE_EXT`
  instead.

Everything else -- layer collisions, base-image overwrites, self-containment
(`ldd`), and `CREATE EXTENSION` -- is checked automatically.

### Documentation and profiles

In the **same commit**:

- Add a row to the README "Available extensions" table.
- Add to the README `shared_preload_libraries` table if it needs
  preloading.
- Add to `profiles/full.txt` (alphabetical order); run `make check-profiles`.
- Add to relevant service profiles (e.g. `profiles/azure.txt`) if the
  extension is offered by that managed service.

### Version monitoring

- **APT-based extensions:** no `VERSION_XX` to bump -- `apt-get` installs
  the latest PGDG package on every rebuild. Their versions are tracked by
  the [apt-versions lockfile](.github/apt-versions.json), regenerated by
  [monitor-apt-versions.yml](.github/workflows/monitor-apt-versions.yml):
  when PGDG ships a new version the workflow opens a lockfile PR (the
  explicit, git-visible changelog) with **auto-merge enabled**, so it lands
  on `main` and rebuilds the affected layers once checks pass -- no manual
  action needed when adding one.
- **Source-built extensions:** tracked by
  [monitor-extensions.yml](.github/workflows/monitor-extensions.yml).
  Standard semver tags are auto-detected; non-standard tags need a
  `TAG_FILTER` in `extension.conf`; branch-pinned extensions go in the
  workflow's `SKIP_MONITOR` list.

### Pre-commit checks

```bash
# Lint shell (fix all errors and warnings)
shellcheck tests/*.sh scripts/*.sh

# Validate workflow YAML if you changed any (actionlint preferred)
actionlint

# Policy + profile gates
make check-licenses
make check-profiles

# Functional tests (scope to your extension; also run PG 18)
PGLAYERS_EXTENSIONS="<name>" bash tests/test-layers.sh local 17
```

### Submit

```bash
git add extensions/<name>/ tests/test-layers.sh profiles/ README.md
git commit -m "feat(extensions): add <name>"
```

Open a PR against `main`. CI runs the full test suite for PG 17, 18 and 19
(19 is beta and non-blocking).

## Ordering convention

All extension lists must be sorted **alphabetically** wherever they
appear: README tables, `EXT_SQL_NAMES` / `SKIP_CREATE_EXT` arrays, profile
files. This avoids merge conflicts and keeps diffs readable.

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
