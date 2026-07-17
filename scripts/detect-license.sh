#!/usr/bin/env bash
#
# Detect the primary license of an APT extension from its Debian DEP-5
# copyright file -- the License of the "Files: *" catch-all stanza, which
# governs the extension's own code -- normalized to the SPDX id used in
# scripts/licenses.conf.
#
# Usage: detect-license.sh <pg> <apt_package>
# Prints the normalized license, or "UNKNOWN" if it can't be determined.

set -euo pipefail

pg="${1:?usage: detect-license.sh <pg> <apt_package>}"
pkg="${2:?usage: detect-license.sh <pg> <apt_package>}"
tag="$pg"; [ "$pg" = "19" ] && tag="19beta1"

# Fetch the whole copyright file once. Distinguish an infrastructure failure
# (docker/apt error -> fail fast, non-zero) from a package that installs but
# ships no copyright file (-> empty output -> UNKNOWN). The inner `if` keeps a
# missing copyright from being reported as a docker failure.
if ! copyright="$(docker run --rm "postgres:${tag}" bash -c '
    set -e
    apt-get update >/dev/null 2>&1
    apt-get install -y --no-install-recommends "postgresql-'"$pg"'-'"$pkg"'" >/dev/null 2>&1
    f="/usr/share/doc/postgresql-'"$pg"'-'"$pkg"'/copyright"
    if [ -f "$f" ]; then cat "$f"; fi
' 2>/dev/null)"; then
    echo "detect-license: failed to query/install postgresql-${pg}-${pkg} (docker/apt error)" >&2
    exit 1
fi

[ -n "$copyright" ] || { echo "UNKNOWN"; exit 0; }

# Primary license = License of the "Files: *" catch-all DEP-5 stanza.
raw="$(printf '%s\n' "$copyright" | awk '
    /^Files:[[:space:]]*\*[[:space:]]*$/ {instar=1; next}
    /^Files:/ {instar=0}
    instar && /^License:/ {sub(/^License:[[:space:]]*/,""); print; exit}
')"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/licenses.conf"

_normalize() {
    local lic="$1" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in "${lic}="*) echo "${line#*=}"; return 0 ;; esac
    done <<< "$LICENSE_ALIASES"
    echo "$lic"
}

_known() {
    local lic="$1" line
    for line in $ALLOW_LICENSES $DENY_LICENSES; do
        [ "$line" = "$lic" ] && return 0
    done
    return 1
}

# Split "A or B or C" and pick the first allowed option; else the first.
# Split on the literal " or " separator only -- never word-split on internal
# whitespace, so multi-word identifiers (e.g. "Apache 2.0") survive intact.
_choose() {
    local first="" n part rest="$1"
    while [ -n "$rest" ]; do
        case "$rest" in
            *" or "*) part="${rest%% or *}"; rest="${rest#* or }" ;;
            *)        part="$rest";          rest="" ;;
        esac
        # Trim surrounding whitespace from the option.
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [ -n "$part" ] || continue
        n="$(_normalize "$part")"
        [ -n "$first" ] || first="$n"
        _in_allow "$n" && { echo "$n"; return 0; }
    done
    echo "$first"
}
_in_allow() { local x="$1" a; for a in $ALLOW_LICENSES; do [ "$a" = "$x" ] && return 0; done; return 1; }

label=""
[ -n "$raw" ] && label="$(_choose "$raw")"

# If the label maps to a recognized license, trust it.
if [ -n "$label" ] && _known "$label"; then
    echo "$label"
    exit 0
fi

# Otherwise fall back to matching the license *text*. Many PG extensions carry
# the PostgreSQL license verbatim but Debian labels it with the author/company
# name (e.g. verite, CYBERTEC, PostgreSQL-Angelakos). The phrase "without a
# written agreement" is distinctive to the PostgreSQL license.
if printf '%s' "$copyright" | grep -qiF "without fee, and without a written agreement"; then
    echo "PostgreSQL"
    exit 0
fi

echo "${label:-UNKNOWN}"

