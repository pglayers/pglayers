-- pg_lake integration tests
-- Note: full Iceberg/lake functionality requires pgduck_server running
CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;

-- Test: pg_lake and sub-extensions are loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension
          WHERE extname IN ('pg_lake', 'pg_lake_table', 'pg_lake_engine',
                            'pg_extension_base', 'pg_lake_iceberg', 'pg_lake_copy')) >= 5
    THEN 'PASS pg_lake: core extensions loaded'
    ELSE 'FAIL pg_lake: core extensions loaded'
END;

-- Test: pg_lake foreign data wrapper is available
SELECT CASE
    WHEN (SELECT count(*) FROM pg_foreign_data_wrapper WHERE fdwname = 'pg_lake_table') > 0
    THEN 'PASS pg_lake: foreign data wrapper registered'
    ELSE 'FAIL pg_lake: foreign data wrapper registered'
END;

-- Test: pg_lake server exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_foreign_server WHERE srvname = 'pg_lake') > 0
    THEN 'PASS pg_lake: foreign server registered'
    ELSE 'FAIL pg_lake: foreign server registered'
END;
