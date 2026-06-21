-- pg_partman integration tests
CREATE EXTENSION IF NOT EXISTS pg_partman;

-- Test: create partitioned table and configure (v5+ API)
CREATE TABLE test_partman (id serial, created_at timestamp NOT NULL DEFAULT now()) PARTITION BY RANGE (created_at);

SELECT CASE
    WHEN create_parent('public.test_partman', 'created_at', '1 day') IS NOT NULL
    THEN 'PASS pg_partman: create_parent succeeded'
    ELSE 'FAIL pg_partman: create_parent succeeded'
END;

-- Test: partitions were created
SELECT CASE
    WHEN (SELECT count(*) FROM pg_inherits WHERE inhparent = 'test_partman'::regclass) > 0
    THEN 'PASS pg_partman: child partitions created'
    ELSE 'FAIL pg_partman: child partitions created'
END;

-- Test: config table has entry
SELECT CASE
    WHEN (SELECT count(*) FROM public.part_config WHERE parent_table = 'public.test_partman') = 1
    THEN 'PASS pg_partman: config entry exists'
    ELSE 'FAIL pg_partman: config entry exists'
END;

DROP TABLE test_partman CASCADE;
DELETE FROM public.part_config WHERE parent_table = 'public.test_partman';
