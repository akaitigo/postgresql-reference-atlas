\set ON_ERROR_STOP on
CREATE TABLE migration_probe(
  id bigint PRIMARY KEY,
  tenant_id integer NOT NULL,
  amount integer NOT NULL
);
INSERT INTO migration_probe
SELECT g, (g % 100), CASE WHEN g = 1 THEN -1 ELSE (g % 1000) END
FROM generate_series(1, 50000) AS g;

ALTER TABLE migration_probe
  ADD CONSTRAINT migration_probe_amount_nonnegative CHECK (amount >= 0) NOT VALID;
CREATE TEMP TABLE migration_observation AS
SELECT NOT convalidated AS initially_not_valid
FROM pg_constraint
WHERE conname = 'migration_probe_amount_nonnegative';

UPDATE migration_probe SET amount = 0 WHERE amount < 0;
ALTER TABLE migration_probe VALIDATE CONSTRAINT migration_probe_amount_nonnegative;
CREATE INDEX CONCURRENTLY migration_probe_tenant_idx ON migration_probe(tenant_id, id);
ANALYZE migration_probe;

SELECT json_build_object(
  'lab', 'migration',
  'server_version', current_setting('server_version'),
  'rows_preserved', (SELECT count(*) FROM migration_probe),
  'initially_not_valid', initially_not_valid,
  'constraint_validated', (SELECT convalidated FROM pg_constraint WHERE conname = 'migration_probe_amount_nonnegative'),
  'index_valid', (SELECT indisvalid FROM pg_index WHERE indexrelid = 'migration_probe_tenant_idx'::regclass),
  'invalid_rows', (SELECT count(*) FROM migration_probe WHERE amount < 0),
  'verdict', CASE WHEN initially_not_valid
    AND (SELECT count(*) FROM migration_probe) = 50000
    AND (SELECT convalidated FROM pg_constraint WHERE conname = 'migration_probe_amount_nonnegative')
    AND (SELECT indisvalid FROM pg_index WHERE indexrelid = 'migration_probe_tenant_idx'::regclass)
    AND (SELECT count(*) FROM migration_probe WHERE amount < 0) = 0
    THEN 'pass' ELSE 'fail' END
) FROM migration_observation;
