#!/usr/bin/env bash
#
# Reclaim disk on GitHub-hosted runners before disk-heavy extension builds.
#
# The PG 18+ test jobs may rebuild many source-built extensions from scratch in
# a single job (e.g. pg_lake / pg_duckdb, which compile DuckDB). The stock
# ubuntu-latest runner ships with only ~14 GB free on `/`, which is not enough
# for that many concurrent from-source builds -- the failure mode is
# `No space left on device` mid-compile. Removing the preinstalled language
# toolchains and SDKs that our builds never use frees ~25-30 GB.
#
# This only deletes runner-preinstalled content that the CI jobs do not use; it
# does not touch Docker, buildx, the checkout, or the actions runtime.
#
# Usage: ci-free-disk.sh
set -eu

avail() { df -P / | awk 'NR==2 { printf "%.1f", $4 / 1024 / 1024 }'; }

echo "Disk before cleanup: $(avail) GiB free"

# Large preinstalled toolchains/SDKs unused by extension builds. `sudo rm` each
# independently so a missing path on a future runner image is not fatal.
for path in \
  /usr/local/lib/android \
  /usr/share/dotnet \
  /opt/ghc \
  /usr/local/.ghcup \
  /opt/hostedtoolcache/CodeQL \
  /usr/local/share/powershell \
  /usr/share/swift \
  /usr/local/share/chromium \
  /usr/local/lib/node_modules \
  /usr/share/miniconda \
  /opt/az \
; do
  sudo rm -rf "$path" 2>/dev/null || true
done

# Drop preinstalled Docker images we never use (the postgres base images we need
# are pulled fresh). Keep the builder cache intact -- callers manage that.
docker image prune -af >/dev/null 2>&1 || true

echo "Disk after cleanup:  $(avail) GiB free"
df -h /
