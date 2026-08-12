-- pg_clickhouse integration tests
--
-- pg_clickhouse is a Foreign Data Wrapper: real queries require a running
-- ClickHouse server, which isn't available in CI. These checks validate that
-- the extension loads, its FDW objects work, and its re2 regex-pushdown wiring
-- is correct -- all without a live ClickHouse backend (EXPLAIN without ANALYZE
-- never contacts the remote). The re2 functions themselves are covered by
-- extensions/pg_re2/test.sql.

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

-- 3. re2 regex pushdown wiring (the reason pg_clickhouse DEPENDS on re2).
--    pg_clickhouse's deparser must recognize functions/operators owned by the
--    're2' extension and translate them into ClickHouse's regex functions.
--    We assert that a re2 match (the '@~' operator) is pushed down as
--    ClickHouse `match(...)` in the generated Remote SQL. EXPLAIN (no ANALYZE)
--    builds the remote query WITHOUT contacting ClickHouse, so this is safe in
--    CI. This check proves the re2 companion is correctly connected; if re2
--    were absent, the '@~' operator wouldn't exist and pushdown wouldn't occur.
CREATE EXTENSION IF NOT EXISTS re2;

CREATE SERVER pgclickhouse_re2_srv
    FOREIGN DATA WRAPPER clickhouse_fdw
    OPTIONS (host 'localhost', port '9000');
CREATE USER MAPPING FOR CURRENT_USER
    SERVER pgclickhouse_re2_srv OPTIONS (user 'default', password '');
CREATE FOREIGN TABLE pgclickhouse_re2_ft (a text)
    SERVER pgclickhouse_re2_srv OPTIONS (table_name 'dummy');

CREATE OR REPLACE FUNCTION pg_temp.pgch_re2_pushdown() RETURNS boolean AS $$
DECLARE
    ln    text;
    found boolean := false;
BEGIN
    FOR ln IN
        EXECUTE $q$EXPLAIN (VERBOSE)
                   SELECT a FROM pgclickhouse_re2_ft WHERE a @~ 'foo.*bar'$q$
    LOOP
        IF ln LIKE '%match(a,%' THEN
            found := true;
        END IF;
    END LOOP;
    RETURN found;
END;
$$ LANGUAGE plpgsql;

SELECT CASE
    WHEN pg_temp.pgch_re2_pushdown()
    THEN 'PASS pg_clickhouse: re2 regex pushed down to ClickHouse match() (re2 wired)'
    ELSE 'FAIL pg_clickhouse: re2 regex NOT pushed down (re2 not connected)'
END;

DROP FOREIGN TABLE IF EXISTS pgclickhouse_re2_ft;
DROP SERVER IF EXISTS pgclickhouse_re2_srv CASCADE;


