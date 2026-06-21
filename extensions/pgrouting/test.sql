-- pgrouting integration tests
-- Requires PostGIS to be loaded first
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;

-- Test: extension loaded
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pgrouting') = 1
    THEN 'PASS pgrouting: extension loaded'
    ELSE 'FAIL pgrouting: extension loaded'
END;

-- Test: pgr_dijkstra function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc WHERE proname = 'pgr_dijkstra') > 0
    THEN 'PASS pgrouting: pgr_dijkstra function available'
    ELSE 'FAIL pgrouting: pgr_dijkstra function available'
END;

-- Test: basic routing query
CREATE TABLE test_edges (id serial, source int, target int, cost float);
INSERT INTO test_edges (source, target, cost) VALUES
    (1, 2, 1.0), (2, 3, 2.0), (1, 3, 5.0);

SELECT CASE
    WHEN (SELECT count(*) FROM pgr_dijkstra(
        'SELECT id, source, target, cost FROM test_edges',
        1, 3)) > 0
    THEN 'PASS pgrouting: Dijkstra shortest path works'
    ELSE 'FAIL pgrouting: Dijkstra shortest path works'
END;

DROP TABLE test_edges;
