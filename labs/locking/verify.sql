\set ON_ERROR_STOP on
CREATE EXTENSION dblink;
CREATE TABLE lock_probe(id integer PRIMARY KEY, value integer NOT NULL);
INSERT INTO lock_probe VALUES (1, 10);
\o /dev/null
SELECT dblink_connect('holder', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_connect('contender', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_exec('holder', 'BEGIN');
SELECT * FROM dblink('holder', 'SELECT id FROM lock_probe WHERE id = 1 FOR UPDATE') AS t(id integer);
\o

CREATE TEMP TABLE lock_result(sqlstate text, rejected boolean, system_view_lock boolean);
DO $$
DECLARE
  observed_state text;
BEGIN
  BEGIN
    PERFORM * FROM dblink('contender', 'SELECT id FROM lock_probe WHERE id = 1 FOR UPDATE NOWAIT') AS t(id integer);
    INSERT INTO lock_result VALUES (NULL, false, NULL);
  EXCEPTION WHEN lock_not_available THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    INSERT INTO lock_result VALUES (observed_state, true, NULL);
  END;
END $$;
UPDATE lock_result SET system_view_lock = EXISTS (
  SELECT 1
  FROM pg_locks
  WHERE pid = (SELECT pid FROM dblink('holder', 'SELECT pg_backend_pid()') AS t(pid integer))
    AND relation = 'lock_probe'::regclass
    AND granted
);
\o /dev/null
SELECT dblink_exec('holder', 'COMMIT');
SELECT dblink_exec('contender', 'UPDATE lock_probe SET value = 20 WHERE id = 1');
\o

SELECT json_build_object(
  'lab', 'locking',
  'server_version', current_setting('server_version'),
  'sqlstate', max(sqlstate),
  'rejected_while_locked', bool_and(rejected),
  'system_view_lock', bool_and(system_view_lock),
  'value_after_release', (SELECT value FROM lock_probe WHERE id = 1),
  'verdict', CASE WHEN bool_and(rejected) AND bool_and(system_view_lock) AND max(sqlstate) = '55P03' AND
    (SELECT value FROM lock_probe WHERE id = 1) = 20 THEN 'pass' ELSE 'fail' END
) FROM lock_result;
