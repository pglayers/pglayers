-- pljs (JavaScript procedural language) tests.
CREATE EXTENSION IF NOT EXISTS pljs;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pljs')=1
    THEN 'PASS pljs: extension loads' ELSE 'FAIL pljs: extension loads' END;

-- define and call a JavaScript function
CREATE FUNCTION pljs_add(a int, b int) RETURNS int LANGUAGE pljs AS 'return a + b;';
SELECT CASE WHEN pljs_add(2, 3) = 5
    THEN 'PASS pljs: JS function returns computed value'
    ELSE 'FAIL pljs: JS function returns computed value' END;

-- JavaScript can process JSON arguments
CREATE FUNCTION pljs_len(t text) RETURNS int LANGUAGE pljs AS 'return t.length;';
SELECT CASE WHEN pljs_len('hello') = 5
    THEN 'PASS pljs: JS string handling' ELSE 'FAIL pljs: JS string handling' END;

DROP FUNCTION pljs_add(int,int);
DROP FUNCTION pljs_len(text);
