#!/usr/bin/env bash
#
# Ensure local/<prefix>-<ext>:<pg> images exist for the given extensions so
# that combined-image and profile composition (make image / make test /
# make test-image, all with REGISTRY=local) never consume a stale layer.
#
# BUILD-ONCE MODEL
# ----------------
# Layers are compiled exactly once, by the CI `build` job, which pushes an
# immutable per-commit staging tag to the registry:
#   * source extension (native, per-arch):  pgx-<ext>:<pg>-<version>-<arch>
#   * apt extension    (multi-arch):         pgx-<ext>:<pg>-<version>
# The test/profile/integration jobs then *pull* those images instead of
# recompiling them. On merge, the `promote` job retags them into the public
# multi-arch :<pg> / :<pg>-<version> manifests -- again without rebuilding.
#
# Policy per extension:
#   * CI_SKIP=1              -> never built in CI; use a published image or skip
#   * changed (this run)     -> pull the freshly-built <version>[-<arch>] staging
#                               tag the `build` job just pushed; if it is absent
#                               (fork PR with no registry write, or a rerun on a
#                               dirty runner) fall back to building from source
#   * unchanged              -> pull the published multi-arch :<pg> and retag
#   * pull missing/unusable  -> build from source (fallback)
#
# Because changed layers come from this run's `build` (or a local rebuild) and
# unchanged ones come from the last published release, there is no window where
# a composition step binds an out-of-date layer.
#
# Usage:  ci-prepare-images.sh <pg> <ext...>
# Env:
#   SOURCE_REGISTRY  registry to pull images from (default ghcr.io/pglayers)
#   PREFIX           image name prefix (default pgx)
#   PG_TAG           base postgres tag for source builds (default = <pg>)
#   CHANGED          space-separated list of extensions changed in this run
#   CACHE_ARCH       arch selecting the per-arch staging/cache tag (default host)
set -euo pipefail

PG="${1:?usage: ci-prepare-images.sh <pg> <ext...>}"
shift

SOURCE_REGISTRY="${SOURCE_REGISTRY:-ghcr.io/pglayers}"
PREFIX="${PREFIX:-pgx}"
PG_TAG="${PG_TAG:-$PG}"
CHANGED=" ${CHANGED:-} "

# Runner architecture, selecting the per-arch staging tag (<pg>-<ver>-<arch>)
# and the per-arch registry build cache (buildcache-<pg>-<arch>).
CACHE_ARCH="${CACHE_ARCH:-$(dpkg --print-architecture 2>/dev/null || echo amd64)}"

# Below this free-space threshold (GiB) we prune the BuildKit cache between any
# from-source fallback builds. Each finished layer is already `--load`ed into
# the docker image store, so its build cache is safe to drop.
DISK_FLOOR_GIB="${DISK_FLOOR_GIB:-14}"

is_changed() { case "$CHANGED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

avail_gib() { df -P / | awk 'NR==2 { printf "%d", $4 / 1024 / 1024 }'; }

prune_if_low() {
	local avail
	avail="$(avail_gib)"
	if [ "${avail:-99}" -lt "$DISK_FLOOR_GIB" ]; then
		echo "::group::prune build cache (only ${avail} GiB free, floor ${DISK_FLOOR_GIB})"
		docker builder prune -af >/dev/null 2>&1 || true
		docker image prune -f >/dev/null 2>&1 || true
		echo "  now $(avail_gib) GiB free"
		echo "::endgroup::"
	fi
}

build_local() {
	local ext="$1"
	echo "::group::build $ext (PG $PG) from source"
	make build EXT="$ext" PG="$PG" PG_TAG="$PG_TAG" REGISTRY=local \
		CACHE_SCOPE=ci CACHE_REGISTRY="$SOURCE_REGISTRY" CACHE_ARCH="$CACHE_ARCH"
	echo "::endgroup::"
	prune_if_low
}

# For PG >= 18 a pulled image MUST use the isolated layout (files under /lib or
# /share/extension), not a stale classic image. Isolated images are FROM scratch
# (no shell), so inspect the layout via docker export.
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

# Pull $1 and, if it is a usable (isolated-ok) image, retag it as $local_img.
# Returns 0 on success, 1 otherwise (leaving no dangling pulled image).
try_pull() {
	local src="$1"
	if docker pull "$src" 2>/dev/null && isolated_ok "$src"; then
		docker tag "$src" "$local_img"
		return 0
	fi
	docker rmi "$src" 2>/dev/null || true
	return 1
}

for ext in "$@"; do
	[ -d "extensions/$ext" ] || continue
	# Distinguish "not available for this PG" (empty output, skip) from a real
	# resolution failure (non-zero exit, fail loudly) -- do not swallow the latter.
	if ! ver="$(./scripts/ext-version.sh "$ext" "$PG")"; then
		echo "ERROR: version resolution failed for $ext (PG $PG)" >&2
		exit 1
	fi
	[ -z "$ver" ] && { echo "skip $ext (no version for PG $PG)"; continue; }

	local_img="local/${PREFIX}-${ext}:${PG}"
	# Already prepared earlier in this job.
	docker image inspect "$local_img" >/dev/null 2>&1 && continue

	ci_skip=""
	apt_package=""
	# shellcheck disable=SC1090
	{ ci_skip="$(source "extensions/$ext/extension.conf" && echo "${CI_SKIP:-}")"; }
	# shellcheck disable=SC1090
	{ apt_package="$(source "extensions/$ext/extension.conf" && echo "${APT_PACKAGE:-}")"; }

	published="${SOURCE_REGISTRY}/${PREFIX}-${ext}:${PG}"

	# CI_SKIP: never compiled in CI (too heavy). Use a published image if usable.
	if [ "$ci_skip" = "1" ]; then
		try_pull "$published" \
			|| echo "skip $ext (CI_SKIP=1 and no usable published image)"
		continue
	fi

	if is_changed "$ext"; then
		# Freshly built by the `build` job in THIS run (same-repo / schedule /
		# dispatch). APT layers are multi-arch (<pg>-<ver>); source layers are
		# per-arch (<pg>-<ver>-<arch>).
		if [ -n "$apt_package" ]; then
			staged="${SOURCE_REGISTRY}/${PREFIX}-${ext}:${PG}-${ver}"
		else
			staged="${SOURCE_REGISTRY}/${PREFIX}-${ext}:${PG}-${ver}-${CACHE_ARCH}"
		fi
		if try_pull "$staged"; then
			echo "pulled freshly-built $ext ($PG-$ver)"
		else
			# Fork PR (no registry write) or unavailable -> compile locally so
			# the changed code is still validated.
			echo "no freshly-built image for changed $ext; building from source"
			build_local "$ext"
		fi
		continue
	fi

	# Unchanged: the last published multi-arch release layer.
	try_pull "$published" || {
		echo "no usable published image for $ext; building from source"
		build_local "$ext"
	}
done
