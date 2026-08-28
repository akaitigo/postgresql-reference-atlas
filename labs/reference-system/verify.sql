\set ON_ERROR_STOP on
CREATE EXTENSION dblink;
CREATE EXTENSION pg_stat_statements;

CREATE ROLE atlas_app LOGIN PASSWORD 'atlas-app' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE TABLE orders(
  tenant_id integer NOT NULL,
  order_id bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at date NOT NULL,
  status text NOT NULL CHECK (status IN ('open', 'paid', 'cancelled')),
  quantity integer NOT NULL CHECK (quantity > 0),
  unit_cents integer NOT NULL CHECK (unit_cents > 0),
  total_cents integer GENERATED ALWAYS AS (quantity * unit_cents) STORED,
  PRIMARY KEY (tenant_id, order_id, occurred_at)
) PARTITION BY RANGE (occurred_at);
CREATE TABLE orders_2026_01 PARTITION OF orders FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE orders_2026_02 PARTITION OF orders FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE INDEX orders_tenant_status_total_idx ON orders (tenant_id, status, total_cents);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_orders ON orders
  USING (tenant_id = current_setting('app.tenant_id')::integer)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::integer);
GRANT SELECT, INSERT, UPDATE ON orders TO atlas_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO atlas_app;

INSERT INTO orders(tenant_id, occurred_at, status, quantity, unit_cents)
SELECT tenant_id,
       CASE WHEN n <= 500 THEN DATE '2026-01-15' ELSE DATE '2026-02-15' END,
       CASE WHEN n % 3 = 0 THEN 'paid' ELSE 'open' END,
       1 + n % 5,
       100 + n
FROM generate_series(1, 1000) AS n
CROSS JOIN generate_series(1, 2) AS tenant_id;
ANALYZE orders;

