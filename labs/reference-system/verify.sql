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

\o
SELECT json_build_object(
  'lab', 'reference-system',
  'server_version', current_setting('server_version'),
  'partition_count', (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass),
  'tenant_visible_rows', tenant_visible_rows,
  'rls', json_build_object('rejected', rls_denied, 'sqlstate', rls_sqlstate),
  'locking', json_build_object(
    'nowait_rejected', lock_refused,
    'sqlstate', lock_sqlstate,
    'post_release_update', post_release_update
  ),
  'query_plan', query_plan,
  'plan_has_index', query_plan::text ~ 'Index',
  'plan_has_actual_rows', query_plan::text ~ 'Actual Rows',
  'plan_has_buffers', query_plan::text ~ 'Shared Hit Blocks',
  'wal_bytes_delta', wal_bytes_delta,
  'statement_calls', (SELECT calls FROM statement_observation),
  'verdict', CASE WHEN
    (SELECT count(*) FROM pg_inherits WHERE inhparent = 'orders'::regclass) = 2 AND
    tenant_visible_rows = 1000 AND rls_denied AND rls_sqlstate = '42501' AND
    lock_refused AND lock_sqlstate = '55P03' AND post_release_update AND
    query_plan::text ~ 'Index' AND query_plan::text ~ 'Actual Rows' AND
    query_plan::text ~ 'Shared Hit Blocks' AND wal_bytes_delta > 0 AND
    (SELECT calls FROM statement_observation) >= 1
    THEN 'pass' ELSE 'fail' END
) FROM runtime_result;
