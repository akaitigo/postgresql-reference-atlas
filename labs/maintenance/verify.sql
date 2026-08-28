\set ON_ERROR_STOP on
CREATE TABLE maintenance_probe(id bigint PRIMARY KEY, payload text NOT NULL);
INSERT INTO maintenance_probe SELECT g, repeat(md5(g::text), 4) FROM generate_series(1, 100000) AS g;
DELETE FROM maintenance_probe WHERE id % 2 = 0;
SELECT pg_stat_force_next_flush();
CREATE TEMP TABLE maintenance_before AS
SELECT n_dead_tup AS dead_before FROM pg_stat_user_tables WHERE relname = 'maintenance_probe';
\o /dev/null
VACUUM (FREEZE, ANALYZE) maintenance_probe;
SELECT pg_stat_force_next_flush();
\o

SELECT json_build_object(
  'lab', 'maintenance',
  'server_version', current_setting('server_version'),
  'rows_after_delete', (SELECT count(*) FROM maintenance_probe),
  'dead_before', dead_before,
  'dead_after', (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'maintenance_probe'),
  'vacuum_count', (SELECT vacuum_count FROM pg_stat_user_tables WHERE relname = 'maintenance_probe'),
  'analyze_count', (SELECT analyze_count FROM pg_stat_user_tables WHERE relname = 'maintenance_probe'),
  'frozen_xid_age', (SELECT age(relfrozenxid) FROM pg_class WHERE oid = 'maintenance_probe'::regclass),
  'verdict', CASE WHEN (SELECT count(*) FROM maintenance_probe) = 50000
    AND dead_before > 0
    AND (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'maintenance_probe') = 0
    AND (SELECT vacuum_count FROM pg_stat_user_tables WHERE relname = 'maintenance_probe') >= 1
    AND (SELECT analyze_count FROM pg_stat_user_tables WHERE relname = 'maintenance_probe') >= 1
    THEN 'pass' ELSE 'fail' END
) FROM maintenance_before;
