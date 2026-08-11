#!/usr/bin/env bash
#
# Run a command, retrying on failure with exponential backoff.
#
# GHCR intermittently returns transient auth/push errors under the concurrency
# of a full rebuild -- "denied: denied", "failed to fetch oauth token",
# "failed to push ...: 403 Forbidden", "failed to configure registry cache
# importer". These are not real permission problems (sibling jobs pushing to the
# same registry with the same token succeed); a short retry clears them and
# avoids a manual re-run of the whole workflow. See issue #50 / PR CI history.
#
# Usage:
#   ci-retry.sh [-n attempts] [-w seconds] <command> [args...]
#
#   -n  max attempts     (default 3)
#   -w  initial backoff  (default 20s; doubles after each failed attempt)
#
# The command is re-executed verbatim on each attempt, so it must be idempotent
# (docker login, buildx build --push, and imagetools create all are).
set -uo pipefail

attempts=3
wait=20
while getopts ":n:w:" opt; do
  case "$opt" in
    n) attempts="$OPTARG" ;;
    w) wait="$OPTARG" ;;
    *) echo "ci-retry: unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
  echo "usage: ci-retry.sh [-n attempts] [-w seconds] <command> [args...]" >&2
  exit 2
fi

i=1
while true; do
  "$@" && exit 0
  status=$?
  if [ "$i" -ge "$attempts" ]; then
    echo "ci-retry: '$*' failed after $i attempt(s) (exit $status)" >&2
    exit "$status"
  fi
  echo "ci-retry: attempt $i/$attempts failed (exit $status); retrying in ${wait}s..." >&2
  sleep "$wait"
  i=$((i + 1))
  wait=$((wait * 2))
done
