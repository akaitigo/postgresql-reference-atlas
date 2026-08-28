\set ON_ERROR_STOP on
CREATE EXTENSION dblink;
CREATE TABLE wallet(id integer PRIMARY KEY, balance integer NOT NULL);
INSERT INTO wallet VALUES (1, 100);

\o /dev/null
SELECT dblink_connect('reader', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_connect('writer', 'dbname=atlas user=postgres password=atlas');
SELECT dblink_exec('reader', 'BEGIN ISOLATION LEVEL REPEATABLE READ');

CREATE TEMP TABLE observations(stage text PRIMARY KEY, value integer);
INSERT INTO observations
SELECT 'reader_before', value
FROM dblink('reader', 'SELECT balance FROM wallet WHERE id = 1') AS t(value integer);

SELECT dblink_exec('writer', 'UPDATE wallet SET balance = 150 WHERE id = 1');

INSERT INTO observations
SELECT 'reader_during', value
FROM dblink('reader', 'SELECT balance FROM wallet WHERE id = 1') AS t(value integer);
SELECT dblink_exec('reader', 'COMMIT');

INSERT INTO observations
SELECT 'reader_after', value
FROM dblink('reader', 'SELECT balance FROM wallet WHERE id = 1') AS t(value integer);

\o
SELECT json_build_object(
  'lab', 'mvcc',
  'server_version', current_setting('server_version'),
  'reader_before', max(value) FILTER (WHERE stage = 'reader_before'),
  'reader_during', max(value) FILTER (WHERE stage = 'reader_during'),
  'reader_after', max(value) FILTER (WHERE stage = 'reader_after'),
  'verdict', CASE WHEN
    max(value) FILTER (WHERE stage = 'reader_before') = 100 AND
    max(value) FILTER (WHERE stage = 'reader_during') = 100 AND
    max(value) FILTER (WHERE stage = 'reader_after') = 150
  THEN 'pass' ELSE 'fail' END
) FROM observations;
