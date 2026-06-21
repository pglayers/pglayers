-- pgjwt integration tests
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pgjwt;

-- Test: sign a JWT with HS256
SELECT CASE
    WHEN sign('{"sub":"test","iat":1234567890}'::json, 'secret') IS NOT NULL
    THEN 'PASS pgjwt: sign function works'
    ELSE 'FAIL pgjwt: sign function works'
END;

-- Test: verify a signed JWT
SELECT CASE
    WHEN (verify(
        sign('{"sub":"test"}'::json, 'secret'),
        'secret'
    )).valid = true
    THEN 'PASS pgjwt: verify function validates signature'
    ELSE 'FAIL pgjwt: verify function validates signature'
END;

-- Test: sign with RS256 algorithm name accepted
SELECT CASE
    WHEN sign('{"sub":"test"}'::json, 'secret', 'HS384') IS NOT NULL
    THEN 'PASS pgjwt: HS384 algorithm supported'
    ELSE 'FAIL pgjwt: HS384 algorithm supported'
END;
