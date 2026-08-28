\set ON_ERROR_STOP on
CREATE TABLE event_log (
  id bigint PRIMARY KEY,
  category integer NOT NULL,
  payload text NOT NULL
);
INSERT INTO event_log
SELECT g, g % 100, repeat(md5(g::text), 4)
FROM generate_series(1, 100000) AS g;
ANALYZE event_log;

DO $$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT payload FROM event_log WHERE id = 42424' INTO plan;
  IF plan::text !~ 'Index Scan|Index Only Scan' THEN
    RAISE EXCEPTION 'expected index plan: %', plan;
  END IF;
END $$;

SELECT json_build_object(
  'lab', 'planner',
  'server_version', current_setting('server_version'),
  'fixture_rows', count(*),
  'oracle_rows', count(*) FILTER (WHERE id = 42424),
  'verdict', CASE WHEN count(*) = 100000 AND count(*) FILTER (WHERE id = 42424) = 1 THEN 'pass' ELSE 'fail' END
) FROM event_log;
