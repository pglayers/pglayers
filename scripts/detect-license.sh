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

raw="$(docker run --rm "postgres:${tag}" bash -c '
    set -e
    apt-get update >/dev/null 2>&1
    apt-get install -y --no-install-recommends "postgresql-'"$pg"'-'"$pkg"'" >/dev/null 2>&1
    f="/usr/share/doc/postgresql-'"$pg"'-'"$pkg"'/copyright"
    [ -f "$f" ] || exit 0
    awk "
        /^Files:[[:space:]]*\*[[:space:]]*\$/ {instar=1; next}
        /^Files:/ {instar=0}
        instar && /^License:/ {sub(/^License:[[:space:]]*/,\"\"); print; exit}
    " "$f"
' 2>/dev/null || true)"

[ -n "$raw" ] || { echo "UNKNOWN"; exit 0; }

# For "A or B" dual-licensing, prefer whichever side the policy allows.
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

_allowed() {
    local lic="$1" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$line" = "$lic" ] && return 0
    done <<< "$ALLOW_LICENSES"
    return 1
}

# Split "A or B or C" and pick the first allowed option; else the first.
first=""
chosen=""
# shellcheck disable=SC2001
for part in $(echo "$raw" | sed 's/ or /\n/g'); do
    n="$(_normalize "$part")"
    [ -n "$first" ] || first="$n"
    if _allowed "$n"; then chosen="$n"; break; fi
done

echo "${chosen:-$first}"
