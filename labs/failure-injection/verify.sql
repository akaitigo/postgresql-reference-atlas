\set ON_ERROR_STOP on
CREATE EXTENSION dblink;
CREATE TABLE failure_probe(id integer PRIMARY KEY, note text NOT NULL);
\o /dev/null
SELECT dblink_connect('victim', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_exec('victim', 'BEGIN');
SELECT dblink_exec('victim', $$INSERT INTO failure_probe VALUES (1, 'must roll back')$$);
\o
CREATE TEMP TABLE failure_observation(victim_pid integer, terminated boolean);
INSERT INTO failure_observation(victim_pid)
SELECT pid FROM dblink('victim', 'SELECT pg_backend_pid()') AS t(pid integer);
UPDATE failure_observation
SET terminated = pg_terminate_backend(victim_pid);
INSERT INTO failure_probe VALUES (2, 'server remains writable');

SELECT json_build_object(
  'lab', 'failure-injection',
  'server_version', current_setting('server_version'),
  'victim_terminated', terminated,
  'uncommitted_row_count', (SELECT count(*) FROM failure_probe WHERE id = 1),
  'committed_row_count', (SELECT count(*) FROM failure_probe WHERE id = 2),
  'server_accepting_queries', (SELECT 1 = 1),
  'verdict', CASE WHEN terminated
    AND (SELECT count(*) FROM failure_probe WHERE id = 1) = 0
    AND (SELECT count(*) FROM failure_probe WHERE id = 2) = 1
    THEN 'pass' ELSE 'fail' END
) FROM failure_observation;
