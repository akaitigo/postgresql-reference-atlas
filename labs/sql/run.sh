#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

name="pgra-sql-$$"
artifact="$(mktemp)"
cleanup() { docker rm -f -v "$name" >/dev/null 2>&1 || true; rm -f "$artifact"; }
trap cleanup EXIT

docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
docker exec -i "$name" psql -X -qAt -U postgres -d atlas < "$ATLAS_ROOT/labs/sql/verify.sql" > "$artifact"
jq -e '.verdict == "pass" and (.server_version | startswith("18.6"))' "$artifact" >/dev/null
record_evidence sql query.sql-surface test-report container "make lab LAB=sql" "$artifact" pass
echo "SQL Labを通過しました"
