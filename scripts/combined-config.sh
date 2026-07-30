#!/usr/bin/env bash
#
# SINGLE SOURCE OF TRUTH for the runtime configuration of a *combined*
# pglayers image (postgresql.conf.sample settings + a couple of PG18-only
# filesystem fixups).
#
# Both the shipped-image builder (`make image`, the Makefile `image` target)
# and the test harness (tests/test-layers.sh) call this script, so the image
# users run and the image CI tests can never drift apart. If a combined-image
# setting needs to change, change it HERE and both consumers pick it up.
#
# It emits Dockerfile fragments (a `RUN` that appends to
# postgresql.conf.sample, plus any PG18 symlink fixups) to stdout. The caller
# is responsible for the surrounding `FROM` / `COPY --from` layer lines and any
# image-only extras (companion entrypoints, auto-create, manifest, labels).
#
# Usage:
#   scripts/combined-config.sh <PG_MAJOR> <ext> [<ext> ...]
#
# Env:
#   PGLAYERS_MAX_WORKER_PROCESSES   default 64
#
# Must be run from the repository root (reads extensions/<ext>/extension.conf).
set -euo pipefail

PG="${1:?usage: combined-config.sh <PG> <ext...>}"
shift
exts=("$@")

conf="/usr/share/postgresql/postgresql.conf.sample"
max_worker_processes="${PGLAYERS_MAX_WORKER_PROCESSES:-64}"

# Does the extension set contain a given directory name?
has_ext() {
	local needle="$1" e
	for e in "${exts[@]}"; do
		[ "$e" = "$needle" ] && return 0
	done
	return 1
}

# Read one field from an extension's extension.conf (empty if unset).
ext_field() {
	bash -c "source extensions/$1/extension.conf 2>/dev/null && printf '%s' \"\${$2:-}\""
}

# --- Collect the postgresql.conf.sample lines (raw; no shell escaping needed:
#     they are emitted inside a quoted heredoc so $system/$libdir stay literal).
conf_lines=()

if [ "$PG" -ge 18 ] 2>/dev/null; then
	# Isolated layout: point PostgreSQL at each extension's private namespace.
	ext_paths=""
	lib_paths=""
	for e in "${exts[@]}"; do
		ext_paths="${ext_paths}/extensions/${e}/share:"
		lib_paths="${lib_paths}/extensions/${e}/lib:"
	done
	conf_lines+=("extension_control_path = '${ext_paths}\$system'")
	conf_lines+=("dynamic_library_path = '${lib_paths}\$libdir'")
fi

# shared_preload_libraries, aggregated from each extension's SHARED_PRELOAD.
preloads=""
for e in "${exts[@]}"; do
	spl="$(ext_field "$e" SHARED_PRELOAD)"
	[ -n "$spl" ] && preloads="${preloads:+${preloads},}${spl}"
done
[ -n "$preloads" ] && conf_lines+=("shared_preload_libraries = '${preloads}'")

# pgtt loads via session_preload_libraries, not shared_preload_libraries.
if has_ext pgtt; then
	conf_lines+=("session_preload_libraries = 'pgtt'")
fi

# The stock default of 8 is far too low once many bg-worker extensions preload.
conf_lines+=("max_worker_processes = ${max_worker_processes}")

# Per-extension GUCs (PG_CONF is a '|'-delimited list of config lines).
for e in "${exts[@]}"; do
	pgconf="$(ext_field "$e" PG_CONF)"
	[ -z "$pgconf" ] && continue
	while IFS= read -r line; do
		[ -n "$line" ] && conf_lines+=("$line")
	done < <(printf '%s\n' "$pgconf" | tr '|' '\n')
done

# pgsodium's getkey script lives in the isolated namespace on PG18+.
if [ "$PG" -ge 18 ] 2>/dev/null && has_ext pgsodium; then
	conf_lines+=("pgsodium.getkey_script = '/extensions/pgsodium/share/extension/pgsodium_getkey'")
fi

# --- Emit each setting as its own `RUN echo "<line>" >> conf`. The whole value
#     is double-quoted (config values use single quotes internally, which stay
#     literal); the only shell-special char is `$` in $system / $libdir, which
#     is escaped to \$ so the container shell keeps it literal. This mirrors the
#     format the image builder has always produced and needs no BuildKit
#     heredoc support.
for line in "${conf_lines[@]}"; do
	printf 'RUN echo "%s" >> %s\n' "${line//$/\\$}" "$conf"
done

# --- Filesystem fixups (not postgresql.conf.sample content) --------------
# documentdb's gateway GUC points at /etc/documentdb/gateway_config.json. On the
# isolated (PG18+) layout the layer ships it under /extensions/documentdb/etc/,
# so link it into place. On classic (PG17) the layer already installs it at the
# system path.
if [ "$PG" -ge 18 ] 2>/dev/null && has_ext documentdb; then
	printf 'RUN mkdir -p /etc/documentdb && ln -sf /extensions/documentdb/etc/documentdb/gateway_config.json /etc/documentdb/gateway_config.json\n'
fi
