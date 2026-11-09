-- wal2json is an output plugin, not a CREATE EXTENSION module.
-- LOAD checks the actual binary and ABI through dynamic_library_path in both
-- the classic and isolated layouts, without hardcoded PostgreSQL paths.
LOAD 'wal2json';
SELECT 'PASS wal2json: output plugin loads';

-- Full CDC testing requires wal_level=logical; this check also works on the
-- bare postgres image's default wal_level=replica.
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_proc
                 WHERE pronamespace = 'pg_catalog'::regnamespace
                   AND proname = 'pg_create_logical_replication_slot')
    THEN 'PASS wal2json: logical replication infrastructure available'
    ELSE 'FAIL wal2json: logical replication infrastructure unavailable'
END;
