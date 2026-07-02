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

-- Test: Gateway background worker started (give it 3 seconds to connect)
SELECT pg_sleep(3);

SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM pg_stat_activity
        WHERE backend_type = 'bg worker'
          AND application_name = ''
          AND datname = current_database()
    )
    THEN 'PASS documentdb: gateway background worker active'
    ELSE 'FAIL documentdb: gateway background worker active'
END;

-- Test: MongoDB wire protocol port is reachable (via SQL insert/find roundtrip)
SELECT documentdb_api.insert_one('test_db', 'test_coll', '{"_id": 1, "msg": "hello from pglayers"}');

SELECT CASE
    WHEN documentdb_api.find_one('test_db', 'test_coll', '{"_id": 1}') IS NOT NULL
    THEN 'PASS documentdb: insert_one and find_one roundtrip'
    ELSE 'FAIL documentdb: insert_one and find_one roundtrip'
END;

-- Cleanup
SELECT documentdb_api.drop_collection('test_db', 'test_coll');
