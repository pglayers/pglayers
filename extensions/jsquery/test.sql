-- jsquery integration tests.
CREATE EXTENSION IF NOT EXISTS jsquery;

-- Load/sanity
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'jsquery') = 1
    THEN 'PASS jsquery: extension loads'
    ELSE 'FAIL jsquery: extension loads'
END;

-- jsonb matches a jsquery predicate
SELECT CASE
    WHEN '{"a": 1, "b": "x"}'::jsonb @@ 'a = 1'::jsquery
    THEN 'PASS jsquery: jsonb matches predicate'
    ELSE 'FAIL jsquery: jsonb matches predicate'
END;

-- non-matching predicate is false
SELECT CASE
    WHEN NOT ('{"a": 2}'::jsonb @@ 'a = 1'::jsquery)
    THEN 'PASS jsquery: non-matching predicate is false'
    ELSE 'FAIL jsquery: non-matching predicate is false'
END;

-- nested path match
SELECT CASE
    WHEN '{"a": {"b": 3}}'::jsonb @@ 'a.b = 3'::jsquery
    THEN 'PASS jsquery: nested path match'
    ELSE 'FAIL jsquery: nested path match'
END;
