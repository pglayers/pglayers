#!/usr/bin/env bash
#
# Resolve PGDG apt availability + version for extensions, per PostgreSQL major.
#
# For APT-based extensions we no longer pin VERSION_XX by hand: an extension
# supports a PG major iff apt.postgresql.org ships postgresql-<pg>-<pkg>, and
# the "version" is whatever apt would install. This script answers both
# questions by querying the official postgres image (which has the PGDG repo
# configured).
#
# Usage:
#   apt-support.sh version <pg> <apt_package>   # clean tag-safe version, or empty
#   apt-support.sh aptversion <pg> <apt_package> # full Debian apt version, or empty
#   apt-support.sh available <pg> <apt_package> # exit 0 if available, else 1
#   apt-support.sh list <pg>                    # prints "pkg version" lines
#
# Results are cached per PG major under $PGLAYERS_APT_CACHE_DIR (default
# /tmp/pglayers-apt-cache) so repeated lookups in one run are cheap.

set -euo pipefail

CACHE_DIR="${PGLAYERS_APT_CACHE_DIR:-/tmp/pglayers-apt-cache}"

_pg_tag() { [ "$1" = "19" ] && echo "19beta1" || echo "$1"; }

# Debian apt version -> clean, docker-tag-safe upstream version.
# e.g. 0.8.5-1.pgdg13+1 -> 0.8.5 ; 3.6.4+dfsg-2.pgdg13+1 -> 3.6.4
_clean_version() {
    local v="$1"
    v="${v#*:}"     # drop epoch (no-op when absent)
    v="${v%-*}"     # drop Debian revision
    v="${v%%+*}"    # drop +dfsg and similar
    v="${v%%\~*}"   # drop ~beta/~rc pre-release suffixes
    echo "$v"
}

# Populate the per-PG cache file with "postgresql-<pg>-<suffix> <version>"
# lines for every available package, using a single container invocation.
_ensure_cache() {
    local pg="$1"
    local list="${CACHE_DIR}/pg${pg}.list"
    if [ -s "$list" ]; then return 0; fi
    mkdir -p "$CACHE_DIR"
    local tag
    tag="$(_pg_tag "$pg")"
    # One container: apt-get update, then dump name+version for the prefix.
    docker run --rm "postgres:${tag}" bash -c '
        set -e
        apt-get update >/dev/null 2>&1
        for p in $(apt-cache pkgnames "postgresql-'"$pg"'-" 2>/dev/null); do
            case "$p" in *-dbgsym) continue ;; esac
            v="$(apt-cache show "$p" 2>/dev/null | awk "/^Version:/{print \$2; exit}")"
            [ -n "$v" ] && echo "$p $v"
        done
    ' 2>/dev/null | sort -u > "$list" || : > "$list"
}

_raw_version() {
    local pg="$1" pkg="$2"
    _ensure_cache "$pg"
    awk -v n="postgresql-${pg}-${pkg}" '$1==n {print $2; exit}' \
        "${CACHE_DIR}/pg${pg}.list"
}

cmd="${1:-}"; pg="${2:-}"; pkg="${3:-}"

case "$cmd" in
    version)
        [ -n "$pkg" ] || exit 0
        raw="$(_raw_version "$pg" "$pkg")"
        [ -n "$raw" ] && _clean_version "$raw"
        ;;
    aptversion)
        [ -n "$pkg" ] || exit 0
        _raw_version "$pg" "$pkg"
        ;;
    available)
        [ -n "$pkg" ] || exit 1
        _ensure_cache "$pg"
        awk -v n="postgresql-${pg}-${pkg}" '$1==n{f=1} END{exit !f}' \
            "${CACHE_DIR}/pg${pg}.list"
        ;;
    list)
        _ensure_cache "$pg"
        cat "${CACHE_DIR}/pg${pg}.list"
        ;;
    *)
        echo "usage: $0 {version|aptversion|available|list} <pg> [apt_package]" >&2
        exit 2
        ;;
esac
