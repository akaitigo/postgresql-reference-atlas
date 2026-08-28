#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib.sh"
require_command docker

tag="pgra-pg-upgrade:lab-$$"
artifact="$(mktemp)"
cleanup() {
  docker image rm "$tag" >/dev/null 2>&1 || true
  rm -f "$artifact"
}
trap cleanup EXIT

docker build -q -t "$tag" \
  --build-arg "PG17_IMAGE=$PG17_IMAGE" --build-arg "PG18_IMAGE=$PG18_IMAGE" \
  "$ATLAS_ROOT/labs/pg-upgrade" >/dev/null
docker run --rm --tmpfs /work:rw,exec,size=1g "$tag" > "$artifact"
jq -e '.verdict == "pass" and (.old_version | startswith("17.11")) and (.new_version | startswith("18.6")) and .rows == 50000 and .old_digest == .new_digest' "$artifact" >/dev/null
record_evidence pg-upgrade lifecycle.pg-upgrade migration cluster "make lab LAB=pg-upgrade" "$artifact" pass
echo "pg_upgrade Binary Upgrade Labを通過しました"
