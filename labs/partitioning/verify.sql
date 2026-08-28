\set ON_ERROR_STOP on
CREATE TABLE metric_event(
  occurred_on date NOT NULL,
  source_id integer NOT NULL,
  value numeric NOT NULL,
  PRIMARY KEY (occurred_on, source_id)
) PARTITION BY RANGE (occurred_on);
CREATE TABLE metric_event_2026q1 PARTITION OF metric_event FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
CREATE TABLE metric_event_2026q2 PARTITION OF metric_event FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');
CREATE TABLE metric_event_default PARTITION OF metric_event DEFAULT;
INSERT INTO metric_event VALUES ('2026-02-01', 1, 10), ('2026-05-01', 1, 20), ('2027-01-01', 1, 30);

CREATE TEMP TABLE pruning_observation(pruned boolean);
DO $$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE $q$EXPLAIN (FORMAT JSON) SELECT * FROM metric_event WHERE occurred_on = DATE '2026-02-01'$q$ INTO plan;
  INSERT INTO pruning_observation VALUES (
    plan::text LIKE '%metric_event_2026q1%' AND
    plan::text NOT LIKE '%metric_event_2026q2%' AND
    plan::text NOT LIKE '%metric_event_default%'
  );
END $$;

SELECT json_build_object(
  'lab', 'partitioning',
  'server_version', current_setting('server_version'),
  'q1_rows', (SELECT count(*) FROM metric_event_2026q1),
  'q2_rows', (SELECT count(*) FROM metric_event_2026q2),
  'default_rows', (SELECT count(*) FROM metric_event_default),
  'partition_pruning', bool_and(pruned),
  'verdict', CASE WHEN bool_and(pruned) AND
    (SELECT count(*) FROM metric_event) = 3 THEN 'pass' ELSE 'fail' END
) FROM pruning_observation;
