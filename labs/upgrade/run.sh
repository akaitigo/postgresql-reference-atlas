#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

suffix="$$"
network="pgra-upgrade-net-$suffix"
old="pgra-upgrade-old-$suffix"
new="pgra-upgrade-new-$suffix"
artifact="$(mktemp)"
dump_file="$ATLAS_ROOT/evidence/artifacts/upgrade-$suffix.dump"

cleanup() {
  if [[ "${KEEP_LAB:-0}" != "1" ]]; then
    docker rm -f "$old" "$new" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
  fi
  rm -f "$artifact" "$dump_file"
}
trap cleanup EXIT

mkdir -p "$ATLAS_ROOT/evidence/artifacts"
docker network create "$network" >/dev/null
docker run -d --name "$old" --network "$network" --network-alias old \
  -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG17_IMAGE" >/dev/null
docker run -d --name "$new" --network "$network" --network-alias new \
  -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$old"
wait_postgres "$new"

docker exec -i "$old" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas <<'SQL'
CREATE TABLE upgrade_fixture(id bigint PRIMARY KEY, value text NOT NULL, created_at timestamptz NOT NULL);
INSERT INTO upgrade_fixture
SELECT g, md5(g::text), timestamptz '2025-01-01 00:00:00+00' + g * interval '1 second'
FROM generate_series(1, 20000) AS g;
SQL

old_version="$(docker exec "$old" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')"
new_version="$(docker exec "$new" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')"
old_digest="$(docker exec "$old" psql -X -qAt -U postgres -d atlas -c "SELECT md5(string_agg(id::text || ':' || value || ':' || created_at, ',' ORDER BY id)) FROM upgrade_fixture")"

docker run --rm --network "$network" -e PGPASSWORD=atlas "$PG18_IMAGE" \
  pg_dump -h old -U postgres -d atlas -Fc > "$dump_file"
docker cp "$dump_file" "$new:/tmp/upgrade.dump"
docker exec "$new" pg_restore -U postgres -d atlas --exit-on-error /tmp/upgrade.dump
new_digest="$(docker exec "$new" psql -X -qAt -U postgres -d atlas -c "SELECT md5(string_agg(id::text || ':' || value || ':' || created_at, ',' ORDER BY id)) FROM upgrade_fixture")"

jq -n --arg old_version "$old_version" --arg new_version "$new_version" \
  --arg old_digest "$old_digest" --arg new_digest "$new_digest" \
  '{lab:"upgrade",old_version:$old_version,new_version:$new_version,old_digest:$old_digest,new_digest:$new_digest,verdict:(if ($old_version|startswith("17.11")) and ($new_version|startswith("18.6")) and $old_digest == $new_digest then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence upgrade lifecycle.upgrade migration cluster "make lab LAB=upgrade" "$artifact" pass
echo "Major Upgrade Labを通過しました"
