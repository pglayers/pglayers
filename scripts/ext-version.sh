#!/usr/bin/env bash
#
# Resolve the build/tag version for an extension on a given PG major.
#
#   - Source-built extensions: the pinned VERSION_<pg> (git tag) from
#     extension.conf.
#   - APT extensions (APT_PACKAGE set, no VERSION_<pg>): the version apt would
#     install, derived from PGDG via scripts/apt-support.sh. Empty when the
#     package is not available for that PG major (i.e. the extension does not
#     support that PG version).
#
# Usage: ext-version.sh <ext> <pg>
# Prints the version, or nothing if the extension is unavailable on that PG.

set -euo pipefail

ext="${1:?usage: ext-version.sh <ext> <pg>}"
pg="${2:?usage: ext-version.sh <ext> <pg>}"
conf="extensions/${ext}/extension.conf"
[ -f "$conf" ] || exit 0

# shellcheck disable=SC1090
source "$conf"

vv="VERSION_${pg}"
v="${!vv:-}"

if [ -z "$v" ] && [ -n "${APT_PACKAGE:-}" ]; then
    # No `|| true`: an apt-support.sh failure (PGDG query broke) must propagate
    # so callers fail fast. A package that is genuinely unavailable for this PG
    # major returns success with empty output, which stays an empty version.
    v="$("$(dirname "$0")/apt-support.sh" version "$pg" "$APT_PACKAGE")"
fi

echo "$v"
