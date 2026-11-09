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
    WHEN (SELECT valid AND payload->>'sub' = 'test' FROM verify(
        sign('{"sub":"test"}'::json, 'secret'),
        'secret'
    ))
    THEN 'PASS pgjwt: verify function validates signature'
    ELSE 'FAIL pgjwt: verify function validates signature'
END;

-- Test: HS384 signatures can also be verified
SELECT CASE
    WHEN (SELECT valid FROM verify(
        sign('{"sub":"test"}'::json, 'secret', 'HS384'), 'secret', 'HS384'
    ))
    THEN 'PASS pgjwt: HS384 algorithm supported'
    ELSE 'FAIL pgjwt: HS384 algorithm supported'
END;

-- Test: a different key must not validate the signature
SELECT CASE
    WHEN (SELECT NOT valid FROM verify(
        sign('{"sub":"test"}'::json, 'secret'), 'wrong-key'
    ))
    THEN 'PASS pgjwt: wrong signing key rejected'
    ELSE 'FAIL pgjwt: wrong signing key rejected'
END;
