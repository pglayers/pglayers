FROM postgres:17

# Vector similarity search
COPY --from=ghcr.io/pglayers/pgx-pgvector:17   / /

# Job scheduler
COPY --from=ghcr.io/pglayers/pgx-pg_cron:17    / /

# Geospatial
COPY --from=ghcr.io/pglayers/pgx-postgis:17    / /

# Online table reorganization
COPY --from=ghcr.io/pglayers/pgx-pg_repack:17  / /

# Audit logging
COPY --from=ghcr.io/pglayers/pgx-pgaudit:17    / /

# Partition management
COPY --from=ghcr.io/pglayers/pgx-pg_partman:17 / /

# Extensions that need shared_preload_libraries
RUN echo "shared_preload_libraries = 'pg_cron,pgaudit,pg_partman_bgw'" \
    >> /usr/share/postgresql/postgresql.conf.sample

# Auto-create all extensions on first start
COPY <<'EOF' /docker-entrypoint-initdb.d/10-extensions.sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_repack;
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS pg_partman;
EOF
