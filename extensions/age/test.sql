-- Apache AGE integration tests
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Test: create a graph
SELECT CASE
    WHEN create_graph('test_graph') IS NOT NULL
    THEN 'PASS age: create_graph'
    ELSE 'FAIL age: create_graph'
END;

-- Test: create a vertex
SELECT * FROM cypher('test_graph', $$ CREATE (n:Person {name: 'Alice', age: 30}) RETURN n $$) AS (v agtype);
SELECT CASE
    WHEN (SELECT count(*) FROM cypher('test_graph', $$ MATCH (n:Person) RETURN n $$) AS (v agtype)) = 1
    THEN 'PASS age: create and query vertex'
    ELSE 'FAIL age: create and query vertex'
END;

-- Test: create an edge
SELECT * FROM cypher('test_graph', $$ CREATE (a:Person {name: 'Bob'})-[:KNOWS]->(b:Person {name: 'Alice'}) RETURN a $$) AS (v agtype);
SELECT CASE
    WHEN (SELECT count(*) FROM cypher('test_graph', $$ MATCH ()-[r:KNOWS]->() RETURN r $$) AS (e agtype)) >= 1
    THEN 'PASS age: create and query edge'
    ELSE 'FAIL age: create and query edge'
END;

-- Cleanup
SELECT drop_graph('test_graph', true);
