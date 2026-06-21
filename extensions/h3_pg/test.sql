-- h3-pg integration tests
CREATE EXTENSION IF NOT EXISTS h3;

-- Test: lat/lng to H3 cell
SELECT CASE
    WHEN h3_lat_lng_to_cell('(48.8566, 2.3522)'::point, 7) IS NOT NULL
    THEN 'PASS h3_pg: lat_lng_to_cell'
    ELSE 'FAIL h3_pg: lat_lng_to_cell'
END;

-- Test: get resolution
SELECT CASE
    WHEN h3_get_resolution(h3_lat_lng_to_cell('(48.8566, 2.3522)'::point, 7)) = 7
    THEN 'PASS h3_pg: get_resolution'
    ELSE 'FAIL h3_pg: get_resolution'
END;

-- Test: cell to boundary
SELECT CASE
    WHEN h3_cell_to_boundary(h3_lat_lng_to_cell('(0, 0)'::point, 5)) IS NOT NULL
    THEN 'PASS h3_pg: cell_to_boundary'
    ELSE 'FAIL h3_pg: cell_to_boundary'
END;
