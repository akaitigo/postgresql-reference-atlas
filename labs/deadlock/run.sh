#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

name="pgra-deadlock-$$"
artifact="$(mktemp)"
session_a="$(mktemp)"
session_b="$(mktemp)"
cleanup() {
  docker rm -f -v "$name" >/dev/null 2>&1 || true
  rm -f "$artifact" "$session_a" "$session_b"
}
trap cleanup EXIT

docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
  "$PG18_IMAGE" -c deadlock_timeout=100ms >/dev/null
wait_postgres "$name"
docker exec "$name" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas \
  -c "CREATE TABLE deadlock_probe(id integer PRIMARY KEY, value integer NOT NULL); INSERT INTO deadlock_probe VALUES (1, 0), (2, 0);"

set +e
docker exec -i "$name" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas < "$ATLAS_ROOT/labs/deadlock/session-a.sql" >"$session_a" 2>&1 &
pid_a=$!
docker exec -i "$name" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d atlas < "$ATLAS_ROOT/labs/deadlock/session-b.sql" >"$session_b" 2>&1 &
pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

victims=0
rg -q '40P01' "$session_a" && victims=$((victims + 1))
rg -q '40P01' "$session_b" && victims=$((victims + 1))
value_sum="$(docker exec "$name" psql -X -qAt -U postgres -d atlas -c 'SELECT sum(value) FROM deadlock_probe')"
successes=0
[[ "$status_a" -eq 0 ]] && successes=$((successes + 1))
[[ "$status_b" -eq 0 ]] && successes=$((successes + 1))

jq -n --arg version "$(docker exec "$name" psql -X -qAt -U postgres -d postgres -c 'SHOW server_version')" \
  --argjson victims "$victims" --argjson successful_transactions "$successes" --argjson value_sum "$value_sum" \
  '{lab:"deadlock",server_version:$version,sqlstate:"40P01",deadlock_victims:$victims,successful_transactions:$successful_transactions,value_sum:$value_sum,verdict:(if $victims == 1 and $successful_transactions == 1 and $value_sum == 2 then "pass" else "fail" end)}' > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence deadlock concurrency.deadlock test-report container "make lab LAB=deadlock" "$artifact" pass
echo "Deadlock Detection Labを通過しました"
