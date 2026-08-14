#!/usr/bin/env sh
#
# Single source of truth: map a PostgreSQL major version to its Docker Hub tag.
#
# A GA major's image tag is just the major ("postgres:17"), but a PRE-RELEASE
# major has no bare tag yet -- Docker Hub publishes only pre-release tags
# ("postgres:19beta3", later "19beta4", "19rc1", and finally the GA
# "postgres:19"). Every consumer (Makefile, scripts, and the CI / base-image
# workflows) resolves the tag through THIS script, so a tag roll is a one-line
# edit here instead of a find-and-replace across the repo (the "PG 19 drift").
#
# When the pre-release tag rolls: change the 19) line below.
# When the major goes GA:         delete the 19) line (it maps to itself).
#
# Usage: pg-tag.sh <pg-major>   # echoes the Docker tag for that major

set -eu

case "${1:?usage: pg-tag.sh <pg-major>}" in
    19) echo "19beta3" ;;
    *)  echo "$1" ;;
esac
