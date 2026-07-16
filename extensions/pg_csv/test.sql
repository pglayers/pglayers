-- pg_csv (aggregate rows to CSV) tests.
CREATE EXTENSION IF NOT EXISTS pg_csv;

SELECT CASE WHEN (SELECT count(*) FROM pg_extension WHERE extname='pg_csv')=1
    THEN 'PASS pg_csv: extension loads' ELSE 'FAIL pg_csv: extension loads' END;

SELECT CASE WHEN (SELECT csv_agg(t) FROM (VALUES (1,'a'),(2,'b')) t(id,name)) LIKE '%1,a%2,b%'
    THEN 'PASS pg_csv: csv_agg renders rows as CSV' ELSE 'FAIL pg_csv: csv_agg renders rows as CSV' END;
