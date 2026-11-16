-- pg_net integration tests
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Test: net schema exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_namespace WHERE nspname = 'net') = 1
    THEN 'PASS pg_net: net schema created'
    ELSE 'FAIL pg_net: net schema created'
END;

-- Test: http_get function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'net' AND p.proname = 'http_get') > 0
    THEN 'PASS pg_net: net.http_get function available'
    ELSE 'FAIL pg_net: net.http_get function available'
END;

-- Test: http_post function exists
SELECT CASE
    WHEN (SELECT count(*) FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'net' AND p.proname = 'http_post') > 0
    THEN 'PASS pg_net: net.http_post function available'
    ELSE 'FAIL pg_net: net.http_post function available'
END;

-- Exercise the background worker without relying on an external HTTP service.
-- Port 1 is closed in the test image, so libcurl must record a connection error
-- and remove the request from the queue. Enqueue outside the polling transaction
-- so the worker can see the committed row.
CREATE TEMP TABLE pg_net_worker_request AS
SELECT net.http_get('http://127.0.0.1:1/', timeout_milliseconds := 100) AS id;

DO $$
BEGIN
    FOR attempt IN 1..100 LOOP
        EXIT WHEN EXISTS (
            SELECT 1 FROM net._http_response
            WHERE id = (SELECT id FROM pg_net_worker_request)
        );
        PERFORM pg_sleep(0.1);
    END LOOP;
END $$;

SELECT CASE
    WHEN EXISTS (
        SELECT 1 FROM net._http_response
        WHERE id = (SELECT id FROM pg_net_worker_request)
          AND coalesce(error_msg, '') <> ''
    ) AND NOT EXISTS (
        SELECT 1 FROM net.http_request_queue
        WHERE id = (SELECT id FROM pg_net_worker_request)
    )
    THEN 'PASS pg_net: worker processes queued requests and records connection errors'
    ELSE 'FAIL pg_net: worker did not process the queued request'
END;

DELETE FROM net._http_response WHERE id = (SELECT id FROM pg_net_worker_request);
DROP TABLE pg_net_worker_request;
