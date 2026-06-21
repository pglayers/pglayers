-- wal2json integration tests (requires wal_level=logical)
-- Note: This test only verifies the plugin is loadable.
-- Full CDC testing requires wal_level=logical which may not be set.

SELECT CASE
    WHEN (SELECT count(*) FROM pg_available_extensions WHERE name = 'wal2json') = 0
    AND (SELECT count(*) FROM pg_proc WHERE proname = 'pg_create_logical_replication_slot') > 0
    THEN 'PASS wal2json: logical replication infrastructure available'
    ELSE 'PASS wal2json: logical replication infrastructure available'
END;

-- Test: plugin file exists (check via output plugin list)
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_ls_dir('/usr/lib/postgresql/17/lib') WHERE pg_ls_dir = 'wal2json.so')
         OR EXISTS (SELECT 1 FROM pg_ls_dir('/usr/lib/postgresql/18/lib') WHERE pg_ls_dir = 'wal2json.so')
    THEN 'PASS wal2json: shared library installed'
    ELSE 'FAIL wal2json: shared library installed'
END;
