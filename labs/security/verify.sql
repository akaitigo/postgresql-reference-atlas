\set ON_ERROR_STOP on
CREATE EXTENSION dblink;
CREATE ROLE tenant_app LOGIN PASSWORD 'tenant-atlas' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE TABLE tenant_record(tenant_id integer NOT NULL, id integer NOT NULL, secret text NOT NULL, PRIMARY KEY (tenant_id, id));
ALTER TABLE tenant_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_record FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenant_record
  USING (tenant_id = current_setting('app.tenant_id')::integer)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::integer);
GRANT SELECT, INSERT ON tenant_record TO tenant_app;
INSERT INTO tenant_record VALUES (1, 1, 'tenant-one'), (2, 1, 'tenant-two');

CREATE FUNCTION secured_row_count() RETURNS bigint
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, public
AS 'SELECT count(*) FROM public.tenant_record';
REVOKE ALL ON FUNCTION secured_row_count() FROM PUBLIC;

\o /dev/null
SELECT dblink_connect('tenant1', 'dbname=atlas user=tenant_app password=tenant-atlas options=-capp.tenant_id=1');
\o
CREATE TEMP TABLE security_result(visible_rows integer, denied boolean, sqlstate text);
INSERT INTO security_result(visible_rows, denied)
SELECT visible_rows, false FROM dblink('tenant1', 'SELECT count(*)::integer FROM tenant_record') AS t(visible_rows integer);

DO $$
DECLARE
  observed_state text;
BEGIN
  BEGIN
    PERFORM dblink_exec('tenant1', $q$INSERT INTO tenant_record VALUES (2, 2, 'escape')$q$);
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
    UPDATE security_result SET denied = true, sqlstate = observed_state;
  END;
END $$;

SELECT json_build_object(
  'lab', 'security',
  'server_version', current_setting('server_version'),
  'visible_rows', max(visible_rows),
  'tenant_escape_denied', bool_and(denied),
  'sqlstate', max(sqlstate),
  'password_encryption', current_setting('password_encryption'),
  'scram_verifier', (SELECT rolpassword LIKE 'SCRAM-SHA-256$%' FROM pg_authid WHERE rolname = 'tenant_app'),
  'host_scram_rule', (SELECT bool_or(auth_method = 'scram-sha-256') FROM pg_hba_file_rules WHERE type LIKE 'host%'),
  'fixed_search_path', (SELECT proconfig @> ARRAY['search_path=pg_catalog, public'] FROM pg_proc WHERE proname = 'secured_row_count'),
  'verdict', CASE WHEN max(visible_rows) = 1 AND bool_and(denied) AND max(sqlstate) = '42501' AND
    current_setting('password_encryption') = 'scram-sha-256' AND
    (SELECT rolpassword LIKE 'SCRAM-SHA-256$%' FROM pg_authid WHERE rolname = 'tenant_app') AND
    (SELECT bool_or(auth_method = 'scram-sha-256') FROM pg_hba_file_rules WHERE type LIKE 'host%') AND
    (SELECT proconfig @> ARRAY['search_path=pg_catalog, public'] FROM pg_proc WHERE proname = 'secured_row_count')
    THEN 'pass' ELSE 'fail' END
) FROM security_result;
