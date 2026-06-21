-- hypopg integration tests
CREATE EXTENSION IF NOT EXISTS hypopg;

CREATE TABLE test_hypopg (id serial, val int, name text);
INSERT INTO test_hypopg SELECT g, g, 'name_' || g FROM generate_series(1, 1000) g;
ANALYZE test_hypopg;

-- Test: create hypothetical index
SELECT CASE
    WHEN (SELECT indexrelid FROM hypopg_create_index('CREATE INDEX ON test_hypopg(val)')) > 0
    THEN 'PASS hypopg: hypothetical index created'
    ELSE 'FAIL hypopg: hypothetical index created'
END;

-- Test: hypothetical index is visible in hypopg
SELECT CASE
    WHEN (SELECT count(*) FROM hypopg() WHERE indexname LIKE '%val%') > 0
    THEN 'PASS hypopg: index visible via hypopg() function'
    ELSE 'FAIL hypopg: index visible via hypopg() function'
END;

-- Test: estimated size
SELECT CASE
    WHEN (SELECT hypopg_relation_size(indexrelid) FROM hypopg() LIMIT 1) > 0
    THEN 'PASS hypopg: hypothetical index has estimated size'
    ELSE 'FAIL hypopg: hypothetical index has estimated size'
END;

-- Cleanup
SELECT hypopg_reset();
DROP TABLE test_hypopg;
