#!/usr/bin/env bash
#
# Generate .github/apt-versions.json -- the recorded apt version of every
# APT-based extension, per PostgreSQL major.
#
# WHY THIS EXISTS
#   APT extensions carry no VERSION_XX: apt installs whatever PGDG currently
#   ships, resolved at build time. That makes version bumps invisible in git --
#   nothing in the tree changes when apt.postgresql.org publishes a new
#   package. This lockfile is the explicit, git-visible record of those
#   versions. The monitor-apt-versions workflow regenerates it on a schedule;
#   a change to this file is the signal that PGDG shipped a new version, and
#   merging that change triggers a rebuild of the affected extension layers
#   (build-push.yml keys its change detection off this file).
#
#   It is a RECORD, not a pin. PGDG is a rolling repository (only the latest
#   version of each package is available), so builds always install the latest
#   patch. This file simply tracks what "latest" resolved to at monitor time,
#   so the update is auditable and the rebuild is deliberate.
#
# Usage: apt-lock.sh [output-file]   (default: .github/apt-versions.json)
#
# Requires docker (via scripts/apt-support.sh) and jq.

set -euo pipefail

cd "$(dirname "$0")/.."

out="${1:-.github/apt-versions.json}"
pgs="17 18 19"

result='{}'
for dir in extensions/*/; do
    ext="$(basename "$dir")"
    conf="${dir}extension.conf"
    [ -f "$conf" ] || continue

    # Reset so a prior extension's APT_PACKAGE cannot bleed over.
    APT_PACKAGE=""
    # shellcheck disable=SC1090
    source "$conf"
    [ -n "${APT_PACKAGE:-}" ] || continue

    obj='{}'
    for pg in $pgs; do
        v="$(scripts/apt-support.sh version "$pg" "$APT_PACKAGE" 2>/dev/null || true)"
        [ -n "$v" ] || continue
        obj="$(jq -c --arg pg "$pg" --arg v "$v" '. + {($pg): $v}' <<<"$obj")"
    done

    # No PG major ships this package (unlikely for an onboarded ext) -> omit.
    [ "$obj" = "{}" ] && continue
    result="$(jq -c --arg ext "$ext" --argjson o "$obj" '. + {($ext): $o}' <<<"$result")"
done

# -S sorts object keys so the file diffs cleanly and deterministically.
jq -S . <<<"$result" >"$out"
echo "Wrote $(jq 'length' <<<"$result") APT extensions to $out" >&2