CREATE FUNCTION explain_json(query_text text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  document jsonb;
BEGIN
  FOR document IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || query_text LOOP
    RETURN document;
  END LOOP;
  RAISE EXCEPTION 'EXPLAIN returned no rows';
END $$;

CREATE TEMP TABLE runtime_result(
  tenant_visible_rows integer,
  rls_denied boolean DEFAULT false,
  rls_sqlstate text,
  lock_refused boolean DEFAULT false,
  lock_sqlstate text,
  post_release_update boolean DEFAULT false,
  failure_rejected boolean DEFAULT false,
  failure_sqlstate text,
  recovery_inserted boolean DEFAULT false,
  migration_constraint_validated boolean DEFAULT false,
  wal_bytes_delta numeric,
  query_plan jsonb
);

\o /dev/null
SELECT dblink_connect(
  'tenant1',
  'host=127.0.0.1 dbname=atlas user=atlas_app password=atlas-app options=-capp.tenant_id=1'
);
INSERT INTO runtime_result(tenant_visible_rows)
SELECT visible_rows
FROM dblink('tenant1', 'SELECT count(*)::integer FROM orders') AS result(visible_rows integer);

DO $$
DECLARE
  observed_state text;
BEGIN
  BEGIN
    PERFORM dblink_exec(
      'tenant1',
      $query$INSERT INTO orders(tenant_id, occurred_at, status, quantity, unit_cents)
               VALUES (2, DATE '2026-02-20', 'open', 1, 500)$query$
    );
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    UPDATE runtime_result SET rls_denied = true, rls_sqlstate = observed_state;
  END;
END $$;

SELECT dblink_connect('locker', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_exec('locker', 'BEGIN');
CREATE TEMP TABLE held_lock AS
SELECT locked
FROM dblink(
  'locker',
  'SELECT 1 FROM orders WHERE tenant_id=1 AND order_id=1 AND occurred_at=DATE ''2026-01-15'' FOR UPDATE'
) AS result(locked integer);
DO $$
DECLARE
  observed_state text;
BEGIN
  BEGIN
    PERFORM 1 FROM orders
    WHERE tenant_id = 1 AND order_id = 1 AND occurred_at = DATE '2026-01-15'
    FOR UPDATE NOWAIT;
  EXCEPTION WHEN lock_not_available THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    UPDATE runtime_result SET lock_refused = true, lock_sqlstate = observed_state;
  END;
END $$;
SELECT dblink_exec('locker', 'COMMIT');
WITH changed AS (
  UPDATE orders SET status = 'paid'
  WHERE tenant_id = 1 AND order_id = 1 AND occurred_at = DATE '2026-01-15'
  RETURNING 1
)
UPDATE runtime_result SET post_release_update = EXISTS (SELECT 1 FROM changed);

DO $$
DECLARE
  observed_state text;
BEGIN
  BEGIN
    INSERT INTO orders(tenant_id, occurred_at, status, quantity, unit_cents)
    VALUES (1, DATE '2026-02-21', 'open', 0, 500);
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    UPDATE runtime_result SET failure_rejected = true, failure_sqlstate = observed_state;
  END;
END $$;

WITH recovered AS (
  INSERT INTO orders(tenant_id, occurred_at, status, quantity, unit_cents)
  VALUES (1, DATE '2026-02-21', 'open', 1, 500)
  RETURNING 1
)
UPDATE runtime_result SET recovery_inserted = EXISTS (SELECT 1 FROM recovered);

ALTER TABLE orders ADD CONSTRAINT orders_total_positive CHECK (total_cents > 0) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_total_positive;
UPDATE runtime_result
SET migration_constraint_validated = (
  SELECT convalidated
  FROM pg_constraint
  WHERE conrelid = 'orders'::regclass AND conname = 'orders_total_positive'
);

SET enable_seqscan = off;
UPDATE runtime_result
SET query_plan = explain_json(
  $$SELECT order_id, total_cents FROM orders
    WHERE tenant_id = 1 AND status = 'open' AND total_cents > 1000
    ORDER BY total_cents LIMIT 20$$
);
RESET enable_seqscan;

CREATE TEMP TABLE wal_before(lsn pg_lsn);
INSERT INTO wal_before VALUES (pg_current_wal_insert_lsn());
INSERT INTO orders(tenant_id, occurred_at, status, quantity, unit_cents)
VALUES (1, DATE '2026-02-20', 'paid', 3, 700);
UPDATE runtime_result
SET wal_bytes_delta = pg_wal_lsn_diff(pg_current_wal_insert_lsn(), (SELECT lsn FROM wal_before));

CREATE TEMP TABLE tenant_statement AS
SELECT total
FROM dblink('tenant1', 'SELECT sum(total_cents)::bigint FROM orders WHERE status = ''open''')
AS result(total bigint);
SELECT sum(total_cents) FROM orders WHERE tenant_id = 1 AND status = 'open';
CREATE TEMP TABLE statement_observation AS
SELECT coalesce(sum(calls), 0)::integer AS calls
FROM pg_stat_statements
WHERE query LIKE 'SELECT sum(total_cents)%FROM orders%';

CREATE TEMP TABLE scenario_results(
  ordinal integer PRIMARY KEY,
  scenario text UNIQUE NOT NULL,
  final_status text NOT NULL,
  oracle jsonb NOT NULL,
  artifact_pointers jsonb NOT NULL
);

INSERT INTO scenario_results
SELECT 1, 'normal',
       CASE WHEN tenant_visible_rows = 1000 THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('tenant_visible_rows', tenant_visible_rows, 'expected', 1000),
       '["/tenant_visible_rows", "/artifacts/sql"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 2, 'boundary',
       CASE WHEN (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass) = 2 THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('partition_count', (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass), 'expected', 2),
       '["/partition_count", "/artifacts/sql"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 3, 'rejection',
       CASE WHEN rls_denied AND rls_sqlstate = '42501' AND lock_refused AND lock_sqlstate = '55P03' THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('rls_sqlstate', rls_sqlstate, 'lock_sqlstate', lock_sqlstate),
       '["/rls", "/locking", "/artifacts/sql", "/artifacts/log"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 4, 'failure',
       CASE WHEN failure_rejected AND failure_sqlstate = '23514' THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('check_rejected', failure_rejected, 'sqlstate', failure_sqlstate),
       '["/failure", "/artifacts/sql", "/artifacts/log"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 5, 'recovery',
       CASE WHEN recovery_inserted AND post_release_update THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('valid_write_after_rejection', recovery_inserted, 'update_after_lock_release', post_release_update),
       '["/recovery", "/locking/post_release_update", "/artifacts/sql", "/artifacts/wal"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 6, 'migration',
       CASE WHEN migration_constraint_validated THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('not_valid_then_validated', migration_constraint_validated),
       '["/migration", "/artifacts/sql"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 7, 'operations',
       CASE WHEN (SELECT calls FROM statement_observation) >= 1 THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('pg_stat_statements_calls', (SELECT calls FROM statement_observation), 'minimum', 1),
       '["/statement_calls", "/artifacts/metric"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 8, 'security',
       CASE WHEN rls_denied AND rls_sqlstate = '42501' THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('cross_tenant_write_rejected', rls_denied, 'sqlstate', rls_sqlstate),
       '["/rls", "/artifacts/sql", "/artifacts/log"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 9, 'performance',
       CASE WHEN query_plan::text ~ 'Index' AND query_plan::text ~ 'Actual Rows' AND query_plan::text ~ 'Shared Hit Blocks' THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('index_observed', query_plan::text ~ 'Index', 'actual_rows_observed', query_plan::text ~ 'Actual Rows', 'buffers_observed', query_plan::text ~ 'Shared Hit Blocks'),
       '["/query_plan", "/artifacts/plan", "/artifacts/metric"]'::jsonb
FROM runtime_result
UNION ALL
SELECT 10, 'compatibility',
       CASE WHEN current_setting('server_version_num')::integer = 180006 AND :'client_version' LIKE '%18.6%' THEN 'passed' ELSE 'failed' END,
       jsonb_build_object('server_version_num', current_setting('server_version_num')::integer, 'client_version', :'client_version'),
       '["/identity/server", "/identity/client", "/identity/version", "/identity/runtime"]'::jsonb
FROM runtime_result;

\o
SELECT json_build_object(
  'schema_version', 2,
  'lab', 'reference-system',
  'server_version', current_setting('server_version'),
  'identity', json_build_object(
    'server', json_build_object(
      'product', 'PostgreSQL',
      'version', current_setting('server_version'),
      'version_num', current_setting('server_version_num')::integer
    ),
    'client', json_build_object('product', 'psql', 'version', :'client_version'),
    'version', json_build_object('contract', '18.6', 'server_num', 180006),
    'runtime', json_build_object('container_image', :'runtime_identity', 'database', current_database())
  ),
  'partition_count', (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass),
  'tenant_visible_rows', tenant_visible_rows,
  'rls', json_build_object('rejected', rls_denied, 'sqlstate', rls_sqlstate),
  'locking', json_build_object(
    'nowait_rejected', lock_refused,
    'sqlstate', lock_sqlstate,
    'post_release_update', post_release_update
  ),
  'failure', json_build_object('check_rejected', failure_rejected, 'sqlstate', failure_sqlstate),
  'recovery', json_build_object('valid_write_after_rejection', recovery_inserted),
  'migration', json_build_object('constraint_validated', migration_constraint_validated),
  'query_plan', query_plan,
  'plan_has_index', query_plan::text ~ 'Index',
  'plan_has_actual_rows', query_plan::text ~ 'Actual Rows',
  'plan_has_buffers', query_plan::text ~ 'Shared Hit Blocks',
  'wal_bytes_delta', wal_bytes_delta,
  'statement_calls', (SELECT calls FROM statement_observation),
  'counts', json_build_object(
    'total', (SELECT count(*) FROM scenario_results),
    'passed', (SELECT count(*) FROM scenario_results WHERE final_status = 'passed'),
    'failed', (SELECT count(*) FROM scenario_results WHERE final_status = 'failed')
  ),
  'scenario_results', (
    SELECT json_agg(row_to_json(scenario_results) ORDER BY ordinal)
    FROM scenario_results
  ),
  'artifacts', json_build_object(
    'sql', json_build_object('path', 'labs/reference-system/verify.sql', 'kind', 'executed-sql-harness'),
    'plan', json_build_object('pointer', '/query_plan', 'kind', 'explain-analyze-buffers-json'),
    'wal', json_build_object('pointer', '/wal_bytes_delta', 'kind', 'wal-lsn-delta'),
    'log', json_build_object('status', 'added-by-runner-after-server-log-capture'),
    'metric', json_build_object('pointers', json_build_array('/statement_calls', '/query_plan/0/Planning Time', '/query_plan/0/Execution Time'))
  ),
  'completion_limits', json_build_object(
    'integrated_success_counts_as_behavior_specific_proof', false,
    'requires_authority_atomic_binding', true,
    'authority_atomic_bindings', 0,
    'completion_eligible', false
  ),
  'verdict', CASE WHEN
    (SELECT count(*) FROM scenario_results) = 10 AND
    (SELECT count(*) FROM scenario_results WHERE final_status = 'passed') = 10 AND
    (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass) = 2 AND
    tenant_visible_rows = 1000 AND rls_denied AND rls_sqlstate = '42501' AND
    lock_refused AND lock_sqlstate = '55P03' AND post_release_update AND
    failure_rejected AND failure_sqlstate = '23514' AND recovery_inserted AND
    migration_constraint_validated AND
    query_plan::text ~ 'Index' AND query_plan::text ~ 'Actual Rows' AND
    query_plan::text ~ 'Shared Hit Blocks' AND wal_bytes_delta > 0 AND
    (SELECT calls FROM statement_observation) >= 1 AND
    current_setting('server_version_num')::integer = 180006 AND :'client_version' LIKE '%18.6%'
    THEN 'pass' ELSE 'fail' END
) FROM runtime_result;
