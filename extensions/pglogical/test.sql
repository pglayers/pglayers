-- pglogical integration tests
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Test: pglogical schema exists with expected functions
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'pglogical' AND p.proname = 'create_node') > 0
    THEN 'PASS pglogical: create_node function available'
    ELSE 'FAIL pglogical: create_node function available'
END;

-- Test: version function returns a value
SELECT CASE
    WHEN pglogical.pglogical_version() IS NOT NULL
    THEN 'PASS pglogical: version function returns value'
    ELSE 'FAIL pglogical: version function returns value'
END;

-- Test: replication set management functions exist
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'pglogical'
            AND p.proname IN ('create_replication_set',
                              'replication_set_add_table',
                              'replication_set_remove_table')) = 3
    THEN 'PASS pglogical: replication set functions available'
    ELSE 'FAIL pglogical: replication set functions available'
END;
