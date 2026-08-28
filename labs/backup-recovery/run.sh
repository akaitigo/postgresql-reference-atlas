#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
name="pgra-backup-$$"
artifact="$(mktemp)"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -f "$artifact"; }
trap cleanup EXIT

docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
docker exec -i "$name" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas < "$ATLAS_ROOT/labs/backup-recovery/seed.sql"
source_digest="$(docker exec "$name" psql -X -qAt -U postgres -d atlas -c "SELECT md5(string_agg(id::text || ':' || account_id || ':' || amount || ':' || booked_at, ',' ORDER BY id)) FROM ledger_entry")"
source_rows="$(docker exec "$name" psql -X -qAt -U postgres -d atlas -c 'SELECT count(*) FROM ledger_entry')"
docker exec "$name" pg_dump -U postgres -d atlas -Fc -f /tmp/atlas.dump
docker exec "$name" createdb -U postgres atlas_restore
docker exec "$name" pg_restore -U postgres -d atlas_restore --exit-on-error /tmp/atlas.dump
restore_digest="$(docker exec "$name" psql -X -qAt -U postgres -d atlas_restore -c "SELECT md5(string_agg(id::text || ':' || account_id || ':' || amount || ':' || booked_at, ',' ORDER BY id)) FROM ledger_entry")"
restore_rows="$(docker exec "$name" psql -X -qAt -U postgres -d atlas_restore -c 'SELECT count(*) FROM ledger_entry')"

jq -n \
  --arg version "$(docker exec "$name" psql -X -qAt -U postgres -d postgres -c "SHOW server_version")" \
  --arg source_digest "$source_digest" \
  --arg restore_digest "$restore_digest" \
  --argjson source_rows "$source_rows" \
  --argjson restore_rows "$restore_rows" \
  '{lab:"backup-recovery",server_version:$version,source_digest:$source_digest,restore_digest:$restore_digest,source_rows:$source_rows,restore_rows:$restore_rows,verdict:(if $source_digest == $restore_digest and $source_rows == $restore_rows then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence backup-recovery operations.backup-recovery recovery container "make lab LAB=backup-recovery" "$artifact" pass
echo "Backup / Recovery Labを通過しました"
