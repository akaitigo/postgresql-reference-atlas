#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
name="pgra-index-$$"
artifact="$(mktemp)"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; rm -f "$artifact"; }
trap cleanup EXIT
docker run -d --name "$name" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas "$PG18_IMAGE" >/dev/null
wait_postgres "$name"
docker exec -i "$name" psql -X -qAt -U postgres -d atlas < "$ATLAS_ROOT/labs/index/verify.sql" > "$artifact"
jq -e '.verdict == "pass" and .digest_unchanged == true' "$artifact" >/dev/null
record_evidence index performance.index benchmark container "make lab LAB=index" "$artifact" pass
echo "Index Labを通過しました"
