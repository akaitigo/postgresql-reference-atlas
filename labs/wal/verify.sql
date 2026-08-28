\set ON_ERROR_STOP on
CREATE TABLE wal_probe(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, payload text NOT NULL);
CREATE TEMP TABLE wal_observation(start_lsn pg_lsn, end_lsn pg_lsn, switched_lsn pg_lsn);
INSERT INTO wal_observation(start_lsn) SELECT pg_current_wal_insert_lsn();
INSERT INTO wal_probe(payload)
SELECT repeat(md5(g::text), 8) FROM generate_series(1, 20000) AS g;
UPDATE wal_observation SET end_lsn = pg_current_wal_insert_lsn();
UPDATE wal_observation SET switched_lsn = pg_switch_wal();

SELECT json_build_object(
  'lab', 'wal',
  'server_version', current_setting('server_version'),
  'wal_level', current_setting('wal_level'),
  'rows_written', (SELECT count(*) FROM wal_probe),
  'wal_bytes_delta', pg_wal_lsn_diff(end_lsn, start_lsn),
  'segment_switched', switched_lsn >= end_lsn,
  'wal_records_observed', (SELECT wal_records > 0 FROM pg_stat_wal),
  'verdict', CASE WHEN (SELECT count(*) FROM wal_probe) = 20000
    AND pg_wal_lsn_diff(end_lsn, start_lsn) > 0
    AND switched_lsn >= end_lsn
    AND (SELECT wal_records > 0 FROM pg_stat_wal)
    THEN 'pass' ELSE 'fail' END
) FROM wal_observation;
