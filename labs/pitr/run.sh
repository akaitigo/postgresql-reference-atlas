#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

node="pgra-pitr-tmpfs-$$"
artifact="$(mktemp)"

cleanup() {
  if [[ "${KEEP_LAB:-0}" != "1" ]]; then
    docker rm -f -v "$node" >/dev/null 2>&1 || true
  fi
  rm -f "$artifact"
}
trap cleanup EXIT

docker run -d --name "$node" --tmpfs /work:rw,size=384m "$PG18_IMAGE" \
  sh -ceu 'trap "exit 0" TERM INT; while :; do sleep 60; done' >/dev/null
docker exec "$node" sh -ceu 'mkdir -p /work/primary /work/archive /work/backup /work/restore; chown -R postgres:postgres /work'
docker exec --user postgres "$node" initdb -D /work/primary -A trust -U postgres >/dev/null
docker exec --user postgres "$node" pg_ctl -D /work/primary \
  -o "-c listen_addresses='' -c wal_level=replica -c archive_mode=on -c archive_command='test ! -f /work/archive/%f && cp %p /work/archive/%f'" \
  -w start >/dev/null
docker exec --user postgres "$node" createdb -U postgres atlas
docker exec "$node" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE pitr_probe(id integer PRIMARY KEY, phase text NOT NULL); INSERT INTO pitr_probe VALUES (1, 'base-backup');"
docker exec --user postgres "$node" pg_basebackup -U postgres -D /work/backup/base -Fp -X stream --checkpoint=fast
docker exec "$node" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "INSERT INTO pitr_probe VALUES (2, 'before-target');"
docker exec "$node" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "SELECT pg_create_restore_point('atlas_keep_point');"
docker exec "$node" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "INSERT INTO pitr_probe VALUES (3, 'after-target');"
docker exec "$node" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "SELECT pg_switch_wal();"

attempts=60
archived="0"
until archived="$(docker exec "$node" psql -X -qAt -U postgres -d postgres -c 'SELECT archived_count FROM pg_stat_archiver')" && [[ "$archived" -gt 0 ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "WAL SegmentがArchiveされませんでした"
  sleep 1
done
docker exec --user postgres "$node" pg_ctl -D /work/primary -m fast -w stop >/dev/null
docker exec "$node" sh -ceu \
  'cp -a /work/backup/base/. /work/restore/; touch /work/restore/recovery.signal; printf "%s\n" "restore_command = '\''cp /work/archive/%f %p'\''" "recovery_target_name = '\''atlas_keep_point'\''" "recovery_target_action = '\''promote'\''" >> /work/restore/postgresql.auto.conf; chown -R postgres:postgres /work/restore; chmod 700 /work/restore'
docker exec --user postgres "$node" pg_ctl -D /work/restore -o "-c listen_addresses=''" -w start >/dev/null

attempts=60
in_recovery="t"
until in_recovery="$(docker exec "$node" psql -X -qAt -U postgres -d atlas -c 'SELECT pg_is_in_recovery()')" && [[ "$in_recovery" == "f" ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "Restore ClusterがRecovery TargetでPromoteしませんでした"
  sleep 1
done
restored_ids="$(docker exec "$node" psql -X -qAt -U postgres -d atlas -c "SELECT string_agg(id::text, ',' ORDER BY id) FROM pitr_probe")"
after_target_rows="$(docker exec "$node" psql -X -qAt -U postgres -d atlas -c 'SELECT count(*) FROM pitr_probe WHERE id = 3')"

jq -n --arg version "$(docker exec "$node" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')" \
  --arg restored_ids "$restored_ids" --arg in_recovery "$in_recovery" --argjson archived_segments "$archived" \
  --argjson after_target_rows "$after_target_rows" \
  '{lab:"pitr",server_version:$version,recovery_target:"atlas_keep_point",restored_ids:$restored_ids,after_target_rows:$after_target_rows,in_recovery:$in_recovery,archived_segments:$archived_segments,verdict:(if $restored_ids == "1,2" and $after_target_rows == 0 and $in_recovery == "f" and $archived_segments > 0 then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence pitr operations.pitr-recovery recovery cluster "make lab LAB=pitr" "$artifact" pass
echo "Point-in-Time Recovery Labを通過しました"
