#!/usr/bin/env bash
#
# Assert that a pushed image is a multi-arch manifest list containing every
# required platform.
#
# The combined profile images (pglayers-full, pglayers-azure) are composed from
# the per-arch extension layers and pushed as a single manifest list. A single-
# arch push (e.g. building without buildx, or a layer that only exists for one
# arch) silently produces an image that fails at `docker pull` time on the
# missing platform with "does not provide the specified platform" -- the failure
# reported in #50. This check runs right after the push so that regression is
# caught in CI instead of by users.
#
# Usage:
#   verify-multiarch.sh <image-ref> [platform ...]
# Platforms default to linux/amd64 linux/arm64 when none are given. Extra
# attestation manifests (platform architecture "unknown") are ignored.
set -eu

IMAGE="${1:?usage: verify-multiarch.sh <image-ref> [platform ...]}"
shift || true
if [ "$#" -gt 0 ]; then
  REQUIRED=("$@")
else
  REQUIRED=(linux/amd64 linux/arm64)
fi

echo "Verifying multi-arch manifest: $IMAGE"

raw="$(docker buildx imagetools inspect --raw "$IMAGE")"

# Real (non-attestation) platforms declared in the manifest list. A single-image
# manifest has no .manifests[] and yields an empty list here.
present="$(printf '%s' "$raw" | jq -r '
  (.manifests // [])[]
  | select((.platform.architecture // "unknown") != "unknown")
  | "\(.platform.os)/\(.platform.architecture)"
' | sort -u)"

if [ -z "$present" ]; then
  echo "ERROR: $IMAGE is not a multi-arch manifest list (single-platform image)." >&2
  exit 1
fi

echo "Platforms present:"
# shellcheck disable=SC2086 # intentional word-split: one platform per line
printf '  - %s\n' $present

missing=""
for want in "${REQUIRED[@]}"; do
  if ! printf '%s\n' "$present" | grep -qxF "$want"; then
    missing="${missing:+$missing }$want"
  fi
done

if [ -n "$missing" ]; then
  echo "ERROR: $IMAGE is missing required platform(s): $missing" >&2
  exit 1
fi

echo "OK: $IMAGE provides all required platforms: ${REQUIRED[*]}"
