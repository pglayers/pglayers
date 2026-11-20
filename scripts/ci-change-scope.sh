#!/usr/bin/env bash
# Plan layer changes over a complete GitHub push or pull-request range.
# Usage: ci-change-scope.sh <push|pull_request> <before|pr-base> <after|pr-head>
# Emits JSON: {changed: [extension directories], build_all: boolean}.
set -euo pipefail

event="${1:?usage: ci-change-scope.sh <event> <base> <head>}"
base="${2:?missing event base SHA}"
head="${3:?missing event head SHA}"
head="$(git rev-parse --verify "${head}^{commit}")"
build_all=false

case "$event" in
    push)
        if [[ "$base" =~ ^0+$ ]]; then
            # A newly created branch has no before commit. Compare the entire
            # tree and rebuild, rather than silently falling back to HEAD~1.
            base="$(git hash-object -t tree /dev/null)"
            build_all=true
        else
            base="$(git rev-parse --verify "${base}^{commit}")"
        fi
        ;;
    pull_request)
        # Exclude unrelated main changes since the branch diverged. The PR
        # head (not just the last commit or checkout's synthetic merge parent)
        # must include earlier extension edits even after a docs-only commit.
        base="$(git merge-base "$base" "$head")"
        ;;
    *) echo "Unsupported change-scope event: $event" >&2; exit 2 ;;
esac

echo "CI change range ($event): $base..$head" >&2
files="$(git diff --name-only --no-renames "$base" "$head")"
changed="$(printf '%s\n' "$files" | awk -F/ '$1 == "extensions" {print $2}')"

if grep -qxF 'Dockerfile.apt' <<<"$files"; then
    for dir in extensions/*/; do
        [ -d "$dir" ] || continue
        [ -f "${dir}Dockerfile" ] || changed+=$'\n'"$(basename "$dir")"
    done
fi

if grep -qxF '.github/apt-versions.json' <<<"$files"; then
    old='{}'
    if git cat-file -e "$base:.github/apt-versions.json" 2>/dev/null; then
        old="$(git show "$base:.github/apt-versions.json")"
    fi
    # Read both snapshots from the selected range, not HEAD~1 or the worktree.
    new="$(git show "$head:.github/apt-versions.json")"
    apt_changed="$(jq -r --argjson old "$old" \
        'to_entries[] | select(.value != ($old[.key] // {})) | .key' <<<"$new")"
    changed+=$'\n'"$apt_changed"
fi

if grep -qE '^(\.github/workflows/ci\.yml$|\.github/base-image-digests\.json$|Makefile$|scripts/)' <<<"$files"; then
    build_all=true
fi

printf '%s\n' "$changed" | jq -Rsc --argjson build_all "$build_all" \
    '{changed: (split("\n") | map(select(length > 0)) | unique), build_all: $build_all}'
