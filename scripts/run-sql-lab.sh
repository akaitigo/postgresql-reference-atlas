#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

lab="${1:?lab is required}"
claim="${2:?claim is required}"
kind="${3:?kind is required}"
shift 3
name="pgra-${lab}-$$"
artifact="$(mktemp)"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -f "$artifact"
}
trap cleanup EXIT

if [[ "$#" -gt 0 ]]; then
  docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
    "$PG18_IMAGE" "$@" >/dev/null
else
  docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
    "$PG18_IMAGE" >/dev/null
fi
wait_postgres "$name"
wait_postgres_database "$name" atlas
docker exec -i "$name" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d atlas \
  < "$ROOT/labs/$lab/verify.sql" > "$artifact"
jq -e -s 'length == 1 and .[0].verdict == "pass" and (.[0].server_version | startswith("18.6"))' "$artifact" >/dev/null
record_evidence "$lab" "$claim" "$kind" container "make lab LAB=$lab" "$artifact" pass
echo "$lab Labを通過しました"
