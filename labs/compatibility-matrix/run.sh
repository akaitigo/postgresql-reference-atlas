#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

images=(
  "postgres:14.24-alpine@sha256:727876d274666da0b92a445390ba093c84b8e9f8343e1c53cd4e9a7ab2d85310"
  "postgres:15.19-alpine3.23@sha256:b0dc4a8dc256b963ee25867843d9fd366850e327e4a2a65ccb3c47262d092973"
  "postgres:16.15-alpine3.23@sha256:421b84e07a72bb8f3715f20501a1fdbe1219aad1fa4af7786a49d9a3f2480296"
  "$PG17_IMAGE"
  "$PG18_IMAGE"
)
expected_versions=("14.24" "15.19" "16.15" "17.11" "18.6")
observations="$(mktemp)"
artifact="$(mktemp)"
current_container=""

cleanup() {
  [[ -z "$current_container" ]] || docker rm -f -v "$current_container" >/dev/null 2>&1 || true
  rm -f "$observations" "$artifact"
}
trap cleanup EXIT

for image in "${images[@]}"; do
  digest="${image##*@}"
  rg -q --fixed-strings "$digest" "$ATLAS_ROOT/sources.lock.yaml" \
    || die "Compatibility Imageがsources.lock.yamlへ未固定です: $image"
done

for index in "${!images[@]}"; do
  current_container="pgra-compat-${expected_versions[$index]//./-}-$$"
  docker run -d --name "$current_container" -e POSTGRES_PASSWORD=atlas -e POSTGRES_DB=atlas \
    "${images[$index]}" >/dev/null
  wait_postgres "$current_container"
  docker exec -i "$current_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d atlas \
    < "$ATLAS_ROOT/labs/compatibility-matrix/verify.sql" \
    | jq -c --arg image "${images[$index]}" '. + {image:$image}' >> "$observations"
  docker rm -f -v "$current_container" >/dev/null
  current_container=""
done

jq -s '
  {lab:"compatibility-matrix",observations:.,versions:(map(.server_version)),logical_digests:(map(.logical_digest)|unique),verdict:
    (if length == 5
      and map(.server_version) == ["14.24","15.19","16.15","17.11","18.6"]
      and all(.rows == 1000 and .password_encryption == "scram-sha-256")
      and (map(.logical_digest)|unique|length) == 1
      and (.[0:4] | all(.has_uuidv7 == false))
      and .[4].has_uuidv7 == true
    then "pass" else "fail" end)}' "$observations" > "$artifact"
jq -e '.verdict == "pass"' "$artifact" >/dev/null
record_evidence compatibility-matrix lifecycle.compatibility-matrix compatibility cluster \
  "make lab LAB=compatibility-matrix" "$artifact" pass
echo "PostgreSQL 14.24-18.6 Compatibility Matrix Labを通過しました"
