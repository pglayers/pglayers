-- tds_fdw integration tests
CREATE EXTENSION IF NOT EXISTS tds_fdw;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'tds_fdw') = 1
    THEN 'PASS tds_fdw: extension loaded'
    ELSE 'FAIL tds_fdw: extension loaded'
END;

-- Test: foreign data wrapper registered
SELECT CASE
    WHEN (SELECT count(*) FROM pg_foreign_data_wrapper WHERE fdwname = 'tds_fdw') = 1
    THEN 'PASS tds_fdw: FDW registered'
    ELSE 'FAIL tds_fdw: FDW registered'
END;

-- Test: can create server (won't connect, but DDL works)
CREATE SERVER test_tds FOREIGN DATA WRAPPER tds_fdw
    OPTIONS (servername '127.0.0.1', port '1433');
SELECT CASE
    WHEN (SELECT count(*) FROM pg_foreign_server WHERE srvname = 'test_tds') = 1
    THEN 'PASS tds_fdw: foreign server created'
    ELSE 'FAIL tds_fdw: foreign server created'
END;

DROP SERVER test_tds;
