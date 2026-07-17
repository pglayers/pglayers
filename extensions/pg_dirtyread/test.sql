-- pg_dirtyread (read dead-but-unvacuumed tuples) tests.
CREATE EXTENSION IF NOT EXISTS pg_dirtyread;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_dirtyread')=1
    THEN 'PASS pg_dirtyread: extension loads' ELSE 'FAIL pg_dirtyread: extension loads' END;

-- a deleted (not yet vacuumed) row is still visible via pg_dirtyread
CREATE TABLE dirtyread_test (id int);
INSERT INTO dirtyread_test VALUES (1),(2);
DELETE FROM dirtyread_test WHERE id = 2;
SELECT CASE WHEN (SELECT count(*) FROM pg_dirtyread('dirtyread_test') AS t(id int)) = 2
    THEN 'PASS pg_dirtyread: sees the deleted tuple' ELSE 'FAIL pg_dirtyread: sees the deleted tuple' END;
DROP TABLE dirtyread_test;
