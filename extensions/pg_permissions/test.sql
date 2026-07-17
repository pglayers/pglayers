-- pg_permissions integration tests.
CREATE EXTENSION IF NOT EXISTS pg_permissions;

SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_permissions') = 1
    THEN 'PASS pg_permissions: extension loads'
    ELSE 'FAIL pg_permissions: extension loads'
END;

-- the table_permissions view reports existing grants
SELECT CASE
    WHEN (SELECT count(*) FROM table_permissions) > 0
    THEN 'PASS pg_permissions: table_permissions view returns grants'
    ELSE 'FAIL pg_permissions: table_permissions view returns grants'
END;

-- the aggregate all_permissions view is queryable
SELECT CASE
    WHEN (SELECT count(*) FROM all_permissions) >= 0
    THEN 'PASS pg_permissions: all_permissions view is queryable'
    ELSE 'FAIL pg_permissions: all_permissions view is queryable'
END;
