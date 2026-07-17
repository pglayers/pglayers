#!/usr/bin/env bash
#
# Enforce the pglayers licensing policy (scripts/licenses.conf) against every
# extension's declared LICENSE field.
#
#   scripts/check-licenses.sh              # check all extensions
#   scripts/check-licenses.sh <ext> ...    # check specific extensions
#
# Exit non-zero if any extension declares a denied license, an unknown
# ("needs review") license, an exception whose declared license does not match
# the recorded one, or no LICENSE at all.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/licenses.conf"

RED=''; GREEN=''; YELLOW=''; NC=''
if [ -t 1 ]; then RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'; fi

_in_list() {
    # _in_list <needle> <newline-separated-haystack>
    local needle="$1" hay="$2" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$line" = "$needle" ] && return 0
    done <<< "$hay"
    return 1
}

_normalize() {
    # Map an alias to its canonical SPDX id (or echo unchanged).
    local lic="$1" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            "${lic}="*) echo "${line#*=}"; return 0 ;;
        esac
    done <<< "$LICENSE_ALIASES"
    echo "$lic"
}

_exception_license() {
    # Print the recorded exception license for an extension, if any.
    local ext="$1" line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            "${ext}="*) echo "${line#*=}"; return 0 ;;
        esac
    done <<< "$LICENSE_EXCEPTIONS"
    return 1
}

pass=0; fail=0

# Collect the list of extensions to check.
if [ "$#" -gt 0 ]; then
    exts=("$@")
else
    exts=()
    for d in "${ROOT}"/extensions/*/; do exts+=("$(basename "$d")"); done
fi

for ext in "${exts[@]}"; do
    conf="${ROOT}/extensions/${ext}/extension.conf"
    if [ ! -f "$conf" ]; then
        printf "${RED}FAIL${NC} %-22s (no extension.conf)\n" "$ext"; fail=$((fail+1)); continue
    fi
    LICENSE=""
    # shellcheck source=/dev/null
    source "$conf"
    declared="$LICENSE"

    if [ -z "$declared" ]; then
        printf "${RED}FAIL${NC} %-22s no LICENSE declared\n" "$ext"; fail=$((fail+1)); continue
    fi

    norm="$(_normalize "$declared")"

    if exc="$(_exception_license "$ext")"; then
        if [ "$norm" = "$exc" ] || [ "$declared" = "$exc" ]; then
            printf "${YELLOW}EXCEPTION${NC} %-18s %s (documented)\n" "$ext" "$declared"; pass=$((pass+1))
        else
            printf "${RED}FAIL${NC} %-22s declares '%s' but exception records '%s'\n" \
                "$ext" "$declared" "$exc"; fail=$((fail+1))
        fi
        continue
    fi

    if _in_list "$norm" "$ALLOW_LICENSES"; then
        printf "${GREEN}OK${NC}   %-22s %s\n" "$ext" "$declared"; pass=$((pass+1))
    elif _in_list "$norm" "$DENY_LICENSES"; then
        printf "${RED}FAIL${NC} %-22s denied license '%s' (add a documented exception in scripts/licenses.conf if intentional)\n" \
            "$ext" "$declared"; fail=$((fail+1))
    else
        printf "${RED}FAIL${NC} %-22s unknown license '%s' -- add it to ALLOW_LICENSES or record an exception in scripts/licenses.conf\n" \
            "$ext" "$declared"; fail=$((fail+1))
    fi
done

echo
printf -- "Licenses: ${GREEN}%d ok${NC}, ${RED}%d rejected${NC}\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
