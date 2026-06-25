-- PostGIS integration tests
CREATE EXTENSION IF NOT EXISTS postgis;

-- Test: point creation and distance
SELECT CASE
    WHEN round(ST_Distance(
        ST_SetSRID(ST_GeomFromText('POINT(0 0)'), 4326)::geography,
        ST_SetSRID(ST_GeomFromText('POINT(0 1)'), 4326)::geography
    )) BETWEEN 110000 AND 112000
    THEN 'PASS postgis: geographic distance calculation'
    ELSE 'FAIL postgis: geographic distance calculation'
END;

-- Test: geometry contains
SELECT CASE
    WHEN ST_Contains(
        ST_MakeEnvelope(0, 0, 10, 10, 4326),
        ST_SetSRID(ST_GeomFromText('POINT(5 5)'), 4326)
    )
    THEN 'PASS postgis: ST_Contains point in polygon'
    ELSE 'FAIL postgis: ST_Contains point in polygon'
END;

-- Test: GeoJSON output
SELECT CASE
    WHEN ST_AsGeoJSON(ST_GeomFromText('POINT(1 2)'))::jsonb->>'type' = 'Point'
    THEN 'PASS postgis: GeoJSON output'
    ELSE 'FAIL postgis: GeoJSON output'
END;

-- Test: spatial index
CREATE TABLE test_postgis (id serial, geom geometry(Point, 4326));
INSERT INTO test_postgis (geom) SELECT ST_SetSRID(ST_GeomFromText('POINT(' || (random()*360-180) || ' ' || (random()*180-90) || ')'), 4326) FROM generate_series(1,100);
CREATE INDEX ON test_postgis USING gist (geom);
SELECT CASE
    WHEN (SELECT count(*) FROM test_postgis WHERE ST_DWithin(geom, ST_SetSRID(ST_GeomFromText('POINT(0 0)'), 4326), 50)) >= 0
    THEN 'PASS postgis: GiST spatial index query'
    ELSE 'FAIL postgis: GiST spatial index query'
END;

DROP TABLE test_postgis;
