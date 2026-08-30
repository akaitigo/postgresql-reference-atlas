#!/usr/bin/env sh
set -eu

primary=/work/primary
archive=/work/archive
backup=/work/backup
restore=/work/restore
port=5540
mkdir -p "$primary" "$archive" "$backup" "$restore"
chown -R postgres:postgres /work

gosu postgres initdb -D "$primary" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/pitr-security-init.log
gosu postgres pg_ctl -D "$primary" -l /tmp/pitr-security-primary.log \
  -o "-k /tmp -p $port -c listen_addresses='' -c wal_level=replica -c archive_mode=on -c archive_command='test ! -f $archive/%f && cp %p $archive/%f' -c log_statement=all" \
  -w start >/tmp/pitr-security-start.log
gosu postgres createdb -h /tmp -p "$port" atlas
gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$port" -d atlas <<'SQL'
CREATE ROLE atlas_pitr_reader;
CREATE TABLE atlas_pitr_secure(id integer PRIMARY KEY, tenant name NOT NULL, payload text NOT NULL);
ALTER TABLE atlas_pitr_secure ENABLE ROW LEVEL SECURITY;
CREATE POLICY atlas_pitr_policy ON atlas_pitr_secure USING (tenant = current_user);
GRANT SELECT ON atlas_pitr_secure TO atlas_pitr_reader;
INSERT INTO atlas_pitr_secure VALUES
  (1, 'atlas_pitr_reader', 'visible'),
  (2, 'postgres', 'hidden');
SQL
gosu postgres pg_basebackup -h /tmp -p "$port" -U postgres -D "$backup/base" -Fp -X stream --checkpoint=fast
gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$port" -d atlas -c "SELECT pg_create_restore_point('atlas_security_point')" >/dev/null
gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$port" -d atlas -c "INSERT INTO atlas_pitr_secure VALUES (3, 'atlas_pitr_reader', 'after-target')"
source_lsn="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d postgres -c 'SELECT pg_current_wal_lsn()')"
gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$port" -d postgres -c 'SELECT pg_switch_wal()' >/dev/null

attempts=80
archived=0
while [ "$archived" -le 0 ]; do
  archived="$(find "$archive" -type f | wc -l | tr -d ' ')"
  attempts=$((attempts - 1))
  [ "$attempts" -gt 0 ] || { echo 'PITR archive timeout' >&2; exit 1; }
  sleep 0.25
done
gosu postgres pg_ctl -D "$primary" -m fast -w stop >/tmp/pitr-security-stop.log

cp -a "$backup/base/." "$restore/"
touch "$restore/recovery.signal"
cat >>"$restore/postgresql.auto.conf" <<EOF
restore_command = 'cp $archive/%f %p'
recovery_target_name = 'atlas_security_point'
recovery_target_action = 'promote'
EOF
chown -R postgres:postgres "$restore"
chmod 700 "$restore"
gosu postgres pg_ctl -D "$restore" -l /tmp/pitr-security-restore.log \
  -o "-k /tmp -p $port -c listen_addresses='' -c log_statement=all" -w start >/tmp/pitr-security-restore-start.log

attempts=80
in_recovery=t
while [ "$in_recovery" != f ]; do
  in_recovery="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c 'SELECT pg_is_in_recovery()')"
  attempts=$((attempts - 1))
  [ "$attempts" -gt 0 ] || { echo 'PITR promotion timeout' >&2; exit 1; }
  sleep 0.25
done

visible_rows="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c 'SET ROLE atlas_pitr_reader; SELECT count(*) FROM atlas_pitr_secure')"
after_target_rows="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c 'SELECT count(*) FROM atlas_pitr_secure WHERE id = 3')"
select_acl="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c "SELECT has_table_privilege('atlas_pitr_reader', 'atlas_pitr_secure', 'SELECT')")"
rls_enabled="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c "SELECT relrowsecurity FROM pg_class WHERE oid='atlas_pitr_secure'::regclass")"
denied_output="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas 2>&1 <<'SQL'
SET ROLE atlas_pitr_reader;
DO $$ BEGIN
  UPDATE atlas_pitr_secure SET payload = 'forged';
  RAISE EXCEPTION 'update unexpectedly allowed';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ATLAS_SECURITY_PASS:operations.pitr-recovery';
END $$;
SQL
)"
printf '%s\n' "$denied_output" | grep -q 'ATLAS_SECURITY_PASS:operations.pitr-recovery'
plan_base64="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d atlas -c "SET ROLE atlas_pitr_reader; EXPLAIN (FORMAT JSON) SELECT payload FROM atlas_pitr_secure WHERE tenant=current_user" | base64 | tr -d '\n')"
restore_lsn="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d postgres -c 'SELECT pg_current_wal_lsn()')"
version="$(gosu postgres psql -X -qAt -h /tmp -p "$port" -d postgres -c 'SHOW server_version')"
gosu postgres pg_ctl -D "$restore" -m fast -w stop >/tmp/pitr-security-restore-stop.log

verdict=fail
if [ "$version" = 18.6 ] && [ "$visible_rows" = 1 ] && [ "$after_target_rows" = 0 ] && \
   [ "$select_acl" = t ] && [ "$rls_enabled" = t ] && [ "$in_recovery" = f ] && [ "$archived" -gt 0 ]; then
  verdict=pass
fi
printf '{"version":"%s","recovery_target":"atlas_security_point","visible_rows":%s,"after_target_rows":%s,"select_acl":"%s","rls_enabled":"%s","update_denied":true,"in_recovery":"%s","archived_segments":%s,"source_lsn":"%s","restore_lsn":"%s","plan_base64":"%s","verdict":"%s"}\n' \
  "$version" "$visible_rows" "$after_target_rows" "$select_acl" "$rls_enabled" "$in_recovery" "$archived" "$source_lsn" "$restore_lsn" "$plan_base64" "$verdict"
[ "$verdict" = pass ]
