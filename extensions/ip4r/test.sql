-- ip4r integration tests
CREATE EXTENSION IF NOT EXISTS ip4r;

-- Test: range containment
SELECT CASE
    WHEN '10.0.0.0/8'::ip4r >>= '10.1.2.3'::ip4
    THEN 'PASS ip4r: range contains address'
    ELSE 'FAIL ip4r: range contains address'
END;

-- Test: range overlap
SELECT CASE
    WHEN '192.168.0.0/16'::ip4r && '192.168.1.0/24'::ip4r
    THEN 'PASS ip4r: range overlap detection'
    ELSE 'FAIL ip4r: range overlap detection'
END;

-- Test: GiST index
CREATE TABLE test_ip4r (id serial, network ip4r);
INSERT INTO test_ip4r (network) VALUES ('10.0.0.0/24'), ('172.16.0.0/16'), ('192.168.1.0/24');
CREATE INDEX ON test_ip4r USING gist (network);
SELECT CASE
    WHEN (SELECT count(*) FROM test_ip4r WHERE network >>= '172.16.5.10') = 1
    THEN 'PASS ip4r: GiST index containment query'
    ELSE 'FAIL ip4r: GiST index containment query'
END;

DROP TABLE test_ip4r;
