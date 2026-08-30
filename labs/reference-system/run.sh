#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/lib.sh"

require_command docker
require_command jq

name="pgra-reference-system-$$"
started_at_epoch="$(date +%s)"
raw_artifact="$(mktemp)"
final_artifact="$(mktemp)"
server_log="$(mktemp)"

cleanup() {
  docker rm -f -v "$name" >/dev/null 2>&1 || true
  rm -f "$raw_artifact" "$final_artifact" "$server_log"
}
trap cleanup EXIT

docker run -d --name "$name" \
  -e POSTGRES_PASSWORD=atlas \
  -e POSTGRES_DB=atlas \
  "$PG18_IMAGE" \
  -c shared_preload_libraries=pg_stat_statements >/dev/null
wait_postgres "$name"
wait_postgres_database "$name" atlas

client_version="$(docker exec "$name" psql --version)"
docker exec -i "$name" psql -X -qAt -v ON_ERROR_STOP=1 \
  -v client_version="$client_version" \
  -v runtime_identity="$PG18_IMAGE" \
  -U postgres -d atlas < "$ROOT/labs/reference-system/verify.sql" > "$raw_artifact"
docker logs "$name" > "$server_log" 2>&1

if rg -qi 'password[=:]' "$server_log"; then
  die "Reference SystemのServer LogにCredential表現を検出しました"
fi

mkdir -p "$ROOT/evidence/artifacts"
cp "$server_log" "$ROOT/evidence/artifacts/reference-system.server.log"
log_digest="$(sha256_file "$ROOT/evidence/artifacts/reference-system.server.log")"
log_size="$(wc -c < "$ROOT/evidence/artifacts/reference-system.server.log" | tr -d ' ')"
finished_at_epoch="$(date +%s)"
duration_ms="$(( (finished_at_epoch - started_at_epoch) * 1000 ))"
[[ "$duration_ms" -gt 0 ]] || duration_ms=1
jq --arg digest "sha256:$log_digest" --argjson bytes "$log_size" --argjson duration_ms "$duration_ms" \
  '.duration_ms = $duration_ms | .artifacts.log = {
    path: "evidence/artifacts/reference-system.server.log",
    digest: $digest,
    bytes: $bytes,
    stream: "postgres-server-stderr"
  }' "$raw_artifact" > "$final_artifact"

jq -e '
  .verdict == "pass" and
  (.identity.server.version | startswith("18.6")) and
  (.identity.client.version | contains("18.6")) and
  .counts.total == 10 and .counts.passed == 10 and .counts.failed == 0 and
  ([.scenario_results[].scenario] | unique | length) == 10 and
  (.scenario_results | all(.final_status == "passed")) and
  (.artifacts.log.bytes > 0)
' "$final_artifact" >/dev/null

record_evidence reference-system foundation.reference-system.runtime-slice test-report container \
  "make lab LAB=reference-system" "$final_artifact" pass
echo "reference-system Labを通過しました: 10/10 Scenario"
