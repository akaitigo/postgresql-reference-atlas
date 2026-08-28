\set ON_ERROR_STOP on
\set VERBOSITY sqlstate
BEGIN;
UPDATE deadlock_probe SET value = value + 1 WHERE id = 1;
SELECT pg_sleep(2);
UPDATE deadlock_probe SET value = value + 1 WHERE id = 2;
COMMIT;
