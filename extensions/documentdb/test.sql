-- documentdb integration tests
CREATE EXTENSION IF NOT EXISTS documentdb_core;

-- Test: BSON data type creation from JSON string
SELECT CASE
    WHEN '{"hello": "world"}'::documentdb_core.bson IS NOT NULL
    THEN 'PASS documentdb: BSON data type creation'
    ELSE 'FAIL documentdb: BSON data type creation'
END;

-- Test: BSON equality comparison
SELECT CASE
    WHEN '{"a": 1}'::documentdb_core.bson = '{"a": 1}'::documentdb_core.bson
    THEN 'PASS documentdb: BSON equality comparison'
    ELSE 'FAIL documentdb: BSON equality comparison'
END;

-- Test: Full documentdb extension with dependencies
CREATE EXTENSION IF NOT EXISTS tsm_system_rows;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS documentdb;

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'documentdb')
    THEN 'PASS documentdb: full extension loaded with dependencies'
    ELSE 'FAIL documentdb: full extension loaded with dependencies'
END;
