#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

name="pgra-mvcc-$$"
artifact="$(mktemp)"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -f "$artifact"; }
trap cleanup EXIT

docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
docker exec -i "$name" psql -X -qAt -U postgres -d atlas < "$ATLAS_ROOT/labs/mvcc/verify.sql" > "$artifact"
jq -e '.verdict == "pass" and .reader_before == .reader_during and .reader_after == 150' "$artifact" >/dev/null
record_evidence mvcc concurrency.mvcc test-report container "make lab LAB=mvcc" "$artifact" pass
echo "MVCC Labを通過しました"
