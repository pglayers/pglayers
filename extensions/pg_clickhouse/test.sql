-- pg_clickhouse integration tests
--
-- pg_clickhouse is a Foreign Data Wrapper: real queries require a running
-- ClickHouse server, which isn't available in CI. These checks validate that
-- the extension (and its bundled re2 companion) load and that their SQL objects
-- work without a live ClickHouse backend.

-- 1. Load / sanity: the clickhouse_fdw foreign data wrapper is registered.
--    (Doubles as the smoke test.)
SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM pg_foreign_data_wrapper WHERE fdwname = 'clickhouse_fdw'
    )
    THEN 'PASS pg_clickhouse: clickhouse_fdw foreign data wrapper registered'
    ELSE 'FAIL pg_clickhouse: clickhouse_fdw foreign data wrapper missing'
END;

-- 2. FDW handler/validator work: creating a foreign server + user mapping
--    exercises the FDW's validator without contacting ClickHouse.
DO $$
BEGIN
    CREATE SERVER pgclickhouse_test_srv
        FOREIGN DATA WRAPPER clickhouse_fdw
        OPTIONS (host 'localhost', port '8123');
    CREATE USER MAPPING FOR CURRENT_USER
        SERVER pgclickhouse_test_srv
        OPTIONS (user 'default', password '');
END $$;

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'pgclickhouse_test_srv')
    THEN 'PASS pg_clickhouse: CREATE SERVER via clickhouse_fdw succeeded'
    ELSE 'FAIL pg_clickhouse: CREATE SERVER via clickhouse_fdw failed'
END;

DROP SERVER IF EXISTS pgclickhouse_test_srv CASCADE;

-- 3. Bundled companion: the re2 extension (ClickHouse-compatible RE2 regex,
--    used for regex pushdown) loads and matches correctly.
CREATE EXTENSION IF NOT EXISTS re2;

SELECT CASE
    WHEN re2match('hello world', 'w.rld') IS TRUE
     AND re2match('hello world', '^x') IS FALSE
    THEN 'PASS pg_clickhouse: re2match regex evaluation works'
    ELSE 'FAIL pg_clickhouse: re2match regex evaluation broken'
END;

-- 4. re2 extraction returns the captured group.
SELECT CASE
    WHEN re2extract('2024-08-12', '([0-9]{4})') = '2024'
     AND re2countmatches('a1b2c3', '[0-9]') = 3
    THEN 'PASS pg_clickhouse: re2extract/re2countmatches work'
    ELSE 'FAIL pg_clickhouse: re2extract/re2countmatches broken'
END;

DROP EXTENSION IF EXISTS re2;
