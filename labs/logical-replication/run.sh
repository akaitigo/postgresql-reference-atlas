#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

suffix="$$"
network="pgra-logical-net-$suffix"
publisher="pgra-logical-publisher-$suffix"
subscriber="pgra-logical-subscriber-$suffix"
artifact="$(mktemp)"

cleanup() {
  if [[ "${KEEP_LAB:-0}" != "1" ]]; then
    docker rm -f "$subscriber" "$publisher" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
  fi
  rm -f "$artifact"
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$publisher" --network "$network" --network-alias publisher \
  -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
  "$PG18_IMAGE" -c wal_level=logical -c max_wal_senders=5 -c max_replication_slots=5 >/dev/null
docker run -d --name "$subscriber" --network "$network" --network-alias subscriber \
  -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$publisher"
wait_postgres "$subscriber"

docker exec "$publisher" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE logical_probe(id integer PRIMARY KEY, payload text NOT NULL); CREATE PUBLICATION atlas_publication FOR TABLE logical_probe;"
docker exec "$subscriber" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE logical_probe(id integer PRIMARY KEY, payload text NOT NULL);"
docker exec "$subscriber" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE SUBSCRIPTION atlas_subscription CONNECTION 'host=publisher dbname=atlas user=postgres password=atlas' PUBLICATION atlas_publication WITH (copy_data = true, create_slot = true, enabled = true);"
docker exec "$publisher" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "INSERT INTO logical_probe VALUES (1, 'logical-wal-applied');"

attempts=60
payload=""
until payload="$(docker exec "$subscriber" psql -X -qAt -U postgres -d atlas -c "SELECT payload FROM logical_probe WHERE id = 1" 2>/dev/null)" && [[ "$payload" == "logical-wal-applied" ]]; do
  attempts=$((attempts - 1))
  [[ "$attempts" -gt 0 ]] || die "Logical Subscriberが変更を適用しませんでした"
  sleep 1
done

slot_active="$(docker exec "$publisher" psql -X -qAt -U postgres -d atlas -c "SELECT active FROM pg_replication_slots WHERE slot_name = 'atlas_subscription'")"
worker_active="$(docker exec "$subscriber" psql -X -qAt -U postgres -d atlas -c "SELECT pid IS NOT NULL FROM pg_stat_subscription WHERE subname = 'atlas_subscription'")"
publication_tables="$(docker exec "$publisher" psql -X -qAt -U postgres -d atlas -c "SELECT count(*) FROM pg_publication_tables WHERE pubname = 'atlas_publication'")"

jq -n \
  --arg version "$(docker exec "$publisher" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')" \
  --arg payload "$payload" --arg slot_active "$slot_active" --arg worker_active "$worker_active" \
  --argjson publication_tables "$publication_tables" \
  '{lab:"logical-replication",server_version:$version,payload:$payload,slot_active:$slot_active,worker_active:$worker_active,publication_tables:$publication_tables,verdict:(if $payload == "logical-wal-applied" and $slot_active == "t" and $worker_active == "t" and $publication_tables == 1 then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence logical-replication operations.logical-replication recovery cluster "make lab LAB=logical-replication" "$artifact" pass
echo "Logical Replication Labを通過しました"
