#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

suffix="$$"
primary="pgra-pitr-primary-$suffix"
restore="pgra-pitr-restore-$suffix"
primary_volume="pgra-pitr-primary-data-$suffix"
archive_volume="pgra-pitr-archive-$suffix"
backup_volume="pgra-pitr-backup-$suffix"
restore_volume="pgra-pitr-restore-data-$suffix"
artifact="$(mktemp)"

cleanup() {
  if [[ "${KEEP_LAB:-0}" != "1" ]]; then
    docker rm -f "$restore" "$primary" >/dev/null 2>&1 || true
    docker volume rm "$primary_volume" "$archive_volume" "$backup_volume" "$restore_volume" >/dev/null 2>&1 || true
  fi
  rm -f "$artifact"
}
trap cleanup EXIT

for volume in "$primary_volume" "$archive_volume" "$backup_volume" "$restore_volume"; do
  docker volume create "$volume" >/dev/null
done
docker run -d --name "$primary" \
  -v "$primary_volume:/var/lib/postgresql/data" -v "$archive_volume:/archive" -v "$backup_volume:/backup" \
  -e PGDATA=/var/lib/postgresql/data -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
  "$PG18_IMAGE" -c wal_level=replica -c archive_mode=on \
  -c "archive_command=test ! -f /archive/%f && cp %p /archive/%f" >/dev/null
wait_postgres "$primary"
docker exec "$primary" chown postgres:postgres /archive /backup
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE pitr_probe(id integer PRIMARY KEY, phase text NOT NULL); INSERT INTO pitr_probe VALUES (1, 'base-backup');"
docker exec --user postgres "$primary" pg_basebackup -U postgres -D /backup/base -Fp -X stream --checkpoint=fast
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "INSERT INTO pitr_probe VALUES (2, 'before-target');"
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "SELECT pg_create_restore_point('atlas_keep_point');"
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "INSERT INTO pitr_probe VALUES (3, 'after-target');"
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "SELECT pg_switch_wal();"

attempts=60
archived="0"
until archived="$(docker exec "$primary" psql -X -qAt -U postgres -d postgres -c 'SELECT archived_count FROM pg_stat_archiver')" && [[ "$archived" -gt 0 ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "WAL SegmentがArchiveされませんでした"
  sleep 1
done
docker stop "$primary" >/dev/null

docker run --rm -v "$backup_volume:/backup" -v "$restore_volume:/restore" "$PG18_IMAGE" sh -ceu \
  'cp -a /backup/base/. /restore/; touch /restore/recovery.signal; printf "%s\n" "restore_command = '\''cp /archive/%f %p'\''" "recovery_target_name = '\''atlas_keep_point'\''" "recovery_target_action = '\''promote'\''" >> /restore/postgresql.auto.conf; chown -R postgres:postgres /restore; chmod 700 /restore'
docker run -d --name "$restore" -v "$restore_volume:/var/lib/postgresql/data" -v "$archive_volume:/archive:ro" \
  -e PGDATA=/var/lib/postgresql/data -e POSTGRES_PASSWORD=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$restore"

attempts=60
in_recovery="t"
until in_recovery="$(docker exec "$restore" psql -X -qAt -U postgres -d atlas -c 'SELECT pg_is_in_recovery()')" && [[ "$in_recovery" == "f" ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "Restore ClusterがRecovery TargetでPromoteしませんでした"
  sleep 1
done
restored_ids="$(docker exec "$restore" psql -X -qAt -U postgres -d atlas -c "SELECT string_agg(id::text, ',' ORDER BY id) FROM pitr_probe")"
after_target_rows="$(docker exec "$restore" psql -X -qAt -U postgres -d atlas -c 'SELECT count(*) FROM pitr_probe WHERE id = 3')"

jq -n --arg version "$(docker exec "$restore" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')" \
  --arg restored_ids "$restored_ids" --arg in_recovery "$in_recovery" --argjson archived_segments "$archived" \
  --argjson after_target_rows "$after_target_rows" \
  '{lab:"pitr",server_version:$version,recovery_target:"atlas_keep_point",restored_ids:$restored_ids,after_target_rows:$after_target_rows,in_recovery:$in_recovery,archived_segments:$archived_segments,verdict:(if $restored_ids == "1,2" and $after_target_rows == 0 and $in_recovery == "f" and $archived_segments > 0 then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence pitr operations.pitr-recovery recovery cluster "make lab LAB=pitr" "$artifact" pass
echo "Point-in-Time Recovery Labを通過しました"
