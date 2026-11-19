#!/usr/bin/env sh
#
# Single source of truth: map a PostgreSQL major version to its Docker Hub tag.
#
# All supported majors (17, 18, and 19) use their GA tags. Every consumer
# (Makefile, scripts, and CI / base-image workflows) resolves the tag here.
# If a future prerelease major needs a different tag, add its mapping here
# and remove it once the official GA image is published.
#
# Usage: pg-tag.sh <pg-major>   # echoes the Docker tag for that major

set -eu

case "${1:?usage: pg-tag.sh <pg-major>}" in
    *)  echo "$1" ;;
esac
