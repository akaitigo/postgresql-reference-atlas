#!/usr/bin/env sh
set -eu

primary=/work/primary
standby=/work/standby
primary_port=5550
standby_port=5551
mkdir -p "$primary" "$standby"
chown -R postgres:postgres /work

gosu postgres initdb -D "$primary" --no-locale --encoding=UTF8 --auth=trust --data-checksums >/tmp/replication-security-init.log
if ! gosu postgres pg_ctl -D "$primary" -l /tmp/replication-security-primary.log \
  -o "-k /tmp -p $primary_port -c listen_addresses='' -c wal_level=replica -c max_wal_senders=5 -c max_replication_slots=5 -c log_statement=all" \
  -w start >/tmp/replication-security-start.log; then
  cat /tmp/replication-security-primary.log >&2
  exit 1
fi
gosu postgres createdb -h /tmp -p "$primary_port" atlas
gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$primary_port" -d atlas <<'SQL'
CREATE ROLE atlas_replication_reader;
CREATE ROLE atlas_physical_replicator WITH LOGIN REPLICATION;
CREATE TABLE atlas_replication_secure(id integer PRIMARY KEY, tenant name NOT NULL, payload text NOT NULL);
ALTER TABLE atlas_replication_secure ENABLE ROW LEVEL SECURITY;
CREATE POLICY atlas_replication_policy ON atlas_replication_secure USING (tenant = current_user);
GRANT SELECT ON atlas_replication_secure TO atlas_replication_reader;
INSERT INTO atlas_replication_secure VALUES
  (1, 'atlas_replication_reader', 'visible'),
  (2, 'postgres', 'hidden');
SQL
gosu postgres pg_basebackup -h /tmp -p "$primary_port" -U atlas_physical_replicator -D "$standby" -R -X stream -C -S atlas_security_slot
chmod 700 "$standby"
if ! gosu postgres pg_ctl -D "$standby" -l /tmp/replication-security-standby.log \
  -o "-k /tmp -p $standby_port -c listen_addresses='' -c hot_standby=on -c log_statement=all" \
  -w start >/tmp/replication-security-standby-start.log; then
  cat /tmp/replication-security-standby.log >&2
  exit 1
fi

gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p "$primary_port" -d atlas \
  -c "INSERT INTO atlas_replication_secure VALUES (3, 'postgres', 'replayed-hidden')"
attempts=80
rows=0
while [ "$rows" -ne 3 ]; do
  rows="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d atlas -c 'SELECT count(*) FROM atlas_replication_secure' 2>/dev/null || printf 0)"
  attempts=$((attempts - 1))
  [ "$attempts" -gt 0 ] || { echo 'physical replication catch-up timeout' >&2; exit 1; }
  sleep 0.25
done

visible_rows="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d atlas -c 'SET ROLE atlas_replication_reader; SELECT count(*) FROM atlas_replication_secure')"
select_acl="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d atlas -c "SELECT has_table_privilege('atlas_replication_reader', 'atlas_replication_secure', 'SELECT')")"
rls_enabled="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d atlas -c "SELECT relrowsecurity FROM pg_class WHERE oid='atlas_replication_secure'::regclass")"
if denied_output="$(gosu postgres psql -X -qAt -v ON_ERROR_STOP=1 -h /tmp -p "$standby_port" -d atlas \
  -c "SET ROLE atlas_replication_reader; UPDATE atlas_replication_secure SET payload = 'forged'" 2>&1)"; then
  echo 'standby write unexpectedly allowed' >&2
  exit 1
fi
printf '%s\n' "$denied_output" | grep -Eq 'read-only transaction|cannot execute UPDATE'
plan_base64="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d atlas -c "SET ROLE atlas_replication_reader; EXPLAIN (FORMAT JSON) SELECT payload FROM atlas_replication_secure WHERE tenant=current_user" | base64 | tr -d '\n')"
in_recovery="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d postgres -c 'SELECT pg_is_in_recovery()')"
sender_state="$(gosu postgres psql -X -qAt -h /tmp -p "$primary_port" -d postgres -c "SELECT state FROM pg_stat_replication LIMIT 1")"
slot_active="$(gosu postgres psql -X -qAt -h /tmp -p "$primary_port" -d postgres -c "SELECT active FROM pg_replication_slots WHERE slot_name='atlas_security_slot'")"
primary_lsn="$(gosu postgres psql -X -qAt -h /tmp -p "$primary_port" -d postgres -c 'SELECT pg_current_wal_lsn()')"
replay_lsn="$(gosu postgres psql -X -qAt -h /tmp -p "$standby_port" -d postgres -c 'SELECT pg_last_wal_replay_lsn()')"
version="$(gosu postgres psql -X -qAt -h /tmp -p "$primary_port" -d postgres -c 'SHOW server_version')"
gosu postgres pg_ctl -D "$standby" -m fast -w stop >/tmp/replication-security-standby-stop.log
gosu postgres pg_ctl -D "$primary" -m fast -w stop >/tmp/replication-security-primary-stop.log

verdict=fail
if [ "$version" = 18.6 ] && [ "$visible_rows" = 1 ] && [ "$select_acl" = t ] && [ "$rls_enabled" = t ] && \
   [ "$in_recovery" = t ] && [ "$sender_state" = streaming ] && [ "$slot_active" = t ] && [ "$rows" -eq 3 ]; then
  verdict=pass
fi
printf '{"version":"%s","visible_rows":%s,"replicated_rows":%s,"select_acl":"%s","rls_enabled":"%s","write_denied":true,"in_recovery":"%s","sender_state":"%s","slot_active":"%s","primary_lsn":"%s","replay_lsn":"%s","plan_base64":"%s","verdict":"%s"}\n' \
  "$version" "$visible_rows" "$rows" "$select_acl" "$rls_enabled" "$in_recovery" "$sender_state" "$slot_active" "$primary_lsn" "$replay_lsn" "$plan_base64" "$verdict"
[ "$verdict" = pass ]
