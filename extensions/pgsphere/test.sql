-- pgsphere (pg_sphere) integration tests.
CREATE EXTENSION IF NOT EXISTS pg_sphere;

-- Load/sanity
SELECT CASE
    WHEN (SELECT count(*) FROM pg_extension WHERE extname = 'pg_sphere') = 1
    THEN 'PASS pgsphere: extension loads'
    ELSE 'FAIL pgsphere: extension loads'
END;

-- spherical distance between two points 90 degrees apart is pi/2 radians
SELECT CASE
    WHEN abs((spoint '(0d,0d)' <-> spoint '(90d,0d)') - pi()/2) < 1e-9
    THEN 'PASS pgsphere: spherical distance of 90deg = pi/2'
    ELSE 'FAIL pgsphere: spherical distance of 90deg = pi/2'
END;

-- a spherical point can be stored and round-tripped
SELECT CASE
    WHEN (spoint '(0d,0d)') = (spoint '(0d,0d)')
    THEN 'PASS pgsphere: spoint equality'
    ELSE 'FAIL pgsphere: spoint equality'
END;
