\set ON_ERROR_STOP on
CREATE TABLE correlated_fact(a integer NOT NULL, b integer NOT NULL, payload text NOT NULL);
INSERT INTO correlated_fact
SELECT g % 100, g % 100, md5(g::text) FROM generate_series(1, 10000) AS g;
CREATE STATISTICS correlated_fact_ab (dependencies, mcv) ON a, b FROM correlated_fact;
ANALYZE correlated_fact;

CREATE TEMP TABLE plan_observation(estimated_rows integer);
DO $$
DECLARE
  plan jsonb;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) SELECT * FROM correlated_fact WHERE a = 42 AND b = 42' INTO plan;
  INSERT INTO plan_observation VALUES ((plan #>> '{0,Plan,Plan Rows}')::integer);
END $$;

SELECT json_build_object(
  'lab', 'statistics',
  'server_version', current_setting('server_version'),
  'statistics_kinds', (SELECT stxkind FROM pg_statistic_ext WHERE stxname = 'correlated_fact_ab'),
  'estimated_rows', max(estimated_rows),
  'actual_rows', (SELECT count(*) FROM correlated_fact WHERE a = 42 AND b = 42),
  'verdict', CASE WHEN max(estimated_rows) BETWEEN 80 AND 120 AND
    (SELECT count(*) FROM correlated_fact WHERE a = 42 AND b = 42) = 100 THEN 'pass' ELSE 'fail' END
) FROM plan_observation;
