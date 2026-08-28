\set ON_ERROR_STOP on
CREATE EXTENSION pg_stat_statements;
CREATE TABLE observable_item(id bigint PRIMARY KEY, value integer NOT NULL);
INSERT INTO observable_item SELECT g, g % 10 FROM generate_series(1, 1000) AS g;
ANALYZE observable_item;
\o /dev/null
SELECT sum(value) FROM observable_item WHERE id BETWEEN 1 AND 100;
SELECT sum(value) FROM observable_item WHERE id BETWEEN 1 AND 100;
SELECT sum(value) FROM observable_item WHERE id BETWEEN 1 AND 100;
\o

SELECT json_build_object(
  'lab', 'observability',
  'server_version', current_setting('server_version'),
  'pg_stat_statements_loaded', EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'),
  'statement_calls', COALESCE((SELECT max(calls) FROM pg_stat_statements WHERE query LIKE 'SELECT sum(value) FROM observable_item%'), 0),
  'activity_visible', EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = pg_backend_pid()),
  'database_stats', EXISTS (SELECT 1 FROM pg_stat_database WHERE datname = current_database()),
  'table_stats', EXISTS (SELECT 1 FROM pg_stat_user_tables WHERE relname = 'observable_item'),
  'lock_stats', EXISTS (SELECT 1 FROM pg_locks WHERE pid = pg_backend_pid()),
  'wal_stats', EXISTS (SELECT 1 FROM pg_stat_wal),
  'verdict', CASE WHEN
    EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') AND
    COALESCE((SELECT max(calls) FROM pg_stat_statements WHERE query LIKE 'SELECT sum(value) FROM observable_item%'), 0) >= 3 AND
    EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = pg_backend_pid()) AND
    EXISTS (SELECT 1 FROM pg_stat_wal)
  THEN 'pass' ELSE 'fail' END
);
