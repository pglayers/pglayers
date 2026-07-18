#!/usr/bin/env bash
#
# Ensure local/<prefix>-<ext>:<pg> images exist for the given extensions so
# that combined-image and profile composition (make image / make test /
# make test-image, all with REGISTRY=local) never consume a stale layer.
#
# Policy per extension:
#   * in $CHANGED            -> build from source (fresh layer with the change)
#   * otherwise              -> pull the published image and retag as local/
#   * pull missing/unusable  -> build from source (fallback)
#   * CI_SKIP=1 + unpublished -> skip (long builds not exercised in CI)
#
# This is the single source of truth the CI test jobs use to assemble images;
# because changed layers are always rebuilt and unchanged ones come from the
# last published (correct) release, there is no window where a composition
# step binds an out-of-date layer -- the class of bug behind "the azure
# profile pulled a pre-fix postgis".
#
# Usage:  ci-prepare-images.sh <pg> <ext...>
# Env:
#   SOURCE_REGISTRY  registry to pull unchanged images from (default ghcr.io/pglayers)
#   PREFIX           image name prefix (default pgx)
#   PG_TAG           base postgres tag for source builds (default = <pg>)
#   CHANGED          space-separated list of extensions to build from source
set -euo pipefail

PG="${1:?usage: ci-prepare-images.sh <pg> <ext...>}"
shift

SOURCE_REGISTRY="${SOURCE_REGISTRY:-ghcr.io/pglayers}"
PREFIX="${PREFIX:-pgx}"
PG_TAG="${PG_TAG:-$PG}"
CHANGED=" ${CHANGED:-} "

is_changed() { case "$CHANGED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

build_local() {
	local ext="$1"
	echo "::group::build $ext (PG $PG)"
	make build EXT="$ext" PG="$PG" PG_TAG="$PG_TAG" REGISTRY=local CACHE_SCOPE=ci
	echo "::endgroup::"
}

# For PG >= 18 a pulled image MUST use the isolated layout (files under /lib or
# /share/extension). Stale images built before the isolated layout -- or before
# the $ORIGIN RUNPATH fix -- must be rebuilt, not trusted. Isolated images are
# FROM scratch (no shell), so inspect the layout via docker export.
isolated_ok() {
	local img="$1"
	[ "$PG" -ge 18 ] 2>/dev/null || return 0
	local cid ok=no
	cid="$(docker create "$img" true 2>/dev/null)" || return 1
	if docker export "$cid" 2>/dev/null | tar -t 2>/dev/null \
		| grep -q '^lib/\|^share/extension/'; then
		ok=yes
	fi
	docker rm "$cid" >/dev/null 2>&1 || true
	[ "$ok" = yes ]
}

for ext in "$@"; do
	[ -d "extensions/$ext" ] || continue
	ver="$(./scripts/ext-version.sh "$ext" "$PG" 2>/dev/null || true)"
	[ -z "$ver" ] && { echo "skip $ext (no version for PG $PG)"; continue; }

	local_img="local/${PREFIX}-${ext}:${PG}"
	docker image inspect "$local_img" >/dev/null 2>&1 && continue

	if is_changed "$ext"; then
		build_local "$ext"
		continue
	fi

	ci_skip="$(bash -c "source extensions/$ext/extension.conf && echo \"\${CI_SKIP:-}\"")"
	src="${SOURCE_REGISTRY}/${PREFIX}-${ext}:${PG}"

	if docker pull "$src" 2>/dev/null && isolated_ok "$src"; then
		docker tag "$src" "$local_img"
	elif [ "$ci_skip" = "1" ]; then
		echo "skip $ext (CI_SKIP=1 and no usable published image)"
		docker rmi "$src" 2>/dev/null || true
	else
		echo "no usable published image for $ext; building from source"
		docker rmi "$src" 2>/dev/null || true
		build_local "$ext"
	fi
done
