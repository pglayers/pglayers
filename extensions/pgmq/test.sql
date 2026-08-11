-- pgmq integration tests
CREATE EXTENSION IF NOT EXISTS pgmq;

-- Test: extension loads and creates the pgmq schema (smoke test)
SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'pgmq')
    THEN 'PASS pgmq: extension loads and pgmq schema exists'
    ELSE 'FAIL pgmq: extension loads and pgmq schema exists'
END;

-- Test: create a queue and send a message, msg_id is returned
SELECT pgmq.create('test_queue');
SELECT CASE
    WHEN (SELECT pgmq.send('test_queue', '{"hello": "world"}')) >= 1
    THEN 'PASS pgmq: create queue and send returns a msg_id'
    ELSE 'FAIL pgmq: create queue and send returns a msg_id'
END;

-- Test: read the message back within a visibility timeout
SELECT CASE
    WHEN (SELECT message FROM pgmq.read('test_queue', 30, 1) LIMIT 1)
         = '{"hello": "world"}'::jsonb
    THEN 'PASS pgmq: read returns the enqueued message'
    ELSE 'FAIL pgmq: read returns the enqueued message'
END;

-- Test: archive moves the message out of the queue into the archive table.
-- Archive in its own statement so the verification below sees the committed
-- effect (mutating and reading in one statement would use a stale snapshot).
SELECT pgmq.archive('test_queue', msg_id) FROM pgmq.q_test_queue;
SELECT CASE
    WHEN (SELECT count(*) FROM pgmq.a_test_queue) = 1
     AND (SELECT count(*) FROM pgmq.q_test_queue) = 0
    THEN 'PASS pgmq: archive moves message to archive table'
    ELSE 'FAIL pgmq: archive moves message to archive table'
END;

-- Cleanup
SELECT pgmq.drop_queue('test_queue');
