#!/usr/bin/env sh
set -eu

old_bindir=/opt/postgresql/17/bin
new_bindir=/usr/local/bin
old_data=/work/old
new_data=/work/new
mkdir -p "$old_data" "$new_data"
chown -R postgres:postgres /work

gosu postgres "$old_bindir/initdb" -D "$old_data" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/security-init-old.log
gosu postgres "$old_bindir/pg_ctl" -D "$old_data" -o "-k /tmp -p 5517 -c listen_addresses='' -c log_statement=all" -w start >/tmp/security-start-old.log
gosu postgres "$old_bindir/createdb" -h /tmp -p 5517 atlas
gosu postgres "$old_bindir/psql" -X -q -v ON_ERROR_STOP=1 -h /tmp -p 5517 -d atlas <<'SQL'
CREATE ROLE atlas_upgrade_tenant LOGIN PASSWORD 'atlas-scenario-only-password';
CREATE TABLE secure_upgrade_rows(tenant name NOT NULL, payload text NOT NULL);
ALTER TABLE secure_upgrade_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY secure_upgrade_tenant_policy ON secure_upgrade_rows USING (tenant = current_user);
GRANT SELECT ON secure_upgrade_rows TO atlas_upgrade_tenant;
INSERT INTO secure_upgrade_rows VALUES ('atlas_upgrade_tenant', 'visible'), ('postgres', 'hidden');
SQL
old_version="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5517 -d postgres -c 'SHOW server_version')"
old_client_version="$(gosu postgres "$old_bindir/psql" --version | awk '{print $3}')"
old_password_encryption="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5517 -d postgres -c 'SHOW password_encryption')"
old_verifier_digest="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5517 -d postgres -c "SELECT md5(rolpassword) FROM pg_authid WHERE rolname = 'atlas_upgrade_tenant'")"
old_lsn="$(gosu postgres "$old_bindir/psql" -X -qAt -h /tmp -p 5517 -d postgres -c 'SELECT pg_current_wal_lsn()')"
gosu postgres "$old_bindir/pg_ctl" -D "$old_data" -m fast -w stop >/tmp/security-stop-old.log

gosu postgres "$new_bindir/initdb" -D "$new_data" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/security-init-new.log
cd /work
gosu postgres "$new_bindir/pg_upgrade" --old-bindir="$old_bindir" --new-bindir="$new_bindir" \
  --old-datadir="$old_data" --new-datadir="$new_data" --socketdir=/tmp --check >&2
gosu postgres "$new_bindir/pg_upgrade" --old-bindir="$old_bindir" --new-bindir="$new_bindir" \
  --old-datadir="$old_data" --new-datadir="$new_data" --socketdir=/tmp >&2
gosu postgres "$new_bindir/pg_ctl" -D "$new_data" -o "-k /tmp -p 5518 -c listen_addresses='' -c log_statement=all" -w start >/tmp/security-start-new.log

new_version="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d postgres -c 'SHOW server_version')"
new_client_version="$(gosu postgres "$new_bindir/psql" --version | awk '{print $3}')"
new_password_encryption="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d postgres -c 'SHOW password_encryption')"
new_verifier_digest="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d postgres -c "SELECT md5(rolpassword) FROM pg_authid WHERE rolname = 'atlas_upgrade_tenant'")"
visible_rows="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d atlas -c 'SET ROLE atlas_upgrade_tenant; SELECT count(*) FROM secure_upgrade_rows')"
select_acl="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d atlas -c "SELECT has_table_privilege('atlas_upgrade_tenant', 'secure_upgrade_rows', 'SELECT')")"
rls_enabled="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d atlas -c "SELECT relrowsecurity FROM pg_class WHERE oid = 'secure_upgrade_rows'::regclass")"
denied_output="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d atlas 2>&1 <<'SQL'
SET ROLE atlas_upgrade_tenant;
DO $$ BEGIN
  UPDATE secure_upgrade_rows SET payload = 'forged';
  RAISE EXCEPTION 'update unexpectedly allowed';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ATLAS_SECURITY_PASS:lifecycle.pg-upgrade';
END $$;
SQL
)"
printf '%s\n' "$denied_output" | grep -q 'ATLAS_SECURITY_PASS:lifecycle.pg-upgrade'
plan_base64="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d atlas -c "SET ROLE atlas_upgrade_tenant; EXPLAIN (FORMAT JSON) SELECT payload FROM secure_upgrade_rows WHERE tenant = current_user" | base64 | tr -d '\n')"
new_lsn="$(gosu postgres "$new_bindir/psql" -X -qAt -h /tmp -p 5518 -d postgres -c 'SELECT pg_current_wal_lsn()')"
gosu postgres "$new_bindir/pg_ctl" -D "$new_data" -m fast -w stop >/tmp/security-stop-new.log

verdict=fail
if [ "$old_version" = 17.11 ] && [ "$new_version" = 18.6 ] && \
   [ "$old_password_encryption" = scram-sha-256 ] && [ "$new_password_encryption" = scram-sha-256 ] && \
   [ "$old_verifier_digest" = "$new_verifier_digest" ] && [ "$visible_rows" = 1 ] && \
   [ "$select_acl" = t ] && [ "$rls_enabled" = t ]; then
  verdict=pass
fi

printf '{"old_version":"%s","new_version":"%s","old_client_version":"%s","new_client_version":"%s","password_encryption":"%s","verifier_digest_preserved":%s,"visible_rows":%s,"select_acl":"%s","rls_enabled":"%s","update_denied":true,"old_lsn":"%s","new_lsn":"%s","plan_base64":"%s","verdict":"%s"}\n' \
  "$old_version" "$new_version" "$old_client_version" "$new_client_version" "$new_password_encryption" \
  "$( [ "$old_verifier_digest" = "$new_verifier_digest" ] && printf true || printf false )" \
  "$visible_rows" "$select_acl" "$rls_enabled" "$old_lsn" "$new_lsn" "$plan_base64" "$verdict"
[ "$verdict" = pass ]
