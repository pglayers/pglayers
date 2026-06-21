-- pg_graphql integration tests
CREATE EXTENSION IF NOT EXISTS pg_graphql;

-- Test: graphql schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'graphql') = 1
    THEN 'PASS pg_graphql: graphql schema created'
    ELSE 'FAIL pg_graphql: graphql schema created'
END;

-- Test: resolve function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'graphql' AND p.proname = 'resolve') > 0
    THEN 'PASS pg_graphql: resolve function available'
    ELSE 'FAIL pg_graphql: resolve function available'
END;

-- Test: introspection query works
SELECT CASE
    WHEN graphql.resolve($$ { __typename } $$) IS NOT NULL
    THEN 'PASS pg_graphql: introspection query returns result'
    ELSE 'FAIL pg_graphql: introspection query returns result'
END;
