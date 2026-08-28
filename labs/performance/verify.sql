\set ON_ERROR_STOP on
CREATE TABLE performance_fact(id bigint PRIMARY KEY, tenant_id integer NOT NULL, payload text NOT NULL);
INSERT INTO performance_fact
SELECT g, g % 1000, repeat(md5(g::text), 2) FROM generate_series(1, 200000) AS g;
CREATE INDEX performance_fact_tenant_idx ON performance_fact(tenant_id) INCLUDE (id);
VACUUM (ANALYZE) performance_fact;

CREATE TEMP TABLE performance_observation(plan jsonb);
DO $$
DECLARE
  observed jsonb;
BEGIN
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) SELECT id FROM performance_fact WHERE tenant_id = 42 ORDER BY id' INTO observed;
  INSERT INTO performance_observation VALUES (observed);
END $$;

SELECT json_build_object(
  'lab', 'performance',
  'server_version', current_setting('server_version'),
  'fixture_rows', (SELECT count(*) FROM performance_fact),
  'result_rows', (SELECT count(*) FROM performance_fact WHERE tenant_id = 42),
  'index_bytes', pg_relation_size('performance_fact_tenant_idx'),
  'heap_bytes', pg_relation_size('performance_fact'),
  'plan_has_index', plan::text LIKE '%performance_fact_tenant_idx%',
  'plan_has_actual_rows', plan::text LIKE '%Actual Rows%',
  'plan_has_buffers', plan::text LIKE '%Shared Hit Blocks%',
  'verdict', CASE WHEN (SELECT count(*) FROM performance_fact WHERE tenant_id = 42) = 200 AND
    plan::text LIKE '%performance_fact_tenant_idx%' AND plan::text LIKE '%Actual Rows%' AND
    pg_relation_size('performance_fact_tenant_idx') > 0 THEN 'pass' ELSE 'fail' END
) FROM performance_observation;
