#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

suffix="$$"
network="pgra-repl-net-$suffix"
primary="pgra-repl-primary-$suffix"
standby="pgra-repl-standby-$suffix"
standby_volume="pgra-repl-standby-data-$suffix"
artifact="$(mktemp)"

cleanup() {
  if [[ "${KEEP_LAB:-0}" != "1" ]]; then
    docker rm -f "$standby" "$primary" >/dev/null 2>&1 || true
    docker volume rm "$standby_volume" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
  fi
  rm -f "$artifact"
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker volume create "$standby_volume" >/dev/null
docker run -d --name "$primary" --network "$network" --network-alias primary \
  -e PGDATA=/var/lib/postgresql/data -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
  "$PG18_IMAGE" -c wal_level=replica -c max_wal_senders=5 -c max_replication_slots=5 >/dev/null
wait_postgres "$primary"
docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica-atlas';"
docker exec "$primary" sh -ceu \
  "printf '%s\n' 'host replication replicator all scram-sha-256' >> /var/lib/postgresql/data/pg_hba.conf"
docker exec --user postgres "$primary" pg_ctl reload -D /var/lib/postgresql/data >/dev/null

docker run --rm --network "$network" -e PGPASSWORD=replica-atlas \
  -v "$standby_volume:/var/lib/postgresql/data" "$PG18_IMAGE" \
  sh -ceu 'chown -R postgres:postgres /var/lib/postgresql/data; rm -rf /var/lib/postgresql/data/*; gosu postgres pg_basebackup -h primary -U replicator -D /var/lib/postgresql/data -R -X stream -C -S atlas_slot; chmod 700 /var/lib/postgresql/data'

docker run -d --name "$standby" --network "$network" --network-alias standby \
  -v "$standby_volume:/var/lib/postgresql/data" -e PGDATA=/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$standby"

docker exec "$primary" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE replication_probe(id integer PRIMARY KEY, payload text NOT NULL); INSERT INTO replication_probe VALUES (1, 'wal-replayed');"

attempts=60
replicated=""
until replicated="$(docker exec "$standby" psql -X -qAt -U postgres -d atlas -c "SELECT payload FROM replication_probe WHERE id = 1" 2>/dev/null)" && [[ "$replicated" == "wal-replayed" ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "StandbyがWALをReplayしませんでした"
  sleep 1
done

in_recovery="$(docker exec "$standby" psql -X -qAt -U postgres -d atlas -c 'SELECT pg_is_in_recovery()')"
sender_state="$(docker exec "$primary" psql -X -qAt -U postgres -d postgres -c "SELECT state FROM pg_stat_replication WHERE application_name = 'walreceiver' LIMIT 1")"

jq -n \
  --arg version "$(docker exec "$primary" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')" \
  --arg payload "$replicated" \
  --arg in_recovery "$in_recovery" \
  --arg sender_state "$sender_state" \
  '{lab:"replication",server_version:$version,payload:$payload,in_recovery:$in_recovery,sender_state:$sender_state,verdict:(if $payload == "wal-replayed" and $in_recovery == "t" and $sender_state == "streaming" then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence replication operations.replication recovery cluster "make lab LAB=replication" "$artifact" pass
echo "Physical Replication Labを通過しました"
