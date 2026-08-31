#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
name="pgra-planner-$$"
artifact="$(mktemp)"
cleanup() { docker rm -f -v "$name" >/dev/null 2>&1 || true; rm -f "$artifact"; }
trap cleanup EXIT
docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
docker exec -i "$name" psql -X -qAt -U postgres -d atlas < "$ATLAS_ROOT/labs/planner/verify.sql" > "$artifact"
jq -e '.verdict == "pass" and .oracle_rows == 1' "$artifact" >/dev/null
record_evidence planner performance.planner benchmark container "make lab LAB=planner" "$artifact" pass
echo "Planner Labを通過しました"
